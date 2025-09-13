# WiFi Captive Portal

A production-ready captive portal system for WiFi authentication with user registration and session management.

## Features

- User registration with name, squadron, and email
- Session management with Redis
- PostgreSQL database for user data
- Rate limiting and security features
- Responsive splash page design
- Production-ready with PM2 process management
- Comprehensive logging with Winston

## Prerequisites

- Node.js >= 18.0.0
- PostgreSQL
- Redis
- Nginx (for production)

## Installation

1. Clone the repository:
```bash
cd /opt
git clone <repository-url> captive-portal
cd captive-portal
```

2. Install dependencies:
```bash
npm install
```

3. Set up environment variables:
```bash
cp .env.example .env
# Edit .env with your configuration
```

4. Set up the database:
```bash
# Create the database
createdb captive_portal

# Run migrations
npm run db:migrate

# (Optional) Seed with test data
npm run db:seed
```

5. Start the development server:
```bash
npm run dev
```

## Production Deployment

1. Install PM2 globally:
```bash
npm install -g pm2
```

2. Start the application:
```bash
pm2 start config/pm2.config.js --env production
```

3. Save PM2 configuration:
```bash
pm2 save
pm2 startup
```

## Router Configuration

To integrate with your router:

1. Configure DNS to redirect all requests to the portal server
2. Set up iptables rules (see `scripts/iptables-setup.sh`)
3. Configure MAC address whitelisting after successful authentication

## API Endpoints

- `POST /auth/register` - User registration
- `POST /auth/logout` - User logout
- `GET /auth/status` - Authentication status
- `GET /api/users/current` - Get current user info
- `GET /api/users/stats` - Get usage statistics

## Security Features

- HTTPS with Let's Encrypt (production)
- Helmet.js for security headers
- Rate limiting on authentication endpoints
- Input validation and sanitization
- CSRF protection
- Session timeout (30 minutes)

## Monitoring

Logs are stored in the `logs/` directory:
- `error.log` - Error logs only
- `combined.log` - All logs
- `pm2-*.log` - PM2 process logs

## License

MIT