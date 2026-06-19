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
  connectionTimeoutMillis: 8000,
  idleTimeoutMillis: 30000,
  query_timeout: 8000,
  max: 3,
});

pool.on('error', (err) => console.error('Pool error:', err.message));
pool.on('connect', () => console.log('✅ New DB connection established'));

// Query wrapper with timeout
async function query(text, params) {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    console.log(`📊 Query OK (${Date.now()-start}ms):`, text.substring(0, 50));
    return res;
  } catch (err) {
    console.error(`❌ Query FAILED (${Date.now()-start}ms):`, err.message);
    throw err;
  }
}

/**
 * Create all tables on first run
 */
async function initDB() {
  await query(`
    -- Users table
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      real_number VARCHAR(15) UNIQUE NOT NULL,   -- actual phone e.g. +919876543210
      masked_number VARCHAR(15) UNIQUE NOT NULL, -- virtual number from Exotel
      plan VARCHAR(20) DEFAULT 'trial',          -- trial | basic | pro | family
      active BOOLEAN DEFAULT true,
      created_at TIMESTAMP DEFAULT NOW(),
      expires_at TIMESTAMP DEFAULT NOW() + INTERVAL '7 days',
      open_until TIMESTAMP DEFAULT NULL   -- Delivery Mode: allow all until this time
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

    -- FCM tokens for push notifications
    CREATE TABLE IF NOT EXISTS fcm_tokens (
      id SERIAL PRIMARY KEY,
      user_id INT REFERENCES users(id) ON DELETE CASCADE,
      token TEXT NOT NULL,
      updated_at TIMESTAMP DEFAULT NOW(),
      UNIQUE(user_id)
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

    -- Virtual number pool (Plivo numbers)
    CREATE TABLE IF NOT EXISTS virtual_numbers (
      id SERIAL PRIMARY KEY,
      number VARCHAR(15) UNIQUE NOT NULL,        -- e.g. +919XXXXXXXXXX
      provider VARCHAR(20) DEFAULT 'plivo',      -- plivo | exotel
      status VARCHAR(20) DEFAULT 'available',    -- available | assigned | suspended
      assigned_to INT REFERENCES users(id) ON DELETE SET NULL,
      assigned_at TIMESTAMP,
      added_at TIMESTAMP DEFAULT NOW()
    );
  `);
  console.log('✅ Database tables ready');
}

// ─── USER QUERIES ──────────────────────────────────────────

async function getUserByMaskedNumber(maskedNumber) {
  const res = await query(
    'SELECT * FROM users WHERE masked_number = $1 AND active = true',
    [maskedNumber]
  );
  return res.rows[0] || null;
}

async function getUserByRealNumber(realNumber) {
  const res = await query(
    'SELECT * FROM users WHERE real_number = $1',
    [realNumber]
  );
  return res.rows[0] || null;
}

async function createUser(realNumber, maskedNumber, plan = 'pro', trialDays = 15) {
  const res = await query(
    `INSERT INTO users (real_number, masked_number, plan, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '${trialDays} days')
     RETURNING *`,
    [realNumber, maskedNumber, plan]
  );
  return res.rows[0];
}

// ─── PHONEBOOK QUERIES ─────────────────────────────────────

async function isInPhonebook(userId, callerNumber) {
  const res = await query(
    'SELECT id FROM phonebook WHERE user_id = $1 AND contact_number = $2',
    [userId, callerNumber]
  );
  return res.rows.length > 0;
}

async function addToPhonebook(userId, contactNumber, contactName = '') {
  await query(
    `INSERT INTO phonebook (user_id, contact_number, contact_name)
     VALUES ($1, $2, $3) ON CONFLICT (user_id, contact_number) DO NOTHING`,
    [userId, contactNumber, contactName]
  );
}

