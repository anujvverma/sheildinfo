require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');

const {
  initDB,
  getUserByMaskedNumber,
  getUserByRealNumber,
  createUser,
  isInPhonebook,
  isInTempWhitelist,
  addTempWhitelist,
  getTempWhitelist,
  addToPhonebook,
  getPhonebook,
  bulkAddPhonebook,
  getCallLog,
  getSMSLog,
  logCall,
  logSMS,
} = require('./db');

const {
  sendSMS,
  buildCallConnectXML,
  buildCallBlockXML,
} = require('./exotel');

const app = express();
app.use(cors());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

// ═══════════════════════════════════════════════════════════════
//  EXOTEL WEBHOOKS  (Exotel calls these URLs automatically)
// ═══════════════════════════════════════════════════════════════

/**
 * INCOMING CALL WEBHOOK
 * Exotel hits this URL when someone calls the masked number.
 * We decide: allow (forward to real number) or block.
 *
 * Set this URL in Exotel dashboard:
 *   POST https://yourapp.railway.app/webhook/call
 */
app.post('/webhook/call', async (req, res) => {
  const callerNumber = normaliseNumber(req.body.From || req.body.CallFrom);
  const maskedNumber = normaliseNumber(req.body.To   || req.body.CallTo);

  console.log(`📞 Incoming call | caller: ${callerNumber} → masked: ${maskedNumber}`);

  try {
    const user = await getUserByMaskedNumber(maskedNumber);

    if (!user) {
      console.log('❌ No user found for masked number — blocking');
      res.set('Content-Type', 'text/xml');
      return res.send(buildCallBlockXML());
    }

    // Check 1 — is caller in permanent phonebook?
    const inPhonebook = await isInPhonebook(user.id, callerNumber);
    if (inPhonebook) {
      console.log(`✅ ALLOWED — ${callerNumber} is in phonebook`);
      await logCall(user.id, callerNumber, maskedNumber, 'allowed', 'phonebook');
      res.set('Content-Type', 'text/xml');
      return res.send(buildCallConnectXML(user.real_number));
    }

    // Check 2 — is caller on temp whitelist (e.g. delivery rider)?
    const inTempList = await isInTempWhitelist(user.id, callerNumber);
    if (inTempList) {
      console.log(`✅ ALLOWED — ${callerNumber} is on temp whitelist`);
      await logCall(user.id, callerNumber, maskedNumber, 'allowed', 'temp_whitelist');
      res.set('Content-Type', 'text/xml');
      return res.send(buildCallConnectXML(user.real_number));
    }

    // Neither — block the call
    console.log(`🚫 BLOCKED — ${callerNumber} is unknown`);
    await logCall(user.id, callerNumber, maskedNumber, 'blocked', 'unknown');

    // Optionally notify user via SMS that someone tried to call (non-fatal)
    sendSMS(
      user.real_number,
      maskedNumber,
      `ShieldNumber blocked a call from ${callerNumber}. If you know this person, add them to your whitelist in the app.`
    ).catch(err => console.warn('Block notification SMS failed (non-fatal):', err.message));

    res.set('Content-Type', 'text/xml');
    return res.send(buildCallBlockXML());

  } catch (err) {
    console.error('Webhook /call error:', err);
    // On error, block for safety
    res.set('Content-Type', 'text/xml');
    return res.send(buildCallBlockXML());
  }
});

/**
 * INCOMING SMS WEBHOOK
 * Exotel hits this URL when someone texts the masked number.
 * We always forward SMS — no filtering.
 *
 * Set this URL in Exotel dashboard:
 *   POST https://yourapp.railway.app/webhook/sms
 */
app.post('/webhook/sms', async (req, res) => {
  const fromNumber  = normaliseNumber(req.body.From);
  const maskedNumber = normaliseNumber(req.body.To);
  const message     = req.body.Body || req.body.Message || '';

  console.log(`💬 Incoming SMS | from: ${fromNumber} → masked: ${maskedNumber} | "${message}"`);

  try {
    const user = await getUserByMaskedNumber(maskedNumber);

    if (!user) {
      return res.sendStatus(200);
    }

    // Always forward SMS to real number
    const forwardedMsg = `📩 Message from ${fromNumber}:\n\n${message}\n\n(via ShieldNumber)`;
    await sendSMS(user.real_number, maskedNumber, forwardedMsg);
    await logSMS(user.id, fromNumber, maskedNumber, message, 'inbound');

    console.log(`✅ SMS forwarded to ${user.real_number}`);
    res.sendStatus(200);

  } catch (err) {
    console.error('Webhook /sms error:', err);
    res.sendStatus(200); // Always 200 to Exotel
  }
});

// ═══════════════════════════════════════════════════════════════
//  USER API  (your frontend/app calls these)
// ═══════════════════════════════════════════════════════════════

/**
 * POST /api/register
 * Register a new user with a masked number
 * Body: { realNumber, maskedNumber }
 *
 * In production: add OTP verification before creating user
 */
