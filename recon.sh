#!/bin/bash

# ⚡ CTF Recon Script - Full Suite with Tool Toggles ⚡

# ========== Config ==========
TARGET=$1
WORDLIST="/usr/share/seclists/Discovery/Web-Content/raft-small-words.txt"
USE_FFUF=true
USE_GOBUSTER=true
USE_NIKTO=true
# ============================

if [ -z "$TARGET" ]; then
  echo "Usage: $0 <target (IP or URL)>"
  exit 1
fi

OUTPUT_DIR="recon_$(echo $TARGET | sed 's/[:\/]/_/g')"
mkdir -p "$OUTPUT_DIR"

echo "[*] Starting Recon on $TARGET"
echo "[*] Saving results in: $OUTPUT_DIR"
echo ""

# ---------- Host Reachability ----------
echo "[*] Checking if host is alive..."
ping -c 1 "$TARGET" > /dev/null 2>&1 && echo "[+] Host is up" || echo "[!] Host seems unreachable"
echo ""

# ---------- Nmap Scan ----------
echo "[*] Running Nmap scan..."
nmap -T4 -sV -oN "$OUTPUT_DIR/nmap.txt" "$TARGET"
echo "[+] Nmap scan complete: $OUTPUT_DIR/nmap.txt"
echo ""

# ---------- HTTP Content Recon ----------
if [[ "$TARGET" == http* ]]; then
  echo "[*] Grabbing HTTP headers..."
  curl -I "$TARGET" -s > "$OUTPUT_DIR/headers.txt"
  echo "[+] Headers saved: headers.txt"

  echo "[*] Fetching main page content..."
  curl "$TARGET" -s > "$OUTPUT_DIR/page.html"

  echo "[*] Extracting links..."
  grep -Eo 'href="([^"#]+)"' "$OUTPUT_DIR/page.html" | cut -d'"' -f2 | sort -u > "$OUTPUT_DIR/links.txt"

  echo "[*] Extracting script sources..."
  grep -Eo 'src="([^"#]+)"' "$OUTPUT_DIR/page.html" | cut -d'"' -f2 | sort -u > "$OUTPUT_DIR/scripts.txt"
  echo ""

  # ---------- FFUF ----------
  if $USE_FFUF && command -v ffuf >/dev/null 2>&1; then
    echo "[*] Running ffuf directory scan..."
    ffuf -u "$TARGET/FUZZ" -w "$WORDLIST" -o "$OUTPUT_DIR/ffuf.json" -of json -t 40
    echo "[+] ffuf complete: $OUTPUT_DIR/ffuf.json"
    echo ""
  fi

  # ---------- Gobuster ----------
  if $USE_GOBUSTER && command -v gobuster >/dev/null 2>&1; then
    echo "[*] Running Gobuster scan..."
    gobuster dir -u "$TARGET" -w "$WORDLIST" -o "$OUTPUT_DIR/gobuster.txt" -q
    echo "[+] Gobuster complete: $OUTPUT_DIR/gobuster.txt"
    echo ""
  fi

  # ---------- Admin/Login Discovery ----------
  echo "[*] Checking common admin/login pages..."
  COMMON_PATHS=(admin login dashboard panel wp-admin cpanel admin.php login.php)
  ADMIN_RESULT_FILE="$OUTPUT_DIR/admin_panels.txt"
  > "$ADMIN_RESULT_FILE"

  for path in "${COMMON_PATHS[@]}"; do
    FULL_URL="${TARGET%/}/$path"
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FULL_URL")
    if [[ "$STATUS" != "404" ]]; then
      echo "[+] Found: $FULL_URL (Status: $STATUS)" | tee -a "$ADMIN_RESULT_FILE"
    fi
  done
  echo "[✓] Admin page scan done."
  echo ""

  # ---------- Nikto Scan ----------
  if $USE_NIKTO && command -v nikto >/dev/null 2>&1; then
    echo "[*] Running Nikto scan..."
    nikto -h "$TARGET" -o "$OUTPUT_DIR/nikto.txt" > /dev/null
    echo "[+] Nikto complete: $OUTPUT_DIR/nikto.txt"
    echo ""
  fi

  # ---------- WPScan ----------
  if grep -qi "wp-content" "$OUTPUT_DIR/page.html"; then
    if command -v wpscan >/dev/null 2>&1; then
      echo "[*] WordPress detected! Running WPScan..."
      wpscan --url "$TARGET" --enumerate u --output "$OUTPUT_DIR/wpscan.txt"
      echo "[+] WPScan complete: $OUTPUT_DIR/wpscan.txt"
    else
      echo "[!] WPScan not installed. Skipping WordPress scan."
    fi
  fi
fi

echo ""
echo "[✓] Recon complete! Review: $OUTPUT_DIR"
