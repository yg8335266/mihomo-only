Option Explicit
' Start mihomo elevated in portable mode.
' Force home directory to this folder so data is NOT written to %USERPROFILE%\.config\mihomo

Dim ws, fso, scriptPath, objShell, objWMI, colProcesses, objProcess, args, exePath, cfgPath

Set ws = CreateObject("Wscript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = fso.GetParentFolderName(WScript.ScriptFullName)
ws.CurrentDirectory = scriptPath

exePath = scriptPath & "\mihomo.exe"
cfgPath = scriptPath & "\config.yaml"

If Not fso.FileExists(exePath) Then
  MsgBox "mihomo.exe not found:" & vbCrLf & exePath, 16, "Mihomo"
  WScript.Quit 1
End If

If Not fso.FileExists(cfgPath) Then
  MsgBox "config.yaml not found:" & vbCrLf & cfgPath, 16, "Mihomo"
  WScript.Quit 1
End If

' Stop existing mihomo first
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
Set colProcesses = objWMI.ExecQuery("Select * from Win32_Process Where Name = 'mihomo.exe'")
If colProcesses.Count > 0 Then
  For Each objProcess In colProcesses
    On Error Resume Next
    objProcess.Terminate
    On Error GoTo 0
  Next
  WScript.Sleep 1000
End If

' IMPORTANT:
' -d  = portable home directory (ui/cache/geo/providers stay here)
' -f  = absolute config path
args = "-d """ & scriptPath & """ -f """ & cfgPath & """"

Set objShell = CreateObject("Shell.Application")
' Use full exe path to avoid picking another mihomo.exe from PATH
objShell.ShellExecute exePath, args, scriptPath, "runas", 0

WScript.Quit 0
