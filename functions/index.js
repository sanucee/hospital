// Cloud Functions for NAAK HMS.
//
// sendDueReminders: every 5 minutes, sends the SMS/WhatsApp appointment
// reminders the app has queued, through Twilio. It does nothing unless
// "Send reminders automatically" is switched on in the app's hospital
// details. Configure with:
//   firebase functions:secrets:set TWILIO_ACCOUNT_SID
//   firebase functions:secrets:set TWILIO_AUTH_TOKEN
//   firebase functions:secrets:set TWILIO_FROM            (e.g. +15005550006)
//   firebase functions:secrets:set TWILIO_WHATSAPP_FROM   (optional)
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { processDueReminders, twilioSender } = require('./reminders');

initializeApp();

const sid = defineSecret('TWILIO_ACCOUNT_SID');
const token = defineSecret('TWILIO_AUTH_TOKEN');
const from = defineSecret('TWILIO_FROM');
const whatsappFrom = defineSecret('TWILIO_WHATSAPP_FROM');

exports.sendDueReminders = onSchedule(
  {
    schedule: 'every 5 minutes',
    secrets: [sid, token, from, whatsappFrom],
    timeoutSeconds: 120,
  },
  async () => {
    const db = getFirestore();
    const profile = (await db.doc('settings/profile').get()).data() || {};
    if (!profile.autoSendReminders) return;
    const result = await processDueReminders(db, {
      now: new Date(),
      send: twilioSender({
        sid: sid.value(),
        token: token.value(),
        from: from.value(),
        whatsappFrom: whatsappFrom.value(),
      }),
    });
    logger.info('Reminders processed', result);
  },
);
