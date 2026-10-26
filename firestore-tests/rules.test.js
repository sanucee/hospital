// Security-rules tests. Run with `npm test` (starts the Firestore emulator).
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayUnion,
  deleteDoc,
  doc,
  collection,
  getDoc,
  getDocs,
  increment,
  query,
  where,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-hospital',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

after(() => env.cleanup());

const roles = {
  admin: 'admin',
  rec: 'receptionist',
  doc: 'doctor',
  lab: 'labTechnician',
  pha: 'pharmacist',
  nur: 'nurse',
  acc: 'accountant',
  rad: 'radiographer',
  sto: 'storekeeper',
};

/** Seeds a set-up hospital with one account per role, bypassing rules. */
async function seedHospital() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'meta/setup'), { by: 'admin' });
    await setDoc(doc(db, 'meta/counters'), { mrn: 1 });
    for (const [uid, role] of Object.entries(roles)) {
      await setDoc(doc(db, `roles/${uid}`), { role, staffId: `USR-${uid}` });
    }
    await setDoc(doc(db, 'patients/p1'), { name: 'Pat' });
    await setDoc(doc(db, 'labOrders/o1'), { status: 'ordered', result: '' });
    await setDoc(doc(db, 'medicines/m1'), { name: 'Para', stock: 100 });
    await setDoc(doc(db, 'notifications/n1'), { title: 'Hi', readBy: [] });
    await setDoc(doc(db, 'invoiceLines/l1'), { invoiceId: 'i1', unitPrice: 5 });
    await setDoc(doc(db, 'salaries/USR-doc'), { basic: 5000 });
    await setDoc(doc(db, 'admissions/a1'), { patientId: 'p1' });
    await setDoc(doc(db, 'surgeries/s1'), { status: 'scheduled' });
    await setDoc(doc(db, 'leaves/lv1'), { staffId: 'USR-lab', status: 'pending' });
  });
}

const as = (uid) => env.authenticatedContext(uid).firestore();

beforeEach(() => env.clearFirestore());

describe('first-run setup', () => {
  test('the first user can make themselves admin together with meta/setup', async () => {
    const db = as('founder');
    const batch = writeBatch(db);
    batch.set(doc(db, 'roles/founder'), { role: 'admin', staffId: 'USR-admin' });
    batch.set(doc(db, 'meta/setup'), { by: 'founder' });
    await assertSucceeds(batch.commit());
  });

  test('nobody can claim admin once the hospital is set up', async () => {
    await seedHospital();
    const db = as('latecomer');
    const batch = writeBatch(db);
    batch.set(doc(db, 'roles/latecomer'), { role: 'admin', staffId: 'X' });
    batch.set(doc(db, 'meta/setup'), { by: 'latecomer' });
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(db, 'roles/latecomer'), { role: 'admin', staffId: 'X' }));
  });

  test('setup cannot grant a non-admin role or skip the setup marker', async () => {
    const db = as('founder');
    await assertFails(setDoc(doc(db, 'roles/founder'), { role: 'admin', staffId: 'X' }));
    const batch = writeBatch(db);
    batch.set(doc(db, 'roles/founder'), { role: 'doctor', staffId: 'X' });
    batch.set(doc(db, 'meta/setup'), { by: 'founder' });
    await assertFails(batch.commit());
  });
});

