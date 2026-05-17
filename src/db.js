const { Pool } = require('pg');
const dns = require('dns');
dns.setDefaultResultOrder('ipv4first');

// Supabase session pooler (port 5432) — supports prepared statements unlike transaction pooler (6543)
const dbUrl = (process.env.DATABASE_URL
  || 'postgresql://postgres.yqirhxuitstamejwgbck:lL3sRzr4XRjGxoJq@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres')
  .replace(':6543/', ':5432/');
console.log('🔌 Connecting to DB:', dbUrl.substring(0, 50) + '...');

const pool = new Pool({
  connectionString: dbUrl,
  ssl: { rejectUnauthorized: false },
  connectionTimeoutMillis: 5000,
  idleTimeoutMillis: 10000,
  max: 5,
});

/**
 * Create all tables on first run
 */
async function initDB() {
  await pool.query(`
    -- Users table
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      real_number VARCHAR(15) UNIQUE NOT NULL,   -- actual phone e.g. +919876543210
      masked_number VARCHAR(15) UNIQUE NOT NULL, -- virtual number from Exotel
      plan VARCHAR(20) DEFAULT 'trial',          -- trial | basic | pro | family
      active BOOLEAN DEFAULT true,
      created_at TIMESTAMP DEFAULT NOW(),
      expires_at TIMESTAMP DEFAULT NOW() + INTERVAL '7 days'
    );

    -- Phonebook: numbers allowed to call through
    CREATE TABLE IF NOT EXISTS phonebook (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id) ON DELETE CASCADE,
      contact_number VARCHAR(15) NOT NULL,       -- e.g. +919123456789
      contact_name VARCHAR(100),
      added_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id, contact_number)
    );

    -- Temp whitelist: time-limited access (e.g. delivery rider for 2 hrs)
    CREATE TABLE IF NOT EXISTS temp_whitelist (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id) ON DELETE CASCADE,
      caller_number VARCHAR(15) NOT NULL,
      label VARCHAR(100),                        -- e.g. "Zomato rider"
      expires_at TIMESTAMP NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );

    -- Call log: every call attempt (allowed or blocked)
    CREATE TABLE IF NOT EXISTS call_log (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id),
      caller_number VARCHAR(15),
      masked_number VARCHAR(15),
      action VARCHAR(10),                        -- allowed | blocked
      reason VARCHAR(50),                        -- phonebook | temp_whitelist | unknown
      called_at TIMESTAMP DEFAULT NOW()
    );

    -- SMS log: every forwarded message
    CREATE TABLE IF NOT EXISTS sms_log (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id),
      from_number VARCHAR(15),
      masked_number VARCHAR(15),
      message TEXT,
      direction VARCHAR(10),                     -- inbound | outbound
      sent_at TIMESTAMP DEFAULT NOW()
    );

    -- Payments
    CREATE TABLE IF NOT EXISTS payments (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id),
      razorpay_order_id VARCHAR(100),
      razorpay_payment_id VARCHAR(100),
      amount INT,                                -- in paise
      plan VARCHAR(20),
      status VARCHAR(20) DEFAULT 'pending',
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('✅ Database tables ready');
}

// ─── USER QUERIES ──────────────────────────────────────────

async function getUserByMaskedNumber(maskedNumber) {
  const res = await pool.query(
    'SELECT * FROM users WHERE masked_number = $1 AND active = true',
    [maskedNumber]
  );
  return res.rows[0] || null;
}

async function getUserByRealNumber(realNumber) {
  const res = await pool.query(
    'SELECT * FROM users WHERE real_number = $1',
    [realNumber]
  );
  return res.rows[0] || null;
}

async function createUser(realNumber, maskedNumber) {
  const res = await pool.query(
    `INSERT INTO users (real_number, masked_number, plan, expires_at)
     VALUES ($1, $2, 'trial', NOW() + INTERVAL '7 days')
     RETURNING *`,
    [realNumber, maskedNumber]
  );
  return res.rows[0];
}

// ─── PHONEBOOK QUERIES ─────────────────────────────────────

async function isInPhonebook(userId, callerNumber) {
  const res = await pool.query(
    'SELECT id FROM phonebook WHERE user_id = $1 AND contact_number = $2',
    [userId, callerNumber]
  );
  return res.rows.length > 0;
}

async function addToPhonebook(userId, contactNumber, contactName = '') {
  await pool.query(
    `INSERT INTO phonebook (user_id, contact_number, contact_name)
     VALUES ($1, $2, $3) ON CONFLICT (user_id, contact_number) DO NOTHING`,
    [userId, contactNumber, contactName]
  );
}

async function getPhonebook(userId) {
  const res = await pool.query(
    'SELECT * FROM phonebook WHERE user_id = $1 ORDER BY contact_name',
    [userId]
  );
  return res.rows;
}

async function bulkAddPhonebook(userId, contacts) {
  // contacts = [{number, name}]
  for (const c of contacts) {
    await addToPhonebook(userId, c.number, c.name);
  }
}

// ─── TEMP WHITELIST QUERIES ────────────────────────────────

async function isInTempWhitelist(userId, callerNumber) {
  const res = await pool.query(
    `SELECT id FROM temp_whitelist
     WHERE user_id = $1
       AND caller_number = $2
       AND expires_at > NOW()`,
    [userId, callerNumber]
  );
  return res.rows.length > 0;
}

async function addTempWhitelist(userId, callerNumber, label, hoursValid = 2) {
  await pool.query(
    `INSERT INTO temp_whitelist (user_id, caller_number, label, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '${hoursValid} hours')`,
    [userId, callerNumber, label]
  );
}

async function getTempWhitelist(userId) {
  const res = await pool.query(
    `SELECT * FROM temp_whitelist
     WHERE user_id = $1 AND expires_at > NOW()
     ORDER BY expires_at`,
    [userId]
  );
  return res.rows;
}

// ─── LOG QUERIES ───────────────────────────────────────────

async function logCall(userId, callerNumber, maskedNumber, action, reason) {
  await pool.query(
    `INSERT INTO call_log (user_id, caller_number, masked_number, action, reason)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, callerNumber, maskedNumber, action, reason]
  );
}

async function logSMS(userId, fromNumber, maskedNumber, message, direction) {
  await pool.query(
    `INSERT INTO sms_log (user_id, from_number, masked_number, message, direction)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, fromNumber, maskedNumber, message, direction]
  );
}

async function getCallLog(userId, limit = 20) {
  const res = await pool.query(
    'SELECT * FROM call_log WHERE user_id = $1 ORDER BY called_at DESC LIMIT $2',
    [userId, limit]
  );
  return res.rows;
}

async function getSMSLog(userId, limit = 20) {
  const res = await pool.query(
    'SELECT * FROM sms_log WHERE user_id = $1 ORDER BY sent_at DESC LIMIT $2',
    [userId, limit]
  );
  return res.rows;
}

module.exports = {
  initDB, pool,
  getUserByMaskedNumber, getUserByRealNumber, createUser,
  isInPhonebook, addToPhonebook, getPhonebook, bulkAddPhonebook,
  isInTempWhitelist, addTempWhitelist, getTempWhitelist,
  logCall, logSMS, getCallLog, getSMSLog,
};
