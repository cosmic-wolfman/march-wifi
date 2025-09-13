#!/bin/bash

# Captive Portal Setup for Development
# Run each command with sudo as needed

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PORTAL_IP="10.1.50.140"
PORTAL_PORT="3000"
GATEWAY_IP="10.1.50.1"
NETWORK_INTERFACE="eno1"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  Captive Portal Setup Instructions${NC}"
echo -e "${BLUE}===========================================${NC}"

echo -e "\n${YELLOW}Configuration:${NC}"
echo -e "Portal Server: ${PORTAL_IP}:${PORTAL_PORT}"
echo -e "Gateway: ${GATEWAY_IP}"
echo -e "Network Interface: ${NETWORK_INTERFACE}"

echo -e "\n${GREEN}Step 1: Install Required Packages${NC}"
echo "Run: sudo apt update && sudo apt install -y dnsmasq iptables-persistent"

echo -e "\n${GREEN}Step 2: Configure dnsmasq${NC}"
echo "Create /etc/dnsmasq.d/captive-portal.conf with:"
cat << EOF
# Save this to /etc/dnsmasq.d/captive-portal.conf

# Listen on specific interface
interface=${NETWORK_INTERFACE}
bind-interfaces

# DNS hijacking - redirect all domains to portal
address=/#/${PORTAL_IP}

# Don't read /etc/hosts
no-hosts

# Don't read /etc/resolv.conf
no-resolv

# Use Google DNS for upstream when needed
server=8.8.8.8
server=8.8.4.4

# Cache size
cache-size=1000

# Log queries (optional, for debugging)
log-queries
EOF

echo -e "\n${GREEN}Step 3: Configure iptables${NC}"
echo "Run these commands with sudo:"
cat << 'EOF'

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Create custom chains
sudo iptables -t nat -N CAPTIVE_PORTAL 2>/dev/null || true
sudo iptables -t filter -N CAPTIVE_ALLOWED 2>/dev/null || true

# Allow established connections
sudo iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow portal access
sudo iptables -t nat -A PREROUTING -i eno1 -d 10.1.50.140 -p tcp --dport 3000 -j ACCEPT

# Redirect HTTP to portal
sudo iptables -t nat -A PREROUTING -i eno1 -p tcp --dport 80 ! -d 10.1.50.140 -j DNAT --to-destination 10.1.50.140:3000

# Redirect HTTPS to portal (optional, may cause cert warnings)
sudo iptables -t nat -A PREROUTING -i eno1 -p tcp --dport 443 ! -d 10.1.50.140 -j DNAT --to-destination 10.1.50.140:3000

# DNS redirection
sudo iptables -t nat -A PREROUTING -i eno1 -p udp --dport 53 -j DNAT --to-destination 10.1.50.140:53
sudo iptables -t nat -A PREROUTING -i eno1 -p tcp --dport 53 -j DNAT --to-destination 10.1.50.140:53

# Block forwarding by default (except whitelisted MACs)
sudo iptables -A FORWARD -i eno1 -j DROP

# NAT for internet access (for whitelisted MACs)
sudo iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE

# Save iptables rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
EOF

echo -e "\n${GREEN}Step 4: Create MAC Whitelist Script${NC}"
echo "Save this as /usr/local/bin/captive-whitelist:"
cat << 'EOF'
#!/bin/bash

WHITELIST_FILE="/etc/captive-portal/allowed_macs.txt"
INTERFACE="eno1"

add_mac() {
    local mac=$1
    if [[ $mac =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
        # Add to whitelist file
        sudo mkdir -p /etc/captive-portal
        if ! grep -q "$mac" "$WHITELIST_FILE" 2>/dev/null; then
            echo "$mac" | sudo tee -a "$WHITELIST_FILE"
        fi

        # Add iptables rule - insert before the DROP rule
        sudo iptables -C FORWARD -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || \
        sudo iptables -I FORWARD 1 -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT

        # Allow in NAT table too
        sudo iptables -t nat -C PREROUTING -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || \
        sudo iptables -t nat -I PREROUTING 1 -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT

        echo "MAC address $mac whitelisted"

        # Save rules
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
    else
        echo "Invalid MAC address format: $mac"
        exit 1
    fi
}

remove_mac() {
    local mac=$1
    # Remove from whitelist file
    sudo sed -i "/$mac/d" "$WHITELIST_FILE" 2>/dev/null

    # Remove iptables rules
    sudo iptables -D FORWARD -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || true
    sudo iptables -t nat -D PREROUTING -i $INTERFACE -m mac --mac-source "$mac" -j ACCEPT 2>/dev/null || true

    echo "MAC address $mac removed from whitelist"

    # Save rules
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
}

list_macs() {
    echo "Whitelisted MAC addresses:"
    if [ -f "$WHITELIST_FILE" ]; then
        cat "$WHITELIST_FILE" 2>/dev/null || echo "No MAC addresses whitelisted"
    else
        echo "No MAC addresses whitelisted"
    fi
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

echo -e "\n${GREEN}Step 5: Make scripts executable${NC}"
echo "Run: sudo chmod +x /usr/local/bin/captive-whitelist"

echo -e "\n${GREEN}Step 6: Restart services${NC}"
echo "Run:"
echo "sudo systemctl restart dnsmasq"
echo "sudo netfilter-persistent save"

echo -e "\n${YELLOW}Testing Commands:${NC}"
echo "• Check iptables: sudo iptables -t nat -L -n -v"
echo "• Check dnsmasq: sudo systemctl status dnsmasq"
echo "• Add MAC: captive-whitelist add AA:BB:CC:DD:EE:FF"
echo "• Test DNS: nslookup google.com 127.0.0.1"

echo -e "\n${BLUE}===========================================${NC}"
echo -e "${BLUE}  Manual setup required - follow steps above${NC}"
echo -e "${BLUE}===========================================${NC}"