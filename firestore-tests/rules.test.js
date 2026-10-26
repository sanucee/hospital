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
  getDoc,
  increment,
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

  test('staff can reserve sequence numbers', async () => {
    await assertSucceeds(updateDoc(doc(as('rec'), 'meta/counters'), { mrn: 2 }));
    await assertFails(updateDoc(doc(as('stranger'), 'meta/counters'), { mrn: 3 }));
  });
});
