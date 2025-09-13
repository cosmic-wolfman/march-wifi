# Captive Portal Network Architecture

## Overview
Transform the current registration portal into a full captive portal that controls network access through traffic interception and user authentication.

## Network Flow

```
Internet
   ↑
Router/Gateway (10.1.50.1)
   ↑
Portal Server (10.1.50.103)
   ↑
WiFi Clients → Authentication → Network Access
```

## Components

### 1. Traffic Interception Layer
- **iptables rules**: Redirect all HTTP/HTTPS traffic to portal
- **DNS hijacking**: Route all DNS queries through portal server
- **MAC address tracking**: Identify and whitelist authenticated devices

### 2. Authentication Flow
```
1. Client connects to WiFi
2. Client tries to browse → Redirected to portal
3. User fills registration form
4. Server validates and stores user data
5. MAC address added to whitelist
6. Client gets full internet access
```

### 3. Portal Server Responsibilities
- **Traffic routing**: iptables NAT rules
- **DNS server**: dnsmasq configuration
- **User management**: Registration and session handling
- **Access control**: MAC whitelist management

## Implementation Strategy

### Phase 3A: Network Infrastructure
1. **iptables configuration** for traffic interception
2. **dnsmasq setup** for DNS hijacking
3. **Network interface configuration**

### Phase 3B: Access Control
1. **MAC address whitelisting system**
2. **Session management integration**
3. **Automatic cleanup of expired sessions**

### Phase 3C: Portal Detection
1. **Captive portal detection endpoints** (iOS, Android, Windows)
2. **Automatic redirect logic**
3. **Browser compatibility testing**

## Network Configuration

### Required Services
- **iptables**: Traffic routing and NAT
- **dnsmasq**: DHCP and DNS services
- **hostapd**: WiFi access point (if needed)

### Firewall Rules Strategy
```bash
# Allow portal access
iptables -A INPUT -p tcp --dport 3000 -j ACCEPT

# Redirect HTTP to portal
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.1.50.103:3000

# DNS redirection
iptables -t nat -A PREROUTING -p udp --dport 53 -j DNAT --to-destination 10.1.50.103:53

# Allow authenticated MACs
iptables -A FORWARD -m mac --mac-source XX:XX:XX:XX:XX:XX -j ACCEPT
```

### DNS Configuration
```conf
# dnsmasq.conf
interface=wlan0
dhcp-range=10.1.50.50,10.1.50.150,12h
address=/#/10.1.50.103
```

## Security Considerations

### 1. Access Control
- MAC address spoofing protection
- Session timeout enforcement
- Rate limiting on authentication attempts

### 2. Network Security
- Isolated guest network
- No access to internal resources
- Logging of all network activity

### 3. Data Protection
- Encrypted user data storage
- Secure session management
- GDPR compliance considerations

## Implementation Files

### Scripts to Create
1. `scripts/setup-captive-portal.sh` - Full setup automation
2. `scripts/iptables-captive.sh` - Firewall configuration
3. `scripts/dnsmasq-config.sh` - DNS setup
4. `scripts/mac-whitelist.sh` - Access control management

### Code Changes
1. Enhanced authentication middleware
2. MAC address detection and storage
3. Network access management API
4. Captive portal detection endpoints

## Testing Strategy

### 1. Network Isolation Testing
- Verify traffic interception
- Test DNS redirection
- Confirm access control

### 2. Device Compatibility
- iOS captive portal detection
- Android network validation
- Windows network awareness

### 3. Load Testing
- Multiple simultaneous users
- Session management under load
- Network performance impact

## Deployment Considerations

### Production Environment
- Dedicated network interface for captive portal
- Separate VLAN for guest access
- Network monitoring and logging
- Backup and recovery procedures

### Hardware Requirements
- Network interface capable of promiscuous mode
- Sufficient bandwidth for all users
- Reliable power and network connectivity