describe('access control', () => {
  beforeEach(seedHospital);

  test('signed-out users and accounts without a role read nothing', async () => {
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'patients/p1')));
    await assertFails(getDoc(doc(as('stranger'), 'patients/p1')));
    await assertFails(getDoc(doc(as('stranger'), 'roles/admin')));
  });

  test('every staff role can read clinical data', async () => {
    for (const uid of Object.keys(roles)) {
      await assertSucceeds(getDoc(doc(as(uid), 'patients/p1')));
    }
  });

  test('staff can read only their own role; admin can read all', async () => {
    await assertSucceeds(getDoc(doc(as('doc'), 'roles/doc')));
    await assertFails(getDoc(doc(as('doc'), 'roles/lab')));
    await assertSucceeds(getDoc(doc(as('admin'), 'roles/lab')));
  });

  test('only admins manage staff and roles', async () => {
    await assertFails(setDoc(doc(as('doc'), 'roles/doc'), { role: 'admin', staffId: 'X' }));
    await assertFails(setDoc(doc(as('rec'), 'users/u1'), { name: 'x' }));
    await assertSucceeds(setDoc(doc(as('admin'), 'roles/newbie'), { role: 'doctor', staffId: 'U' }));
    await assertSucceeds(setDoc(doc(as('admin'), 'users/u1'), { name: 'x' }));
    await assertSucceeds(deleteDoc(doc(as('admin'), 'roles/lab')));
  });

  test('reception registers patients; lab and pharmacy cannot', async () => {
    await assertSucceeds(setDoc(doc(as('rec'), 'patients/p2'), { name: 'New' }));
    await assertFails(setDoc(doc(as('lab'), 'patients/p3'), { name: 'New' }));
    await assertFails(setDoc(doc(as('pha'), 'patients/p3'), { name: 'New' }));
    await assertFails(deleteDoc(doc(as('rec'), 'patients/p1')));
  });

  test('doctors order lab tests; the lab results them but cannot order', async () => {
    await assertSucceeds(setDoc(doc(as('doc'), 'labOrders/o2'), { status: 'ordered' }));
    await assertFails(setDoc(doc(as('lab'), 'labOrders/o3'), { status: 'ordered' }));
    await assertSucceeds(updateDoc(doc(as('lab'), 'labOrders/o1'), { status: 'completed', result: '5.1' }));
    await assertFails(updateDoc(doc(as('pha'), 'labOrders/o1'), { result: 'x' }));
  });

  test('only the pharmacy changes stock, and increments are allowed', async () => {
    await assertSucceeds(updateDoc(doc(as('pha'), 'medicines/m1'), { stock: increment(-10) }));
    await assertFails(updateDoc(doc(as('doc'), 'medicines/m1'), { stock: increment(-10) }));
    await assertFails(updateDoc(doc(as('lab'), 'medicines/m1'), { stock: 0 }));
  });

  test('doctors prescribe and the pharmacy dispenses', async () => {
    await assertSucceeds(setDoc(doc(as('doc'), 'prescriptions/r1'), { status: 'pending' }));
    await assertFails(setDoc(doc(as('pha'), 'prescriptions/r2'), { status: 'pending' }));
    await assertSucceeds(updateDoc(doc(as('pha'), 'prescriptions/r1'), { status: 'dispensed' }));
    await assertFails(updateDoc(doc(as('rec'), 'prescriptions/r1'), { status: 'dispensed' }));
  });

  test('any department can bill; the lab can remove a cancelled charge', async () => {
    for (const uid of ['doc', 'lab', 'pha', 'rec']) {
      await assertSucceeds(setDoc(doc(as(uid), `invoiceLines/x-${uid}`), { invoiceId: 'i1' }));
    }
    await assertSucceeds(deleteDoc(doc(as('lab'), 'invoiceLines/l1')));
    await assertFails(setDoc(doc(as('stranger'), 'invoiceLines/x'), { invoiceId: 'i1' }));
  });

  test('notifications can only be marked as read', async () => {
    await assertSucceeds(updateDoc(doc(as('doc'), 'notifications/n1'), { readBy: arrayUnion('USR-doc') }));
    await assertFails(updateDoc(doc(as('doc'), 'notifications/n1'), { title: 'Edited' }));
    await assertSucceeds(setDoc(doc(as('lab'), 'notifications/n2'), { title: 'Result', readBy: [] }));
    await assertFails(deleteDoc(doc(as('doc'), 'notifications/n1')));
  });

  test('only admin and accounts see or change salaries, payroll and expenses', async () => {
    for (const uid of ['doc', 'nur', 'rec', 'lab', 'pha', 'stranger']) {
      await assertFails(getDoc(doc(as(uid), 'salaries/USR-doc')));
      await assertFails(setDoc(doc(as(uid), 'expenses/e1'), { amount: 1 }));
      await assertFails(setDoc(doc(as(uid), 'payslips/x'), { net: 1 }));
    }
    for (const uid of ['admin', 'acc']) {
      await assertSucceeds(getDoc(doc(as(uid), 'salaries/USR-doc')));
      await assertSucceeds(setDoc(doc(as(uid), `expenses/e-${uid}`), { amount: 10 }));
      await assertSucceeds(setDoc(doc(as(uid), `payslips/p-${uid}`), { net: 10 }));
    }
  });

  test('wards: clinical staff admit and discharge; only admin sets room rates', async () => {
    for (const uid of ['rec', 'doc', 'nur']) {
      await assertSucceeds(updateDoc(doc(as(uid), 'admissions/a1'), { reason: uid }));
    }
    await assertFails(updateDoc(doc(as('acc'), 'admissions/a1'), { reason: 'x' }));
    await assertFails(setDoc(doc(as('nur'), 'rooms/r1'), { dailyRate: 1 }));
    await assertSucceeds(setDoc(doc(as('admin'), 'rooms/r1'), { dailyRate: 40 }));
  });

  test('doctors book surgeries; nurses run them but cannot book', async () => {
    await assertSucceeds(setDoc(doc(as('doc'), 'surgeries/s2'), { status: 'scheduled' }));
    await assertFails(setDoc(doc(as('nur'), 'surgeries/s3'), { status: 'scheduled' }));
    await assertSucceeds(updateDoc(doc(as('nur'), 'surgeries/s1'), { status: 'inProgress' }));
    await assertFails(updateDoc(doc(as('rec'), 'surgeries/s1'), { status: 'cancelled' }));
  });

  test('staff request their own leave; only admin decides', async () => {
    await assertSucceeds(setDoc(doc(as('nur'), 'leaves/lv2'), { staffId: 'USR-nur', status: 'pending' }));
    await assertFails(setDoc(doc(as('nur'), 'leaves/lv3'), { staffId: 'USR-doc', status: 'pending' }));
    await assertFails(setDoc(doc(as('nur'), 'leaves/lv4'), { staffId: 'USR-nur', status: 'approved' }));
    await assertFails(updateDoc(doc(as('lab'), 'leaves/lv1'), { status: 'approved' }));
    await assertSucceeds(updateDoc(doc(as('admin'), 'leaves/lv1'), { status: 'approved' }));
  });

  test('cashiers record payments; others cannot', async () => {
    for (const uid of ['rec', 'pha', 'acc']) {
      await assertSucceeds(setDoc(doc(as(uid), `payments/pm-${uid}`), { amount: 5 }));
    }
    await assertFails(setDoc(doc(as('doc'), 'payments/pm-doc'), { amount: 5 }));
    await assertFails(updateDoc(doc(as('rec'), 'payments/pm-rec'), { amount: 500 }));
  });

  test('insurance: front office and accounts work claims; insurers are set by admin/accounts', async () => {
    for (const uid of ['rec', 'acc', 'admin']) {
      await assertSucceeds(setDoc(doc(as(uid), `claims/c-${uid}`), { status: 'draft' }));
    }
    await assertFails(setDoc(doc(as('doc'), 'claims/c-doc'), { status: 'draft' }));
    await assertFails(setDoc(doc(as('pha'), 'claims/c-pha'), { status: 'draft' }));
    await assertSucceeds(setDoc(doc(as('acc'), 'insurers/i1'), { coveragePercent: 80 }));
    await assertFails(setDoc(doc(as('rec'), 'insurers/i2'), { coveragePercent: 100 }));
    await assertSucceeds(getDoc(doc(as('doc'), 'insurers/i1')));
  });

  test('purchasing: pharmacy orders and receives; accounts may only mark paid', async () => {
    await assertSucceeds(setDoc(doc(as('pha'), 'suppliers/s1'), { name: 'MedSupply' }));
    await assertFails(setDoc(doc(as('doc'), 'suppliers/s2'), { name: 'X' }));
    await assertSucceeds(setDoc(doc(as('pha'), 'purchaseOrders/po1'), { status: 'ordered', items: [] }));
    await assertFails(setDoc(doc(as('acc'), 'purchaseOrders/po2'), { status: 'ordered' }));
    await assertSucceeds(updateDoc(doc(as('acc'), 'purchaseOrders/po1'), { paidAt: '2026-10-26', expenseId: 'e1' }));
    await assertFails(updateDoc(doc(as('acc'), 'purchaseOrders/po1'), { status: 'received' }));
    await assertFails(updateDoc(doc(as('rec'), 'purchaseOrders/po1'), { paidAt: 'x' }));
  });

  test('only the admin edits hospital details', async () => {
    await assertSucceeds(setDoc(doc(as('admin'), 'settings/profile'), { name: 'H' }));
    await assertFails(setDoc(doc(as('acc'), 'settings/profile'), { name: 'X' }));
    await assertSucceeds(getDoc(doc(as('nur'), 'settings/profile')));
  });

  test('nursing records are created by clinical staff and never edited', async () => {
    await assertSucceeds(setDoc(doc(as('nur'), 'vitals/v1'), { pulse: 80 }));
    await assertSucceeds(setDoc(doc(as('doc'), 'nursingNotes/n1'), { text: 'ok' }));
    await assertSucceeds(setDoc(doc(as('nur'), 'medicationDoses/d1'), { status: 'given' }));
    await assertFails(setDoc(doc(as('rec'), 'vitals/v2'), { pulse: 80 }));
    await assertFails(updateDoc(doc(as('nur'), 'vitals/v1'), { pulse: 60 }));
    await assertFails(deleteDoc(doc(as('admin'), 'medicationDoses/d1')));
    await assertSucceeds(setDoc(doc(as('doc'), 'medicationOrders/o1'), { dose: '1 g' }));
    await assertFails(setDoc(doc(as('nur'), 'medicationOrders/o2'), { dose: '1 g' }));
  });

  test('audit log: append in your own name, admin-only reads, no edits', async () => {
    await assertSucceeds(setDoc(doc(as('rec'), 'auditLog/a1'), { userId: 'USR-rec', action: 'updated' }));
    await assertFails(setDoc(doc(as('rec'), 'auditLog/a2'), { userId: 'USR-admin', action: 'updated' }));
    await assertFails(setDoc(doc(as('stranger'), 'auditLog/a3'), { userId: 'x' }));
    await assertFails(getDoc(doc(as('rec'), 'auditLog/a1')));
    await assertFails(getDoc(doc(as('acc'), 'auditLog/a1')));
    await assertSucceeds(getDoc(doc(as('admin'), 'auditLog/a1')));
    await assertFails(updateDoc(doc(as('admin'), 'auditLog/a1'), { action: 'nothing' }));
    await assertFails(deleteDoc(doc(as('admin'), 'auditLog/a1')));
  });

  test('doctors edit only their own schedule; admins edit any', async () => {
    await assertSucceeds(setDoc(doc(as('doc'), 'schedules/USR-doc'), { slotMinutes: 15 }));
    await assertFails(setDoc(doc(as('doc'), 'schedules/USR-other'), { slotMinutes: 15 }));
    await assertFails(setDoc(doc(as('rec'), 'schedules/USR-doc'), { slotMinutes: 10 }));
    await assertSucceeds(setDoc(doc(as('admin'), 'schedules/USR-other'), { slotMinutes: 20 }));
    await assertSucceeds(getDoc(doc(as('rec'), 'schedules/USR-doc')));
  });

  test('reminders are queued and sent by the front office', async () => {
    await assertSucceeds(setDoc(doc(as('rec'), 'reminders/r1'), { status: 'pending' }));
    await assertSucceeds(setDoc(doc(as('doc'), 'reminders/r2'), { status: 'pending' }));
    await assertSucceeds(updateDoc(doc(as('rec'), 'reminders/r2'), { status: 'sent' }));
    await assertFails(setDoc(doc(as('lab'), 'reminders/r3'), { status: 'pending' }));
    await assertFails(deleteDoc(doc(as('rec'), 'reminders/r1')));
  });

  test('cashiers run their own till; payments go only into it', async () => {
    const till = { cashierId: 'USR-rec', openingFloat: 50, closedAt: null };
    await assertSucceeds(setDoc(doc(as('rec'), 'tills/t1'), till));
    await assertFails(setDoc(doc(as('rec'), 'tills/t2'), { ...till, cashierId: 'USR-pha' }));
    await assertFails(setDoc(doc(as('doc'), 'tills/t3'), { ...till, cashierId: 'USR-doc' }));
    await assertFails(getDoc(doc(as('lab'), 'tills/t1')));
    // Payments into your own open till; not into someone else's.
    await assertSucceeds(setDoc(doc(as('rec'), 'payments/p1'), { amount: 5, tillId: 't1' }));
    await assertFails(setDoc(doc(as('pha'), 'payments/p2'), { amount: 5, tillId: 't1' }));
    await assertFails(updateDoc(doc(as('rec'), 'tills/t1'), { openingFloat: 500 }));
    await assertFails(updateDoc(doc(as('pha'), 'tills/t1'), { closedAt: 'now' }));
    await assertSucceeds(updateDoc(doc(as('rec'), 'tills/t1'), {
      closedAt: 'now', countedCash: 55, expectedCash: 55,
    }));
    // Closed: no more payments or edits by the cashier; accounts can still correct it.
    await assertFails(setDoc(doc(as('rec'), 'payments/p3'), { amount: 5, tillId: 't1' }));
    await assertFails(updateDoc(doc(as('rec'), 'tills/t1'), { countedCash: 60 }));
    await assertSucceeds(updateDoc(doc(as('acc'), 'tills/t1'), { notes: 'checked' }));
  });

  test('refunds: requested, approved by someone else, paid out as a negative payment', async () => {
    const ask = {
      requestedBy: 'USR-rec', status: 'pending', amount: 10, paymentId: 'pm1',
    };
    await assertSucceeds(setDoc(doc(as('rec'), 'refunds/r1'), ask));
    // A cashier can't approve, nor create one already approved.
    await assertFails(setDoc(doc(as('rec'), 'refunds/r2'), {
      ...ask, status: 'approved', decidedBy: 'USR-rec',
    }));
    await assertFails(updateDoc(doc(as('rec'), 'refunds/r1'), {
      status: 'approved', decidedBy: 'USR-rec',
    }));
    await assertFails(getDoc(doc(as('doc'), 'refunds/r1')));
    // Accounts can't approve their own, but can approve the cashier's.
    await assertSucceeds(setDoc(doc(as('acc'), 'refunds/r3'), {
      ...ask, requestedBy: 'USR-acc', status: 'approved', decidedBy: 'USR-acc',
    }));
    await assertSucceeds(setDoc(doc(as('acc'), 'refunds/r4'), { ...ask, requestedBy: 'USR-acc' }));
    await assertFails(updateDoc(doc(as('acc'), 'refunds/r4'), {
      status: 'approved', decidedBy: 'USR-acc',
    }));
    await assertFails(updateDoc(doc(as('acc'), 'refunds/r1'), {
      status: 'approved', decidedBy: 'USR-acc', amount: 99,
    }));
    await assertSucceeds(updateDoc(doc(as('acc'), 'refunds/r1'), {
      status: 'approved', decidedBy: 'USR-acc',
    }));

    // A negative payment without a matching paid refund is refused.
    await assertFails(setDoc(doc(as('rec'), 'payments/x1'), { amount: -10 }));
    await assertFails(setDoc(doc(as('rec'), 'payments/x2'), { amount: -10, refundId: 'r1' }));
    const db = as('rec');
    const wrongAmount = writeBatch(db);
    wrongAmount.update(doc(db, 'refunds/r1'), { status: 'paid', paidBy: 'USR-rec' });
    wrongAmount.set(doc(db, 'payments/x3'), { amount: -50, refundId: 'r1' });
    await assertFails(wrongAmount.commit());
    const payout = writeBatch(db);
    payout.update(doc(db, 'refunds/r1'), { status: 'paid', paidBy: 'USR-rec', number: 'RFD-1' });
    payout.set(doc(db, 'payments/x4'), { amount: -10, refundId: 'r1' });
    await assertSucceeds(payout.commit());
    // Paid once only.
    await assertFails(updateDoc(doc(as('pha'), 'refunds/r1'), { status: 'paid', paidBy: 'USR-pha' }));
  });

  test('staff can reserve sequence numbers', async () => {
    await assertSucceeds(updateDoc(doc(as('rec'), 'meta/counters'), { mrn: 2 }));
    await assertFails(updateDoc(doc(as('stranger'), 'meta/counters'), { mrn: 3 }));
  });

  test('emergency: front desk and clinicians run the board; clinicians register unknowns', async () => {
    await assertSucceeds(setDoc(doc(as('rec'), 'emergencyVisits/e1'), { status: 'waitingTriage' }));
    await assertSucceeds(updateDoc(doc(as('nur'), 'emergencyVisits/e1'), { status: 'waitingDoctor' }));
    await assertSucceeds(updateDoc(doc(as('doc'), 'emergencyVisits/e1'), { status: 'beingSeen' }));
    await assertFails(setDoc(doc(as('lab'), 'emergencyVisits/e2'), { status: 'waitingTriage' }));
    await assertFails(deleteDoc(doc(as('nur'), 'emergencyVisits/e1')));
    await assertSucceeds(setDoc(doc(as('nur'), 'patients/p2'), { name: 'Unknown male' }));
    await assertFails(updateDoc(doc(as('nur'), 'patients/p1'), { name: 'Changed' }));
  });

  test('radiology: doctors request, radiographers report and keep the catalogue', async () => {
    await assertSucceeds(setDoc(doc(as('doc'), 'imagingOrders/i1'), { status: 'ordered' }));
    await assertFails(setDoc(doc(as('rad'), 'imagingOrders/i2'), { status: 'ordered' }));
    await assertSucceeds(updateDoc(doc(as('rad'), 'imagingOrders/i1'), { status: 'reported' }));
    await assertFails(updateDoc(doc(as('lab'), 'imagingOrders/i1'), { status: 'cancelled' }));
    await assertSucceeds(setDoc(doc(as('rad'), 'imagingStudies/s1'), { name: 'CT head' }));
    await assertFails(setDoc(doc(as('doc'), 'imagingStudies/s2'), { name: 'MRI' }));
  });

  test('blood bank: the lab holds stock; doctors request and may withdraw before cross-match', async () => {
    await assertSucceeds(setDoc(doc(as('lab'), 'bloodUnits/u1'), { status: 'available' }));
    await assertFails(setDoc(doc(as('doc'), 'bloodUnits/u2'), { status: 'available' }));
    await assertSucceeds(setDoc(doc(as('lab'), 'bloodDonors/d1'), { name: 'Donor' }));
    await assertFails(setDoc(doc(as('nur'), 'bloodDonors/d2'), { name: 'Donor' }));
    const ask = { doctorId: 'USR-doc', status: 'pending', unitIds: [] };
    await assertSucceeds(setDoc(doc(as('doc'), 'bloodRequests/r1'), ask));
    await assertSucceeds(setDoc(doc(as('doc'), 'bloodRequests/r2'), ask));
    await assertFails(setDoc(doc(as('doc'), 'bloodRequests/r3'), { ...ask, status: 'issued' }));
    await assertFails(setDoc(doc(as('nur'), 'bloodRequests/r4'), ask));
    // A doctor can't cross-match, but can withdraw their own pending request.
    await assertFails(updateDoc(doc(as('doc'), 'bloodRequests/r1'), { status: 'reserved' }));
    await assertSucceeds(updateDoc(doc(as('doc'), 'bloodRequests/r1'), {
      status: 'cancelled', cancelReason: 'Not needed',
    }));
    await assertSucceeds(updateDoc(doc(as('lab'), 'bloodRequests/r2'), { status: 'reserved' }));
    await assertFails(updateDoc(doc(as('doc'), 'bloodRequests/r2'), { status: 'cancelled' }));
    // The lab records the patient's blood group, and nothing else.
    await assertSucceeds(updateDoc(doc(as('lab'), 'patients/p1'), { bloodGroup: 'A+' }));
    await assertFails(updateDoc(doc(as('lab'), 'patients/p1'), { name: 'Changed' }));
  });

  test('general store: anyone requisitions in their own name; the store issues', async () => {
    await assertSucceeds(setDoc(doc(as('sto'), 'storeItems/g1'), { name: 'Gloves', stock: 10 }));
    await assertFails(setDoc(doc(as('nur'), 'storeItems/g2'), { name: 'Gauze', stock: 10 }));
    await assertSucceeds(updateDoc(doc(as('sto'), 'storeItems/g1'), { stock: increment(-2) }));
    const req = { requestedBy: 'USR-nur', status: 'pending' };
    await assertSucceeds(setDoc(doc(as('nur'), 'requisitions/q1'), req));
    await assertSucceeds(setDoc(doc(as('nur'), 'requisitions/q2'), req));
    await assertFails(setDoc(doc(as('nur'), 'requisitions/q3'), { ...req, requestedBy: 'USR-doc' }));
    await assertFails(setDoc(doc(as('nur'), 'requisitions/q4'), { ...req, status: 'issued' }));
    await assertFails(updateDoc(doc(as('nur'), 'requisitions/q1'), { status: 'issued' }));
    await assertSucceeds(updateDoc(doc(as('nur'), 'requisitions/q1'), { status: 'cancelled' }));
    await assertFails(updateDoc(doc(as('doc'), 'requisitions/q2'), { status: 'cancelled' }));
    await assertSucceeds(updateDoc(doc(as('sto'), 'requisitions/q2'), { status: 'issued' }));
    // The stock card is append-only and written by the store.
    await assertSucceeds(setDoc(doc(as('sto'), 'stockMovements/m1'), { quantity: -2 }));
    await assertFails(setDoc(doc(as('nur'), 'stockMovements/m2'), { quantity: 5 }));
    await assertFails(updateDoc(doc(as('sto'), 'stockMovements/m1'), { quantity: -1 }));
  });
});

