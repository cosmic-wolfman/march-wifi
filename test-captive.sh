#!/bin/bash

# Captive Portal Test Script
echo "========================================="
echo "     Captive Portal Test Suite"
echo "========================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "\n${YELLOW}1. Testing DNS Hijacking:${NC}"
echo "Testing google.com resolution..."
DNS_RESULT=$(nslookup google.com 127.0.0.1 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}')
if [[ "$DNS_RESULT" == "10.1.50.140" ]]; then
    echo -e "${GREEN}✓ DNS hijacking is working (google.com → 10.1.50.140)${NC}"
else
    echo -e "${RED}✗ DNS not redirecting properly. Result: $DNS_RESULT${NC}"
fi

echo -e "\n${YELLOW}2. Testing Portal Accessibility:${NC}"
if curl -s http://10.1.50.140:3000 | grep -q "WiFi Access Portal"; then
    echo -e "${GREEN}✓ Portal is accessible at http://10.1.50.140:3000${NC}"
else
    echo -e "${RED}✗ Portal not accessible${NC}"
fi

echo -e "\n${YELLOW}3. Checking iptables Rules:${NC}"
HTTP_RULES=$(sudo iptables -t nat -L PREROUTING -n 2>/dev/null | grep -c "10.1.50.140:3000")
if [[ "$HTTP_RULES" -gt 0 ]]; then
    echo -e "${GREEN}✓ Found $HTTP_RULES redirect rules to portal${NC}"
else
    echo -e "${RED}✗ No redirect rules found${NC}"
    echo "  You may need to run: sudo ./install-captive-portal.sh"
fi

echo -e "\n${YELLOW}4. Checking Whitelisted MACs:${NC}"
if [ -f /etc/captive-portal/allowed_macs.txt ]; then
    MAC_COUNT=$(wc -l < /etc/captive-portal/allowed_macs.txt 2>/dev/null || echo "0")
    echo -e "${GREEN}✓ Whitelist file exists with $MAC_COUNT MACs${NC}"
    if [ "$MAC_COUNT" -gt 0 ]; then
        echo "  Recent entries:"
        tail -3 /etc/captive-portal/allowed_macs.txt | sed 's/^/    /'
    fi
else
    echo -e "${YELLOW}⚠ Whitelist file not found${NC}"
fi

echo -e "\n${YELLOW}5. Service Status:${NC}"
for service in dnsmasq postgresql redis; do
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        echo -e "${RED}✗ $service is not running${NC}"
    fi
done

# Check Node.js app
if pgrep -f "node.*app.js" > /dev/null; then
    echo -e "${GREEN}✓ Node.js portal application is running${NC}"
else
    echo -e "${RED}✗ Portal application not running${NC}"
fi

echo -e "\n${YELLOW}6. Testing Captive Portal Detection Endpoints:${NC}"
for endpoint in "/generate_204" "/hotspot-detect.html" "/success.txt"; do
    if curl -s "http://10.1.50.140:3000$endpoint" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Endpoint $endpoint is responding${NC}"
    else
        echo -e "${RED}✗ Endpoint $endpoint not responding${NC}"
    fi
done

echo "========================================="
echo -e "${YELLOW}Test Instructions for Client Device:${NC}"
echo "1. Connect a device to the network"
echo "2. Try to browse http://google.com"
echo "3. You should be redirected to:"
echo "   ${GREEN}http://10.1.50.140:3000${NC}"
echo ""
echo "4. After registration, check whitelist:"
echo "   ${GREEN}sudo captive-whitelist list${NC}"
echo "========================================="