# Installing NAAK HMS on several computers

This guide sets NAAK HMS up so that every computer in the hospital (reception, doctors'
rooms, laboratory, radiology, pharmacy, wards, store, accounts) works on **the same live
data**. A lab result entered on the lab PC appears on the doctor's PC within a second.

It is written for whoever sets the hospital up (the "administrator"). Steps marked
**(once)** are done one time; steps marked **(each PC)** are repeated on every computer.

---

## 1. How the network works

```
 Reception PC ─┐
 Doctor PC ────┤                         ┌───────────────────────────────┐
 Lab PC ───────┼── internet (HTTPS) ───▶ │ Firebase (Google Cloud)       │
 Pharmacy PC ──┤                         │  • Firestore: hospital data   │
 Ward tablet ──┘                         │  • Authentication: logins     │
                                         │  • Hosting: the web app       │
                                         └───────────────────────────────┘
```

- The computers don't talk to each other directly. Each one connects to **your own
  Firebase project**, a database that belongs to your hospital's Google account.
- Every computer keeps an **offline copy**. If the internet drops, staff keep working and
  their changes are sent when the connection returns.
- **Security rules** decide what each role may see and change (for example, only accounts
  and administrators see salaries; only the lab enters results). They are part of this
  project (`firestore.rules`) and you upload them in step 4.
- Each person signs in with **their own email and password**, created by the administrator.

> **Without internet:** the networked setup needs internet on every computer, except for
> short outages. A hospital with no internet can only run NAAK HMS on one computer
> (section 11). Sharing data over a local network without internet would need a
> self-hosted server, which NAAK HMS doesn't include.

## 2. What you need

| Item | Notes |
|---|---|
| A Google account for the hospital | Use a hospital account, not a personal one, and turn on 2-step verification. It owns all the data. |
| A Firebase project | Free to create. For real use choose the **Blaze** (pay as you go) plan and set a budget alert (step 3). |
| Internet on every computer | Ordinary broadband is enough. See section 9 for firewall settings. |
| One "setup" computer | Used once to connect the app to your project. Needs Flutter (already installed on this PC in `C:\Users\Khan\flutter`) and Node.js. |
| Windows 10 or 11 PCs (64-bit) | Or any computer, tablet or phone with an up-to-date browser (option A). |

**Why Blaze?** The free Spark plan allows 50,000 database reads and 20,000 writes per day.
Each computer loads the hospital's records when someone signs in, so a busy hospital
passes that limit within weeks and the app stops syncing until the next day. Blaze bills
only above those free amounts; a small hospital usually pays little. Check
<https://firebase.google.com/pricing> for current prices.

## 3. Create the Firebase project **(once)**

1. Go to <https://console.firebase.google.com> and sign in with the hospital Google
   account.
2. **Create a project**, e.g. `naak-hms`. Google Analytics isn't needed.
3. **Build → Authentication → Get started → Sign-in method:** enable **Email/Password**.
   (Leave "Email link" off.)
4. **Build → Firestore Database → Create database:**
   - Choose **production mode**.
   - Choose the location closest to the hospital, e.g. `asia-south1` (Mumbai). It can't be
     changed later.
5. **Upgrade to Blaze** (bottom left, *Spark → Upgrade*), then in
   <https://console.cloud.google.com/billing> → **Budgets & alerts**, create a budget (for
   example a monthly amount you're comfortable with) so you get an email if usage grows.

## 4. Connect the app to the project **(once, on the setup computer)**

Open PowerShell in the project folder (`C:\Users\Khan\Documents\HMS`).

