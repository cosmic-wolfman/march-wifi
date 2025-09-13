const logger = require('../utils/logger');

const requireAuth = (req, res, next) => {
  if (!req.session.authenticated || !req.session.userId) {
    logger.warn(`Unauthorized access attempt from IP: ${req.ip}`);
    return res.status(401).json({
      error: 'Unauthorized',
      message: 'Authentication required'
    });
  }
  next();
};

const requireAdmin = (req, res, next) => {
  if (!req.session.authenticated || !req.session.isAdmin) {
    logger.warn(`Unauthorized admin access attempt from IP: ${req.ip}`);
    return res.status(403).json({
      error: 'Forbidden',
      message: 'Admin access required'
    });
  }
  next();
};

module.exports = {
  requireAuth,
  requireAdmin
};