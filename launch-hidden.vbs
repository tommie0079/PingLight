' =========================================================
'  Hidden launcher for PingLight.
'  Runs PingLight.ps1 with NO visible PowerShell window.
'  Called by Start-PingLight.bat, which passes the host and name.
'  Arguments: 0 = HostName, 1 = Name (optional)
' =========================================================
Option Explicit

Dim args, hostName, widgetName, scriptDir, cmd, shell
Set args = WScript.Arguments

If args.Count >= 1 Then hostName = args(0) Else hostName = ""
If args.Count >= 2 Then widgetName = args(1) Else widgetName = ""

' Folder this .vbs lives in (so PingLight.ps1 is found next to it).
scriptDir = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ _
    & scriptDir & "PingLight.ps1"" -HostName """ & hostName & """ -Name """ & widgetName & """"

Set shell = CreateObject("WScript.Shell")
' 0 = hidden window, False = don't wait for it to exit.
shell.Run cmd, 0, False
