#define AppName      "RF4 Backup Tool - Full Package"
#define AppVersion   "1.2.0"
#define AppPublisher "Natural (Bjoern)"
#define AppURL       "https://codeberg.org/Natural78/rf4-backup-tool"

[Setup]
AppId={{1C2D3E4F-5A6B-7C8D-9E0F-A1B2C3D4E5F6}
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
OutputBaseFilename=rf4sa-backup-full-setup-v1.2.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german";  MessagesFile: "compiler:Languages\German.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Types]
Name: "full";   Description: "Full installation / Vollstaendige Installation"
Name: "gui";    Description: "GUI only / Nur GUI"
Name: "cli";    Description: "Terminal only / Nur Terminal"
Name: "custom"; Description: "Custom / Benutzerdefiniert"; Flags: iscustom

[Components]
Name: "gui";  Description: "GUI Version (rf4sa-backup-gui.ps1)";  Types: full gui
Name: "cli";  Description: "Terminal Version (rf4sa-backup.ps1)"; Types: full cli
Name: "bash"; Description: "Linux/Mac Shell (rf4sa-backup.sh)";   Types: full

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "../rf4sa-backup-gui.ps1"; DestDir: "{app}"; Flags: ignoreversion; Components: gui
Source: "../rf4sa-backup.ps1";     DestDir: "{app}"; Flags: ignoreversion; Components: cli
Source: "../rf4sa-backup.sh";      DestDir: "{app}"; Flags: ignoreversion; Components: bash
Source: "../LICENSE";               DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";            DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\RF4 Backup Tool (GUI)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; WorkingDir: "{app}"; Components: gui
Name: "{group}\RF4 Backup Tool (Terminal)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup.ps1'"""; WorkingDir: "{app}"; Components: cli
Name: "{commondesktop}\RF4 Backup Tool (GUI)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; WorkingDir: "{app}"; Tasks: desktopicon; Components: gui

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; Description: "{cm:LaunchProgram,RF4 Backup Tool GUI}"; Flags: nowait postinstall skipifsilent; Components: gui
