# ══════════════════════════════════════════════════════════════════════════════
#  Grafische Oberfläche (Windows Forms, selbst gezeichnet, DPI-scharf, Dunkel/Hell automatisch)
#  Nutzt core.ps1 (Logik, Sprachen, Themes) und ui.cs (Bausteine).
# ══════════════════════════════════════════════════════════════════════════════
# WinForms braucht einen STA-Thread (Windows PowerShell 5.1 ist es, PowerShell 7 standardmäßig nicht) -> neu starten
if ($env:RF4_GUI_NOSHOW -ne '1' -and $PSCommandPath -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $exe = (Get-Process -Id $PID).Path
    Start-Process $exe -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Lang', $Lang)
    exit
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# @@UICS@@
if (-not ('Rf4Ui.UButton' -as [type])) {
    $uiPath = Join-Path $PSScriptRoot 'ui.cs'
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($uiPath, [Text.Encoding]::UTF8)) -ReferencedAssemblies System.Windows.Forms, System.Drawing
}
[Rf4Ui.Native]::EnableDpi()
[Rf4Ui.Native]::HideConsole()
[Rf4Ui.WheelFilter]::Install()
# ── Globaler Fehlerfänger: Fehler in Ereignissen führen nicht mehr zum .NET-Absturzdialog ──
function Write-ErrorLog([string]$msg) {
    try { New-Item -ItemType Directory -Force -Path (Get-ConfigDir) | Out-Null; Add-Content -LiteralPath (Join-Path (Get-ConfigDir) 'error.log') -Value ("{0}  {1}`r`n" -f (Get-Date -Format 's'), $msg) -Encoding UTF8 } catch { }
}
try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch { }
[System.Windows.Forms.Application]::add_ThreadException({
    param($s, $e)
    $m = $e.Exception.Message; Write-ErrorLog ($m + ' | ' + $e.Exception.StackTrace)
    $script:state.Busy = $false; $script:lblCur = $null
    try { $form.Cursor = [System.Windows.Forms.Cursors]::Default } catch { }
    try { [void](Show-Msg ((T 'err_unexpected') + "`n`n" + $m + "`n`n" + (T 'err_logged' @((Join-Path (Get-ConfigDir) 'error.log')))) 'Error' 'OK') } catch { }
})
                       # VOR dem ersten Fenster: sonst skaliert Windows das Bild hoch (unscharf)
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
Initialize-Lang $Lang

# ── Skalierung, Schriften, Theme ───────────────────────────────────────────────
function Get-SystemScale {
    if ($env:RF4_GUI_SCALE) { return [double]$env:RF4_GUI_SCALE }
    try { $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $s = $g.DpiX / 96.0; $g.Dispose(); return $s } catch { return 1.0 }
}
$script:Scale = Get-SystemScale
function S([double]$n) { [int][Math]::Round($n * $script:Scale) }

function New-F([double]$pt, [bool]$bold = $false) {
    $fam = if ($script:Lang -eq 'zh') { 'Microsoft YaHei UI' } else { 'Segoe UI' }
    $st = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    New-Object System.Drawing.Font($fam, [single]($pt * $script:Scale * 96.0 / 72.0), $st, [System.Drawing.GraphicsUnit]::Pixel)
}
function Update-Fonts {
    $script:F = @{ body = (New-F 9.5); bold = (New-F 9.5 $true); small = (New-F 8.5); smallb = (New-F 8.5 $true); h1 = (New-F 16 $true); h2 = (New-F 12 $true); big = (New-F 20 $true); card = (New-F 10.5 $true) }
}
function Get-ThemeName([string]$code) {
    $k = "theme_name_$code"
    if ($script:TX.ContainsKey($k)) { return (T $k) }
    return [string]$script:Themes[$code].name
}
function ColorOf([string]$hex) { [Rf4Ui.UiTheme]::Hex($hex) }
function Apply-Theme {
    $cfg = Get-Config
    $script:ThemeChoice = if ($cfg.theme) { $cfg.theme } else { 'auto' }
    $script:ThemeCode = Resolve-ThemeCode $script:ThemeChoice
    $c = Get-ThemeColors $script:ThemeCode
    $script:Col = @{}
    foreach ($k in $c.Keys) { $script:Col[$k] = ColorOf $c[$k] }
    [Rf4Ui.UiTheme]::Bg = $script:Col.bg; [Rf4Ui.UiTheme]::Surface = $script:Col.surface; [Rf4Ui.UiTheme]::Surface2 = $script:Col.surface2
    [Rf4Ui.UiTheme]::Border = $script:Col.border; [Rf4Ui.UiTheme]::Text = $script:Col.text; [Rf4Ui.UiTheme]::Muted = $script:Col.muted
    [Rf4Ui.UiTheme]::Accent = $script:Col.accent; [Rf4Ui.UiTheme]::AccentHover = $script:Col.accentHover; [Rf4Ui.UiTheme]::AccentText = $script:Col.accentText
    [Rf4Ui.UiTheme]::Success = $script:Col.success; [Rf4Ui.UiTheme]::Warn = $script:Col.warn; [Rf4Ui.UiTheme]::Danger = $script:Col.danger
    [Rf4Ui.UiTheme]::Selection = $script:Col.selection
    [Rf4Ui.UiTheme]::Dark = ($script:Themes[$script:ThemeCode].base -eq 'dark')
}
Update-Fonts
Apply-Theme

# ── Bausteine ──────────────────────────────────────────────────────────────────
function New-Lbl([string]$text, $font = $null, $color = $null) {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $false; $l.UseMnemonic = $false; $l.Text = $text
    $l.Font = $(if ($font) { $font } else { $script:F.body })
    $l.ForeColor = $(if ($color) { $color } else { $script:Col.text })
    $l.BackColor = [System.Drawing.Color]::Transparent
    return $l
}
function New-Btn([string]$text, [string]$kind = 'secondary', [string]$icon = '', [bool]$chevron = $false) {
    $b = New-Object Rf4Ui.UButton
    $b.Kind = $kind; $b.IconKind = $icon; $b.ShowChevron = $chevron; $b.Dpi = [single]$script:Scale
    $b.Font = $script:F.bold; $b.Text = $text; $b.BackColor = $script:Col.bg
    $m = $b.Measure(); $b.Size = New-Object System.Drawing.Size($m.Width, [Math]::Max($m.Height, (S 38)))
    return $b
}
function New-Cards([string]$mode = 'one', [int]$cardH = 0) {
    $l = New-Object Rf4Ui.UCardList
    $l.Mode = $mode; $l.Dpi = [single]$script:Scale; $l.CardHeight = $(if ($cardH) { $cardH } else { S 66 }); $l.Gap = (S 8)
    $l.TitleFont = $script:F.card; $l.SubFont = $script:F.small; $l.BadgeFont = $script:F.smallb; $l.Font = $script:F.small
    $l.BackColor = $script:Col.bg
    return $l
}
function New-Check([string]$text, [bool]$checked = $false) {
    $c = New-Object Rf4Ui.UCheck
    $c.Dpi = [single]$script:Scale; $c.Font = $script:F.body; $c.Text = $text; $c.Checked = $checked; $c.BackColor = $script:Col.bg
    $c.Size = New-Object System.Drawing.Size($c.PreferredWidth(), (S 28))
    return $c
}
function New-Input([string]$value) {
    $i = New-Object Rf4Ui.UInput
    $i.Dpi = [single]$script:Scale; $i.Font = $script:F.body; $i.BackColor = $script:Col.bg; $i.Height = (S 40); $i.Text = $value; $i.ApplyTheme()
    return $i
}
# Auswahl-Button mit Menü (Sprache, Design, Account …):  items = @( @{ text=..; value=.. } … )
function New-Dropdown([string]$text, [string]$icon, $items, [string]$selected, [scriptblock]$onPick) {
    $b = New-Btn $text 'secondary' $icon $true
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Renderer = New-Object Rf4Ui.ThemedRenderer
    $menu.Font = $script:F.body; $menu.BackColor = $script:Col.surface; $menu.ForeColor = $script:Col.text; $menu.ShowImageMargin = $true
    foreach ($it in $items) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($it.text)
        $mi.Tag = [string]$it.value; $mi.Checked = ([string]$it.value -eq $selected)
        $mi.ForeColor = $script:Col.text; $mi.BackColor = $script:Col.surface; $mi.Padding = New-Object System.Windows.Forms.Padding((S 4), (S 6), (S 4), (S 6))
        $cb = $onPick
        $mi.Add_Click({ param($s, $e) & $cb ([string]$s.Tag) }.GetNewClosure())
        [void]$menu.Items.Add($mi)
    }
    $b.Tag = $menu
    $b.Add_Click({ param($s, $e) $s.Tag.Show($s, (New-Object System.Drawing.Point(0, ($s.Height + (S 4))))) })
    return $b
}

