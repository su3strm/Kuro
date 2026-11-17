# Kuro installer - installs Kuro for this Windows user, adds Desktop and Start menu shortcuts and an
# entry in Settings > Apps, then starts Kuro. Run it through "Launch Kuro.bat".
#   -Uninstall   removes the shortcuts, the Apps entry and the installed files (asks first)
# Kuro's own settings, licence and tweak backups live in C:\ProgramData\Kuro and are never touched here,
# so reinstalling brings everything back and "Restore everything" still works.
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$Src     = $PSScriptRoot
$Dst     = Join-Path $env:LOCALAPPDATA 'Programs\Kuro'
$RegKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Kuro'
$Pink    = '#E86A9C'
$Desktop = [Environment]::GetFolderPath('Desktop')
$Menu    = Join-Path ([Environment]::GetFolderPath('Programs')) 'Kuro.lnk'
$KuroArgs = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "{0}"'

function Start-Kuro([string]$Dir) {
    Start-Process -FilePath 'powershell.exe' -ArgumentList ($KuroArgs -f (Join-Path $Dir 'Kuro.ps1')) -WorkingDirectory $Dir -WindowStyle Hidden
}

# already running from the installed copy: nothing to install
if (-not $Uninstall -and $Src.TrimEnd('\') -ieq $Dst.TrimEnd('\')) { Start-Kuro $Dst; return }

# ------------------------------------------------------------------ window (Hone-style: black, mark, wordmark, thin bar)
$img = { param($p) if (Test-Path -LiteralPath $p) { $p } else { '' } }
$icon = & $img (Join-Path $Src 'assets\Kuro.png')
$mark = & $img (Join-Path $Src 'assets\kuro-mark.png')
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kuro Installer" Width="480" Height="300" WindowStyle="None" ResizeMode="NoResize"
        WindowStartupLocation="CenterScreen" Background="#0B0B0F" ShowInTaskbar="True" FontFamily="Segoe UI">
  <Border BorderBrush="#24242C" BorderThickness="1">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="34"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="44"/></Grid.RowDefinitions>
      <!-- title bar -->
      <Grid x:Name="TitleBar" Background="#0B0B0F">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="12,0,0,0">
          <Image x:Name="TitleIcon" Width="16" Height="16" Margin="0,0,8,0" RenderOptions.BitmapScalingMode="HighQuality"/>
          <TextBlock x:Name="TitleText" Text="Kuro Installer" Foreground="#B9B9C6" FontSize="12" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
      <!-- centre: heading, mark, wordmark -->
      <StackPanel Grid.Row="1" VerticalAlignment="Center" HorizontalAlignment="Center" Margin="0,-6,0,0">
        <TextBlock x:Name="Heading" Text="Installing Kuro" Foreground="#E8E8F0" FontSize="14" HorizontalAlignment="Center" Margin="0,0,0,14"/>
        <Grid HorizontalAlignment="Center">
          <Ellipse x:Name="Glow" Width="96" Height="96" Opacity="0.0">
            <Ellipse.Fill><RadialGradientBrush><GradientStop Color="#66E86A9C" Offset="0"/><GradientStop Color="#00E86A9C" Offset="1"/></RadialGradientBrush></Ellipse.Fill>
          </Ellipse>
          <Image x:Name="Mark" Width="68" Height="68" RenderOptions.BitmapScalingMode="HighQuality" RenderTransformOrigin="0.5,0.5">
            <Image.RenderTransform><ScaleTransform x:Name="MarkScale" ScaleX="1" ScaleY="1"/></Image.RenderTransform>
          </Image>
        </Grid>
        <TextBlock Text="KURO" Foreground="White" FontSize="34" FontWeight="Black" HorizontalAlignment="Center" Margin="0,8,0,0"/>
      </StackPanel>
      <!-- progress bar -->
      <Grid Grid.Row="2" Margin="0,0,0,0" Height="3">
        <Border Background="#1A1A21"/>
        <Border x:Name="Fill" Background="$Pink" HorizontalAlignment="Left" Width="0"/>
      </Grid>
      <!-- footer -->
      <Grid Grid.Row="3" Margin="16,0,16,0">
        <TextBlock x:Name="Status" Text="Getting ready..." Foreground="#8E8E9C" FontSize="12" VerticalAlignment="Center"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <TextBlock x:Name="BtnGo" Text="Uninstall" Foreground="$Pink" FontSize="12" Cursor="Hand" Margin="0,0,18,0" Visibility="Collapsed"/>
          <TextBlock x:Name="BtnCancel" Text="Cancel" Foreground="#8E8E9C" FontSize="12" Cursor="Hand"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'TitleBar', 'TitleIcon', 'TitleText', 'Heading', 'Glow', 'Mark', 'MarkScale', 'Fill', 'Status', 'BtnGo', 'BtnCancel') { $ui[$n] = $win.FindName($n) }
foreach ($p in @(@($ui.TitleIcon, $icon), @($ui.Mark, $mark))) {
    if ($p[1]) { try { $b = New-Object Windows.Media.Imaging.BitmapImage; $b.BeginInit(); $b.UriSource = New-Object Uri $p[1]; $b.CacheOption = 'OnLoad'; $b.EndInit(); $p[0].Source = $b } catch { } }
}
try { $win.Icon = New-Object Windows.Media.Imaging.BitmapImage (New-Object Uri (Join-Path $Src 'assets\Kuro.ico')) } catch { }
$ui.TitleBar.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
foreach ($b in @($ui.BtnCancel, $ui.BtnGo)) {
    $b.Add_MouseEnter({ $this.Tag = $this.Foreground; $this.Foreground = [Windows.Media.Brushes]::White })
    $b.Add_MouseLeave({ if ($this.Tag) { $this.Foreground = $this.Tag } })
}

# gentle "breathing" pulse on the mark while working
$pulse = New-Object Windows.Media.Animation.DoubleAnimation 1.0, 1.06, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(900)))
$pulse.AutoReverse = $true; $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
$pulse.EasingFunction = New-Object Windows.Media.Animation.SineEase
$glow = New-Object Windows.Media.Animation.DoubleAnimation 0.25, 0.9, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(900)))
$glow.AutoReverse = $true; $glow.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever

