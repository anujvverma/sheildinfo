const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'shieldinfo-secret-2026-nikisha';
const JWT_EXPIRES = '30d';

function generateToken(userId, realNumber) {
  return jwt.sign({ userId, realNumber }, JWT_SECRET, { expiresIn: JWT_EXPIRES });
}

function verifyToken(token) {
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch {
    return null;
  }
}

// Middleware — protects API routes
function requireAuth(req, res, next) {
  // Skip auth for webhooks, health, register, and auth endpoints
  const publicPaths = ['/webhook/', '/health', '/api/register', '/api/auth/', '/exotel/', '/api/admin/'];
  if (publicPaths.some(p => req.path.startsWith(p))) return next();

  const authHeader = req.headers['authorization'];
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) {
    return res.status(401).json({ error: 'Authentication required', code: 'NO_TOKEN' });
  }

  const decoded = verifyToken(token);
  if (!decoded) {
    return res.status(401).json({ error: 'Invalid or expired token', code: 'INVALID_TOKEN' });
  }

  req.userId = decoded.userId;
  req.realNumber = decoded.realNumber;
  next();
}

module.exports = { generateToken, verifyToken, requireAuth };