# Eigenes, themefähiges Meldungsfenster (statt weißem MessageBox im dunklen Design).
# WICHTIG: Closures sehen $script:-Variablen nicht -> alles Nötige vorher in lokale Variablen holen.
function Show-Msg([string]$Text, [string]$Kind = 'Warning', [string]$Buttons = 'OK') {
    $colBg = $script:Col.bg; $colSurface = $script:Col.surface; $colText = $script:Col.text
    $isDark = [Rf4Ui.UiTheme]::Dark
    $res = @{ v = $(if ($Buttons -eq 'YesNo') { 'No' } else { 'OK' }) }
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = T 'app_title'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.StartPosition = 'CenterParent'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false; $dlg.BackColor = $colBg
    $w = (S 560); $dlg.ClientSize = New-Object System.Drawing.Size($w, (S 210))
    $icon = switch ($Kind) { 'Warning' { 'warn' } 'Error' { 'danger' } default { 'accent' } }
    $lbl = New-Lbl $Text $script:F.body $colText
    $lbl.SetBounds((S 30), (S 22), ($w - (S 60)), (S 120)); $lbl.AutoEllipsis = $true
    $bar = New-Object System.Windows.Forms.Panel; $bar.SetBounds(0, (S 18), (S 5), (S 110)); $bar.BackColor = [Rf4Ui.UiTheme]::Kind($icon)
    $dlg.Controls.AddRange(@($bar, $lbl))
    $by = (S 152)
    if ($Buttons -eq 'YesNo') {
        $y = New-Btn (T 'dialog_yes') 'primary'; $n = New-Btn (T 'dialog_no') 'secondary'
        $y.BackColor = $colBg; $n.BackColor = $colBg
        $y.Width = [Math]::Max($y.Width, (S 120)); $n.Width = [Math]::Max($n.Width, (S 120))
        $n.Location = New-Object System.Drawing.Point(($w - $n.Width - (S 24)), $by); $y.Location = New-Object System.Drawing.Point(($n.Left - $y.Width - (S 10)), $by)
        $y.Add_Click({ $res.v = 'Yes'; $dlg.Close() }.GetNewClosure()); $n.Add_Click({ $res.v = 'No'; $dlg.Close() }.GetNewClosure())
        $dlg.Controls.AddRange(@($y, $n))
    } else {
        $o = New-Btn (T 'dialog_ok') 'primary'; $o.BackColor = $colBg; $o.Width = [Math]::Max($o.Width, (S 120))
        $o.Location = New-Object System.Drawing.Point(($w - $o.Width - (S 24)), $by)
        $o.Add_Click({ $res.v = 'OK'; $dlg.Close() }.GetNewClosure()); $dlg.Controls.Add($o)
    }
    $dlg.Add_HandleCreated({ try { [Rf4Ui.Native]::TitleBar($dlg.Handle, $isDark, $colSurface, $colText) } catch { } }.GetNewClosure())
    try {
        if ($script:form -and $script:form.Visible) { [void]$dlg.ShowDialog($script:form) } else { [void]$dlg.ShowDialog() }
    } finally { $dlg.Dispose() }
    return $res.v
}
function New-AppIcon {
    try {
        $bmp = New-Object System.Drawing.Bitmap(64, 64); $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
        $p = [Rf4Ui.Gfx]::Round((New-Object System.Drawing.RectangleF(2, 2, 60, 60)), 14)
        $br = New-Object System.Drawing.SolidBrush($script:Col.accent); $g.FillPath($br, $p)
        [Rf4Ui.Gfx]::Icon($g, 'backup', (New-Object System.Drawing.RectangleF(13, 13, 38, 38)), $script:Col.accentText, 5)
        $g.Dispose(); return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
    } catch { return $null }
}

# ── Hauptfenster ───────────────────────────────────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$script:form = $form
$form.StartPosition = 'CenterScreen'; $form.AutoScaleMode = 'None'
# Startgröße: Wunschgröße, aber nie größer als der Bildschirm (kleine Laptops: 1366x768 bei 125 %)
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.ClientSize = New-Object System.Drawing.Size([Math]::Min((S 1000), [int]($wa.Width * 0.94)), [Math]::Min((S 740), [int]($wa.Height * 0.90) - (S 40)))
$form.MinimumSize = New-Object System.Drawing.Size([Math]::Min((S 780), $wa.Width), [Math]::Min((S 520), $wa.Height))
$ic = New-AppIcon; if ($ic) { $form.Icon = $ic }

$script:pContent = New-Object System.Windows.Forms.Panel; $script:pContent.Dock = 'Fill'; $script:pContent.AutoScroll = $true
$script:pContent.Add_HandleCreated({ try { [Rf4Ui.Native]::DarkScroll($script:pContent.Handle, [Rf4Ui.UiTheme]::Dark) } catch { } })
$script:stepper = New-Object Rf4Ui.UStepper; $script:stepper.Dock = 'Top'
$script:pHeader = New-Object System.Windows.Forms.Panel; $script:pHeader.Dock = 'Top'
$script:pFooter = New-Object System.Windows.Forms.Panel; $script:pFooter.Dock = 'Bottom'
$form.Controls.Add($script:pContent); $form.Controls.Add($script:stepper); $form.Controls.Add($script:pHeader); $form.Controls.Add($script:pFooter)

