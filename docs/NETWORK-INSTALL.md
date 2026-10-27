# Installing NAAK HMS on the hospital network

This guide sets NAAK HMS up so that every computer in the hospital (reception, doctors'
rooms, emergency, laboratory, radiology, pharmacy, wards, store, accounts) works on **the
same live data, held in the hospital's own database on its own computer**. No internet or
cloud service is needed.

It is written for whoever installs NAAK HMS (the "administrator"). Steps marked **(once)**
are done one time; steps marked **(each PC)** are repeated on every computer.

---

## 1. Choose how to run NAAK HMS

| Setup | Where the data is | Use it when |
|---|---|---|
| **Hospital server (this guide)** | On one hospital computer, the *server PC*. Every other computer connects to it over the local network. | Several computers; you want to keep the data in the hospital, without depending on the internet. |
| One computer only | On that computer | A single-PC clinic, or to try NAAK HMS (section 12). |
| Google cloud (Firebase) | In your own Firebase project on the internet | Branches in different places, or patients booking online from home (appendix A). |

## 2. How the hospital server works

```
                         Hospital network (LAN: cables / Wi-Fi)
 Reception PC ─┐
 Doctor PC ────┤        ┌────────────────────────────────────────┐
 Lab PC ───────┼──────▶ │ Server PC: NAAK HMS Server             │
 Pharmacy PC ──┤        │  • the hospital database (on its disk) │
 Ward laptop ──┤        │  • logins and role permissions         │
 Any browser ──┘        │  • daily backups                       │
                        └────────────────────────────────────────┘
```

- **NAAK HMS Server** runs on one computer. It holds the database, checks each person's
  permissions (only the lab can enter results; only accounts and administrators see
  salaries…), and passes every change to the other computers within a second.
- **Every other computer** runs the NAAK HMS app, or simply a web browser, connected to the
  server's address.
- **Not fully dependent on the server:** each computer also keeps its own copy of the data.
  If the network or the server PC goes down, staff **keep working**. A small orange
  **Offline** badge appears at the top of the screen, changes are saved on that computer,
  and they are sent automatically when the connection returns. (Signing in for the first
  time, and creating staff logins, do need the server.)
- **Nothing leaves the hospital.** The server needs no internet connection.
- **Backups:** the server saves a dated copy of the database every day and keeps the last
  30 (section 9).

## 3. What you need

| Item | Notes |
|---|---|
| **Server PC** | Any reliable Windows 10/11 64-bit PC (4 GB RAM or more). It must stay **switched on** during working hours, ideally all the time. A wired network connection and a UPS (battery backup) are strongly recommended. It can also be used as an ordinary workstation. |
| **Network** | All computers on the same local network: a router or switch, cables or Wi-Fi. Internet is not required. |
| **Other computers** | Windows 10/11 64-bit for the app, or any computer, tablet or phone with a modern browser (Edge, Chrome). |
| **Installers** | From the [latest release](https://github.com/sanucee/hospital/releases/latest): `NAAK-HMS-Server-Setup-<version>.exe` (server PC) and `NAAK-HMS-Setup-<version>.exe` (other computers). Use the same version everywhere. |

## 4. Prepare the server PC **(once)**

1. **Give it a fixed address.** The other computers find the server by its IP address, so
   that address must not change. Either:
   - in the **router's settings**, reserve an address for the server PC (often called
     *DHCP reservation* or *static lease*), e.g. `192.168.1.10`; or
   - in Windows: *Settings → Network & internet → Ethernet (or Wi-Fi) → IP assignment →
     Edit → Manual*, and enter an address outside the router's automatic range, plus the
     subnet mask, gateway and DNS your network uses.

   Note the address: in this guide, `192.168.1.10`.
2. **Mark the network as private:** *Settings → Network & internet → Ethernet (or Wi-Fi) →
   Network profile type → **Private network***. Windows only lets other computers connect
   on private networks.
3. **Stop it sleeping:** *Settings → System → Power → Screen and sleep → "When plugged in,
   put my device to sleep after" → **Never***. (The screen may still turn off.)
