#!/bin/bash

# Quick HTTPS Fix Script
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Fixing HTTPS setup...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

# Try to install nginx
echo -e "${YELLOW}Installing nginx...${NC}"
apt update
apt install -y nginx

# Check if nginx was installed
if ! command -v nginx &> /dev/null; then
    echo -e "${RED}Failed to install nginx${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Nginx installed successfully${NC}"

# Start and enable nginx
systemctl start nginx
systemctl enable nginx

# Create SSL directory
SSL_DIR="/etc/ssl/captive-portal"
mkdir -p $SSL_DIR

# Generate self-signed certificate
echo -e "${YELLOW}Generating SSL certificate...${NC}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $SSL_DIR/private.key \
    -out $SSL_DIR/certificate.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=portal.local"

chmod 600 $SSL_DIR/private.key
chmod 644 $SSL_DIR/certificate.crt

# Create nginx config
echo -e "${YELLOW}Creating nginx configuration...${NC}"
cat > /etc/nginx/sites-available/captive-portal << 'EOF'
# HTTP to HTTPS redirect
server {
    listen 80;
    server_name _;
    
    # Captive portal detection endpoints (must stay HTTP)
    location ~ ^/(generate_204|hotspot-detect\.html|library/test/success\.html|connecttest\.txt|ncsi\.txt)$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl;
    server_name _;
    
    ssl_certificate /etc/ssl/captive-portal/certificate.crt;
    ssl_certificate_key /etc/ssl/captive-portal/private.key;
    
    # Basic SSL config
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    
    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    
    # Proxy to Node.js
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/captive-portal /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test nginx config
nginx -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
    systemctl reload nginx
else
    echo -e "${RED}✗ Nginx configuration error${NC}"
    exit 1
fi

# Update firewall
echo -e "${YELLOW}Updating firewall...${NC}"
ufw allow 80/tcp
ufw allow 443/tcp

echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}  HTTPS Fix Complete!${NC}"
echo -e "${GREEN}===========================================${NC}"

echo -e "\n${YELLOW}Test URLs:${NC}"
echo "• HTTP: http://10.1.50.103 (should redirect to HTTPS)"
echo "• HTTPS: https://10.1.50.103 (main portal)"
echo "• Admin: https://10.1.50.103/admin"

echo -e "\n${YELLOW}Status Check:${NC}"
systemctl status nginx --no-pager -l
EOF