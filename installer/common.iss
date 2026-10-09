; Gemeinsame Teile der drei Installer (per #include eingebunden)
[CustomMessages]
english.RemoveSettings=Also delete your saved settings (language, theme, sync folder, backup list and your own language/theme files)?%n%nYour RF4 game data and your backups are NEVER deleted.
german.RemoveSettings=Sollen auch die gespeicherten Einstellungen gelöscht werden (Sprache, Design, Sync-Ordner, Backup-Liste und eigene Sprach-/Design-Dateien)?%n%nDeine RF4-Spieldaten und deine Backups werden NIE gelöscht.
russian.RemoveSettings=Удалить также сохранённые настройки (язык, тема, папка синхронизации, список копий и ваши файлы языков/тем)?%n%nИгровые данные RF4 и ваши резервные копии НИКОГДА не удаляются.
english.UninstallLink=Uninstall RF4 Backup Tool
german.UninstallLink=RF4 Backup Tool deinstallieren
russian.UninstallLink=Удалить RF4 Backup Tool

[UninstallDelete]
Type: dirifempty; Name: "{app}\examples"
Type: dirifempty; Name: "{app}\lang"
Type: dirifempty; Name: "{app}\themes"
Type: dirifempty; Name: "{app}"

[Code]
// Deinstallation: nur Programmdateien entfernen. Konfiguration auf Nachfrage – Spieldaten und Backups bleiben immer.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  CfgDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    CfgDir := ExpandConstant('{userappdata}\rf4-backup');
    if DirExists(CfgDir) and (not UninstallSilent) then
      if MsgBox(CustomMessage('RemoveSettings'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(CfgDir, True, True, True);
  end;
end;
