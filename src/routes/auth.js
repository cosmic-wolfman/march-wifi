const express = require('express');
const { body, validationResult } = require('express-validator');
const { v4: uuidv4 } = require('uuid');
const logger = require('../utils/logger');
const { authLimiter } = require('../middleware/rateLimiter');
const db = require('../models/db');
const networkManager = require('../utils/network');

const router = express.Router();

router.post('/register', 
  authLimiter,
  [
    body('name').trim().notEmpty().isLength({ min: 2, max: 255 }).escape(),
    body('squadron').trim().notEmpty().isLength({ min: 1, max: 100 }).escape(),
    body('email').trim().isEmail().normalizeEmail()
  ],
  async (req, res, next) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({ errors: errors.array() });
      }

      const { name, squadron, email } = req.body;
      const ipAddress = req.ip || req.connection.remoteAddress;

      // Create user record
      const user = await db.createUser({
        name,
        squadron,
        email,
        ip_address: ipAddress,
        mac_address: null // Will be updated by network manager
      });

      // Grant network access
      try {
        const accessResult = await networkManager.grantAccess(req, user);
        
        req.session.userId = user.id;
        req.session.authenticated = true;
        req.session.macAddress = accessResult.macAddress;

        logger.info(`New user registered and granted access: ${email} from IP: ${ipAddress}, MAC: ${accessResult.macAddress}`);

        res.json({
          success: true,
          message: 'Registration successful - Network access granted',
          redirect: process.env.SUCCESS_REDIRECT_URL || '/welcome',
          macAddress: accessResult.macAddress
        });
      } catch (networkError) {
        logger.error('Network access grant failed:', networkError);
        
        // Still allow registration but note the network issue
        req.session.userId = user.id;
        req.session.authenticated = true;

        res.json({
          success: true,
          message: 'Registration successful - Network access may be limited',
          redirect: process.env.SUCCESS_REDIRECT_URL || '/welcome',
          warning: 'Network access configuration failed'
        });
      }
    } catch (error) {
      next(error);
    }
  }
);

router.post('/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      logger.error('Session destruction error:', err);
      return res.status(500).json({ error: 'Logout failed' });
    }
    res.json({ success: true, message: 'Logged out successfully' });
  });
});

router.get('/status', (req, res) => {
  res.json({
    authenticated: req.session.authenticated || false,
    userId: req.session.userId || null
  });
});

module.exports = router;