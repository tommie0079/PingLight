# PingLight

PingLight is a lightweight, always-on-top desktop widget for Windows that
continuously pings a host and shows its status as a colored circle.

| Color | Meaning |
|-------|---------|
| 🟢 Green | The host replied to the last ping. |
| 🔴 Red | The host did not reply. |
| ⚪ Grey | Checking, or the first ping is still pending. |

It has no external dependencies and runs entirely on the PowerShell and WPF
components already included with Windows.

## Features

- **Always on top** — stays above other windows and re-asserts itself when
  another application opens, so it is not pushed to the back.
- **No console window** — launched through a small VBScript wrapper, so no
  PowerShell window ever appears.
- **Editable label** — click the text, type a new name, and press Enter. The
  label is display-only and does not change which host is pinged.
- **Edge and corner snapping** — the window snaps to screen edges and corners.
- **Widget snapping** — multiple PingLights snap to one another to form a tidy
  status bar.
- **Draggable** — click and drag the circle to reposition it.
- **Resizable** — scale the entire widget up or down (see [Resizing](#resizing)).
- **Resilient** — transient ping, display, and UI errors are caught and logged
  instead of closing the widget.
- **Logging** — startup, shutdown, and errors are written to a per-host log file
  for troubleshooting.
- **Zero dependencies** — no additional runtimes to install.

## Requirements

- Windows with PowerShell (included by default).

## Getting started

1. Open `Start-PingLight.bat` in a text editor.
2. Set the host and optional display name:
   ```bat
   set "HOSTNAME=192.168.1.2"
   set "NAME=Web Server"
   ```
   Leave `NAME` empty to display the hostname instead.
3. Double-click `Start-PingLight.bat` to launch the widget.

`Start-PingLight.bat` launches the widget through `launch-hidden.vbs`, which
starts PowerShell with no visible window. Keep `launch-hidden.vbs` and
`PingLight.ps1` in the same folder as the `.bat` file.

To run it directly from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -STA -File PingLight.ps1 -HostName server01 -Name "Web Server"
```

## Running multiple widgets

- **Ad hoc:** launch one widget, then click the label and edit it as needed.
- **Persistent:** copy `Start-PingLight.bat` (for example
  `Start-Server01.bat`, `Start-Router.bat`), set a different `HOSTNAME` in each,
  and launch them. They snap together into a single status panel.

## Resizing

The whole widget — circle and label — scales together, between 0.5× and 3×.

- **Ctrl + mouse wheel** over the widget to resize it live.
- **Right-click → Bigger / Smaller / Reset size**.
- **`-Scale` parameter** to set the initial size, for example:
  ```bat
  start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0PingLight.ps1" -HostName "%HOSTNAME%" -Name "%NAME%" -Scale "1.5"
  ```

## Configuration

Options are exposed as parameters on `PingLight.ps1`:

| Setting | Parameter / Location | Default |
|---------|----------------------|---------|
| Host to ping | `-HostName` | `google.com` |
| Display label | `-Name` | Hostname |
| Ping interval | `-IntervalSeconds` | 2 seconds |
| Ping timeout | `-TimeoutMs` | 1000 ms |
| Initial scale | `-Scale` | 1.0 |
| Snap distance | `$script:snap` | 25 px |

## Logging and troubleshooting

Each widget writes to a log file named `PingLight_<host>.log` in a `logs`
folder next to the script (falling back to `%TEMP%` if that folder cannot be
created).

If the widget disappears, the end of the log indicates the cause:

- Ends with `Window closed.` / `Widget stopped.` — closed intentionally.
- Ends with an `ERROR` or `FATAL` entry — an application error occurred.
- Stops abruptly with no closing entry — the process was terminated externally
  (for example by security software, group policy, or system sleep).

## Frequently asked questions

**Does it require administrator rights?**
No. It uses the managed .NET ping API, which does not require elevation.

**The circle is red but the host is reachable.**
Some hosts and firewalls block ICMP (ping) traffic. The status reflects only
whether a ping reply was received.

**Another window still covered the widget.**
The widget re-asserts itself above normal windows automatically. A true
exclusive full-screen application (such as some games or full-screen video)
can still cover any always-on-top window; this is a Windows limitation.

## License

Provided as-is. You are free to use and modify it.
