#!/usr/bin/env bash

B="\e[34m"; G="\e[32m"; R="\e[31m"; N="\e[0m"

PKGS=(curl dnsutils whois nmap jq mtr)

#======== AUTO INSTALL DEPENDENCIES =========
auto_install(){

need_install=false

for p in "${PKGS[@]}"; do
if ! dpkg -s "$p" &>/dev/null; then
need_install=true
break
fi
done

if ! command -v nuclei >/dev/null; then
need_install=true
fi

$need_install || return 0

echo -e "${G}[+] Checking & installing missing dependencies...${N}"

for p in "${PKGS[@]}"; do
dpkg -s "$p" &>/dev/null || {
echo "[+] Installing $p"
sudo apt-get install -y "$p" >/dev/null
}
done

if ! command -v nuclei >/dev/null; then
echo "[+] Installing nuclei"
tmpdir=$(mktemp -d)
cd "$tmpdir" || exit
wget -q https://github.com/projectdiscovery/nuclei/releases/latest/download/nuclei_$(uname -s)_$(uname -m).zip -O nuclei.zip
unzip -o nuclei.zip >/dev/null
sudo mv nuclei /usr/local/bin/
cd - >/dev/null || exit
rm -rf "$tmpdir"
fi

echo -e "${G}[+] Dependencies ready.${N}"
}

#======== BANNER FUNCTION =========
banner(){
clear
echo -e "${B}
   ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗    ██████╗ ███████╗
  ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝   ██╔═══██╗██╔════╝
  ██║  ███╗███████║██║   ██║███████╗   ██║█████╗██║   ██║███████╗
  ██║   ██║██╔══██║██║   ██║╚════██║   ██║╚════╝██║   ██║╚════██║
  ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║      ╚██████╔╝███████║
   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝       ╚═════╝ ╚══════╝
  Ghost OSINT Scanner - Recon • Enum • Vuln • Report - version 1.0
${N}"
}

pause(){ read -p "Enter to continue..."; }

#========= FUNCTIONS MAIN =========
dns_lookup(){ read -p "Target: " t; dig "$t" +trace ANY; }
whois_lookup(){ read -p "Target: " t; whois "$t"; }
http_headers(){ read -p "URL: " t; curl -I "$t"; }

clickjack(){
read -p "URL: " t; [[ "$t" != http* ]] && t="http://$t"
curl -sI "$t" | grep -qi x-frame-options && echo "Safe" || echo "Vulnerable"
}

robots(){ read -p "URL: " t; curl -s "$t/robots.txt"; }
ip_location(){ read -p "IP/Domain: " t; curl -s "http://ip-api.com/json/$t" | jq; }
trace_route(){ read -p "Target: " t; mtr -4 -rwc 1 "$t"; }

subdomain_enum(){
if [ -n "$1" ]; then
d="$1"
else
read -p "Domain: " d
fi

echo "[+] Enumerating subdomains..."

resp=$(curl -s -H "User-Agent: recon" "https://crt.sh/?q=%25.$d&output=json")

echo "$resp" | grep -q "name_value" || {
echo "[!] crt.sh returned non-JSON (rate limit?)"
return 1
}

echo "$resp" | jq -r '.[].name_value' 2>/dev/null \
| sed 's/\*\.//g' \
| sort -u | tee subs.txt
}

wayback_enum(){
read -p "Domain: " d
curl -s "https://web.archive.org/cdx/search/cdx?url=*.$d/*&output=text&fl=original&collapse=urlkey" \
| sort -u | tee wayback_urls.txt
}

takeover_check(){
  read -p "Domain: " d

  echo "[+] Checking subdomain takeover..."

  subdomain_enum "$d" >/dev/null || {
  echo "[!] Subdomain enumeration failed"
  return
  }

  [ -f subs.txt ] || { echo "[!] subs.txt missing"; return; }

  while read -r sub; do
  [ -z "$sub" ] && continue

  cname=$(dig +short CNAME "$sub" | head -n1)
  ip=$(dig +short "$sub" | head -n1)

  [[ -z "$ip" ]] && echo "[NXDOMAIN] $sub"

  if echo "$cname" | grep -Eqi "github.io|herokuapp.com|amazonaws.com|azurewebsites.net|fastly.net"; then
  echo "[CNAME Risk] $sub -> $cname"
  fi

  resp=$(curl -sL --max-time 5 "http://$sub")
  echo "$resp" | grep -Eqi "NoSuchBucket|There isn't a GitHub Pages site here|heroku" \
  && echo "[HTTP Takeover Pattern] $sub"

  done < subs.txt
}

dir_brute(){
read -p "URL: " t
wl="/usr/share/wordlists/dirb/common.txt"
while read w; do
code=$(curl -s -o /dev/null -w "%{http_code}" "$t/$w")
[[ "$code" != "404" ]] && echo "$t/$w [$code]"
done < "$wl"
}

vuln_header_scan(){
read -p "URL: " t
h=$(curl -sI "$t")
for x in x-frame-options content-security-policy x-content-type-options strict-transport-security; do
echo "$h" | grep -qi "$x" || echo "Missing $x"
done
}

ssl_check(){
read -p "Domain: " d
echo | openssl s_client -connect "$d:443" 2>/dev/null | openssl x509 -noout -dates -issuer -subject
}

nuclei_scan(){ 
  read -p "URL: " t; nuclei -u "$t"; 
}

nuclei_cve_scan(){
read -p "URL/Domain: " t

echo "[+] Running CVE-only scan (nuclei)..."

nuclei -u "$t" -tags cve -severity critical,high,medium
}

subdomain_nuclei_mass(){
read -p "Domain: " d

subdomain_enum "$d" || {
echo "[!] Subdomain enum failed"
return
}

[ -f subs.txt ] || { echo "[!] subs.txt not found"; return; }

echo "[+] Running nuclei on subdomains..."
nuclei -l subs.txt
}

parallel_scan(){
read -p "Target URL: " t
mkdir -p reports
R="reports/report-$(date +%F_%T).html"
echo "<html><body><pre>" > "$R"

{
echo "=== NMAP ==="
nmap -Pn "$t"
} >> "$R" &

{
echo "=== HEADERS ==="
curl -sI "$t"
} >> "$R" &

{
echo "=== DIR BRUTE ==="
wl="/usr/share/wordlists/dirb/common.txt"
while read w; do
code=$(curl -s -o /dev/null -w "%{http_code}" "$t/$w")
[[ "$code" != "404" ]] && echo "$t/$w [$code]"
done < "$wl"
} >> "$R" &

{
echo "=== NUCLEI ==="
nuclei -u "$t"
} >> "$R" &

wait
echo "</pre></body></html>" >> "$R"
echo -e "${G}Saved: $R${N}"
}

# ========= MENU =========
menu(){
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
[18] Exit
${N}"
}

# ========= MAIN =========
auto_install

while true; do
banner
menu
read -p "Choice: " c
case $c in
1) dns_lookup ;;
2) whois_lookup ;;
3) http_headers ;;
4) clickjack ;;
5) robots ;;
6) ip_location ;;
7) trace_route ;;
8) subdomain_enum ;;
9) wayback_enum ;;
10) takeover_check ;;
11) dir_brute ;;
12) vuln_header_scan ;;
13) ssl_check ;;
14) nuclei_scan ;;
15) subdomain_nuclei_mass ;;
16) parallel_scan ;;
17) nuclei_cve_scan ;;
18) exit 0 ;;
*) echo "Invalid";;
esac
pause
done
