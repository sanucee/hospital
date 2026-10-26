# CareConnect HMS – Hospital Management App (Flutter)

A cross-platform Flutter app (Android, iOS, Web, Windows, macOS, Linux) that connects
**Reception, Doctors, Laboratory, Pharmacy and Billing** in one workflow, with an optional
**Firebase backend** so every department's devices share the same live data.

![Admin dashboard](docs/screenshots/admin-dashboard.png)

## How the departments connect

```
Reception ──check-in──▶ Doctor queue ──order tests──▶ Laboratory queue
    │                       │    ▲                         │
    │                       │    └──── result + alert ─────┘
    │                       └──prescribe──▶ Pharmacy queue ──dispense──▶ stock deducted
    │                                                              │
    └──────────────── one invoice per visit ◀── consultation fee + lab tests + medicines
```

| Step | Who | What happens automatically |
|------|-----|----------------------------|
| Register / book / walk-in | Reception | Patient gets an MRN; check-in assigns a queue token and notifies the doctor |
| Consultation | Doctor | Opens an invoice with the doctor's fee; records vitals, complaints, diagnosis, notes |
| Order lab tests | Doctor | Orders appear in the lab work queue (urgent first); tests are billed; lab is notified |
| Collect sample / enter result | Laboratory | Doctor is notified (abnormal results flagged); result shows in the consultation and patient record |
| Prescribe | Doctor | Prescription appears in the pharmacy queue, with live stock levels and allergy warnings |
| Dispense | Pharmacy | Stock is deducted (full or partial), dispensed items are billed, doctor is notified, low-stock alerts raised |
| Complete visit | Doctor | Appointment closed; optional follow-up appointment auto-booked |
| Payment | Reception / Pharmacy | Consolidated bill split by department; discounts and part-payments |

Every patient has a single **medical record** showing visits, lab results, prescriptions and bills
from all departments.

## Roles & demo accounts

In local mode all demo passwords are `1234` (one-tap buttons on the login screen).
In Firebase mode, staff sign in with an email account created by the administrator.

| Username | Role | Access |
|----------|------|--------|
| `admin` | Administrator | Everything, staff management, reset demo data |
| `reception` | Reception | Patients, appointments, check-in, billing |
| `doctor`, `cardio`, `peds` | Doctors | Own queue, consultations, lab results, patient records |
| `lab` | Laboratory | Work queue, results, test catalogue |
| `pharmacy` | Pharmacy | Dispensing, inventory (restock, expiry/low-stock alerts), billing |

## Running

```bash
flutter pub get
flutter run              # local mode: data stays on this device
flutter test             # workflow, multi-device sync and widget tests
```

## Firebase backend (multi-device sync)

With `--dart-define=USE_FIREBASE=true` the app stores everything in **Cloud Firestore** and
signs staff in with **Firebase Authentication**. A lab result entered on the lab's PC shows
up on the doctor's tablet within a second, stock dispensed at the pharmacy counter updates
every screen, and so on. Devices keep working offline and sync when the connection returns.

### One-time project setup

1. Create a project at <https://console.firebase.google.com>, then:
   - **Authentication → Sign-in method**: enable **Email/Password**.
   - **Firestore Database**: create a database.
2. Connect the app (generates `lib/firebase_options.dart`, replacing the placeholder):
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
3. Deploy the security rules:
   ```bash
   npm install -g firebase-tools
   firebase login
   firebase use --add            # pick your project
   firebase deploy --only firestore:rules
   ```
4. Run with Firebase enabled:
   ```bash
   flutter run --dart-define=USE_FIREBASE=true
   flutter build web --dart-define=USE_FIREBASE=true   # or apk, windows, ...
   ```
5. On first launch choose **"First time? Set up a new hospital"**. This makes you the
   administrator (only possible once per project) and creates the lab-test catalogue and
   medicine list, plus optional demo patients and staff.
