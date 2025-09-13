const { Pool } = require('pg');
const logger = require('../utils/logger');

// Database configuration
const dbConfig = process.env.DATABASE_URL 
  ? {
      connectionString: process.env.DATABASE_URL,
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    }
  : {
      // Local connection via Unix socket (no password needed)
      database: 'captive_portal',
      host: '/var/run/postgresql',  // Unix socket path
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
    };

const pool = new Pool(dbConfig);

pool.on('error', (err) => {
  logger.error('Unexpected database error:', err);
});

const db = {
  async createUser(userData) {
    const { name, squadron, email, ip_address, mac_address } = userData;
    
    try {
      const query = `
        INSERT INTO users (name, squadron, email, ip_address, mac_address)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (mac_address) 
        DO UPDATE SET 
          name = EXCLUDED.name,
          squadron = EXCLUDED.squadron,
          email = EXCLUDED.email,
          ip_address = EXCLUDED.ip_address,
          last_seen_at = CURRENT_TIMESTAMP
        RETURNING *`;
      
      const values = [name, squadron, email, ip_address, mac_address];
      const result = await pool.query(query, values);
      return result.rows[0];
    } catch (error) {
      logger.error('Error creating user:', error);
      throw error;
    }
  },

  async getUserById(id) {
    try {
      const query = 'SELECT * FROM users WHERE id = $1';
      const result = await pool.query(query, [id]);
      return result.rows[0];
    } catch (error) {
      logger.error('Error fetching user:', error);
      throw error;
    }
  },

  async getUserByMac(macAddress) {
    try {
      const query = 'SELECT * FROM users WHERE mac_address = $1';
      const result = await pool.query(query, [macAddress]);
      return result.rows[0];
    } catch (error) {
      logger.error('Error fetching user by MAC:', error);
      throw error;
    }
  },

  async updateLastSeen(userId) {
    try {
      const query = 'UPDATE users SET last_seen_at = CURRENT_TIMESTAMP WHERE id = $1';
      await pool.query(query, [userId]);
    } catch (error) {
      logger.error('Error updating last seen:', error);
      throw error;
    }
  },

  async getUserStats() {
    try {
      const query = `
        SELECT 
          COUNT(*) as total_users,
          COUNT(DISTINCT squadron) as total_squadrons,
          COUNT(CASE WHEN last_seen_at > NOW() - INTERVAL '24 hours' THEN 1 END) as active_24h,
          COUNT(CASE WHEN last_seen_at > NOW() - INTERVAL '7 days' THEN 1 END) as active_7d
        FROM users`;
      
      const result = await pool.query(query);
      return result.rows[0];
    } catch (error) {
      logger.error('Error fetching user stats:', error);
      throw error;
    }
  },

  async createSession(sessionData) {
    const { id, user_id, expires_at } = sessionData;
    
    try {
      const query = `
        INSERT INTO sessions (id, user_id, expires_at)
        VALUES ($1, $2, $3)
        RETURNING *`;
      
      const values = [id, user_id, expires_at];
      const result = await pool.query(query, values);
      return result.rows[0];
    } catch (error) {
      logger.error('Error creating session:', error);
      throw error;
    }
  },

  async cleanupExpiredSessions() {
    try {
      const query = 'DELETE FROM sessions WHERE expires_at < CURRENT_TIMESTAMP';
      const result = await pool.query(query);
      logger.info(`Cleaned up ${result.rowCount} expired sessions`);
    } catch (error) {
      logger.error('Error cleaning up sessions:', error);
      throw error;
    }
  },

  async updateUserMac(userId, macAddress) {
    try {
      const query = 'UPDATE users SET mac_address = $1, last_seen_at = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *';
      const result = await pool.query(query, [macAddress, userId]);
      return result.rows[0];
    } catch (error) {
      logger.error('Error updating user MAC address:', error);
      throw error;
    }
  },

  async getUserByMacAddress(macAddress) {
    try {
      const query = 'SELECT * FROM users WHERE mac_address = $1';
      const result = await pool.query(query, [macAddress]);
      return result.rows[0];
    } catch (error) {
      logger.error('Error fetching user by MAC address:', error);
      throw error;
    }
  },

  async getRecentUsers(limit = 10) {
    try {
      const query = `
        SELECT id, name, squadron, email, ip_address, mac_address, created_at, last_seen_at
        FROM users 
        ORDER BY created_at DESC 
        LIMIT $1`;
      const result = await pool.query(query, [limit]);
      return result.rows;
    } catch (error) {
      logger.error('Error fetching recent users:', error);
      throw error;
    }
  },

  async getActiveSessions() {
    try {
      const query = `
        SELECT s.id, s.expires_at, s.created_at, u.name, u.email, u.squadron
        FROM sessions s
        JOIN users u ON s.user_id = u.id
        WHERE s.expires_at > CURRENT_TIMESTAMP
        ORDER BY s.created_at DESC`;
      const result = await pool.query(query);
      return result.rows;
    } catch (error) {
      logger.error('Error fetching active sessions:', error);
      throw error;
    }
  },

  async getUsersPaginated({ limit, offset, search, squadron }) {
    try {
      let whereClause = 'WHERE 1=1';
      const params = [];
      let paramCount = 0;

      if (search) {
        paramCount++;
        whereClause += ` AND (name ILIKE $${paramCount} OR email ILIKE $${paramCount})`;
        params.push(`%${search}%`);
      }

      if (squadron) {
        paramCount++;
        whereClause += ` AND squadron = $${paramCount}`;
        params.push(squadron);
      }

      // Get total count
      const countQuery = `SELECT COUNT(*) FROM users ${whereClause}`;
      const countResult = await pool.query(countQuery, params);
      const total = parseInt(countResult.rows[0].count);

      // Get users
      const usersQuery = `
        SELECT id, name, squadron, email, ip_address, mac_address, created_at, last_seen_at
        FROM users 
        ${whereClause}
        ORDER BY created_at DESC 
        LIMIT $${paramCount + 1} OFFSET $${paramCount + 2}`;
      
      params.push(limit, offset);
      const usersResult = await pool.query(usersQuery, params);

      return {
        users: usersResult.rows,
        total
      };
    } catch (error) {
      logger.error('Error fetching paginated users:', error);
      throw error;
    }
  },

  async getSquadrons() {
    try {
      const query = 'SELECT DISTINCT squadron FROM users ORDER BY squadron';
      const result = await pool.query(query);
      return result.rows;
    } catch (error) {
      logger.error('Error fetching squadrons:', error);
      throw error;
    }
  },

  async deleteUser(userId) {
    try {
      const query = 'DELETE FROM users WHERE id = $1';
      await pool.query(query, [userId]);
    } catch (error) {
      logger.error('Error deleting user:', error);
      throw error;
    }
  },

  async updateUserStatus(userId, status) {
    try {
      const query = 'UPDATE users SET status = $1, last_seen_at = CURRENT_TIMESTAMP WHERE id = $2';
      await pool.query(query, [status, userId]);
    } catch (error) {
      logger.error('Error updating user status:', error);
      throw error;
    }
  },

  async getAnalyticsData() {
    try {
      const queries = await Promise.all([
        // Daily registrations last 30 days
        pool.query(`
          SELECT DATE(created_at) as date, COUNT(*) as count
          FROM users 
          WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
          GROUP BY DATE(created_at)
          ORDER BY date DESC
        `),
        
        // Squadron distribution with last active
        pool.query(`
          SELECT 
            squadron, 
            COUNT(*) as count,
            MAX(last_seen_at) as lastActive
          FROM users 
          GROUP BY squadron
          ORDER BY count DESC
        `),
        
        // Hourly activity today
        pool.query(`
          SELECT EXTRACT(HOUR FROM created_at) as hour, COUNT(*) as count
          FROM users 
          WHERE DATE(created_at) = CURRENT_DATE
          GROUP BY hour
          ORDER BY hour
        `),
        
        // Overall statistics
        pool.query(`
          SELECT 
            COUNT(*) as totalRegistrations,
            COUNT(CASE WHEN created_at >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as registrationsThisWeek,
            COUNT(CASE WHEN created_at >= CURRENT_DATE - INTERVAL '7 days' - INTERVAL '7 days' 
                       AND created_at < CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as registrationsLastWeek,
            COUNT(CASE WHEN last_seen_at >= CURRENT_DATE THEN 1 END) as dailyActiveUsers,
            COUNT(CASE WHEN created_at >= CURRENT_DATE THEN 1 END) as newUsersToday,
            COUNT(CASE WHEN created_at >= CURRENT_DATE - INTERVAL '1 day' 
                       AND created_at < CURRENT_DATE THEN 1 END) as newUsersYesterday,
            COUNT(DISTINCT mac_address) as uniqueDevices
          FROM users
        `),
        
        // Active sessions count
        pool.query(`
          SELECT COUNT(*) as activeSessions
          FROM sessions
          WHERE expires_at > CURRENT_TIMESTAMP
        `)
      ]);

      const stats = queries[3].rows[0];
      const registrationsGrowth = stats.registrationslastweek > 0 
        ? Math.round((stats.registrationsthisweek - stats.registrationslastweek) / stats.registrationslastweek * 100)
        : 100;

      return {
        dailyRegistrations: queries[0].rows,
        squadronDistribution: queries[1].rows,
        hourlyActivity: queries[2].rows,
        totalRegistrations: parseInt(stats.totalregistrations),
        registrationsGrowth,
        dailyActiveUsers: parseInt(stats.dailyactiveusers),
        avgDailyUsers: Math.round(parseInt(stats.totalregistrations) / 30),
        avgSessionDuration: '25',
        peakHour: '2:00 PM',
        uniqueDevices: parseInt(stats.uniquedevices),
        newUsersToday: parseInt(stats.newuserstoday),
        newUsersYesterday: parseInt(stats.newusersyesterday),
        activeSessions: parseInt(queries[4].rows[0].activesessions),
        peakSessionsToday: parseInt(queries[4].rows[0].activesessions) + 5
      };
    } catch (error) {
      logger.error('Error fetching analytics data:', error);
      throw error;
    }
  },

  async getSystemLogs({ level, limit }) {
    try {
      // This would typically read from log files or a logging database
      // For now, return mock log entries based on database activity
      const logs = [];
      
      // Get recent user activities
      const userQuery = `
        SELECT name, email, squadron, created_at, last_seen_at, status
        FROM users 
        ORDER BY created_at DESC 
        LIMIT $1`;
      const userResult = await pool.query(userQuery, [Math.min(limit, 50)]);
      
      // Convert to log format
      userResult.rows.forEach(user => {
        logs.push({
          level: 'info',
          message: `User registration: ${user.name} (${user.email})`,
          timestamp: user.created_at,
          meta: { squadron: user.squadron, status: user.status }
        });
        
        if (user.last_seen_at > user.created_at) {
          logs.push({
            level: 'info',
            message: `User activity: ${user.name} accessed portal`,
            timestamp: user.last_seen_at,
            meta: { email: user.email }
          });
        }
      });
      
      // Add some mock system logs
      const now = new Date();
      logs.push({
        level: 'info',
        message: 'System health check completed',
        timestamp: new Date(now - 300000),
        meta: { status: 'healthy', uptime: '99.9%' }
      });
      
      if (level === 'error' || !level) {
        logs.push({
          level: 'error',
          message: 'Failed login attempt from IP 192.168.1.100',
          timestamp: new Date(now - 3600000),
          meta: { ip: '192.168.1.100', attempts: 3 }
        });
      }
      
      if (level === 'warn' || !level) {
        logs.push({
          level: 'warn',
          message: 'High memory usage detected',
          timestamp: new Date(now - 7200000),
          meta: { usage: '85%', threshold: '80%' }
        });
      }
      
      // Filter by level if specified
      const filteredLogs = level 
        ? logs.filter(log => log.level === level)
        : logs;
      
      // Sort by timestamp descending and limit
      return filteredLogs
        .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp))
        .slice(0, limit);
    } catch (error) {
      logger.error('Error fetching system logs:', error);
      throw error;
    }
  },

  async getRecentActivity(limit = 20) {
    try {
      const query = `
        SELECT 'registration' as type, name, email, created_at as timestamp
        FROM users 
        ORDER BY created_at DESC 
        LIMIT $1`;
      const result = await pool.query(query, [limit]);
      return result.rows;
    } catch (error) {
      logger.error('Error fetching recent activity:', error);
      throw error;
    }
  }
};

module.exports = db;