describe('patient portal', () => {
  /** Two patients with portal accounts, and some of their records. */
  async function seedPortal() {
    await seedHospital();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, 'roles/pat1'), { role: 'patient', patientId: 'p1' });
      await setDoc(doc(db, 'roles/pat2'), { role: 'patient', patientId: 'p2' });
      await setDoc(doc(db, 'patients/p2'), { name: 'Other', phone: '1' });
      await setDoc(doc(db, 'appointments/a1'), { patientId: 'p1', status: 'scheduled' });
      await setDoc(doc(db, 'appointments/a2'), { patientId: 'p2', status: 'scheduled' });
      await setDoc(doc(db, 'labOrders/r1'), { patientId: 'p1', reviewedByDoctor: true });
      await setDoc(doc(db, 'labOrders/r2'), { patientId: 'p1', reviewedByDoctor: false });
      await setDoc(doc(db, 'bookedSlots/D_1000'), { doctorId: 'D', appointmentId: 'a2' });
      await setDoc(doc(db, 'directory/D'), { name: 'Dr D' });
      await setDoc(doc(db, 'settings/profile'), { name: 'H' });
    });
  }

  const online = (id, patientId) => ({
    id,
    patientId,
    doctorId: 'D',
    status: 'scheduled',
    channel: 'online',
    tokenNumber: null,
    bookedBy: null,
  });

  test('patients read only their own records and released results', async () => {
    await seedPortal();
    const db = as('pat1');
    await assertSucceeds(getDoc(doc(db, 'patients/p1')));
    await assertFails(getDoc(doc(db, 'patients/p2')));
    await assertSucceeds(getDocs(query(collection(db, 'appointments'), where('patientId', '==', 'p1'))));
    await assertFails(getDocs(collection(db, 'appointments')));
    await assertFails(getDoc(doc(db, 'appointments/a2')));
    await assertSucceeds(getDocs(query(
      collection(db, 'labOrders'),
      where('patientId', '==', 'p1'),
      where('reviewedByDoctor', '==', true),
    )));
    await assertFails(getDoc(doc(db, 'labOrders/r2')));
    for (const c of ['schedules', 'bookedSlots', 'directory', 'settings']) {
      await assertSucceeds(getDocs(collection(db, c)));
    }
    for (const c of ['users', 'leaves', 'notifications', 'medicines', 'payments']) {
      await assertFails(getDocs(collection(db, c)));
    }
    await assertFails(updateDoc(doc(db, 'meta/counters'), { mrn: 9 }));
  });

  test('patients count as staff nowhere', async () => {
    await seedPortal();
    const db = as('pat1');
    await assertFails(setDoc(doc(db, 'invoices/x'), { patientId: 'p1' }));
    await assertFails(setDoc(doc(db, 'labOrders/x'), { patientId: 'p1' }));
    await assertFails(setDoc(doc(db, 'directory/D'), { name: 'Hacked' }));
  });

  test('patients book online for themselves with a free slot', async () => {
    await seedPortal();
    const db = as('pat1');
    const ok = writeBatch(db);
    ok.set(doc(db, 'appointments/a3'), online('a3', 'p1'));
    ok.set(doc(db, 'bookedSlots/D_1100'), { doctorId: 'D', appointmentId: 'a3' });
    ok.set(doc(db, 'reminders/m3'), { patientId: 'p1', status: 'pending' });
    ok.set(doc(db, 'notifications/n3'), {
      patientId: 'p1', targetRole: 'receptionist', targetUserId: null, readBy: [],
    });
    ok.set(doc(db, 'auditLog/x3'), { userId: 'p1' });
    await assertSucceeds(ok.commit());

    // The slot is taken: writing it again is an update, which is refused.
    const taken = writeBatch(db);
    taken.set(doc(db, 'appointments/a4'), online('a4', 'p1'));
    taken.set(doc(db, 'bookedSlots/D_1000'), { doctorId: 'D', appointmentId: 'a4' });
    await assertFails(taken.commit());

    // Not for someone else, not checked in, not as a counter booking.
    await assertFails(setDoc(doc(db, 'appointments/a5'), online('a5', 'p2')));
    await assertFails(setDoc(doc(db, 'appointments/a6'), { ...online('a6', 'p1'), status: 'checkedIn' }));
    await assertFails(setDoc(doc(db, 'appointments/a7'), { ...online('a7', 'p1'), channel: 'counter' }));
    // A slot for another patient's appointment.
    await assertFails(setDoc(doc(db, 'bookedSlots/D_1200'), { doctorId: 'D', appointmentId: 'a2' }));
    // Notifications only to reception, audit entries only in their own name.
    await assertFails(setDoc(doc(db, 'notifications/n4'), {
      patientId: 'p1', targetRole: 'doctor', targetUserId: null, readBy: [],
    }));
    await assertFails(setDoc(doc(db, 'auditLog/x4'), { userId: 'USR-admin' }));
  });

  test('patients cancel their own bookings and nothing else', async () => {
    await seedPortal();
    const db = as('pat1');
    await assertFails(updateDoc(doc(db, 'appointments/a1'), { status: 'scheduled', doctorId: 'X' }));
    await assertFails(updateDoc(doc(db, 'appointments/a1'), { status: 'completed' }));
    await assertFails(updateDoc(doc(db, 'appointments/a2'), { status: 'cancelled' }));
    await assertFails(deleteDoc(doc(db, 'bookedSlots/D_1000')));
    await assertSucceeds(updateDoc(doc(as('pat2'), 'appointments/a2'), { status: 'cancelled' }));
    await assertSucceeds(deleteDoc(doc(as('pat2'), 'bookedSlots/D_1000')));
    await assertSucceeds(updateDoc(doc(db, 'appointments/a1'), { status: 'cancelled' }));
  });

  test('patients update only their contact details', async () => {
    await seedPortal();
    const db = as('pat1');
    await assertSucceeds(updateDoc(doc(db, 'patients/p1'), { phone: '0803', email: 'a@b.c' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { allergies: '' }));
    await assertFails(updateDoc(doc(db, 'patients/p1'), { insurerId: 'INS-1' }));
    await assertFails(updateDoc(doc(db, 'patients/p2'), { phone: '0803' }));
  });

  test('a new patient registers online only as a new record they own', async () => {
    await seedPortal();
    const db = as('newbie');
    const reg = (pid, data) => {
      const b = writeBatch(db);
      b.set(doc(db, `patients/${pid}`), { id: pid, insurerId: null, portalUid: 'newbie', ...data });
      b.set(doc(db, 'roles/newbie'), { role: 'patient', patientId: pid });
      return b.commit();
    };
    // Claiming an existing patient's record, or insurance, or staff access.
    await assertFails(reg('p2', {}));
    await assertFails(reg('p9', { insurerId: 'INS-1' }));
    const staff = writeBatch(db);
    staff.set(doc(db, 'patients/p9'), { id: 'p9', insurerId: null, portalUid: 'newbie' });
    staff.set(doc(db, 'roles/newbie'), { role: 'receptionist', patientId: 'p9' });
    await assertFails(staff.commit());
    await assertSucceeds(reg('p9', { name: 'New' }));
    // Already registered: can't create another record.
    await assertFails(setDoc(doc(db, 'patients/p10'), { id: 'p10', insurerId: null, portalUid: 'newbie' }));
  });

  test('reception gives existing patients portal accounts', async () => {
    await seedPortal();
    await assertSucceeds(setDoc(doc(as('rec'), 'roles/acct1'), { role: 'patient', patientId: 'p1' }));
    await assertFails(setDoc(doc(as('rec'), 'roles/acct2'), { role: 'doctor', staffId: 'X' }));
    await assertFails(setDoc(doc(as('rec'), 'roles/acct3'), { role: 'patient', patientId: 'nobody' }));
    await assertFails(setDoc(doc(as('lab'), 'roles/acct4'), { role: 'patient', patientId: 'p1' }));
    await assertSucceeds(deleteDoc(doc(as('rec'), 'roles/acct1')));
    await assertFails(deleteDoc(doc(as('rec'), 'roles/doc')));
  });
});
