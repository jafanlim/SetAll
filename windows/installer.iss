[Setup]
AppName=SetAll
AppVersion=1.0.4
DefaultDirName={autopf}\SetAll
OutputDir=..\build\windows\installer
OutputBaseFilename=SetAll-Windows
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
SetupIconFile=..\windows\runner\resources\app_icon.ico

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
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"
