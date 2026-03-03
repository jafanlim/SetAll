[Setup]
AppName=SetAll
AppVersion=1.0.1
DefaultDirName={autopf}\SetAll
OutputDir=..\build\windows\installer
OutputBaseFilename=SetAll-Windows
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SetAll"; Filename: "{app}\setall.exe"
Name: "{commondesktop}\SetAll"; Filename: "{app}\setall.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"