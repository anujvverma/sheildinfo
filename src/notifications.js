let admin;
let firebaseApp;

try {
  admin = require('firebase-admin');
  const serviceAccount = {
    type: 'service_account',
    project_id: 'shieldinfo-48a33',
    private_key_id: 'b2bd01b977fe2bc158bbb640c6ee84a4bb8cd85b',
    private_key: (process.env.FIREBASE_PRIVATE_KEY || '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDnLESqbWlpICiN\nuU3yYpIufw5/GP3v3crWbtibBfqws5MmarMZKb23FrHKiz6pjM6WLE0STyKKBnGQ\nfBblO4KCjTPnSHiihE2ZKXybBGWiUb60ifqZwsZDliPtdzhoPvPnQPLmWXqVfpNv\niDEJpnDhCaYdSzFKNAfY3mEJpLpxXviu1NxW+NIHfep+83J90PtIheeJK0JPQg5N\nLKF2WqkZTQdTaQAWQ93La1iyHUJw1uvEx5eg4nSCaMzBn+tvOlH5scKY+1fPgTJY\nWIvm8SlvnVKJ05JuA3ZcB9B2liXgjdkCxohScBnlY6j0g4Rl5XI7MlBwi9YJJQRj\ng49xNXAtAgMBAAECggEAWeqDDtMdxBEJFQ71fYjPmRw8dD0xUGIxajSVNb8eoipG\n2xN3dBsjOpquLrz4c5RcKlcy5yM2qP8Wnv9VHHaILeVkQdqTaYsSb7eOSvFr4rXu\n+mQMwE/dNB6q/Mt5ejq6PcGqeORm5Mzl5eTQRhOiJjXNkelUU6tnPfhJQCn9huiP\nZF+vZjh87WRWNXp2HEhGFQypVKww5QyRpQw+dgcI551AUtCfBNuBaApYSFHUODya\nuRzvnfRJ6DsF7DQDJ3bz9JhTApkj17pAuKwxGsyvo65tVYxkm/8PmnOMGpI8S68G\n9Gpv1WzR/zrKG+ozV1ZUjUqA9xcmJZK5iQKY79A4VQKBgQD9cOg+CWZQPbHQsGH2\n3qfNJhGDdIWAkdGCwcb59QVunG4y+rqbo2qBW3AwFPvS/maIBAmaT09Xi2fqKgLm\nFz3tVLs3/nwfhytErOq//P1kvLSCSiHTs9elJapBmVukYhwIn7m4HMU/zGmgdW/h\ngmqQniJGNRCfqn4oQFGGl9umcwKBgQDpgc1yqw0q8yFwKp0OaMaEN8craoICSEvU\n825gWXpwBOsKxwqqu6yEe4M+rlzkoqVivc2UHzDqmvEyYTPMng2cvNys3DH3bYDB\nmk6ORYEON91nnRCJfJUMnsS7V6V4/Q96m3TQSpcF9r45o3qFlBNATOu+LCzLzw05\nhInhDjRG3wKBgFNy+NVsbObg2Yq4eRk7SQ8wiLW7CTZDTTP7sBOfjPFVyqc4jXcv\nwKLlQ7RhRGW95G7GvY60rJBL06Rzvs6aOobJzndqcN5EuId9VDJxD9I6nEkGNcsq\nPUggdcXxxA4FS+u/A/zOZFhUazctU/Bx67rAhtKNKHMaRT3lp7JkkCtnAoGAFRB4\nkBeOIIm+QngVou8guVyuwuPgxoPvE07Cbj6kJObMrTQ3ah9z+J+Lv2PLTXS+pqGo\noewOZZuElp7eJV88qx7+aTmT6FYgf1aEL6FlevrfJjGtBDoQ2AqahKvraXaqpszP\nRNr1tLwFfP2aV+J7uhk2SvmBMQGEl+O07HBzltECgYEA/ETeOyts1wow8d1Qv5RG\nGipB6vFA6JUv4K/Hx0WmSHZ4LnPCmMyohVNSFSHeipMiec1i/GPamVDjLFGazK0Q\nvYzcixuW7eCderroeQLA+w7zlW5ARujBxNaP9u+m3u3MHx14pAoG4fhP0pM+zING\ngDSEZfgvM2Oqz/+ydBMslbw=\n-----END PRIVATE KEY-----\n').replace(/\\n/g, '\n'),
    client_email: 'firebase-adminsdk-fbsvc@shieldinfo-48a33.iam.gserviceaccount.com',
    client_id: '108675039662669908822',
    auth_uri: 'https://accounts.google.com/o/oauth2/auth',
    token_uri: 'https://oauth2.googleapis.com/token',
  };
  firebaseApp = admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  console.log('✅ Firebase Admin initialized');
} catch (err) {
  console.warn('⚠️ Firebase Admin not available — push notifications disabled:', err.message);
}

async function sendPushNotification(fcmToken, title, body, data = {}) {
  if (!fcmToken || !firebaseApp || !admin) return;
  try {
    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data,
      apns: { payload: { aps: { badge: 1, sound: 'default', 'content-available': 1 } } },
      android: { priority: 'high', notification: { sound: 'default', channelId: 'shieldinfo_alerts' } },
    });
    console.log('📱 Push notification sent:', title);
  } catch (err) {
    console.warn('Push notification failed:', err.message);
  }
}

module.exports = { sendPushNotification };
