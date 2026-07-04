#define AppName      "RF4 Backup Tool - GUI"
#define AppVersion   "1.2.0"
#define AppPublisher "Natural (Bjoern)"
#define AppURL       "https://codeberg.org/Natural78/rf4-backup-tool"

[Setup]
AppId={{8F2A3C1E-4B7D-4E9F-A2B1-C3D5E6F7A8B9}
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
OutputBaseFilename=rf4sa-backup-gui-setup-v1.2.0
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
Source: "../rf4sa-backup-gui.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "../LICENSE";               DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";            DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\RF4 Backup Tool (GUI)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; WorkingDir: "{app}"; Comment: "RF4 Savegame Backup - GUI"
Name: "{commondesktop}\RF4 Backup Tool (GUI)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-gui.ps1'"""; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