4. Set the PC's **date, time and time zone** correctly, with *Set time automatically* on.
   Do the same on every computer: appointments and reports depend on it.

## 5. Install NAAK HMS Server **(once, on the server PC)**

1. Run `NAAK-HMS-Server-Setup-<version>.exe` and accept the administrator prompt.
   - Windows may warn about an unknown publisher, because the installer isn't digitally
     signed. **SmartScreen** ("Windows protected your PC"): click **More info → Run
     anyway**. **Smart App Control**, if it's on, blocks unsigned programs completely; on
     the server PC it has to be off (*Windows Security → App & browser control → Smart App
     Control*), or the programs signed (section 11).
   - Leave *"Also allow connections when Windows calls this network Public"* unticked
     unless step 4.2 isn't possible.
2. The installer:
   - installs the server in `C:\Program Files\NAAK HMS Server`;
   - sets it to **start automatically with Windows**, in the background, even when nobody
     is signed in (a scheduled task called *NAAK HMS Server*);
   - opens port **8787** in Windows Firewall for private networks;
   - keeps the database in `C:\ProgramData\NAAK HMS\data` and a log in
     `C:\ProgramData\NAAK HMS\server.log`;
   - starts the server and opens NAAK HMS in the browser.
3. **Check it works:** Start menu → *NAAK HMS Server → Server status* should show
   `"name":"NAAK HMS Server"`. From another computer, open `http://192.168.1.10:8787` in a
   browser: the NAAK HMS sign-in screen should appear. If it doesn't, see section 13.

## 6. Set up the hospital **(once)**

On the server PC, or any computer connected as in step 7:

1. Open NAAK HMS (Start menu → *NAAK HMS Server → Open NAAK HMS in the browser*, or the app).
2. Click **First time? Set up a new hospital**.
3. Enter your name, an **administrator user name** (e.g. `admin`) and a strong password
   (6+ characters; longer is better). Untick *Include demo patients and staff* for real
   use. The lab tests, imaging examinations, medicines and store items are added either
   way.
4. You're signed in as administrator. Open the account menu (top right) → **Hospital
   details**: hospital name, address, phone, receipt footer, emergency fee. These are
   printed on receipts and reports.
5. Review the lists you'll use: **Inpatients** (wards, beds, daily rates), **Operation
   theatre**, **Laboratory → Test catalogue**, **Radiology → Examinations**, **Pharmacy**,
   **General store → Items**, **Billing → Insurers**.

Only one administrator can be created this way: once a hospital exists on the server,
"set up" is refused.

## 7. Connect the other computers **(each PC)**

Each computer can use the **Windows app** or a **browser**. Both work the same way, but the
app is better for computers used all day: it starts and works even if the server PC is off
at that moment, whereas a browser needs the server to load the page.

### Option A: Windows app (recommended)

1. Run `NAAK-HMS-Setup-<version>.exe` (same warnings as in step 5.1). Choose *Install for
   all users*.
2. Open **NAAK HMS**. At the bottom of the sign-in screen, next to *Data on this computer
   only*, click **Change**.
3. Choose **Hospital server on the network**, enter the server's address (`192.168.1.10`),
   click **Test connection** (it should say *Connected to NAAK HMS Server*), then **Save**.
4. The sign-in screen now shows *Hospital server: 192.168.1.10*. Staff sign in with their
   own user name and password (step 8).

### Option B: browser

1. Open `http://192.168.1.10:8787` in **Microsoft Edge** or Chrome.
2. Optional, so it behaves like a program: Edge **⋯ → Apps → Install this site as an app**
   (Chrome: the install icon in the address bar), and pin it to the taskbar.
3. Sign in.

Tablets and phones on the hospital Wi-Fi can use option B too.

## 8. Create staff logins **(once per person)**

As administrator, **Staff → Add staff** for each person, choosing their role and giving them
a **user name** (e.g. `amaka.obi`) and a password, which they can use on any computer.

