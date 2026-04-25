#!/usr/bin/env bash

# ========= CONFIGURATION =========
readonly VERSION="1.0.1"
readonly TEMP_DIR="$(mktemp -d)"
readonly WORDLIST="${WORDLIST:-/usr/share/wordlists/dirb/common.txt}"
readonly REPORT_DIR="reports"
readonly SUBS_FILE="${TEMP_DIR}/subs.txt"
readonly WAYBACK_FILE="${TEMP_DIR}/wayback_urls.txt"

# ========= COLORS =========
readonly B="\e[34m"
readonly G="\e[32m"
readonly R="\e[31m"
readonly Y="\e[33m"
readonly N="\e[0m"

# ========= STATE =========
NUCLEI_UPDATED=false

# ========= TRAP / CLEANUP =========
cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ========= LOGGING HELPERS =========
log_info()  { echo -e "${G}[+] $*${N}"; }
log_warn()  { echo -e "${Y}[!] $*${N}"; }
log_error() { echo -e "${R}[-] $*${N}"; }

# ========= VALIDATION HELPERS =========
validate_not_empty() {
    [[ -z "$1" ]] && { log_error "$2 cannot be empty"; return 1; }
    return 0
}

ensure_url() {
    local url="$1"
    [[ "$url" != http* ]] && url="http://$url"
    echo "$url"
}

ensure_file_exists() {
    [[ ! -f "$1" ]] && { log_error "File not found: $1"; return 1; }
    return 0
}

# ========= NETWORK HELPER =========
safe_curl() {
    curl -s --connect-timeout 10 --max-time 30 -L "$@"
}

# ========= AUTO INSTALL DEPENDENCIES =========
auto_install() {
    local -a pkgs=(curl dnsutils whois nmap jq mtr)
    local need_install=false

    for p in "${pkgs[@]}"; do
        if ! dpkg -s "$p" &>/dev/null; then
            need_install=true
            break
        fi
    done

    if ! command -v nuclei >/dev/null; then
        need_install=true
    fi

    [[ "$need_install" == "false" ]] && return 0

    log_info "Checking & installing missing dependencies..."

    sudo apt-get update -qq 2>/dev/null

    for p in "${pkgs[@]}"; do
        dpkg -s "$p" &>/dev/null || {
            echo "[+] Installing $p"
            sudo apt-get install -y -qq "$p" >/dev/null
        }
    done

    command -v nuclei >/dev/null || install_nuclei

    log_info "Dependencies ready."
}

install_nuclei() {
    echo "[+] Installing nuclei"

    local os arch download_url tmp_install_dir

    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *)             log_error "Unsupported architecture: $arch"; return 1 ;;
    esac

    case "$os" in
        linux)  os="linux" ;;
        darwin) os="darwin" ;;
        *)      log_error "Unsupported OS: $os"; return 1 ;;
    esac

    download_url="https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_${os}_${arch}.zip"
    tmp_install_dir="$(mktemp -d)"

    if ! wget -q --show-progress "$download_url" -O "${tmp_install_dir}/nuclei.zip" 2>&1; then
        log_error "Failed to download nuclei"
        rm -rf "$tmp_install_dir"
        return 1
    fi

    if ! unzip -o "${tmp_install_dir}/nuclei.zip" -d "$tmp_install_dir" >/dev/null 2>&1; then
        log_error "Failed to extract nuclei"
        rm -rf "$tmp_install_dir"
        return 1
    fi

    if [[ ! -f "${tmp_install_dir}/nuclei" ]]; then
        log_error "nuclei binary not found after extraction"
        rm -rf "$tmp_install_dir"
        return 1
    fi

    sudo mv "${tmp_install_dir}/nuclei" /usr/local/bin/
    sudo chmod +x /usr/local/bin/nuclei
    rm -rf "$tmp_install_dir"
}

update_nuclei_templates() {
    [[ "$NUCLEI_UPDATED" == "true" ]] && return

    command -v nuclei >/dev/null || return

    log_info "Updating nuclei templates..."
    nuclei -update-templates >/dev/null 2>&1

    NUCLEI_UPDATED=true
}

# ========= BANNER FUNCTION =========
banner() {
    clear
    echo -e "${B}
   ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗    ██████╗ ███████╗
  ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝   ██╔═══██╗██╔════╝
  ██║  ███╗███████║██║   ██║███████╗   ██║█████╗██║   ██║███████╗
  ██║   ██║██╔══██║██║   ██║╚════██║   ██║╚════╝██║   ██║╚════██║
  ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║      ╚██████╔╝███████║
   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝       ╚═════╝ ╚══════╝
  Ghost OSINT Scanner - Recon • Enum • Vuln • Report - version ${VERSION}
 ${N}"
}

