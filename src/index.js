require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');

const { sendPushNotification } = require('./notifications');
const { generateToken, requireAuth } = require('./auth');
const { isPlanExpired, canUseDeliveryMode, canUseSmsForwarding, getLogDays, getPlan } = require('./plans');

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
  logCall, logSMS,
  saveFcmToken, getFcmToken,
  enableDeliveryMode, disableDeliveryMode, isDeliveryModeActive,
} = require('./db');

const {
  sendSMS,
  connectCall,
  buildCallConnectXML,
  buildCallBlockXML,
  addToExotelAddressBook,
  removeFromExotelAddressBook,
} = require('./exotel');

const app = express();
app.use(cors());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

// Log every incoming request
app.use((req, res, next) => {
  console.log(`➡️  ${req.method} ${req.path} | body: ${JSON.stringify(req.body)} | query: ${JSON.stringify(req.query)}`);
  next();
});

// ─── AUTH MIDDLEWARE ───────────────────────────────────────────
app.use(requireAuth);

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
// Handle GET from Exotel (Passthru uses GET with query params)
app.get('/webhook/call', async (req, res) => {
  // Exotel sends params as: CallFrom, CallTo (primary) or From, To (fallback)
  const callerNumber = normaliseNumber(
    req.query.CallFrom || req.query.From || req.query.callFrom || ''
  );
  const maskedNumber = normaliseNumber(
    req.query.CallTo || req.query.To || req.query.callTo || ''
  );

  console.log(`📞 GET webhook | RAW: From=${req.query.CallFrom || req.query.From} To=${req.query.CallTo || req.query.To}`);
  console.log(`📞 GET webhook | NORMALISED: caller=${callerNumber} masked=${maskedNumber}`);
  console.log(`📞 GET webhook | ALL PARAMS: ${JSON.stringify(req.query)}`);

  if (!callerNumber || !maskedNumber) {
    console.error('❌ Missing caller or masked number in webhook params');
    // Return 200 so call goes through — don't block due to missing params
    return res.sendStatus(200);
  }

  try {
    const user = await getUserByMaskedNumber(maskedNumber);
    if (!user) {
      console.log(`❌ No user found for masked number ${maskedNumber} — blocking`);
      return res.sendStatus(403);
    }
    console.log(`👤 User found: id=${user.id} real=${user.real_number} plan=${user.plan}`);

    // Check 0 — is Delivery Mode active? (allow everyone temporarily)
    const deliveryUntil = await isDeliveryModeActive(user.id);
    if (deliveryUntil) {
      console.log(`🚚 DELIVERY MODE — allowing ${callerNumber}`);
      logCall(user.id, callerNumber, maskedNumber, 'allowed', 'delivery_mode').catch(() => {});
      return res.sendStatus(200);
    }

    // Check 1 — permanent phonebook
    const inPhonebook = await isInPhonebook(user.id, callerNumber);
    if (inPhonebook) {
      console.log(`✅ ALLOWED — ${callerNumber} is in phonebook → connecting to ${user.real_number}`);
      logCall(user.id, callerNumber, maskedNumber, 'allowed', 'phonebook').catch(() => {});
      return res.sendStatus(200); // Exotel runs Connect applet next
    }

    // Check 2 — temp whitelist (delivery riders etc.)
    const inTempList = await isInTempWhitelist(user.id, callerNumber);
    if (inTempList) {
      console.log(`✅ ALLOWED — ${callerNumber} is on temp whitelist`);
      logCall(user.id, callerNumber, maskedNumber, 'allowed', 'temp_whitelist').catch(() => {});
      return res.sendStatus(200);
    }

    // Not allowed — block
    console.log(`🚫 BLOCKED — ${callerNumber} not in phonebook (user ${user.id})`);
    logCall(user.id, callerNumber, maskedNumber, 'blocked', 'unknown').catch(() => {});

    const fcmToken = await getFcmToken(user.id).catch(() => null);
    if (fcmToken) {
      sendPushNotification(fcmToken,
        'Call Blocked 🛡️',
        `Unknown caller ${callerNumber} was blocked`,
        { type: 'blocked_call', callerNumber }
      ).catch(() => {});
    }
    return res.sendStatus(403);

  } catch (err) {
    // Log the REAL error — this is critical for debugging
    console.error(`🔥 GET Webhook /call EXCEPTION: ${err.message}`);
    console.error(err.stack);
    // On DB/server error: allow rather than silently block
    // Better to let calls through than block phonebook contacts due to a server error
    return res.sendStatus(200);
  }
});

