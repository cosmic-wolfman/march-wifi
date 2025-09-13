#!/bin/bash

# Captive Portal Control Script
# Enable/Disable captive portal redirection without stopping services

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INTERFACE="eno1"
PORTAL_IP="10.1.50.140"
PORTAL_PORT="3000"

show_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}     Captive Portal Current Status      ${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Check redirect rules
    REDIRECT_COUNT=$(sudo iptables -t nat -L PREROUTING -n 2>/dev/null | grep -c "$PORTAL_IP:$PORTAL_PORT" || echo "0")
    if [ "$REDIRECT_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✓ Portal Redirection: ENABLED${NC}"
        echo "  Active redirect rules: $REDIRECT_COUNT"
    else
        echo -e "${YELLOW}○ Portal Redirection: DISABLED${NC}"
        echo "  No active redirect rules"
    fi

    # Check blocking rule
    BLOCK_RULE=$(sudo iptables -L FORWARD -n 2>/dev/null | grep -c "DROP.*$INTERFACE" || echo "0")
    if [ "$BLOCK_RULE" -gt 0 ]; then
        echo -e "${GREEN}✓ Access Blocking: ENABLED${NC}"
        echo "  Non-whitelisted devices are blocked"
    else
        echo -e "${YELLOW}○ Access Blocking: DISABLED${NC}"
        echo "  All devices have internet access"
    fi

    # Check services
    echo -e "\n${BLUE}[Services Status]${NC}"
    for service in dnsmasq postgresql redis; do
        if systemctl is-active --quiet $service; then
            echo -e "  ${GREEN}✓ $service: running${NC}"
        else
            echo -e "  ${RED}✗ $service: stopped${NC}"
        fi
    done

    if pgrep -f "node.*app.js" > /dev/null; then
        echo -e "  ${GREEN}✓ Portal App: running${NC}"
    else
        echo -e "  ${RED}✗ Portal App: stopped${NC}"
    fi

    # Check whitelisted MACs
    if [ -f /etc/captive-portal/allowed_macs.txt ]; then
        MAC_COUNT=$(wc -l < /etc/captive-portal/allowed_macs.txt 2>/dev/null || echo "0")
        echo -e "\n${BLUE}[Whitelisted Devices]${NC}"
        echo "  Total: $MAC_COUNT devices"
    fi
}

enable_portal() {
    echo -e "${YELLOW}Enabling Captive Portal Redirection...${NC}"

    # Add redirect rules
    echo "Adding traffic redirection rules..."

    # HTTP redirection
    sudo iptables -t nat -C PREROUTING -i $INTERFACE -p tcp --dport 80 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT 2>/dev/null || \
    sudo iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 80 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT

    # HTTPS redirection
    sudo iptables -t nat -C PREROUTING -i $INTERFACE -p tcp --dport 443 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT 2>/dev/null || \
    sudo iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 443 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT

    # DNS redirection
    sudo iptables -t nat -C PREROUTING -i $INTERFACE -p udp --dport 53 -j DNAT --to-destination $PORTAL_IP:53 2>/dev/null || \
    sudo iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 53 -j DNAT --to-destination $PORTAL_IP:53

    # Block non-whitelisted forwarding
    sudo iptables -C FORWARD -i $INTERFACE -j DROP 2>/dev/null || \
    sudo iptables -A FORWARD -i $INTERFACE -j DROP

    # Enable NAT
    sudo iptables -t nat -C POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE

    # Save rules
    sudo iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}✓ Captive Portal ENABLED${NC}"
    echo -e "${GREEN}  All new connections will be redirected to the portal${NC}"
}

disable_portal() {
    echo -e "${YELLOW}Disabling Captive Portal Redirection...${NC}"

    # Remove redirect rules
    echo "Removing traffic redirection rules..."

    # Remove HTTP/HTTPS redirections
    sudo iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport 80 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT 2>/dev/null || true
    sudo iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport 443 ! -d $PORTAL_IP -j DNAT --to-destination $PORTAL_IP:$PORTAL_PORT 2>/dev/null || true

    # Remove DNS redirection
    sudo iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport 53 -j DNAT --to-destination $PORTAL_IP:53 2>/dev/null || true

    # Remove blocking rule
    sudo iptables -D FORWARD -i $INTERFACE -j DROP 2>/dev/null || true

    # Keep NAT for general routing
    # sudo iptables -t nat -D POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || true

    # Save rules
    sudo iptables-save > /etc/iptables/rules.v4

    echo -e "${GREEN}✓ Captive Portal DISABLED${NC}"
    echo -e "${GREEN}  All devices now have direct internet access${NC}"
    echo -e "${YELLOW}  Note: Services are still running, portal is still accessible directly${NC}"
}

