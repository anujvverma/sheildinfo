const axios = require('axios');

const {
  EXOTEL_ACCOUNT_SID,
  EXOTEL_API_KEY,
  EXOTEL_API_TOKEN,
  EXOTEL_SUBDOMAIN,
} = process.env;

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
 * Forward a call from virtual number to real number
 * Returns ExoML (XML) that Exotel executes
 */
function buildCallConnectXML(realNumber) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Dial>
    <Number>${realNumber}</Number>
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

module.exports = { sendSMS, buildCallConnectXML, buildCallBlockXML };