app.post('/webhook/call', async (req, res) => {
  console.log('📞 Webhook hit! Full body:', JSON.stringify(req.body));
  console.log('📞 Headers:', JSON.stringify(req.headers));

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
      return res.send(buildCallConnectXML(user.real_number, maskedNumber));
    }

    // Check 2 — is caller on temp whitelist (e.g. delivery rider)?
    const inTempList = await isInTempWhitelist(user.id, callerNumber);
    if (inTempList) {
      console.log(`✅ ALLOWED — ${callerNumber} is on temp whitelist`);
      await logCall(user.id, callerNumber, maskedNumber, 'allowed', 'temp_whitelist');
      res.set('Content-Type', 'text/xml');
      return res.send(buildCallConnectXML(user.real_number, maskedNumber));
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
 * POST /api/auth/token
 * Exchange phone number for JWT session token (called after Firebase OTP)
 * Body: { realNumber, firebaseUid }
 */
app.post('/api/auth/token', async (req, res) => {
  const { realNumber, firebaseUid } = req.body;
  if (!realNumber) return res.status(400).json({ error: 'realNumber required' });
  try {
    let user = await getUserByRealNumber(normaliseNumber(realNumber));
    // Auto-register if first time
    if (!user) {
      return res.status(404).json({ error: 'User not registered', code: 'NOT_REGISTERED' });
    }
    const token = generateToken(user.id, user.real_number);
    const { isPlanExpired: planExpired, getPlan } = require('./plans');
    const planDetails = getPlan(user.plan);
    res.json({
      token,
      user: {
        id: user.id,
        maskedNumber: user.masked_number,
        plan: user.plan,
        planName: planDetails.name,
        active: user.active && !planExpired(user),
        expiresAt: user.expires_at,
      }
    });
  } catch (err) {
    console.error('auth/token error:', err);
    res.status(500).json({ error: 'Auth failed' });
  }
});

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

    // New users get Pro trial for 15 days
    const user = await createUser(
      normaliseNumber(realNumber),
      normaliseNumber(maskedNumber),
      'pro',
      15
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
    const normalisedContact = normaliseNumber(contactNumber);
    await addToPhonebook(user.id, normalisedContact, contactName);
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
 * DELETE /api/phonebook/remove
 * Remove a contact from phonebook
 * Body: { realNumber, contactNumber }
 */
app.delete('/api/phonebook/remove', async (req, res) => {
  const { realNumber, contactNumber } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    
    const normalisedContact = normaliseNumber(contactNumber);
    await pool.query(
      'DELETE FROM phonebook WHERE user_id = $1 AND contact_number = $2',
      [user.id, normalisedContact]
    );
    res.json({ message: `${contactNumber} removed from phonebook` });
  } catch (err) {
    res.status(500).json({ error: 'Failed to remove contact' });
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
    const logDays = getLogDays(user);
    const [calls, messages] = await Promise.all([
      getCallLog(user.id, 50),
      getSMSLog(user.id, 50)
    ]);
    // Filter by plan log days
    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - logDays);
    const filteredCalls = calls.filter(c => new Date(c.called_at) > cutoff);
    const filteredMessages = messages.filter(m => new Date(m.sent_at) > cutoff);
    res.json({ calls: filteredCalls, messages: filteredMessages, planLogDays: logDays });
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
    const planExpired = isPlanExpired(user);
    const planDetails = getPlan(user.plan);
    res.json({
      maskedNumber: user.masked_number,
      plan: user.plan,
      planName: planDetails.name,
      active: user.active && !planExpired,
      expired: planExpired,
      expiresAt: user.expires_at,
      features: {
        deliveryMode: canUseDeliveryMode(user),
        smsForwarding: canUseSmsForwarding(user),
        logDays: getLogDays(user),
        maskedNumbers: planDetails.maskedNumbers,
      }
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get user' });
  }
});

/**
 * GET /exotel/connect-params
 * Called by Exotel Connect applet to get the number to dial
 * Returns the real number for the masked number being called
 */
app.get('/exotel/connect-params', async (req, res) => {
  const maskedNumber = normaliseNumber(req.query.To || req.query.CallTo);
  console.log('🔗 connect-params for masked:', maskedNumber);
  try {
    const user = await getUserByMaskedNumber(maskedNumber);
    if (!user) return res.sendStatus(404);
    // Exotel Connect dynamic params format
    res.json({
      Number: user.real_number.replace(/^\+91/, '0'),
    });
  } catch (err) {
    console.error('connect-params error:', err);
    res.sendStatus(500);
  }
});

/**
 * POST /api/delivery-mode
 * Enable delivery mode for X hours — allow ALL callers
 * Body: { realNumber, hours }
 */
app.post('/api/delivery-mode', async (req, res) => {
  const { realNumber, hours = 1 } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    // Plan check
    if (!canUseDeliveryMode(user)) {
      return res.status(403).json({ 
        error: 'Delivery Mode requires Pro or Family plan',
        upgrade: true,
        currentPlan: user.plan
      });
    }
    const openUntil = await enableDeliveryMode(user.id, hours);
    console.log(`🚚 Delivery Mode ON for ${realNumber} until ${openUntil}`);
    res.json({ message: `Delivery Mode active for ${hours} hour(s)`, openUntil });
  } catch (err) {
    console.error('delivery-mode error:', err);
    res.status(500).json({ error: 'Failed to enable delivery mode' });
  }
});

/**
 * POST /api/delivery-mode/off
 * Disable delivery mode immediately
 */
app.post('/api/delivery-mode/off', async (req, res) => {
  const { realNumber } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    await disableDeliveryMode(user.id);
    console.log(`🛡️ Delivery Mode OFF for ${realNumber}`);
    res.json({ message: 'Shield restored — delivery mode disabled' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to disable delivery mode' });
  }
});

/**
 * GET /api/delivery-mode?realNumber=+91XXXXXXXXXX
 * Check if delivery mode is active
 */
app.get('/api/delivery-mode', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    const openUntil = await isDeliveryModeActive(user.id);
    res.json({ active: !!openUntil, openUntil: openUntil || null });
  } catch (err) {
    res.status(500).json({ error: 'Failed to check delivery mode' });
  }
});

/**
 * POST /api/fcm-token
 * Register device FCM token for push notifications
 * Body: { realNumber, fcmToken }
 */
app.post('/api/fcm-token', async (req, res) => {
  const { realNumber, fcmToken } = req.body;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    await saveFcmToken(user.id, fcmToken);
    res.json({ message: 'FCM token saved' });
  } catch (err) {
    console.error('fcm-token error:', err);
    res.status(500).json({ error: 'Failed to save token' });
  }
});

