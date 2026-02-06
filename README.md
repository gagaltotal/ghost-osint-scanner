# Ghost OSINT Scanner

Recon • OSINT • Vulnerability Scan • Toolkit (Pure Bash)

Ghost OSINT Scanner adalah toolkit reconnaissance & vulnerability automation berbasis bash.

---

## Features

### Recon
- DNS Lookup (dig trace)
- Whois Lookup
- HTTP Header Grabber
- Robots.txt
- IP Geolocation
- Traceroute

### Enumeration
- Subdomain Enumeration (crt.sh)
- Wayback URL Enumeration
- Subdomain Takeover Detection

### Brute / Discovery
- Directory Brute Force

### Vulnerability Checks
- Clickjacking Test
- Vulnerable Security Headers Scan
- SSL Certificate Info (CVE hint)
- Nuclei Vulnerability Scan

### Automation
- Subdomain → Nuclei Mass Scan
- Parallel Multi Scan
- Auto HTML Report

---

## Auto Dependency Install

Script otomatis install jika belum ada:

- curl
- dig (dnsutils)
- whois
- nmap
- jq
- mtr
- nuclei

---

## Usage

```bash
chmod +x ghost_osint_scanner.sh
./ghost_osint_scanner.sh

---