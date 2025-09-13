const rateLimit = require('express-rate-limit');
const logger = require('../utils/logger');

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: 'Too many requests from this IP, please try again later.',
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    // Use X-Forwarded-For when behind proxy, otherwise use req.ip
    return req.headers['x-forwarded-for']?.split(',')[0].trim() || req.connection.remoteAddress;
  },
  handler: (req, res) => {
    logger.warn(`Rate limit exceeded for IP: ${req.ip}`);
    res.status(429).json({
      error: 'Too many requests',
      message: 'Please try again later'
    });
  }
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  skipSuccessfulRequests: true,
  message: 'Too many authentication attempts, please try again later.',
  keyGenerator: (req) => {
    // Use X-Forwarded-For when behind proxy, otherwise use req.ip
    return req.headers['x-forwarded-for']?.split(',')[0].trim() || req.connection.remoteAddress;
  }
});

module.exports = limiter;
module.exports.authLimiter = authLimiter;