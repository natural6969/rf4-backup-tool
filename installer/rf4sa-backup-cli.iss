#define AppName      "RF4 Backup Tool - Terminal"
#define AppVersion   "1.5.0"
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
OutputDir=output
OutputBaseFilename=rf4sa-backup-cli-setup-v1.5.0
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
DisableWelcomePage=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german";  MessagesFile: "compiler:Languages\German.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; ältere Programmdateien (ohne Version / frühere Versionen) beim Update entfernen
Type: files; Name: "{app}\rf4sa-backup-gui.ps1"
Type: files; Name: "{app}\rf4sa-backup-gui-v*.ps1"
Type: files; Name: "{app}\rf4sa-backup.ps1"
Type: files; Name: "{app}\rf4sa-backup-v*.ps1"
Type: files; Name: "{app}\rf4sa-backup.sh"
Type: files; Name: "{app}\rf4sa-backup-v*.sh"

[Files]
Source: "../examples/*"; DestDir: "{app}\examples"; Flags: ignoreversion
Source: "../rf4sa-backup-v{#AppVersion}.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "../LICENSE";           DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";        DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\RF4 Backup Tool (Terminal)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-v{#AppVersion}.ps1'"""; WorkingDir: "{app}"; Comment: "RF4 Savegame Backup - Terminal"
Name: "{autodesktop}\RF4 Backup Tool (Terminal)"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-v{#AppVersion}.ps1'"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command ""& '{app}\rf4sa-backup-v{#AppVersion}.ps1'"""; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#include "common.iss"
