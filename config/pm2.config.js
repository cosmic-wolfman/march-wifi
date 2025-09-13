module.exports = {
  apps: [{
    name: 'captive-portal',
    script: './src/app.js',
    instances: process.env.NODE_ENV === 'production' ? 'max' : 1,
    exec_mode: process.env.NODE_ENV === 'production' ? 'cluster' : 'fork',
    env: {
      NODE_ENV: 'development',
      PORT: 3000
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: './logs/pm2-error.log',
    out_file: './logs/pm2-out.log',
    log_file: './logs/pm2-combined.log',
    time: true,
    max_memory_restart: '500M',
    watch: process.env.NODE_ENV === 'development',
    watch_delay: 1000,
    ignore_watch: ['node_modules', 'logs', '.git', 'tmp', 'public/uploads'],
    autorestart: true,
    max_restarts: 10,
    min_uptime: '10s',
    exp_backoff_restart_delay: 100,
    kill_timeout: 5000,
    listen_timeout: 3000,
    cron_restart: '0 0 * * *'
  }]
};