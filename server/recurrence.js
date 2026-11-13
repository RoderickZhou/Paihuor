const DAY = 86_400_000;
const SHANGHAI = 8 * 3600_000;

function parseRule(rule, deadline) {
  if (!rule || typeof rule !== 'object') return null;
  if (!['weekly', 'monthly', 'afterDone'].includes(rule.kind)) return null;
  if (!Number.isSafeInteger(deadline) || deadline < 0 || deadline > 8_640_000_000_000_000 - 366 * DAY) return null;
  if (rule.kind !== 'afterDone') return deadline > 0 ? { kind: rule.kind, days: 0 } : null;
  return Number.isInteger(rule.days) && rule.days >= 1 && rule.days <= 365 ? { kind: rule.kind, days: rule.days } : null;
}

function nextDeadline(series, now) {
  const { kind, days, scheduledAt, anchorAt, completedAt, skippedAt } = series;
  if (kind === 'afterDone') {
    const base = skippedAt ? Math.max(skippedAt, scheduledAt) : completedAt || now;
    const next = base + days * DAY;
    return next > now ? next : now + days * DAY;
  }
  if (kind === 'weekly') {
    return scheduledAt + Math.max(1, Math.floor((now - scheduledAt) / (7 * DAY)) + 1) * 7 * DAY;
  }
  const anchor = new Date(anchorAt + SHANGHAI);
  const cursor = new Date(Math.max(now, scheduledAt) + SHANGHAI);
  let year = cursor.getUTCFullYear();
  let month = cursor.getUTCMonth();
  function candidate() {
    const last = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
    return Date.UTC(year, month, Math.min(anchor.getUTCDate(), last), anchor.getUTCHours(),
      anchor.getUTCMinutes(), anchor.getUTCSeconds(), anchor.getUTCMilliseconds()) - SHANGHAI;
  }
  let next = candidate();
  if (next <= Math.max(now, scheduledAt)) {
    if (++month === 12) { month = 0; year++; }
    next = candidate();
  }
  return next;
}

module.exports = { parseRule, nextDeadline };
