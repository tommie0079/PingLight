@echo off
rem =========================================================
rem  Edit the values below to whatever you want to monitor.
rem  HOSTNAME = the host/IP to ping.
rem  NAME     = the friendly label shown in the widget.
rem             Leave NAME empty to show the hostname instead.
rem  Double-click this file to launch the widget.
rem  Copy this .bat and change the values to run several at once.
rem =========================================================

set "HOSTNAME=192.168.1.2"
set "NAME=SSP Hyper -v"

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0PingLight.ps1" -HostName "%HOSTNAME%" -Name "%NAME%"
