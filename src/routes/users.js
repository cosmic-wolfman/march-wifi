const express = require('express');
const logger = require('../utils/logger');
const db = require('../models/db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

router.get('/current', requireAuth, async (req, res, next) => {
  try {
    const user = await db.getUserById(req.session.userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json({
      id: user.id,
      name: user.name,
      squadron: user.squadron,
      email: user.email,
      created_at: user.created_at
    });
  } catch (error) {
    next(error);
  }
});

router.get('/stats', requireAuth, async (req, res, next) => {
  try {
    const stats = await db.getUserStats();
    res.json(stats);
  } catch (error) {
    next(error);
  }
});

module.exports = router;