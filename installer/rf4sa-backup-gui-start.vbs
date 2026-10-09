' Startet die GUI ohne sichtbares Konsolenfenster (kein Aufblitzen). Version wird aus dem Dateinamen der .ps1 im selben Ordner ermittelt.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
best = ""
For Each f In fso.GetFolder(dir).Files
  If LCase(Left(f.Name, 18)) = "rf4sa-backup-gui-v" Then
    If LCase(Right(f.Name, 4)) = ".ps1" Then best = f.Path
  End If
Next
If best <> "" Then
  sh.Run "powershell.exe -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & best & """", 0, False
End If