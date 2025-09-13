#!/bin/bash

# HTTPS Setup Script for Captive Portal
# Configures SSL certificates and HTTPS redirection

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAIN="portal.local"
PORTAL_IP="10.1.50.103"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/ssl/captive-portal"

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  HTTPS Setup for Captive Portal${NC}"
echo -e "${BLUE}===========================================${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root (use sudo)${NC}"
   exit 1
fi

echo -e "\n${YELLOW}Configuration:${NC}"
echo -e "Domain: ${DOMAIN}"
echo -e "Portal IP: ${PORTAL_IP}"
echo -e "SSL Directory: ${SSL_DIR}"

read -p "Continue with HTTPS setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Install required packages
echo -e "\n${YELLOW}Installing required packages...${NC}"
apt update
apt install -y nginx openssl

# Create SSL directory
echo -e "\n${YELLOW}Creating SSL directory...${NC}"
mkdir -p $SSL_DIR

# Generate self-signed certificate for local development
echo -e "\n${YELLOW}Generating self-signed SSL certificate...${NC}"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $SSL_DIR/private.key \
    -out $SSL_DIR/certificate.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=$DOMAIN/emailAddress=admin@$DOMAIN"

# Set proper permissions
chmod 600 $SSL_DIR/private.key
chmod 644 $SSL_DIR/certificate.crt

# Create nginx configuration
echo -e "\n${YELLOW}Creating nginx configuration...${NC}"
cat > $NGINX_AVAILABLE/captive-portal << EOF
# Captive Portal HTTPS Configuration

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN $PORTAL_IP;
    
    # Captive portal detection endpoints (must be HTTP)
    location ~ ^/(generate_204|hotspot-detect\.html|library/test/success\.html|connecttest\.txt|ncsi\.txt)$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN $PORTAL_IP;
    
    # SSL Configuration
    ssl_certificate $SSL_DIR/certificate.crt;
    ssl_certificate_key $SSL_DIR/private.key;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Proxy to Node.js application
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support (for future features)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    # Static assets caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_cache_valid 200 1h;
        add_header Cache-Control "public, max-age=3600";
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000;
        access_log off;
    }
}
EOF

# Enable the site
echo -e "\n${YELLOW}Enabling nginx site...${NC}"
ln -sf $NGINX_AVAILABLE/captive-portal $NGINX_ENABLED/captive-portal

# Remove default nginx site
rm -f $NGINX_ENABLED/default

# Test nginx configuration
echo -e "\n${YELLOW}Testing nginx configuration...${NC}"
nginx -t

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Nginx configuration is valid${NC}"
else
    echo -e "${RED}✗ Nginx configuration error${NC}"
    exit 1
fi

# Update firewall rules for HTTPS
echo -e "\n${YELLOW}Updating firewall rules...${NC}"

# Allow HTTPS traffic
iptables -I INPUT -p tcp --dport 443 -j ACCEPT

# Update captive portal redirection for HTTPS
iptables -t nat -I PREROUTING -i eno1 -p tcp --dport 443 -j DNAT --to-destination $PORTAL_IP:443

# Save iptables rules
iptables-save > /etc/iptables/rules.v4

# Update dnsmasq for HTTPS redirection
echo -e "\n${YELLOW}Updating dnsmasq configuration...${NC}"
sed -i '/^address=\/#\//d' /etc/dnsmasq.conf
echo "address=/#/$PORTAL_IP" >> /etc/dnsmasq.conf

# Restart services
echo -e "\n${YELLOW}Restarting services...${NC}"
systemctl restart nginx
systemctl restart dnsmasq

# Create Let's Encrypt setup script for production
echo -e "\n${YELLOW}Creating Let's Encrypt setup script...${NC}"
cat > /usr/local/bin/setup-letsencrypt << 'EOF'
#!/bin/bash

# Let's Encrypt SSL Certificate Setup
# For production use with a real domain

DOMAIN="$1"
EMAIL="$2"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "Usage: $0 <domain> <email>"
    echo "Example: $0 portal.company.com admin@company.com"
    exit 1
fi

# Install certbot
apt update
apt install -y certbot python3-certbot-nginx

# Get certificate
certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive

# Set up auto-renewal
echo "0 12 * * * /usr/bin/certbot renew --quiet" | crontab -

echo "Let's Encrypt certificate installed for $DOMAIN"
echo "Auto-renewal configured"
EOF

chmod +x /usr/local/bin/setup-letsencrypt

# Create certificate renewal script
cat > /usr/local/bin/renew-certificates << 'EOF'
#!/bin/bash

# Manual certificate renewal script
certbot renew --nginx --quiet

# Restart nginx if certificates were renewed
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "Certificates renewed and nginx reloaded"
fi
EOF

chmod +x /usr/local/bin/renew-certificates

# Update portal application for HTTPS
echo -e "\n${YELLOW}Updating portal application for production...${NC}"

# Update environment variables
cat >> /home/$(logname)/local-projects/wifi-splash-page/.env << EOF

# HTTPS Configuration
HTTPS_ENABLED=true
SSL_CERT_PATH=$SSL_DIR/certificate.crt
SSL_KEY_PATH=$SSL_DIR/private.key
PORTAL_URL=https://$PORTAL_IP
EOF

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}  HTTPS Setup Complete!${NC}"
echo -e "${GREEN}===========================================${NC}"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Restart your Node.js application"
echo "2. Access portal via: https://$PORTAL_IP"
echo "3. For production with real domain: setup-letsencrypt your-domain.com admin@your-domain.com"

echo -e "\n${YELLOW}Important Notes:${NC}"
echo "• Self-signed certificate will show browser warning (normal for development)"
echo "• Captive portal detection endpoints remain on HTTP (required)"
echo "• HTTPS enforced for all user-facing pages"
echo "• SSL certificate valid for 365 days"

echo -e "\n${YELLOW}Management Commands:${NC}"
echo "• Renew certificates: renew-certificates"
echo "• Setup Let's Encrypt: setup-letsencrypt domain.com email@domain.com"
echo "• Check nginx status: systemctl status nginx"
echo "• View nginx logs: journalctl -u nginx -f"

echo -e "\n${BLUE}Portal URLs:${NC}"
echo "• HTTP (redirects): http://$PORTAL_IP"
echo "• HTTPS (main): https://$PORTAL_IP"
echo "• Admin (coming next): https://$PORTAL_IP/admin"