const express = require('express');
const logger = require('../utils/logger');

const router = express.Router();

router.get('/', (req, res) => {
  if (req.session.authenticated) {
    return res.redirect(process.env.SUCCESS_REDIRECT_URL || '/welcome');
  }
  
  res.render('splash-inline', {
    title: 'WiFi Access Portal',
    message: req.query.message || null
  });
});

router.get('/original', (req, res) => {
  if (req.session.authenticated) {
    return res.redirect(process.env.SUCCESS_REDIRECT_URL || '/welcome');
  }
  
  res.render('splash', {
    title: 'WiFi Access Portal',
    message: req.query.message || null
  });
});

router.get('/welcome', (req, res) => {
  if (!req.session.authenticated) {
    return res.redirect('/');
  }
  
  res.render('welcome', {
    title: 'Welcome',
    userId: req.session.userId
  });
});

router.get('/generate_204', (req, res) => {
  res.status(204).send();
});

router.get('/hotspot-detect.html', (req, res) => {
  res.redirect('/');
});

router.get('/success.txt', (req, res) => {
  res.send('success');
});

router.get('/ncsi.txt', (req, res) => {
  res.send('Microsoft NCSI');
});

// Additional captive portal detection endpoints
router.get('/library/test/success.html', (req, res) => {
  // iOS captive portal detection
  res.send('<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>');
});

router.get('/connecttest.txt', (req, res) => {
  // Windows 10 connectivity test
  res.send('Microsoft Connect Test');
});

router.get('/redirect', (req, res) => {
  // Generic redirect endpoint
  res.redirect('/');
});

router.get('/check_network_status.txt', (req, res) => {
  // Additional connectivity check
  res.send('success');
});

// Network access management API
router.get('/api/access/status', async (req, res) => {
  try {
    const networkManager = require('../utils/network');
    const macAddress = await networkManager.getClientMac(req);
    
    if (!macAddress) {
      return res.json({ 
        hasAccess: false, 
        reason: 'MAC address not detected' 
      });
    }

    const hasAccess = await networkManager.isWhitelisted(macAddress);
    
    res.json({
      hasAccess,
      macAddress,
      authenticated: req.session.authenticated || false
    });
  } catch (error) {
    res.status(500).json({ 
      error: 'Failed to check access status',
      hasAccess: false 
    });
  }
});

router.post('/api/access/revoke', async (req, res) => {
  try {
    if (!req.session.authenticated) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const networkManager = require('../utils/network');
    const macAddress = req.session.macAddress || await networkManager.getClientMac(req);
    
    if (macAddress) {
      await networkManager.revokeAccess(macAddress);
      req.session.destroy();
      
      res.json({ 
        success: true, 
        message: 'Network access revoked' 
      });
    } else {
      res.status(400).json({ 
        error: 'Could not determine MAC address' 
      });
    }
  } catch (error) {
    res.status(500).json({ 
      error: 'Failed to revoke access' 
    });
  }
});

module.exports = router;