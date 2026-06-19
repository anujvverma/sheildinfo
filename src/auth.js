// JWT-like auth using Node.js built-in crypto — no external packages needed
const crypto = require('crypto');

const SECRET = process.env.JWT_SECRET || 'shieldinfo-secret-2026-nikisha';

function generateToken(userId, realNumber) {
  const payload = Buffer.from(JSON.stringify({
    userId, realNumber, iat: Date.now(), exp: Date.now() + 30 * 24 * 60 * 60 * 1000
  })).toString('base64');
  const sig = crypto.createHmac('sha256', SECRET).update(payload).digest('base64');
  return `${payload}.${sig}`;
}

function verifyToken(token) {
  try {
    const [payload, sig] = token.split('.');
    if (!payload || !sig) return null;
    const expected = crypto.createHmac('sha256', SECRET).update(payload).digest('base64');
    if (expected !== sig) return null;
    const data = JSON.parse(Buffer.from(payload, 'base64').toString());
    if (data.exp < Date.now()) return null; // expired
    return data;
  } catch { return null; }
}

function requireAuth(req, res, next) {
  const publicPaths = ['/webhook/', '/health', '/api/register', '/api/auth/', '/exotel/', '/api/admin/', '/debug/', '/inbox', '/api/sms-log', '/api/admin/plivo/'];
  if (publicPaths.some(p => req.path.startsWith(p))) return next();

  const authHeader = req.headers['authorization'];
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) return res.status(401).json({ error: 'Authentication required', code: 'NO_TOKEN' });

  const decoded = verifyToken(token);
  if (!decoded) return res.status(401).json({ error: 'Invalid or expired token', code: 'INVALID_TOKEN' });

  req.userId = decoded.userId;
  req.realNumber = decoded.realNumber;
  next();
}

module.exports = { generateToken, verifyToken, requireAuth };
