#!/bin/bash

# Firewall Setup for Captive Portal
# Run with sudo to configure firewall rules

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Configuring Firewall for Captive Portal${NC}"
echo "========================================"

# Check if UFW is available
if command -v ufw &> /dev/null; then
    echo -e "\n${YELLOW}Configuring UFW...${NC}"
    
    # Allow SSH to prevent lockout
    ufw allow ssh
    
    # Allow port 3000 for the captive portal
    ufw allow 3000/tcp
    
    # Allow HTTP and HTTPS for general web access
    ufw allow 80/tcp
    ufw allow 443/tcp
    
    # Enable UFW if not already enabled
    echo "y" | ufw enable
    
    # Show status
    ufw status
    
    echo -e "${GREEN}✓ UFW configured successfully${NC}"
else
    echo -e "\n${YELLOW}UFW not available, checking iptables...${NC}"
    
    # Basic iptables rules
    iptables -I INPUT -p tcp --dport 3000 -j ACCEPT
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT
    
    echo -e "${GREEN}✓ Basic iptables rules added${NC}"
fi

echo -e "\n${GREEN}Firewall configuration complete!${NC}"
echo -e "${YELLOW}Port 3000 is now accessible from external devices${NC}"