pause() { read -rp "Press Enter to continue..."; }

# ========= CORE FUNCTIONS =========
dns_lookup() {
    read -rp "Target: " target
    validate_not_empty "$target" "Target" || return 1
    dig "$target" +trace ANY
}

whois_lookup() {
    read -rp "Target: " target
    validate_not_empty "$target" "Target" || return 1
    whois "$target"
}

http_headers() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    curl -I "$(ensure_url "$target")"
}

clickjack() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    local url
    url="$(ensure_url "$target")"
    
    if safe_curl -sI "$url" | grep -qi "x-frame-options"; then
        echo "Safe"
    else
        echo "Vulnerable"
    fi
}

robots() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    safe_curl "$(ensure_url "$target")/robots.txt"
}

ip_location() {
    read -rp "IP/Domain: " target
    validate_not_empty "$target" "Target" || return 1
    safe_curl "http://ip-api.com/json/${target}" | jq
}

trace_route() {
    read -rp "Target: " target
    validate_not_empty "$target" "Target" || return 1
    mtr -4 -rwc 1 "$target"
}

subdomain_enum() {
    local domain="${1:-}"

    if [[ -z "$domain" ]]; then
        read -rp "Domain: " domain
    fi

    validate_not_empty "$domain" "Domain" || return 1

    echo "[+] Enumerating subdomains..."

    local resp
    resp=$(safe_curl -H "User-Agent: recon" "https://crt.sh/?q=%25.${domain}&output=json")

    if [[ -z "$resp" ]] || ! echo "$resp" | grep -q "name_value"; then
        echo "[!] crt.sh returned non-JSON (rate limit?)"
        return 1
    fi

    echo "$resp" | jq -r '.[].name_value' 2>/dev/null \
        | sed 's/\*\.//g' \
        | sort -u | tee "$SUBS_FILE"
}

wayback_enum() {
    read -rp "Domain: " domain
    validate_not_empty "$domain" "Domain" || return 1

    safe_curl "https://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey" \
        | sort -u | tee "$WAYBACK_FILE"
}

takeover_check() {
    read -rp "Domain: " domain
    validate_not_empty "$domain" "Domain" || return 1

    echo "[+] Checking subdomain takeover..."

    subdomain_enum "$domain" >/dev/null || {
        echo "[!] Subdomain enumeration failed"
        return 1
    }

    ensure_file_exists "$SUBS_FILE" || return 1

    while read -r sub; do
        [[ -z "$sub" ]] && continue

        local cname ip resp
        cname=$(dig +short CNAME "$sub" | head -n1)
        ip=$(dig +short "$sub" | head -n1)

        [[ -z "$ip" ]] && echo "[NXDOMAIN] $sub"

        if echo "$cname" | grep -Eqi "github\.io|herokuapp\.com|amazonaws\.com|azurewebsites\.net|fastly\.net"; then
            echo "[CNAME Risk] $sub -> $cname"
        fi

        resp=$(safe_curl --max-time 5 "http://${sub}")
        if echo "$resp" | grep -Eqi "NoSuchBucket|There isn't a GitHub Pages site here|heroku"; then
            echo "[HTTP Takeover Pattern] $sub"
        fi
    done < "$SUBS_FILE"
}

dir_brute() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    local url
    url="$(ensure_url "$target")"

    ensure_file_exists "$WORDLIST" || {
        log_error "Wordlist not found: $WORDLIST"
        echo "[+] Install with: sudo apt install dirb"
        return 1
    }

    while read -r word; do
        [[ -z "$word" ]] && continue
        local code
        code=$(safe_curl -o /dev/null -w "%{http_code}" "${url}/${word}")
        [[ "$code" != "404" ]] && echo "${url}/${word} [${code}]"
    done < "$WORDLIST"
}

vuln_header_scan() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    local url headers
    url="$(ensure_url "$target")"
    headers=$(safe_curl -sI "$url")

    local -a security_headers=(
        "x-frame-options"
        "content-security-policy"
        "x-content-type-options"
        "strict-transport-security"
    )

    for header in "${security_headers[@]}"; do
        echo "$headers" | grep -qi "$header" || echo "Missing $header"
    done
}

ssl_check() {
    read -rp "Domain: " domain
    validate_not_empty "$domain" "Domain" || return 1
    echo | openssl s_client -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -dates -issuer -subject
}

nuclei_scan() {
    read -rp "URL: " target
    validate_not_empty "$target" "URL" || return 1
    update_nuclei_templates
    nuclei -u "$(ensure_url "$target")"
}

nuclei_cve_scan() {
    read -rp "URL/Domain: " target
    validate_not_empty "$target" "Target" || return 1

    echo "[+] Running CVE-only scan (nuclei)..."
    update_nuclei_templates
    nuclei -u "$target" -tags cve -severity critical,high,medium
}

