#!/usr/bin/env bash
# System-wide DNS over HTTPS (DoH) on Nyarch / Arch, via dnscrypt-proxy
# + systemd-resolved.
#
# Why dnscrypt-proxy, not systemd-resolved alone:
# systemd-resolved does NOT support DoH natively (only DoT, DNSOverTLS).
# So the chain is: apps -> systemd-resolved (127.0.0.53) -> dnscrypt-proxy
# (127.0.0.1:53) -> upstream DoH over https://.../dns-query (port 443).
# DoH only hides the DNS query contents from the network/ISP. It does NOT
# hide the destination IP / SNI of the connections themselves; for that
# you need a VPN / Tor, not DoH.
#
# The DoH URL you give is turned into a DNS stamp (sdns://...) for
# dnscrypt-proxy's [static] section. Stamp format (dnscrypt.info):
#   sdns:// base64url( 0x02 || props LE64 || LP(addr) || 0x00 ||
#                       LP(hostname[:port]) || LP(path) )
# where LP(x) = 1-byte length + bytes, 0x00 = no pinned cert hashes,
# props = 1 (DNSSEC only). NoLog / NoFilter are NOT claimed here because
# for an arbitrary URL we do not know the provider's logging/filtering
# policy; require_nolog / require_nofilter stay false for the same reason.
# The stamp generator in this script is pure bash + base64, no python.
# Verified against the published stamps:
#   cloudflare-dns.com / 1.1.1.1 -> sdns://AgMAAAAAAAAABzEuMS4xLjEAEmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5
#   dns9.quad9.net / 9.9.9.9      -> sdns://AgMAAAAAAAAABzkuOS45LjkADmRuczkucXVhZDkubmV0Ci9kbnMtcXVlcnk
#
# Bootstrap chicken-and-egg: to open the first HTTPS connection to the
# DoH hostname, its IP must be resolved somehow. The stamp deliberately
# carries an EMPTY addr (unlike the published stamps above, which bake
# in 1.1.1.1 / 9.9.9.9): baking one IP at install time freezes it, and
# a stale / hijacked answer at install time would break DoH afterwards.
# Instead dnscrypt-proxy resolves the hostname at runtime through
# fallback_resolver (1.1.1.1:53, plain DNS, bootstrap only -- all real
# queries still go over DoH).
#
# Usage:
#   chmod +x install-doh.sh
#   ./install-doh.sh https://dns.cloudflare.com/dns-query
#   ./install-doh.sh https://dns.nextdns.io/<your-id>   # NextDNS, no /dns-query suffix
#   ./install-doh.sh cloudflare|quad9|google|adguard   # preset (name, not URL)
#   ./install-doh.sh                                    # prompt interactively
#   ./install-doh.sh --dry-run <url-or-preset>          # print config, change nothing
#   ./install-doh.sh --check                            # verify current setup
#   ./install-doh.sh --uninstall                        # remove drop-in, stop proxy, restore DNS
#
# After a successful run, verify by hand too:
#   resolvectl status            # DNS server should be 127.0.0.1
#   resolvectl query archlinux.org
#   journalctl -u dnscrypt-proxy -f   # look for: [NOTICE] [...] OK (DoH)
#
# Rollback: the script backs up /etc/dnscrypt-proxy/dnscrypt-proxy.toml
# (if it existed) to <file>.bak-<timestamp> and prints the path. On a
# failed verification it restores the backups automatically.
# This script does NOT touch Firefox/Helium DoH settings -- those are
# per-browser and independent; system DoH already covers the browser
# unless the browser is set to its own DoH resolver.
set -euo pipefail

TOML="/etc/dnscrypt-proxy/dnscrypt-proxy.toml"
DROPIN_DIR="/etc/systemd/resolved.conf.d"
DROPIN="$DROPIN_DIR/dnscrypt-proxy.conf"
SERVER_NAME="custom-doh"
FALLBACK_RESOLVER="1.1.1.1:53"

DRY_RUN=0
MODE="install"

usage() {
    sed -n '2,/^set -euo pipefail/p' "$0" | sed 's/^# \?//; s/^#$//'
    echo "Usage: $0 [https://<host>[:port]><path> | cloudflare|quad9|google|adguard] [--dry-run] [--check] [--uninstall]"
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "== $*"; }

