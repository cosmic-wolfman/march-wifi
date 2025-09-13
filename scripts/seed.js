#!/usr/bin/env node

const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://localhost/captive_portal'
});

async function seedDatabase() {
  try {
    console.log('Seeding database with sample data...');
    
    const testUsers = [
      {
        name: 'Test User 1',
        squadron: 'Alpha Squadron',
        email: 'test1@example.com',
        mac_address: '00:11:22:33:44:55',
        ip_address: '192.168.1.100'
      },
      {
        name: 'Test User 2',
        squadron: 'Bravo Squadron',
        email: 'test2@example.com',
        mac_address: '00:11:22:33:44:66',
        ip_address: '192.168.1.101'
      }
    ];

    for (const user of testUsers) {
      await pool.query(
        `INSERT INTO users (name, squadron, email, mac_address, ip_address)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (mac_address) DO NOTHING`,
        [user.name, user.squadron, user.email, user.mac_address, user.ip_address]
      );
    }
    
    console.log('Database seeding completed successfully');
  } catch (error) {
    console.error('Seeding failed:', error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  seedDatabase();
}

module.exports = seedDatabase;