| Role | For |
|---|---|
| Reception | Patients, appointments, emergency arrivals, cashier |
| Doctor | Consultations, emergency, lab/imaging/blood orders, admissions, surgery |
| Nurse | Emergency triage, wards, nursing charts, theatre |
| Laboratory | Lab work list and the blood bank |
| Radiology | Imaging work list and reports |
| Pharmacy | Dispensing, stock, purchasing, cashier |
| General store | Requisitions and store stock |
| Accounts | Billing, cash-ups, insurance, expenses, payroll, finance |
| Administrator | Everything, including staff and settings |
| Support staff | Payroll only; no login |

If you included the demo staff, give the ones you keep a login with **Create login** and
mark the others as left.

- Give everyone their **own** login; never share one. The audit log records who did what.
- On shared computers (reception, wards), sign out at the end of each shift (account menu
  → **Sign out**). Signing out also removes that person's copy of the data from the
  computer.
- When someone leaves: **Staff →** the person-off button (**Mark as left**). Their login
  stops working everywhere at once; their history is kept.

## 9. Backups and restoring **(routine)**

**Automatic:** the server saves a copy of the database when it starts and every 24 hours, in
`C:\ProgramData\NAAK HMS\data\backups` (files named like `naak-hms-20261027-090000.json`).
The newest 30 are kept. (Start menu → *NAAK HMS Server → Database and backups folder*.)

**Off the PC (do this weekly):** copy the newest backup file to a USB drive or another
computer and keep it somewhere safe. A fire, theft or failed disk would otherwise take the
backups with the server PC.

**Restoring a backup** (or moving the database to a new server PC):

1. Open **Command Prompt as administrator** on the server PC and stop the server:
   ```bat
   schtasks /End /TN "NAAK HMS Server"
   ```
2. In `C:\ProgramData\NAAK HMS\data`, move `snapshot.json` and `journal.jsonl` somewhere
   safe (in case you need them), then copy the backup file in and rename it to
   `snapshot.json`.
3. Start the server again:
   ```bat
   schtasks /Run /TN "NAAK HMS Server"
   ```

To **move to a new server PC**: install NAAK HMS Server on it, then copy the whole
`C:\ProgramData\NAAK HMS\data` folder from the old PC (with both servers stopped, as in
step 1). Give the new PC the old one's IP address (step 4.1), and the other computers need
no change.

Staff logins are part of the database, so a restored backup includes them.

## 10. Updating to a new version

1. On the server PC, run the new `NAAK-HMS-Server-Setup-<version>.exe`. It stops the old
   server, upgrades it and starts it again; the database is kept.
2. On each computer, run the new `NAAK-HMS-Setup-<version>.exe`. Browsers pick up the new
   version on their next reload.

Keep the server and the apps on the **same version**. *Test connection* warns when a server
and an app can't work together.

## 11. Security checklist

- Lock down the **server PC**: a Windows password, only trusted people as Windows
  administrators, and no everyday web browsing on it. The database files are in
  `C:\ProgramData\NAAK HMS\data`.
- **Secure the Wi-Fi** with WPA2/WPA3 and a strong password, and put patients' and visitors'
  devices on a separate **guest network**. Traffic between the computers and the server
  isn't encrypted, so the network itself must be trusted.
- Use strong passwords for staff, especially administrators, and remove leavers promptly
  (section 8).
