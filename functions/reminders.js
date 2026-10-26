// Sends appointment reminders that the app has queued in the `reminders`
// collection. Kept separate from index.js so it can be tested against the
// Firestore emulator with a fake sender.

/**
 * Sends every pending SMS/WhatsApp reminder whose `sendAt` (UTC ISO
 * string) has passed. Email reminders are left for staff to send.
 *
 * Each reminder is first claimed (status "sending") with a precondition on
 * its update time, so overlapping runs never send the same message twice.
 *
 * @param {FirebaseFirestore.Firestore} db
 * @param {{now: Date, send: (r: object) => Promise<void>, limit?: number}} opts
 * @returns {Promise<{sent: number, failed: number, skipped: number}>}
 */
async function processDueReminders(db, { now, send, limit = 200 }) {
  const snap = await db
    .collection('reminders')
    .where('status', '==', 'pending')
    .where('sendAt', '<=', now.toISOString())
    .orderBy('sendAt')
    .limit(limit)
    .get();
  const result = { sent: 0, failed: 0, skipped: 0 };
  for (const doc of snap.docs) {
    const r = doc.data();
    if (r.channel !== 'sms' && r.channel !== 'whatsapp') {
      result.skipped++;
      continue;
    }
    try {
      await doc.ref.update(
        { status: 'sending' },
        { lastUpdateTime: doc.updateTime },
      );
    } catch (_) {
      // Changed since we read it (claimed by another run, or cancelled).
      result.skipped++;
      continue;
    }
    try {
      await send(r);
      await doc.ref.update({
        status: 'sent',
        sentAt: new Date().toISOString(),
        sentBy: 'system',
        error: '',
      });
      result.sent++;
    } catch (e) {
      await doc.ref.update({
        status: 'failed',
        error: String((e && e.message) || e).slice(0, 300),
      });
      result.failed++;
    }
  }
  return result;
}

/**
 * A sender that uses Twilio's REST API for SMS and WhatsApp.
 * @param {{sid: string, token: string, from: string, whatsappFrom?: string}} cfg
 */
function twilioSender({ sid, token, from, whatsappFrom }) {
  const auth = Buffer.from(`${sid}:${token}`).toString('base64');
  return async (r) => {
    const whatsapp = r.channel === 'whatsapp';
    const body = new URLSearchParams({
      To: whatsapp ? `whatsapp:${r.to}` : r.to,
      From: whatsapp ? `whatsapp:${whatsappFrom || from}` : from,
      Body: r.message,
    });
    const res = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
      {
        method: 'POST',
        headers: {
          Authorization: `Basic ${auth}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body,
      },
    );
    if (!res.ok) {
      const detail = await res.text();
      throw new Error(`Twilio ${res.status}: ${detail}`);
    }
  };
}

module.exports = { processDueReminders, twilioSender };
