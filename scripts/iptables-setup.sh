#!/bin/bash

# Captive Portal iptables Configuration Script
# This script sets up the firewall rules for the captive portal

# Configuration
PORTAL_IP="192.168.1.100"
PORTAL_PORT="3000"
INTERFACE="wlan0"
ALLOWED_MAC_FILE="/etc/captive-portal/allowed_macs.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

echo -e "${GREEN}Setting up captive portal iptables rules...${NC}"

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

# Flush existing rules
iptables -t nat -F
iptables -t mangle -F
iptables -F

# Create custom chains
iptables -t nat -N PORTAL_REDIRECT 2>/dev/null || true
iptables -t filter -N PORTAL_ALLOWED 2>/dev/null || true

# Allow established connections
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow DNS queries to the portal
iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 53 -j DNAT --to-destination $PORTAL_IP:53
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 53 -j DNAT --to-destination $PORTAL_IP:53

# Allow direct access to the portal
iptables -t nat -A PREROUTING -i $INTERFACE -d $PORTAL_IP -p tcp --dport $PORTAL_PORT -j ACCEPT
iptables -t filter -A FORWARD -i $INTERFACE -d $PORTAL_IP -p tcp --dport $PORTAL_PORT -j ACCEPT

# Redirect HTTP traffic to portal
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 80 -j PORTAL_REDIRECT
iptables -t nat -A PORTAL_REDIRECT -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT

# Redirect HTTPS traffic to portal (handle with care)
iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 443 -j PORTAL_REDIRECT

# Allow ICMP (ping)
iptables -A FORWARD -p icmp -j ACCEPT

# Function to add allowed MAC address
add_allowed_mac() {
    local mac=$1
    echo -e "${GREEN}Adding MAC address to whitelist: $mac${NC}"
    iptables -t nat -I PREROUTING -i $INTERFACE -m mac --mac-source $mac -j ACCEPT
    iptables -I FORWARD -i $INTERFACE -m mac --mac-source $mac -j ACCEPT
    echo $mac >> $ALLOWED_MAC_FILE
}

# Load allowed MAC addresses from file
if [ -f "$ALLOWED_MAC_FILE" ]; then
    echo -e "${YELLOW}Loading allowed MAC addresses...${NC}"
    while IFS= read -r mac; do
        if [[ ! -z "$mac" && ! "$mac" =~ ^# ]]; then
            add_allowed_mac "$mac"
        fi
    done < "$ALLOWED_MAC_FILE"
fi

# Drop all other forwarding traffic
iptables -A FORWARD -i $INTERFACE -j DROP

# Save rules
if command -v iptables-save &> /dev/null; then
    echo -e "${GREEN}Saving iptables rules...${NC}"
    iptables-save > /etc/iptables/rules.v4
fi

echo -e "${GREEN}Captive portal iptables setup complete!${NC}"
echo -e "${YELLOW}Remember to:${NC}"
echo "1. Configure dnsmasq for DNS hijacking"
echo "2. Start the captive portal application"
echo "3. Test with a client device"