1. Install [Node.js LTS](https://nodejs.org), then the Firebase tools:

   ```powershell
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   ```

   `firebase login` opens the browser: sign in with the hospital Google account.

2. Generate the connection file:

   ```powershell
   flutterfire configure --project=naak-hms --platforms=web,windows,android
   ```

   This replaces `lib/firebase_options.dart` with your project's settings. The values in it
   identify your project but are not passwords: access is controlled by sign-in and the
   security rules, so the file can be committed.

3. Upload the security rules and database indexes:

   ```powershell
   firebase use naak-hms
   firebase deploy --only firestore
   ```

4. Save the change to GitHub, so the Windows build (option B) picks it up:

   ```powershell
   git add lib/firebase_options.dart
   git commit -m "Connect NAAK HMS to the hospital's Firebase project"
   git push
   ```

## 5. Choose how the computers run NAAK HMS

Both options use the same data, so you can mix them (e.g. PCs on option B, ward tablets on
option A).

### Option A (recommended): web app, installed from Edge or Chrome

One central copy on Firebase Hosting. Every computer runs the same version, and an update
reaches all of them when you publish it. Nothing needs installing as an administrator, and
Windows security (SmartScreen, Smart App Control) doesn't block it.

**Publish it (once, and again for each update)**, on the setup computer:

```powershell
flutter build web --release --dart-define=USE_FIREBASE=true
firebase deploy --only hosting
```

The address is printed at the end, e.g. `https://naak-hms.web.app`.

> On this PC, `flutter build web` is currently blocked by Smart App Control (it blocks one
> of Flutter's tools). Either build on another computer, or allow Flutter in **Windows
> Security → App & browser control → Smart App Control**, which is your decision.

**On each computer (each PC):**

1. Open the address in **Microsoft Edge** (or Chrome).
2. Edge: **⋯ menu → Apps → Install this site as an app** (Chrome: the install icon at the
   right of the address bar). Name it *NAAK HMS*.
3. Tick **Pin to taskbar** / **Create desktop shortcut**. It now opens in its own window
   with the NAAK icon, like any Windows program.

### Option B: Windows desktop app (installer)

A normal Windows program installed on each PC.

**Get the installer (once per version):**

1. After step 4 is pushed, GitHub builds the app automatically (*Actions → Windows app*,
   about 15 minutes). The run's **Artifacts** section contains
   `NAAK-HMS-Setup-<version>-network.exe` (sign in to GitHub to download).
2. To publish a numbered version instead, create a tag; the installers are then attached
   to a GitHub release:

   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   ```

**On each computer (each PC):**

1. Copy `NAAK-HMS-Setup-<version>-network.exe` to the PC (USB stick, shared folder or
   download) and run it. Choose *Install for all users* when asked, so every Windows user on
   that PC gets it.
2. Windows may warn about an unknown publisher, because the installer isn't digitally
   signed:
   - **SmartScreen** ("Windows protected your PC"): click **More info → Run anyway**.
   - **Smart App Control** blocks unsigned programs completely and has no override. On PCs
     where it is on, use option A, or sign the app (below).
3. Start **NAAK HMS** from the Start menu or desktop.

**Updating:** run the new version's installer on each PC; it replaces the old version and
keeps the data.

**Code signing (recommended for many PCs):** buying a code-signing certificate (from a
certificate authority, or Microsoft's *Trusted Signing* service) and signing the installer
removes these warnings and lets it run with Smart App Control on.

> Firebase's support for Windows desktop programs is newer than its support for browsers.
> If a desktop PC has trouble syncing, run option A on that PC; the data is the same.

## 6. Set up the hospital **(once, on any one computer)**

1. Open NAAK HMS and click **First time? Set up a new hospital**.
2. Enter your name, the administrator's email and a strong password. Untick *Include demo
   patients and staff* for real use (the lab tests and medicine list are added either way).
3. You're signed in as administrator. Open the account menu (top right) → **Hospital
   details**: hospital name, address, phone, tax number, receipt footer, emergency fee and
   reminder settings. These are printed on every receipt and report.
4. Check the lists you'll use: **Inpatients** (wards, beds, daily rates), **Operation
   theatre** (rates), **Laboratory → Test catalogue**, **Radiology → Examinations**,
   **Pharmacy** (medicines and stock), **General store → Items**, **Billing → Insurers**.

Only one person can do this. Once set up, the project refuses a second "set up" attempt.

## 7. Create staff logins **(once per person)**

As administrator, open **Staff → Add staff** for each person:

| Role | For |
|---|---|
| Reception | Front desk: patients, appointments, emergency arrivals, cashier |
| Doctor | Consultations, emergency, orders, admissions, surgery (set the specialisation and fee) |
| Nurse | Triage, wards, nursing charts, theatre |
| Laboratory | Lab work list and the blood bank |
| Radiology | Imaging work list and reports |
| Pharmacy | Dispensing, stock, purchasing, cashier |
| General store | Requisitions and store stock |
| Accounts | Billing, cashier cash-ups, insurance, expenses, payroll, finance |
| Administrator | Everything, including staff and settings |
| Support staff | Payroll only; no login |

The email and password you enter become that person's login. Give each person their own
login (never share one), and ask them to keep the password private.

When someone leaves: **Staff →** the person-off button (**Mark as left**). That blocks their
access at once and keeps their history; to remove the login completely, also delete the user in the Firebase console under
*Authentication → Users*.

## 8. Daily use on each computer **(each PC)**

- Staff sign in with their own email and password. On a shared PC (reception, wards), sign
  out at the end of each shift: account menu → **Sign out**.
- **Printing:** receipts, prescriptions, lab and imaging reports, blood issue forms and
  requisitions open the normal Windows print dialog. Set each PC's default printer to the
  printer next to it; a receipt printer that installs as a Windows printer works too.
- **Patient portal:** patients can book online and see their results and bills. With
  option A, give them the same web address and they choose **Patients** on the sign-in
  screen.

## 9. Network and firewall checklist

Each computer needs outgoing HTTPS (port 443) to:

- `firestore.googleapis.com` (data)
- `identitytoolkit.googleapis.com` and `securetoken.googleapis.com` (sign-in)
- `*.googleapis.com` and `*.gstatic.com`
- `<project>.web.app` and `<project>.firebaseapp.com` (option A)

Nothing needs opening for incoming traffic, and no computer acts as a server. If the
hospital uses a proxy, make sure these addresses are allowed and not intercepted.

Keep each computer's **date, time and time zone correct** (Windows Settings → Time &
language → *Set time automatically*). Appointments, reminders and reports depend on it.

## 10. Backups and safety **(once, then routine)**

- **Automatic backups:** in the Google Cloud console, open **Firestore → Disaster
  recovery** and turn on daily backups (and point-in-time recovery if offered). This needs
  the Blaze plan.
- **Reports as records:** the Excel reports (**Reports**) are a useful monthly archive of
  collections, payroll and stock.
- **Security:** use 2-step verification on the hospital Google account, give the
  administrator role to as few people as possible, and remove leavers promptly (step 7).
  The **Audit log** shows who changed what.

## 11. One computer only (no network)

For a small clinic with a single PC, or while you're evaluating:

- Install `NAAK-HMS-Setup-<version>-single-pc.exe`, which GitHub builds every time
  (option B steps, without Firebase).
- The data is stored only on that computer, in
  `%APPDATA%\NAAK\NAAK HMS\shared_preferences.json`. Back that file up regularly (copy it
  to a USB drive or cloud folder while NAAK HMS is closed).
- It starts with demo data, which administrators can reset under **Staff**. The demo
  passwords are all `1234`: for real use, set up your own staff and mark the demo staff as
  left (**Staff**).
- To move to the networked setup later, start again from step 3; data isn't transferred
  automatically from the single-PC edition.

## 12. Troubleshooting

| Problem | What to check |
|---|---|
| "This account has no access to the hospital" | The login exists but has no staff role. Create the person under **Staff → Add staff** (or *Create login* on an existing staff record), not directly in the Firebase console. |
| "Firebase is not configured" when the app starts | `lib/firebase_options.dart` is still the placeholder: redo step 4, then rebuild. |
| "This Firebase project already has a hospital set up" | Setup was already done. Sign in with the administrator account instead. |
| A change shows "could not be saved to the server and was undone" | That role isn't allowed to make that change (security rules), e.g. a nurse editing a lab result. Ask someone with the right role. |
| Changes don't appear on other PCs | Check that PC's internet and firewall (section 9). Changes are kept and sent when it reconnects. |
| Syncing stopped around the same time each day | The free Spark plan's daily limit was reached: upgrade to Blaze (step 3). |
| Windows won't run the installer | SmartScreen: *More info → Run anyway*. Smart App Control: use option A or a signed installer (step 5). |
| Wrong times on appointments or reports | Fix the PC's clock and time zone (section 9). |