# --- stamp generation (pure bash) -------------------------------------------
# make_stamp <host[:port]> <path> [addr] [props]
# Prints sdns://... ; props default 1 (DNSSEC).
make_stamp() {
    local host="$1" path="$2" addr="${3:-}" props="${4:-1}"
    local tmp
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    {
        printf '\x02'
        printf "\\x$(printf '%02x' "$props")\x00\x00\x00\x00\x00\x00\x00"
        printf "\\x$(printf '%02x' "${#addr}")%s" "$addr"
        printf '\x00'
        printf "\\x$(printf '%02x' "${#host}")%s" "$host"
        printf "\\x$(printf '%02x' "${#path}")%s" "$path"
    } > "$tmp"
    printf 'sdns://'
    base64 -w0 "$tmp" | tr '+/' '-_' | tr -d '='
    printf '\n'
}

# --- URL parsing ------------------------------------------------------------
# Sets HOSTPORT, HOST, PATH_OUT. Accepts a full https:// URL, a bare
# hostname (assumed https://<host>/dns-query), or a preset name.
parse_input() {
    local in="$1" url=""
    case "$in" in
        cloudflare) url="https://cloudflare-dns.com/dns-query" ;;
        quad9)      url="https://dns9.quad9.net/dns-query" ;;
        google)     url="https://dns.google/dns-query" ;;
        adguard)    url="https://dns.adguard.com/dns-query" ;;
        nextdns)    die "NextDNS needs your profile ID: pass the full URL, e.g. https://dns.nextdns.io/<id>" ;;
        https://*)  url="$in" ;;
        http://*)   die "DoH must be https://, not http://: $in" ;;
        *) # bare hostname, e.g. dns.cloudflare.com
            [[ "$in" =~ ^[A-Za-z0-9._-]+$ ]] || die "Not a URL, preset, or hostname: $in"
            url="https://$in/dns-query" ;;
    esac
    # Strip query string / fragment: DoH path carries no query.
    url="${url%%\?*}"; url="${url%%\#*}"
    # shellcheck disable=SC1003
    if [[ "$url" =~ ^https://([^/:]+)(:([0-9]+))?(/.*)?$ ]]; then
        HOST="${BASH_REMATCH[1]}"
        local port="${BASH_REMATCH[3]:-}"
        PATH_OUT="${BASH_REMATCH[4]:-/dns-query}"
        if [[ -n "$port" && "$port" != "443" ]]; then
            HOSTPORT="$HOST:$port"
        else
            HOSTPORT="$HOST"
        fi
    else
        die "Could not parse DoH URL: $url (expected https://<host>[:port]</path>)"
    fi
    [[ "$HOST" == *.* ]] || die "Hostname looks invalid (no dot): $HOST"
    # Host must not be a bare IP: DoH needs a hostname for TLS SNI.
    [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && die "DoH needs a hostname, not a bare IP: $HOST"
    [[ "${#HOST}" -lt 256 && "${#PATH_OUT}" -lt 256 ]] || die "Hostname/path too long for a DNS stamp (>255 bytes)"
    DOH_URL="$url"
}

# --- modes that need no install ---------------------------------------------
do_check() {
    echo "--- systemd-resolved ---"
    resolvectl status 2>&1 | head -30 || true
    echo "--- dnscrypt-proxy ---"
    systemctl is-active dnscrypt-proxy.service dnscrypt-proxy.socket 2>&1 || true
    systemctl status dnscrypt-proxy.service --no-pager -l 2>&1 | head -20 || true
    echo "--- live query via proxy (127.0.0.1) ---"
    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl query archlinux.org || echo "resolvectl query FAILED"
    fi
    if command -v dig >/dev/null 2>&1; then
        dig @127.0.0.1 archlinux.org +short +time=5 || echo "dig @127.0.0.1 FAILED"
    fi
    echo "--- recent proxy log (look for OK (DoH)) ---"
    journalctl -u dnscrypt-proxy --no-pager -n 15 2>&1 || true
}

do_uninstall() {
    info "Removing DoH drop-in and stopping dnscrypt-proxy"
    if [[ -f "$DROPIN" ]]; then
        sudo rm -f "$DROPIN"
        echo "Removed: $DROPIN"
    else
        echo "No drop-in found at $DROPIN, nothing to remove."
    fi
    sudo systemctl disable --now dnscrypt-proxy.service dnscrypt-proxy.socket 2>/dev/null || true
    sudo systemctl restart systemd-resolved
    echo "Done. System DNS is back to whatever NetworkManager / resolved had"
    echo "before (per-connection DNS). The dnscrypt-proxy config file is left"
    echo "in place at $TOML, disabled -- delete it by hand if you want it gone."
    resolvectl status 2>&1 | head -20 || true
}

# --- arg parsing ------------------------------------------------------------
INPUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --check) MODE="check"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --*) die "Unknown option: $1 (see --help)" ;;
        *) [[ -z "$INPUT" ]] || die "Only one URL/preset allowed, got both '$INPUT' and '$1'"; INPUT="$1"; shift ;;
    esac
