Option Explicit
Dim sh, fso, root, ps1, cmd
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = root & "\MihomoManager.ps1"
If Not fso.FileExists(ps1) Then
  MsgBox "MihomoManager.ps1 not found. Put it next to this VBS.", 16, "Mihomo Manager"
  WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & ps1 & """"
sh.Run cmd, 0, False