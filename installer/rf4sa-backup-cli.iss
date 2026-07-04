#define AppName      "RF4 Backup Tool - Terminal"
#define AppVersion   "1.2.0"
#define AppPublisher "Natural (Bjoern)"
#define AppURL       "https://codeberg.org/Natural78/rf4-backup-tool"

[Setup]
AppId={{9A3B4C2D-5E8F-4A7B-B3C2-D4E5F6A7B8C9}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\RF4BackupTool
DefaultGroupName=RF4 Backup Tool
AllowNoIcons=yes
LicenseFile=../LICENSE
InfoAfterFile=README.txt
OutputDir=output
OutputBaseFilename=rf4sa-backup-cli-setup-v1.2.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german";  MessagesFile: "compiler:Languages\German.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "../rf4sa-backup.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "../LICENSE";           DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";        DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\RF4 Backup Tool (Terminal)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup.ps1'"""; WorkingDir: "{app}"; Comment: "RF4 Savegame Backup - Terminal"
Name: "{commondesktop}\RF4 Backup Tool (Terminal)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup.ps1'"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup.ps1'"""; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
