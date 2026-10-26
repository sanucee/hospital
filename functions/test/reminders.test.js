// Runs against the Firestore emulator: `npm test`.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { processDueReminders } = require('../reminders');

let db;

before(() => {
  initializeApp({ projectId: 'demo-hospital' });
  db = getFirestore();
});

beforeEach(async () => {
  const docs = await db.collection('reminders').listDocuments();
  await Promise.all(docs.map((d) => d.delete()));
});

const now = new Date('2026-10-26T09:00:00.000Z');
const minutes = (m) => new Date(now.getTime() + m * 60000).toISOString();

async function seed(id, fields) {
  await db.doc(`reminders/${id}`).set({
    appointmentId: 'a',
    patientId: 'p',
    channel: 'sms',
    to: '+2348031112233',
    message: 'Hello',
    status: 'pending',
    sendAt: minutes(-5),
    error: '',
    ...fields,
  });
}

test('sends due SMS and WhatsApp reminders, leaves the rest', async () => {
  await seed('due-sms', {});
  await seed('due-wa', { channel: 'whatsapp' });
  await seed('future', { sendAt: minutes(30) });
  await seed('email', { channel: 'email', to: 'x@y.z' });
  await seed('cancelled', { status: 'cancelled' });
  const calls = [];
  const result = await processDueReminders(db, {
    now,
    send: async (r) => calls.push(`${r.channel}:${r.to}`),
  });
  assert.deepStrictEqual(result, { sent: 2, failed: 0, skipped: 1 });
  assert.deepStrictEqual(calls.sort(), ['sms:+2348031112233', 'whatsapp:+2348031112233']);
  const status = async (id) => (await db.doc(`reminders/${id}`).get()).data();
  assert.strictEqual((await status('due-sms')).status, 'sent');
  assert.strictEqual((await status('due-sms')).sentBy, 'system');
  assert.strictEqual((await status('future')).status, 'pending');
  assert.strictEqual((await status('email')).status, 'pending');
  assert.strictEqual((await status('cancelled')).status, 'cancelled');
});

test('records failures with the provider error', async () => {
  await seed('bad', { to: '+000' });
  const result = await processDueReminders(db, {
    now,
    send: async () => {
      throw new Error('Twilio 400: invalid number');
    },
  });
  assert.deepStrictEqual(result, { sent: 0, failed: 1, skipped: 0 });
  const r = (await db.doc('reminders/bad').get()).data();
  assert.strictEqual(r.status, 'failed');
  assert.match(r.error, /invalid number/);
});

test('overlapping runs send each reminder once', async () => {
  await seed('once', {});
  let calls = 0;
  const send = async () => {
    calls++;
  };
  await Promise.all([
    processDueReminders(db, { now, send }),
    processDueReminders(db, { now, send }),
  ]);
  assert.strictEqual(calls, 1);
  assert.strictEqual((await db.doc('reminders/once').get()).data().status, 'sent');
});
