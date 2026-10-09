#define AppName      "RF4 Backup Tool - GUI"
#define AppVersion   "1.5.0"
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
OutputDir=output
OutputBaseFilename=rf4sa-backup-gui-setup-v1.5.0
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
Type: files; Name: "{app}\docs\img\*.png"
; ältere Programmdateien (ohne Version / frühere Versionen) beim Update entfernen
Type: files; Name: "{app}\rf4sa-backup-gui.ps1"
Type: files; Name: "{app}\rf4sa-backup-gui-v*.ps1"
Type: files; Name: "{app}\rf4sa-backup.ps1"
Type: files; Name: "{app}\rf4sa-backup-v*.ps1"
Type: files; Name: "{app}\rf4sa-backup.sh"
Type: files; Name: "{app}\rf4sa-backup-v*.sh"

[Files]
Source: "../examples/*"; DestDir: "{app}\examples"; Flags: ignoreversion
Source: "../rf4sa-backup-gui-v{#AppVersion}.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "rf4sa-backup-gui-start.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "../LICENSE";               DestDir: "{app}"; Flags: ignoreversion
Source: "README.txt";            DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\RF4 Backup Tool (GUI)"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\rf4sa-backup-gui-start.vbs"""; WorkingDir: "{app}"; Comment: "RF4 Savegame Backup - GUI"
Name: "{autodesktop}\RF4 Backup Tool (GUI)"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\rf4sa-backup-gui-start.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\rf4sa-backup-gui-start.vbs"""; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

#include "common.iss"
