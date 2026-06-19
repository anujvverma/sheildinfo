const plivo = require('plivo');

const AUTH_ID    = process.env.PLIVO_AUTH_ID;
const AUTH_TOKEN = process.env.PLIVO_AUTH_TOKEN;
const WEBHOOK_URL = process.env.PLIVO_WEBHOOK_URL || 'https://sheildinfo-production.up.railway.app';

const client = new plivo.Client(AUTH_ID, AUTH_TOKEN);

// ─── NUMBER POOL ──────────────────────────────────────────────

/**
 * Search for available Indian (+91) numbers to buy.
 * Returns array of { number, monthly_rental_rate, ... }
 */
async function searchAvailableNumbers(countryISO = 'IN', limit = 10) {
  try {
    const res = await client.numbers.search(countryISO, { limit });
    return res.objects || [];
  } catch (err) {
    console.error('Plivo searchAvailableNumbers error:', err.message);
    throw err;
  }
}

/**
 * Buy a number from Plivo.
 * After buying, configure its webhooks automatically.
 */
async function buyAndConfigureNumber(number) {
  try {
    // Buy the number
    await client.numbers.buy(number, 'IN');
    console.log(`✅ Bought Plivo number: ${number}`);

    // Configure SMS + voice webhooks
    await client.numbers.update(number, {
      sms_url:    `${WEBHOOK_URL}/webhook/plivo-sms`,
      sms_method: 'POST',
      answer_url:    `${WEBHOOK_URL}/webhook/plivo-call`,
      answer_method: 'POST',
    });
    console.log(`✅ Webhooks configured for: ${number}`);

    return number;
  } catch (err) {
    console.error('Plivo buyAndConfigureNumber error:', err.message);
    throw err;
  }
}

/**
 * List all numbers already in your Plivo account.
 */
async function listOwnedNumbers() {
  try {
    const res = await client.numbers.list({ limit: 100 });
    return res.objects || [];
  } catch (err) {
    console.error('Plivo listOwnedNumbers error:', err.message);
    throw err;
  }
}

/**
 * Configure webhooks on an already-owned number.
 * Call this once manually for numbers you already own.
 */
async function configureWebhooks(number) {
  try {
    await client.numbers.update(number, {
      sms_url:       `${WEBHOOK_URL}/webhook/plivo-sms`,
      sms_method:    'POST',
      answer_url:    `${WEBHOOK_URL}/webhook/plivo-call`,
      answer_method: 'POST',
    });
    console.log(`✅ Webhooks set for ${number}`);
    return true;
  } catch (err) {
    console.error('Plivo configureWebhooks error:', err.message);
    throw err;
  }
}

// ─── SMS ─────────────────────────────────────────────────────

/**
 * Send an SMS via Plivo.
 * src = your Plivo number, dst = recipient, text = message
 */
async function sendSMS(src, dst, text) {
  try {
    const res = await client.messages.create(src, dst, text);
    console.log(`📤 SMS sent from ${src} to ${dst}: messageUUID=${res.messageUuid}`);
    return res;
  } catch (err) {
    console.error('Plivo sendSMS error:', err.message);
    throw err;
  }
}

// ─── CALL XML BUILDERS ────────────────────────────────────────

/**
 * Build XML to forward the call to the user's real number.
 * callerId = the masked number (what the called party sees)
 * realNumber = user's real phone
 */
function buildCallForwardXML(realNumber, callerId) {
  const r = plivo.Response();
  const dialParams = {
    callerId:  callerId,
    callerName: 'ShieldInfo',
    timeout:   30,
    redirect:  false,
    confirmSound: '',
  };
  const dial = r.addDial(dialParams);
  dial.addNumber(realNumber);
  return r.toXML();
}

/**
 * Build XML to reject/block the call.
 */
function buildCallBlockXML(reason = 'Not in phonebook') {
  const r = plivo.Response();
  r.addSpeak(`Sorry, this call could not be connected.`);
  r.addHangup();
  return r.toXML();
}

/**
 * Build XML to play a ring tone while we look up the user (async answer).
 */
function buildCallWaitXML() {
  const r = plivo.Response();
  r.addWait({ length: 2 });
  return r.toXML();
}

// ─── CALL MANAGEMENT ─────────────────────────────────────────

/**
 * Initiate an outbound call (for future use: callback feature).
 */
async function makeCall(from, to, answerUrl) {
  try {
    const res = await client.calls.create(from, to, answerUrl);
    console.log(`📞 Call initiated from ${from} to ${to}`);
    return res;
  } catch (err) {
    console.error('Plivo makeCall error:', err.message);
    throw err;
  }
}

module.exports = {
  client,
  searchAvailableNumbers,
  buyAndConfigureNumber,
  listOwnedNumbers,
  configureWebhooks,
  sendSMS,
  buildCallForwardXML,
  buildCallBlockXML,
  buildCallWaitXML,
  makeCall,
};
