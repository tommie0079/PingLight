<#
    PingLight - a tiny always-on-top desktop widget.

    Shows a colored circle with a hostname underneath:
        green  = host replied to ping
        red    = no reply
        grey   = checking / first ping pending

    You can edit the display name directly in the widget: click the text,
    type a new name, and press Enter. The name is just a label; it does not
    change which host is pinged.

    Move it:   click-and-drag the circle.
    Close it:  right-click -> Close.

    Run it with a hostname (and optional friendly name):
        powershell -ExecutionPolicy Bypass -STA -File PingLight.ps1 -HostName server01 -Name "Web Server"
#>

param(
    [string]$HostName = "google.com",
    [string]$Name = "",
    [int]$IntervalSeconds = 2,
    [int]$TimeoutMs = 1000,
    [double]$Scale = 1.0
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# --- Logging --------------------------------------------------------------
# Log lands next to the script in a 'logs' folder (falls back to %TEMP%).
# One file per host so multiple widgets don't clobber each other.
$script:logDir = Join-Path $PSScriptRoot 'logs'
try {
    if (-not (Test-Path $script:logDir)) { New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null }
} catch { $script:logDir = $env:TEMP }
$script:safeHost = ($HostName -replace '[^\w\.\-]', '_')
$script:logFile  = Join-Path $script:logDir ("PingLight_{0}.log" -f $script:safeHost)

function Write-Log([string]$msg, [string]$level = 'INFO') {
    try {
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $level, $msg
        Add-Content -LiteralPath $script:logFile -Value $line -Encoding UTF8
    } catch { }
}

Write-Log ("Widget starting. Host='{0}' Name='{1}' PID={2}" -f $HostName, $Name, $PID)

# Catch anything that escapes the AppDomain (last-resort crash record).
try {
    [AppDomain]::CurrentDomain.add_UnhandledException({
        param($s, $e)
        Write-Log ("AppDomain unhandled exception: " + $e.ExceptionObject) 'FATAL'
    })
} catch { }

# Win32 helper: find sibling widget windows (same title) and their pixel bounds.
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class Win32Snap {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    // Force a window into the topmost band without moving, resizing, or activating it.
    static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010;
    public static void ForceTopMost(IntPtr hWnd) {
        SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE);
    }

    public static List<RECT> FindByTitle(string title, IntPtr exclude) {
        var list = new List<RECT>();
        EnumWindows((h, l) => {
            if (h == exclude || !IsWindowVisible(h)) return true;
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (sb.ToString() == title) { RECT r; if (GetWindowRect(h, out r)) list.Add(r); }
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

# --- Shared state ---------------------------------------------------------
$script:hostname  = $HostName
$script:label     = if ($Name.Trim() -ne '') { $Name.Trim() } else { $HostName }
$script:timeoutMs = $TimeoutMs
$script:ping      = New-Object System.Net.NetworkInformation.Ping
$script:task      = $null
$script:winTitle  = 'PingLightWidget'
$script:snap      = 25   # snap distance in DIPs

# --- Build the window from XAML ------------------------------------------
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PingLightWidget"
        Topmost="True"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        SizeToContent="WidthAndHeight"
        WindowStartupLocation="CenterScreen">
    <Border CornerRadius="14" Background="#DD1E1E1E" Padding="14">
        <Border.LayoutTransform>
            <ScaleTransform x:Name="Scaler" ScaleX="1" ScaleY="1"/>
        </Border.LayoutTransform>
        <StackPanel>
            <Ellipse x:Name="Circle" Width="64" Height="64"
                     Fill="#AAAAAA" Stroke="#33FFFFFF" StrokeThickness="1"
                     HorizontalAlignment="Center"/>
            <TextBox x:Name="HostBox"
                     Background="Transparent" Foreground="White"
                     BorderThickness="0" TextAlignment="Center"
                     FontSize="13" Width="150" Margin="0,10,0,0"
                     CaretBrush="White"/>
        </StackPanel>
    </Border>
</Window>
"@

$reader  = New-Object System.Xml.XmlNodeReader $xaml
$window  = [Windows.Markup.XamlReader]::Load($reader)
$circle  = $window.FindName('Circle')
$hostBox = $window.FindName('HostBox')
$scaler  = $window.FindName('Scaler')
$hostBox.Text = $script:label
$hostBox.ToolTip = "Pinging: $($script:hostname)"

# --- Scaling (make the whole widget smaller/bigger) -----------------------
# The ScaleTransform sits on the root Border, so the circle AND the text
# scale together and the window resizes to fit.
$script:scaleMin = 0.5
$script:scaleMax = 3.0
$script:scale    = 1.0

function Set-Scale([double]$value) {
    $v = [math]::Round([math]::Max($script:scaleMin, [math]::Min($script:scaleMax, $value)), 2)
    $script:scale = $v
    $scaler.ScaleX = $v
    $scaler.ScaleY = $v
}

Set-Scale $Scale

# --- Colors ---------------------------------------------------------------
$brushUp       = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(46, 204, 64))
$brushDown     = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(255, 65, 54))
$brushChecking = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(170, 170, 170))

function Set-Light([string]$state) {
    switch ($state) {
        'up'   { $circle.Fill = $brushUp }
        'down' { $circle.Fill = $brushDown }
        default { $circle.Fill = $brushChecking }
    }
}

# --- Dragging (but not when clicking the editable hostname) ---------------
function Test-InHost($src) {
    $d = $src
    while ($null -ne $d) {
        if ($d -eq $hostBox) { return $true }
        try { $d = [System.Windows.Media.VisualTreeHelper]::GetParent($d) } catch { break }
    }
    return $false
}

# Snap to screen edges/corners and to other PingLight widgets.
function Invoke-Snap {
    if ($window.ActualWidth -le 0) { return }
    $handle = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle

    $src = [System.Windows.PresentationSource]::FromVisual($window)
    $dpi = if ($src) { $src.CompositionTarget.TransformToDevice.M11 } else { 1.0 }
    if ($dpi -le 0) { $dpi = 1.0 }

    $w = $window.ActualWidth
    $h = $window.ActualHeight
    $left = $window.Left
    $top  = $window.Top

    # Screen edges (convert working area from pixels to DIPs).
    $wa = [System.Windows.Forms.Screen]::FromHandle($handle).WorkingArea
    $sL = $wa.Left / $dpi; $sT = $wa.Top / $dpi
    $sR = $wa.Right / $dpi; $sB = $wa.Bottom / $dpi

    if ([math]::Abs($left - $sL) -lt $script:snap) { $left = $sL }
    elseif ([math]::Abs(($left + $w) - $sR) -lt $script:snap) { $left = $sR - $w }
    if ([math]::Abs($top - $sT) -lt $script:snap) { $top = $sT }
    elseif ([math]::Abs(($top + $h) - $sB) -lt $script:snap) { $top = $sB - $h }

    # Other widgets.
    foreach ($r in [Win32Snap]::FindByTitle($script:winTitle, $handle)) {
        $oL = $r.Left / $dpi; $oT = $r.Top / $dpi
        $oR = $r.Right / $dpi; $oB = $r.Bottom / $dpi

        $overlapX = ($left -lt $oR) -and (($left + $w) -gt $oL)
        if ($overlapX) {
            if ([math]::Abs($top - $oB) -lt $script:snap) { $top = $oB }
            elseif ([math]::Abs(($top + $h) - $oT) -lt $script:snap) { $top = $oT - $h }
        }
        $overlapY = ($top -lt $oB) -and (($top + $h) -gt $oT)
        if ($overlapY) {
            if ([math]::Abs($left - $oR) -lt $script:snap) { $left = $oR }
            elseif ([math]::Abs(($left + $w) - $oL) -lt $script:snap) { $left = $oL - $w }
        }
        # Align adjacent edges neatly.
        if ([math]::Abs($left - $oL) -lt $script:snap) { $left = $oL }
        if ([math]::Abs($top - $oT) -lt $script:snap) { $top = $oT }
    }

    $window.Left = $left
    $window.Top  = $top
}

$window.Add_MouseLeftButtonDown({
    try {
        if (-not (Test-InHost $_.OriginalSource)) {
            $window.DragMove()
            Invoke-Snap
        }
    } catch {
        Write-Log ("Drag/snap error: " + $_.Exception.Message) 'ERROR'
    }
})

# --- Right-click menu to close -------------------------------------------
$menu = New-Object System.Windows.Controls.ContextMenu

$biggerItem = New-Object System.Windows.Controls.MenuItem
$biggerItem.Header = "Bigger"
$biggerItem.Add_Click({ Set-Scale ($script:scale + 0.1) })
$menu.Items.Add($biggerItem) | Out-Null

$smallerItem = New-Object System.Windows.Controls.MenuItem
$smallerItem.Header = "Smaller"
$smallerItem.Add_Click({ Set-Scale ($script:scale - 0.1) })
$menu.Items.Add($smallerItem) | Out-Null

$resetItem = New-Object System.Windows.Controls.MenuItem
$resetItem.Header = "Reset size"
$resetItem.Add_Click({ Set-Scale 1.0 })
$menu.Items.Add($resetItem) | Out-Null

$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

$closeItem = New-Object System.Windows.Controls.MenuItem
$closeItem.Header = "Close"
$closeItem.Add_Click({ $window.Close() })
$menu.Items.Add($closeItem) | Out-Null
$window.ContextMenu = $menu

# --- Ctrl + mouse wheel to resize live ------------------------------------
$window.Add_PreviewMouseWheel({
    try {
        if ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control) {
            $step = if ($_.Delta -gt 0) { 0.1 } else { -0.1 }
            Set-Scale ($script:scale + $step)
            $_.Handled = $true
        }
    } catch {
        Write-Log ("Resize error: " + $_.Exception.Message) 'ERROR'
    }
})

