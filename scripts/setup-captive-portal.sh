#!/bin/bash

# Captive Portal Full Setup Script
# This script configures the complete captive portal infrastructure

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PORTAL_IP="10.1.50.140"
PORTAL_PORT="3000"
GATEWAY_IP="10.1.50.1"
NETWORK_INTERFACE="eno1"  # Change to your network interface
WIFI_INTERFACE="eno1"     # Using same interface for testing
DHCP_RANGE_START="10.1.50.50"
DHCP_RANGE_END="10.1.50.150"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  Captive Portal Setup Script${NC}"
echo -e "${BLUE}===========================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "\n${YELLOW}Configuration:${NC}"
echo -e "Portal Server: ${PORTAL_IP}:${PORTAL_PORT}"
echo -e "Gateway: ${GATEWAY_IP}"
echo -e "Network Interface: ${NETWORK_INTERFACE}"
echo -e "WiFi Interface: ${WIFI_INTERFACE}"
echo -e "DHCP Range: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"

read -p "Continue with this configuration? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install required packages
echo -e "\n${YELLOW}Installing required packages...${NC}"
apt update
apt install -y iptables-persistent dnsmasq hostapd bridge-utils

# Backup existing configurations
echo -e "\n${YELLOW}Backing up existing configurations...${NC}"
mkdir -p /etc/captive-portal/backups
cp /etc/dnsmasq.conf /etc/captive-portal/backups/dnsmasq.conf.bak 2>/dev/null || true
cp /etc/iptables/rules.v4 /etc/captive-portal/backups/rules.v4.bak 2>/dev/null || true

# Configure dnsmasq
echo -e "\n${YELLOW}Configuring dnsmasq...${NC}"
cat > /etc/dnsmasq.conf << EOF
# Captive Portal DNS Configuration

# Listen on specific interface
interface=${NETWORK_INTERFACE}
bind-interfaces

# DHCP configuration
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},12h
dhcp-option=3,${GATEWAY_IP}  # Gateway
dhcp-option=6,${PORTAL_IP}   # DNS Server

# DNS hijacking - redirect all domains to portal
address=/#/${PORTAL_IP}

# Local domain resolution
local=/portal/
domain=portal

# Log DNS queries for debugging
log-queries
log-dhcp

# Don't read /etc/hosts
no-hosts

# Don't read /etc/resolv.conf
no-resolv

# Use specific DNS servers for upstream when needed
server=8.8.8.8
server=8.8.4.4

# Cache size
cache-size=1000
EOF

# Configure iptables rules
echo -e "\n${YELLOW}Configuring iptables rules...${NC}"

# Flush existing rules
iptables -F
iptables -t nat -F
iptables -t mangle -F

# Create custom chains
iptables -t nat -N CAPTIVE_PORTAL 2>/dev/null || true
iptables -t filter -N CAPTIVE_ALLOWED 2>/dev/null || true
iptables -t filter -N CAPTIVE_BLOCKED 2>/dev/null || true

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Basic firewall rules
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow SSH (important!)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow portal access
iptables -A INPUT -p tcp --dport ${PORTAL_PORT} -j ACCEPT
iptables -A INPUT -p udp --dport 53 -j ACCEPT  # DNS
iptables -A INPUT -p udp --dport 67 -j ACCEPT  # DHCP

# Portal traffic handling
iptables -t nat -A PREROUTING -i ${NETWORK_INTERFACE} -p tcp --dport 80 -j CAPTIVE_PORTAL
iptables -t nat -A PREROUTING -i ${NETWORK_INTERFACE} -p tcp --dport 443 -j CAPTIVE_PORTAL

# DNS redirection
iptables -t nat -A PREROUTING -i ${NETWORK_INTERFACE} -p udp --dport 53 -j DNAT --to-destination ${PORTAL_IP}:53

# Default redirect to portal
iptables -t nat -A CAPTIVE_PORTAL -j DNAT --to-destination ${PORTAL_IP}:${PORTAL_PORT}

# Forward rules
iptables -A FORWARD -i ${NETWORK_INTERFACE} -j CAPTIVE_BLOCKED
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP
iptables -A FORWARD -p icmp -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT

# Drop everything else on input
iptables -A INPUT -j DROP

# NAT for internet access
iptables -t nat -A POSTROUTING -o ${NETWORK_INTERFACE} -j MASQUERADE

# Save iptables rules
echo -e "\n${YELLOW}Saving iptables rules...${NC}"
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

# Create MAC whitelist management
echo -e "\n${YELLOW}Setting up MAC whitelist system...${NC}"
mkdir -p /etc/captive-portal
touch /etc/captive-portal/allowed_macs.txt

# Create MAC whitelist script
cat > /usr/local/bin/captive-whitelist << 'EOF'
#!/bin/bash

WHITELIST_FILE="/etc/captive-portal/allowed_macs.txt"
IPTABLES_CHAIN="CAPTIVE_ALLOWED"

add_mac() {
    local mac=$1
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        # Add to whitelist file
        if ! grep -q "$mac" "$WHITELIST_FILE"; then
            echo "$mac" >> "$WHITELIST_FILE"
        fi
        
        # Add iptables rule
        iptables -C FORWARD -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || \
        iptables -I FORWARD -m mac --mac-source "$mac" -j ACCEPT
        
        echo "MAC address $mac whitelisted"
    else
        echo "Invalid MAC address format: $mac"
        exit 1
    fi
}

remove_mac() {
    local mac=$1
    # Remove from whitelist file
    sed -i "/$mac/d" "$WHITELIST_FILE"
    
    # Remove iptables rule
    iptables -D FORWARD -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || true
    
    echo "MAC address $mac removed from whitelist"
}

list_macs() {
    echo "Whitelisted MAC addresses:"
    cat "$WHITELIST_FILE" 2>/dev/null || echo "No MAC addresses whitelisted"
}

case "$1" in
    add)
        add_mac "$2"
        ;;
    remove)
        remove_mac "$2"
        ;;
    list)
        list_macs
        ;;
    *)
        echo "Usage: $0 {add|remove|list} [MAC_ADDRESS]"
        echo "Example: $0 add aa:bb:cc:dd:ee:ff"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/captive-whitelist

# Create systemd service for restoring iptables on boot
echo -e "\n${YELLOW}Creating systemd services...${NC}"
cat > /etc/systemd/system/captive-portal.service << EOF
[Unit]
Description=Captive Portal Network Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'iptables-restore < /etc/iptables/rules.v4'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Enable services
systemctl daemon-reload
systemctl enable captive-portal.service
systemctl enable dnsmasq

# Start services
echo -e "\n${YELLOW}Starting services...${NC}"
systemctl restart dnsmasq
systemctl start captive-portal.service

# Create helper scripts
echo -e "\n${YELLOW}Creating helper scripts...${NC}"

# Status check script
cat > /usr/local/bin/captive-status << 'EOF'
#!/bin/bash
echo "=== Captive Portal Status ==="
echo ""
echo "DNS Service:"
systemctl is-active dnsmasq

echo ""
echo "Portal Application:"
ps aux | grep "node.*src/app.js" | grep -v grep || echo "Not running"

echo ""
echo "Whitelisted MACs:"
captive-whitelist list

echo ""
echo "Active DHCP Leases:"
cat /var/lib/dhcp/dhcpd.leases 2>/dev/null | grep "lease" | tail -5 || echo "No active leases"
EOF

chmod +x /usr/local/bin/captive-status

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}  Captive Portal Setup Complete!${NC}"
echo -e "${GREEN}===========================================${NC}"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Start your portal application: npm run dev"
echo "2. Test with a client device"
echo "3. Use 'captive-whitelist add MAC_ADDRESS' to grant access"
echo "4. Use 'captive-status' to check system status"

echo -e "\n${YELLOW}Important Commands:${NC}"
echo "• Check status: captive-status"
echo "• Add MAC to whitelist: captive-whitelist add aa:bb:cc:dd:ee:ff"
echo "• Remove MAC: captive-whitelist remove aa:bb:cc:dd:ee:ff"
echo "• View logs: journalctl -u dnsmasq -f"

echo -e "\n${BLUE}Portal URL: http://${PORTAL_IP}:${PORTAL_PORT}${NC}"