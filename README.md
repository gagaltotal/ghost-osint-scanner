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
- Nuclei CVE Scan (Only CVEs)
- Focused Web Vuln Scan (XSS, SQLi, SSRF, etc)
- Auto HTML Report

---

## Auto Dependency Install

Dependency support os :

- Ubuntu/Debian
- Kali Linux

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
```

![Screen Capture](https://raw.githubusercontent.com/gagaltotal/ghost-osint-scanner/refs/heads/main/Screenshot%20from%202026-02-06%2023-18-48.png)

---