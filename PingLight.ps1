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
    [int]$TimeoutMs = 1000
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

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
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
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
$hostBox.Text = $script:label
$hostBox.ToolTip = "Pinging: $($script:hostname)"

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
    if (-not (Test-InHost $_.OriginalSource)) {
        $window.DragMove()
        Invoke-Snap
    }
})

# --- Right-click menu to close -------------------------------------------
$menu = New-Object System.Windows.Controls.ContextMenu
$closeItem = New-Object System.Windows.Controls.MenuItem
$closeItem.Header = "Close"
$closeItem.Add_Click({ $window.Close() })
$menu.Items.Add($closeItem) | Out-Null
$window.ContextMenu = $menu

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
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($IntervalSeconds)
$timer.Add_Tick($tick)

Set-Light 'checking'
$timer.Start()

$window.ShowDialog() | Out-Null
$timer.Stop()