pause_portal() {
    echo -e "${YELLOW}Pausing Captive Portal (Temporary)...${NC}"

    # Just remove the blocking rule, keep redirects
    sudo iptables -D FORWARD -i $INTERFACE -j DROP 2>/dev/null || true

    echo -e "${GREEN}✓ Portal PAUSED${NC}"
    echo -e "${GREEN}  All devices have internet access${NC}"
    echo -e "${YELLOW}  Redirects still active but not blocking${NC}"
}

stop_all() {
    echo -e "${RED}Stopping All Captive Portal Services...${NC}"

    # Disable redirects first
    disable_portal

    # Stop application
    echo "Stopping portal application..."
    pkill -f "node.*app.js" 2>/dev/null || true

    # Stop services (optional)
    read -p "Stop DNS service (dnsmasq)? This may affect network DNS. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl stop dnsmasq
        echo -e "${YELLOW}  dnsmasq stopped${NC}"
    fi

    echo -e "${GREEN}✓ All portal services stopped${NC}"
}

start_all() {
    echo -e "${GREEN}Starting All Captive Portal Services...${NC}"

    # Start services
    echo "Starting services..."
    sudo systemctl start dnsmasq 2>/dev/null || true
    sudo systemctl start postgresql 2>/dev/null || true
    sudo systemctl start redis 2>/dev/null || true

    # Start application
    echo "Starting portal application..."
    cd /home/mlopez/gitprojects/march-wifi
    nohup npm run dev > /dev/null 2>&1 &

    sleep 2

    # Enable portal
    enable_portal

    echo -e "${GREEN}✓ All portal services started and enabled${NC}"
}

clear_whitelist() {
    echo -e "${RED}Clearing MAC Whitelist...${NC}"
    read -p "This will remove all whitelisted devices. Continue? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Backup first
        sudo cp /etc/captive-portal/allowed_macs.txt /etc/captive-portal/allowed_macs.backup.$(date +%s)

        # Clear file
        sudo > /etc/captive-portal/allowed_macs.txt

        # Remove all MAC rules from iptables
        sudo iptables-save | grep -v "mac-source" | sudo iptables-restore

        echo -e "${GREEN}✓ Whitelist cleared${NC}"
        echo "  Backup saved to /etc/captive-portal/allowed_macs.backup.*"
    else
        echo "Cancelled"
    fi
}

show_help() {
    echo -e "${BLUE}Captive Portal Control Script${NC}"
    echo ""
    echo "Usage: $0 {enable|disable|pause|stop|start|status|clear-whitelist}"
    echo ""
    echo "Commands:"
    echo "  ${GREEN}enable${NC}          - Enable portal redirection (block non-registered)"
    echo "  ${GREEN}disable${NC}         - Disable portal redirection (allow all traffic)"
    echo "  ${GREEN}pause${NC}           - Temporarily allow all traffic (keep redirects)"
    echo "  ${GREEN}stop${NC}            - Stop all portal services"
    echo "  ${GREEN}start${NC}           - Start all portal services and enable"
    echo "  ${GREEN}status${NC}          - Show current portal status"
    echo "  ${GREEN}clear-whitelist${NC} - Remove all whitelisted MACs"
    echo ""
    echo "Examples:"
    echo "  $0 disable     # Allow normal internet access"
    echo "  $0 enable      # Require portal registration"
    echo "  $0 status      # Check current state"
}

# Check if running as root for commands that need it
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This command requires root privileges${NC}"
        echo "Please run with sudo: sudo $0 $1"
        exit 1
    fi
}

# Main logic
case "$1" in
    enable)
        check_root $1
        enable_portal
        ;;
    disable)
        check_root $1
        disable_portal
        ;;
    pause)
        check_root $1
        pause_portal
        ;;
    stop)
        check_root $1
        stop_all
        ;;
    start)
        check_root $1
        start_all
        ;;
    status)
        show_status
        ;;
    clear-whitelist)
        check_root $1
        clear_whitelist
        ;;
    *)
        show_help
        ;;
esac