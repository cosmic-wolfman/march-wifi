#!/bin/bash

# WiFi Captive Portal Setup Script

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}WiFi Captive Portal Setup${NC}"
echo "=========================="

# Check Node.js version
echo -e "\n${YELLOW}Checking Node.js version...${NC}"
NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo -e "${RED}Error: Node.js version 18 or higher is required${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Node.js version is compatible${NC}"

# Install dependencies
echo -e "\n${YELLOW}Installing dependencies...${NC}"
npm install

# Create .env file if not exists
if [ ! -f .env ]; then
    echo -e "\n${YELLOW}Creating .env file...${NC}"
    cp .env.example .env
    echo -e "${GREEN}✓ Created .env file${NC}"
    echo -e "${YELLOW}Please edit .env file with your configuration${NC}"
fi

# Create logs directory
mkdir -p logs

# Check PostgreSQL
echo -e "\n${YELLOW}Checking PostgreSQL connection...${NC}"
if command -v psql &> /dev/null; then
    echo -e "${GREEN}✓ PostgreSQL is installed${NC}"
else
    echo -e "${RED}Warning: PostgreSQL not found. Please install PostgreSQL${NC}"
fi

# Check Redis
echo -e "\n${YELLOW}Checking Redis...${NC}"
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        echo -e "${GREEN}✓ Redis is running${NC}"
    else
        echo -e "${RED}Warning: Redis is not running. Please start Redis${NC}"
    fi
else
    echo -e "${RED}Warning: Redis not found. Please install Redis${NC}"
fi

echo -e "\n${GREEN}Setup complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Edit .env file with your configuration"
echo "2. Create PostgreSQL database: createdb captive_portal"
echo "3. Run database migrations: npm run db:migrate"
echo "4. Start development server: npm run dev"
echo -e "\n${YELLOW}For production deployment:${NC}"
echo "1. Install PM2: npm install -g pm2"
echo "2. Configure Nginx as reverse proxy"
echo "3. Set up SSL certificates"
echo "4. Configure router for captive portal"