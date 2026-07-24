@echo off
rem =========================================================
rem  Edit the values below to whatever you want to monitor.
rem  HOSTNAME = the host/IP to ping.
rem  NAME     = the friendly label shown in the widget.
rem             Leave NAME empty to show the hostname instead.
rem  Double-click this file to launch the widget.
rem  Copy this .bat and change the values to run several at once.
rem =========================================================

set "HOSTNAME=192.168.x.x"
set "NAME=Enter_name"

rem  Launch through wscript so no PowerShell window ever appears.
start "" wscript.exe "%~dp0launch-hidden.vbs" "%HOSTNAME%" "%NAME%"