- Keep backups off the server PC (section 9).
- **Code signing:** for many PCs, sign the installers with a code-signing certificate (from
  a certificate authority, or Microsoft's *Trusted Signing* service). That removes the
  SmartScreen warning and lets them run with Smart App Control on.

## 12. One computer only

Install `NAAK-HMS-Setup-<version>.exe` and leave the sign-in screen on *Data on this
computer only*. The data stays on that PC, in
`%APPDATA%\NAAK\NAAK HMS\shared_preferences.json`; back that file up while NAAK HMS is
closed. It starts with demo data, and the demo passwords are `1234`, so set up your own staff
before real use.

To move to a hospital server later, set up the server (sections 4–6) and connect this
computer (section 7). The single-PC data isn't copied across automatically.

## 13. Troubleshooting

| Problem | What to check |
|---|---|
| *Test connection* says "No answer" | Is the server PC on and awake? On it, does *Server status* open? Is the address right (`ipconfig` on the server PC shows it)? Is the server PC's network **Private** (step 4.2)? Try from the other computer: `http://192.168.1.10:8787/health` in a browser. |
| Works on the server PC but not from others | Windows Firewall: rerun the server installer, or tick the *Public* option in it. Another firewall or antivirus may need port 8787 allowed. Make sure both computers are on the same network (not one on guest Wi-Fi). |
| "Cannot reach the hospital server" when signing in | As above. Computers that were already signed in keep working offline; only new sign-ins need the server. |
| Orange **Offline** badge at the top | That computer has lost the server. Keep working; changes are sent when it reconnects. If it stays offline, check the network cable/Wi-Fi and the server PC. |
| "A change could not be saved to the server and was undone" | That person's role isn't allowed to make that change (e.g. a nurse editing stock). Ask someone with the right role. |
| "Invalid user name or password" | Check the user name (not case-sensitive) and password. An administrator can create a new login for the person under **Staff**. |
| "This server already has a hospital set up" | Setup was already done. Sign in with the administrator account. |
| "That server runs a different version" | Install the same version on the server and the computers (section 10). |
| The server doesn't start after a restart | Check `C:\ProgramData\NAAK HMS\server.log`. "Could not listen on port 8787" means something else is using the port (perhaps a second copy). Restart the PC, or run `schtasks /Run /TN "NAAK HMS Server"` as administrator. |
| Wrong times on appointments or reports | Fix that computer's clock and time zone (step 4.4). |
| The patient portal isn't on the sign-in screen | Online patient accounts need the Google cloud setup (appendix A). With a hospital server, reception handles bookings. |

---

## Appendix A: Google cloud (Firebase) instead of a hospital server

Use this when computers are in different places connected only by the internet, or when
patients should book online from home. Every computer then needs internet.

1. **Firebase project:** at <https://console.firebase.google.com>, with the hospital's
   Google account (2-step verification on): create a project; *Authentication → Sign-in
   method*: enable **Email/Password**; *Firestore Database → Create database* in
   **production mode**, in the location nearest the hospital (e.g. `asia-south1`). Choose
   the **Blaze** plan and set a budget alert: the free plan's daily limits (50,000 reads,
   20,000 writes) are soon exceeded by a busy hospital.
2. **Connect the app** (on a computer with Flutter and Node.js, in the project folder):
   ```powershell
   npm install -g firebase-tools
   dart pub global activate flutterfire_cli
   firebase login
   flutterfire configure --project=<project-id> --platforms=web,windows,android
   firebase use <project-id>
   firebase deploy --only firestore
   git add lib/firebase_options.dart
   git commit -m "Connect NAAK HMS to the hospital's Firebase project"
   git push
   ```
   GitHub then also builds `NAAK-HMS-Setup-<version>-cloud.exe`.
3. **Web app** (recommended for the cloud setup; updates reach every computer at once):
   ```powershell
   flutter build web --release --dart-define=USE_FIREBASE=true
   firebase deploy --only hosting
   ```
   Open the printed address (e.g. `https://<project-id>.web.app`) in Edge on each computer
   and install it as an app.
4. **First run:** *First time? Set up a new hospital* (administrator email and password),
   then **Staff → Add staff** with each person's **email** and password.
5. **Firewall:** allow outgoing HTTPS to `firestore.googleapis.com`,
   `identitytoolkit.googleapis.com`, `securetoken.googleapis.com`, `*.googleapis.com`,
   `*.gstatic.com` and your `web.app` address.
6. **Backups:** Google Cloud console → *Firestore → Disaster recovery* → daily backups.

Firebase's support for Windows desktop programs is newer than its support for browsers; if a
desktop PC has trouble syncing, use the web app on it.