done

if [[ "$MODE" == "check" ]]; then do_check; exit 0; fi
if [[ "$MODE" == "uninstall" ]]; then do_uninstall; exit 0; fi

if [[ -z "$INPUT" ]]; then
    if [[ -t 0 ]]; then
        echo "DoH URL (e.g. https://dns.cloudflare.com/dns-query)"
        echo "Presets: cloudflare | quad9 | google | adguard"
        echo "Leave empty for the Cloudflare default."
        read -rp "DoH URL or preset: " INPUT
        [[ -n "$INPUT" ]] || INPUT="cloudflare"
    else
        INPUT="cloudflare"
        echo "No input (not a terminal), using default preset: cloudflare"
    fi
fi

parse_input "$INPUT"
echo "DoH URL:  $DOH_URL"
echo "Host:     $HOSTPORT"
echo "Path:     $PATH_OUT"

# No IP is baked into the stamp (see header): dnscrypt-proxy resolves
# $HOST at runtime via fallback_resolver ($FALLBACK_RESOLVER).
STAMP="$(make_stamp "$HOSTPORT" "$PATH_OUT" "" 1)"
echo "Stamp:    $STAMP"

read -r -d '' TOML_CONTENT <<EOF || true
# Generated by install-doh.sh -- DoH: $DOH_URL
# Stamp props=1 (DNSSEC only); NoLog/NoFilter not claimed for an
# arbitrary URL. fallback_resolver is bootstrap-only; real queries
# go over DoH to the server below.
server_names = ['$SERVER_NAME']
listen_addresses = ['127.0.0.1:53']
ipv4_servers = true
ipv6_servers = false
dnscrypt_servers = true
doh_servers = true
require_dnssec = true
require_nolog = false
require_nofilter = false
fallback_resolver = '$FALLBACK_RESOLVER'

[static.'$SERVER_NAME']
  stamp = '$STAMP'
EOF

read -r -d '' DROPIN_CONTENT <<EOF || true
# Generated by install-doh.sh -- forward all DNS to dnscrypt-proxy (DoH).
# FallbackDNS is intentionally empty: fail closed instead of leaking
# plain DNS to the ISP if the proxy is down. Domains=~. routes every
# domain through 127.0.0.1 even when NetworkManager pushes per-link DNS.
[Resolve]
DNS=127.0.0.1
FallbackDNS=
Domains=~.
EOF

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "--- dry run: nothing written, nothing installed ---"
    echo "--- $TOML would be: ---"
    printf '%s\n' "$TOML_CONTENT"
    echo "--- $DROPIN would be: ---"
    printf '%s\n' "$DROPIN_CONTENT"
    echo "--- commands that would run: ---"
    echo "sudo pacman -S --needed dnscrypt-proxy"
    echo "sudo systemctl disable --now dnscrypt-proxy.socket"
    echo "sudo systemctl enable --now dnscrypt-proxy.service"
    echo "sudo systemctl restart systemd-resolved"
    exit 0
fi

