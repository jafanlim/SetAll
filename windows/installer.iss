[Setup]
AppName=SetAll
AppVersion=1.2.8
; Stable GUID — must never change between versions so Inno detects upgrades.
AppId={{A7F3C2E1-9D4B-4F8A-B6E0-12345678ABCD}
AppPublisher=SetAll
DefaultDirName={autopf}\SetAll
DefaultGroupName=SetAll
OutputDir=..\build\windows\installer
OutputBaseFilename=SetAll-Windows
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Automatically uninstall the previous version before installing the new one.
UninstallDisplayName=SetAll
UninstallDisplayIcon={app}\setall.exe
; Kill the running app gracefully before upgrading.
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
; Allow fully silent install via /SILENT or /VERYSILENT flags.
PrivilegesRequired=admin

[Registry]
Root: HKCR; Subkey: "setall"; ValueType: string; ValueName: ""; ValueData: "URL:SetAll Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "setall"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCR; Subkey: "setall\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\setall.exe,0"
Root: HKCR; Subkey: "setall\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\setall.exe"" ""%1"""

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SetAll"; Filename: "{app}\setall.exe"
Name: "{commondesktop}\SetAll"; Filename: "{app}\setall.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:";

[Run]
Filename: "{app}\setall.exe"; Description: "Launch SetAll"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/C taskkill /F /IM setall.exe"; Flags: runhidden