# --- Keep the widget above other windows ---------------------------------
# WPF's Topmost can be overtaken when another app opens (e.g. Paint). We push
# the window back into the topmost band with the Win32 SetWindowPos API, and
# defer it so it runs AFTER the other window has finished appearing.
function Set-TopMost {
    try {
        $h = (New-Object System.Windows.Interop.WindowInteropHelper $window).Handle
        if ($h -ne [IntPtr]::Zero) {
            $window.Topmost = $true
            [Win32Snap]::ForceTopMost($h)
        }
    } catch {
        Write-Log ("Topmost reassert error: " + $_.Exception.Message) 'ERROR'
    }
}

$window.Add_Deactivated({
    # Defer until the app is idle so the newly opened window is already shown.
    $window.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
        [action]{ Set-TopMost }
    ) | Out-Null
})

# --- Commit display-name edits --------------------------------------------
$commit = {
    $new = $hostBox.Text.Trim()
    if ($new -ne '' -and $new -ne $script:label) {
        $script:label = $new
    }
    $hostBox.Text = $script:label
}

$hostBox.Add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Return) {
        & $commit
        $window.Focus() | Out-Null
        $_.Handled = $true
    }
})
$hostBox.Add_LostFocus($commit)

# --- Ping loop (non-blocking) --------------------------------------------
$tick = {
    try {
        # Safety net: some apps steal the front without deactivating us.
        Set-TopMost

        if ($null -ne $script:task -and $script:task.IsCompleted) {
            $up = $false
            if (-not $script:task.IsFaulted -and -not $script:task.IsCanceled) {
                try {
                    if ($script:task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $up = $true }
                } catch {}
            }
            if ($up) { Set-Light 'up' } else { Set-Light 'down' }
            $script:task = $null
        }

        if ($null -eq $script:task) {
            try { $script:task = $script:ping.SendPingAsync($script:hostname, $script:timeoutMs) }
            catch { Set-Light 'down'; $script:task = $null }
        }
    } catch {
        # A transient error here must never tear down the window.
        Write-Log ("Ping tick error: " + $_.Exception.Message) 'ERROR'
        try { Set-Light 'down' } catch {}
        $script:task = $null
    }
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($IntervalSeconds)
$timer.Add_Tick($tick)

Set-Light 'checking'
$timer.Start()

# Keep the widget alive if an unhandled exception reaches the UI dispatcher;
# log it instead of letting WPF close the window.
$window.Dispatcher.Add_UnhandledException({
    param($s, $e)
    Write-Log ("Dispatcher unhandled exception: " + $e.Exception.Message + " | " + $e.Exception.StackTrace) 'FATAL'
    $e.Handled = $true
})

$window.Add_Closed({ Write-Log 'Window closed.' })

try {
    $window.ShowDialog() | Out-Null
} catch {
    Write-Log ("ShowDialog failed: " + $_.Exception.Message) 'FATAL'
}
$timer.Stop()
Write-Log 'Widget stopped.'
