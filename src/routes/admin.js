const express = require('express');
const { body, validationResult, query } = require('express-validator');
const bcrypt = require('bcryptjs');
const logger = require('../utils/logger');
const db = require('../models/db');
const networkManager = require('../utils/network');

const router = express.Router();

// Admin authentication middleware
const requireAdmin = async (req, res, next) => {
  if (!req.session.isAdmin) {
    return res.redirect('/admin/login');
  }
  next();
};

// Root admin route - redirect to login or dashboard
router.get('/', (req, res) => {
  if (req.session.isAdmin) {
    return res.redirect('/admin/dashboard');
  }
  res.redirect('/admin/login');
});

// Admin login page
router.get('/login', (req, res) => {
  if (req.session.isAdmin) {
    return res.redirect('/admin/dashboard');
  }
  
  res.render('admin/login', {
    title: 'Admin Login',
    error: req.query.error || null
  });
});

// Admin login handler
router.post('/login', [
  body('username').trim().notEmpty(),
  body('password').notEmpty()
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.redirect('/admin/login?error=Invalid credentials');
    }

    const { username, password } = req.body;
    
    // Simple admin credentials (in production, use database)
    const adminUsername = process.env.ADMIN_USERNAME || 'admin';
    const adminPasswordHash = process.env.ADMIN_PASSWORD_HASH || '$2a$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi'; // 'password'
    
    // Debug logging
    logger.info(`Admin login attempt - Username: ${username}, Expected: ${adminUsername}`);
    logger.info(`Password hash from env: ${adminPasswordHash ? 'Present' : 'Missing'}`);
    
    const passwordMatch = await bcrypt.compare(password, adminPasswordHash);
    logger.info(`Password comparison result: ${passwordMatch}`);
    
    if (username === adminUsername && passwordMatch) {
      req.session.isAdmin = true;
      req.session.adminUsername = username;
      logger.info(`Admin login successful: ${username} from IP: ${req.ip}`);
      return res.redirect('/admin/dashboard');
    }
    
    logger.warn(`Failed admin login attempt: ${username} from IP: ${req.ip}`);
    res.redirect('/admin/login?error=Invalid credentials');
  } catch (error) {
    logger.error('Admin login error:', error);
    res.redirect('/admin/login?error=Login failed');
  }
});

// Admin logout
router.post('/logout', (req, res) => {
  req.session.isAdmin = false;
  req.session.adminUsername = null;
  res.redirect('/admin/login');
});

// Admin dashboard
router.get('/dashboard', requireAdmin, async (req, res) => {
  try {
    const stats = await db.getUserStats();
    const recentUsers = await db.getRecentUsers(10);
    const activeSessions = await db.getActiveSessions();
    
    res.render('admin/dashboard', {
      title: 'Admin Dashboard',
      stats,
      recentUsers,
      activeSessions,
      adminUsername: req.session.adminUsername
    });
  } catch (error) {
    logger.error('Dashboard error:', error);
    res.status(500).render('admin/error', { error: 'Failed to load dashboard' });
  }
});

// User management
router.get('/users', requireAdmin, [
  query('page').optional().isInt({ min: 1 }),
  query('search').optional().trim(),
  query('squadron').optional().trim()
], async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = 20;
    const offset = (page - 1) * limit;
    const search = req.query.search || '';
    const squadron = req.query.squadron || '';
    
    const result = await db.getUsersPaginated({
      limit,
      offset,
      search,
      squadron
    });
    
    const squadrons = await db.getSquadrons();
    
    res.render('admin/users', {
      title: 'User Management',
      users: result.users,
      total: result.total,
      page,
      totalPages: Math.ceil(result.total / limit),
      search,
      squadron,
      squadrons,
      adminUsername: req.session.adminUsername
    });
  } catch (error) {
    logger.error('Users page error:', error);
    res.status(500).render('admin/error', { error: 'Failed to load users' });
  }
});

// Delete user
router.delete('/users/:id', requireAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    const user = await db.getUserById(userId);
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Revoke network access if user has MAC address
    if (user.mac_address) {
      try {
        await networkManager.revokeAccess(user.mac_address);
      } catch (networkError) {
        logger.warn(`Failed to revoke network access for MAC ${user.mac_address}:`, networkError);
      }
    }
    
    // Delete user from database
    await db.deleteUser(userId);
    
    logger.info(`Admin ${req.session.adminUsername} deleted user ${user.email}`);
    res.json({ success: true, message: 'User deleted successfully' });
  } catch (error) {
    logger.error('Delete user error:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// Revoke user access
router.post('/users/:id/revoke', requireAdmin, async (req, res) => {
  try {
    const userId = req.params.id;
    const user = await db.getUserById(userId);
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    if (user.mac_address) {
      await networkManager.revokeAccess(user.mac_address);
      await db.updateUserStatus(userId, 'revoked');
      
      logger.info(`Admin ${req.session.adminUsername} revoked access for user ${user.email}`);
      res.json({ success: true, message: 'Access revoked successfully' });
    } else {
      res.status(400).json({ error: 'User has no MAC address to revoke' });
    }
  } catch (error) {
    logger.error('Revoke access error:', error);
    res.status(500).json({ error: 'Failed to revoke access' });
  }
});

// Network status
router.get('/network', requireAdmin, async (req, res) => {
  try {
    const whitelistedMacs = await networkManager.getWhitelistedMacs();
    const dhcpLeases = await networkManager.getDHCPLeases();
    const arpTable = await networkManager.getARPTable();
    
    res.render('admin/network', {
      title: 'Network Management',
      whitelistedMacs,
      dhcpLeases,
      arpTable,
      adminUsername: req.session.adminUsername
    });
  } catch (error) {
    logger.error('Network page error:', error);
    res.status(500).render('admin/error', { error: 'Failed to load network status' });
  }
});

// Analytics page
router.get('/analytics', requireAdmin, async (req, res) => {
  try {
    const analyticsData = await db.getAnalyticsData();
    
    res.render('admin/analytics', {
      title: 'Analytics & Reports',
      analytics: analyticsData,
      adminUsername: req.session.adminUsername
    });
  } catch (error) {
    logger.error('Analytics page error:', error);
    res.status(500).render('admin/error', { error: 'Failed to load analytics' });
  }
});

// System logs
router.get('/logs', requireAdmin, [
  query('level').optional().isIn(['error', 'warn', 'info', 'debug']),
  query('limit').optional().isInt({ min: 1, max: 1000 })
], async (req, res) => {
  try {
    const level = req.query.level || 'info';
    const limit = parseInt(req.query.limit) || 100;
    
    const logs = await db.getSystemLogs({ level, limit });
    
    res.render('admin/logs', {
      title: 'System Logs',
      logs,
      currentLevel: level,
      limit,
      adminUsername: req.session.adminUsername
    });
  } catch (error) {
    logger.error('Logs page error:', error);
    res.status(500).render('admin/error', { error: 'Failed to load logs' });
  }
});

// Settings page
router.get('/settings', requireAdmin, (req, res) => {
  res.render('admin/settings', {
    title: 'System Settings',
    adminUsername: req.session.adminUsername
  });
});

// API endpoints for dashboard updates
router.get('/api/stats', requireAdmin, async (req, res) => {
  try {
    const stats = await db.getUserStats();
    res.json(stats);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch stats' });
  }
});

router.get('/api/recent-activity', requireAdmin, async (req, res) => {
  try {
    const recentActivity = await db.getRecentActivity(20);
    res.json(recentActivity);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch recent activity' });
  }
});

module.exports = router;