$script:lblTitle = New-Lbl '' $script:F.h1; $script:lblSub = New-Lbl '' $script:F.small
$script:lblDonate = New-Lbl '' $script:F.small; $script:lblDonate.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:lblDonate.Add_Click({ try { Start-Process 'https://paypal.me/bjoernoppermann' } catch { } })
$script:pHeader.Controls.AddRange(@($script:lblTitle, $script:lblSub, $script:lblDonate))
$script:btnBack = New-Btn '' 'secondary'; $script:btnExtra = New-Btn '' 'ghost'; $script:btnPrimary = New-Btn '' 'primary'
$script:pFooter.Controls.AddRange(@($script:btnBack, $script:btnExtra, $script:btnPrimary))
$script:btnBack.Add_Click({ if ($script:BackAction) { & $script:BackAction } })
$script:btnExtra.Add_Click({ if ($script:ExtraAction) { & $script:ExtraAction } })
$script:btnPrimary.Add_Click({ if ($script:PrimaryAction) { & $script:PrimaryAction } })
$script:state = @{ Installs = $null; Action = ''; Render = $null; Step = 0; LastOpen = ''; Busy = $false; ResultKey = '' }
$script:RunLog = New-Object System.Text.StringBuilder
$script:L = @()                                   # Layout-Einträge des aktuellen Panels
foreach ($n in @('lblCur', 'BackAction', 'PrimaryAction', 'ExtraAction', 'headHelp', 'headLang', 'headTheme', 'bkAcct', 'bkAcctItems', 'rsCurrent', 'statCtls', 'tbDetails', 'dlgResult', 'cmbDirty')) { Set-Variable -Name $n -Value $null -Scope Script }
$script:bkAcctValue = ''
$script:inLayout = $false
$script:Tip = New-Object System.Windows.Forms.ToolTip

# Rebuild der Kopfzeile (Texte, Schriften, Farben, Position)
function Build-Header {
    $script:pHeader.Height = (S 68); $script:pHeader.BackColor = $script:Col.surface
    $script:pFooter.Height = (S 68); $script:pFooter.BackColor = $script:Col.surface
    $script:pContent.BackColor = $script:Col.bg; $form.BackColor = $script:Col.bg
    $script:stepper.Height = (S 70); $script:stepper.BackColor = $script:Col.bg; $script:stepper.Dpi = [single]$script:Scale; $script:stepper.Font = $script:F.small
    $script:stepper.Steps = @((T 'step1'), (T 'step2'), (T 'step3'), (T 'step4'), (T 'step5'))
    $script:lblTitle.Font = $script:F.h1; $script:lblTitle.ForeColor = $script:Col.text; $script:lblTitle.Text = T 'app_title'
    $script:lblSub.Font = $script:F.small; $script:lblSub.ForeColor = $script:Col.muted; $script:lblSub.Text = 'v' + $script:ToolVersion + '  ·  '
    $script:lblDonate.Font = New-Object System.Drawing.Font($script:F.small, [System.Drawing.FontStyle]::Underline); $script:lblDonate.ForeColor = $script:Col.accent; $script:lblDonate.Text = T 'donate'
    $script:Tip.SetToolTip($script:lblDonate, 'https://paypal.me/bjoernoppermann')
    foreach ($b in @($script:headHelp, $script:headLang, $script:headTheme)) { if ($b) { $script:pHeader.Controls.Remove($b); $b.Dispose() } }
    # Hilfe: Anleitung in der aktuellen Sprache öffnen
    $script:headHelp = New-Btn (T 'help_btn') 'secondary' 'help'
    $script:headHelp.Add_Click({ Open-Guide })
    $script:Tip.SetToolTip($script:headHelp, (T 'tip_help'))
    # Sprache
    $langItems = @($script:Langs | ForEach-Object { @{ text = $script:LangNames[$_]; value = $_ } })
    $script:headLang = New-Dropdown $script:LangNames[$script:Lang] 'globe' $langItems $script:Lang { param($v) Set-Language $v }
    $script:Tip.SetToolTip($script:headLang, (T 'tip_lang'))
    # Design
    $items = @(@{ text = (T 'theme_auto'); value = 'auto' }) + @($script:Themes.Keys | ForEach-Object { @{ text = (Get-ThemeName $_); value = $_ } })
    $icon = if ($script:ThemeChoice -eq 'auto') { 'auto' } elseif ($script:Themes[$script:ThemeCode].base -eq 'dark') { 'moon' } else { 'sun' }
    $label = if ($script:ThemeChoice -eq 'auto') { T 'theme_auto' } else { Get-ThemeName $script:ThemeCode }
    $script:headTheme = New-Dropdown $label $icon $items $script:ThemeChoice { param($v) Set-ThemeChoice $v }
    $script:Tip.SetToolTip($script:headTheme, (T 'tip_theme'))
    $script:pHeader.Controls.AddRange(@($script:headHelp, $script:headLang, $script:headTheme))
    Position-Header
    $script:stepper.Current = $script:state.Step; $script:stepper.Invalidate()
    try { if ($script:pContent.IsHandleCreated) { [Rf4Ui.Native]::DarkScroll($script:pContent.Handle, [Rf4Ui.UiTheme]::Dark) } } catch { }
    $form.Text = (T 'app_title') + ' v' + $script:ToolVersion
    try { if ($form.IsHandleCreated) { [Rf4Ui.Native]::TitleBar($form.Handle, [Rf4Ui.UiTheme]::Dark, $script:Col.surface, $script:Col.text) } } catch { }
}
function Position-Header {
    $w = $script:pHeader.ClientSize.Width; $pad = (S 24)
    $script:lblTitle.SetBounds($pad, (S 8), [Math]::Max((S 200), $w - (S 560)), (S 32))
    $subW = [System.Windows.Forms.TextRenderer]::MeasureText($script:lblSub.Text, $script:lblSub.Font).Width
    $script:lblSub.SetBounds($pad, (S 40), $subW + (S 2), (S 20))
    $dw = [System.Windows.Forms.TextRenderer]::MeasureText($script:lblDonate.Text, $script:lblDonate.Font).Width
    $script:lblDonate.SetBounds($pad + $subW, (S 40), $dw + (S 4), (S 20))
    $h = $script:headLang.Height; $y = [int](($script:pHeader.Height - $h) / 2)
    $script:headTheme.Location = New-Object System.Drawing.Point(($w - $pad - $script:headTheme.Width), $y)
    $script:headLang.Location = New-Object System.Drawing.Point(($script:headTheme.Left - (S 10) - $script:headLang.Width), $y)
    $script:headHelp.Location = New-Object System.Drawing.Point(($script:headLang.Left - (S 10) - $script:headHelp.Width), $y)
}
function Position-Footer {
    $pad = (S 24); $w = $script:pFooter.ClientSize.Width; $y = [int](($script:pFooter.Height - $script:btnPrimary.Height) / 2)
    $script:btnBack.Location = New-Object System.Drawing.Point($pad, $y)
    $script:btnExtra.Location = New-Object System.Drawing.Point(($script:btnBack.Right + (S 10)), $y)
    $script:btnPrimary.Location = New-Object System.Drawing.Point(($w - $pad - $script:btnPrimary.Width), $y)
}
function Set-Footer([string]$backText, [scriptblock]$back, [string]$primaryText, [scriptblock]$primary, [string]$extraText = '', [scriptblock]$extra = $null, [string]$primaryIcon = '') {
    foreach ($pair in @(@($script:btnBack, $backText, 'secondary'), @($script:btnExtra, $extraText, 'ghost'), @($script:btnPrimary, $primaryText, 'primary'))) {
        $b = $pair[0]; $b.Text = $pair[1]; $b.Font = $script:F.bold; $b.Dpi = [single]$script:Scale; $b.BackColor = $script:Col.surface; $b.Kind = $pair[2]
        $b.Visible = [bool]$pair[1]
        if ($pair[1]) { $m = $b.Measure(); $b.Size = New-Object System.Drawing.Size([Math]::Max($m.Width, (S 120)), [Math]::Max($m.Height, (S 40))) }
    }
    $script:btnPrimary.IconKind = $primaryIcon; if ($primaryIcon) { $m = $script:btnPrimary.Measure(); $script:btnPrimary.Width = [Math]::Max($m.Width, (S 140)) }
    $script:btnPrimary.Enabled = $true
    $script:BackAction = $back; $script:PrimaryAction = $primary; $script:ExtraAction = $extra
    Position-Footer
}

