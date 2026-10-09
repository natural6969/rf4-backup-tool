; Gemeinsame Teile der drei Installer (per include eingebunden)
[CustomMessages]
english.RemoveSettings=Also delete your saved settings (language, theme, sync folder, backup list and your own language/theme files)?%n%nYour RF4 game data and your backups are NEVER deleted.
german.RemoveSettings=Sollen auch die gespeicherten Einstellungen gelöscht werden (Sprache, Design, Sync-Ordner, Backup-Liste und eigene Sprach-/Design-Dateien)?%n%nDeine RF4-Spieldaten und deine Backups werden NIE gelöscht.
russian.RemoveSettings=Удалить также сохранённые настройки (язык, тема, папка синхронизации, список копий и ваши файлы языков/тем)?%n%nИгровые данные RF4 и ваши резервные копии НИКОГДА не удаляются.
english.UninstallLink=Uninstall RF4 Backup Tool
german.UninstallLink=RF4 Backup Tool deinstallieren
russian.UninstallLink=Удалить RF4 Backup Tool
english.GuideLink=Guide (with screenshots)
german.GuideLink=Anleitung (mit Screenshots)
russian.GuideLink=Руководство (со скриншотами)
english.OpenGuide=Open the guide (with screenshots)
german.OpenGuide=Anleitung mit Screenshots öffnen
russian.OpenGuide=Открыть руководство (со скриншотами)
english.InfoTitle=Links and help
german.InfoTitle=Links und Hilfe
russian.InfoTitle=Ссылки и справка
english.InfoDesc=Click a link to open it in your browser.
german.InfoDesc=Ein Klick auf einen Link öffnet ihn im Browser.
russian.InfoDesc=Щёлкните ссылку, чтобы открыть её в браузере.
english.InfoDonate=Thank you for using RF4 Backup Tool! If you like it, a small donation is very welcome:
german.InfoDonate=Danke, dass du das RF4 Backup Tool benutzt! Wenn es dir gefällt, freue ich mich über eine kleine Spende:
russian.InfoDonate=Спасибо, что пользуетесь RF4 Backup Tool! Если он вам нравится, буду рад небольшому пожертвованию:
english.InfoBlog=Guide and blog:
german.InfoBlog=Anleitung und Blog:
russian.InfoBlog=Руководство и блог:
english.InfoDownload=Latest version / download:
german.InfoDownload=Neueste Version / Download:
russian.InfoDownload=Последняя версия / загрузка:
english.InfoSource=Source code (Codeberg):
german.InfoSource=Quellcode (Codeberg):
russian.InfoSource=Исходный код (Codeberg):
english.InfoGuide=Local guide with screenshots (opens in your browser):
german.InfoGuide=Lokale Anleitung mit Screenshots (öffnet im Browser):
russian.InfoGuide=Локальное руководство со скриншотами (откроется в браузере):
english.InfoGuideLink=Open the guide
german.InfoGuideLink=Anleitung öffnen
russian.InfoGuideLink=Открыть руководство

[Files]
Source: "../docs/guide.*.html"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "../docs/img/*"; DestDir: "{app}\docs\img"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{cm:UninstallLink}"; Filename: "{uninstallexe}"
Name: "{group}\{cm:GuideLink}"; Filename: "{app}\docs\guide.de.html"; Languages: german
Name: "{group}\{cm:GuideLink}"; Filename: "{app}\docs\guide.en.html"; Languages: english
Name: "{group}\{cm:GuideLink}"; Filename: "{app}\docs\guide.ru.html"; Languages: russian
Name: "{group}\指南 (中文)"; Filename: "{app}\docs\guide.zh.html"

[Run]
Filename: "{app}\docs\guide.de.html"; Description: "{cm:OpenGuide}"; Flags: postinstall shellexec skipifsilent; Languages: german
Filename: "{app}\docs\guide.en.html"; Description: "{cm:OpenGuide}"; Flags: postinstall shellexec skipifsilent; Languages: english
Filename: "{app}\docs\guide.ru.html"; Description: "{cm:OpenGuide}"; Flags: postinstall shellexec skipifsilent; Languages: russian

[UninstallDelete]
Type: dirifempty; Name: "{app}\docs\img\de"
Type: dirifempty; Name: "{app}\docs\img\en"
Type: dirifempty; Name: "{app}\docs\img\zh"
Type: dirifempty; Name: "{app}\docs\img\ru"
Type: dirifempty; Name: "{app}\docs\img"
Type: dirifempty; Name: "{app}\docs"
Type: dirifempty; Name: "{app}\examples"
Type: dirifempty; Name: "{app}\lang"
Type: dirifempty; Name: "{app}\themes"
Type: dirifempty; Name: "{app}"

