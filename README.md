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

## Administrative Management

### System Control

The captive portal can be controlled using the `captive-portal-control.sh` script:

```bash
# Check current system status
./captive-portal-control.sh status

# Enable captive portal (require registration)
sudo ./captive-portal-control.sh enable

# Disable captive portal (allow normal internet)
sudo ./captive-portal-control.sh disable

# Pause portal temporarily (allow all traffic)
sudo ./captive-portal-control.sh pause

# Stop all portal services
sudo ./captive-portal-control.sh stop

# Start all portal services
sudo ./captive-portal-control.sh start
```

### Quick Installation

For complete captive portal setup with traffic interception:

```bash
# Run automated installer
sudo ./install-captive-portal.sh

# Test the installation
./test-captive.sh
```

### MAC Address Management

Manage device access using the whitelist system:

```bash
# Add a device to whitelist
sudo captive-whitelist add AA:BB:CC:DD:EE:FF

# Remove a device from whitelist
sudo captive-whitelist remove AA:BB:CC:DD:EE:FF

# List all whitelisted devices
sudo captive-whitelist list

# Reload whitelist from file
sudo captive-whitelist reload

# Clear all whitelisted devices
sudo ./captive-portal-control.sh clear-whitelist
```

### Admin Dashboard

Access the web-based admin interface:

- **URL**: http://10.1.50.140:3000/admin
- **Default Username**: admin
- **Default Password**: password (change immediately!)

Dashboard features:
- Real-time statistics and monitoring
- User management (search, filter, delete)
- Network monitoring (MAC addresses, DHCP leases)
- Analytics and usage patterns
- System logs and audit trails

### System Monitoring

```bash
# Complete system status check
sudo captive-status

# Monitor DNS queries in real-time
sudo tail -f /var/log/dnsmasq.log

# Watch portal application logs
tail -f logs/combined.log

# Check authentication attempts
tail -f logs/error.log | grep -i auth

# Monitor active connections
watch -n 1 'netstat -an | grep :3000'
```

### Service Management

Individual service control:

```bash
# PostgreSQL Database
sudo systemctl {start|stop|restart|status} postgresql

# Redis Session Store
sudo systemctl {start|stop|restart|status} redis

# DNS Service
sudo systemctl {start|stop|restart|status} dnsmasq

# Portal Application
npm run dev                    # Development
pm2 start config/pm2.config.js # Production
pm2 stop all                   # Stop application
```

### Troubleshooting

#### Portal Not Accessible
```bash
# Check if application is running
ps aux | grep node

# Verify port is listening
sudo netstat -tlpn | grep 3000

# Test locally
curl http://localhost:3000
```

#### DNS Not Redirecting
```bash
# Check dnsmasq status
sudo systemctl status dnsmasq

# Test DNS resolution
nslookup google.com 127.0.0.1

# Restart DNS service
sudo systemctl restart dnsmasq
```

#### Users Can't Access Internet After Registration
```bash
# Check if MAC was whitelisted
sudo captive-whitelist list | grep -i <MAC>

# Verify iptables rules
sudo iptables -L FORWARD -n -v

# Manually whitelist MAC
sudo captive-whitelist add <MAC>
```

### Backup and Recovery

#### Create Backup
```bash
# Backup database
pg_dump captive_portal > backup_$(date +%Y%m%d).sql

# Backup whitelist
cp /etc/captive-portal/allowed_macs.txt whitelist_backup.txt

# Backup configuration
tar -czf config_backup.tar.gz .env /etc/dnsmasq.d/captive-portal.conf
```

#### Restore from Backup
```bash
# Restore database
psql -d captive_portal < backup_20240113.sql

# Restore whitelist
sudo cp whitelist_backup.txt /etc/captive-portal/allowed_macs.txt
sudo captive-whitelist reload

# Restore configuration
tar -xzf config_backup.tar.gz
```

### Security Best Practices

1. **Change default admin password immediately**:
```bash
# Generate new password hash
node -e "console.log(require('bcryptjs').hashSync('NewSecurePassword', 10))"
# Update ADMIN_PASSWORD_HASH in .env
```

2. **Enable HTTPS for production**:
```bash
sudo ./scripts/setup-https.sh
```

3. **Regular security audits**:
```bash
# Check for suspicious MACs
sudo captive-whitelist list | sort | uniq -c | sort -rn

# Review recent registrations
psql -d captive_portal -c "SELECT * FROM users WHERE created_at > NOW() - INTERVAL '24 hours';"

# Check failed attempts
grep "Failed" logs/error.log | tail -20
```

4. **Update regularly**:
```bash
# System updates
sudo apt update && sudo apt upgrade

# Node.js dependencies
npm update && npm audit fix
```

### Network Configuration

Current setup:
- **Portal IP**: 10.1.50.140
- **Portal Port**: 3000
- **Network Interface**: eno1
- **Gateway**: 10.1.50.1

To modify network settings, edit `install-captive-portal.sh` and re-run installation.

### Maintenance Commands

```bash
# Clean old sessions (>30 days)
psql -d captive_portal -c "DELETE FROM sessions WHERE expires_at < NOW() - INTERVAL '30 days';"

# View disk usage
df -h
du -sh logs/

# Archive old logs
tar -czf logs_$(date +%Y%m%d).tar.gz logs/*.log
> logs/combined.log
> logs/error.log

# Database optimization
psql -d captive_portal -c "VACUUM ANALYZE;"
```

### Emergency Procedures

#### Disable Portal Immediately
```bash
# Quick disable - allows all traffic
sudo ./captive-portal-control.sh disable
```

#### Emergency Access (Temporary)
```bash
# Allow all traffic temporarily
sudo iptables -t nat -I PREROUTING 1 -j ACCEPT
sudo iptables -I FORWARD 1 -j ACCEPT

# Restore normal operation
sudo iptables-restore < /etc/iptables/rules.v4
```

#### Reset to Clean State
```bash
# Stop everything
sudo ./captive-portal-control.sh stop

# Clear sessions
redis-cli FLUSHALL

# Clear database (CAUTION!)
psql -d captive_portal -c "TRUNCATE users, sessions CASCADE;"

# Clear whitelist
sudo > /etc/captive-portal/allowed_macs.txt

# Restart
sudo ./captive-portal-control.sh start
```

### Documentation

- **Administrator Guide**: See `ADMINISTRATOR_GUIDE.md` for comprehensive management documentation
- **Setup Guide**: See `CAPTIVE_PORTAL_SETUP.md` for installation details
- **Phase 4 Features**: See `PHASE4_SETUP.md` for advanced features

## License

MIT