# ── Layout-Engine: senkrechte Reihe (DPI-sicher, mit Scroll bei kleinem Fenster) ──
function Add-Item([hashtable]$it) { $script:L += $it; if ($it.ContainsKey('c')) { $script:pContent.Controls.Add($it.c) } }
function Add-Label([string]$text, $font = $null, $color = $null, [int]$gap = 8) {
    $l = New-Lbl $text $font $color; Add-Item @{ k = 'label'; c = $l; gap = (S $gap) }; return $l
}
function Add-Fill($ctl, [int]$min = 120) { Add-Item @{ k = 'fill'; c = $ctl; min = (S $min); gap = (S 12) } }
function Add-Fixed($ctl, [int]$h, [int]$gap = 12) { Add-Item @{ k = 'ctl'; c = $ctl; h = (S $h); gap = (S $gap) } }
function Add-Row([int]$h, [scriptblock]$fn, [int]$gap = 12) { Add-Item @{ k = 'row'; h = (S $h); fn = $fn; gap = (S $gap) } }
function Do-Layout {
    if ($script:inLayout -or -not $script:pContent) { return }
    $script:inLayout = $true
    try {
        $pad = (S 28); $top = (S 20)
        $w = [Math]::Max((S 300), $script:pContent.ClientSize.Width - 2 * $pad)
        $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
        $fixed = 0; $fillMin = 0; $fillItem = $null
        foreach ($it in $script:L) {
            switch ($it.k) {
                'label' { $sz = [System.Windows.Forms.TextRenderer]::MeasureText($it.c.Text, $it.c.Font, (New-Object System.Drawing.Size($w, 0)), $flags); $it.h = $sz.Height + (S 4) }
            }
            if ($it.k -eq 'fill') { $fillItem = $it; $fillMin += $it.min + $it.gap } else { $fixed += $it.h + $it.gap }
        }
        $avail = $script:pContent.ClientSize.Height - $top - (S 16)
        $fillH = [Math]::Max($(if ($fillItem) { $fillItem.min } else { 0 }), $avail - $fixed - $(if ($fillItem) { $fillItem.gap } else { 0 }))
        $y = $top
        foreach ($it in $script:L) {
            $h = if ($it.k -eq 'fill') { $fillH } else { $it.h }
            if ($it.k -eq 'fill' -and $it.c -is [Rf4Ui.UCardList] -and $it.c.Cards.Count -gt 0) { $h = [Math]::Min($h, $it.c.ContentHeight + (S 4)) }
            switch ($it.k) {
                'row' { & $it.fn $pad $y $w }
                default { $it.c.SetBounds($pad, $y, $w, $h) }
            }
            $y += $h + $it.gap
        }
        $script:pContent.AutoScrollMinSize = New-Object System.Drawing.Size(0, ($y + (S 8)))
        foreach ($it in $script:L) { if ($it.k -eq 'fill' -and $it.c -is [Rf4Ui.UCardList]) { $it.c.LayoutCards() } }
    } finally { $script:inLayout = $false }
}

function Show-Panel([scriptblock]$render) {
    $script:state.Render = $render
    $script:pContent.SuspendLayout()
    while ($script:pContent.Controls.Count -gt 0) { $c = $script:pContent.Controls[0]; $script:pContent.Controls.RemoveAt(0); $c.Dispose() }
    $script:L = @(); $script:pContent.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
    & $render
    $script:pContent.ResumeLayout($false)
    Do-Layout
    $script:stepper.Current = $script:state.Step; $script:stepper.Invalidate()
}
function Set-Step([int]$s) { $script:state.Step = $s; $script:stepper.Current = $s }

# ── Sprache / Design / DPI umschalten ──────────────────────────────────────────
function Rebuild-All {
    Update-Fonts; Apply-Theme; Build-Header
    $script:cmbDirty = $false
    if ($script:state.Render -and -not $script:state.Busy) { Show-Panel $script:state.Render }
    Position-Footer
}
function Set-Language([string]$code) {
    [void](Set-Lang $code); try { Save-Lang $script:Lang } catch { }
    Rebuild-All
}
function Set-ThemeChoice([string]$choice) {
    try { Save-ThemeChoice $choice } catch { }
    Rebuild-All
}
$script:pContent.Add_ClientSizeChanged({ Do-Layout })
$script:pHeader.Add_Resize({ if ($script:headLang) { Position-Header } })
$script:pFooter.Add_Resize({ Position-Footer })
$form.Add_DpiChanged({ param($s, $e) $script:Scale = $e.DeviceDpiNew / 96.0; Rebuild-All })
$form.Add_HandleCreated({ try { [Rf4Ui.Native]::TitleBar($form.Handle, [Rf4Ui.UiTheme]::Dark, $script:Col.surface, $script:Col.text) } catch { } })
# Windows-Design live verfolgen (nur bei "Automatisch")
$script:themeTimer = New-Object System.Windows.Forms.Timer; $script:themeTimer.Interval = 2000
$script:themeTimer.Add_Tick({
    if ($script:state.Busy) { return }
    $cfg = Get-Config; $choice = if ($cfg.theme) { $cfg.theme } else { 'auto' }
    if ($choice -eq 'auto' -and (Resolve-ThemeCode 'auto') -ne $script:ThemeCode) { Rebuild-All }
})

# ── Log-Senke ──────────────────────────────────────────────────────────────────
$script:LogSink = {
    param($lvl, $msg)
    $prefix = switch ($lvl) { 'ok' { '[OK] ' } 'warn' { '[!]  ' } 'err' { '[X]  ' } default { '     ' } }
    [void]$script:RunLog.AppendLine("$prefix$msg")
    if ($script:lblCur) { $script:lblCur.Text = $msg; $script:lblCur.Refresh() }
    [System.Windows.Forms.Application]::DoEvents()
}