[Code]
var
  LinksPage: TWizardPage;
  GuideLinkLabel: TNewStaticText;

// Klickbarer Link: sichtbar als unterstrichener, blauer Text mit Hand-Cursor; die Adresse steht im Hint
procedure LinkClick(Sender: TObject);
var
  ErrorCode: Integer;
begin
  ShellExec('open', TNewStaticText(Sender).Hint, '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
end;

function AddText(Parent: TWinControl; const Text: String; Left, Top, Width: Integer): Integer;
var
  L: TNewStaticText;
begin
  L := TNewStaticText.Create(Parent);
  L.Parent := Parent;
  L.AutoSize := True;
  L.WordWrap := True;
  L.Width := Width;
  L.Left := Left;
  L.Top := Top;
  L.Caption := Text;
  Result := Top + L.Height + ScaleY(2);
end;

function AddLink(Parent: TWinControl; const Caption, Url: String; Top: Integer; out Lbl: TNewStaticText): Integer;
begin
  Lbl := TNewStaticText.Create(Parent);
  Lbl.Parent := Parent;
  Lbl.AutoSize := True;
  Lbl.Caption := Caption;
  Lbl.Hint := Url;
  Lbl.ShowHint := True;
  Lbl.Cursor := crHand;
  Lbl.Font.Style := [fsUnderline];
  Lbl.Font.Color := $00CC6600;
  Lbl.Left := ScaleX(12);
  Lbl.Top := Top;
  Lbl.OnClick := @LinkClick;
  Result := Top + Lbl.Height + ScaleY(10);
end;

function GuideFile: String;
var
  Code: String;
begin
  if ActiveLanguage = 'german' then Code := 'de'
  else if ActiveLanguage = 'russian' then Code := 'ru'
  else Code := 'en';
  Result := ExpandConstant('{app}\docs\guide.' + Code + '.html');
end;

procedure InitializeWizard;
var
  Y, W: Integer;
  Dummy: TNewStaticText;
begin
  // Willkommensseite: Spenden-Link gut sichtbar
  Y := WizardForm.WelcomeLabel2.Top + WizardForm.WelcomeLabel2.Height + ScaleY(18);
  W := WizardForm.WelcomeLabel2.Width;
  Y := AddText(WizardForm.WelcomePage, CustomMessage('InfoDonate'), WizardForm.WelcomeLabel2.Left, Y, W);
  Y := Y + ScaleY(4);
  Y := AddLink(WizardForm.WelcomePage, 'https://paypal.me/bjoernoppermann', 'https://paypal.me/bjoernoppermann', Y, Dummy);
  Dummy.Left := WizardForm.WelcomeLabel2.Left;

  // Seite nach der Installation: alle Links anklickbar
  LinksPage := CreateCustomPage(wpInstalling, CustomMessage('InfoTitle'), CustomMessage('InfoDesc'));
  W := LinksPage.SurfaceWidth;
  Y := 0;
  Y := AddText(LinksPage.Surface, CustomMessage('InfoDonate'), 0, Y, W);
  Y := AddLink(LinksPage.Surface, 'https://paypal.me/bjoernoppermann', 'https://paypal.me/bjoernoppermann', Y, Dummy);
  Y := AddText(LinksPage.Surface, CustomMessage('InfoBlog'), 0, Y, W);
  Y := AddLink(LinksPage.Surface, 'https://nga.li/rf4b', 'https://nga.li/rf4b', Y, Dummy);
  Y := AddText(LinksPage.Surface, CustomMessage('InfoDownload'), 0, Y, W);
  Y := AddLink(LinksPage.Surface, 'https://nga.li/rf4dl', 'https://nga.li/rf4dl', Y, Dummy);
  Y := AddText(LinksPage.Surface, CustomMessage('InfoSource'), 0, Y, W);
  Y := AddLink(LinksPage.Surface, 'https://nga.li/rf4git', 'https://nga.li/rf4git', Y, Dummy);
  Y := AddText(LinksPage.Surface, CustomMessage('InfoGuide'), 0, Y, W);
  Y := AddLink(LinksPage.Surface, CustomMessage('InfoGuideLink'), '', Y, GuideLinkLabel);
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (LinksPage <> nil) and (CurPageID = LinksPage.ID) then
    GuideLinkLabel.Hint := GuideFile;
end;

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