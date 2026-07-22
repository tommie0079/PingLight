@echo off
rem =========================================================
rem  Edit the hostname below to whatever you want to monitor.
rem  Double-click this file to launch the widget.
rem  Copy this .bat and change HOSTNAME to run several at once.
rem =========================================================

set "HOSTNAME=192.168.1.2"

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0PingLight.ps1" -HostName "%HOSTNAME%"