function Ensure-Installs { if ($null -eq $script:state.Installs) { $script:state.Installs = @(Find-Installations) } }
function Get-ExistingInstalls { Ensure-Installs; @($script:state.Installs | Where-Object { $_.Exists }) }
function Confirm-GameClosedGui {
    $run = Test-Rf4Running
    if (-not $run) { return $true }
    return ((Show-Msg ((T 'running_warn' @($run)) + "`n`n" + (T 'running_ask')) 'Warning' 'YesNo') -eq 'Yes')
}
$script:ConfirmOverwrite = { param($name) ((Show-Msg (T 'overwrite_q' @($name, "`n")) 'Warning' 'YesNo') -eq 'Yes') }
function Pick-Folder([string]$start, [string]$desc = '') {
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($desc) { $fb.Description = $desc }
    if ($start -and (Test-Path -LiteralPath $start)) { $fb.SelectedPath = $start }
    if ($fb.ShowDialog($form) -eq 'OK') { return $fb.SelectedPath }
    return $null
}
function Inst-Card($list, $inst, [string]$icon = 'disk') {
    $sub = ''
    if ($inst.Exists) { $info = Get-InstInfo $inst.Path; $sub = (T 'scan_stats' @($info.Mailboxes.Count, $info.Convs)) + $(if ($info.Ids) { '   ·   ' + (T 'scan_accounts' @($info.Ids)) } else { '' }) + "`n" + $inst.Path }
    else { $sub = $inst.Path }
    $badge = if ($inst.Exists) { T 'chip_found' } else { T 'chip_missing' }
    $c = $list.Add((Get-InstLabel $inst), $sub, $badge, $(if ($inst.Exists) { 'ok' } else { 'muted' }), $icon, $inst)
    $c.Dim = (-not $inst.Exists)
    return $c
}