focused_web_vuln_scan() {
    read -rp "URL/Domain: " target
    validate_not_empty "$target" "Target" || return 1

    update_nuclei_templates
    log_info "Running focused web vulnerability scan..."

    echo -e "\n==== CSRF ===="
    nuclei -u "$target" -tags csrf

    echo -e "\n==== Open Redirect ===="
    nuclei -u "$target" -tags redirect

    echo -e "\n==== SSRF ===="
    nuclei -u "$target" -tags ssrf

    echo -e "\n==== XSS ===="
    nuclei -u "$target" -tags xss

    echo -e "\n==== SQL Injection ===="
    nuclei -u "$target" -tags sqli
}

subdomain_nuclei_mass() {
    read -rp "Domain: " domain
    validate_not_empty "$domain" "Domain" || return 1

    subdomain_enum "$domain" || {
        echo "[!] Subdomain enum failed"
        return 1
    }

    ensure_file_exists "$SUBS_FILE" || return 1

    echo "[+] Running nuclei on subdomains..."
    update_nuclei_templates
    nuclei -l "$SUBS_FILE"
}

parallel_scan() {
    read -rp "Target URL: " target
    validate_not_empty "$target" "URL" || return 1
    local url
    url="$(ensure_url "$target")"

    mkdir -p "$REPORT_DIR"
    
    local report_file="${REPORT_DIR}/report-$(date +%F_%T).html"
    local tmp_nmap="${TEMP_DIR}/nmap_$$.tmp"
    local tmp_headers="${TEMP_DIR}/headers_$$.tmp"
    local tmp_dir="${TEMP_DIR}/dir_$$.tmp"
    local tmp_nuclei="${TEMP_DIR}/nuclei_$$.tmp"

    echo "<html><body><pre>" > "$report_file"

    {
        echo "=== NMAP ==="
        nmap -Pn "$url"
    } > "$tmp_nmap" 2>&1 &

    {
        echo "=== HEADERS ==="
        safe_curl -sI "$url"
    } > "$tmp_headers" 2>&1 &

    {
        echo "=== DIR BRUTE ==="
        if ensure_file_exists "$WORDLIST" 2>/dev/null; then
            while read -r word; do
                [[ -z "$word" ]] && continue
                local code
                code=$(safe_curl -o /dev/null -w "%{http_code}" "${url}/${word}")
                [[ "$code" != "404" ]] && echo "${url}/${word} [${code}]"
            done < "$WORDLIST"
        else
            echo "Wordlist not found, skipping directory brute"
        fi
    } > "$tmp_dir" 2>&1 &

    {
        echo "=== NUCLEI ==="
        update_nuclei_templates
        nuclei -u "$url"
    } > "$tmp_nuclei" 2>&1 &

    wait

    cat "$tmp_nmap" "$tmp_headers" "$tmp_dir" "$tmp_nuclei" >> "$report_file" 2>/dev/null
    echo "</pre></body></html>" >> "$report_file"

    log_info "Saved: $report_file"
}

# ========= MENU =========
menu() {
    echo -e "${B}
[1] DNS Lookup
[2] Whois
[3] HTTP Headers
[4] Clickjack Test
[5] Robots.txt
[6] IP Location
[7] Traceroute
[8] Subdomain Enum
[9] Wayback URL Enum
[10] Subdomain Takeover Check
[11] Directory Brute
[12] Vulnerable Header Scan
[13] SSL Certificate Check
[14] Nuclei Single Scan
[15] Subdomain → Nuclei Mass Scan
[16] Parallel Scan + HTML Report
[17] Nuclei CVE Scan (Only CVEs)
[18] Focused Web Vuln Scan (XSS, SQLi, SSRF, etc)
[19] Exit
 ${N}"
}

# ========= MAIN =========
auto_install

while true; do
    banner
    menu
    read -rp "Choice: " choice
    case "$choice" in
        1)  dns_lookup ;;
        2)  whois_lookup ;;
        3)  http_headers ;;
        4)  clickjack ;;
        5)  robots ;;
        6)  ip_location ;;
        7)  trace_route ;;
        8)  subdomain_enum ;;
        9)  wayback_enum ;;
        10) takeover_check ;;
        11) dir_brute ;;
        12) vuln_header_scan ;;
        13) ssl_check ;;
        14) nuclei_scan ;;
        15) subdomain_nuclei_mass ;;
        16) parallel_scan ;;
        17) nuclei_cve_scan ;;
        18) focused_web_vuln_scan ;;
        19) exit 0 ;;
        *)  echo "Invalid" ;;
    esac
    pause
done