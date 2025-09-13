#!/bin/bash

# Service Setup Script for WiFi Captive Portal
# Run this script with sudo privileges

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

USER=$(logname 2>/dev/null || echo $SUDO_USER)
PROJECT_DIR="/home/$USER/local-projects/wifi-splash-page"

echo -e "${GREEN}Setting up PostgreSQL and Redis for Captive Portal${NC}"
echo "=================================================="

# Start and enable services
echo -e "\n${YELLOW}Starting services...${NC}"
systemctl start postgresql
systemctl start redis-server
systemctl enable postgresql
systemctl enable redis-server

echo -e "${GREEN}✓ Services started and enabled${NC}"

# Check service status
echo -e "\n${YELLOW}Checking service status...${NC}"
if systemctl is-active --quiet postgresql; then
    echo -e "${GREEN}✓ PostgreSQL is running${NC}"
else
    echo -e "${RED}✗ PostgreSQL failed to start${NC}"
    exit 1
fi

if systemctl is-active --quiet redis-server; then
    echo -e "${GREEN}✓ Redis is running${NC}"
else
    echo -e "${RED}✗ Redis failed to start${NC}"
    exit 1
fi

# Set up PostgreSQL user and database
echo -e "\n${YELLOW}Setting up PostgreSQL user and database...${NC}"

# Create user if it doesn't exist
sudo -u postgres psql -tc "SELECT 1 FROM pg_user WHERE usename = '$USER'" | grep -q 1 || \
sudo -u postgres psql -c "CREATE USER $USER WITH CREATEDB;"

echo -e "${GREEN}✓ PostgreSQL user '$USER' ready${NC}"

# Create database if it doesn't exist
sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'captive_portal'" | grep -q 1 || \
sudo -u postgres createdb captive_portal -O $USER

echo -e "${GREEN}✓ Database 'captive_portal' ready${NC}"

# Test database connection
echo -e "\n${YELLOW}Testing database connection...${NC}"
if sudo -u $USER psql -d captive_portal -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
    exit 1
fi

# Test Redis connection
echo -e "\n${YELLOW}Testing Redis connection...${NC}"
if redis-cli ping | grep -q PONG; then
    echo -e "${GREEN}✓ Redis connection successful${NC}"
else
    echo -e "${RED}✗ Redis connection failed${NC}"
    exit 1
fi

# Set proper permissions for logs directory
echo -e "\n${YELLOW}Setting up log directory...${NC}"
mkdir -p "$PROJECT_DIR/logs"
chown $USER:$USER "$PROJECT_DIR/logs"
chmod 755 "$PROJECT_DIR/logs"

echo -e "${GREEN}✓ Log directory configured${NC}"

echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "\n${YELLOW}Next steps (run as user $USER):${NC}"
echo "1. cd $PROJECT_DIR"
echo "2. npm run db:migrate"
echo "3. npm run dev"
echo -e "\n${YELLOW}Access the portal at:${NC} http://10.1.50.103:3000"