const { exec } = require('child_process');
const { promisify } = require('util');
const logger = require('./logger');

const execAsync = promisify(exec);

class NetworkManager {
  constructor() {
    this.whitelistFile = '/etc/captive-portal/allowed_macs.txt';
  }

  /**
   * Get MAC address from IP address using ARP table
   */
  async getMacFromIP(ipAddress) {
    try {
      const { stdout } = await execAsync(`arp -n ${ipAddress}`);
      const lines = stdout.split('\n');
      
      for (const line of lines) {
        if (line.includes(ipAddress)) {
          const parts = line.split(/\s+/);
          const macIndex = parts.findIndex(part => 
            /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/.test(part)
          );
          
          if (macIndex !== -1) {
            return parts[macIndex].toLowerCase();
          }
        }
      }
      
      logger.warn(`MAC address not found for IP: ${ipAddress}`);
      return null;
    } catch (error) {
      logger.error(`Error getting MAC address for IP ${ipAddress}:`, error);
      return null;
    }
  }

  /**
   * Get MAC address from DHCP leases
   */
  async getMacFromDHCP(ipAddress) {
    try {
      const { stdout } = await execAsync('cat /var/lib/dhcp/dhcpd.leases');
      const leases = this.parseDHCPLeases(stdout);
      
      const lease = leases.find(l => l.ip === ipAddress);
      return lease ? lease.mac.toLowerCase() : null;
    } catch (error) {
      logger.error(`Error reading DHCP leases for IP ${ipAddress}:`, error);
      return null;
    }
  }

  /**
   * Parse DHCP leases file
   */
  parseDHCPLeases(content) {
    const leases = [];
    const leaseBlocks = content.split('lease ').slice(1);
    
    for (const block of leaseBlocks) {
      const lines = block.split('\n');
      const ip = lines[0].trim().replace(/\s*{$/, '');
      
      let mac = null;
      let state = null;
      
      for (const line of lines) {
        const trimmed = line.trim();
        if (trimmed.startsWith('hardware ethernet')) {
          mac = trimmed.split(' ')[2].replace(';', '');
        }
        if (trimmed.startsWith('binding state')) {
          state = trimmed.split(' ')[2].replace(';', '');
        }
      }
      
      if (mac && state === 'active') {
        leases.push({ ip, mac: mac.toLowerCase() });
      }
    }
    
    return leases;
  }

  /**
   * Add MAC address to whitelist
   */
  async whitelistMac(macAddress) {
    try {
      const normalizedMac = macAddress.toLowerCase();
      
      // Validate MAC address format
      if (!/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(normalizedMac)) {
        throw new Error('Invalid MAC address format');
      }

      // Use the captive-whitelist script
      await execAsync(`captive-whitelist add ${normalizedMac}`);
      
      logger.info(`MAC address whitelisted: ${normalizedMac}`);
      return true;
    } catch (error) {
      logger.error(`Error whitelisting MAC ${macAddress}:`, error);
      throw error;
    }
  }

  /**
   * Remove MAC address from whitelist
   */
  async removeFromWhitelist(macAddress) {
    try {
      const normalizedMac = macAddress.toLowerCase();
      await execAsync(`captive-whitelist remove ${normalizedMac}`);
      
      logger.info(`MAC address removed from whitelist: ${normalizedMac}`);
      return true;
    } catch (error) {
      logger.error(`Error removing MAC ${macAddress} from whitelist:`, error);
      throw error;
    }
  }

  /**
   * Check if MAC address is whitelisted
   */
  async isWhitelisted(macAddress) {
    try {
      const { stdout } = await execAsync('captive-whitelist list');
      const normalizedMac = macAddress.toLowerCase();
      return stdout.toLowerCase().includes(normalizedMac);
    } catch (error) {
      logger.error(`Error checking whitelist status for MAC ${macAddress}:`, error);
      return false;
    }
  }

  /**
   * Get client MAC address from request
   */
  async getClientMac(req) {
    const clientIP = req.ip || req.connection.remoteAddress || req.socket.remoteAddress;
    
    // Try multiple methods to get MAC address
    let macAddress = null;
    
    // Method 1: Check custom header (if router provides it)
    if (req.headers['x-mac-address']) {
      macAddress = req.headers['x-mac-address'];
    }
    
    // Method 2: ARP table lookup
    if (!macAddress) {
      macAddress = await this.getMacFromIP(clientIP);
    }
    
    // Method 3: DHCP leases lookup
    if (!macAddress) {
      macAddress = await this.getMacFromDHCP(clientIP);
    }
    
    if (macAddress) {
      logger.info(`Found MAC address ${macAddress} for IP ${clientIP}`);
      return macAddress.toLowerCase();
    }
    
    logger.warn(`Could not determine MAC address for IP ${clientIP}`);
    return null;
  }

  /**
   * Grant network access to a user
   */
  async grantAccess(req, user) {
    try {
      const macAddress = await this.getClientMac(req);
      
      if (!macAddress) {
        throw new Error('Could not determine client MAC address');
      }

      // Update user record with MAC address
      if (user && user.id) {
        const db = require('../models/db');
        await db.updateUserMac(user.id, macAddress);
      }

      // Add to firewall whitelist
      await this.whitelistMac(macAddress);

      logger.info(`Network access granted to MAC: ${macAddress}`);
      return { success: true, macAddress };
    } catch (error) {
      logger.error('Error granting network access:', error);
      throw error;
    }
  }

  /**
   * Revoke network access
   */
  async revokeAccess(macAddress) {
    try {
      await this.removeFromWhitelist(macAddress);
      logger.info(`Network access revoked for MAC: ${macAddress}`);
      return { success: true };
    } catch (error) {
      logger.error('Error revoking network access:', error);
      throw error;
    }
  }

  /**
   * Get list of whitelisted MAC addresses
   */
  async getWhitelistedMacs() {
    try {
      const { stdout } = await execAsync('captive-whitelist list');
      const lines = stdout.split('\n').filter(line => line.trim());
      return lines.filter(line => /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i.test(line.trim()));
    } catch (error) {
      logger.error('Error getting whitelisted MACs:', error);
      return [];
    }
  }

  /**
   * Get current DHCP leases
   */
  async getDHCPLeases() {
    try {
      const { stdout } = await execAsync('cat /var/lib/dhcp/dhcpd.leases');
      return this.parseDHCPLeases(stdout);
    } catch (error) {
      logger.error('Error reading DHCP leases:', error);
      return [];
    }
  }

  /**
   * Get ARP table
   */
  async getARPTable() {
    try {
      const { stdout } = await execAsync('arp -a');
      const entries = [];
      const lines = stdout.split('\n');
      
      for (const line of lines) {
        const match = line.match(/\(([\d.]+)\) at ([a-f0-9:]{17})/i);
        if (match) {
          entries.push({
            ip: match[1],
            mac: match[2].toLowerCase(),
            interface: line.split(' ').pop()
          });
        }
      }
      
      return entries;
    } catch (error) {
      logger.error('Error reading ARP table:', error);
      return [];
    }
  }
}

module.exports = new NetworkManager();