# ── Panel 1: Scan ──────────────────────────────────────────────────────────────
function Render-Scan {
    Set-Step 0
    [void](Add-Label (T 'hdr_scan_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'scan_hint') $script:F.small $script:Col.muted 12)
    $lst = New-Cards 'none' (S 92); Add-Fill $lst 160
    $status = Add-Label (T 'scanning') $script:F.body $script:Col.accent 4
    [void](Add-Label (T 'scan_readonly') $script:F.small $script:Col.success 4)
    Set-Footer (T 'rescan') { $script:state.Installs = $null; Show-Panel { Render-Scan } } (T 'next') { Show-Panel { Render-Action } }
    $script:btnPrimary.Enabled = $false
    Do-Layout; $form.Refresh()
    if ($null -eq $script:state.Installs) {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; [System.Windows.Forms.Application]::DoEvents()
        $script:state.Installs = @(Find-Installations)
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
    $found = 0
    foreach ($i in ($script:state.Installs | Sort-Object { -not $_.Exists })) { [void](Inst-Card $lst $i); if ($i.Exists) { $found++ } }
    $status.Text = if ($found -gt 0) { T 'found_n' @($found) } else { T 'none_found' }
    $status.ForeColor = if ($found -gt 0) { $script:Col.success } else { $script:Col.warn }
    $script:btnPrimary.Enabled = ($found -gt 0)
    Do-Layout
}

# ── Panel 2: Aktion ────────────────────────────────────────────────────────────
function Render-Action {
    Set-Step 1
    [void](Add-Label (T 'hdr_action_t') $script:F.h2 $script:Col.text 12)
    $acts = @(@('backup', 'act_backup', 'act_backup_d'), @('restore', 'act_restore', 'act_restore_d'), @('merge', 'act_merge', 'act_merge_d'), @('sync', 'act_sync', 'act_sync_d'))
    $script:actCards = @{}
    foreach ($a in $acts) {
        $c = New-Object Rf4Ui.UCard
        $c.Dpi = [single]$script:Scale; $c.Title = T $a[1]; $c.Sub = T $a[2]; $c.IconKind = $a[0]
        $c.TitleFont = $script:F.card; $c.SubFont = $script:F.body; $c.Font = $script:F.body; $c.BadgeFont = $script:F.smallb; $c.BackColor = $script:Col.bg
        $c.Selected = ($script:state.Action -eq $a[0]); $c.Tag = $a[0]; $c.IconTop = $true
        $c.Add_Click({ param($s, $e)
            $script:state.Action = [string]$s.Tag
            foreach ($k in $script:actCards.Keys) { $script:actCards[$k].Selected = ($k -eq $script:state.Action); $script:actCards[$k].Invalidate() }
        })
        $script:pContent.Controls.Add($c); $script:actCards[$a[0]] = $c
    }
    Add-Row 270 {
        param($x, $y, $w)
        $gap = (S 16); $cw = [int](($w - $gap) / 2); $ch = [int]((S 270 - $gap) / 2)
        $keys = @('backup', 'restore', 'merge', 'sync')
        for ($i = 0; $i -lt 4; $i++) { $script:actCards[$keys[$i]].SetBounds($x + ($i % 2) * ($cw + $gap), $y + [int][Math]::Floor($i / 2) * ($ch + $gap), $cw, $ch) }
    }
    Set-Footer (T 'back') { Show-Panel { Render-Scan } } (T 'next') {
        switch ($script:state.Action) {
            'backup'  { Show-Panel { Render-Backup } }
            'restore' { Show-Panel { Render-Restore } }
            'merge'   { Show-Panel { Render-Merge } }
            'sync'    { Show-Panel { Render-Sync } }
            default   { [void](Show-Msg (T 'pick_action')) }
        }
    }
}

# Reihe aus Checkboxen mit Umbruch
function Add-CheckRow($checks) {
    foreach ($c in $checks) { $script:pContent.Controls.Add($c) }
    $script:chkRowChecks = $checks
    $rows = 1
    Add-Row 34 {
        param($x, $y, $w)
        $cx = $x; $cy = $y; $gap = (S 26); $rowH = (S 32)
        foreach ($c in $script:chkRowChecks) {
            if ($cx + $c.Width -gt $x + $w -and $cx -gt $x) { $cx = $x; $cy += $rowH }
            $c.Location = New-Object System.Drawing.Point($cx, $cy); $cx += $c.Width + $gap
        }
    }
    # Höhe der Reihe an die tatsächliche Zeilenzahl anpassen
    $total = 0; foreach ($c in $checks) { $total += $c.Width + (S 26) }
    $it = $script:L[-1]; $avail = [Math]::Max((S 300), $script:pContent.ClientSize.Width - 2 * (S 28))
    $lines = [Math]::Max(1, [int][Math]::Ceiling($total / $avail)); $it.h = (S 32) * $lines + (S 2)
}

function Update-AcctText { $t = ($script:bkAcctItems | Where-Object { $_.value -eq $script:bkAcctValue } | Select-Object -First 1).text; $script:bkAcct.Text = (T 'sel_account') + ' ' + $t; $m = $script:bkAcct.Measure(); $script:bkAcct.Width = $m.Width; $script:bkAcct.Invalidate() }

# ── Panel 3a: Backup ───────────────────────────────────────────────────────────
function Render-Backup {
    Set-Step 2
    [void](Add-Label (T 'hdr_backup_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'pick_source') $script:F.small $script:Col.muted 8)
    $script:exSrc = Get-ExistingInstalls
    $lst = New-Cards 'one' (S 92); $script:lstSrc = $lst
    foreach ($i in $script:exSrc) { [void](Inst-Card $lst $i) }
    if ($lst.Cards.Count -gt 0) { $lst.SelectedIndex = 0 }
    Add-Fill $lst 150
    [void](Add-Label (T 'what_backup') $script:F.bold $script:Col.text 6)
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:bkKeys = $keys; $script:bkChecks = @()
    foreach ($k in $keys) { $script:bkChecks += (New-Check (T "item_$k") ($k -in @('mail', 'Settings.dat', 'Preferences.dat'))) }
    Add-CheckRow $script:bkChecks
    # Account-Auswahl (Dropdown), nur bei > 1 Mailbox
    $script:bkAcctHost = New-Object System.Windows.Forms.Panel; $script:bkAcctHost.BackColor = $script:Col.bg
    $script:pContent.Controls.Add($script:bkAcctHost); $script:bkAcct = $null; $script:bkAcctValue = ''
    Add-Item @{ k = 'ctl'; c = $script:bkAcctHost; h = (S 44); gap = (S 6) }
    $script:refreshAcct = {
        $script:bkAcctHost.Controls.Clear(); $script:bkAcctValue = ''
        if ($script:lstSrc.SelectedIndex -lt 0) { return }
        $boxes = @(Get-Mailboxes $script:exSrc[$script:lstSrc.SelectedIndex].Path)
        if ($boxes.Count -le 1) { return }
        $items = @(@{ text = (T 'all_accts' @($boxes.Count)); value = '' }) + @($boxes | ForEach-Object { @{ text = (T 'acct_line' @($_.Id, $_.Convs)); value = $_.Name } })
        $b = New-Dropdown ((T 'sel_account') + ' ' + (T 'all_accts' @($boxes.Count))) '' $items '' { param($v) $script:bkAcctValue = $v; Update-AcctText }
        $script:bkAcct = $b; $script:bkAcctItems = $items; $script:bkAcctHost.Controls.Add($b); $b.Location = New-Object System.Drawing.Point(0, 0)
    }

    $lst.add_SelectionChanged({ & $script:refreshAcct })
    & $script:refreshAcct
    [void](Add-Label (T 'backup_to') $script:F.bold $script:Col.text 6)
    $script:inDir = New-Input (Get-DefaultBackupDir); $script:pContent.Controls.Add($script:inDir)
    $script:btnBrowseBk = New-Btn (T 'btn_browse') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnBrowseBk)
    $script:btnBrowseBk.Add_Click({ $p = Pick-Folder $script:inDir.Text; if ($p) { $script:inDir.Text = $p } })
    Add-Row 42 { param($x, $y, $w) $bw = $script:btnBrowseBk.Width; $script:inDir.SetBounds($x, $y, $w - $bw - (S 10), (S 40)); $script:btnBrowseBk.SetBounds($x + $w - $bw, $y, $bw, (S 40)) } 4
    $script:lblBkHint = Add-Label '' $script:F.small $script:Col.muted 4
    $script:updateBkHint = { $d = $script:inDir.Text.Trim(); $i = if ($d) { Read-BackupInfo $d } else { $null }; $script:lblBkHint.Text = if ($i) { T 'bk_existing_here' @((Get-BackupSourceLabel $i) + '  ' + (Format-BackupDates ([pscustomobject]@{ Created = $i.Created; Updated = $i.Updated; Time = (Get-Date) }))) } else { '' }; Do-Layout }
    $script:inDir.Box.Add_TextChanged({ & $script:updateBkHint }); & $script:updateBkHint
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_backup') {
        if ($script:lstSrc.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        $items = @(); for ($i = 0; $i -lt $script:bkKeys.Count; $i++) { if ($script:bkChecks[$i].Checked) { $items += $script:bkKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        $src = $script:exSrc[$script:lstSrc.SelectedIndex]
        $dest = $script:inDir.Text.Trim(); if (-not $dest) { $dest = Get-DefaultBackupDir }
        $acc = if ($script:bkAcctValue) { @($script:bkAcctValue) } else { $null }
        Start-Operation 'hdr_backup_t' $dest {
            Copy-Rf4Data -SrcDir $src.Path -DstDir $dest -Items $items -Accounts $acc -ShotsSrc (Get-ScreenshotDir $src.Path) -ShotsDst (Join-Path $dest 'Screenshots') -Confirm $script:ConfirmOverwrite
            Write-BackupInfo $dest $src $items
            Add-BackupDir $dest
            Write-Log 'ok' 'backup_done' @($dest)
        }
    } '' $null 'backup'
}

# ── Panel 3b: Restore ──────────────────────────────────────────────────────────
function Render-Restore {
    Set-Step 2
    [void](Add-Label (T 'hdr_restore_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'existing_backups') $script:F.bold $script:Col.text 6)
    $script:rsBackups = @(Find-Backups); $script:rsExtra = $null
    $lb = New-Cards 'one' (S 136); $script:lstBk = $lb
    foreach ($b in $script:rsBackups) { [void]$lb.Add($b.Name, (Format-BackupCard $b), $(if ($b.IsSync) { T 'bk_badge_sync' } else { '' }), 'accent', 'disk', $b) }
    if ($script:rsBackups.Count -eq 0) { $lb.Visible = $true }
    Add-Fixed $lb ([Math]::Min(2, [Math]::Max(1, $script:rsBackups.Count)) * 144 + 4) 8
    $script:lblNoBk = Add-Label $(if ($script:rsBackups.Count -eq 0) { T 'no_existing_backups' } else { '' }) $script:F.small $script:Col.muted 8
    $script:btnOtherBk = New-Btn (T 'other_folder') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnOtherBk)
    Add-Row 40 { param($x, $y, $w) $script:btnOtherBk.SetBounds($x, $y, $script:btnOtherBk.Width, (S 40)) }
    [void](Add-Label (T 'pick_target') $script:F.bold $script:Col.text 6)
    Ensure-Installs; $script:rsIns = @($script:state.Installs)
    $ld = New-Cards 'one' (S 92); $script:lstDst = $ld
    foreach ($i in ($script:rsIns | Sort-Object { -not $_.Exists })) { [void](Inst-Card $ld $i) }
    Add-Fill $ld 120
    [void](Add-Label (T 'what_restore') $script:F.bold $script:Col.text 6)
    $keys = @('mail', 'Settings.dat', 'Preferences.dat', 'Crafting.dat', 'shots')
    $script:rsKeys = $keys; $script:rsChecks = @()
    foreach ($k in $keys) { $script:rsChecks += (New-Check (T "item_$k") $false) }
    Add-CheckRow $script:rsChecks
    $script:rsCurrent = $null
    $script:applyBackup = {
        param($bk)
        $script:rsCurrent = $bk
        $has = @{ 'mail' = ($bk.Mailboxes -gt 0); 'shots' = ($bk.Shots -gt 0) }; foreach ($f in $script:DatFiles) { $has[$f] = ($bk.Files -contains $f) }
        for ($i = 0; $i -lt $script:rsKeys.Count; $i++) { $c = $script:rsChecks[$i]; $c.Enabled = [bool]$has[$script:rsKeys[$i]]; $c.Checked = [bool]$has[$script:rsKeys[$i]]; $c.Invalidate() }
    }
    $lb.add_SelectionChanged({ $ix = $script:lstBk.SelectedIndex; if ($ix -ge 0) { & $script:applyBackup $script:rsBackups[$ix] } })
    $script:btnOtherBk.Add_Click({
        $start = if (Get-SyncPath) { Get-SyncPath } else { Get-DefaultBackupDir }
        $p = Pick-Folder $start (T 'pick_backup_d'); if (-not $p) { return }
        $rp = Resolve-BackupPath $p     # nimmt auch den übergeordneten Ordner eines RF4_Sync-Ordners (Netzwerk/NAS)
        if (-not $rp) { [void](Show-Msg ((T 'restore_path_bad') + "`n`n" + $p)); return }
        $dupe = [Array]::FindIndex($script:lstBk.Cards.ToArray(), [Predicate[object]] { param($c) $c.Tag2.Path -eq $rp })
        if ($dupe -ge 0) { $script:lstBk.SelectedIndex = $dupe; return }
        $bk = Get-BackupEntry $rp
        [void]$script:lstBk.Add($bk.Name, (Format-BackupCard $bk), $(if ($bk.IsSync) { T 'bk_badge_sync' } else { '' }), 'accent', 'disk', $bk)
        $script:lstBk.SelectedIndex = $script:lstBk.Cards.Count - 1
        $script:rsBackups = @($script:lstBk.Cards | ForEach-Object { $_.Tag2 })
        $script:lblNoBk.Text = ''; Do-Layout
    })
    if ($lb.Cards.Count -gt 0) { $lb.SelectedIndex = 0 }
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_restore') {
        if (-not $script:rsCurrent) { [void](Show-Msg (T 'select_backup_first')); return }
        if ($script:lstDst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        $items = @(); for ($i = 0; $i -lt $script:rsKeys.Count; $i++) { if ($script:rsChecks[$i].Checked -and $script:rsChecks[$i].Enabled) { $items += $script:rsKeys[$i] } }
        if ($items.Count -eq 0) { [void](Show-Msg (T 'pick_item')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dst = $script:lstDst.Cards[$script:lstDst.SelectedIndex].Tag2.Path; $src = $script:rsCurrent.Path
        Start-Operation 'hdr_restore_t' $dst {
            Write-Log 'info' 'importing_to' @($dst)
            Copy-Rf4Data -SrcDir $src -DstDir $dst -Items $items -ShotsSrc (Join-Path $src 'Screenshots') -ShotsDst (Get-ScreenshotDir $dst -Create) -Confirm $script:ConfirmOverwrite -UndoRoot (New-UndoRoot $dst)
            Add-BackupDir (Split-Path $src -Parent)
            Write-Log 'ok' 'restore_done'
        }
    } '' $null 'restore'
}

# ── Panel 3c: Merge ────────────────────────────────────────────────────────────
function Render-Merge {
    Set-Step 2
    [void](Add-Label (T 'hdr_merge_t') $script:F.h2 $script:Col.text 4)
    $ex = Get-ExistingInstalls; $script:mgEx = $ex
    if ($ex.Count -lt 2) {
        [void](Add-Label (T 'merge_need2') $script:F.body $script:Col.warn 8)
        Set-Footer (T 'back') { Show-Panel { Render-Action } } '' $null; return
    }
    [void](Add-Label (T 'merge_note') $script:F.small $script:Col.warn 4)
    [void](Add-Label (T 'merge_safe') $script:F.small $script:Col.success 4)
    [void](Add-Label (T 'undo_hint') $script:F.small $script:Col.muted 10)
    [void](Add-Label (T 'merge_dst') $script:F.bold $script:Col.text 6)
    $script:lstMgDst = New-Cards 'one' (S 92); foreach ($i in $ex) { [void](Inst-Card $script:lstMgDst $i) }
    Add-Fill $script:lstMgDst 120
    [void](Add-Label (T 'merge_src') $script:F.bold $script:Col.text 6)
    $script:lstMgSrc = New-Cards 'multi' (S 92); foreach ($i in $ex) { [void](Inst-Card $script:lstMgSrc $i) }
    Add-Fill $script:lstMgSrc 120
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'run_merge') {
        $d = $script:lstMgDst.SelectedIndex; $s = @($script:lstMgSrc.SelectedIndices)
        if ($d -lt 0) { [void](Show-Msg (T 'pick_dst')); return }
        if ($s.Count -eq 0) { [void](Show-Msg (T 'pick_one_src')); return }
        if ($s -contains $d) { [void](Show-Msg (T 'merge_same')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        $dstPath = $script:mgEx[$d].Path; $srcs = @($s | ForEach-Object { $script:mgEx[$_] }); $undo = New-UndoRoot $dstPath
        Start-Operation 'hdr_merge_t' $dstPath {
            foreach ($si in $srcs) {
                Write-Log 'info' 'merge_src_hdr' @((Get-InstLabel $si))
                Copy-Rf4Data -SrcDir $si.Path -DstDir $dstPath -Items @('mail') -UndoRoot $undo
            }
            Write-Log 'ok' 'merge_done'
        }
    } '' $null 'merge'
}

# ── Panel 3d: Sync ─────────────────────────────────────────────────────────────
function Render-Sync {
    Set-Step 2
    [void](Add-Label (T 'hdr_sync_t') $script:F.h2 $script:Col.text 4)
    [void](Add-Label (T 'sync_intro') $script:F.small $script:Col.muted 10)
    [void](Add-Label (T 'sync_dir_lbl') $script:F.bold $script:Col.text 6)
    $script:inSync = New-Input (Get-SyncPath); $script:pContent.Controls.Add($script:inSync)
    $script:btnBrowseSy = New-Btn (T 'btn_browse') 'secondary' 'folder'; $script:pContent.Controls.Add($script:btnBrowseSy)
    $script:btnBrowseSy.Add_Click({ $p = Pick-Folder $script:inSync.Text (T 'sync_pick_dir'); if ($p) { $script:inSync.Text = $p; Set-SyncPath $p } })
    Add-Row 42 { param($x, $y, $w) $bw = $script:btnBrowseSy.Width; $script:inSync.SetBounds($x, $y, $w - $bw - (S 10), (S 40)); $script:btnBrowseSy.SetBounds($x + $w - $bw, $y, $bw, (S 40)) } 4
    [void](Add-Label (T 'sync_hint') $script:F.small $script:Col.muted 12)
    [void](Add-Label (T 'sync_inst_lbl') $script:F.bold $script:Col.text 6)
    $script:syEx = Get-ExistingInstalls
    $script:lstSyInst = New-Cards 'one' (S 92); foreach ($i in $script:syEx) { [void](Inst-Card $script:lstSyInst $i) }
    if ($script:lstSyInst.Cards.Count -gt 0) { $script:lstSyInst.SelectedIndex = 0 }
    Add-Fill $script:lstSyInst 110
    $script:lblSyState = Add-Label '' $script:F.small $script:Col.muted 4
    $script:lstSySt = New-Cards 'none' (S 40); Add-Fill $script:lstSySt 80
    Set-Footer (T 'back') { Show-Panel { Render-Action } } (T 'sync_run_btn') {
        $sp = $script:inSync.Text.Trim()
        if (-not $sp) { [void](Show-Msg (T 'sync_first')); return }
        if (-not (Test-Path -LiteralPath $sp)) { [void](Show-Msg ((T 'sync_unreach' @($sp)) + "`n" + (T 'sync_unreach_h'))); return }
        if ($script:lstSyInst.SelectedIndex -lt 0) { [void](Show-Msg (T 'pick_src')); return }
        if (-not (Confirm-GameClosedGui)) { return }
        Set-SyncPath $sp; $inst = $script:syEx[$script:lstSyInst.SelectedIndex]
        Start-Operation 'hdr_sync_t' $inst.Path { Invoke-SyncRun -InstPath $inst.Path -SyncBase $sp }
    } (T 'sync_status_btn') {
        $script:lstSySt.ClearItems(); $sp = $script:inSync.Text.Trim()
        if (-not $sp) { $script:lblSyState.Text = T 'sync_none'; return }
        if (-not (Test-Path -LiteralPath $sp)) { $script:lblSyState.Text = T 'sync_unreach' @($sp); return }
        Set-SyncPath $sp; $script:lblSyState.Text = T 'sync_ok' @($sp)
        $st = Get-SyncStatus $sp
        if (-not $st.Exists) { [void]$script:lstSySt.Add((T 'sync_st_nodir'), '', '', 'muted', '', $null); return }
        if ($st.Mailboxes.Count -eq 0) { [void]$script:lstSySt.Add((T 'sync_st_none'), '', '', 'muted', '', $null) }
        foreach ($m in $st.Mailboxes) { [void]$script:lstSySt.Add((T 'sync_st_boxes' @($m.Name, $m.Convs)), '', '', 'muted', '', $null) }
        foreach ($f in $st.Files) { [void]$script:lstSySt.Add("$($f.Name)  ·  $($f.Time)", '', '', 'muted', '', $null) }
        foreach ($l in $st.Log) { [void]$script:lstSySt.Add($l, '', '', 'muted', '', $null) }
    } 'sync'
}

# ── Ausführen + Ergebnis ───────────────────────────────────────────────────────
function Start-Operation([string]$titleKey, [string]$openPath, [scriptblock]$work) {
    if ($script:state.Busy) { return }
    $script:state.Busy = $true; $script:state.LastOpen = $openPath; $script:state.ResultKey = $titleKey
    $script:RunLog.Clear() | Out-Null; Reset-Stats
    Show-Panel {
        Set-Step 3
        [void](Add-Label (T $script:state.ResultKey) $script:F.h2 $script:Col.text 8)
        [void](Add-Label (T 'working_title') $script:F.body $script:Col.muted 18)
        $pg = New-Object Rf4Ui.UProgress; $pg.Dpi = [single]$script:Scale; $pg.BackColor = $script:Col.bg; Add-Fixed $pg 12 14
        $script:lblCur = Add-Label (T 'working') $script:F.small $script:Col.accent 4
        Set-Footer '' $null '' $null
    }
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    [System.Windows.Forms.Application]::DoEvents()
    try { & $work } catch { Add-Stat Failed; Write-Log 'err' 'f_failed' @($titleKey, $_.Exception.Message) }
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    $script:lblCur = $null; $script:state.Busy = $false
    Show-Panel { Render-Result }
}
function Render-Result {
    Set-Step 4
    $st = Get-Stats
    [void](Add-Label ((T $script:state.ResultKey) + '  ·  ' + (T 'result_title')) $script:F.h2 $script:Col.text 10)
    # Status-Karte
    $card = New-Object Rf4Ui.UCard; $card.Dpi = [single]$script:Scale; $card.Clickable = $false; $card.Cursor = [System.Windows.Forms.Cursors]::Default
    $card.IconKind = 'check'; $card.TitleFont = $script:F.card; $card.SubFont = $script:F.small; $card.Font = $script:F.small; $card.BadgeFont = $script:F.smallb; $card.BackColor = $script:Col.bg
    if ($st.Failed -gt 0) { $card.Title = T 'res_err' @($st.Failed); $card.Badge = ''; $card.IconKind = 'folder' } else { $card.Title = T 'res_ok' }
    $card.Sub = $script:state.LastOpen
    Add-Fixed $card 74 14
    # Kennzahlen
    $stats = @()
    $stats += , @($st.MsgAdded, (T 'sum_msgs'), 'accent')
    $stats += , @(($st.ConvNew + $st.ConvMerged), (T 'sum_convs'), 'ok')
    $stats += , @(($st.FilesNew + $st.FilesReplaced), (T 'sum_files'), 'ok')
    if ($st.Shots -gt 0) { $stats += , @($st.Shots, (T 'sum_shots'), 'ok') }
    if ($st.FilesSkipped -gt 0) { $stats += , @($st.FilesSkipped, (T 'sum_skipped'), 'warn') }
    if ($st.Failed -gt 0) { $stats += , @($st.Failed, (T 'sum_failed'), 'danger') }
    $script:statCtls = @()
    foreach ($s in $stats) {
        $u = New-Object Rf4Ui.UStat; $u.Dpi = [single]$script:Scale; $u.Value = [string]$s[0]; $u.Caption = [string]$s[1]; $u.Kind = [string]$s[2]; $u.ValueFont = $script:F.big; $u.Font = $script:F.small; $u.BackColor = $script:Col.bg
        $script:pContent.Controls.Add($u); $script:statCtls += $u
    }
    Add-Row 84 {
        param($x, $y, $w)
        $n = $script:statCtls.Count; if ($n -eq 0) { return }
        $gap = (S 12); $cw = [int](($w - $gap * ($n - 1)) / $n)
        for ($i = 0; $i -lt $n; $i++) { $script:statCtls[$i].SetBounds($x + $i * ($cw + $gap), $y, $cw, (S 84)) }
    } 14
    # Details
    $script:btnDetails = New-Btn (T 'show_details') 'ghost'; $script:pContent.Controls.Add($script:btnDetails)
    Add-Row 40 { param($x, $y, $w) $script:btnDetails.SetBounds($x, $y, $script:btnDetails.Width, (S 38)) } 4
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Multiline = $true; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.BorderStyle = 'None'; $tb.Font = New-Object System.Drawing.Font('Consolas', [single](9.5 * $script:Scale * 96 / 72), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $tb.Add_HandleCreated({ param($s, $e) try { [Rf4Ui.Native]::DarkScroll($s.Handle, [Rf4Ui.UiTheme]::Dark) } catch { } }); $tb.BackColor = $script:Col.surface; $tb.ForeColor = $script:Col.text; $tb.Text = ($script:RunLog.ToString().Replace("`r`n", "`n").Replace("`n", "`r`n")); $tb.Visible = $false
    $script:tbDetails = $tb; Add-Fill $tb 140
    $script:btnDetails.Add_Click({
        $script:tbDetails.Visible = -not $script:tbDetails.Visible
        $script:btnDetails.Text = if ($script:tbDetails.Visible) { T 'hide_details' } else { T 'show_details' }
        $m = $script:btnDetails.Measure(); $script:btnDetails.Width = $m.Width; $script:pContent.ScrollControlIntoView($script:tbDetails)
    })
    Set-Footer (T 'btn_open') { if ($script:state.LastOpen -and (Test-Path -LiteralPath $script:state.LastOpen)) { Start-Process explorer.exe -ArgumentList ('"' + $script:state.LastOpen + '"') } } (T 'btn_start_over') { $script:state.Installs = $null; Show-Panel { Render-Scan } } '' $null 'sync'
    $script:btnPrimary.IconKind = ''
}

# ── Start ──────────────────────────────────────────────────────────────────────
Build-Header
if ($env:RF4_GUI_NOSHOW -ne '1') {
    $form.Add_Shown({ Show-Panel { Render-Scan }; $script:themeTimer.Start() })
    [void]$form.ShowDialog()
}
