# WiFi Captive Portal - Testing Guide

## Current Status
✅ **RUNNING** - Server is active on port 3000
- Server IP: **10.1.50.103**
- Portal URL: **http://10.1.50.103:3000**

## Testing from Different Devices

### 1. Basic Web Browser Testing

From any device on the same network:

1. **Open a web browser** (Chrome, Firefox, Safari, etc.)
2. **Navigate to**: `http://10.1.50.103:3000`
3. **You should see**: The WiFi Access Portal splash page
4. **Fill out the form**:
   - **Name**: Your full name
   - **Squadron**: Your squadron designation
   - **Email**: Valid email address
   - **Check**: Terms of service checkbox
5. **Click**: "Connect to WiFi"
6. **Expected result**: Redirect to welcome page

### 2. Testing Different Endpoints

#### Registration Process
```
GET  http://10.1.50.103:3000/           → Shows splash page
POST http://10.1.50.103:3000/auth/register → Submits registration
GET  http://10.1.50.103:3000/welcome    → Welcome page after success
```

#### API Testing with curl
```bash
# Test splash page
curl http://10.1.50.103:3000/

# Test registration (replace with real data)
curl -X POST http://10.1.50.103:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test User", 
    "squadron": "Alpha Squadron", 
    "email": "test@example.com"
  }'

# Check authentication status
curl http://10.1.50.103:3000/auth/status
```

### 3. Mobile Device Testing

#### iPhone/iPad:
1. Connect to the same WiFi network
2. Open Safari
3. Go to `http://10.1.50.103:3000`
4. Test form submission and responsive design

#### Android:
1. Connect to the same WiFi network  
2. Open Chrome browser
3. Go to `http://10.1.50.103:3000`
4. Test form submission and responsive design

### 4. Network-level Testing

#### Different Network Segments:
- **Same subnet**: Direct access to `http://10.1.50.103:3000`
- **Different subnet**: May need routing/firewall configuration

#### WiFi Hotspot Testing:
1. Create a mobile hotspot
2. Connect the server to hotspot
3. Connect test device to same hotspot
4. Access portal via server's hotspot IP

### 5. Captive Portal Simulation

To simulate a real captive portal environment:

#### Option A: DNS Hijacking (Advanced)
```bash
# Redirect all HTTP traffic to portal (requires iptables/router config)
# This would be configured on the router/gateway
```

#### Option B: Manual Testing
1. **Block internet access** on test device
2. **Set portal as homepage** in browser
3. **Test registration flow**
4. **Verify session management**

### 6. Database Verification

Check if users are being registered:
```bash
# Connect to database
psql -d captive_portal

# View registered users
SELECT id, name, squadron, email, created_at FROM users;

# View active sessions
SELECT * FROM sessions WHERE expires_at > NOW();
```

### 7. Log Monitoring

Monitor application logs:
```bash
# View real-time logs
tail -f logs/combined.log

# View error logs
tail -f logs/error.log
```

### 8. Load Testing

Simple load test with curl:
```bash
# Multiple simultaneous requests
for i in {1..10}; do
  curl -X POST http://10.1.50.103:3000/auth/register \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"User$i\",\"squadron\":\"Test Squadron\",\"email\":\"user$i@test.com\"}" &
done
```

## Troubleshooting

### Common Issues:

1. **Can't connect to portal**:
   - Check server IP: `hostname -I`
   - Verify server is running: `ps aux | grep node`
   - Check firewall: `sudo ufw status`

2. **Form submission fails**:
   - Check browser console for errors
   - Verify database connection
   - Check Redis connection: `redis-cli ping`

3. **Database errors**:
   - Restart PostgreSQL: `sudo systemctl restart postgresql`
   - Check database exists: `psql -l | grep captive`

4. **Session issues**:
   - Restart Redis: `sudo systemctl restart redis-server`
   - Clear browser cookies

### Success Indicators:

✅ **Splash page loads correctly**
✅ **Form validation works**  
✅ **Registration creates database entry**
✅ **Session is created and maintained**
✅ **Welcome page shows after registration**
✅ **Responsive design works on mobile**

## Next Steps

After successful testing:
1. **Router Integration**: Configure actual router for captive portal
2. **HTTPS Setup**: Add SSL certificates for production
3. **Network Rules**: Implement iptables rules for traffic control
4. **Monitoring**: Set up proper logging and monitoring