app.post('/api/register', async (req, res) => {
  const { realNumber, maskedNumber } = req.body;

  if (!realNumber || !maskedNumber) {
    return res.status(400).json({ error: 'realNumber and maskedNumber required' });
  }

  try {
    const existing = await getUserByRealNumber(normaliseNumber(realNumber));
    if (existing) {
      return res.json({ user: existing, message: 'Already registered' });
    }

    const user = await createUser(
      normaliseNumber(realNumber),
      normaliseNumber(maskedNumber)
    );

    // Send welcome SMS (non-fatal — don't block registration if SMS fails)
    sendSMS(
      user.real_number,
      maskedNumber,
      `Welcome to ShieldNumber! Your masked number is: ${maskedNumber}. Share this with strangers - your real number stays private. Unknown callers will be blocked automatically.`
    ).catch(err => console.warn('Welcome SMS failed (non-fatal):', err.message));

    res.json({ user, message: 'Registered successfully' });

  } catch (err) {
    console.error('/api/register error:', err);
    res.status(500).json({ error: 'Registration failed' });
  }
});

/**
 * POST /api/whitelist/temp
 * Add a temporary whitelist entry (e.g. allow rider for 2 hours)
 * Body: { realNumber, callerNumber, label, hoursValid }
 */
app.post('/api/whitelist/temp', async (req, res) => {
  const { realNumber, callerNumber, label, hoursValid = 2 } = req.body;

  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });

    await addTempWhitelist(
      user.id,
      normaliseNumber(callerNumber),
      label,
      hoursValid
    );

    res.json({
      message: `✅ ${callerNumber} can now call for ${hoursValid} hour(s)`,
      expiresIn: `${hoursValid} hours`
    });

  } catch (err) {
    console.error('/api/whitelist/temp error:', err);
    res.status(500).json({ error: 'Failed to add whitelist entry' });
  }
});

/**
 * GET /api/whitelist/temp?realNumber=+91XXXXXXXXXX
 * Get active temp whitelist entries
 */
app.get('/api/whitelist/temp', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    const list = await getTempWhitelist(user.id);
    res.json({ whitelist: list });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get whitelist' });
  }
});

/**
 * POST /api/phonebook/add
 * Add a contact to permanent phonebook
 * Body: { realNumber, contactNumber, contactName }
 */
app.post('/api/phonebook/add', async (req, res) => {
  const { realNumber, contactNumber, contactName } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    await addToPhonebook(user.id, normaliseNumber(contactNumber), contactName);
    res.json({ message: `✅ ${contactName || contactNumber} added to phonebook` });
  } catch (err) {
    res.status(500).json({ error: 'Failed to add to phonebook' });
  }
});

/**
 * POST /api/phonebook/bulk
 * Bulk upload contacts from mobile app
 * Body: { realNumber, contacts: [{number, name}] }
 */
app.post('/api/phonebook/bulk', async (req, res) => {
  const { realNumber, contacts } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });

    const normalised = contacts.map(c => ({
      number: normaliseNumber(c.number),
      name: c.name || ''
    }));

    await bulkAddPhonebook(user.id, normalised);
    res.json({ message: `✅ ${contacts.length} contacts synced` });
  } catch (err) {
    res.status(500).json({ error: 'Failed to sync phonebook' });
  }
});

/**
 * GET /api/phonebook?realNumber=+91XXXXXXXXXX
 */
app.get('/api/phonebook', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    const contacts = await getPhonebook(user.id);
    res.json({ contacts });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get phonebook' });
  }
});

/**
 * GET /api/logs?realNumber=+91XXXXXXXXXX
 * Get call and SMS history
 */
app.get('/api/logs', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    const [calls, messages] = await Promise.all([
      getCallLog(user.id),
      getSMSLog(user.id)
    ]);
    res.json({ calls, messages });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get logs' });
  }
});

/**
 * GET /api/user?realNumber=+91XXXXXXXXXX
 * Get user info and their masked number
 */
app.get('/api/user', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({
      maskedNumber: user.masked_number,
      plan: user.plan,
      active: user.active,
      expiresAt: user.expires_at
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// Health check
app.get('/health', (_, res) => res.json({ status: 'ok', app: 'ShieldNumber' }));

// ═══════════════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════════════

/**
 * Normalise Indian phone numbers to +91XXXXXXXXXX format
 */
function normaliseNumber(num = '') {
  if (!num) return num;
  num = num.toString().replace(/\s|-/g, '');
  if (num.startsWith('0')) num = '+91' + num.slice(1);
  if (num.startsWith('91') && num.length === 12) num = '+' + num;
  if (!num.startsWith('+')) num = '+91' + num;
  return num;
}

// ═══════════════════════════════════════════════════════════════
//  START
// ═══════════════════════════════════════════════════════════════

const PORT = process.env.PORT || 3000;
const APP_URL = process.env.APP_URL || 'https://sheildinfo-production.up.railway.app';

initDB().then(() => {
  app.listen(PORT, () => {
    console.log(`
🔒 ShieldNumber backend running on port ${PORT}

Webhook URLs to configure in Exotel:
  Incoming Call : POST ${APP_URL}/webhook/call
  Incoming SMS  : POST ${APP_URL}/webhook/sms

API endpoints:
  POST /api/register
  POST /api/whitelist/temp
  GET  /api/whitelist/temp
  POST /api/phonebook/add
  POST /api/phonebook/bulk
  GET  /api/phonebook
  GET  /api/logs
  GET  /api/user
    `);
  });
});