$State = @{ Cancel = $false; Busy = $false; Pct = 0.0 }
function Pump { try { $win.Dispatcher.Invoke([Action] { }, [Windows.Threading.DispatcherPriority]::Background) } catch { } }
function Set-Progress([double]$Pct, [string]$Text) {
    $State.Pct = [math]::Max($State.Pct, [math]::Min(100.0, $Pct))
    $w = ($win.ActualWidth - 2) * $State.Pct / 100.0
    $a = New-Object Windows.Media.Animation.DoubleAnimation $w, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(260)))
    $a.EasingFunction = New-Object Windows.Media.Animation.QuadraticEase
    $ui.Fill.BeginAnimation([Windows.FrameworkElement]::WidthProperty, $a)
    if ($Text) { $ui.Status.Text = $Text }
    Pump
}
function Start-Pulse { $ui.MarkScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $pulse); $ui.MarkScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $pulse); $ui.Glow.BeginAnimation([Windows.UIElement]::OpacityProperty, $glow) }
function Stop-Pulse { $ui.MarkScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $ui.MarkScale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, $null); $ui.Glow.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $ui.Glow.Opacity = 0.6 }
function Close-Later([int]$Ms) {
    $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds($Ms)
    $t.Add_Tick({ $this.Stop(); $win.Close() }); $t.Start()
}

function New-Shortcut([string]$Path, [string]$Dir) {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($Path)
    $l.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $l.Arguments = $KuroArgs -f (Join-Path $Dir 'Kuro.ps1')
    $l.WorkingDirectory = $Dir
    $l.IconLocation = (Join-Path $Dir 'assets\Kuro.ico') + ',0'
    $l.Description = 'Kuro FPS optimizer'
    $l.WindowStyle = 7   # minimised: no console flash
    $l.Save()
}