# --- install (real run) -----------------------------------------------------
command -v pacman >/dev/null 2>&1 || die "pacman not found -- this script is for Arch-based systems (Nyarch)."
command -v systemctl >/dev/null 2>&1 || die "systemctl not found."
command -v base64 >/dev/null 2>&1 || die "base64 not found."
if ! systemctl is-active --quiet systemd-resolved; then
    info "systemd-resolved is not active -- enabling it (DoH is wired through it)"
    sudo systemctl enable --now systemd-resolved \
        || die "Could not start systemd-resolved."
fi

# Port conflict: something else already answering plain DNS on 127.0.0.1:53?
if command -v ss >/dev/null 2>&1 && ss -tuln 2>/dev/null | grep -q '127\.0\.0\.1:53'; then
    # dnscrypt-proxy itself counts as fine if it is already the listener.
    if ! systemctl is-active --quiet dnscrypt-proxy.service; then
        die "Something already listens on 127.0.0.1:53 (see: ss -tulnp | grep ':53'). Stop it first, or --uninstall a previous DoH setup."
    fi
fi

info "1. Installing dnscrypt-proxy"
sudo pacman -S --needed dnscrypt-proxy

# Backups (only if the files already exist).
BACKUP_TOML=""
if [[ -f "$TOML" ]]; then
    BACKUP_TOML="$TOML.bak-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$TOML" "$BACKUP_TOML"
    echo "Backed up: $TOML -> $BACKUP_TOML"
fi
BACKUP_DROPIN=""
if [[ -f "$DROPIN" ]]; then
    BACKUP_DROPIN="$DROPIN.bak-$(date +%Y%m%d-%H%M%S)"
    sudo cp "$DROPIN" "$BACKUP_DROPIN"
    echo "Backed up: $DROPIN -> $BACKUP_DROPIN"
fi

restore_backups() {
    echo "Restoring backups..."
    if [[ -n "$BACKUP_TOML" ]]; then sudo cp "$BACKUP_TOML" "$TOML";
    elif [[ -f "$TOML" ]]; then sudo rm -f "$TOML"; fi
    if [[ -n "$BACKUP_DROPIN" ]]; then sudo cp "$BACKUP_DROPIN" "$DROPIN";
    elif [[ -f "$DROPIN" ]]; then sudo rm -f "$DROPIN"; fi
    sudo systemctl restart systemd-resolved 2>/dev/null || true
    sudo systemctl disable --now dnscrypt-proxy.service 2>/dev/null || true
}

info "2. Writing dnscrypt-proxy config"
printf '%s\n' "$TOML_CONTENT" | sudo tee "$TOML" >/dev/null
sudo dnscrypt-proxy -config "$TOML" -check \
    || { echo "Config check FAILED -- see above."; restore_backups; exit 1; }

info "3. Pointing systemd-resolved at dnscrypt-proxy"
sudo mkdir -p "$DROPIN_DIR"
printf '%s\n' "$DROPIN_CONTENT" | sudo tee "$DROPIN" >/dev/null

info "4. Starting services (socket activation OFF -- the service binds 127.0.0.1:53 itself)"
sudo systemctl disable --now dnscrypt-proxy.socket 2>/dev/null || true
sudo systemctl enable --now dnscrypt-proxy.service
sudo systemctl restart systemd-resolved
sleep 2

info "5. Verifying"
if ! resolvectl query archlinux.org >/dev/null 2>&1; then
    echo "Verification FAILED: resolvectl query archlinux.org did not resolve."
    journalctl -u dnscrypt-proxy --no-pager -n 30 >&2 || true
    restore_backups
    die "Rolled back to the previous DNS config. Check the log above, then re-run with --dry-run to inspect the generated stamp/config."
fi
resolvectl query archlinux.org
journalctl -u dnscrypt-proxy --no-pager -n 8 | grep -E 'OK \(DoH\)|ERROR|FATAL' || journalctl -u dnscrypt-proxy --no-pager -n 8 || true

echo
echo "Done. System-wide DoH is live:"
echo "  Upstream: $DOH_URL"
echo "  Chain:    apps -> systemd-resolved -> dnscrypt-proxy 127.0.0.1:53 -> DoH"
echo "  Check:    ./install-doh.sh --check"
echo "  Remove:   ./install-doh.sh --uninstall"
if [[ -n "$BACKUP_TOML" ]]; then echo "  Backup:   $BACKUP_TOML"; fi
