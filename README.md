# CareConnect HMS – Hospital Management App (Flutter)

A cross-platform Flutter app (Android, iOS, Web, Windows, macOS, Linux) that connects
**Reception, Doctors, Laboratory, Pharmacy and Billing** in one workflow.

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

All demo passwords are `1234` (one-tap buttons on the login screen).

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
flutter run              # pick a device: chrome, android, windows, ...
flutter test             # workflow + widget tests
```

## Project structure

```
lib/
  main.dart                    App, theme, login gate
  models/models.dart           Patients, appointments, consultations, lab orders,
                               medicines, prescriptions, invoices, notifications
  data/hospital_store.dart     Central store + all cross-department business rules
  data/seed_data.dart          Demo data
  data/storage.dart            Persistence (shared_preferences; in-memory for tests)
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
  widget_test.dart             Login, navigation and consultation UI
```

## Notes

- Data is stored locally on the device (`shared_preferences`). To share data across
  multiple devices, implement `StorageBackend` (in `lib/data/storage.dart`) against a server
  or Firebase; all business logic lives in `HospitalStore` and doesn't need to change.
- Passwords are stored in plain text for the demo. Use a real auth backend before production.