# ------------------------------------------------------------------ install
function Invoke-Install {
    $State.Busy = $true
    $fresh = -not (Test-Path -LiteralPath (Join-Path $Dst 'Kuro.ps1'))
    # an update over an existing install cannot be stopped half-way, so Cancel only shows on a fresh install
    if (-not $fresh) { $ui.Heading.Text = 'Updating Kuro'; $ui.BtnCancel.Visibility = 'Collapsed' }
    Start-Pulse
    try {
        Set-Progress 3 'Getting ready...'
        if (-not (Test-Path -LiteralPath (Join-Path $Src 'Kuro.ps1'))) { throw 'Kuro.ps1 is missing next to the installer. Extract the whole zip first.' }
        $files = @(Get-ChildItem -LiteralPath $Src -Recurse -File -Force | Where-Object { $_.Name -notlike '*.kuroupd' })
        $total = [double](($files | Measure-Object Length -Sum).Sum); if ($total -le 0) { $total = 1 }
        [void](New-Item -ItemType Directory -Path $Dst -Force)
        $done = 0.0; $i = 0
        foreach ($f in $files) {
            if ($State.Cancel) { throw 'cancelled' }
            $rel = $f.FullName.Substring($Src.TrimEnd('\').Length).TrimStart('\')
            $to = Join-Path $Dst $rel
            $dir = Split-Path -Parent $to
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            Copy-Item -LiteralPath $f.FullName -Destination $to -Force
            $done += $f.Length; $i++
            if ($i % 3 -eq 0 -or $i -eq $files.Count) { Set-Progress (5 + 75 * $done / $total) ("Installing...  {0}/{1} files" -f $i, $files.Count) }
        }
        if ($State.Cancel) { throw 'cancelled' }
        Set-Progress 84 'Unblocking files...'
        Get-ChildItem -LiteralPath $Dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        Set-Progress 90 'Adding shortcuts...'
        New-Shortcut (Join-Path $Desktop 'Kuro.lnk') $Dst
        New-Shortcut $Menu $Dst
        Set-Progress 95 'Registering Kuro...'
        $ver = ''; try { $ver = [string]((Get-Content -LiteralPath (Join-Path $Dst 'manifest.json') -Raw | ConvertFrom-Json).version) } catch { }
        $kb = [int]([math]::Ceiling($total / 1024))
        [void](New-Item -Path $RegKey -Force)
        $vals = [ordered]@{
            DisplayName = 'Kuro'; DisplayVersion = $ver; Publisher = 'Kuro'; DisplayIcon = (Join-Path $Dst 'assets\Kuro.ico')
            InstallLocation = $Dst; URLInfoAbout = 'https://github.com/su3strm/Kuro'
            UninstallString = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Uninstall' -f (Join-Path $Dst 'Install-Kuro.ps1'))
        }
        foreach ($k in $vals.Keys) { Set-ItemProperty -Path $RegKey -Name $k -Value $vals[$k] }
        foreach ($k in 'NoModify', 'NoRepair') { New-ItemProperty -Path $RegKey -Name $k -Value 1 -PropertyType DWord -Force | Out-Null }
        New-ItemProperty -Path $RegKey -Name 'EstimatedSize' -Value $kb -PropertyType DWord -Force | Out-Null
        Set-Progress 100 'Installed. Starting Kuro...'
        Stop-Pulse
        $ui.Heading.Text = $(if ($fresh) { 'Kuro is installed' } else { 'Kuro is up to date' })
        $ui.BtnCancel.Visibility = 'Collapsed'
        Start-Kuro $Dst
        Close-Later 1400
    } catch {
        Stop-Pulse
        $msg = $_.Exception.Message
        if ($msg -eq 'cancelled') {
            if ($fresh) { try { Remove-Item -LiteralPath $Dst -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
            $win.Close(); return
        }
        $ui.Heading.Text = 'Could not install Kuro'
        $ui.Status.Text = 'Starting Kuro from this folder instead...'
        $ui.Fill.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#FF5A6A'))
        try { [IO.File]::AppendAllText((Join-Path $env:TEMP 'kuro-install.log'), ("[{0}] {1}`r`n" -f (Get-Date -Format s), $msg)) } catch { }
        Start-Kuro $Src
        Close-Later 2600
    } finally { $State.Busy = $false }
}

# ------------------------------------------------------------------ uninstall
function Invoke-Uninstall {
    $State.Busy = $true
    $ui.BtnGo.Visibility = 'Collapsed'; $ui.BtnCancel.Visibility = 'Collapsed'
    $ui.Heading.Text = 'Uninstalling Kuro'
    Start-Pulse
    try {
        Get-Process powershell, Kuro -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID -and $_.Path -and ($_.MainWindowTitle -like 'Kuro*') } | ForEach-Object { try { $_.CloseMainWindow() | Out-Null } catch { } }
        Set-Progress 25 'Removing shortcuts...'
        foreach ($p in @((Join-Path $Desktop 'Kuro.lnk'), $Menu)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
        Set-Progress 55 'Removing Kuro from Apps...'
        if (Test-Path $RegKey) { Remove-Item -Path $RegKey -Recurse -Force }
        Set-Progress 85 'Removing files...'
        # this script lives in the folder being removed, so a tiny helper deletes it after the window closes
        $cmd = 'ping 127.0.0.1 -n 6 >nul & rmdir /s /q "{0}"' -f $Dst
        Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmd) -WindowStyle Hidden
        Set-Progress 100 'Kuro has been removed.'
        Stop-Pulse
        $ui.Heading.Text = 'Kuro is uninstalled'
        Close-Later 1600
    } catch {
        Stop-Pulse
        $ui.Heading.Text = 'Could not uninstall Kuro'
        $ui.Status.Text = $_.Exception.Message
        $ui.BtnCancel.Text = 'Close'; $ui.BtnCancel.Visibility = 'Visible'
    } finally { $State.Busy = $false }
}

$ui.BtnCancel.Add_MouseLeftButtonUp({
    if ($State.Busy) { $State.Cancel = $true; $ui.Status.Text = 'Cancelling...' } else { $win.Close() }
})
$ui.BtnGo.Add_MouseLeftButtonUp({ Invoke-Uninstall })

if ($Uninstall) {
    $win.Title = 'Uninstall Kuro'
    $ui.Heading.Text = 'Uninstall Kuro?'
    $ui.Status.Text = 'Your Windows tweaks stay. Undo them first in Kuro > Settings > Restore everything.'
    $ui.Status.TextWrapping = 'Wrap'; $ui.Status.Margin = '0,0,150,0'
    $ui.BtnGo.Visibility = 'Visible'
} else {
    $win.Add_ContentRendered({
        $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromMilliseconds(350)
        $t.Add_Tick({ $this.Stop(); Invoke-Install }); $t.Start()
    })
}
[void]$win.ShowDialog()
