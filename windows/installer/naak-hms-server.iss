; Inno Setup script for NAAK HMS Server (the hospital's database on the
; local network). Built by .github/workflows/windows-app.yml:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<folder with naak_server.exe and web\> naak-hms-server.iss
;
; The server runs in the background from Windows start-up (a scheduled task
; under the SYSTEM account), so it works without anyone signing in.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\server"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif
#define Port "8787"
#define TaskName "NAAK HMS Server"
#define DataDir "{commonappdata}\NAAK HMS"

[Setup]
; Never change AppId: it lets new versions upgrade the installed one.
AppId={{5D3C8A1E-7B42-4F0D-9C61-2E8B7A4F1D93}
AppName=NAAK HMS Server
AppVersion={#AppVersion}
AppVerName=NAAK HMS Server {#AppVersion}
AppPublisher=NAAK
DefaultDirName={autopf}\NAAK HMS Server
DefaultGroupName=NAAK HMS Server
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=NAAK-HMS-Server-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\naak_server.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installing a start-up task and a firewall rule needs administrator rights.
PrivilegesRequired=admin
CloseApplications=yes

[Tasks]
Name: "publicfw"; Description: "Also allow connections when Windows calls this network ""Public"" (only if other computers can't connect)"; GroupDescription: "Firewall:"; Flags: unchecked

[Dirs]
; The database lives outside Program Files so upgrades never touch it.
Name: "{#DataDir}\data"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NAAK HMS Server\Open NAAK HMS in the browser"; Filename: "http://localhost:{#Port}/"
Name: "{autoprograms}\NAAK HMS Server\Server status"; Filename: "http://localhost:{#Port}/health"
Name: "{autoprograms}\NAAK HMS Server\Database and backups folder"; Filename: "{#DataDir}"
Name: "{autoprograms}\NAAK HMS Server\Server log"; Filename: "{#DataDir}\server.log"

[Run]
; Stop an older version that may still be running.
Filename: "{sys}\schtasks.exe"; Parameters: "/End /TN ""{#TaskName}"""; Flags: runhidden; StatusMsg: "Stopping the previous server..."
Filename: "{sys}\schtasks.exe"; Parameters: "/Create /F /TN ""{#TaskName}"" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR ""\""{app}\naak_server.exe\"" --port {#Port} --data \""{#DataDir}\data\"" --log \""{#DataDir}\server.log\"""""; Flags: runhidden; StatusMsg: "Setting the server to start with Windows..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#TaskName}"""; Flags: runhidden
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#TaskName}"" dir=in action=allow protocol=TCP localport={#Port} profile=private,domain"; Flags: runhidden; Tasks: not publicfw; StatusMsg: "Opening port {#Port} in the firewall..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#TaskName}"" dir=in action=allow protocol=TCP localport={#Port} profile=any"; Flags: runhidden; Tasks: publicfw; StatusMsg: "Opening port {#Port} in the firewall..."
Filename: "{sys}\schtasks.exe"; Parameters: "/Run /TN ""{#TaskName}"""; Flags: runhidden; StatusMsg: "Starting the server..."
Filename: "http://localhost:{#Port}/"; Description: "Open NAAK HMS in the browser"; Flags: postinstall shellexec nowait skipifsilent

[UninstallRun]
Filename: "{sys}\schtasks.exe"; Parameters: "/End /TN ""{#TaskName}"""; Flags: runhidden; RunOnceId: "StopServer"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /F /TN ""{#TaskName}"""; Flags: runhidden; RunOnceId: "DeleteTask"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#TaskName}"""; Flags: runhidden; RunOnceId: "DeleteFirewallRule"

[Messages]
FinishedLabel=NAAK HMS Server is installed and running. It starts automatically with Windows.%n%nThe database and daily backups are kept in %n{#DataDir}%n%nOn the other computers, install NAAK HMS and choose "Change" under "Hospital server" on the sign-in screen, then enter this computer's address.
