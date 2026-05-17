// ─── PLAN DEFINITIONS ─────────────────────────────────────────
const PLANS = {
  trial: {
    name: 'Trial',
    maskedNumbers: 1,
    logDays: 7,
    deliveryMode: false,
    smsForwarding: false,
    tempWhitelist: true,
    durationDays: 7,
  },
  basic: {
    name: 'Basic',
    maskedNumbers: 1,
    logDays: 30,
    deliveryMode: false,
    smsForwarding: true,
    tempWhitelist: true,
    durationDays: 30,
  },
  pro: {
    name: 'Pro',
    maskedNumbers: 2,
    logDays: 90,
    deliveryMode: true,
    smsForwarding: true,
    tempWhitelist: true,
    durationDays: 30,
  },
  family: {
    name: 'Family',
    maskedNumbers: 5,
    logDays: 365,
    deliveryMode: true,
    smsForwarding: true,
    tempWhitelist: true,
    durationDays: 30,
  },
};

function getPlan(planName) {
  return PLANS[planName] || PLANS.trial;
}

function isTrialExpired(user) {
  if (user.plan !== 'trial') return false;
  return new Date() > new Date(user.expires_at);
}

function isPlanExpired(user) {
  if (user.plan === 'trial') return isTrialExpired(user);
  return new Date() > new Date(user.expires_at);
}

function canUseDeliveryMode(user) {
  if (isPlanExpired(user)) return false;
  return getPlan(user.plan).deliveryMode;
}

function canUseSmsForwarding(user) {
  if (isPlanExpired(user)) return false;
  return getPlan(user.plan).smsForwarding;
}

function getLogDays(user) {
  return getPlan(user.plan).logDays;
}

module.exports = { PLANS, getPlan, isTrialExpired, isPlanExpired, canUseDeliveryMode, canUseSmsForwarding, getLogDays };
