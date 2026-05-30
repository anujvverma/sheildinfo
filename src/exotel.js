const axios = require('axios');

const EXOTEL_ACCOUNT_SID = process.env.EXOTEL_ACCOUNT_SID || 'anujvvermahuf1';
const EXOTEL_API_KEY     = process.env.EXOTEL_API_KEY     || '4f08f8a472b917e81e4f2fd39e741b7bd621eef676b04499';
const EXOTEL_API_TOKEN   = process.env.EXOTEL_API_TOKEN   || 'd479c1b0fe955bcea97b1cad9aad0d779188a115cee81028';
const EXOTEL_SUBDOMAIN   = process.env.EXOTEL_SUBDOMAIN   || 'api.exotel.com';

// Base URL for Singapore region
const BASE_URL = `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_ACCOUNT_SID}`;

/**
 * Send an SMS from your virtual number to any number
 */
async function sendSMS(to, from, message) {
  try {
    const res = await axios.post(`${BASE_URL}/Sms/send`, null, {
      params: {
        From: from,
        To: to,
        Body: message,
      },
    });
    return res.data;
  } catch (err) {
    console.error('Exotel sendSMS error:', err.response?.data || err.message);
    throw err;
  }
}

/**
 * Use Exotel REST API to bridge an incoming call to the real number
 * This is the correct way to do dynamic call routing in Exotel
 */
async function connectCall(callSid, realNumber, maskedNumber) {
  const fmt = n => n.replace(/^\+91/, '0');
  try {
    const res = await axios.post(
      `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_ACCOUNT_SID}/Calls/connect`,
      null,
      {
        params: {
          CallSid: callSid,
          From: fmt(maskedNumber),
          To: fmt(realNumber),
          CallerId: fmt(maskedNumber),
        }
      }
    );
    console.log('✅ Exotel connect call success:', res.data);
    return res.data;
  } catch (err) {
    console.error('Exotel connectCall error:', err.response?.data || err.message);
    throw err;
  }
}

/**
 * Forward a call from virtual number to real number
 * Returns ExoML (XML) that Exotel executes
 */
function buildCallConnectXML(realNumber, callerId) {
  const fmt = n => n.replace(/^\+91/, '0');
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Dial callerId="${fmt(callerId || '')}">
    <Number>${fmt(realNumber)}</Number>
  </Dial>
</Response>`;
}

/**
 * Block a call — plays "not reachable" and hangs up
 */
function buildCallBlockXML() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say>The number you have dialled is not reachable. Please try again later.</Say>
  <Hangup/>
</Response>`;
}

/**
 * Play a "please wait" while we check the whitelist
 */
function buildCallWaitXML() {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Play>http://www.mfiles.co.uk/mp3-downloads/brahms-hungarian-dance-5.mp3</Play>
</Response>`;
}

/**
 * Add a contact to Exotel Address Book
 * Required for trial accounts — only address book numbers can call through
 */
async function addToExotelAddressBook(phoneNumber, name = '') {
  try {
    const fmt = n => n.replace(/^\+91/, '0');
    const res = await axios.post(
      `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_ACCOUNT_SID}/Contacts`,
      null,
      {
        params: {
          PhoneNumber: fmt(phoneNumber),
          Name: name || phoneNumber,
        }
      }
    );
    console.log(`✅ Added ${phoneNumber} to Exotel Address Book`);
    return res.data;
  } catch (err) {
    // Don't throw — Exotel address book sync is non-critical
    console.warn(`⚠️ Exotel address book sync failed for ${phoneNumber}:`, err.response?.data || err.message);
  }
}

/**
 * Remove a contact from Exotel Address Book
 */
async function removeFromExotelAddressBook(phoneNumber) {
  try {
    const fmt = n => n.replace(/^\+91/, '0');
    await axios.delete(
      `https://${EXOTEL_API_KEY}:${EXOTEL_API_TOKEN}@${EXOTEL_SUBDOMAIN}/v1/Accounts/${EXOTEL_ACCOUNT_SID}/Contacts/${fmt(phoneNumber)}`
    );
    console.log(`✅ Removed ${phoneNumber} from Exotel Address Book`);
  } catch (err) {
    console.warn(`⚠️ Exotel address book remove failed for ${phoneNumber}:`, err.response?.data || err.message);
  }
}

module.exports = { sendSMS, connectCall, buildCallConnectXML, buildCallBlockXML, addToExotelAddressBook, removeFromExotelAddressBook };
