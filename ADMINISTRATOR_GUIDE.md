# WiFi Captive Portal - Administrator Guide

## Table of Contents
1. [System Overview](#system-overview)
2. [Installation](#installation)
3. [Daily Operations](#daily-operations)
4. [User Management](#user-management)
5. [Network Management](#network-management)
6. [Monitoring & Logs](#monitoring--logs)
7. [Troubleshooting](#troubleshooting)
8. [Security Best Practices](#security-best-practices)
9. [Backup & Recovery](#backup--recovery)
10. [Command Reference](#command-reference)

---

## System Overview

### Architecture Components

The WiFi Captive Portal system consists of several integrated components:

| Component | Purpose | Port | Service |
|-----------|---------|------|---------|
| **Node.js Application** | Web portal interface | 3000 | `npm run dev` or PM2 |
| **PostgreSQL** | User database | 5432 | `postgresql` |
| **Redis** | Session management | 6379 | `redis-server` |
| **dnsmasq** | DNS hijacking | 53 | `dnsmasq` |
| **iptables** | Traffic control | N/A | Kernel module |

### Network Flow

```
1. Device connects to WiFi → Gets IP from DHCP
2. Device tries to browse → DNS redirects to portal
3. iptables intercepts traffic → Redirects to portal
4. User registers → MAC address captured
5. MAC whitelisted → Full internet access granted
```

---

## Installation

### Quick Installation

```bash
# 1. Make script executable
chmod +x install-captive-portal.sh

# 2. Run installation (requires sudo)
sudo ./install-captive-portal.sh

# 3. Start the application
cd /home/mlopez/gitprojects/march-wifi
npm run dev
```

### Post-Installation Checklist

- [ ] Verify all services are running: `sudo captive-status`
- [ ] Test DNS hijacking: `nslookup google.com 127.0.0.1`
- [ ] Check firewall rules: `sudo iptables -t nat -L -n`
- [ ] Verify portal access: `curl http://10.1.50.140:3000`
- [ ] Test with a client device

---

## Daily Operations

### Starting the System

```bash
# Start all services
sudo systemctl start postgresql redis dnsmasq
cd /home/mlopez/gitprojects/march-wifi
npm run dev

# Or use PM2 for production
pm2 start config/pm2.config.js --env production
```

### Stopping the System

```bash
# Stop application
pkill -f "node.*app.js"  # or pm2 stop all

# Stop services (optional)
sudo systemctl stop dnsmasq
```

### System Health Check

```bash
# Quick status check
sudo captive-status

# Detailed service status
sudo systemctl status dnsmasq postgresql redis
```

---

## User Management

### Via Admin Dashboard

1. **Access Admin Panel**: http://10.1.50.140:3000/admin
2. **Default Credentials**:
   - Username: `admin`
   - Password: `password` (change immediately!)

### Admin Dashboard Features

| Section | Functionality |
|---------|--------------|
| **Dashboard** | Overview statistics, recent registrations |
| **Users** | Search, filter, view all registered users |
| **Network** | View whitelisted MACs, active connections |
| **Analytics** | Usage patterns, growth trends |
| **Logs** | System events, audit trail |
| **Settings** | Configuration management |

### Via Command Line

```bash
# View all registered users
psql -d captive_portal -c "SELECT name, email, squadron, mac_address FROM users ORDER BY created_at DESC LIMIT 20;"

# Search for specific user
psql -d captive_portal -c "SELECT * FROM users WHERE email LIKE '%john%';"

# Delete a user
psql -d captive_portal -c "DELETE FROM users WHERE id = 123;"
```

---

## Network Management

### MAC Address Whitelisting

#### Add Device to Whitelist
```bash
# Add MAC address
sudo captive-whitelist add aa:bb:cc:dd:ee:ff

# Verify it was added
sudo captive-whitelist list
```

#### Remove Device from Whitelist
```bash
# Remove MAC address
sudo captive-whitelist remove aa:bb:cc:dd:ee:ff

# Verify removal
sudo iptables -t nat -L PREROUTING -n | grep -i aa:bb:cc
```

#### Bulk Operations
```bash
# Add multiple MACs from file
while read mac; do
    sudo captive-whitelist add "$mac"
done < mac_list.txt

# Export current whitelist
sudo captive-whitelist list > whitelist_backup.txt
```

### Finding Device MAC Addresses

```bash
# From ARP cache
arp -a | grep 10.1.50

# From DHCP leases (if using DHCP)
cat /var/lib/dhcp/dhcpd.leases | grep "hardware ethernet"

# From connected devices
sudo nmap -sn 10.1.50.0/24
```

### Emergency Access

```bash
# Temporarily allow all traffic (EMERGENCY ONLY)
sudo iptables -t nat -I PREROUTING 1 -j ACCEPT
sudo iptables -I FORWARD 1 -j ACCEPT

# Restore normal operation
sudo iptables-restore < /etc/iptables/rules.v4
```

---

## Monitoring & Logs

### Real-time Monitoring

```bash
# Watch DNS queries
sudo tail -f /var/log/dnsmasq.log

# Monitor portal access
tail -f logs/combined.log

# Watch authentication attempts
tail -f logs/error.log | grep -i auth

# Monitor active connections
watch -n 1 'netstat -an | grep :3000'
```

### Log Locations

| Log File | Content | Location |
|----------|---------|----------|
| Portal Application | Access, errors | `logs/combined.log` |
| DNS Queries | All DNS lookups | `/var/log/dnsmasq.log` |
| System Events | Whitelist changes | `/var/log/captive-portal.log` |
| PostgreSQL | Database queries | `/var/log/postgresql/*.log` |
| Nginx (if used) | Web server logs | `/var/log/nginx/*.log` |

### Performance Monitoring

```bash
# Check system resources
htop

# Monitor network traffic
sudo iftop -i eno1

# Database connections
psql -d captive_portal -c "SELECT count(*) FROM pg_stat_activity;"

# Redis memory usage
redis-cli INFO memory
```

---

## Troubleshooting

### Common Issues and Solutions

#### Portal Not Accessible

```bash
# 1. Check if application is running
ps aux | grep node

# 2. Verify port is listening
sudo netstat -tlpn | grep 3000

# 3. Check firewall allows access
sudo iptables -L INPUT -n | grep 3000

# 4. Test locally
curl http://localhost:3000
```

#### DNS Not Redirecting

```bash
# 1. Check dnsmasq is running
sudo systemctl status dnsmasq

# 2. Verify DNS configuration
grep "address=" /etc/dnsmasq.d/captive-portal.conf

# 3. Test DNS resolution
nslookup google.com 10.1.50.140

# 4. Restart dnsmasq
sudo systemctl restart dnsmasq
```

#### Users Can't Access Internet After Registration

```bash
# 1. Check if MAC was whitelisted
sudo captive-whitelist list | grep -i <user_mac>

# 2. Verify iptables rules
sudo iptables -L FORWARD -n -v | grep -i <user_mac>

# 3. Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# 4. Manually whitelist MAC
sudo captive-whitelist add <user_mac>
```

#### Database Connection Issues

```bash
# 1. Check PostgreSQL is running
sudo systemctl status postgresql

# 2. Test connection
psql -U postgres -d captive_portal -c "SELECT 1;"

# 3. Check connection settings
grep DATABASE_URL .env

# 4. Restart PostgreSQL
sudo systemctl restart postgresql
```

### Reset Procedures

#### Clear All Whitelisted MACs
```bash
# Backup current list
sudo captive-whitelist list > mac_backup.txt

# Clear whitelist file
sudo > /etc/captive-portal/allowed_macs.txt

# Remove all MAC rules from iptables
sudo iptables-save | grep -v "mac-source" | sudo iptables-restore
```

#### Reset Portal to Clean State
```bash
# 1. Stop application
pkill -f "node.*app.js"

# 2. Clear sessions
redis-cli FLUSHALL

# 3. Clear database (CAUTION!)
psql -d captive_portal -c "TRUNCATE users, sessions CASCADE;"

# 4. Clear whitelist
sudo > /etc/captive-portal/allowed_macs.txt

# 5. Restart everything
sudo systemctl restart postgresql redis dnsmasq
npm run dev
```

---

## Security Best Practices

### 1. Change Default Credentials

```bash
# Generate new admin password hash
node -e "console.log(require('bcryptjs').hashSync('YourNewSecurePassword', 10))"

# Update .env file
ADMIN_USERNAME=your_admin_user
ADMIN_PASSWORD_HASH=<generated_hash>
```

### 2. Enable HTTPS

```bash
# Run HTTPS setup script
sudo ./scripts/setup-https.sh

# Or manually with Let's Encrypt
sudo certbot --nginx -d your-domain.com
```

### 3. Regular Security Audits

```bash
# Check for suspicious MACs
sudo captive-whitelist list | sort | uniq -c | sort -rn

# Review recent registrations
psql -d captive_portal -c "SELECT * FROM users WHERE created_at > NOW() - INTERVAL '24 hours';"

# Check failed login attempts
grep "Failed" logs/error.log | tail -20
```

### 4. Firewall Hardening

```bash
# Limit SSH access to specific IP
sudo iptables -I INPUT -p tcp --dport 22 -s YOUR_ADMIN_IP -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 22 -j DROP

# Rate limit portal access
sudo iptables -I INPUT -p tcp --dport 3000 -m limit --limit 10/min -j ACCEPT
```

### 5. Regular Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade

# Update Node.js dependencies
npm update
npm audit fix

# Check for security advisories
npm audit
```

---

## Backup & Recovery

### Automated Backups

Create a backup script (`/usr/local/bin/captive-backup`):

```bash
#!/bin/bash
BACKUP_DIR="/backup/captive-portal"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup database
pg_dump captive_portal > "$BACKUP_DIR/database_$DATE.sql"

# Backup whitelist
cp /etc/captive-portal/allowed_macs.txt "$BACKUP_DIR/whitelist_$DATE.txt"

# Backup configuration
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
    /home/mlopez/gitprojects/march-wifi/.env \
    /etc/dnsmasq.d/captive-portal.conf \
    /etc/iptables/rules.v4

# Keep only last 30 days
find "$BACKUP_DIR" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/*_$DATE.*"
```

### Schedule Automated Backups

```bash
# Add to crontab
sudo crontab -e

# Daily backup at 2 AM
0 2 * * * /usr/local/bin/captive-backup
```

### Recovery Procedures

```bash
# Restore database
psql -d captive_portal < /backup/captive-portal/database_20240113_020000.sql

# Restore whitelist
cp /backup/captive-portal/whitelist_20240113_020000.txt /etc/captive-portal/allowed_macs.txt
sudo captive-whitelist reload

# Restore configuration
tar -xzf /backup/captive-portal/config_20240113_020000.tar.gz -C /
```

---

## Command Reference

### Essential Commands

| Command | Description | Example |
|---------|-------------|---------|
| `captive-status` | System health check | `sudo captive-status` |
| `captive-whitelist add` | Add MAC to whitelist | `sudo captive-whitelist add aa:bb:cc:dd:ee:ff` |
| `captive-whitelist remove` | Remove MAC | `sudo captive-whitelist remove aa:bb:cc:dd:ee:ff` |
| `captive-whitelist list` | Show all whitelisted MACs | `sudo captive-whitelist list` |
| `captive-whitelist reload` | Reload MACs from file | `sudo captive-whitelist reload` |

### Service Management

```bash
# Start services
sudo systemctl start dnsmasq postgresql redis

# Stop services
sudo systemctl stop dnsmasq postgresql redis

# Restart services
sudo systemctl restart dnsmasq postgresql redis

# Check status
sudo systemctl status dnsmasq postgresql redis

# Enable auto-start
sudo systemctl enable dnsmasq postgresql redis
```

### Database Queries

```bash
# Connect to database
psql -d captive_portal

# Useful queries
SELECT COUNT(*) FROM users;                           # Total users
SELECT * FROM users ORDER BY created_at DESC LIMIT 10; # Recent users
SELECT squadron, COUNT(*) FROM users GROUP BY squadron; # Users by squadron
DELETE FROM sessions WHERE expires_at < NOW();         # Clean old sessions
```

### Network Diagnostics

```bash
# Check firewall rules
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# Monitor traffic
sudo tcpdump -i eno1 port 3000
sudo tcpdump -i eno1 port 53

# Test connectivity
ping 10.1.50.140
curl http://10.1.50.140:3000
nslookup google.com 10.1.50.140
```

---

## Maintenance Schedule

### Daily Tasks
- [ ] Check system status: `sudo captive-status`
- [ ] Review error logs: `tail -100 logs/error.log`
- [ ] Monitor disk space: `df -h`

### Weekly Tasks
- [ ] Review user registrations
- [ ] Check for unusual activity in logs
- [ ] Update whitelist documentation
- [ ] Test backup restoration

### Monthly Tasks
- [ ] Security updates: `sudo apt update && sudo apt upgrade`
- [ ] Clean old sessions: `psql -d captive_portal -c "DELETE FROM sessions WHERE expires_at < NOW() - INTERVAL '30 days';"`
- [ ] Archive old logs
- [ ] Review and optimize database

### Annual Tasks
- [ ] Full security audit
- [ ] Update SSL certificates
- [ ] Review and update documentation
- [ ] Disaster recovery drill

---

## Support Information

### Log Files for Debugging
- Application logs: `/home/mlopez/gitprojects/march-wifi/logs/`
- DNS logs: `/var/log/dnsmasq.log`
- System logs: `/var/log/syslog`
- Portal action logs: `/var/log/captive-portal.log`

### Configuration Files
- Application config: `/home/mlopez/gitprojects/march-wifi/.env`
- DNS config: `/etc/dnsmasq.d/captive-portal.conf`
- Firewall rules: `/etc/iptables/rules.v4`
- Whitelist: `/etc/captive-portal/allowed_macs.txt`

### Getting Help
1. Check this guide first
2. Review logs for error messages
3. Run `sudo captive-status` for quick diagnostics
4. Check service status with `systemctl status <service>`

---

*Last Updated: January 2025*
*Version: 1.0*