async function getPhonebook(userId) {
  const res = await query(
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
  const res = await query(
    `SELECT id FROM temp_whitelist
     WHERE user_id = $1
       AND caller_number = $2
       AND expires_at > NOW()`,
    [userId, callerNumber]
  );
  return res.rows.length > 0;
}

async function addTempWhitelist(userId, callerNumber, label, hoursValid = 2) {
  await query(
    `INSERT INTO temp_whitelist (user_id, caller_number, label, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '${hoursValid} hours')`,
    [userId, callerNumber, label]
  );
}

async function getTempWhitelist(userId) {
  const res = await query(
    `SELECT * FROM temp_whitelist
     WHERE user_id = $1 AND expires_at > NOW()
     ORDER BY expires_at`,
    [userId]
  );
  return res.rows;
}

// ─── LOG QUERIES ───────────────────────────────────────────

async function logCall(userId, callerNumber, maskedNumber, action, reason) {
  await query(
    `INSERT INTO call_log (user_id, caller_number, masked_number, action, reason)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, callerNumber, maskedNumber, action, reason]
  );
}

async function logSMS(userId, fromNumber, maskedNumber, message, direction) {
  await query(
    `INSERT INTO sms_log (user_id, from_number, masked_number, message, direction)
     VALUES ($1, $2, $3, $4, $5)`,
    [userId, fromNumber, maskedNumber, message, direction]
  );
}

async function getCallLog(userId, limit = 20) {
  const res = await query(
    'SELECT * FROM call_log WHERE user_id = $1 ORDER BY called_at DESC LIMIT $2',
    [userId, limit]
  );
  return res.rows;
}

async function getSMSLog(userId, limit = 20) {
  const res = await query(
    'SELECT * FROM sms_log WHERE user_id = $1 ORDER BY sent_at DESC LIMIT $2',
    [userId, limit]
  );
  return res.rows;
}

// ─── DELIVERY MODE QUERIES ────────────────────────────

async function enableDeliveryMode(userId, hours) {
  const res = await query(
    `UPDATE users SET open_until = NOW() + INTERVAL '${hours} hours'
     WHERE id = $1 RETURNING open_until`,
    [userId]
  );
  return res.rows[0]?.open_until;
}

async function disableDeliveryMode(userId) {
  await query(
    'UPDATE users SET open_until = NULL WHERE id = $1',
    [userId]
  );
}

async function isDeliveryModeActive(userId) {
  const res = await query(
    'SELECT open_until FROM users WHERE id = $1 AND open_until > NOW()',
    [userId]
  );
  return res.rows.length > 0 ? res.rows[0].open_until : null;
}

// ─── FCM TOKEN QUERIES ────────────────────────────────

async function saveFcmToken(userId, token) {
  await query(
    `INSERT INTO fcm_tokens (user_id, token, updated_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (user_id) DO UPDATE SET token=$2, updated_at=NOW()`,
    [userId, token]
  );
}

async function getFcmToken(userId) {
  const res = await query(
    'SELECT token FROM fcm_tokens WHERE user_id=$1',
    [userId]
  );
  return res.rows[0]?.token || null;
}

// ─── VIRTUAL NUMBER POOL ──────────────────────────────

/**
 * Add a Plivo number to the pool (call after buying it).
 */
async function addNumberToPool(number, provider = 'plivo') {
  await query(
    `INSERT INTO virtual_numbers (number, provider)
     VALUES ($1, $2) ON CONFLICT (number) DO NOTHING`,
    [number, provider]
  );
}

/**
 * Pick the next available number from the pool and assign it to a user.
 * Returns the assigned number string, or null if pool is empty.
 */
async function assignNumberToUser(userId) {
  const res = await query(
    `UPDATE virtual_numbers
     SET status = 'assigned', assigned_to = $1, assigned_at = NOW()
     WHERE id = (
       SELECT id FROM virtual_numbers
       WHERE status = 'available'
       ORDER BY added_at ASC
       LIMIT 1
     )
     RETURNING number`,
    [userId]
  );
  return res.rows[0]?.number || null;
}

/**
 * Release a user's number back to the pool.
 */
async function releaseNumber(userId) {
  await query(
    `UPDATE virtual_numbers
     SET status = 'available', assigned_to = NULL, assigned_at = NULL
     WHERE assigned_to = $1`,
    [userId]
  );
}

/**
 * Get pool stats.
 */
async function getNumberPoolStats() {
  const res = await query(
    `SELECT status, COUNT(*) as count FROM virtual_numbers GROUP BY status`
  );
  return res.rows;
}

/**
 * List all numbers in pool.
 */
async function listNumberPool() {
  const res = await query(
    `SELECT vn.*, u.real_number as user_real_number
     FROM virtual_numbers vn
     LEFT JOIN users u ON vn.assigned_to = u.id
     ORDER BY vn.added_at DESC`
  );
  return res.rows;
}

module.exports = {
  initDB, pool,
  getUserByMaskedNumber, getUserByRealNumber, createUser,
  isInPhonebook, addToPhonebook, getPhonebook, bulkAddPhonebook,
  isInTempWhitelist, addTempWhitelist, getTempWhitelist,
  logCall, logSMS, getCallLog, getSMSLog, saveFcmToken, getFcmToken,
  enableDeliveryMode, disableDeliveryMode, isDeliveryModeActive,
  addNumberToPool, assignNumberToUser, releaseNumber, getNumberPoolStats, listNumberPool,
};
