const express = require('express');
const session = require('express-session');
const RedisStore = require('connect-redis').default;
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const path = require('path');
const { createClient } = require('redis');
require('dotenv').config();

const logger = require('./utils/logger');
const rateLimiter = require('./middleware/rateLimiter');
const errorHandler = require('./middleware/errorHandler');
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const captiveRoutes = require('./routes/captive');
const adminRoutes = require('./routes/admin');

const app = express();
const PORT = process.env.PORT || 3000;

// Trust proxy for reverse proxy setup (Nginx)
app.set('trust proxy', true);

const redisClient = createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379',
  legacyMode: false
});

redisClient.connect().catch(console.error);

redisClient.on('error', (err) => {
  logger.error('Redis Client Error', err);
});

// Only use security headers in production
if (process.env.NODE_ENV === 'production') {
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        scriptSrc: ["'self'"],
        imgSrc: ["'self'", "data:", "https:"],
      },
    },
  }));
} else {
  // Minimal security headers for development
  app.use(helmet({
    contentSecurityPolicy: false,
    crossOriginOpenerPolicy: false,
    crossOriginResourcePolicy: false,
    hsts: false,
    originAgentCluster: false
  }));
}

app.use(compression());
app.use(cors({
  origin: process.env.CORS_ORIGIN || false,
  credentials: true
}));

app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(session({
  store: new RedisStore({ client: redisClient }),
  secret: process.env.SESSION_SECRET || 'your-secret-key',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    httpOnly: true,
    maxAge: 1800000
  }
}));

app.use(rateLimiter);

app.use('/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/admin', adminRoutes);
app.use('/', captiveRoutes);

app.use(errorHandler);

const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info(`Server running on port ${PORT} and accessible from all interfaces`);
});

process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
    redisClient.quit();
    process.exit(0);
  });
});

module.exports = app;