6. Under **Staff**, use **Add staff** (or **Create login** on a demo staff member) to give
   each doctor, lab technician, pharmacist and receptionist an email and password.

### Local development with the emulators

No Firebase project is needed:

```bash
firebase emulators:start --only firestore,auth --project demo-hospital
flutter run -d chrome --dart-define=USE_FIREBASE=true \
  --dart-define=FIREBASE_EMULATOR_HOST=localhost       # 10.0.2.2 for the Android emulator
```

Security-rules tests run against the Firestore emulator:

```bash
cd firestore-tests && npm install && npm test
```

### How sync handles departments working at the same time

- Every record is its own Firestore document, and changes are written **field by field**,
  so the lab entering a result and the doctor marking another field on the same order
  don't overwrite each other.
- **Medicine stock** and **invoice payments** are written as atomic increments, so two
  pharmacists dispensing at once both get deducted.
- **Invoice lines** are separate documents, so the doctor's fee, lab tests and pharmacy
  charges can be added to the same bill from different devices at the same moment.
- **MRN, invoice and queue-token numbers** come from a shared counter updated in a
  transaction. Offline, a device falls back to a unique time-based number (e.g.
  `MRN-TL2X9QK`) rather than blocking registration.
- **Security rules** (`firestore.rules`) give each role write access only to its own
  department's records: reception registers patients, doctors order tests and prescribe,
  the lab results tests, the pharmacy changes stock, and only administrators manage staff.
  Accounts without a staff role can't read anything.

### Limitations

- Firebase mode runs on Android, iOS, macOS and web. FlutterFire's Windows support is meant
  for development, and Linux has no Firebase SDK, so use local mode there.
- Each device loads the whole hospital into memory. That's fine for a clinic or small
  hospital. A large hospital with years of records would need query-based loading (e.g.
  only today's queue and the open patient's history).
- The stock check happens on the dispensing device, so two devices dispensing the very
  last units at the same instant can take stock below zero. Neither deduction is lost.
- Removing a staff member revokes their access, but their Firebase Auth account remains.
  Delete it in the Firebase console, or add a Cloud Function using the Admin SDK.
- Staff accounts are created with the client SDK, so keep Email/Password sign-up enabled.
  Anyone can create an account in the project, but without a role it has no access.

## Project structure

```
lib/
  main.dart                    App, theme, login gate
  models/models.dart           Patients, appointments, consultations, lab orders,
                               medicines, prescriptions, invoices, notifications
  data/hospital_store.dart     Central store + all cross-department business rules
  data/seed_data.dart          Demo data
  data/backend.dart            Backend interface + local (on-device) backend
  data/firebase_backend.dart   Firestore sync, Firebase Auth, shared counters
  data/firebase_setup.dart     Firebase initialisation (real project or emulators)
  data/storage.dart            Key-value storage for local mode
  firebase_options.dart        Placeholder; generated by `flutterfire configure`
  screens/
    home_shell.dart            Role-based navigation (rail on wide screens, drawer on phones)
    dashboard_screen.dart      Per-role KPIs and activity feed
    patient_detail_screen.dart Unified medical record
    reception/                 Patients & appointments
    doctor/                    Queue & consultation (lab orders, prescriptions)
    lab/                       Lab queue, results, catalogue
    pharmacy/                  Dispensing & inventory
    billing/                   Invoices & payments
    admin/                     Staff management
test/
  hospital_store_test.dart     End-to-end patient journey across departments
  firebase_sync_test.dart      Several devices sharing one database, concurrent edits
  widget_test.dart             Login, navigation and consultation UI
firestore.rules                Role-based security rules
firestore-tests/               Security-rules tests (Firestore emulator)
```

## Notes

- In local mode, data is stored on the device (`shared_preferences`) and demo passwords are
  stored in plain text. Use Firebase mode for real deployments: passwords are handled by
  Firebase Auth and never stored in the database.
