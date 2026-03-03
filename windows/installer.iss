[Setup]
AppName=SetAll
AppVersion=1.0.3
DefaultDirName={autopf}\SetAll
OutputDir=..\build\windows\installer
OutputBaseFilename=SetAll-Windows
# ... other settings ...

[Registry]
Root: HKCR; Subkey: "setall"; ValueType: string; ValueName: ""; ValueData: "URL:SetAll Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "setall"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCR; Subkey: "setall\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\setall.exe,0"
Root: HKCR; Subkey: "setall\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\setall.exe"" ""%1"""

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
# ... rest of file ...