/**
 * POST /api/admin/upgrade
 * Admin endpoint to manually upgrade a user's plan
 * Body: { realNumber, plan, days }
 */
app.post('/api/admin/upgrade', async (req, res) => {
  const { realNumber, plan = 'pro', days = 30, adminKey } = req.body;
  // Simple admin key check
  if (adminKey !== 'shieldinfo-admin-nikisha-2026') {
    return res.status(403).json({ error: 'Unauthorized' });
  }
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    const { pool } = require('./db');
    await pool.query(
      `UPDATE users SET plan=$1, active=true, expires_at=NOW() + INTERVAL '${days} days' WHERE id=$2`,
      [plan, user.id]
    );
    console.log(`✅ Admin upgraded ${realNumber} to ${plan} for ${days} days`);
    res.json({ message: `${realNumber} upgraded to ${plan} for ${days} days` });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Health check
app.get('/health', (_, res) => res.json({ status: 'ok', app: 'ShieldInfo' }));

/**
 * GET /debug/call-test?caller=+91XXXXXXXXXX&masked=+91YYYYYYYYYY
 *
 * Simulates the Exotel webhook WITHOUT making a real call.
 * Use this in browser to diagnose why calls are being blocked.
 * e.g. https://yourapp.railway.app/debug/call-test?caller=+918980003138&masked=+919513886363
 */
app.get('/webhook/debug', async (req, res) => {
  const caller = normaliseNumber(req.query.caller || '');
  const masked = normaliseNumber(req.query.masked || '');

  if (!caller || !masked) {
    return res.json({ error: 'Pass ?caller=+91XXXXXXXXXX&masked=+91YYYYYYYYYY' });
  }

  const result = { caller, masked, steps: [] };

  try {
    const user = await getUserByMaskedNumber(masked);
    if (!user) {
      result.steps.push({ step: 'user_lookup', result: 'FAIL — no user for this masked number' });
      result.verdict = 'BLOCKED';
      return res.json(result);
    }
    result.steps.push({ step: 'user_lookup', result: `OK — user id=${user.id} plan=${user.plan} active=${user.active}` });

    const expired = new Date(user.expires_at) < new Date();
    result.steps.push({ step: 'plan_expiry', result: expired ? `EXPIRED at ${user.expires_at}` : `OK — expires ${user.expires_at}` });

    const inPhonebook = await isInPhonebook(user.id, caller);
    result.steps.push({ step: 'phonebook_check', result: inPhonebook ? 'FOUND ✅' : 'NOT FOUND ❌' });

    if (inPhonebook) {
      result.verdict = 'ALLOW — phonebook match';
      result.real_number = user.real_number;
      return res.json(result);
    }

    const inTemp = await isInTempWhitelist(user.id, caller);
    result.steps.push({ step: 'temp_whitelist_check', result: inTemp ? 'FOUND ✅' : 'NOT FOUND' });

    const deliveryMode = await isDeliveryModeActive(user.id);
    result.steps.push({ step: 'delivery_mode', result: deliveryMode ? `ACTIVE until ${deliveryMode}` : 'OFF' });

    if (inTemp || deliveryMode) {
      result.verdict = 'ALLOW';
    } else {
      result.verdict = 'BLOCK — not in phonebook or whitelist';
    }

    return res.json(result);
  } catch (err) {
    return res.json({ error: err.message, verdict: 'ERROR — this is why calls are blocked!' });
  }
});

// ═══════════════════════════════════════════════════════════════
//  SIM BOX ENDPOINTS (Android phone with Jio SIM)
// ═══════════════════════════════════════════════════════════════

const SIM_SECRET = process.env.SIM_SECRET || 'shieldinfo-sim-secret-2026';

function verifySIMSecret(req, res) {
  const secret = req.headers['x-sim-secret'];
  if (secret !== SIM_SECRET) {
    console.warn('⚠️  SIM Box: invalid secret from', req.ip);
    res.status(403).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

/**
 * POST /webhook/sms-inbound
 * Called by the Android SIM Box app when an SMS arrives on the Jio SIM.
 * Forwards the content to the real user via push notification.
 *
 * Body: { from, body, simNumber, timestamp }
 * Header: X-Sim-Secret
 */
app.post('/webhook/sms-inbound', async (req, res) => {
  if (!verifySIMSecret(req, res)) return;

  const { from, body: smsBody, simNumber } = req.body;
  if (!from || !smsBody || !simNumber) {
    return res.status(400).json({ error: 'Missing from, body, or simNumber' });
  }

  try {
    const maskedNum = normaliseNumber(simNumber);
    const user = await getUserByMaskedNumber(maskedNum);

    if (!user) {
      console.warn(`📩 SMS arrived for unknown SIM: ${maskedNum}`);
      return res.status(404).json({ error: 'No user for this SIM' });
    }

    // Log the SMS
    await logSMS(user.id, normaliseNumber(from), maskedNum, smsBody, 'inbound');

    // Push-notify the real user with the SMS content
    const fcmToken = await getFcmToken(user.id);
    if (fcmToken) {
      await sendPushNotification(
        fcmToken,
        `📩 SMS from ${from}`,
        smsBody,
        { type: 'inbound_sms', from, maskedNumber: maskedNum }
      );
      console.log(`✅ SMS forwarded: ${from} → user ${user.id} via push`);
    } else {
      console.warn(`⚠️  No FCM token for user ${user.id} — SMS received but not forwarded`);
    }

    res.json({ forwarded: !!fcmToken, userId: user.id });
  } catch (err) {
    console.error('SMS inbound error:', err);
    res.status(500).json({ error: 'Internal error' });
  }
});

/**
 * POST /webhook/simbox-heartbeat
 * Called by Android app every 5 minutes to confirm it's alive.
 */
app.post('/webhook/simbox-heartbeat', async (req, res) => {
  if (!verifySIMSecret(req, res)) return;
  const { simNumber, timestamp } = req.body;
  console.log(`💓 SIM Box heartbeat: ${simNumber} at ${new Date(timestamp).toISOString()}`);
  res.json({ alive: true, serverTime: new Date().toISOString() });
});

/**
 * GET /api/sms-log  (authenticated)
 * Returns SMS history for the logged-in user.
 */
app.get('/api/sms-log', requireAuth, async (req, res) => {
  try {
    const log = await getSMSLog(req.userId, 50);
    res.json({ smsLog: log });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

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
🔒 ShieldInfo backend running on port ${PORT}

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


// ═══════════════════════════════════════════════════════════════
//  PAYMENTS (Razorpay)
// ═══════════════════════════════════════════════════════════════

const Razorpay = require('razorpay');
const crypto  = require('crypto');

const razorpay = new Razorpay({
  key_id:     process.env.RAZORPAY_KEY_ID     || 'your_razorpay_key_id',
  key_secret: process.env.RAZORPAY_KEY_SECRET || 'your_razorpay_secret',
});

const PLANS = {
  basic:  { amount: 9900,  label: 'Basic',  months: 1 },
  pro:    { amount: 19900, label: 'Pro',     months: 1 },
  family: { amount: 39900, label: 'Family',  months: 1 },
};

/**
 * POST /api/payment/create-order
 * Creates a Razorpay order for the selected plan
 * Body: { realNumber, plan }
 */
app.post('/api/payment/create-order', async (req, res) => {
  const { realNumber, plan } = req.body;
  const planData = PLANS[plan];
  if (!planData) return res.status(400).json({ error: 'Invalid plan' });

  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });

    const order = await razorpay.orders.create({
      amount:   planData.amount,
      currency: 'INR',
      receipt:  `shieldinfo_${user.id}_${Date.now()}`,
      notes:    { userId: user.id, plan, realNumber },
    });

    // Save pending payment to DB
    
    await pool.query(
      `INSERT INTO payments (user_id, razorpay_order_id, amount, plan, status)
       VALUES ($1, $2, $3, $4, 'pending')`,
      [user.id, order.id, planData.amount, plan]
    );

    res.json({
      orderId:  order.id,
      amount:   order.amount,
      currency: order.currency,
      plan,
      planLabel: planData.label,
    });
  } catch (err) {
    console.error('create-order error:', err);
    res.status(500).json({ error: 'Failed to create order' });
  }
});

/**
 * POST /api/payment/verify
 * Verifies Razorpay payment signature and activates plan
 * Body: { razorpay_order_id, razorpay_payment_id, razorpay_signature, realNumber, plan }
 */
app.post('/api/payment/verify', async (req, res) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature, realNumber, plan } = req.body;

  try {
    // Verify signature
    const body = `${razorpay_order_id}|${razorpay_payment_id}`;
    const expectedSig = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET || 'your_razorpay_secret')
      .update(body)
      .digest('hex');

    if (expectedSig !== razorpay_signature) {
      return res.status(400).json({ error: 'Invalid payment signature' });
    }

    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });

    

    // Update payment record
    await pool.query(
      `UPDATE payments SET razorpay_payment_id=$1, status='paid'
       WHERE razorpay_order_id=$2`,
      [razorpay_payment_id, razorpay_order_id]
    );

    // Activate plan — extend expiry by 30 days
    await pool.query(
      `UPDATE users SET plan=$1, active=true,
       expires_at = NOW() + INTERVAL '30 days'
       WHERE id=$2`,
      [plan, user.id]
    );

    console.log(`✅ Payment verified — ${realNumber} upgraded to ${plan}`);
    res.json({ success: true, plan, message: `${plan} plan activated!` });

  } catch (err) {
    console.error('verify payment error:', err);
    res.status(500).json({ error: 'Payment verification failed' });
  }
});

/**
 * GET /api/payment/history?realNumber=+91XXXXXXXXXX
 */
app.get('/api/payment/history', async (req, res) => {
  const { realNumber } = req.query;
  try {
    const user = await getUserByRealNumber(normaliseNumber(realNumber));
    if (!user) return res.status(404).json({ error: 'User not found' });
    
    const result = await pool.query(
      `SELECT * FROM payments WHERE user_id=$1 ORDER BY created_at DESC LIMIT 10`,
      [user.id]
    );
    res.json({ payments: result.rows });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get payment history' });
  }
});
