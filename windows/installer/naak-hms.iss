; Inno Setup script for the NAAK HMS Windows installer.
; Built by .github/workflows/windows-app.yml:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=<dir> naak-hms.iss
; /DEdition=-cloud names the Firebase edition's installer.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif
#ifndef Edition
  #define Edition ""
#endif

[Setup]
; Never change AppId: it lets new versions upgrade the installed one.
AppId={{086FD981-E966-4CC4-9484-B003B4F837EF}
AppName=NAAK HMS
AppVersion={#AppVersion}
AppVerName=NAAK HMS {#AppVersion}
AppPublisher=NAAK
DefaultDirName={autopf}\NAAK HMS
DefaultGroupName=NAAK HMS
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=NAAK-HMS-Setup-{#AppVersion}{#Edition}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\naak_hms.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Installs for all users of the PC by default; can also install just for one.
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NAAK HMS"; Filename: "{app}\naak_hms.exe"
Name: "{autodesktop}\NAAK HMS"; Filename: "{app}\naak_hms.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\naak_hms.exe"; Description: "{cm:LaunchProgram,NAAK HMS}"; Flags: nowait postinstall skipifsilent
