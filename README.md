# 🟢🔴 PingLight

A tiny desktop widget that stares at a host and judges it silently.

Green circle = "we're friends, it answered my ping." 🟢
Red circle = "it's ghosting me." 🔴
Grey circle = "hang on, I'm thinking..." ⚪

That's it. That's the app.

![It's a circle. With feelings.](https://img.shields.io/badge/dependencies-absolutely%20none-brightgreen) ![Made with](https://img.shields.io/badge/made%20with-PowerShell%20%26%20spite-blue)

## Why does this exist?

Because opening a terminal and typing `ping server01 -t` like a caveman is *so* 1998. Now you get a floating circle that lives on top of everything and never lets you forget that the printer is offline again.

## Features

- 🟢 **Always on top** — it will not be ignored.
- ✏️ **Editable hostname** — click the text, type, press Enter. It re-pings instantly.
- 🧲 **Snaps to screen edges & corners** — for the tidy people.
- 🧲 **Snaps to other PingLights** — build a little wall of judgment.
- 🖱️ **Drag it anywhere** — click the circle and fling it around.
- ❌ **Right-click → Close** — when you can't handle the truth anymore.
- 📦 **Zero dependencies** — no Python, no Node, no 400MB Electron sadness. Just Windows being Windows.

## Requirements

- Windows.
- ...that's it. It uses the PowerShell and WPF that are already sitting on your machine gathering dust.

## Usage

1. Open `Start-PingLight.bat` in Notepad.
2. Change this line to whatever you want to monitor:
   ```bat
   set "HOSTNAME=google.com"
   ```
3. Double-click `Start-PingLight.bat`.
4. Enjoy your new emotionally expressive circle.

Prefer the command line? Sure, show-off:

```powershell
powershell -ExecutionPolicy Bypass -STA -File PingLight.ps1 -HostName server01
```

## Running several

You wanted many. You can have many.

- **The lazy way:** launch one, then click the hostname and edit it. Repeat.
- **The organized way:** copy `Start-PingLight.bat` a few times (`Start-Server01.bat`, `Start-Router.bat`, `Start-ThatOnePrinter.bat`), set a different `HOSTNAME` in each, and double-click them all. They'll snap together into a neat little status bar of doom.

## Tweaking

Everything lives in `PingLight.ps1`:

| What | Where | Default |
|------|-------|---------|
| Ping interval | `-IntervalSeconds` | 2 seconds |
| Ping timeout | `-TimeoutMs` | 1000 ms |
| Snap distance | `$script:snap` | 25 px |
| Circle size | `Ellipse Width/Height` in the XAML | 64 |

## FAQ

**Q: Does it need admin rights?**
A: Nope. It pings using the polite .NET method, not the raw-socket "I am root now" method.

**Q: It says red but the server is fine!**
A: Some hosts block ICMP (ping) on purpose. The circle only knows what the ping tells it. Don't shoot the messenger circle.

**Q: Can I make it green permanently to fool my boss?**
A: This README does not condone that. (Line 3 of the ping loop, but you didn't hear it from me.)

## License

Do whatever you want with it. If it saves your day, a green circle salutes you. 🟢
