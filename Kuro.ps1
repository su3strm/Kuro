<#
    Kuro - FPS optimizer for Windows 10/11
    Version 1.0.0

    Run "Launch Kuro.bat" (or the compiled Kuro.exe). Administrator rights are required
    because most optimizations write to HKLM, services and power settings.

    Every change is backed up to %ProgramData%\Kuro\backup.json and can be switched off again.
#>

$Global:CCH_Debug = ($env:CCH_DEBUG -eq '1') -or (@($args) -contains '-debug')
if ($Global:CCH_Debug) { $ErrorActionPreference = 'Continue' } else { $ErrorActionPreference = 'SilentlyContinue' }
$ProgressPreference    = 'SilentlyContinue'
Set-StrictMode -Off

$Global:CCH_Version = '2.9.5'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms

function Show-Fatal([string]$Title, $Err) {
    $msg = [string]$Err
    try {
        if ($Err -is [System.Management.Automation.ErrorRecord]) {
            $msg = $Err.Exception.Message
            if ($Err.Exception.InnerException) { $msg += "`n`nDetails: " + $Err.Exception.InnerException.Message }
            if ($Err.InvocationInfo) { $msg += "`n`nScript line: " + $Err.InvocationInfo.ScriptLineNumber + "`n" + ([string]$Err.InvocationInfo.Line).Trim() }
        }
    } catch { }
    try {
        $dir = Join-Path $env:ProgramData 'Kuro'
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $f = Join-Path $dir 'error.txt'
        [IO.File]::AppendAllText($f, ('[' + (Get-Date -Format 's') + '] ' + $Title + "`r`n" + $msg + "`r`n" + [string]$Err.ScriptStackTrace + "`r`n`r`n"))
        $msg += "`n`nSaved to: " + $f
    } catch { }
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Kuro - ' + $Title, 'OK', 'Error')
}

# ------------------------------------------------------------------ elevation + STA
$cchIsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$cchScript  = $PSCommandPath
if (-not $cchScript) { $cchScript = $MyInvocation.MyCommand.Path }
$cchIsExe   = (-not $cchScript) -or ($cchScript -notlike '*.ps1')

if (-not $cchIsAdmin -or ([Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA')) {
    try {
        if ($cchIsExe) {
            $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            Start-Process -FilePath $exe -Verb RunAs -ErrorAction Stop | Out-Null
        } elseif ($Global:CCH_Debug) {
            $argLine = '-NoProfile -ExecutionPolicy Bypass -STA -NoExit -File "' + $cchScript + '" -debug'
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs -ErrorAction Stop | Out-Null
        } else {
            $argLine = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $cchScript + '"'
            Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs -ErrorAction Stop | Out-Null
        }
    } catch {
        Show-Fatal 'Administrator permission needed' 'Kuro needs administrator permission to change registry, service and power settings. Run it again and click Yes on the Windows prompt.'
    }
    exit
}

if ($PSScriptRoot) { $Global:AppDir = $PSScriptRoot }
else { $Global:AppDir = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
# Owner's default auto-update source (raw GitHub folder). Users can override it in Settings.
$Global:DefaultUpdateUrl = 'https://raw.githubusercontent.com/su3strm/Kuro/main'
# Owner's license / account / live-stats server (Cloudflare Worker URL). Users can override it in Settings.
$Global:DefaultLicenseServer = ''
# Kuro Discord bot address (data\bot.txt, shipped through auto-update) - used by Premium > Get my Discord role
$Global:DiscordBotUrl = ''
try {
    $botTxt = Join-Path $Global:AppDir 'data\bot.txt'
    if (Test-Path -LiteralPath $botTxt) {
        $bl = ([IO.File]::ReadAllText($botTxt)).Trim().TrimEnd('/')
        if ($bl -match '^https://[A-Za-z0-9.-]+$') { $Global:DiscordBotUrl = $bl }
    }
} catch { }
# The owner's setup script writes the server address into data\server.txt and it reaches every copy
# through auto-update, so no rebuild is needed to connect existing copies.
try {
    $srvTxt = Join-Path $Global:AppDir 'data\server.txt'
    if (-not $Global:DefaultLicenseServer -and (Test-Path -LiteralPath $srvTxt)) {
        $line = ([IO.File]::ReadAllText($srvTxt)).Trim().TrimEnd('/')
        if ($line -match '^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._~/-]*)?$') { $Global:DefaultLicenseServer = $line }
    }
} catch { }
$Global:CchIsExe = $cchIsExe
# A Kuro.exe holds a frozen copy of the script, which updates cannot change. If the newer Kuro.ps1
# sits next to it, hand over to that so exe users get every update too.
if ($cchIsExe) {
    $handoff = Join-Path $Global:AppDir 'Kuro.ps1'
    if (Test-Path -LiteralPath $handoff) {
        try {
            Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $handoff + '"') -ErrorAction Stop | Out-Null
            exit
        } catch { }
    }
}
$Global:CchScriptPath = $cchScript

# Apply any update files downloaded in a previous session, before anything loads them (avoids file locks).
try {
    foreach ($u in @(Get-ChildItem -Path $Global:AppDir -Recurse -Filter '*.kuroupd' -File -ErrorAction SilentlyContinue)) {
        $target = $u.FullName.Substring(0, $u.FullName.Length - 9)
        try {
            $td = Split-Path -Parent $target
            if (-not (Test-Path $td)) { New-Item -ItemType Directory -Force -Path $td | Out-Null }
            Move-Item -LiteralPath $u.FullName -Destination $target -Force -ErrorAction Stop
        } catch { }
    }
} catch { }

if (-not (Test-Path (Join-Path $Global:AppDir 'assets\Kuro.png'))) {
    Show-Fatal 'Extract the zip first' ("Kuro could not find its 'data' folder next to the app:`n" + $Global:AppDir + "`n`nRight-click the downloaded zip > Extract All..., open the extracted Kuro folder and run 'Launch Kuro.bat' from there.")
    exit
}

if ($Global:CCH_Debug) {
    try { Start-Transcript -Path (Join-Path $env:ProgramData 'Kuro\debug-transcript.txt') -Force | Out-Null } catch { }
    Write-Host "Kuro $Global:CCH_Version DEBUG MODE - errors will be printed here." -ForegroundColor Yellow
}

if (-not ('CchNative' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class CchNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX {
        public uint dwLength; public uint dwMemoryLoad;
        public ulong ullTotalPhys; public ulong ullAvailPhys;
        public ulong ullTotalPageFile; public ulong ullAvailPageFile;
        public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);
    private static MEMORYSTATUSEX Mem() {
        MEMORYSTATUSEX m = new MEMORYSTATUSEX();
        m.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        GlobalMemoryStatusEx(ref m);
        return m;
    }
    public static uint MemoryLoad() { return Mem().dwMemoryLoad; }
    public static ulong TotalPhys() { return Mem().ullTotalPhys; }
    public static ulong AvailPhys() { return Mem().ullAvailPhys; }

    [DllImport("kernel32.dll")]
    private static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    private static long pIdle, pKernel, pUser;
    public static int CpuPercent() {
        long i, k, u;
        if (!GetSystemTimes(out i, out k, out u)) return 0;
        long di = i - pIdle, dk = k - pKernel, du = u - pUser;
        pIdle = i; pKernel = k; pUser = u;
        long total = dk + du;
        if (total <= 0) return 0;
        int v = (int)Math.Round(100.0 * (total - di) / total);
        return v < 0 ? 0 : (v > 100 ? 100 : v);
    }

    [DllImport("psapi.dll")]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);

    [DllImport("powrprof.dll")]
    public static extern uint PowerSetActiveOverlayScheme(Guid overlay);
    [DllImport("powrprof.dll")]
    public static extern uint PowerGetEffectiveOverlayScheme(out Guid overlay);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public static void GameBarRecord() {
        byte WIN = 0x5B, ALT = 0x12, R = 0x52; uint UP = 2;
        keybd_event(WIN, 0, 0, UIntPtr.Zero); keybd_event(ALT, 0, 0, UIntPtr.Zero); keybd_event(R, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(40);
        keybd_event(R, 0, UP, UIntPtr.Zero); keybd_event(ALT, 0, UP, UIntPtr.Zero); keybd_event(WIN, 0, UP, UIntPtr.Zero);
    }

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr h, int cmd);
}
'@
}
# own taskbar identity, so Windows shows the Kuro window icon instead of PowerShell's
try { [void][CchNative]::SetCurrentProcessExplicitAppUserModelID('Kuro.App') } catch { }
if (-not $Global:CCH_Debug) { try { $cw = [CchNative]::GetConsoleWindow(); if ($cw -ne [IntPtr]::Zero) { [void][CchNative]::ShowWindow($cw, 0) } } catch { } }

# ------------------------------------------------------------------ paths, settings, log
$Global:DataDir = Join-Path $env:ProgramData 'Kuro'
if (-not (Test-Path $Global:DataDir)) { New-Item -ItemType Directory -Force -Path $Global:DataDir | Out-Null }
# One-time move of data from the ColaCatHub days (settings, Premium licence, tweak backups) into Kuro's folder.
# Copies only files Kuro does not have yet, so nothing current is overwritten. The old folder is left as it was.
try {
    $legacyDir = Join-Path $env:ProgramData 'ColaCatHub'
    $legacyMark = Join-Path $Global:DataDir 'migrated-from-colacathub.txt'
    if ((Test-Path -LiteralPath $legacyDir) -and -not (Test-Path -LiteralPath $legacyMark)) {
        foreach ($lf in @(Get-ChildItem -LiteralPath $legacyDir -Recurse -File -ErrorAction SilentlyContinue)) {
            $relp = $lf.FullName.Substring($legacyDir.Length).TrimStart('\')
            $dest = Join-Path $Global:DataDir $relp
            if (-not (Test-Path -LiteralPath $dest)) {
                $dd = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $dd)) { New-Item -ItemType Directory -Force -Path $dd | Out-Null }
                Copy-Item -LiteralPath $lf.FullName -Destination $dest -ErrorAction SilentlyContinue
            }
        }
        Set-Content -LiteralPath $legacyMark -Value ('Copied from ' + $legacyDir + ' on ' + (Get-Date -Format s)) -ErrorAction SilentlyContinue
    }
} catch { }
$Global:SettingsFile = Join-Path $Global:DataDir 'settings.json'
$Global:BackupFile   = Join-Path $Global:DataDir 'backup.json'
$Global:LogFile      = Join-Path $Global:DataDir 'colacathub.log'
$Global:Utf8NoBom    = New-Object System.Text.UTF8Encoding($false)

$Global:CCH = @{
    Window   = $null
    Premium  = $false
    Recording = $false
    Tampered = $false
    Scan     = $null
    Tags     = @()
    Appx     = @()
    Backup   = (New-Object System.Collections.ArrayList)
    Filter   = @{
        optim   = @{ Cat = 'All'; Search = ''; RecoOnly = $false }
        debloat = @{ Cat = 'All'; Search = ''; RecoOnly = $false }
    }
    ModalAction = $null
    ModalArg    = $null
    Boost    = @{ On = $false; PrevOverlay = ''; Restart = @(); Boosted = @{} }
    Settings = @{
        Accent        = '#E86A9C'
        Bg            = 'Ink'
        AutoRestore   = $true
        ConfirmRisky  = $true
        LicenseServer = ''
        ShareStats    = $true
        Account       = ''
        UpdateUrl     = ''
        AutoUpdate    = $true
        Macros        = @()
        MacroRobloxOnly = $true
        RestoreDay    = ''
        ShortcutDone  = $false
        VibesArt      = $true
        VibesMusic    = $true
        MusicGamePause = $true
        Volume        = 35
        Track         = 'shuffle'
        Mascot        = 'cola'
        Avatar        = 'kuro'
        VibesFx       = $true
        StartSound    = $true
        RbxStep       = 0
        StreamProof   = $false
        Greet         = $true
        Bedtime       = $true
        GameAuto      = $true
        GameProfiles  = @{}
        CrossShow     = $false
        RbxCursor     = $false
        RbxCursorLock = $false
        DnsBackup     = $null
        SeqExampleDone = $false
        TutorialDone  = $false
        UltimateGuid  = ''
        RobloxEnabled = @()
        Boost         = @{ Power = $true; Kill = $true; Browsers = $false; Priority = $true; Ram = $true; Roblox = $true }
    }
}

function Write-Log([string]$Text) {
    $line = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $Text
    try { [IO.File]::AppendAllText($Global:LogFile, $line + "`r`n", $Global:Utf8NoBom) } catch { }
    try {
        $tb = $Global:UI['ToolsLog']
        if ($tb) { $tb.AppendText($line + "`r`n"); $tb.ScrollToEnd() }
    } catch { }
}

function Load-Settings {
    if (-not (Test-Path $Global:SettingsFile)) { return }
    try {
        $j = [IO.File]::ReadAllText($Global:SettingsFile) | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) {
            if ($p.Name -eq 'Boost') {
                foreach ($b in $p.Value.PSObject.Properties) { $Global:CCH.Settings.Boost[$b.Name] = [bool]$b.Value }
            } elseif ($p.Name -eq 'RobloxEnabled') {
                $Global:CCH.Settings.RobloxEnabled = @($p.Value | Where-Object { $_ })
            } else {
                $Global:CCH.Settings[$p.Name] = $p.Value
            }
        }
    } catch { Write-Log "Settings could not be read: $_" }
}

function Save-Settings {
    try {
        $json = ConvertTo-Json -InputObject $Global:CCH.Settings -Depth 5
        [IO.File]::WriteAllText($Global:SettingsFile, $json, $Global:Utf8NoBom)
    } catch { Write-Log "Settings could not be saved: $_" }
}

# ------------------------------------------------------------------ backup store
function Load-Backup {
    $Global:CCH.Backup.Clear()
    if (-not (Test-Path $Global:BackupFile)) { return }
    try {
        $arr = [IO.File]::ReadAllText($Global:BackupFile) | ConvertFrom-Json
        foreach ($e in @($arr)) { if ($e) { [void]$Global:CCH.Backup.Add($e) } }
    } catch { Write-Log "Backup file could not be read: $_" }
}

function Save-Backup {
    try {
        $json = ConvertTo-Json -InputObject @($Global:CCH.Backup.ToArray()) -Depth 4
        [IO.File]::WriteAllText($Global:BackupFile, $json, $Global:Utf8NoBom)
    } catch { Write-Log "Backup file could not be saved: $_" }
}

function Get-BackupEntry([string]$TweakId, [string]$Kind, [string]$Path, [string]$Name) {
    foreach ($e in $Global:CCH.Backup) {
        if ($e.Tweak -eq $TweakId -and $e.Kind -eq $Kind -and $e.Path -eq $Path -and $e.Name -eq $Name) { return $e }
    }
    return $null
}

function Add-BackupEntry([string]$TweakId, [string]$Kind, [string]$Path, [string]$Name, $Existed, $KeyExisted, [string]$ValKind, [string]$Data) {
    if (Get-BackupEntry $TweakId $Kind $Path $Name) { return }   # keep the very first (true original) value
    $e = [pscustomobject]@{
        Tweak = $TweakId; Kind = $Kind; Path = $Path; Name = $Name
        Existed = [bool]$Existed; KeyExisted = [bool]$KeyExisted; ValKind = $ValKind; Data = $Data
        Date = (Get-Date -Format 's')
    }
    [void]$Global:CCH.Backup.Add($e)
}

function Remove-BackupFor([string]$TweakId) {
    $keep = @($Global:CCH.Backup | Where-Object { $_.Tweak -ne $TweakId })
    $Global:CCH.Backup.Clear()
    foreach ($k in $keep) { [void]$Global:CCH.Backup.Add($k) }
}

function Get-BackupTweakIds { return @($Global:CCH.Backup | ForEach-Object { $_.Tweak } | Select-Object -Unique) }

# ------------------------------------------------------------------ registry engine (64-bit view)
function Get-RegBase([string]$Path) {
    $i = $Path.IndexOf(':\')
    $hive = $Path.Substring(0, $i)
    $sub  = $Path.Substring($i + 2)
    $h = $null
    switch ($hive) {
        'HKLM' { $h = [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCU' { $h = [Microsoft.Win32.RegistryHive]::CurrentUser }
        'HKU'  { $h = [Microsoft.Win32.RegistryHive]::Users }
        'HKCR' { $h = [Microsoft.Win32.RegistryHive]::ClassesRoot }
    }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($h, [Microsoft.Win32.RegistryView]::Registry64)
    return @($base, $sub)
}

function Open-Reg([string]$Path, [bool]$Create = $false, [bool]$Write = $false) {
    try {
        $b = Get-RegBase $Path
        if ($Create) { return $b[0].CreateSubKey($b[1]) }
        return $b[0].OpenSubKey($b[1], $Write)
    } catch { return $null }
}

function ConvertTo-RegText($Kind, $Value) {
    switch ("$Kind") {
        'DWord'       { return [string]([BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]$Value), 0)) }
        'QWord'       { return [string]([BitConverter]::ToUInt64([BitConverter]::GetBytes([int64]$Value), 0)) }
        'Binary'      { return ((@($Value) | ForEach-Object { ([byte]$_).ToString('x2') }) -join ',') }
        'MultiString' { return (@($Value) -join "`n") }
        default       { return [string]$Value }
    }
}

function Read-RegValue([string]$Path, [string]$Name) {
    $r = @{ KeyExists = $false; Exists = $false; Kind = ''; Data = '' }
    $k = Open-Reg $Path
    if (-not $k) { return $r }
    $r.KeyExists = $true
    try {
        if (@($k.GetValueNames()) -contains $Name) {
            $kind = $k.GetValueKind($Name)
            $v = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $r.Exists = $true
            $r.Kind = "$kind"
            $r.Data = ConvertTo-RegText $kind $v
        }
    } finally { $k.Close() }
    return $r
}

function Write-RegValue([string]$Path, [string]$Name, [string]$Type, [string]$Data) {
    $k = Open-Reg $Path $true
    if (-not $k) { throw "Cannot open registry key $Path" }
    try {
        switch ($Type) {
            'DWord' {
                $u = [uint32][int64]$Data
                $k.SetValue($Name, [BitConverter]::ToInt32([BitConverter]::GetBytes($u), 0), [Microsoft.Win32.RegistryValueKind]::DWord)
            }
            'QWord' {
                $u = [uint64]$Data
                $k.SetValue($Name, [BitConverter]::ToInt64([BitConverter]::GetBytes($u), 0), [Microsoft.Win32.RegistryValueKind]::QWord)
            }
            'Binary' {
                $bytes = [byte[]]@($Data.Split(',') | Where-Object { $_.Trim() -ne '' } | ForEach-Object { [Convert]::ToByte($_.Trim(), 16) })
                $k.SetValue($Name, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
            }
            'ExpandString' { $k.SetValue($Name, $Data, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
            'MultiString'  { $k.SetValue($Name, [string[]]($Data -split "`n"), [Microsoft.Win32.RegistryValueKind]::MultiString) }
            default        { $k.SetValue($Name, $Data, [Microsoft.Win32.RegistryValueKind]::String) }
        }
    } finally { $k.Close() }
}

function Remove-RegValue([string]$Path, [string]$Name) {
    $k = Open-Reg $Path $false $true
    if ($k) { try { $k.DeleteValue($Name, $false) } catch { } finally { $k.Close() } }
}

function Remove-RegKeyTree([string]$Path) {
    try { $b = Get-RegBase $Path; $b[0].DeleteSubKeyTree($b[1], $false) } catch { }
}

function Remove-RegKeyIfEmpty([string]$Path) {
    $k = Open-Reg $Path
    if (-not $k) { return }
    $empty = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
    $k.Close()
    if ($empty) { try { $b = Get-RegBase $Path; $b[0].DeleteSubKey($b[1], $false) } catch { } }
}

# Spec format: "HIVE:\Path|ValueName|Type|Value|DefaultForRevert"
#   Type  = DWord, QWord, String, ExpandString, Binary, Delete (value must not exist)
#   Name  = (Default) for the unnamed default value
#   Default (optional) = value written back if no backup exists; "-" means delete the value
function ConvertFrom-RegSpec([string]$Spec) {
    $p = $Spec.Split('|')
    $name = $p[1]
    if ($name -eq '(Default)') { $name = '' }
    $o = @{ Path = $p[0]; Name = $name; Type = $p[2]; Data = ''; Default = $null }
    if ($p.Count -ge 4) { $o.Data = $p[3] }
    if ($p.Count -ge 5) { $o.Default = $p[4] }
    return $o
}

function Test-RegSpecs([string[]]$Specs) {
    foreach ($s in $Specs) {
        $r = ConvertFrom-RegSpec $s
        $cur = Read-RegValue $r.Path $r.Name
        if ($r.Type -eq 'Delete') { if ($cur.Exists) { return $false } else { continue } }
        if (-not $cur.Exists) { return $false }
        if ($r.Type -eq 'Binary') {
            if ($cur.Data.ToLower() -ne $r.Data.ToLower()) { return $false }
        } elseif ($r.Type -eq 'DWord' -or $r.Type -eq 'QWord') {
            if ([string]([uint64][int64]$r.Data) -ne $cur.Data) { return $false }
        } else {
            if ($cur.Data -ne $r.Data) { return $false }
        }
    }
    return $true
}

function Invoke-RegSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($s in $Specs) {
        $r = ConvertFrom-RegSpec $s
        $cur = Read-RegValue $r.Path $r.Name
        Add-BackupEntry $TweakId 'reg' $r.Path $r.Name $cur.Exists $cur.KeyExists $cur.Kind $cur.Data
        if ($r.Type -eq 'Delete') { Remove-RegValue $r.Path $r.Name }
        else { Write-RegValue $r.Path $r.Name $r.Type $r.Data }
    }
}

function Restore-RegSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($s in $Specs) {
        $r = ConvertFrom-RegSpec $s
        $b = Get-BackupEntry $TweakId 'reg' $r.Path $r.Name
        if ($b) {
            if ($b.Existed) {
                $kind = $b.ValKind; if (-not $kind) { $kind = 'String' }
                Write-RegValue $r.Path $r.Name $kind ([string]$b.Data)
            } else {
                Remove-RegValue $r.Path $r.Name
                if (-not $b.KeyExisted) { Remove-RegKeyIfEmpty $r.Path }
            }
        } elseif ($null -ne $r.Default) {
            if ($r.Default -eq '-') { Remove-RegValue $r.Path $r.Name }
            else {
                $t = $r.Type; if ($t -eq 'Delete') { $t = 'String' }
                Write-RegValue $r.Path $r.Name $t $r.Default
            }
        } elseif ($r.Type -ne 'Delete') {
            Remove-RegValue $r.Path $r.Name
        }
    }
}

# ------------------------------------------------------------------ services (via the Start value, so they are fully reversible)
# Spec: "ServiceName|StartValue|DefaultStartValue"   (2 = Automatic, 3 = Manual, 4 = Disabled)
function Test-RegKey([string]$Path) {
    $k = Open-Reg $Path
    if ($k) { $k.Close(); return $true }
    return $false
}

function Get-SvcRegSpec([string]$Spec) {
    $p = $Spec.Split('|')
    $s = 'HKLM:\SYSTEM\CurrentControlSet\Services\' + $p[0] + '|Start|DWord|' + $p[1]
    if ($p.Count -ge 3) { $s += '|' + $p[2] }
    return $s
}

function Test-SvcSpecs([string[]]$Specs) {
    foreach ($sp in $Specs) {
        $n = $sp.Split('|')[0]
        if (-not (Test-RegKey ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $n))) { continue }   # not installed = nothing to do
        if (-not (Test-RegSpecs @(Get-SvcRegSpec $sp))) { return $false }
    }
    return $true
}

function Invoke-SvcSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($sp in $Specs) {
        $p = $sp.Split('|'); $n = $p[0]
        if (-not (Test-RegKey ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $n))) { continue }
        Invoke-RegSpecs $TweakId @(Get-SvcRegSpec $sp)
        if ($p[1] -eq '4') { try { Stop-Service -Name $n -Force -ErrorAction SilentlyContinue } catch { } }
    }
}

function Restore-SvcSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($sp in $Specs) {
        $n = $sp.Split('|')[0]
        if (-not (Test-RegKey ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $n))) { continue }
        Restore-RegSpecs $TweakId @(Get-SvcRegSpec $sp)
        $start = (Read-RegValue ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $n) 'Start').Data
        if ($start -eq '2') { try { Start-Service -Name $n -ErrorAction SilentlyContinue } catch { } }
    }
}

# ------------------------------------------------------------------ power settings (powercfg)
# Spec: "SUBGROUP|SETTING|ACValue|DCValue"   (leave AC or DC empty to not touch it)
function Get-PowerIndex([string]$Sub, [string]$Set) {
    foreach ($sw in @('/qh', '/q')) {
        $out = (& powercfg $sw scheme_current $Sub $Set 2>$null) -join "`n"
        $hex = @([regex]::Matches($out, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
        if ($hex.Count -ge 2) {
            return @{ AC = [Convert]::ToUInt32($hex[$hex.Count - 2], 16); DC = [Convert]::ToUInt32($hex[$hex.Count - 1], 16) }
        }
    }
    return $null
}

function Test-PwrSpecs([string[]]$Specs) {
    foreach ($sp in $Specs) {
        $p = $sp.Split('|')
        $cur = Get-PowerIndex $p[0] $p[1]
        if (-not $cur) { continue }   # setting does not exist on this CPU / adapter
        if ($p[2] -ne '' -and [uint32]$p[2] -ne $cur.AC) { return $false }
        if ($p.Count -ge 4 -and $p[3] -ne '' -and [uint32]$p[3] -ne $cur.DC) { return $false }
    }
    return $true
}

function Invoke-PwrSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($sp in $Specs) {
        $p = $sp.Split('|')
        $cur = Get-PowerIndex $p[0] $p[1]
        if ($cur) { Add-BackupEntry $TweakId 'pwr' $p[0] $p[1] $true $true '' ("{0}|{1}" -f $cur.AC, $cur.DC) }
        if ($p[2] -ne '') { & powercfg /setacvalueindex scheme_current $p[0] $p[1] $p[2] 2>$null | Out-Null }
        if ($p.Count -ge 4 -and $p[3] -ne '') { & powercfg /setdcvalueindex scheme_current $p[0] $p[1] $p[3] 2>$null | Out-Null }
    }
    & powercfg /setactive scheme_current 2>$null | Out-Null
}

function Restore-PwrSpecs([string]$TweakId, [string[]]$Specs) {
    foreach ($sp in $Specs) {
        $p = $sp.Split('|')
        $b = Get-BackupEntry $TweakId 'pwr' $p[0] $p[1]
        if (-not $b) { continue }
        $v = ([string]$b.Data).Split('|')
        & powercfg /setacvalueindex scheme_current $p[0] $p[1] $v[0] 2>$null | Out-Null
        & powercfg /setdcvalueindex scheme_current $p[0] $p[1] $v[1] 2>$null | Out-Null
    }
    & powercfg /setactive scheme_current 2>$null | Out-Null
}

function Get-ActiveSchemeGuid {
    $o = (& powercfg /getactivescheme 2>$null) -join ' '
    return ([regex]::Match($o, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')).Value
}

function Get-OverlayGuid {
    try {
        $g = [Guid]::Empty
        [void][CchNative]::PowerGetEffectiveOverlayScheme([ref]$g)
        return $g.ToString()
    } catch {
        return (Read-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' 'ActiveOverlayAcPowerScheme').Data
    }
}

function Set-OverlayGuid([string]$Guid) {
    try { [void][CchNative]::PowerSetActiveOverlayScheme([Guid]$Guid); return $true } catch { return $false }
}

# ------------------------------------------------------------------ Appx (Store apps)
function Update-AppxCache {
    try { $Global:CCH.Appx = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) } catch { $Global:CCH.Appx = @() }
}

function Test-AppxGone([string[]]$Patterns) {
    foreach ($p in $Patterns) {
        foreach ($n in $Global:CCH.Appx) { if ($n -like $p) { return $false } }
    }
    return $true
}

function Remove-AppxSet([string[]]$Patterns) {
    foreach ($p in $Patterns) {
        foreach ($pkg in @(Get-AppxPackage -Name $p -ErrorAction SilentlyContinue)) {
            try { Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop; Write-Log "Removed app $($pkg.Name)" }
            catch { Write-Log "Could not remove $($pkg.Name): $($_.Exception.Message)" }
        }
    }
    Update-AppxCache
}

function Restore-AppxSet([string[]]$Patterns) {
    $missing = $false
    foreach ($p in $Patterns) {
        $found = @(Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue)
        foreach ($pkg in $found) {
            $m = Join-Path $pkg.InstallLocation 'AppxManifest.xml'
            if (Test-Path $m) {
                try { Add-AppxPackage -DisableDevelopmentMode -Register $m -ErrorAction Stop; Write-Log "Re-installed $($pkg.Name)" } catch { $missing = $true }
            } else { $missing = $true }
        }
        if ($found.Count -eq 0) { $missing = $true }
    }
    Update-AppxCache
    if ($missing) { Write-Log 'Some apps could not be restored automatically - reinstall them from the Microsoft Store if you need them.' }
}

# ==================================================================================================
#  TWEAK CATALOGUE
#  Page  : optim | debloat
#  For   : profile tags this tweak is recommended for ('All' = everyone, empty = optional)
#  Avoid : profile tags where it is NOT recommended
#  Tags  : All LowEnd Laptop Desktop iGPU dGPU Hybrid LowRAM LowDisk HDD SSD LowCPU HybridCPU S0 Win10 Win11
# ==================================================================================================

$Global:Tweaks = New-Object System.Collections.ArrayList

function New-Tweak {
    param(
        [string]$Id, [string]$Name, [string]$Page, [string]$Cat, [string]$Desc,
        [string]$Risk = 'Low', [switch]$Premium, [string[]]$For = @('All'), [string[]]$Avoid = @(),
        [string[]]$Reg = @(), [string[]]$Svc = @(), [string[]]$Pwr = @(), [string[]]$Appx = @(),
        [scriptblock]$Apply = $null, [scriptblock]$Revert = $null, [scriptblock]$Test = $null,
        [switch]$Reboot, [string]$Impact = 'Medium'
    )
    $t = [pscustomobject]@{
        Id = $Id; Name = $Name; Page = $Page; Cat = $Cat; Desc = $Desc; Risk = $Risk
        Premium = [bool]$Premium; For = $For; Avoid = $Avoid
        Reg = $Reg; Svc = $Svc; Pwr = $Pwr; Appx = $Appx
        ApplyCode = $Apply; RevertCode = $Revert; TestCode = $Test
        Reboot = [bool]$Reboot; Impact = $Impact
        Applied = $false; Reco = 'Optional'
        Card = $null; Toggle = $null; StateTxt = $null; ProIcon = $null
    }
    [void]$Global:Tweaks.Add($t)
}

$Global:CatIcons = @{
    'FPS & Latency'        = [char]0xE945
    'Power'                = [char]0xE7E8
    'Network & Ping'       = [char]0xE701
    'Memory & Storage'     = [char]0xEDA2
    'Roblox & Games'       = [char]0xE7FC
    'Quality of Life'      = [char]0xE771
    'Apps'                 = [char]0xE74D
    'Services'             = [char]0xE90F
    'Privacy & Telemetry'  = [char]0xEA18
    'Background & Startup' = [char]0xE823
}
$Global:PageCats = @{
    optim   = @('All', 'FPS & Latency', 'Power', 'Network & Ping', 'Memory & Storage', 'Roblox & Games', 'Quality of Life')
    debloat = @('All', 'Apps', 'Services', 'Privacy & Telemetry', 'Background & Startup')
}

# ------------------------------------------------------------------ Roblox helpers
$Global:RbxFlagSets = @{
    rbx_lowend = [ordered]@{
        'DFIntCSGLevelOfDetailSwitchingDistance'    = '0'
        'DFIntCSGLevelOfDetailSwitchingDistanceL12' = '0'
        'DFIntCSGLevelOfDetailSwitchingDistanceL23' = '0'
        'DFIntCSGLevelOfDetailSwitchingDistanceL34' = '0'
        'DFFlagTextureQualityOverrideEnabled'       = 'True'
        'DFIntTextureQualityOverride'               = '0'
        'FIntDebugForceMSAASamples'                 = '0'
        'FFlagDebugGraphicsPreferD3D11'             = 'True'
    }
    rbx_potato = [ordered]@{
        'DFIntDebugFRMQualityLevelOverride' = '1'
        'DFFlagDebugPauseVoxelizer'         = 'True'
        'FIntFRMMinGrassDistance'           = '0'
        'FIntFRMMaxGrassDistance'           = '0'
    }
}

function Get-RobloxVersionDirs {
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Roblox\Versions'),
        (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions'),
        (Join-Path $env:ProgramFiles 'Roblox\Versions')
    )
    $dirs = @()
    foreach ($r in $roots) {
        if ($r -and (Test-Path $r)) {
            $dirs += @(Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'RobloxPlayerBeta.exe') })
        }
    }
    return @($dirs | Sort-Object LastWriteTime -Descending)
}

function Read-RobloxFlags([string]$File) {
    $cur = [ordered]@{}
    if (Test-Path $File) {
        try {
            $o = [IO.File]::ReadAllText($File) | ConvertFrom-Json
            foreach ($p in $o.PSObject.Properties) { $cur[$p.Name] = [string]$p.Value }
        } catch { }
    }
    return $cur
}

function Set-RobloxFlags($Add, [string[]]$Remove) {
    $dirs = Get-RobloxVersionDirs
    if ($dirs.Count -eq 0) { throw 'Roblox Player is not installed on this PC (RobloxPlayerBeta.exe not found).' }
    foreach ($d in $dirs) {
        $cs = Join-Path $d.FullName 'ClientSettings'
        if (-not (Test-Path $cs)) { New-Item -ItemType Directory -Force -Path $cs | Out-Null }
        $f = Join-Path $cs 'ClientAppSettings.json'
        $cur = Read-RobloxFlags $f
        foreach ($k in @($Remove)) { if ($k -and $cur.Contains($k)) { $cur.Remove($k) } }
        if ($Add) { foreach ($k in $Add.Keys) { $cur[$k] = [string]$Add[$k] } }
        $json = '{}'
        if ($cur.Count -gt 0) { $json = ConvertTo-Json -InputObject $cur }
        [IO.File]::WriteAllText($f, $json, $Global:Utf8NoBom)
    }
}

function Test-RobloxFlags($Set) {
    $dirs = Get-RobloxVersionDirs
    if ($dirs.Count -eq 0) { return $false }
    $cur = Read-RobloxFlags (Join-Path $dirs[0].FullName 'ClientSettings\ClientAppSettings.json')
    foreach ($k in $Set.Keys) { if (-not $cur.Contains($k) -or $cur[$k] -ne [string]$Set[$k]) { return $false } }
    return $true
}

function Sync-RobloxFlags {
    foreach ($id in @($Global:CCH.Settings.RobloxEnabled)) {
        $set = $Global:RbxFlagSets[$id]
        if ($set -and -not (Test-RobloxFlags $set)) {
            try { Set-RobloxFlags $set @(); Write-Log "Re-applied Roblox flags ($id) after a Roblox update." } catch { }
        }
    }
}

function Set-RobloxEnabled([string]$Id, [bool]$On) {
    $list = @($Global:CCH.Settings.RobloxEnabled | Where-Object { $_ -and $_ -ne $Id })
    if ($On) { $list += $Id }
    $Global:CCH.Settings.RobloxEnabled = $list
    Save-Settings
}

function Get-RobloxGpuSpecs {
    $specs = @()
    foreach ($d in Get-RobloxVersionDirs) {
        $exe = Join-Path $d.FullName 'RobloxPlayerBeta.exe'
        $specs += 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences|' + $exe + '|String|GpuPreference=2;'
        $specs += 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers|' + $exe + '|String|~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    }
    return $specs
}

function Get-NagleSpecs {
    $specs = @()
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $k = Open-Reg $base
    if (-not $k) { return $specs }
    foreach ($g in $k.GetSubKeyNames()) {
        $p = $base + '\' + $g
        $ip = (Read-RegValue $p 'DhcpIPAddress').Data
        if (-not $ip -or $ip -eq '0.0.0.0') { $ip = (Read-RegValue $p 'IPAddress').Data }
        if ($ip -and $ip -ne '0.0.0.0') {
            $specs += "$p|TcpAckFrequency|DWord|1|-"
            $specs += "$p|TCPNoDelay|DWord|1|-"
            $specs += "$p|TcpDelAckTicks|DWord|0|-"
        }
    }
    $k.Close()
    return $specs
}

# ==================================================================================================
#  OPTIMIZATIONS PAGE
# ==================================================================================================

# ---------- FPS & Latency
New-Tweak -Id 'gamemode' -Page optim -Cat 'FPS & Latency' -Name 'Enable Windows Game Mode' -Impact High `
  -Desc 'Tells Windows to put the game first: pauses Windows Update installs and gives the game more CPU and GPU time while you play.' `
  -Reg @('HKCU:\Software\Microsoft\GameBar|AutoGameModeEnabled|DWord|1|1', 'HKCU:\Software\Microsoft\GameBar|AllowAutoGameMode|DWord|1|-')

New-Tweak -Id 'gamedvr' -Page optim -Cat 'FPS & Latency' -Name 'Disable Game DVR Background Recording' -Impact High `
  -Desc 'Stops Xbox Game Bar from silently recording your gameplay in the background. This recording eats GPU power, which hurts a lot on integrated graphics.' `
  -Reg @('HKCU:\System\GameConfigStore|GameDVR_Enabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR|AppCaptureEnabled|DWord|0|1',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR|AllowGameDVR|DWord|0|-')

New-Tweak -Id 'sysresp' -Page optim -Cat 'FPS & Latency' -Name 'Prioritize Games in the Multimedia Scheduler' -Premium -Impact High `
  -Desc 'Reserves less CPU for background tasks and raises the GPU and CPU priority of games in the Windows multimedia scheduler (MMCSS).' `
  -Reg @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile|SystemResponsiveness|DWord|10|20',
         'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|GPU Priority|DWord|8|8',
         'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|Priority|DWord|6|2',
         'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|Scheduling Category|String|High|Medium',
         'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games|SFIO Priority|String|High|Normal')

New-Tweak -Id 'prisep' -Page optim -Cat 'FPS & Latency' -Name 'Foreground CPU Priority Boost' -Premium -Impact Medium `
  -Desc 'Gives the window you are using (your game) longer, higher-priority CPU time slices than background programs. Smoother frame times on 2-4 core CPUs.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl|Win32PrioritySeparation|DWord|38|2')

New-Tweak -Id 'hags' -Page optim -Cat 'FPS & Latency' -Name 'Hardware-Accelerated GPU Scheduling' -For @('dGPU') -Impact Medium -Reboot `
  -Desc 'Lets a dedicated NVIDIA/AMD graphics card manage its own memory, which lowers latency and can raise FPS. Needs a restart. Little effect on integrated graphics.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers|HwSchMode|DWord|2|-')

New-Tweak -Id 'fso' -Page optim -Cat 'FPS & Latency' -Name 'Disable Fullscreen Optimizations (Global)' -Premium -Risk Medium -For @('dGPU') -Impact Medium `
  -Desc 'Forces true exclusive fullscreen in older DirectX games for lower input lag. Can make Alt+Tab slower and may affect HDR, so only use it if you play fullscreen.' `
  -Reg @('HKCU:\System\GameConfigStore|GameDVR_FSEBehaviorMode|DWord|2|0',
         'HKCU:\System\GameConfigStore|GameDVR_FSEBehavior|DWord|2|-',
         'HKCU:\System\GameConfigStore|GameDVR_HonorUserFSEBehaviorMode|DWord|1|0',
         'HKCU:\System\GameConfigStore|GameDVR_DXGIHonorFSEWindowsCompatible|DWord|1|0')

New-Tweak -Id 'mouseaccel' -Page optim -Cat 'FPS & Latency' -Name 'Disable Mouse Acceleration' -Impact Low `
  -Desc 'Turns off "Enhance pointer precision" so your aim moves the same distance every time, no matter how fast you move the mouse. Essential for shooters.' `
  -Reg @('HKCU:\Control Panel\Mouse|MouseSpeed|String|0|1', 'HKCU:\Control Panel\Mouse|MouseThreshold1|String|0|6', 'HKCU:\Control Panel\Mouse|MouseThreshold2|String|0|10')

New-Tweak -Id 'powerthrottle' -Page optim -Cat 'FPS & Latency' -Name 'Disable Windows Power Throttling' -Impact Medium `
  -Desc 'Stops Windows from putting apps it thinks are "in the background" onto slow, power-saving CPU states. Keeps launchers, Discord and the game at full speed.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling|PowerThrottlingOff|DWord|1|-')

New-Tweak -Id 'timerres' -Page optim -Cat 'FPS & Latency' -Name 'Global Timer Resolution Requests' -Premium -For @('Win11') -Impact Low -Reboot `
  -Desc 'Windows 11 only: lets a game''s high-precision timer request apply system-wide again, which can reduce stutter and input delay in some titles.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel|GlobalTimerResolutionRequests|DWord|1|-')

New-Tweak -Id 'mpo' -Page optim -Cat 'FPS & Latency' -Name 'Disable Multiplane Overlay (MPO)' -Premium -Risk Medium -For @() -Impact Low -Reboot `
  -Desc 'Fixes flickering, black screens and stutter that some NVIDIA/AMD cards get in borderless games. Only turn on if you actually see those problems.' `
  -Reg @('HKLM:\SOFTWARE\Microsoft\Windows\Dwm|OverlayTestMode|DWord|5|-')

New-Tweak -Id 'windowedopt' -Page optim -Cat 'FPS & Latency' -Name 'Optimizations for Windowed Games' -For @('Win11') -Impact Medium `
  -Desc 'Windows 11 feature that upgrades older DirectX 10/11 games running windowed or borderless to a lower-latency presentation mode. Helps Roblox in windowed mode.' `
  -Reg @('HKCU:\Software\Microsoft\DirectX\UserGpuPreferences|DirectXUserGlobalSettings|String|SwapEffectUpgradeEnable=1;|-')

New-Tweak -Id 'visualfx' -Page optim -Cat 'FPS & Latency' -Name 'Visual Effects: Best Performance' -For @('LowEnd', 'iGPU', 'LowRAM') -Impact Medium `
  -Desc 'Turns off window animations, shadows and fades so Windows uses less GPU and RAM. Font smoothing is kept. Sign out and back in to see the full effect.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects|VisualFXSetting|DWord|2|0',
         'HKCU:\Control Panel\Desktop|UserPreferencesMask|Binary|90,12,03,80,10,00,00,00|9e,1e,07,80,12,00,00,00',
         'HKCU:\Control Panel\Desktop\WindowMetrics|MinAnimate|String|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|TaskbarAnimations|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ListviewShadow|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\DWM|EnableAeroPeek|DWord|0|1')

New-Tweak -Id 'transparency' -Page optim -Cat 'FPS & Latency' -Name 'Disable Transparency Effects' -For @('iGPU', 'LowEnd') -Impact Low `
  -Desc 'Removes the see-through blur on the taskbar, Start menu and windows. Saves GPU work that integrated graphics would rather spend on your game.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize|EnableTransparency|DWord|0|1')

New-Tweak -Id 'pagingexec' -Page optim -Cat 'FPS & Latency' -Name 'Keep Windows Kernel in RAM' -Premium -Avoid @('LowRAM4') -Impact Low -Reboot `
  -Desc 'Stops Windows from paging its own core drivers out to disk, avoiding small hitches when they are needed again. Not recommended with 4 GB of RAM or less.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management|DisablePagingExecutive|DWord|1|0')

# ---------- Power
New-Tweak -Id 'powermode' -Page optim -Cat 'Power' -Name 'Windows Power Mode: Best Performance' -For @('Laptop') -Impact High `
  -Desc 'Switches the Windows power slider to "Best performance" while plugged in. On thin laptops this is one of the biggest FPS gains, because it raises CPU and GPU power limits.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes|ActiveOverlayAcPowerScheme|String|ded574b5-45a0-4f42-8737-46345c09c238') `
  -Apply { [void](Set-OverlayGuid 'ded574b5-45a0-4f42-8737-46345c09c238') } `
  -Revert { [void](Set-OverlayGuid '00000000-0000-0000-0000-000000000000') }

New-Tweak -Id 'cpuboost' -Page optim -Cat 'Power' -Name 'Aggressive CPU Boost (on charger)' -Premium -Impact High `
  -Desc 'While plugged in, tells the CPU to boost to its top clock speed immediately and prefer performance over power saving. Battery settings are not changed.' `
  -Pwr @('sub_processor|PERFBOOSTMODE|2|', 'sub_processor|PERFEPP|0|', 'sub_processor|PERFEPP1|0|')

New-Tweak -Id 'ultimate' -Page optim -Cat 'Power' -Name 'Ultimate Performance Power Plan' -Premium -Risk Medium -For @('Desktop', 'dGPU') -Avoid @('S0') -Impact Medium `
  -Desc 'Adds and activates Microsoft''s hidden "Ultimate Performance" plan, removing tiny power-saving delays. Uses more power and heat; many thin laptops do not support it.' `
  -Test { $g = [string]$Global:CCH.Settings.UltimateGuid; return ($g -and ((Get-ActiveSchemeGuid) -eq $g)) } `
  -Apply {
      param($t)
      $prev = Get-ActiveSchemeGuid
      Add-BackupEntry $t.Id 'misc' 'scheme' 'previous' $true $true '' $prev
      $out = (& powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null) -join ' '
      $g = ([regex]::Match($out, '[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')).Value
      if (-not $g) { throw 'This PC does not allow extra power plans (common on Modern Standby laptops). Use "Windows Power Mode: Best Performance" instead.' }
      & powercfg -setactive $g 2>$null | Out-Null
      if ((Get-ActiveSchemeGuid) -ne $g) { & powercfg -delete $g 2>$null | Out-Null; throw 'Windows refused to switch power plans on this PC.' }
      $Global:CCH.Settings.UltimateGuid = $g; Save-Settings
  } `
  -Revert {
      param($t)
      $b = Get-BackupEntry $t.Id 'misc' 'scheme' 'previous'
      $prev = '381b4222-f694-41f0-9685-ff5bb260df2e'
      if ($b -and $b.Data) { $prev = [string]$b.Data }
      & powercfg -setactive $prev 2>$null | Out-Null
      if ($Global:CCH.Settings.UltimateGuid) { & powercfg -delete $Global:CCH.Settings.UltimateGuid 2>$null | Out-Null }
      $Global:CCH.Settings.UltimateGuid = ''; Save-Settings
  }

New-Tweak -Id 'coreparking' -Page optim -Cat 'Power' -Name 'Disable CPU Core Parking (on charger)' -Premium -For @('Desktop') -Avoid @('HybridCPU') -Impact Medium `
  -Desc 'Keeps all CPU cores awake so a game never waits for a sleeping core to wake up. Not recommended on Intel 12th gen+ hybrid CPUs, which park E-cores on purpose.' `
  -Pwr @('sub_processor|CPMINCORES|100|')

New-Tweak -Id 'usbsuspend' -Page optim -Cat 'Power' -Name 'Disable USB Selective Suspend (on charger)' -Impact Low `
  -Desc 'Stops Windows from putting your USB mouse, keyboard and headset to sleep, which can cause random input lag or disconnects mid-game.' `
  -Pwr @('2a737441-1930-4402-8d77-b2bebba308a3|48e6b7a6-50f5-4782-a5d4-53bb8f07e226|0|')

New-Tweak -Id 'pcieaspm' -Page optim -Cat 'Power' -Name 'Disable PCIe Link Power Saving (on charger)' -Premium -For @('dGPU') -Impact Low `
  -Desc 'Keeps the link to your graphics card and NVMe SSD at full speed instead of dropping into power-save, avoiding micro-stutters when load spikes.' `
  -Pwr @('sub_pciexpress|ASPM|0|')

New-Tweak -Id 'diskidle' -Page optim -Cat 'Power' -Name 'Never Spin Down the Hard Drive (on charger)' -For @('HDD') -Impact Low `
  -Desc 'Stops a hard drive (HDD) from spinning down, which causes a multi-second freeze when a game loads something. Not needed for SSDs.' `
  -Pwr @('sub_disk|DISKIDLE|0|')

New-Tweak -Id 'hibernate' -Page optim -Cat 'Power' -Name 'Disable Hibernation' -For @('Desktop', 'LowDisk') -Impact Low `
  -Desc 'Deletes hiberfil.sys and frees disk space equal to a big part of your RAM (several GB). Laptops lose the hibernate option on critical battery.' `
  -Test { return ((Read-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled').Data -eq '0') } `
  -Apply { & powercfg /hibernate off 2>$null | Out-Null } `
  -Revert { & powercfg /hibernate on 2>$null | Out-Null }

# ---------- Network & Ping
New-Tweak -Id 'netthrottle' -Page optim -Cat 'Network & Ping' -Name 'Remove Network Throttling' -Impact Medium `
  -Desc 'Windows limits network packet processing while media is playing. This removes that limit so game traffic is never held back.' `
  -Reg @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile|NetworkThrottlingIndex|DWord|4294967295|10')

New-Tweak -Id 'qoslimit' -Page optim -Cat 'Network & Ping' -Name 'Remove Reserved Bandwidth Limit' -Impact Low `
  -Desc 'Sets the Windows QoS bandwidth reservation to 0% so no part of your connection is set aside for system services.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched|NonBestEffortLimit|DWord|0|-')

New-Tweak -Id 'nagle' -Page optim -Cat 'Network & Ping' -Name 'Disable Nagle''s Algorithm (TCP No Delay)' -Premium -Impact Low `
  -Desc 'Sends small TCP packets immediately instead of bundling them. Helps games and launchers that use TCP; games using UDP are unaffected.' `
  -Test { $s = Get-NagleSpecs; if ($s.Count -eq 0) { return $false }; return (Test-RegSpecs $s) } `
  -Apply { param($t) $s = Get-NagleSpecs; if ($s.Count -eq 0) { throw 'No connected network adapter found.' }; Invoke-RegSpecs $t.Id $s } `
  -Revert { param($t) $s = @($Global:CCH.Backup | Where-Object { $_.Tweak -eq $t.Id -and $_.Kind -eq 'reg' } | ForEach-Object { $_.Path + '|' + $_.Name + '|DWord|0|-' }); if ($s.Count) { Restore-RegSpecs $t.Id $s } }

New-Tweak -Id 'deliveryopt' -Page optim -Cat 'Network & Ping' -Name 'Stop Windows Update Peer-to-Peer Uploads' -Impact Medium `
  -Desc 'Stops your PC from uploading Windows updates to other people on the internet in the background, which can cause ping spikes.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization|DODownloadMode|DWord|0|-')

New-Tweak -Id 'wifipower' -Page optim -Cat 'Network & Ping' -Name 'Wi-Fi Adapter Maximum Performance (on charger)' -For @('Laptop') -Impact Medium `
  -Desc 'Stops the Wi-Fi card from napping between packets while plugged in. Reduces ping spikes and jitter on laptops.' `
  -Pwr @('19cac1b6-e1d1-4d1f-a12e-47963a01d9da|12bbebe6-58d6-4636-95bb-3217ef867c1a|0|')

New-Tweak -Id 'preferipv4' -Page optim -Cat 'Network & Ping' -Name 'Prefer IPv4 over IPv6' -Premium -For @() -Impact Low -Reboot `
  -Desc 'Makes Windows try IPv4 first. Can fix slow connections or higher ping on networks with poor IPv6 routing. IPv6 stays enabled.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters|DisabledComponents|DWord|32|-')

# ---------- Memory & Storage
New-Tweak -Id 'lastaccess' -Page optim -Cat 'Memory & Storage' -Name 'Disable NTFS Last-Access Timestamps' -Impact Low `
  -Desc 'Stops Windows writing a timestamp every time a file is opened. Fewer disk writes while games load thousands of small files.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem|NtfsDisableLastAccessUpdate|DWord|2147483649|2147483650')

New-Tweak -Id 'shortnames' -Page optim -Cat 'Memory & Storage' -Name 'Disable 8.3 Short File Names' -Premium -For @('HDD') -Impact Low `
  -Desc 'Stops creating old DOS-style short names for every new file, which speeds up folders with many files, especially on hard drives.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem|NtfsDisable8dot3NameCreation|DWord|1|2')

New-Tweak -Id 'sysmain' -Page optim -Cat 'Memory & Storage' -Name 'Disable SysMain (Superfetch)' -Risk Medium -For @('HDD') -Impact Medium `
  -Desc 'Stops Windows pre-loading apps into RAM. Fixes 100% disk usage on hard drives. On SSDs it rarely helps, so it is left optional there.' `
  -Svc @('SysMain|4|2')

New-Tweak -Id 'searchindex' -Page optim -Cat 'Memory & Storage' -Name 'Disable Search Indexing' -Risk Medium -For @('HDD', 'LowCPU') -Impact Medium `
  -Desc 'Stops the indexer scanning your files in the background. Start-menu and Outlook search get slower, but CPU and disk stay free for games.' `
  -Svc @('WSearch|4|2')

New-Tweak -Id 'pagefile' -Page optim -Cat 'Memory & Storage' -Name 'System-Managed Page File' -For @('LowRAM') -Impact Medium `
  -Desc 'Lets Windows size the page file automatically. With 8 GB of RAM or less this prevents big games crashing with "out of memory" errors.' `
  -Test { $c = Get-CimInstance Win32_ComputerSystem; return [bool]$c.AutomaticManagedPagefile } `
  -Apply { Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop } `
  -Revert { Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = $false } -ErrorAction SilentlyContinue }

New-Tweak -Id 'storagesense' -Page optim -Cat 'Memory & Storage' -Name 'Enable Storage Sense Auto-Cleanup' -For @('LowDisk') -Impact Low `
  -Desc 'Lets Windows automatically clear temp files and old Recycle Bin items when space runs low. A full disk makes everything slower.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy|01|DWord|1|0')

# ---------- Roblox & Games
New-Tweak -Id 'rbx_lowend' -Page optim -Cat 'Roblox & Games' -Name 'Roblox: Low-End Graphics Pack' -For @('All') -Impact High `
  -Desc 'Uses only Roblox''s officially allow-listed FastFlags: lowest texture and part detail, no anti-aliasing, DirectX 11. Re-applied automatically after Roblox updates.' `
  -Test { return (Test-RobloxFlags $Global:RbxFlagSets['rbx_lowend']) } `
  -Apply { Set-RobloxFlags $Global:RbxFlagSets['rbx_lowend'] @(); Set-RobloxEnabled 'rbx_lowend' $true } `
  -Revert { Set-RobloxEnabled 'rbx_lowend' $false; try { Set-RobloxFlags $null @($Global:RbxFlagSets['rbx_lowend'].Keys) } catch { } }

New-Tweak -Id 'rbx_potato' -Page optim -Cat 'Roblox & Games' -Name 'Roblox: Ultra-Low Render Mode' -Premium -For @('LowEnd', 'iGPU') -Impact High `
  -Desc 'Forces Roblox''s lowest render quality, removes grass and pauses voxel lighting updates. Looks plainer but gives the biggest FPS jump on integrated graphics.' `
  -Test { return (Test-RobloxFlags $Global:RbxFlagSets['rbx_potato']) } `
  -Apply { Set-RobloxFlags $Global:RbxFlagSets['rbx_potato'] @(); Set-RobloxEnabled 'rbx_potato' $true } `
  -Revert { Set-RobloxEnabled 'rbx_potato' $false; try { Set-RobloxFlags $null @($Global:RbxFlagSets['rbx_potato'].Keys) } catch { } }

New-Tweak -Id 'rbx_gpu' -Page optim -Cat 'Roblox & Games' -Name 'Roblox: High-Performance GPU + Fullscreen Fix' -Impact Medium `
  -Desc 'Tells Windows to run Roblox on your strongest GPU (important on laptops with NVIDIA/AMD + Intel) and turns off fullscreen optimizations for Roblox only.' `
  -Test { $s = Get-RobloxGpuSpecs; if ($s.Count -eq 0) { return $false }; return (Test-RegSpecs $s) } `
  -Apply { param($t) $s = Get-RobloxGpuSpecs; if ($s.Count -eq 0) { throw 'Roblox Player is not installed on this PC.' }; Invoke-RegSpecs $t.Id $s } `
  -Revert { param($t) $s = @($Global:CCH.Backup | Where-Object { $_.Tweak -eq $t.Id -and $_.Kind -eq 'reg' } | ForEach-Object { $_.Path + '|' + $_.Name + '|String||-' }); if ($s.Count) { Restore-RegSpecs $t.Id $s } }

New-Tweak -Id 'gamebar' -Page optim -Cat 'Roblox & Games' -Name 'Disable Game Bar Popups and Controller Button' -Impact Low `
  -Desc 'Stops the Xbox Game Bar opening when you press the Xbox button on a controller and hides its startup tips. Game Mode keeps working.' `
  -Reg @('HKCU:\Software\Microsoft\GameBar|UseNexusForGameBarEnabled|DWord|0|1', 'HKCU:\Software\Microsoft\GameBar|ShowStartupPanel|DWord|0|-')

# ---------- Quality of Life
New-Tweak -Id 'menudelay' -Page optim -Cat 'Quality of Life' -Name 'Instant Menus' -Impact Low `
  -Desc 'Removes the 0.4 second delay before right-click sub-menus and Start menus open. Windows simply feels snappier.' `
  -Reg @('HKCU:\Control Panel\Desktop|MenuShowDelay|String|0|400')

New-Tweak -Id 'startupdelay' -Page optim -Cat 'Quality of Life' -Name 'Remove Startup App Delay' -Impact Low `
  -Desc 'Windows waits several seconds after login before launching startup apps. This removes the artificial wait so the desktop is ready sooner.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize|StartupDelayInMSec|DWord|0|-')

New-Tweak -Id 'stickykeys' -Page optim -Cat 'Quality of Life' -Name 'Disable Sticky Keys Popup' -Impact Low `
  -Desc 'Stops the "Sticky Keys" box that steals focus from your game when you press Shift five times (very common when sprinting).' `
  -Reg @('HKCU:\Control Panel\Accessibility\StickyKeys|Flags|String|506|510',
         'HKCU:\Control Panel\Accessibility\ToggleKeys|Flags|String|58|62',
         'HKCU:\Control Panel\Accessibility\Keyboard Response|Flags|String|122|126')

New-Tweak -Id 'fileext' -Page optim -Cat 'Quality of Life' -Name 'Show File Extensions' -For @() -Impact Low `
  -Desc 'Shows .exe, .zip, .png and so on in File Explorer. Makes it much easier to spot fake "game hacks" that are really malware.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|HideFileExt|DWord|0|1')

New-Tweak -Id 'classicmenu' -Page optim -Cat 'Quality of Life' -Name 'Classic Right-Click Menu' -For @() -Impact Low `
  -Desc 'Windows 11: brings back the full right-click menu without having to click "Show more options". Explorer restarts to apply it.' `
  -Test { return (Test-RegKey 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32') } `
  -Apply { Write-RegValue 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '' 'String' ''; Stop-Process -Name explorer -Force } `
  -Revert { Remove-RegKeyTree 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'; Stop-Process -Name explorer -Force }

New-Tweak -Id 'faststartup' -Page optim -Cat 'Quality of Life' -Name 'Disable Fast Startup' -For @() -Impact Low `
  -Desc 'Makes "Shut down" a real full shutdown. Boot is a few seconds slower, but drivers start fresh, which fixes many "laptop gets slower over days" problems.' `
  -Reg @('HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power|HiberbootEnabled|DWord|0|1')

New-Tweak -Id 'bootinfo' -Page optim -Cat 'Quality of Life' -Name 'Show Detailed Startup Messages' -For @() -Impact Low `
  -Desc 'Shows what Windows is doing during startup and shutdown ("Applying settings..."). Does not make it faster, but helps you see what is slow.' `
  -Reg @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System|VerboseStatus|DWord|1|-')

# ==================================================================================================
#  DEBLOAT PAGE
# ==================================================================================================

# ---------- Privacy & Telemetry
New-Tweak -Id 'telemetry' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Windows Telemetry' -Impact Medium `
  -Desc 'Turns diagnostic data collection down to the minimum and disables the DiagTrack service that uploads it in the background.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|AllowTelemetry|DWord|0|-',
         'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection|AllowTelemetry|DWord|0|-') `
  -Svc @('DiagTrack|4|2', 'dmwappushservice|4|3')

New-Tweak -Id 'adid' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Advertising ID' -Impact Low `
  -Desc 'Stops apps using a unique ID to show you personalised ads across apps.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo|Enabled|DWord|0|1',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo|DisabledByGroupPolicy|DWord|1|-')

New-Tweak -Id 'tailored' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Tailored Experiences' -Impact Low `
  -Desc 'Stops Microsoft using your diagnostic data to show personalised tips, ads and recommendations.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy|TailoredExperiencesWithDiagnosticDataEnabled|DWord|0|1')

New-Tweak -Id 'activity' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Activity History' -Impact Low `
  -Desc 'Stops Windows recording which apps, files and websites you use for the Timeline feature.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\System|EnableActivityFeed|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System|PublishUserActivities|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System|UploadUserActivities|DWord|0|-')

New-Tweak -Id 'tips' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Tips, Suggestions and Auto-Installed Apps' -Impact Medium `
  -Desc 'Stops Windows installing "suggested" apps and games by itself and removes tips and ads in Start, Settings and the lock screen.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SilentInstalledAppsEnabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SystemPaneSuggestionsEnabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SoftLandingEnabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|RotatingLockScreenOverlayEnabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338388Enabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-338389Enabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353694Enabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-353696Enabled|DWord|0|1',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SubscribedContent-310093Enabled|DWord|0|1')

New-Tweak -Id 'bing' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Bing Web Results in Start' -Impact Medium `
  -Desc 'Start-menu search only searches your PC instead of sending every keystroke to Bing. Search becomes faster and uses less CPU.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search|BingSearchEnabled|DWord|0|-',
         'HKCU:\Software\Policies\Microsoft\Windows\Explorer|DisableSearchBoxSuggestions|DWord|1|-')

New-Tweak -Id 'copilot' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Copilot' -Impact Low `
  -Desc 'Turns off the Windows Copilot sidebar and its taskbar button.' `
  -Reg @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|DWord|1|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot|TurnOffWindowsCopilot|DWord|1|-',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced|ShowCopilotButton|DWord|0|-')

New-Tweak -Id 'recall' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Recall Snapshots' -For @('Win11') -Impact Medium `
  -Desc 'Windows 11 24H2: stops Recall from taking screenshots of everything you do. Saves disk space, CPU and a lot of privacy.' `
  -Reg @('HKCU:\Software\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|DWord|1|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI|DisableAIDataAnalysis|DWord|1|-')

New-Tweak -Id 'cortana' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Cortana' -Impact Low `
  -Desc 'Stops Cortana running and listening in the background.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search|AllowCortana|DWord|0|-')

New-Tweak -Id 'feedback' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Feedback Prompts' -Impact Low `
  -Desc 'Stops Windows popping up "How likely are you to recommend..." surveys at random moments, including mid-game.' `
  -Reg @('HKCU:\Software\Microsoft\Siuf\Rules|NumberOfSIUFInPeriod|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection|DoNotShowFeedbackNotifications|DWord|1|-')

New-Tweak -Id 'errorreport' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Windows Error Reporting' -Impact Low `
  -Desc 'Stops Windows collecting and uploading crash dumps after an app crashes, which can freeze the PC for a while on slow drives.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting|Disabled|DWord|1|-') `
  -Svc @('WerSvc|4|3')

New-Tweak -Id 'ceip' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable CEIP and App Inventory' -Premium -Impact Low `
  -Desc 'Turns off the Customer Experience Improvement Program and the app-compatibility inventory that scans your installed programs.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows|CEIPEnable|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat|AITEnable|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat|DisableInventory|DWord|1|-')

New-Tweak -Id 'inking' -Page debloat -Cat 'Privacy & Telemetry' -Name 'Disable Typing and Inking Data Collection' -Premium -Impact Low `
  -Desc 'Stops Windows learning from what you type and write to build a personal dictionary that is sent to Microsoft.' `
  -Reg @('HKCU:\Software\Microsoft\InputPersonalization|RestrictImplicitInkCollection|DWord|1|0',
         'HKCU:\Software\Microsoft\InputPersonalization|RestrictImplicitTextCollection|DWord|1|0',
         'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore|HarvestContacts|DWord|0|1',
         'HKCU:\Software\Microsoft\Personalization\Settings|AcceptedPrivacyPolicy|DWord|0|-')

# ---------- Background & Startup
New-Tweak -Id 'bgapps' -Page debloat -Cat 'Background & Startup' -Name 'Disable Background Store Apps' -Impact High `
  -Desc 'Stops Microsoft Store apps (Weather, News, Mail...) running in the background when you are not using them. Frees RAM and CPU on 8 GB machines.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications|GlobalUserDisabled|DWord|1|0',
         'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search|BackgroundAppGlobalToggle|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy|LetAppsRunInBackground|DWord|2|-')

New-Tweak -Id 'widgets' -Page debloat -Cat 'Background & Startup' -Name 'Disable Widgets and News Feed' -Impact High `
  -Desc 'Removes the Widgets board / News and Interests. Its background processes use 150-400 MB of RAM all the time.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Dsh|AllowNewsAndInterests|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds|EnableFeeds|DWord|0|-')

New-Tweak -Id 'edgebg' -Page debloat -Cat 'Background & Startup' -Name 'Stop Edge Running in the Background' -Impact Medium `
  -Desc 'Turns off Edge "Startup boost" and "Continue running background apps", so Edge does not sit in RAM after you close it.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Microsoft\Edge|StartupBoostEnabled|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\Microsoft\Edge|BackgroundModeEnabled|DWord|0|-')

New-Tweak -Id 'chromebg' -Page debloat -Cat 'Background & Startup' -Name 'Stop Chrome and Brave Running in the Background' -Impact Medium `
  -Desc 'Makes Chrome and Brave fully close when you close the window instead of staying in the system tray using RAM.' `
  -Reg @('HKLM:\SOFTWARE\Policies\Google\Chrome|BackgroundModeEnabled|DWord|0|-',
         'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave|BackgroundModeEnabled|DWord|0|-')

New-Tweak -Id 'onedrive' -Page debloat -Cat 'Background & Startup' -Name 'Stop OneDrive Starting with Windows' -Risk Medium -For @('LowEnd') -Impact Medium `
  -Desc 'OneDrive will no longer start automatically (files only sync when you open it). It is not uninstalled. Skip this if you rely on live sync for work.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run|OneDrive|Delete')

New-Tweak -Id 'teamsstart' -Page debloat -Cat 'Background & Startup' -Name 'Stop Teams Starting with Windows' -For @() -Impact Medium `
  -Desc 'Prevents Microsoft Teams auto-starting at login (you can still open it). Teams can use 300-600 MB of RAM in the background.' `
  -Reg @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run|com.squirrel.Teams.Teams|Delete',
         'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData\MSTeams_8wekyb3d8bbwe\TeamsTfwStartupTask|State|DWord|1|-')

# ---------- Services
New-Tweak -Id 'svc_fax' -Page debloat -Cat 'Services' -Name 'Disable Fax and Retail Demo Services' -Impact Low `
  -Desc 'Turns off the fax service and the shop-display "Retail Demo" service. Nobody needs these on a gaming PC.' `
  -Svc @('Fax|4|3', 'RetailDemo|4|3')

New-Tweak -Id 'svc_maps' -Page debloat -Cat 'Services' -Name 'Disable Downloaded Maps Manager' -Impact Low `
  -Desc 'Stops the service that keeps offline maps for the Windows Maps app up to date in the background.' `
  -Svc @('MapsBroker|4|2')

New-Tweak -Id 'svc_insider' -Page debloat -Cat 'Services' -Name 'Disable Insider and Phone Services' -For @('Desktop') -Impact Low `
  -Desc 'Turns off the Windows Insider service and the telephony Phone service. Safe unless you use Insider builds or make calls through Windows.' `
  -Svc @('wisvc|4|3', 'PhoneSvc|4|3')

New-Tweak -Id 'svc_xbox' -Page debloat -Cat 'Services' -Name 'Disable Xbox Services' -Risk Medium -For @() -Impact Low `
  -Desc 'Turns off Xbox Live sign-in, cloud saves and accessory services. Only do this if you never use the Xbox app, Game Pass or Xbox wireless accessories.' `
  -Svc @('XblAuthManager|4|3', 'XblGameSave|4|3', 'XboxNetApiSvc|4|3', 'XboxGipSvc|4|3')

New-Tweak -Id 'svc_spooler' -Page debloat -Cat 'Services' -Name 'Disable Print Spooler' -Risk Medium -For @() -Impact Low `
  -Desc 'Turns off printing support. Only for PCs that never print - office laptops usually need this, so it is never recommended automatically.' `
  -Svc @('Spooler|4|2')

New-Tweak -Id 'svc_remote' -Page debloat -Cat 'Services' -Name 'Disable Remote Registry' -Premium -Impact Low `
  -Desc 'Makes sure nobody on the network can edit this PC''s registry remotely. Usually already off; this keeps it off.' `
  -Svc @('RemoteRegistry|4|4')

# ---------- Apps
New-Tweak -Id 'app_bing' -Page debloat -Cat 'Apps' -Name 'Remove Bing News and Weather' -Impact Medium `
  -Desc 'Uninstalls the News and Weather apps, which refresh in the background and feed the Widgets board.' `
  -Appx @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch')

New-Tweak -Id 'app_games' -Page debloat -Cat 'Apps' -Name 'Remove Solitaire and Pre-installed Games' -Impact Low `
  -Desc 'Uninstalls Microsoft Solitaire Collection and promoted games such as Candy Crush that came with Windows.' `
  -Appx @('Microsoft.MicrosoftSolitaireCollection', 'king.com.*', '*CandyCrush*', '*BubbleWitch*', '*MarchofEmpires*')

New-Tweak -Id 'app_clipchamp' -Page debloat -Cat 'Apps' -Name 'Remove Clipchamp' -Impact Low `
  -Desc 'Uninstalls the Clipchamp video editor. Reinstall it from the Microsoft Store any time.' `
  -Appx @('Clipchamp.Clipchamp')

New-Tweak -Id 'app_officehub' -Page debloat -Cat 'Apps' -Name 'Remove "Microsoft 365 (Office)" Hub App' -Impact Low `
  -Desc 'Removes the Office launcher/advert app only. Installed Word, Excel and Outlook are NOT touched.' `
  -Appx @('Microsoft.MicrosoftOfficeHub')

New-Tweak -Id 'app_help' -Page debloat -Cat 'Apps' -Name 'Remove Get Help, Tips and Feedback Hub' -Impact Low `
  -Desc 'Uninstalls three small Microsoft helper apps that most people never open.' `
  -Appx @('Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.WindowsFeedbackHub')

New-Tweak -Id 'app_teams' -Page debloat -Cat 'Apps' -Name 'Remove Teams Chat (Personal)' -Impact Low `
  -Desc 'Removes the consumer "Chat" Teams app that Windows 11 pre-installs. Teams for work or school is not removed.' `
  -Appx @('MicrosoftTeams')

New-Tweak -Id 'app_cortana' -Page debloat -Cat 'Apps' -Name 'Remove Cortana App' -Impact Low `
  -Desc 'Uninstalls the Cortana app (it has been discontinued by Microsoft).' `
  -Appx @('Microsoft.549981C3F5F10')

New-Tweak -Id 'app_3d' -Page debloat -Cat 'Apps' -Name 'Remove 3D and Mixed Reality Apps' -Impact Low `
  -Desc 'Uninstalls 3D Viewer, Print 3D, 3D Builder and Mixed Reality Portal.' `
  -Appx @('Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.3DBuilder', 'Microsoft.MixedReality.Portal')

New-Tweak -Id 'app_people' -Page debloat -Cat 'Apps' -Name 'Remove People and Maps' -Impact Low `
  -Desc 'Uninstalls the People (contacts) and Windows Maps apps.' `
  -Appx @('Microsoft.People', 'Microsoft.WindowsMaps')

New-Tweak -Id 'app_todo' -Page debloat -Cat 'Apps' -Name 'Remove To Do and Power Automate' -Premium -For @() -Impact Low `
  -Desc 'Uninstalls Microsoft To Do and Power Automate. Skip this if you use them for work.' `
  -Appx @('Microsoft.Todos', 'Microsoft.PowerAutomateDesktop')

New-Tweak -Id 'app_skype' -Page debloat -Cat 'Apps' -Name 'Remove Skype and Old Mail and Calendar' -Premium -Impact Low `
  -Desc 'Removes Skype (shut down by Microsoft) and the retired Mail and Calendar apps. Outlook is not touched.' `
  -Appx @('Microsoft.SkypeApp', 'microsoft.windowscommunicationsapps')

New-Tweak -Id 'app_copilot' -Page debloat -Cat 'Apps' -Name 'Remove Copilot App' -Premium -Impact Low `
  -Desc 'Uninstalls the stand-alone Copilot app.' `
  -Appx @('Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider')

New-Tweak -Id 'app_devhome' -Page debloat -Cat 'Apps' -Name 'Remove Dev Home and Family' -Premium -Impact Low `
  -Desc 'Uninstalls the Dev Home developer dashboard and the Microsoft Family app.' `
  -Appx @('Microsoft.Windows.DevHome', 'MicrosoftCorporationII.MicrosoftFamily')

New-Tweak -Id 'app_phone' -Page debloat -Cat 'Apps' -Name 'Remove Phone Link' -Premium -For @() -Impact Medium `
  -Desc 'Removes Phone Link, which keeps a background process running to sync your phone. Skip if you use it for texts or photos.' `
  -Appx @('Microsoft.YourPhone')

New-Tweak -Id 'app_media' -Page debloat -Cat 'Apps' -Name 'Remove Media Player and Movies and TV' -Premium -Risk Medium -For @() -Impact Low `
  -Desc 'Removes Groove/Media Player and Movies and TV. You will need another player such as VLC for music and video files.' `
  -Appx @('Microsoft.ZuneMusic', 'Microsoft.ZuneVideo')

New-Tweak -Id 'app_xbox' -Page debloat -Cat 'Apps' -Name 'Remove Xbox Apps' -Premium -Risk Medium -For @() -Impact Low `
  -Desc 'Removes the Xbox app, Game Bar and speech overlay. Breaks Game Pass PC and Game Bar - only for people who never use them.' `
  -Appx @('Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay')

# ------------------------------------------------------------------ engine
function Test-Tweak($t) {
    try {
        if ($t.TestCode) { return [bool](& $t.TestCode $t) }
        $ok = $true
        if ($t.Reg.Count -gt 0)  { $ok = $ok -and (Test-RegSpecs $t.Reg) }
        if ($t.Svc.Count -gt 0)  { $ok = $ok -and (Test-SvcSpecs $t.Svc) }
        if ($t.Pwr.Count -gt 0)  { $ok = $ok -and (Test-PwrSpecs $t.Pwr) }
        if ($t.Appx.Count -gt 0) { $ok = $ok -and (Test-AppxGone $t.Appx) }
        return [bool]$ok
    } catch { return $false }
}

function Invoke-TweakApply($t) {
    if ($t.Reg.Count -gt 0)  { Invoke-RegSpecs $t.Id $t.Reg }
    if ($t.Svc.Count -gt 0)  { Invoke-SvcSpecs $t.Id $t.Svc }
    if ($t.Pwr.Count -gt 0)  { Invoke-PwrSpecs $t.Id $t.Pwr }
    if ($t.Appx.Count -gt 0) { Remove-AppxSet $t.Appx }
    if ($t.ApplyCode)        { $null = & $t.ApplyCode $t }
    Add-BackupEntry $t.Id 'mark' '' '' $true $true '' 'applied'
}

function Invoke-TweakRevert($t) {
    if ($t.RevertCode)       { $null = & $t.RevertCode $t }
    if ($t.Appx.Count -gt 0) { Restore-AppxSet $t.Appx }
    if ($t.Reg.Count -gt 0)  { Restore-RegSpecs $t.Id $t.Reg }
    if ($t.Svc.Count -gt 0)  { Restore-SvcSpecs $t.Id $t.Svc }
    if ($t.Pwr.Count -gt 0)  { Restore-PwrSpecs $t.Id $t.Pwr }
    Remove-BackupFor $t.Id
}

function Set-TweakState($t, [bool]$On) {
    try {
        if ($On) { $null = Invoke-TweakApply $t; Write-Log "Applied: $($t.Name)" }
        else     { $null = Invoke-TweakRevert $t; Write-Log "Reverted: $($t.Name)" }
        Save-Backup
        $t.Applied = Test-Tweak $t
        if ($On -and $t.Appx.Count -gt 0) { $t.Applied = $true }
        return @{ Ok = $true; Msg = '' }
    } catch {
        Save-Backup
        $t.Applied = Test-Tweak $t
        $m = $_.Exception.Message
        Write-Log "FAILED $($t.Name): $m"
        return @{ Ok = $false; Msg = $m }
    }
}

function Update-Recommendations {
    $tags = @($Global:CCH.Tags)
    foreach ($t in $Global:Tweaks) {
        $avoid = $false
        foreach ($a in $t.Avoid) { if ($tags -contains $a) { $avoid = $true } }
        $match = $false
        if ($t.For -contains 'All') { $match = $true }
        foreach ($f in $t.For) { if ($tags -contains $f) { $match = $true } }
        if ($t.Id -like 'rbx_*' -and -not ($tags -contains 'Roblox')) { $match = $false }   # Roblox not installed
        if ($avoid) { $t.Reco = 'Avoid' } elseif ($match) { $t.Reco = 'Recommended' } else { $t.Reco = 'Optional' }
    }
}

# ==================================================================================================
#  PC SCANNER
# ==================================================================================================

function Format-GB([double]$Bytes) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }

function Get-GpuVramMap {
    # Win32_VideoController.AdapterRAM is capped at 4 GB, so read the real size from the driver key
    $map = @{}
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $k = Open-Reg $base
    if (-not $k) { return $map }
    foreach ($sub in $k.GetSubKeyNames()) {
        if ($sub -notmatch '^\d{4}$') { continue }
        $p = $base + '\' + $sub
        $desc = (Read-RegValue $p 'DriverDesc').Data
        $q = Read-RegValue $p 'HardwareInformation.qwMemorySize'
        $size = 0
        if ($q.Exists) { $size = [double]$q.Data }
        else {
            $m = Read-RegValue $p 'HardwareInformation.MemorySize'
            if ($m.Exists -and $m.Kind -eq 'DWord') { $size = [double]$m.Data }
        }
        if ($desc -and $size -gt 0 -and -not $map.ContainsKey($desc)) { $map[$desc] = $size }
    }
    $k.Close()
    return $map
}

function Get-SysScan {
    $s = [ordered]@{}

    # ---- CPU
    Set-BusyText 'Scanning processor...' 8
    $cpu = @(Get-CimInstance Win32_Processor)[0]
    $s.CpuName  = (([string]$cpu.Name) -replace '\(R\)|\(TM\)|CPU|\s+@.*$', '' -replace '\s+', ' ').Trim()
    $s.CpuFull  = ([string]$cpu.Name).Trim()
    $s.Cores    = [int]$cpu.NumberOfCores
    $s.Threads  = [int]$cpu.NumberOfLogicalProcessors
    $s.CpuMHz   = [int]$cpu.MaxClockSpeed
    $s.HybridCpu = ($s.CpuFull -match '1[2-4]th Gen|Core\(TM\) Ultra|Core Ultra|Core\(TM\) [3579] [12]\d\d')

    # ---- System / OS
    Set-BusyText 'Reading system information...' 18
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $s.Maker   = ([string]$cs.Manufacturer).Trim()
    $s.Model   = ([string]$cs.Model).Trim()
    $s.OS      = ([string]$os.Caption) -replace 'Microsoft ', ''
    $s.Build   = [int]$os.BuildNumber
    $s.OSVer   = (Read-RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion').Data
    if ($s.Build -ge 22000 -and $s.OS -match 'Windows 10') { $s.OS = $s.OS -replace 'Windows 10', 'Windows 11' }

    # ---- Memory
    Set-BusyText 'Checking memory...' 28
    $mem = @(Get-CimInstance Win32_PhysicalMemory)
    $total = [double](($mem | Measure-Object -Property Capacity -Sum).Sum)
    if (-not $total) { $total = [double]$cs.TotalPhysicalMemory }
    $s.RamBytes   = $total
    $s.RamGB      = [math]::Round($total / 1GB, 1)
    $s.RamModules = $mem.Count
    $speed = 0
    if ($mem.Count) { $speed = [int]$mem[0].ConfiguredClockSpeed; if (-not $speed) { $speed = [int]$mem[0].Speed } }
    $s.RamSpeed = $speed
    $types = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $s.RamType = ''
    if ($mem.Count -and $types.ContainsKey([int]$mem[0].SMBIOSMemoryType)) { $s.RamType = $types[[int]$mem[0].SMBIOSMemoryType] }
    $s.RamFreeGB = [math]::Round([double]([CchNative]::AvailPhys()) / 1GB, 1)

    # ---- GPU(s)
    Set-BusyText 'Detecting graphics...' 40
    $vram = Get-GpuVramMap
    $gpus = @()
    foreach ($g in @(Get-CimInstance Win32_VideoController)) {
        $name = ([string]$g.Name).Trim()
        if (-not $name -or $name -match 'Basic Display|Basic Render|Remote|Virtual|Parsec|Meta Virtual|Citrix|DisplayLink|Mirage') { continue }
        $bytes = 0
        if ($vram.ContainsKey($name)) { $bytes = $vram[$name] } elseif ($g.AdapterRAM) { $bytes = [double][uint32]$g.AdapterRAM }
        $discrete = ($name -match 'NVIDIA|GeForce|Quadro|RTX|GTX|Radeon RX|Radeon Pro|FirePro|Arc\(TM\) A\d|Arc A\d')
        $date = ''
        $ageDays = 0
        if ($g.DriverDate) { try { $d = [datetime]$g.DriverDate; $date = $d.ToString('yyyy-MM-dd'); $ageDays = [int]((Get-Date) - $d).TotalDays } catch { } }
        $gpus += [pscustomobject]@{
            Name = $name; Discrete = [bool]$discrete; VramBytes = $bytes
            Driver = [string]$g.DriverVersion; DriverDate = $date; DriverAge = $ageDays
            ResX = [int]$g.CurrentHorizontalResolution; ResY = [int]$g.CurrentVerticalResolution; Hz = [int]$g.CurrentRefreshRate
        }
    }
    $s.Gpus = $gpus
    $s.HasDGpu = @($gpus | Where-Object { $_.Discrete }).Count -gt 0
    $s.HasIGpu = @($gpus | Where-Object { -not $_.Discrete }).Count -gt 0
    $disp = @($gpus | Where-Object { $_.Hz -gt 0 } | Select-Object -First 1)
    $s.ResX = 0; $s.ResY = 0; $s.Hz = 0
    if ($disp.Count) { $s.ResX = $disp[0].ResX; $s.ResY = $disp[0].ResY; $s.Hz = $disp[0].Hz }
    $main = @($gpus | Where-Object { $_.Discrete }) + @($gpus | Where-Object { -not $_.Discrete })
    $s.MainGpu = ''
    if ($main.Count) { $s.MainGpu = $main[0].Name }

    # ---- Storage
    Set-BusyText 'Checking storage...' 52
    $sysDrive = $env:SystemDrive
    $ld = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $sysDrive + "'")
    $s.DiskSize = [double]$ld.Size
    $s.DiskFree = [double]$ld.FreeSpace
    $s.DiskFreePct = 0
    if ($s.DiskSize) { $s.DiskFreePct = [math]::Round(100 * $s.DiskFree / $s.DiskSize) }
    $s.DiskType = 'Unknown'; $s.DiskBus = ''; $s.DiskModel = ''
    try {
        $part = Get-Partition -DriveLetter $sysDrive.TrimEnd(':') -ErrorAction Stop
        $pd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$part.DiskNumber })[0]
        if ($pd) {
            $s.DiskModel = ([string]$pd.FriendlyName).Trim()
            $s.DiskBus   = [string]$pd.BusType
            $mt = [string]$pd.MediaType
            if ($mt -eq 'SSD' -or $mt -eq '4') { $s.DiskType = 'SSD' }
            elseif ($mt -eq 'HDD' -or $mt -eq '3') { $s.DiskType = 'HDD' }
            elseif ($s.DiskBus -match 'NVMe|17') { $s.DiskType = 'SSD' }
            if ($s.DiskBus -eq '17') { $s.DiskBus = 'NVMe' }
            if ($s.DiskBus -eq '11') { $s.DiskBus = 'SATA' }
        }
    } catch { }

    # ---- Form factor + power
    Set-BusyText 'Checking battery and power...' 62
    $bat = @(Get-CimInstance Win32_Battery)
    $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
    $laptopTypes = @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32)
    $isLaptop = ($bat.Count -gt 0)
    foreach ($c in $chassis) { if ($laptopTypes -contains [int]$c) { $isLaptop = $true } }
    $s.IsLaptop = $isLaptop
    $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
    $s.OnAC = ([string]$ps.PowerLineStatus -ne 'Offline')
    $s.BatteryPct = -1
    if ($bat.Count) { $s.BatteryPct = [int]$bat[0].EstimatedChargeRemaining }
    $planOut = (& powercfg /getactivescheme 2>$null) -join ' '
    $s.PowerPlan = ([regex]::Match($planOut, '\(([^)]+)\)')).Groups[1].Value
    $cs0 = (Read-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'CsEnabled').Data
    $avail = (& powercfg /a 2>$null) -join ' '
    $s.ModernStandby = ($cs0 -eq '1') -or ($avail -match 'S0')

    # ---- Profile tags
    $tags = @('All')
    if ($s.IsLaptop) { $tags += 'Laptop' } else { $tags += 'Desktop' }
    if ($s.HasDGpu) { $tags += 'dGPU' } else { $tags += 'iGPU' }
    if ($s.HasDGpu -and $s.HasIGpu) { $tags += 'Hybrid' }
    if ($s.RamGB -le 8.5) { $tags += 'LowRAM' }
    if ($s.RamGB -le 4.5) { $tags += 'LowRAM4' }
    if ($s.DiskType -eq 'HDD') { $tags += 'HDD' } else { $tags += 'SSD' }
    if ($s.DiskFreePct -lt 15 -or $s.DiskFree -lt 20GB) { $tags += 'LowDisk' }
    if ($s.Threads -le 4) { $tags += 'LowCPU' }
    if ($s.HybridCpu) { $tags += 'HybridCPU' }
    if ($s.ModernStandby) { $tags += 'S0' }
    if ($s.Build -ge 22000) { $tags += 'Win11' } else { $tags += 'Win10' }
    if ((Get-RobloxVersionDirs).Count -gt 0) { $tags += 'Roblox' }
    $lowEnd = (-not $s.HasDGpu) -or $s.RamGB -le 8.5 -or $s.Threads -le 4
    if ($lowEnd) { $tags += 'LowEnd' }
    $s.Tags = $tags

    # ---- Device class
    if ($s.IsLaptop -and $s.HasDGpu)       { $s.Class = 'Gaming Laptop'; $s.ClassSub = 'Laptop with a dedicated graphics card' }
    elseif ($s.IsLaptop -and $lowEnd)      { $s.Class = 'Low-End / Office Laptop'; $s.ClassSub = 'Integrated graphics, built for office work - tuned for maximum FPS' }
    elseif ($s.IsLaptop)                   { $s.Class = 'Thin and Light Laptop'; $s.ClassSub = 'Integrated graphics with plenty of RAM' }
    elseif ($s.HasDGpu)                    { $s.Class = 'Gaming Desktop'; $s.ClassSub = 'Desktop with a dedicated graphics card' }
    else                                   { $s.Class = 'Office / Low-End Desktop'; $s.ClassSub = 'Desktop running on integrated graphics' }

    # ---- Rough gaming score (0-100)
    $score = 0
    $score += [math]::Min(25, $s.Threads * 1.6)
    $score += [math]::Min(20, $s.RamGB * 1.25)
    if ($s.HasDGpu) {
        $dv = (@($gpus | Where-Object { $_.Discrete } | Sort-Object VramBytes -Descending)[0]).VramBytes / 1GB
        $score += [math]::Min(45, 15 + $dv * 3.5)
    } else {
        if ($s.MainGpu -match 'Iris|Arc\(TM\) Graphics|Radeon 7\d0M|Radeon 6\d0M|Radeon \(TM\) Graphics|Vega') { $score += 14 } else { $score += 7 }
    }
    if ($s.DiskType -ne 'HDD') { $score += 10 } else { $score += 3 }
    $s.Score = [int][math]::Min(100, [math]::Round($score))

    # ---- iGPU single-channel detection
    $s.SingleChannel = $false
    if (-not $s.HasDGpu -and $s.MainGpu -match 'UHD' -and $s.CpuFull -match 'i[57]-1[1-4]\d\d(G\d|[UPH])|1[1-4]th Gen Intel\(R\) Core\(TM\) i[57]') { $s.SingleChannel = $true }

    return $s
}

function Get-ScanAdvice($s) {
    $a = @()
    if ($s.SingleChannel) {
        $a += @{ Lvl = 'bad'; T = 'Your RAM is probably running in single-channel'; D = 'Windows reports your graphics as "UHD" instead of "Iris Xe". Intel only enables Iris Xe with two matching RAM sticks. Adding a second identical stick is the single biggest FPS upgrade for this laptop (often 30-80% more FPS).' }
    } elseif (-not $s.HasDGpu -and $s.RamModules -eq 1) {
        $a += @{ Lvl = 'warn'; T = 'Only one RAM module detected'; D = 'Integrated graphics use your RAM as video memory. If your laptop has a free slot, a matching second stick (dual-channel) gives a big FPS boost. Some laptops have soldered RAM that already runs dual-channel.' }
    }
    if ($s.RamGB -le 8.5) {
        $a += @{ Lvl = 'warn'; T = ("{0} GB RAM is tight for big games" -f $s.RamGB); D = 'Close Chrome/Edge, Discord overlays and Teams before playing. Game Boost does this for you. Upgrading to 16 GB (2 x 8 GB) is the best hardware upgrade after dual-channel.' }
    }
    if (-not $s.HasDGpu) {
        $v = 0; if ($s.Gpus.Count) { $v = [math]::Round($s.Gpus[0].VramBytes / 1MB) }
        $a += @{ Lvl = 'info'; T = ("Your ""{0} MB graphics memory"" is normal" -f $v); D = 'Integrated graphics do not have their own memory. Windows shows a small reserved amount (often 128 MB), but the GPU borrows up to half of your system RAM when games need it.' }
    }
    if ($s.IsLaptop -and -not $s.OnAC) {
        $a += @{ Lvl = 'bad'; T = 'You are running on battery'; D = 'Laptops cut CPU and GPU power on battery, often halving FPS. Always plug in the charger to game.' }
    }
    foreach ($g in $s.Gpus) {
        if ($g.DriverAge -gt 365) {
            $a += @{ Lvl = 'warn'; T = "Graphics driver is over a year old ($($g.DriverDate))"; D = "Update the driver for $($g.Name) from the Intel, NVIDIA or AMD website (Tools page has a shortcut). New drivers regularly add FPS and fix stutter." }
        }
    }
    if ($s.Hz -gt 0 -and $s.Hz -le 60) {
        $a += @{ Lvl = 'info'; T = "Your screen runs at $($s.Hz) Hz"; D = 'A 60 Hz screen can only display 60 frames per second. Running at 120 FPS still lowers input delay, but you will not see the extra smoothness without a 120/144 Hz monitor.' }
    }
    if ($s.DiskType -eq 'HDD') {
        $a += @{ Lvl = 'warn'; T = 'Windows is installed on a hard drive (HDD)'; D = 'An SSD makes loading, boot and stutter dramatically better. It is the best value upgrade for an older PC.' }
    }
    if ($s.DiskFreePct -lt 15) {
        $a += @{ Lvl = 'warn'; T = ("Low disk space ({0}% free)" -f $s.DiskFreePct); D = 'Run "Clean temporary files" on the Tools page and remove games you no longer play. Keep at least 15-20% free.' }
    }
    if ($s.HasDGpu -and $s.HasIGpu) {
        $a += @{ Lvl = 'info'; T = 'Two GPUs detected'; D = 'Make sure games use the dedicated GPU: turn on "Roblox: High-Performance GPU" and check Settings > Display > Graphics for other games.' }
    }
    if ($s.IsLaptop) {
        $a += @{ Lvl = 'info'; T = 'Keep it cool'; D = 'Thin laptops slow down when hot. Game on a hard, flat surface (not a bed), keep the vents clear, and consider a cheap cooling pad.' }
    }
    $a += @{ Lvl = 'good'; T = 'Roblox settings that matter most'; D = 'Graphics Mode: Manual, Graphics Quality 1-3, Maximum Frame Rate: 120 or 144. Then turn on the Roblox tweaks in Optimizations.' }
    return $a
}

function Get-ScanExpectation($s) {
    if ($s.HasDGpu) {
        return "With a dedicated GPU, most esports titles (Roblox, Fortnite Performance mode, Valorant, CS2) can run above 120 FPS on low-medium settings. AAA games depend on your exact card - lower the resolution scale first if you are short of your target."
    }
    $t  = "Integrated graphics ($($s.MainGpu)) share your RAM, so FPS depends heavily on dual-channel memory and staying plugged in.`n"
    $t += "Approximate, with low settings and the recommended tweaks:`n"
    $t += "   Roblox (light experiences): 90-160 FPS     Roblox (busy games): 50-90 FPS`n"
    $t += "   Fortnite (Performance mode): 50-80 FPS     Minecraft (Java, with Sodium): 80-150 FPS`n"
    $t += "   Big AAA games: 25-45 FPS at 720p low - many will not reach 60.`n"
    $t += "Tweaks usually add 5-20% and make frame times smoother; they cannot turn integrated graphics into a gaming GPU."
    if ($s.SingleChannel) { $t += "`nSingle-channel RAM detected: expect roughly half these numbers until a second RAM stick is added." }
    return $t
}

function Get-ScanReport($s) {
    $lines = @()
    $lines += 'Kuro PC Report  -  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
    $lines += '=================================================='
    $lines += "Profile    : $($s.Class)   (gaming score $($s.Score)/100)"
    $lines += "Device     : $($s.Maker) $($s.Model)"
    $lines += "OS         : $($s.OS) $($s.OSVer) (build $($s.Build))"
    $lines += "CPU        : $($s.CpuFull)  [$($s.Cores) cores / $($s.Threads) threads]"
    foreach ($g in $s.Gpus) {
        $lines += ("GPU        : {0}  ({1}, {2} MB, driver {3} {4})" -f $g.Name, $(if ($g.Discrete) { 'dedicated' } else { 'integrated' }), [math]::Round($g.VramBytes / 1MB), $g.Driver, $g.DriverDate)
    }
    $lines += ("RAM        : {0} GB {1} {2} MHz, {3} module(s)" -f $s.RamGB, $s.RamType, $s.RamSpeed, $s.RamModules)
    $lines += ("Storage    : {0} {1} {2}, {3} free of {4}" -f $s.DiskModel, $s.DiskBus, $s.DiskType, (Format-GB $s.DiskFree), (Format-GB $s.DiskSize))
    $lines += ("Display    : {0}x{1} @ {2} Hz" -f $s.ResX, $s.ResY, $s.Hz)
    $lines += ("Power      : {0}, plan '{1}', on charger: {2}" -f $(if ($s.IsLaptop) { 'Laptop' } else { 'Desktop' }), $s.PowerPlan, $s.OnAC)
    $lines += "Tags       : $(($s.Tags | Where-Object { $_ -ne 'All' }) -join ', ')"
    $lines += ''
    $lines += 'Advice:'
    foreach ($a in (Get-ScanAdvice $s)) { $lines += ' - ' + $a.T + ': ' + $a.D }
    return ($lines -join "`r`n")
}

# ==================================================================================================
#  PREMIUM LICENSING  (one-time codes)
#  Codes are checked by the Kuro server, which signs each licence with the Kuro licence key. This app
#  ships only the matching PUBLIC key and verifies that signature - no code list and no secret of any
#  kind travel with the app, so a licence file cannot be forged or hand-made. A redeemed code locks to
#  this PC (MachineGuid); moving it to another PC goes through a Kuro account (up to 3 PCs).
# ==================================================================================================

$Global:IntegrityBaseline = '421654e6734e47bda4dd4b04af99605685b00f08e7bdad7976555c57b75bd82a'
$Global:LicFile     = Join-Path $Global:DataDir 'license.dat'
$Global:LicLedgerKey = 'HKLM:\SOFTWARE\Kuro\Redeemed'
# Public half of the Kuro licence-signing key. The private half lives only on the Kuro server, so only
# the server can issue a licence this app will accept. There is no secret in this file to find or reuse.
$Global:LicPubKeyXml = '<RSAKeyValue><Modulus>wPI8IR7NN+nLbo9sWlrNYUWnJRSAZMGyMf41Vau5zFMJ3oq118PkUVjiv7Odaity95xC2NK5dKQPnKglOjCVWUClUX9gA4fR/eVjTxN/ZamPPFjA/ZlNE8SoO8H6xnFOBcfirF9JPJDPwStMsl3ei7/xwehEOpdD03NdODUsAtbHRa/F7JE5uil89Lucj+XwmTJcMKQD8TXoH8NDo1PQYlqlv+LV8umUsso70l1B6qpYhCL7F3E4wD9Rys2Jp5oxv8FGjcxkAiJl3FiMF682lL1rw402skL6JtKp+rAx5LRGJUR4WbLjPkdwNFHp9rPUalEnIEM9KltYWsUvFNXJfQ==</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'

function Get-Sha256Hex([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) } finally { $sha.Dispose() }
    return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}

function ConvertTo-NormalCode([string]$Code) { return (($Code.ToUpperInvariant()) -replace '[^A-Z0-9]', '') }

# Verify a server-signed licence grant. The signed text is exactly  hash|machine|expires  (expires 0 = lifetime).
function Test-GrantSig($Hash, $Machine, $Expires, $Sig) {
    if (-not $Sig -or -not $Hash) { return $false }
    $canonical = '{0}|{1}|{2}' -f $Hash, $Machine, ([int64]$Expires)
    $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
    try { $rsa.FromXmlString($Global:LicPubKeyXml); return $rsa.VerifyData([Text.Encoding]::UTF8.GetBytes($canonical), 'SHA256', [Convert]::FromBase64String($Sig)) }
    catch { return $false } finally { $rsa.Dispose() }
}

function Test-ScriptIntegrity {
    # Verifies the app's own code has not been edited to force Premium. A compiled EXE embeds the
    # source, so it is trusted here; an edited .ps1 fails the check and quietly drops back to Free.
    # This NEVER deletes or damages anything - it only withholds the paid features.
    if ($Global:CchIsExe) { return $true }
    try {
        $path = $Global:CchScriptPath
        if (-not $path -or -not (Test-Path $path)) { return $true }
        $t = [IO.File]::ReadAllText($path)
        $t = $t.Replace("`r`n", "`n")
        $t = [regex]::Replace($t, "IntegrityBaseline = '[0-9a-f]*'", "IntegrityBaseline = ''")
        return ((Get-Sha256Hex $t) -eq $Global:IntegrityBaseline)
    } catch { return $true }
}

function Get-LicenseServer {
    $u = [string]$Global:CCH.Settings.LicenseServer
    if (-not $u) { $u = [string]$Global:DefaultLicenseServer }
    $u = $u.Trim().TrimEnd('/')
    if ($u -and $u -notmatch '^https://') { return '' }
    return $u
}

function Confirm-LicenseOnline {
    # Re-check with the server on startup. Also upgrades an older license.dat to a fresh server-signed
    # one, so buyers from before this version keep Premium. Only drops Premium on a definite
    # 'used elsewhere' / 'revoked' / 'expired' answer; a network problem leaves Premium untouched.
    $url = Get-LicenseServer
    if (-not $url) { return $true }
    $info = Get-LicenseInfo
    if (-not $info) { return $true }
    $r = Invoke-OnlineRedeem ([string]$info.hash) ([string]$info.machine) -ByHash
    if (-not $r.Ok) {
        if ($r.Reason -eq 'used' -or $r.Reason -eq 'invalid' -or $r.Reason -eq 'expired') { return $false }
        return $true
    }
    $exp = [int64]0; if ($info.expires) { $exp = [int64]$info.expires }
    if ($r.Sig -and (Test-GrantSig $info.hash $info.machine $exp $r.Sig) -and -not (Test-GrantSig $info.hash $info.machine $exp $info.sig)) {
        Save-SignedLicense $info.hash $info.machine $exp $r.Days $r.Sig ([string]$info.activated) ([string]$info.code) | Out-Null
    }
    return $true
}

function Repair-LicenseGrant {
    # An older (pre-signing) license.dat, or one restored onto this PC, will not verify. If the Kuro
    # server still recognises this licence for THIS machine, fetch a fresh signed grant and rewrite it.
    # This never grants Premium by itself - the server must agree and the signature must check out.
    if (-not (Get-LicenseServer)) { return $false }
    $info = Get-LicenseInfo
    if (-not $info -or -not $info.hash) { return $false }
    $mid = Get-MachineId
    if ([string]$info.machine -ne $mid) { return $false }
    $r = Invoke-OnlineRedeem ([string]$info.hash) $mid -ByHash
    if (-not $r.Ok -or -not $r.Sig) { return $false }
    $exp = [int64]0
    if ($info.expires) { $exp = [int64]$info.expires }
    if ($r.Expires -gt 0) { $exp = [int64]$r.Expires }
    if (-not (Test-GrantSig $info.hash $mid $exp $r.Sig)) { return $false }
    return (Save-SignedLicense $info.hash $mid $exp $r.Days $r.Sig ([string]$info.activated) ([string]$info.code))
}

function Get-MachineId {
    $g = (Read-RegValue 'HKLM:\SOFTWARE\Microsoft\Cryptography' 'MachineGuid').Data
    if (-not $g) { $g = $env:COMPUTERNAME }
    return (Get-Sha256Hex ('cch-machine|' + $g)).Substring(0, 32)
}

# ------------------------------------------------------------------ timed keys (1 day / 3 days / 1 week)
function Get-NowMs { return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

function Test-TimedCode([string]$Normal) { return ($Normal -match '^K([0-9]D|1M)[A-Z0-9]{12}$') }

function Get-KeyLengthText([int]$Days) {
    switch ($Days) { 1 { '1 day' } 3 { '3 day' } 7 { '1 week' } 30 { '1 month' } default { "$Days day" } }
}

function Get-LicenseExpiry {
    # 0 = lifetime (or no licence); otherwise the end time in Unix milliseconds
    $i = Get-LicenseInfo
    if ($i -and $i.expires) { try { return [int64]$i.expires } catch { } }
    return [int64]0
}

function Test-ClockOk {
    # A timed key must not be stretched by winding the PC clock back. Kuro remembers the latest time
    # it has seen; a clock more than an hour behind that counts as "time is up".
    $now = Get-NowMs
    $mark = [int64]0
    try { $v = (Read-RegValue 'HKLM:\SOFTWARE\Kuro' 'ClockMark').Data; if ($v) { $mark = [int64]$v } } catch { }
    if ($mark -gt 0 -and $now -lt ($mark - 3600000)) { return $false }
    if ($now -gt $mark + 60000) { try { Write-RegValue 'HKLM:\SOFTWARE\Kuro' 'ClockMark' 'String' ([string]$now) } catch { } }
    return $true
}

function Test-LicenseExpired {
    # true when there is a timed licence on this PC and its time is up
    $exp = Get-LicenseExpiry
    if ($exp -le 0) { return $false }
    return ((Get-NowMs) -gt $exp -or -not (Test-ClockOk))
}

function Format-TimeLeft([int64]$Ms) {
    if ($Ms -le 0) { return 'ended' }
    $ts = [TimeSpan]::FromMilliseconds($Ms)
    if ($ts.TotalDays -ge 1) { return ('{0}d {1}h left' -f [math]::Floor($ts.TotalDays), $ts.Hours) }
    if ($ts.TotalHours -ge 1) { return ('{0}h {1}m left' -f [math]::Floor($ts.TotalHours), $ts.Minutes) }
    return ('{0}m left' -f [math]::Max(1, [math]::Ceiling($ts.TotalMinutes)))
}


function Test-CodeRedeemedHere([string]$Hash) {
    if ((Read-RegValue $Global:LicLedgerKey $Hash).Exists) { return $true }
    $ledger = Join-Path $Global:DataDir 'redeemed.dat'
    if ((Test-Path $ledger) -and (@([IO.File]::ReadAllLines($ledger)) -contains $Hash)) { return $true }
    return $false
}

function Add-CodeRedeemedHere([string]$Hash) {
    try { Write-RegValue $Global:LicLedgerKey $Hash 'String' (Get-Date -Format 's') } catch { }
    try { [IO.File]::AppendAllText((Join-Path $Global:DataDir 'redeemed.dat'), $Hash + "`r`n", $Global:Utf8NoBom) } catch { }
}

function Save-SignedLicense($Hash, $Machine, $Expires, $Days, $Sig, $Activated, $CodeMask) {
    if (-not $Activated) { $Activated = Get-Date -Format 's' }
    $lic = [ordered]@{
        product   = $(if ([int64]$Expires -gt 0) { 'Kuro Premium (' + (Get-KeyLengthText $Days) + ' key)' } else { 'Kuro Premium' })
        code      = $(if ($CodeMask) { $CodeMask } else { '(account)' })
        hash      = $Hash
        machine   = $Machine
        activated = $Activated
    }
    if ([int64]$Expires -gt 0) { $lic.days = [int]$Days; $lic.expires = [string]([int64]$Expires) }
    $lic.sig = $Sig
    [IO.File]::WriteAllText($Global:LicFile, (ConvertTo-Json -InputObject $lic), $Global:Utf8NoBom)
    return $true
}

function Test-License {
    if (-not (Test-Path $Global:LicFile)) { return $false }
    try {
        $l = [IO.File]::ReadAllText($Global:LicFile) | ConvertFrom-Json
        if ($l.machine -ne (Get-MachineId)) { return $false }
        $exp = [int64]0; if ($l.expires) { $exp = [int64]$l.expires }
        # The server signed this grant; verify it with the built-in public key. No code list, no secret.
        if (-not (Test-GrantSig $l.hash $l.machine $exp $l.sig)) { return $false }
        if ($exp -gt 0 -and ((Get-NowMs) -gt $exp -or -not (Test-ClockOk))) { return $false }
        return $true
    } catch { return $false }
}

function Confirm-Premium {
    # Re-checks integrity + license every time a paid feature is used, so flipping the in-memory
    # flag or editing the script mid-session cannot unlock anything. Caches the integrity hash once.
    if (-not (Test-ScriptIntegrity)) { $Global:CCH.Premium = $false; $Global:CCH.Tampered = $true; return $false }
    $ok = Test-License
    $Global:CCH.Premium = $ok
    return $ok
}

function Get-LicenseInfo {
    try { return ([IO.File]::ReadAllText($Global:LicFile) | ConvertFrom-Json) } catch { return $null }
}

function Invoke-OnlineRedeem($CodeOrHash, [string]$Machine, [switch]$ByHash) {
    # Ask the Kuro server to redeem a code (ByHash: re-check a licence we already hold). The server
    # validates, locks it to this PC and signs the result; we never compute or hold any code hash.
    $url = Get-LicenseServer
    if (-not $url) { return @{ Ok = $false; Reason = 'noserver' } }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $payload = if ($ByHash) { @{ hash = $CodeOrHash; machine = $Machine } } else { @{ code = $CodeOrHash; machine = $Machine } }
        $body = ConvertTo-Json -InputObject $payload -Compress
        $r = Invoke-RestMethod -Uri ($url + '/redeem') -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop
        $exp = [int64]0; $days = 0
        try { if ($r.expires) { $exp = [int64]$r.expires }; if ($r.days) { $days = [int]$r.days } } catch { }
        return @{ Ok = [bool]$r.ok; Reason = [string]$r.reason; Expires = $exp; Days = $days; Hash = [string]$r.hash; Sig = [string]$r.sig }
    } catch {
        return @{ Ok = $false; Reason = 'network' }
    }
}

function Invoke-Redeem([string]$Code) {
    if (-not (Test-ScriptIntegrity)) { return @{ Ok = $false; Msg = 'This copy of Kuro has been modified, so Premium is disabled. Please download a fresh copy from the official Discord.' } }
    $n = ConvertTo-NormalCode $Code
    $timed = Test-TimedCode $n
    if ($n.Length -ne 15 -or -not ($n.StartsWith('CCH') -or $timed)) { return @{ Ok = $false; Msg = 'That does not look like a Kuro code. Format: CCH-XXXX-XXXX-XXXX (or K1D / K3D / K7D / K1M for timed keys)' } }
    if (-not (Get-LicenseServer)) { return @{ Ok = $false; Msg = 'Kuro needs the internet to check this code. Connect and try again.' } }
    # Don't spend a code if Premium is already active here.
    if (Test-License) {
        $curExp = Get-LicenseExpiry
        if ($curExp -le 0) { return @{ Ok = $false; Msg = 'Lifetime Premium is already active on this PC - keep this code for someone else.' } }
        if ($timed) { return @{ Ok = $false; Msg = ('Your current key still has ' + (Format-TimeLeft ($curExp - (Get-NowMs))) + '. Redeem this one after it ends so you do not lose any time (a lifetime code can be redeemed now).') } }
    }
    $mid = Get-MachineId
    $online = Invoke-OnlineRedeem $Code $mid
    if (-not $online.Ok) {
        switch ($online.Reason) {
            'used'      { return @{ Ok = $false; Msg = 'This code has already been used on another PC.' } }
            'invalid'   { return @{ Ok = $false; Msg = 'Invalid code. Check for typos (codes never contain 0, O, 1 or I).' } }
            'expired'   { return @{ Ok = $false; Msg = 'This key has run out. Get a new one in the Kuro Discord.' } }
            'slow_down' { return @{ Ok = $false; Msg = 'Too many tries from this connection. Wait 10 minutes and try again.' } }
            'noserver'  { return @{ Ok = $false; Msg = 'Kuro needs the internet to check this code. Connect and try again.' } }
            'network'   { return @{ Ok = $false; Msg = 'Could not reach the license server. Check your internet connection and try again.' } }
            default     { return @{ Ok = $false; Msg = 'The license server rejected this code.' } }
        }
    }
    $h = [string]$online.Hash
    $exp = [int64]$online.Expires
    if (-not $h -or -not $online.Sig -or -not (Test-GrantSig $h $mid $exp $online.Sig)) {
        return @{ Ok = $false; Msg = 'The license server sent a reply Kuro could not verify. Update Kuro and try again.' }
    }
    $cur = Get-LicenseInfo
    if ($cur -and $cur.hash -eq $h -and (Test-License)) { return @{ Ok = $true; Msg = 'This code is already active on this PC.' } }
    if ($timed -and $exp -le 0) { return @{ Ok = $false; Msg = 'The license server did not return an end time for this key. Try again in a minute.' } }
    $mask = ($n.Substring(0, 3) + '-' + $n.Substring(3, 4) + '-****-' + $n.Substring(11, 4))
    Save-SignedLicense $h $mid $exp $online.Days $online.Sig (Get-Date -Format 's') $mask | Out-Null
    Add-CodeRedeemedHere $h
    Write-Log "Premium activated with code $mask"
    if ($exp -gt 0) {
        $end = [DateTimeOffset]::FromUnixTimeMilliseconds($exp).LocalDateTime
        return @{ Ok = $true; Msg = ('Premium unlocked until {0:ddd d MMM, HH:mm} ({1}). When it ends, Kuro puts every Premium change back by itself.' -f $end, (Format-TimeLeft ($exp - (Get-NowMs)))) }
    }
    return @{ Ok = $true; Msg = 'Premium unlocked! Thank you for supporting Kuro.' }
}

# ==================================================================================================
#  ACCOUNTS  (optional) - sign up / log in so Premium follows the user across PCs.
#  Requires the owner's licence server (Settings > License server). Passwords are sent over HTTPS and
#  stored only as a salted PBKDF2 hash on the server; this app never stores the password.
# ==================================================================================================

function Write-LocalLicense([string]$Hash, [string]$Machine, [int64]$Expires, [int]$Days, [string]$Sig) {
    # Writes a licence file the app will trust ONLY if the server actually signed this grant.
    if (-not $Hash -or -not $Sig) { return $false }
    if ($Expires -gt 0 -and (Get-NowMs) -gt $Expires) { return $false }   # timed key on the account has run out
    if (-not (Test-GrantSig $Hash $Machine $Expires $Sig)) { return $false }
    Save-SignedLicense $Hash $Machine $Expires $Days $Sig (Get-Date -Format 's') '(account)' | Out-Null
    Write-Log 'Premium restored from account on this PC.'
    return $true
}

function Invoke-AccountApi([string]$Path, $Body) {
    $url = Get-LicenseServer
    if (-not $url) { return @{ ok = $false; reason = 'noserver' } }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $json = ConvertTo-Json -InputObject $Body -Compress
        return Invoke-RestMethod -Uri ($url + $Path) -Method Post -Body $json -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop
    } catch { return @{ ok = $false; reason = 'network' } }
}

$Global:AccErr = @{
    exists = 'That username is already taken.'; bad_username = 'Username must be 3-32 characters: letters, numbers, . _ - only.'
    weak_password = 'Password must be at least 6 characters.'; nouser = 'No account found with that username.'
    badpass = 'Wrong password.'; network = 'Could not reach the account server. Check your internet.'
    noserver = 'No account server is set up yet. The owner must deploy one (see the owner guide).'
    slow_down = 'Too many tries from this connection. Wait 10 minutes and try again.'
}

function Register-Account([string]$User, [string]$Pass) {
    $r = Invoke-AccountApi '/register' @{ username = $User; password = $Pass }
    if ($r.ok) { return @{ Ok = $true; Msg = 'Account created. You can log in now.' } }
    $m = $Global:AccErr[[string]$r.reason]; if (-not $m) { $m = 'Could not create the account.' }
    return @{ Ok = $false; Msg = $m }
}

function Login-Account([string]$User, [string]$Pass) {
    $r = Invoke-AccountApi '/login' @{ username = $User; password = $Pass; machine = (Get-MachineId) }
    if (-not $r.ok) {
        if ([string]$r.reason -eq 'device_limit') {
            $mx = $r.max; if (-not $mx) { $mx = 3 }
            return @{ Ok = $false; Msg = "This account is already active on the maximum number of PCs ($mx). Log out on one of them first, or ask the owner to reset it." }
        }
        $m = $Global:AccErr[[string]$r.reason]; if (-not $m) { $m = 'Could not log in.' }
        return @{ Ok = $false; Msg = $m }
    }
    $Global:CCH.Settings.Account = $User.ToLower(); Save-Settings
    $lic = [string]$r.license
    $msg = 'Logged in. No Premium is linked to this account yet.'
    if ($lic) {
        if (Test-License) { $msg = 'Logged in. Premium is active.' }
        elseif (Write-LocalLicense $lic (Get-MachineId) ([int64]$(if ($r.expires) { $r.expires } else { 0 })) ([int]$(if ($r.days) { $r.days } else { 0 })) ([string]$r.sig)) { $msg = 'Logged in. Premium restored on this PC!' }
        elseif ($r.expires -and [int64]$r.expires -lt (Get-NowMs)) { $msg = 'Logged in, but the timed key on this account has run out.' }
        else { $msg = 'Logged in, but the linked Premium code is not valid in this version.' }
    } elseif (Test-License) {
        $info = Get-LicenseInfo
        if ($info) {
            $lr = Invoke-AccountApi '/link' @{ username = $User; password = $Pass; license = [string]$info.hash }
            if ($lr.ok) { $msg = 'Logged in. Your Premium is now linked to this account.' }
        }
    }
    return @{ Ok = $true; Msg = $msg }
}

function Logout-Account { $Global:CCH.Settings.Account = ''; Save-Settings }

function Update-AccountUI {
    $ui = $Global:UI
    $acct = [string]$Global:CCH.Settings.Account
    if ($acct) {
        $ui.AccUser.Text = $acct
        $ui.BtnLogin.Visibility = 'Collapsed'; $ui.BtnSignup.Visibility = 'Collapsed'; $ui.BtnLogout.Visibility = 'Visible'
        if (-not $ui.AccMsg.Text) { $ui.AccMsg.Text = 'Signed in as ' + $acct + '.' }
    } else {
        $ui.BtnLogin.Visibility = 'Visible'; $ui.BtnSignup.Visibility = 'Visible'; $ui.BtnLogout.Visibility = 'Collapsed'
    }
}

function Connect-Account {
    $ui = $Global:UI
    $set = {
        param($r)
        $Global:UI.AccMsg.Text = $r.Msg
        $Global:UI.AccMsg.Foreground = $Global:CCH.Window.Resources[$(if ($r.Ok) { 'GoodBrush' } else { 'BadBrush' })]
    }
    $ui.BtnSignup.Add_Click({
        if (-not (Get-LicenseServer)) { $Global:UI.AccMsg.Text = $Global:AccErr['noserver']; $Global:UI.AccMsg.Foreground = $Global:CCH.Window.Resources['BadBrush']; return }
        Show-Busy 'Creating your account...'
        $r = Register-Account $Global:UI.AccUser.Text $Global:UI.AccPass.Password
        Hide-Busy; & $set $r
    })
    $ui.BtnLogin.Add_Click({
        if (-not (Get-LicenseServer)) { $Global:UI.AccMsg.Text = $Global:AccErr['noserver']; $Global:UI.AccMsg.Foreground = $Global:CCH.Window.Resources['BadBrush']; return }
        Show-Busy 'Logging in...'
        $r = Login-Account $Global:UI.AccUser.Text $Global:UI.AccPass.Password
        Hide-Busy; & $set $r
        $Global:UI.AccPass.Password = ''
        if ($r.Ok) { Update-PremiumUI; Update-AllViews; Update-AccountUI }
    })
    $ui.BtnLogout.Add_Click({
        Logout-Account
        $Global:UI.AccMsg.Text = 'Logged out on this PC. Your Premium stays active here.'
        $Global:UI.AccMsg.Foreground = $Global:CCH.Window.Resources['SubTextBrush']
        Update-AccountUI
    })
    if ($ui.BtnAccountBuy) { $ui.BtnAccountBuy.Add_Click({ Open-Discord; Show-Toast 'Opening Discord - grab a Premium code, redeem it, then log in to sync it.' 'info' }) }
    Update-AccountUI
}

# ==================================================================================================
#  USER INTERFACE
# ==================================================================================================

$Global:UI = @{}

$Global:BgThemes = [ordered]@{
    'Ink' = @{ Bg = '#141317'; Sidebar = '#17161B'; Panel = '#1C1B21'; Panel2 = '#26242D'; Line = '#302E38'; Text = '#F3F2F6'; Sub = '#9A96A4' }
    'Slate' = @{ Bg = '#0E1116'; Sidebar = '#11151B'; Panel = '#171C24'; Panel2 = '#202833'; Line = '#2C3745'; Text = '#EEF1F5'; Sub = '#8D96A4' }
    'Midnight' = @{ Bg = '#0B0F17'; Sidebar = '#0D121B'; Panel = '#131A26'; Panel2 = '#1A2331'; Line = '#243045'; Text = '#F2F4F8'; Sub = '#8C96AA' }
    'Sakura Night' = @{ Bg = '#190E16'; Sidebar = '#1F121C'; Panel = '#2A1824'; Panel2 = '#3A2130'; Line = '#4E2C40'; Text = '#FCEEF5'; Sub = '#C59BB2' }
    'Charcoal' = @{ Bg = '#121212'; Sidebar = '#161616'; Panel = '#1C1C1E'; Panel2 = '#252528'; Line = '#323236'; Text = '#F4F4F5'; Sub = '#9A9AA2' }
    'Deep Navy' = @{ Bg = '#0A1022'; Sidebar = '#0C1430'; Panel = '#111B3A'; Panel2 = '#182449'; Line = '#24325E'; Text = '#EEF2FF'; Sub = '#8F9BC2' }
    'OLED Black' = @{ Bg = '#000000'; Sidebar = '#050505'; Panel = '#0C0C0C'; Panel2 = '#151515'; Line = '#242424'; Text = '#F5F5F5'; Sub = '#8F8F8F' }
    'Cola' = @{ Bg = '#140B0A'; Sidebar = '#1A0E0D'; Panel = '#231413'; Panel2 = '#2E1B19'; Line = '#422826'; Text = '#FBEFEA'; Sub = '#B39690' }
    'Blossom' = @{ Bg = '#17101A'; Sidebar = '#1D1422'; Panel = '#271B2E'; Panel2 = '#33253B'; Line = '#49374F'; Text = '#FCEEF7'; Sub = '#BBA3C0' }
    'Cotton' = @{ Bg = '#1A1222'; Sidebar = '#20172A'; Panel = '#2B2038'; Panel2 = '#392B49'; Line = '#4E3D63'; Text = '#F6EEFF'; Sub = '#B4A6C8' }
    'Forest' = @{ Bg = '#0A120E'; Sidebar = '#0D1712'; Panel = '#122019'; Panel2 = '#192A21'; Line = '#25392E'; Text = '#EEF6F1'; Sub = '#8FA699' }
}
$Global:Accents = [ordered]@{
    'Rose' = '#E86A9C'; 'Blush' = '#F08FB4'; 'Plum' = '#A86BC7'; 'Amber' = '#E8963C'; 'Steel' = '#5B8DEF'; 'Jade' = '#3FB98A'; 'Cola Red' = '#E53935'; 'Cyber Cyan' = '#22D3EE'; 'Neon Purple' = '#A855F7'
    'Toxic Green' = '#3DDC84'; 'Hot Pink' = '#EC4899'; 'Royal Blue' = '#3B82F6'; 'Gold' = '#FACC15'
    'Mint' = '#2DD4BF'; 'Ice White' = '#E5E7EB'
}
$Global:TagNames = @{
    Laptop = 'Laptop'; Desktop = 'Desktop'; iGPU = 'Integrated graphics'; dGPU = 'Dedicated GPU'; Hybrid = 'Dual GPU'
    LowRAM = '8 GB RAM or less'; LowRAM4 = '4 GB RAM or less'; HDD = 'Hard drive'; SSD = 'SSD'; LowDisk = 'Low disk space'
    Roblox = 'Roblox installed'; LowCPU = '4 threads or less'; HybridCPU = 'Hybrid P/E-core CPU'; S0 = 'Modern Standby'; Win10 = 'Windows 10'; Win11 = 'Windows 11'; LowEnd = 'Low-end tuning'
}
$Global:BoostKill     = @('OneDrive', 'PhoneExperienceHost', 'YourPhone', 'Widgets', 'WidgetService', 'GameBar', 'GameBarFTServer', 'Cortana', 'SkypeApp', 'Teams', 'ms-teams', 'Copilot', 'Microsoft.Photos', 'HxOutlook', 'HxTsr', 'Video.UI', 'Music.UI', 'msedge_webview_host')
$Global:BoostBrowsers = @('chrome', 'msedge', 'firefox', 'opera', 'brave', 'vivaldi')
$Global:BoostGames    = @('RobloxPlayerBeta', 'FortniteClient-Win64-Shipping', 'VALORANT-Win64-Shipping', 'cs2', 'r5apex', 'GTA5', 'Minecraft.Windows', 'javaw', 'RocketLeague', 'FiveM', 'TslGame', 'Overwatch', 'League of Legends', 'GenshinImpact', 'eldenring', 'Warframe.x64', 'destiny2', 'RainbowSix', 'cod', 'FallGuys_client_game')
$Global:OverlayBest   = 'ded574b5-45a0-4f42-8737-46345c09c238'

# ------------------------------------------------------------------ small helpers
function Esc([string]$s) { return [Security.SecurityElement]::Escape([string]$s) }
function Glyph($c) { return '&#x' + ([int][char]$c).ToString('X4') + ';' }
function New-Brush([string]$Hex) {
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($Hex))
    $b.Freeze(); return $b
}
function Set-Res([string]$Key, [System.Windows.Freezable]$Value) {
    # typed parameter unwraps the PowerShell object wrapper - WPF rejects wrapped values in resource dictionaries
    $Global:CCH.Window.Resources[$Key] = $Value
}
function Parse-Xaml([string]$x) { return [Windows.Markup.XamlReader]::Parse($x) }

function Pump-UI {
    try { $Global:CCH.Window.Dispatcher.Invoke([Action] { }, [Windows.Threading.DispatcherPriority]::Background) } catch { }
}

function Show-Busy([string]$Text, [string]$Sub = '') {
    $Global:UI.BusyText.Text = $Text
    $Global:UI.BusySub.Text = $Sub
    $Global:UI.BusyLayer.Visibility = 'Visible'
    Pump-UI
}
function Set-BusyText([string]$Sub, [double]$Pct = -1) {
    if ($Global:UI.ScanLayer -and $Global:UI.ScanLayer.Visibility -eq 'Visible') {
        Set-ScanProgress $Pct $Sub
        Pump-UI
        return
    }
    if ($Global:UI.BusyLayer -and $Global:UI.BusyLayer.Visibility -eq 'Visible') {
        $Global:UI.BusySub.Text = $Sub
        $Global:UI.BusyRotate.Angle = ($Global:UI.BusyRotate.Angle + 30) % 360
        Pump-UI
    }
}
function Hide-Busy { $Global:UI.BusyLayer.Visibility = 'Collapsed' }

$Global:ToastTimer = New-Object Windows.Threading.DispatcherTimer
$Global:ToastTimer.Interval = [TimeSpan]::FromSeconds(4)
$Global:ToastTimer.Add_Tick({ $Global:UI.Toast.Visibility = 'Collapsed'; $Global:ToastTimer.Stop() })

function Show-Toast([string]$Text, [string]$Kind = 'ok') {
    $ui = $Global:UI
    switch ($Kind) {
        'error' { $ui.ToastIcon.Text = [string][char]0xE783; $ui.ToastIcon.Foreground = $Global:CCH.Window.Resources['BadBrush']; $ui.Toast.BorderBrush = $Global:CCH.Window.Resources['BadBrush'] }
        'info'  { $ui.ToastIcon.Text = [string][char]0xE946; $ui.ToastIcon.Foreground = $Global:CCH.Window.Resources['AccentBrush']; $ui.Toast.BorderBrush = $Global:CCH.Window.Resources['AccentBrush'] }
        default { $ui.ToastIcon.Text = [string][char]0xE73E; $ui.ToastIcon.Foreground = $Global:CCH.Window.Resources['GoodBrush']; $ui.Toast.BorderBrush = $Global:CCH.Window.Resources['GoodBrush'] }
    }
    $ui.ToastText.Text = $Text
    $ui.Toast.Visibility = 'Visible'
    $Global:ToastTimer.Stop(); $Global:ToastTimer.Start()
}

function Show-Modal([string]$Title, [string]$Msg, [string]$Yes, [string]$No, [scriptblock]$Action, $Arg = $null, [string]$Icon = 'warn') {
    $ui = $Global:UI
    $ui.ModalTitle.Text = $Title
    $ui.ModalMsg.Text = $Msg
    $ui.ModalYes.Content = $Yes
    if ($No) { $ui.ModalNo.Content = $No; $ui.ModalNo.Visibility = 'Visible' } else { $ui.ModalNo.Visibility = 'Collapsed' }
    if ($Icon -eq 'star') { $ui.ModalIcon.Text = [string][char]0xE735; $ui.ModalIcon.Foreground = $Global:CCH.Window.Resources['AccentBrush'] }
    else { $ui.ModalIcon.Text = [string][char]0xE7BA; $ui.ModalIcon.Foreground = $Global:CCH.Window.Resources['WarnBrush'] }
    $Global:CCH.ModalAction = $Action
    $Global:CCH.ModalArg = $Arg
    $ui.ModalLayer.Visibility = 'Visible'
}

function Show-PremiumPrompt([string]$What) {
    Show-Modal 'Premium feature' ("""$What"" is part of Kuro Premium.`n`nRedeem a one-time code on the Premium page to unlock it, plus every other PRO tweak and Game Boost.") 'Go to Premium' 'Not now' { Show-Page 'PagePremium' } $null 'star'
}

function Invoke-Async([scriptblock]$Script, $Arg, [string]$Text, [string]$Sub = '') {
    Show-Busy $Text $Sub
    $ps = [powershell]::Create()
    [void]$ps.AddScript($Script)
    if ($null -ne $Arg) { [void]$ps.AddArgument($Arg) }
    $h = $ps.BeginInvoke()
    while (-not $h.IsCompleted) {
        $Global:UI.BusyRotate.Angle = ($Global:UI.BusyRotate.Angle + 15) % 360
        Pump-UI
        Start-Sleep -Milliseconds 50
    }
    $res = $null
    try { $res = $ps.EndInvoke($h) } catch { }
    $ps.Dispose()
    Hide-Busy
    return $res
}

# ------------------------------------------------------------------ theme
function Apply-Theme {
    $s = $Global:CCH.Settings
    $t = $Global:BgThemes[[string]$s.Bg]
    if (-not $t) { $t = $Global:BgThemes['Midnight']; $s.Bg = 'Midnight' }
    if ([string]$s.Accent -notmatch '^#[0-9a-fA-F]{6}$') { $s.Accent = '#F7A8C4' }
    Set-Res 'BgBrush' (New-Brush $t.Bg)
    Set-Res 'SidebarBrush' (New-Brush $t.Sidebar)
    Set-Res 'PanelBrush' (New-Brush $t.Panel)
    Set-Res 'Panel2Brush' (New-Brush $t.Panel2)
    Set-Res 'LineBrush' (New-Brush $t.Line)
    Set-Res 'TextBrush' (New-Brush $t.Text)
    Set-Res 'SubTextBrush' (New-Brush $t.Sub)
    $c = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString([string]$s.Accent)
    Set-Res 'AccentBrush' (New-Brush $s.Accent)
    $soft = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, $c.R, $c.G, $c.B)); $soft.Freeze()
    Set-Res 'AccentSoftBrush' ($soft)
    $lum = 0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B
    if ($lum -gt 150) { Set-Res 'OnAccentBrush' (New-Brush '#111111') } else { Set-Res 'OnAccentBrush' (New-Brush '#FFFFFF') }
    # flat, editorial hero: panel colour nudged ~14% toward the accent (no AI-style gradient)
    $pc = [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString([string]$t.Panel)
    $hx = [byte]([math]::Min(255, $pc.R + ($c.R - $pc.R) * 0.16))
    $hy = [byte]([math]::Min(255, $pc.G + ($c.G - $pc.G) * 0.16))
    $hz = [byte]([math]::Min(255, $pc.B + ($c.B - $pc.B) * 0.16))
    $hero = New-Brush ('#{0:X2}{1:X2}{2:X2}' -f $hx, $hy, $hz)
    Set-Res 'HeroBrush' ($hero)
    Update-Swatches
    foreach ($tw in $Global:Tweaks) { Refresh-Tweak $tw }
    try { Update-BoostUI } catch { }
    try { Update-MusicUI } catch { }
}

function Update-Swatches {
    $sel = New-Brush '#FFFFFF'
    foreach ($b in @($Global:UI.AccentSwatches.Children)) {
        if ($b.Tag -eq $Global:CCH.Settings.Accent) { $b.BorderBrush = $sel } else { $b.BorderBrush = [Windows.Media.Brushes]::Transparent }
    }
    foreach ($b in @($Global:UI.BgSwatches.Children)) {
        if ($b.Tag -eq $Global:CCH.Settings.Bg) { $b.BorderBrush = $Global:CCH.Window.Resources['AccentBrush'] } else { $b.BorderBrush = $Global:CCH.Window.Resources['LineBrush'] }
    }
    try { $Global:UI.HexBox.Text = $Global:CCH.Settings.Accent } catch { }
}

function Build-Swatches {
    foreach ($name in $Global:Accents.Keys) {
        $hex = $Global:Accents[$name]
        $b = New-Object Windows.Controls.Border
        $b.Width = 46; $b.Height = 46
        $b.CornerRadius = New-Object Windows.CornerRadius 12
        $b.Margin = New-Object Windows.Thickness 0, 0, 10, 10
        $b.BorderThickness = New-Object Windows.Thickness 3
        $b.Background = New-Brush $hex
        $b.Tag = $hex
        $b.ToolTip = $name
        $b.Cursor = [Windows.Input.Cursors]::Hand
        $b.Add_MouseLeftButtonUp({ $Global:CCH.Settings.Accent = [string]$this.Tag; Apply-Theme; Save-Settings })
        [void]$Global:UI.AccentSwatches.Children.Add($b)
    }
    foreach ($name in $Global:BgThemes.Keys) {
        $t = $Global:BgThemes[$name]
        $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="150" Height="92" CornerRadius="12" BorderThickness="2" Margin="0,0,12,12" Padding="10" Cursor="Hand" Background="$($t.Bg)">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="18"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Background="$($t.Sidebar)" CornerRadius="4" Margin="0,0,4,0"/>
    <StackPanel Grid.Column="1">
      <Border Background="$($t.Panel)" CornerRadius="4" Height="22"/>
      <Border Background="$($t.Panel2)" CornerRadius="4" Height="12" Margin="0,5,20,0"/>
      <TextBlock Text="$(Esc $name)" Foreground="$($t.Text)" FontSize="12" FontWeight="SemiBold" Margin="0,8,0,0"/>
    </StackPanel>
  </Grid>
</Border>
"@
        $b = Parse-Xaml $x
        $b.Tag = $name
        $b.Add_MouseLeftButtonUp({ $Global:CCH.Settings.Bg = [string]$this.Tag; Apply-Theme; Save-Settings })
        [void]$Global:UI.BgSwatches.Children.Add($b)
    }
}

# ------------------------------------------------------------------ navigation
$Global:Pages = @('PageDash', 'PageOptim', 'PageDebloat', 'PageBoost', 'PageScan', 'PageTools', 'PagePremium', 'PageTheme', 'PageSupport', 'PageMacro', 'PageRoblox', 'PagePing', 'PageCross', 'PageGame')
$Global:NavMap = @{ NavDash = 'PageDash'; NavOptim = 'PageOptim'; NavDebloat = 'PageDebloat'; NavBoost = 'PageBoost'; NavScan = 'PageScan'; NavTools = 'PageTools'; NavPremium = 'PagePremium'; NavTheme = 'PageTheme'; NavSupport = 'PageSupport'; NavMacro = 'PageMacro'; NavRoblox = 'PageRoblox'; NavPing = 'PagePing'; NavCross = 'PageCross'; NavGame = 'PageGame' }

function Show-Page([string]$Page) {
    foreach ($p in $Global:Pages) {
        if ($p -eq $Page) { $Global:UI[$p].Visibility = 'Visible'; $Global:UI[$p].ScrollToTop(); Fade-In $Global:UI[$p] } else { $Global:UI[$p].Visibility = 'Collapsed' }
    }
    foreach ($n in $Global:NavMap.Keys) { if ($Global:NavMap[$n] -eq $Page -and -not $Global:UI[$n].IsChecked) { $Global:UI[$n].IsChecked = $true } }
    if ($Page -eq 'PageBoost') { [void](Update-BoostGames) }
    if ($Page -eq 'PageRoblox') { try { Update-RbxNow } catch { } }
    if ($Page -eq 'PagePing') { try { Update-PingPage } catch { } }
    if ($Page -eq 'PageGame') { try { Update-GamePage } catch { } }
}

# ------------------------------------------------------------------ tweak cards
$Global:CardTpl = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="336" Height="236" Margin="0,0,14,14" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="10" Padding="18,16" ToolTip="@TIP">
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <WrapPanel Grid.Row="0" Margin="0,0,0,10">
      <Border Background="{DynamicResource Panel2Brush}" CornerRadius="6" Padding="8,3" Margin="0,0,6,0">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="@CATGLYPH" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,6,0"/>
          <TextBlock Text="@CATNAME" FontSize="11" Foreground="{DynamicResource SubTextBrush}"/>
        </StackPanel>
      </Border>
      <Border Visibility="@PROVIS" Background="{DynamicResource AccentSoftBrush}" CornerRadius="6" Padding="7,3" Margin="0,0,6,0">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="ProIcon" Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,5,0"/>
          <TextBlock Text="PRO" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentBrush}"/>
        </StackPanel>
      </Border>
      <Border Visibility="@RISKVIS" Background="#26FFB020" CornerRadius="6" Padding="7,3" Margin="0,0,6,0"><TextBlock Text="Medium risk" FontSize="11" Foreground="#FFB020"/></Border>
      <Border Visibility="@BOOTVIS" Background="{DynamicResource Panel2Brush}" CornerRadius="6" Padding="7,3"><TextBlock Text="Restart" FontSize="11" Foreground="{DynamicResource SubTextBrush}"/></Border>
    </WrapPanel>
    <TextBlock Grid.Row="1" Text="@TITLE" FontSize="15.5" FontWeight="SemiBold" TextWrapping="Wrap" Foreground="{DynamicResource TextBrush}"/>
    <TextBlock Grid.Row="2" Text="@BODY" FontSize="12.5" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" TextTrimming="CharacterEllipsis" Margin="0,6,0,10" LineHeight="18"/>
    <Grid Grid.Row="3">
      <Border HorizontalAlignment="Left" VerticalAlignment="Center" CornerRadius="6" Padding="8,4" Background="@RBG">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="@RICON" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="@RFG" VerticalAlignment="Center" Margin="0,0,6,0"/>
          <TextBlock Text="@RTEXT" FontSize="11" FontWeight="SemiBold" Foreground="@RFG"/>
        </StackPanel>
      </Border>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <TextBlock x:Name="StateTxt" Text="Activate" VerticalAlignment="Center" Margin="0,0,10,0" FontSize="12" Foreground="{DynamicResource SubTextBrush}"/>
        <CheckBox x:Name="Tgl" Style="{DynamicResource Switch}" VerticalAlignment="Center"/>
      </StackPanel>
    </Grid>
  </Grid>
</Border>
'@

$Global:MiniTpl = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="10" Background="{DynamicResource Panel2Brush}" Padding="14,10" Margin="0,0,0,8">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Margin="0,0,14,0">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="@TITLE" FontWeight="SemiBold" FontSize="14" Foreground="{DynamicResource TextBrush}"/>
        <TextBlock Text="@IMPACT" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource GoodBrush}" Margin="10,2,0,0"/>
        <TextBlock Text="@PRO" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentBrush}" Margin="8,2,0,0"/>
      </StackPanel>
      <TextBlock Text="@BODY" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextTrimming="CharacterEllipsis" Margin="0,3,0,0"/>
    </StackPanel>
    <CheckBox x:Name="Tgl" Grid.Column="1" Style="{DynamicResource Switch}" VerticalAlignment="Center"/>
  </Grid>
</Border>
'@

$Global:ToggleHandler = {
    $t = $this.Tag
    $want = [bool]$this.IsChecked
    $this.IsChecked = $t.Applied
    Request-Tweak $t $want
}

function New-TweakCard($t) {
    switch ($t.Reco) {
        'Recommended' { $rbg = '#263DDC84'; $rfg = '#3DDC84'; $ric = 'E73E'; $rtx = 'Recommended for your PC' }
        'Avoid'       { $rbg = '#26FF5A5F'; $rfg = '#FF6B6B'; $ric = 'E7BA'; $rtx = 'Not recommended for your PC' }
        default       { $rbg = '#228C96AA'; $rfg = '#9AA3B2'; $ric = 'E946'; $rtx = 'Optional' }
    }
    $vis = @{ $true = 'Visible'; $false = 'Collapsed' }
    $x = $Global:CardTpl.Replace('@TIP', (Esc $t.Desc)).Replace('@CATGLYPH', (Glyph $Global:CatIcons[$t.Cat])).Replace('@CATNAME', (Esc $t.Cat))
    $x = $x.Replace('@PROVIS', $vis[[bool]$t.Premium]).Replace('@RISKVIS', $vis[($t.Risk -eq 'Medium')]).Replace('@BOOTVIS', $vis[[bool]$t.Reboot])
    $x = $x.Replace('@TITLE', (Esc $t.Name)).Replace('@BODY', (Esc $t.Desc))
    $x = $x.Replace('@RBG', $rbg).Replace('@RFG', $rfg).Replace('@RICON', ('&#x' + $ric + ';')).Replace('@RTEXT', $rtx)
    $card = Parse-Xaml $x
    $t.Card = $card
    $t.Toggle = $card.FindName('Tgl')
    $t.StateTxt = $card.FindName('StateTxt')
    $t.ProIcon = $card.FindName('ProIcon')
    $t.Toggle.Tag = $t
    $t.Toggle.Add_Click($Global:ToggleHandler)
    Refresh-Tweak $t
    return $card
}

function Refresh-Tweak($t) {
    if (-not $t.Toggle) { return }
    $t.Toggle.IsChecked = [bool]$t.Applied
    if ($t.Applied) { $t.StateTxt.Text = 'Active'; $t.StateTxt.Foreground = $Global:CCH.Window.Resources['GoodBrush'] }
    else { $t.StateTxt.Text = 'Activate'; $t.StateTxt.Foreground = $Global:CCH.Window.Resources['SubTextBrush'] }
    if ($t.ProIcon) { if ($Global:CCH.Premium) { $t.ProIcon.Text = [string][char]0xE735 } else { $t.ProIcon.Text = [string][char]0xE72E } }
}

function Build-Cards {
    foreach ($page in @('optim', 'debloat')) {
        $wrap = $Global:UI[$(if ($page -eq 'optim') { 'OptimWrap' } else { 'DebloatWrap' })]
        $chips = $Global:UI[$(if ($page -eq 'optim') { 'ChipsOptim' } else { 'ChipsDebloat' })]
        $wrap.Children.Clear(); $chips.Children.Clear()
        foreach ($cat in $Global:PageCats[$page]) {
            $n = @($Global:Tweaks | Where-Object { $_.Page -eq $page -and ($cat -eq 'All' -or $_.Cat -eq $cat) }).Count
            $rb = New-Object Windows.Controls.RadioButton
            $rb.Style = $Global:CCH.Window.FindResource('Chip')
            $rb.GroupName = 'chips_' + $page
            $rb.Content = "$cat  ($n)"
            $rb.Tag = $page + '|' + $cat
            if ($cat -eq 'All') { $rb.IsChecked = $true }
            $rb.Add_Checked({ $p = ([string]$this.Tag).Split('|'); $Global:CCH.Filter[$p[0]].Cat = $p[1]; Update-Filter $p[0] })
            [void]$chips.Children.Add($rb)
        }
        $order = @{ 'Recommended' = 0; 'Optional' = 1; 'Avoid' = 2 }
        $list = @($Global:Tweaks | Where-Object { $_.Page -eq $page } | Sort-Object @{ Expression = { $Global:PageCats[$page].IndexOf($_.Cat) } }, @{ Expression = { $order[$_.Reco] } })
        $i = 0
        foreach ($t in $list) {
            [void]$wrap.Children.Add((New-TweakCard $t))
            $i++; if ($i % 8 -eq 0) { Set-BusyText "Building interface... $i" }
        }
        Update-Filter $page
    }
}

function Update-Filter([string]$Page) {
    $f = $Global:CCH.Filter[$Page]
    $shown = 0; $active = 0; $total = 0
    foreach ($t in $Global:Tweaks) {
        if ($t.Page -ne $Page -or -not $t.Card) { continue }
        $total++
        if ($t.Applied) { $active++ }
        $ok = ($f.Cat -eq 'All' -or $t.Cat -eq $f.Cat)
        if ($ok -and $f.RecoOnly) { $ok = ($t.Reco -eq 'Recommended') }
        if ($ok -and $f.Search) { $ok = (($t.Name + ' ' + $t.Desc + ' ' + $t.Cat) -like ('*' + $f.Search + '*')) }
        if ($ok) { $t.Card.Visibility = 'Visible'; $shown++ } else { $t.Card.Visibility = 'Collapsed' }
    }
    $txt = "$shown shown  -  $active of $total active"
    if ($Page -eq 'optim') { $Global:UI.OptimCount.Text = $txt } else { $Global:UI.DebloatCount.Text = $txt }
}

# ------------------------------------------------------------------ applying tweaks
function Ensure-RestorePoint {
    $s = $Global:CCH.Settings
    $today = Get-Date -Format 'yyyy-MM-dd'
    if (-not $s.AutoRestore -or $s.RestoreDay -eq $today) { return }
    $r = New-RestorePoint
    $s.RestoreDay = $today; Save-Settings
}

function New-RestorePoint {
    $script = {
        try {
            Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
            New-ItemProperty -Path $k -Name 'SystemRestorePointCreationFrequency' -Value 0 -PropertyType DWord -Force | Out-Null
            Checkpoint-Computer -Description 'Kuro restore point' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Remove-ItemProperty -Path $k -Name 'SystemRestorePointCreationFrequency' -ErrorAction SilentlyContinue
            'ok'
        } catch { 'fail: ' + $_.Exception.Message }
    }
    $res = [string](@(Invoke-Async $script $null 'Creating a System Restore point...' 'This safety net lets you roll Windows back. It can take up to a minute.') -join '')
    if ($res -eq 'ok') { Write-Log 'System Restore point created.'; return $true }
    Write-Log "Restore point not created ($res). Your per-tweak backups still work."
    return $false
}

function Request-Tweak($t, [bool]$Want) {
    if ($Want -and $t.Premium -and -not (Confirm-Premium)) { Show-PremiumPrompt $t.Name; return }
    if ($Want -and $t.Reco -eq 'Avoid') {
        Show-Modal 'Not recommended for your PC' ($t.Name + "`n`n" + $t.Desc + "`n`nThe scan suggests this tweak does not suit your hardware. Apply it anyway?") 'Apply anyway' 'Cancel' { param($x) Invoke-OneTweak $x $true } $t
        return
    }
    if ($Want -and $t.Risk -eq 'Medium' -and $Global:CCH.Settings.ConfirmRisky) {
        Show-Modal 'Medium-risk tweak' ($t.Name + "`n`n" + $t.Desc + "`n`nYou can switch it off again at any time.") 'Apply' 'Cancel' { param($x) Invoke-OneTweak $x $true } $t
        return
    }
    Invoke-OneTweak $t $Want
}

function Invoke-OneTweak($t, [bool]$Want) {
    if ($Want) { Ensure-RestorePoint }
    $verb = 'Reverting'; if ($Want) { $verb = 'Applying' }
    Show-Busy ($verb + ': ' + $t.Name)
    $r = Set-TweakState $t $Want
    Hide-Busy
    Refresh-Tweak $t
    Update-AllViews
    if ($r.Ok) {
        if ($Want) {
            $m = $t.Name + ' is now active.'
            if ($t.Reboot) { $m += ' Restart your PC to finish.' }
            Show-Toast $m
            Show-Fx 'sparkle' ''
        } else { Show-Toast ($t.Name + ' was switched off and restored.') 'info' }
    } else { Show-Toast ('Could not change "' + $t.Name + '": ' + $r.Msg) 'error' }
}

function Invoke-ManyTweaks($List, [bool]$Want) {
    $List = @($List)
    if ($List.Count -eq 0) { Show-Toast 'Nothing to do - everything is already in place.' 'info'; return }
    if ($Want) { Ensure-RestorePoint }
    $ok = 0; $fail = 0; $reboot = $false; $i = 0
    Show-Busy 'Optimizing your PC...'
    foreach ($t in $List) {
        $i++
        Set-BusyText ("[{0}/{1}]  {2}" -f $i, $List.Count, $t.Name)
        $r = Set-TweakState $t $Want
        if ($r.Ok) { $ok++; if ($t.Reboot) { $reboot = $true } } else { $fail++ }
        Refresh-Tweak $t
        Pump-UI
    }
    Hide-Busy
    Update-AllViews
    $m = "$ok changes done"
    if ($fail) { $m += ", $fail could not be applied (see Tools > Activity log)" }
    if ($reboot -and $Want) { $m += '. Restart your PC to finish.' } else { $m += '.' }
    if ($fail) { Show-Toast $m 'error' } else { Show-Toast $m }
    if ($Want -and $ok -gt 0) { Show-Fx 'success' (("{0}" -f $ok) + ' OPTIMIZED') }
}

function Request-ApplyRecommended([string]$Page = '') {
    $cand = @($Global:Tweaks | Where-Object { $_.Reco -eq 'Recommended' -and -not $_.Applied -and ($Page -eq '' -or $_.Page -eq $Page) })
    $prem = Confirm-Premium
    $locked = @($cand | Where-Object { $_.Premium -and -not $prem })
    $todo = @($cand | Where-Object { -not ($_.Premium -and -not $prem) })
    if ($todo.Count -eq 0) {
        if ($locked.Count) { Show-PremiumPrompt "$($locked.Count) recommended PRO tweaks" } else { Show-Toast 'All recommended optimizations are already active.' }
        return
    }
    $risky = @($todo | Where-Object { $_.Risk -eq 'Medium' })
    $msg = "Kuro will apply $($todo.Count) optimizations picked for your $($Global:CCH.Scan.Class)."
    if ($risky.Count) { $msg += "`n`nIncludes $($risky.Count) medium-risk change(s): " + (($risky | ForEach-Object { $_.Name }) -join ', ') + '.' }
    if ($locked.Count) { $msg += "`n`n$($locked.Count) recommended PRO tweaks are skipped - unlock Premium to include them." }
    $msg += "`n`nEverything is backed up and can be switched off individually."
    Show-Modal 'Apply recommended optimizations?' $msg 'Apply now' 'Cancel' { param($l) Invoke-ManyTweaks $l $true } $todo 'star'
}

# ------------------------------------------------------------------ dashboard
function Set-Ring([double]$Pct) {
    $p = [math]::Max(0.0, [math]::Min(99.99, $Pct))
    $r = 66.0; $cx = 75.0; $cy = 75.0
    $a = $p / 100.0 * 2 * [math]::PI
    $start = New-Object Windows.Point $cx, ($cy - $r)
    $end = New-Object Windows.Point ($cx + $r * [math]::Sin($a)), ($cy - $r * [math]::Cos($a))
    $seg = New-Object Windows.Media.ArcSegment $end, (New-Object Windows.Size $r, $r), 0.0, ($p -gt 50), ([Windows.Media.SweepDirection]::Clockwise), $true
    $fig = New-Object Windows.Media.PathFigure
    $fig.StartPoint = $start
    $fig.IsClosed = $false
    [void]$fig.Segments.Add($seg)
    $geo = New-Object Windows.Media.PathGeometry
    [void]$geo.Figures.Add($fig)
    if ($p -le 0.5) { $Global:UI.RingArc.Data = $null } else { $Global:UI.RingArc.Data = $geo }
}

function Update-Dashboard {
    $ui = $Global:UI
    $reco = @($Global:Tweaks | Where-Object { $_.Reco -eq 'Recommended' })
    $done = @($reco | Where-Object { $_.Applied })
    $pct = 100.0
    if ($reco.Count) { $pct = [math]::Round(100.0 * $done.Count / $reco.Count, 1) }
    Set-Ring $pct
    $ui.RingPct.Text = ('{0}%' -f [math]::Round($pct))
    $ui.OptTitle.Text = ('{0}% Optimized' -f $pct)
    if ($pct -lt 50) { $ui.OptMsg.Text = 'Your PC is not at its top performance' }
    elseif ($pct -lt 95) { $ui.OptMsg.Text = 'Your PC could run smoother' }
    else { $ui.OptMsg.Text = 'Your PC is fully tuned for gaming' }
    $left = $reco.Count - $done.Count
    $ui.OptCount.Text = "$left recommended optimizations found that can make your PC run smoother"
    $ui.StatActive.Text = [string]@($Global:Tweaks | Where-Object { $_.Applied }).Count
    $ui.StatReco.Text = [string]$left

    $ui.DashRecoList.Children.Clear()
    $impact = @{ High = 0; Medium = 1; Low = 2 }
    $top = @($reco | Where-Object { -not $_.Applied } | Sort-Object @{ Expression = { [int]$_.Premium } }, @{ Expression = { $impact[$_.Impact] } } | Select-Object -First 6)
    if ($top.Count -eq 0) {
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = 'All recommended optimizations are active. Nice!'
        $tb.Foreground = $Global:CCH.Window.Resources['GoodBrush']
        $tb.Margin = New-Object Windows.Thickness 0, 4, 0, 4
        [void]$ui.DashRecoList.Children.Add($tb)
    }
    foreach ($t in $top) {
        $pro = ''; if ($t.Premium) { $pro = 'PRO' }
        $x = $Global:MiniTpl.Replace('@TITLE', (Esc $t.Name)).Replace('@IMPACT', ('+' + $t.Impact + ' impact')).Replace('@PRO', $pro).Replace('@BODY', (Esc $t.Desc))
        $row = Parse-Xaml $x
        $tg = $row.FindName('Tgl')
        $tg.Tag = $t
        $tg.IsChecked = [bool]$t.Applied
        $tg.Add_Click($Global:ToggleHandler)
        [void]$ui.DashRecoList.Children.Add($row)
    }
}

function Update-AllViews {
    Update-Dashboard
    Update-Filter 'optim'
    Update-Filter 'debloat'
}

# ------------------------------------------------------------------ live usage
$Global:Perf = @{ Tick = 0 }
# Performance counters can take minutes to initialise on some PCs (third-party counter providers),
# so CPU uses GetSystemTimes and the GPU counters are built on a background thread.
$Global:PerfSync = [hashtable]::Synchronized(@{ Gpu = @(); Busy = $false; Ready = $false; PS = $null })

function Init-Perf {
    [void][CchNative]::CpuPercent()
    Start-GpuRefresh
}

function Start-GpuRefresh {
    $sync = $Global:PerfSync
    if ($sync.Busy) { return }
    $sync.Busy = $true
    if ($sync.PS) { try { $sync.PS.Dispose() } catch { } }
    $ps = [powershell]::Create()
    [void]$ps.AddScript({
        param($sync)
        try {
            $old = $sync.Gpu
            $list = New-Object System.Collections.ArrayList
            $cat = New-Object System.Diagnostics.PerformanceCounterCategory 'GPU Engine'
            foreach ($inst in $cat.GetInstanceNames()) {
                if ($inst -like '*engtype_3D*') {
                    try {
                        $c = New-Object System.Diagnostics.PerformanceCounter 'GPU Engine', 'Utilization Percentage', $inst
                        [void]$c.NextValue()
                        [void]$list.Add($c)
                    } catch { }
                }
            }
            $sync.Gpu = $list.ToArray()
            $sync.Ready = $true
            foreach ($c in @($old)) { try { $c.Dispose() } catch { } }
        } catch { }
        $sync.Busy = $false
    })
    [void]$ps.AddArgument($sync)
    $sync.PS = $ps
    [void]$ps.BeginInvoke()
}

function Update-Usage {
    $ui = $Global:UI
    $cpu = [CchNative]::CpuPercent()
    $ui.UsageCpuBar.Value = $cpu; $ui.UsageCpuTxt.Text = "$cpu%"
    $ram = [int][CchNative]::MemoryLoad()
    $ui.UsageRamBar.Value = $ram; $ui.UsageRamTxt.Text = "$ram%"
    if ($Global:Perf.Tick % 10 -eq 0) { Start-GpuRefresh }
    $g = 0.0
    foreach ($c in @($Global:PerfSync.Gpu)) { try { $g += $c.NextValue() } catch { } }
    $g = [math]::Min(100, [math]::Round($g))
    if (-not $Global:PerfSync.Ready) { $ui.UsageGpuTxt.Text = '...' } else { $ui.UsageGpuTxt.Text = "$g%" }
    $ui.UsageGpuBar.Value = $g
}

# ------------------------------------------------------------------ scanner UI
function New-SpecCard([string]$IconHex, [string]$Title, $Rows) {
    $rowsX = ''
    $i = 0
    foreach ($r in $Rows) {
        $rowsX += '<TextBlock Grid.Row="' + $i + '" Text="' + (Esc $r[0]) + '" Foreground="{DynamicResource SubTextBrush}" Margin="0,0,12,7"/>'
        $rowsX += '<TextBlock Grid.Row="' + $i + '" Grid.Column="1" Text="' + (Esc $r[1]) + '" TextWrapping="Wrap" FontWeight="SemiBold" Margin="0,0,0,7"/>'
        $i++
    }
    $defs = ''
    for ($j = 0; $j -lt $i; $j++) { $defs += '<RowDefinition Height="Auto"/>' }
    $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="352" Margin="0,0,14,16" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="14" Padding="20,18">
  <StackPanel>
    <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
      <Border Width="34" Height="34" CornerRadius="9" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
        <TextBlock Text="&#x$IconHex;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock Text="$(Esc $Title)" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center" Foreground="{DynamicResource TextBrush}"/>
    </StackPanel>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width="104"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions>$defs</Grid.RowDefinitions>
      $rowsX
    </Grid>
  </StackPanel>
</Border>
"@
    return (Parse-Xaml $x)
}

function Update-ScanUI {
    $s = $Global:CCH.Scan
    $ui = $Global:UI
    if (-not $s) { return }
    $ui.ScanClass.Text = $s.Class
    $ui.ScanClassSub.Text = "$($s.ClassSub)  -  $($s.Maker) $($s.Model)"
    $ui.ScanScore.Text = [string]$s.Score
    $ui.ScanTags.Children.Clear()
    foreach ($tg in $s.Tags) {
        if ($tg -eq 'All' -or -not $Global:TagNames.ContainsKey($tg)) { continue }
        $x = '<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Background="{DynamicResource Panel2Brush}" CornerRadius="7" Padding="10,4" Margin="0,0,8,6"><TextBlock Text="' + (Esc $Global:TagNames[$tg]) + '" FontSize="12" Foreground="{DynamicResource TextBrush}"/></Border>'
        [void]$ui.ScanTags.Children.Add((Parse-Xaml $x))
    }

    $ui.ScanCards.Children.Clear()
    $cpuRows = @(@('Model', $s.CpuFull), @('Cores', ("{0} cores / {1} threads" -f $s.Cores, $s.Threads)), @('Base clock', ("{0:N2} GHz" -f ($s.CpuMHz / 1000))))
    if ($s.HybridCpu) { $cpuRows += , @('Design', 'Hybrid (Performance + Efficient cores)') }
    [void]$ui.ScanCards.Children.Add((New-SpecCard 'E945' 'Processor' $cpuRows))

    foreach ($g in $s.Gpus) {
        $kind = 'Integrated (shares system RAM)'; if ($g.Discrete) { $kind = 'Dedicated graphics card' }
        $vr = ('{0} MB' -f [math]::Round($g.VramBytes / 1MB))
        if ($g.VramBytes -ge 1GB) { $vr = ('{0:N1} GB' -f ($g.VramBytes / 1GB)) }
        if (-not $g.Discrete) { $vr += (' reserved, up to {0:N1} GB shared' -f ($s.RamBytes / 2 / 1GB)) }
        $rows = @(@('Model', $g.Name), @('Type', $kind), @('Video memory', $vr), @('Driver', ("{0} ({1})" -f $g.Driver, $g.DriverDate)))
        [void]$ui.ScanCards.Children.Add((New-SpecCard 'E7F4' 'Graphics' $rows))
    }

    $ramDesc = ("{0} GB" -f $s.RamGB); if ($s.RamType) { $ramDesc += " $($s.RamType)" }
    $ch = 'Dual-channel likely'; if ($s.SingleChannel) { $ch = 'Single-channel (upgrade!)' } elseif ($s.RamModules -eq 1) { $ch = 'Possibly single-channel' }
    $ramRows = @(@('Installed', $ramDesc), @('Speed', ("{0} MHz" -f $s.RamSpeed)), @('Modules', ("{0} stick(s)  -  {1}" -f $s.RamModules, $ch)), @('Free now', ("{0} GB" -f $s.RamFreeGB)))
    [void]$ui.ScanCards.Children.Add((New-SpecCard 'EC4A' 'Memory' $ramRows))

    $diskRows = @(@('Drive', $(if ($s.DiskModel) { $s.DiskModel } else { 'System drive' })), @('Type', (($s.DiskBus + ' ' + $s.DiskType).Trim())), @('Capacity', (Format-GB $s.DiskSize)), @('Free', ("{0} ({1}%)" -f (Format-GB $s.DiskFree), $s.DiskFreePct)))
    [void]$ui.ScanCards.Children.Add((New-SpecCard 'EDA2' 'Storage' $diskRows))

    $sysRows = @(@('Device', ("{0} {1}" -f $s.Maker, $s.Model)), @('Windows', ("{0} {1}" -f $s.OS, $s.OSVer)), @('Build', [string]$s.Build))
    [void]$ui.ScanCards.Children.Add((New-SpecCard 'E770' 'System' $sysRows))

    $pw = 'Plugged in'; if (-not $s.OnAC) { $pw = 'On battery' }
    if ($s.BatteryPct -ge 0) { $pw += " ($($s.BatteryPct)%)" }
    $dispRows = @(@('Resolution', ("{0} x {1}" -f $s.ResX, $s.ResY)), @('Refresh rate', ("{0} Hz" -f $s.Hz)), @('Power', $pw), @('Power plan', $s.PowerPlan))
    [void]$ui.ScanCards.Children.Add((New-SpecCard 'E7F8' 'Display and Power' $dispRows))

    $ui.ScanExpect.Text = Get-ScanExpectation $s

    $ui.ScanAdvice.Children.Clear()
    $colors = @{ bad = '#FF5A5F'; warn = '#FFB020'; info = '#3B82F6'; good = '#3DDC84' }
    foreach ($a in (Get-ScanAdvice $s)) {
        $x = @"
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Background="{DynamicResource Panel2Brush}" CornerRadius="10" Margin="0,0,0,10" Padding="0">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="4"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <Border Background="$($colors[$a.Lvl])" CornerRadius="10,0,0,10"/>
    <StackPanel Grid.Column="1" Margin="16,12">
      <TextBlock Text="$(Esc $a.T)" FontWeight="SemiBold" FontSize="14" Foreground="{DynamicResource TextBrush}" TextWrapping="Wrap"/>
      <TextBlock Text="$(Esc $a.D)" FontSize="12.5" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,4,0,0" LineHeight="18"/>
    </StackPanel>
  </Grid>
</Border>
"@
        [void]$ui.ScanAdvice.Children.Add((Parse-Xaml $x))
    }

    $ui.DashDevice.Text = $s.Class
    $ui.DashWelcome.Text = "Tuned for your $($s.Maker) $($s.Model)"
    $ui.HwClass.Text = $s.Class
    $ui.HwCpu.Text = "CPU:  $($s.CpuName)  ($($s.Cores)C / $($s.Threads)T)"
    $ui.HwGpu.Text = "GPU:  $($s.MainGpu)"
    $ui.HwRam.Text = "RAM:  $($s.RamGB) GB $($s.RamType)"
    $ui.HwDisk.Text = ("Storage:  {0} {1}, {2} free" -f (Format-GB $s.DiskSize), $s.DiskType, (Format-GB $s.DiskFree))
}

function Invoke-FullScan {
    Show-ScanLayer 'Getting things ready...'
    Update-AppxCache
    $Global:CCH.Scan = Get-SysScan
    $Global:CCH.Tags = $Global:CCH.Scan.Tags
    Update-Recommendations
    Set-BusyText 'Checking which optimizations are already active...' 66
    $i = 0
    $n = [Math]::Max(1, $Global:Tweaks.Count)
    foreach ($t in $Global:Tweaks) {
        $t.Applied = Test-Tweak $t
        $i++; if ($i % 6 -eq 0) { Set-BusyText ("Checking optimizations... {0}/{1}" -f $i, $Global:Tweaks.Count) (66 + 24 * $i / $n) }
    }
    Update-ScanUI
}

# ------------------------------------------------------------------ tools
function Invoke-FreeRam {
    $before = [double][CchNative]::AvailPhys()
    foreach ($p in [Diagnostics.Process]::GetProcesses()) {
        if ($Global:BoostGames -contains $p.ProcessName) { continue }
        try { [void][CchNative]::EmptyWorkingSet($p.Handle) } catch { }
    }
    Start-Sleep -Milliseconds 400
    $after = [double][CchNative]::AvailPhys()
    return [int][math]::Max(0, [math]::Round(($after - $before) / 1MB))
}

function Invoke-CleanTemp {
    $script = {
        $paths = @(
            $env:TEMP,
            (Join-Path $env:SystemRoot 'Temp'),
            (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'),
            (Join-Path $env:LOCALAPPDATA 'Roblox\logs'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
            (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
            (Join-Path $env:SystemRoot 'SoftwareDistribution\Download')
        )
        $freed = 0.0
        $cut = (Get-Date).AddHours(-12)
        foreach ($p in $paths) {
            if (-not $p -or -not (Test-Path $p)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue)) {
                if ($f.LastWriteTime -gt $cut) { continue }
                $len = $f.Length
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
            }
            foreach ($d in @(Get-ChildItem -LiteralPath $p -Recurse -Force -Directory -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
                try { if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue } } catch { }
            }
        }
        [math]::Round($freed / 1MB)
    }
    $mb = [string](@(Invoke-Async $script $null 'Cleaning temporary files...' 'Files in use are skipped automatically.') -join '')
    Write-Log "Temp clean-up freed $mb MB."
    Show-Toast "Cleaned $mb MB of temporary files."
}

$Global:ToolDefs = @(
    @{ Id = 'restore'; Icon = 'E777'; Title = 'Create restore point'; Desc = 'Snapshot Windows so you can roll back any change.' }
    @{ Id = 'temp'; Icon = 'EA99'; Title = 'Clean temporary files'; Desc = 'Clear temp, crash dumps, old update downloads and Roblox logs.' }
    @{ Id = 'ram'; Icon = 'EC4A'; Title = 'Free up RAM'; Desc = 'Trim background apps so your game has more memory.' }
    @{ Id = 'dns'; Icon = 'E701'; Title = 'Flush DNS cache'; Desc = 'Fixes "can''t connect" errors after network changes.' }
    @{ Id = 'startup'; Icon = 'E7E8'; Title = 'Startup apps'; Desc = 'Open Windows settings to turn off apps that start with your PC.' }
    @{ Id = 'graphics'; Icon = 'E7F4'; Title = 'Graphics settings'; Desc = 'Choose which GPU each game uses (Windows Graphics settings).' }
    @{ Id = 'driver'; Icon = 'E896'; Title = 'Update GPU driver'; Desc = 'Open the right driver page for your graphics card.' }
    @{ Id = 'report'; Icon = 'E8A5'; Title = 'Save PC report'; Desc = 'Save your scan to a text file on the Desktop.' }
    @{ Id = 'shortcut'; Icon = 'E71B'; Title = 'Desktop shortcut'; Desc = 'Add Kuro to the Desktop and Start menu.' }
    @{ Id = 'record'; Icon = 'E7C8'; Title = 'Record screen'; Desc = 'Capture your gameplay to your Videos folder (uses the Windows recorder).' }
    @{ Id = 'ping'; Icon = 'E701'; Title = 'Ping and region test'; Desc = 'Measure your latency to major servers and see what is realistic.' }
    @{ Id = 'update'; Icon = 'E777'; Title = 'Check for updates'; Desc = 'Download the newest files from the official source and apply on restart.' }
    @{ Id = 'folder'; Icon = 'E838'; Title = 'Open backup folder'; Desc = 'See the backup, settings, license and log files.' }
    @{ Id = 'revert'; Icon = 'E7A7'; Title = 'Revert everything'; Desc = 'Switch off every tweak Kuro has applied.' }
)

function Build-Tools {
    foreach ($d in $Global:ToolDefs) {
        $x = @"
<Button xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="262" Height="128" Margin="0,0,14,14">
  <StackPanel>
    <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" HorizontalAlignment="Left">
      <TextBlock Text="&#x$($d.Icon);" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <TextBlock Text="$(Esc $d.Title)" FontSize="14.5" FontWeight="SemiBold" Margin="0,10,0,0" Foreground="{DynamicResource TextBrush}"/>
    <TextBlock Text="$(Esc $d.Desc)" FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource SubTextBrush}" Margin="0,3,0,0"/>
  </StackPanel>
</Button>
"@
        $b = Parse-Xaml $x
        $b.Style = $Global:CCH.Window.FindResource('TileBtn')
        $b.Tag = $d.Id
        $b.Add_Click({ Invoke-Tool ([string]$this.Tag) })
        [void]$Global:UI.ToolsWrap.Children.Add($b)
    }
}

function New-AppShortcuts {
    $shell = New-Object -ComObject WScript.Shell
    $icon = Join-Path $Global:AppDir 'assets\Kuro.ico'
    $exe = Join-Path $Global:AppDir 'Kuro.exe'
    $ps1 = Join-Path $Global:AppDir 'Kuro.ps1'
    $places = @(
        [Environment]::GetFolderPath('Desktop'),
        (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs')
    )
    foreach ($dir in $places) {
        if (-not $dir -or -not (Test-Path $dir)) { continue }
        $lnk = $shell.CreateShortcut((Join-Path $dir 'Kuro.lnk'))
        # always the script: it is the file auto-update keeps current (an exe would hand over to it anyway)
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $ps1 + '"'
        $lnk.WindowStyle = 7
        $lnk.WorkingDirectory = $Global:AppDir
        if (Test-Path $icon) { $lnk.IconLocation = $icon + ',0' }
        $lnk.Description = 'Kuro FPS Optimizer'
        $lnk.Save()
    }
    Write-Log 'Desktop and Start menu shortcuts created.'
}

# Old ColaCatHub shortcuts would keep opening the old copy; swap them (and Kuro shortcuts that point at
# a frozen Kuro.exe) for shortcuts to this copy. Only touches shortcuts with those exact names.
function Update-LegacyShortcuts {
    try {
        $places = @([Environment]::GetFolderPath('Desktop'), (Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Microsoft\Windows\Start Menu\Programs'))
        $shell = New-Object -ComObject WScript.Shell
        $need = $false
        foreach ($dir in $places) {
            if (-not $dir -or -not (Test-Path $dir)) { continue }
            $old = Join-Path $dir 'ColaCatHub.lnk'
            if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue; $need = $true; Write-Log "Removed old shortcut $old" }
            $cur = Join-Path $dir 'Kuro.lnk'
            if (Test-Path -LiteralPath $cur) {
                $l = $shell.CreateShortcut($cur)
                $tgt = [string]$l.TargetPath
                $file = $null
                if ([string]$l.Arguments -match '-File "([^"]+)"') { $file = $Matches[1] }
                # repoint only shortcuts that open a frozen exe or a copy that no longer exists
                if ($tgt -like '*Kuro.exe' -or -not (Test-Path -LiteralPath $tgt) -or ($file -and -not (Test-Path -LiteralPath $file))) { $need = $true }
            }
        }
        if ($need) { New-AppShortcuts }
    } catch { Write-Log "Shortcut update failed: $($_.Exception.Message)" }
}

function Invoke-ScreenRecord {
    try { [CchNative]::GameBarRecord() } catch { Show-Toast 'Could not reach the Windows recorder.' 'error'; return }
    $Global:CCH.Recording = -not [bool]$Global:CCH.Recording
    if ($Global:CCH.Recording) {
        Write-Log 'Screen recording started (Windows Game Bar).'
        Show-Toast 'Recording started. Press Record again to stop - the clip saves to Videos\Captures.' 'info'
    } else {
        Write-Log 'Screen recording stopped.'
        $cap = Join-Path ([Environment]::GetFolderPath('MyVideos')) 'Captures'
        Show-Toast 'Recording stopped and saved to your Videos\Captures folder.'
        if (Test-Path $cap) { Start-Process 'explorer.exe' $cap }
    }
}

function Get-GatewayIP {
    try { $g = (Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1).IPv4DefaultGateway.NextHop; if ($g) { return $g } } catch { }
    try { foreach ($l in (& ipconfig 2>$null)) { if ($l -match 'Default Gateway.*?:\s*([0-9]{1,3}(\.[0-9]{1,3}){3})') { return $Matches[1] } } } catch { }
    return ''
}

function Invoke-PingTest {
    $targets = @(
        @{ N = 'Your router (LAN)'; H = (Get-GatewayIP) },
        @{ N = 'Cloudflare (1.1.1.1)'; H = '1.1.1.1' },
        @{ N = 'Google (8.8.8.8)'; H = '8.8.8.8' },
        @{ N = 'OpenDNS'; H = '208.67.222.222' }
    )
    Show-Busy 'Testing your connection...' 'Pinging servers, this takes a few seconds'
    $lines = @(); $best = 999999
    foreach ($t in $targets) {
        if (-not $t.H) { continue }
        Set-BusyText ('Pinging ' + $t.N + '...')
        try {
            $r = @(Test-Connection -ComputerName $t.H -Count 4 -ErrorAction Stop)
            $ms = @($r | ForEach-Object { if ($null -ne $_.ResponseTime) { [int]$_.ResponseTime } elseif ($null -ne $_.Latency) { [int]$_.Latency } })
            if ($ms.Count) {
                $avg = [int](($ms | Measure-Object -Average).Average)
                if ($avg -lt $best) { $best = $avg }
                $lines += ('{0,-22} {1} ms avg   (min {2}, max {3})' -f $t.N, $avg, ($ms | Measure-Object -Minimum).Minimum, ($ms | Measure-Object -Maximum).Maximum)
            } else { $lines += ('{0,-22} replied, no timing' -f $t.N) }
        } catch { $lines += ('{0,-22} no response' -f $t.N) }
    }
    Hide-Busy
    $tz = ''
    try { $tz = [TimeZoneInfo]::Local.DisplayName } catch { }
    $msg = ($lines -join "`n") + "`n`nTime zone / region: $tz`n`n"
    $msg += "Your ping to a game server depends on how far away that server is and your ISP's routing. "
    $msg += "The LAN number above is your PC-to-router latency; the internet numbers are the realistic floor to nearby servers. "
    $msg += "Kuro's network tweaks (Optimizations > Network) reduce jitter and spikes, but no app can beat the distance to the server - single-digit ping only happens when the server is physically very close to you."
    Write-Log ('Ping test: best ' + $best + ' ms. ' + ($lines -join ' | '))
    Show-Modal 'Ping and region test' $msg 'Close' '' $null $null 'info'
}

function Invoke-Tool([string]$Id) {
    switch ($Id) {
        'restore' { if (New-RestorePoint) { Show-Toast 'System Restore point created.' } else { Show-Toast 'Windows did not create a restore point (System Protection may be off). See the activity log.' 'error' } }
        'temp'    { Invoke-CleanTemp }
        'ram'     { Show-Busy 'Freeing RAM...'; $mb = Invoke-FreeRam; Hide-Busy; Write-Log "Freed $mb MB of RAM."; Show-Toast "Freed about $mb MB of RAM."; Show-Fx 'sparkle' '' }
        'dns'     { & ipconfig /flushdns 2>$null | Out-Null; Write-Log 'DNS cache flushed.'; Show-Toast 'DNS cache flushed.'; Show-Fx 'sparkle' '' }
        'startup' { Start-Process 'ms-settings:startupapps' }
        'graphics' { Start-Process 'ms-settings:display-advancedgraphics' }
        'driver' {
            $g = [string]$Global:CCH.Scan.MainGpu
            $url = 'https://www.intel.com/content/www/us/en/support/detect.html'
            if ($g -match 'NVIDIA|GeForce|RTX|GTX') { $url = 'https://www.nvidia.com/en-us/drivers/' }
            elseif ($g -match 'AMD|Radeon') { $url = 'https://www.amd.com/en/support/download/drivers.html' }
            Start-Process $url
        }
        'report' {
            $f = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Kuro-PC-Report.txt'
            [IO.File]::WriteAllText($f, (Get-ScanReport $Global:CCH.Scan), $Global:Utf8NoBom)
            Write-Log "Report saved to $f"; Show-Toast 'Report saved to your Desktop.'
        }
        'record'  { Invoke-ScreenRecord }
        'ping'    { Invoke-PingTest }
        'update'  { Invoke-Update $false }
        'folder'  { Start-Process 'explorer.exe' $Global:DataDir }
        'shortcut' { try { New-AppShortcuts; Show-Toast 'Kuro shortcuts added to your Desktop and Start menu.' } catch { Show-Toast ('Could not create shortcuts: ' + $_.Exception.Message) 'error' } }
        'revert'  {
            $ids = Get-BackupTweakIds
            $list = @($Global:Tweaks | Where-Object { $ids -contains $_.Id })
            if ($list.Count -eq 0) { Show-Toast 'Kuro has not changed anything yet.' 'info'; return }
            Show-Modal 'Revert everything?' "This switches off all $($list.Count) tweaks Kuro applied and restores your original settings. Removed apps are re-registered where Windows still has them." 'Revert all' 'Cancel' { param($l) Invoke-ManyTweaks $l $false } $list
        }
    }
}

# ------------------------------------------------------------------ premium UI
function Update-PremiumUI {
    $Global:CCH.Tampered = -not (Test-ScriptIntegrity)
    # A licence from before signed grants (or one just restored) won't verify yet: ask the server to
    # re-sign it for this PC so existing buyers keep Premium without doing anything.
    if (-not $Global:CCH.Tampered -and (Test-Path $Global:LicFile) -and -not (Test-License)) { Repair-LicenseGrant | Out-Null }
    $Global:CCH.Premium = (Test-License) -and (-not $Global:CCH.Tampered)
    if ($Global:CCH.Premium -and -not (Confirm-LicenseOnline)) {
        $Global:CCH.Premium = $false
        if ((Get-LicenseExpiry) -gt 0) { Request-PremiumExpiry }   # server says the timed key is over: revert like a normal expiry
        else { try { Remove-Item -LiteralPath $Global:LicFile -Force -ErrorAction SilentlyContinue } catch { } }
        Write-Log 'License was rejected by the license server (used on another PC, revoked or expired). Premium disabled.'
    }
    if ($Global:CCH.Tampered) { Write-Log 'Integrity check failed: the script was modified. Premium features are locked.' }
    if (-not $Global:CCH.Premium -and (Test-LicenseExpired)) { Request-PremiumExpiry }
    Start-PremiumClock
    $ui = $Global:UI
    if ($Global:CCH.Premium) {
        $info = Get-LicenseInfo
        $exp = Get-LicenseExpiry
        $ui.TitlePlan.Text = 'PREMIUM'
        $ui.StatPremium.Text = 'Premium'
        $ui.StatPremiumSub.Text = 'All features unlocked'
        $ui.PremStatus.Text = 'Premium is active on this PC'
        $ui.PremSub.Text = "Code $($info.code)  -  activated $(([string]$info.activated).Replace('T', ' '))"
        if ($exp -gt 0) {
            $left = Format-TimeLeft ($exp - (Get-NowMs))
            $end = [DateTimeOffset]::FromUnixTimeMilliseconds($exp).LocalDateTime
            $ui.StatPremiumSub.Text = 'Timed key: ' + $left
            $ui.PremStatus.Text = 'Premium is active on this PC  -  ' + $left
            $ui.PremSub.Text = ('{0} key {1}  -  ends {2:ddd d MMM, HH:mm}. When it ends Kuro puts every Premium change back by itself. A lifetime code can be redeemed any time to upgrade.' -f (Get-KeyLengthText ([int]$info.days)), $info.code, $end)
        }
        # a timed key can be upgraded to lifetime, so keep the code box open for it
        $ui.BtnRedeem.IsEnabled = ($exp -gt 0)
        $ui.CodeBox.IsEnabled = ($exp -gt 0)
        $ui.BoostSub.Text = 'Ready when you are'
    } else {
        $ui.TitlePlan.Text = 'FREE'
        $ui.StatPremium.Text = 'Free'
        $ui.StatPremiumSub.Text = 'Redeem a code to unlock Premium'
        $ui.PremStatus.Text = "You're on the Free plan"
        $ui.PremSub.Text = 'Redeem a one-time code to unlock every PRO tweak, Game Boost and one-click optimize with PRO tweaks included.'
        $ui.BtnRedeem.IsEnabled = $true
        $ui.CodeBox.IsEnabled = $true
        $ui.BoostSub.Text = 'Premium feature - unlock it on the Premium page'
    }
    foreach ($t in $Global:Tweaks) { Refresh-Tweak $t }
    try { Step-PremiumGate } catch { Write-Log "Premium gate: $($_.Exception.Message)" }

    $ui.PerksList.Children.Clear()
    $free = @($Global:Tweaks | Where-Object { -not $_.Premium }).Count
    $pro = @($Global:Tweaks | Where-Object { $_.Premium }).Count
    $perks = @(
        @('Free', 'PC scanner, hardware advice and FPS expectations'),
        @('Free', "$free optimizations and debloat tweaks"),
        @('Free', 'Colour themes and live usage monitor'),
        @('PRO', "$pro advanced PRO tweaks (scheduler, CPU boost, network, Roblox ultra-low mode...)"),
        @('PRO', 'Game Boost: one-click RAM, power and priority boost before you play'),
        @('PRO', 'Stream proof: hide Kuro, its Game Bar and crosshair from captures and screen share'),
        @('PRO', 'One-click "Apply all recommended" includes PRO tweaks')
    )
    foreach ($p in $perks) {
        $col = '{DynamicResource GoodBrush}'; if ($p[0] -eq 'PRO') { $col = '{DynamicResource AccentBrush}' }
        $x = @"
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Margin="0,0,0,10">
  <Grid.ColumnDefinitions><ColumnDefinition Width="56"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <Border CornerRadius="6" Padding="6,2" HorizontalAlignment="Left" VerticalAlignment="Top" Background="{DynamicResource Panel2Brush}">
    <TextBlock Text="$($p[0])" FontSize="11" FontWeight="Bold" Foreground="$col"/>
  </Border>
  <TextBlock Grid.Column="1" Text="$(Esc $p[1])" TextWrapping="Wrap" Foreground="{DynamicResource TextBrush}"/>
</Grid>
"@
        [void]$ui.PerksList.Children.Add((Parse-Xaml $x))
    }
}

# ------------------------------------------------------------------ game boost
function Update-BoostGames {
    $all = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessName })
    $running = @($Global:BoostGames | Where-Object { $all -contains $_ })
    if ($running.Count) { $Global:UI.BoostGames.Text = ($running -join ', ') } else { $Global:UI.BoostGames.Text = 'No supported game running right now' }
    return $running
}

function Update-BoostUI {
    $ui = $Global:UI
    $res = $Global:CCH.Window.Resources
    if ($Global:CCH.Boost.On) {
        $ui.BoostStatus.Text = 'Game Boost is ON'
        $ui.BtnBoost.Content = 'Stop Game Boost'
        $ui.BoostRing.Stroke = $res['GoodBrush']
        $ui.BoostIcon.Foreground = $res['GoodBrush']
        $ui.TitleBoostText.Text = 'GAME BOOST ON'
        $ui.TitleBoostText.Foreground = $res['GoodBrush']
        $ui.TitleBoostDot.Fill = $res['GoodBrush']
        $ui.TitleBoostPill.BorderBrush = $res['GoodBrush']
    } else {
        $ui.BoostStatus.Text = 'Game Boost is off'
        $ui.BtnBoost.Content = 'Activate Game Boost'
        $ui.BoostRing.Stroke = $res['LineBrush']
        $ui.BoostIcon.Foreground = $res['SubTextBrush']
        $ui.TitleBoostText.Text = 'GAME BOOST OFF'
        $ui.TitleBoostText.Foreground = $res['SubTextBrush']
        $ui.TitleBoostDot.Fill = $res['SubTextBrush']
        $ui.TitleBoostPill.BorderBrush = $res['LineBrush']
    }
}

function Start-Boost {
    if (-not (Confirm-Premium)) { Show-PremiumPrompt 'Game Boost'; return }
    $o = $Global:CCH.Settings.Boost
    $b = $Global:CCH.Boost
    $log = @()
    Show-Busy 'Starting Game Boost...'
    $b.Restart = @(); $b.Boosted = @{}; $b.PrevOverlay = ''
    if ($o.Power) {
        $b.PrevOverlay = Get-OverlayGuid
        if (Set-OverlayGuid $Global:OverlayBest) { $log += 'Power mode set to Best performance' }
    }
    if ($o.Kill) {
        $names = @($Global:BoostKill)
        if ($o.Browsers) { $names += $Global:BoostBrowsers }
        $closed = @()
        foreach ($n in $names) {
            $procs = @(Get-Process -Name $n -ErrorAction SilentlyContinue)
            if ($procs.Count -eq 0) { continue }
            if ($n -eq 'OneDrive' -and $procs[0].Path) { $b.Restart += $procs[0].Path }
            foreach ($p in $procs) { try { $p.Kill() } catch { } }
            $closed += $n
        }
        if ($closed.Count) { $log += 'Closed: ' + ($closed -join ', ') } else { $log += 'No background apps needed closing' }
    }
    if ($o.Ram) { Set-BusyText 'Freeing RAM...'; $log += ('Freed about {0} MB of RAM' -f (Invoke-FreeRam)) }
    if ($o.Roblox) { Sync-RobloxFlags; try { Sync-RbxCursor } catch { } }
    $b.On = $true
    Hide-Busy
    $Global:UI.BoostLog.Text = ($log -join "`n")
    Write-Log ('Game Boost started. ' + ($log -join '; '))
    Update-BoostUI
    Invoke-BoostTick
    Show-BoostEngine
        Show-Toast 'Game Boost is on - launch your game!'
}

function Stop-Boost {
    $b = $Global:CCH.Boost
    if ($b.PrevOverlay) { [void](Set-OverlayGuid $b.PrevOverlay) }
    foreach ($procId in @($b.Boosted.Keys)) {
        try { $p = Get-Process -Id $procId -ErrorAction Stop; $p.PriorityClass = 'Normal' } catch { }
    }
    foreach ($path in $b.Restart) { try { Start-Process 'explorer.exe' ('"' + $path + '"') } catch { } }
    $b.On = $false; $b.Boosted = @{}; $b.Restart = @()
    $Global:UI.BoostLog.Text = 'Boost stopped - power mode restored and OneDrive restarted.'
    Write-Log 'Game Boost stopped.'
    Update-BoostUI
    Show-Toast 'Game Boost stopped. Everything is back to normal.' 'info'
}

function Invoke-BoostTick {
    $running = Update-BoostGames
    $b = $Global:CCH.Boost
    if (-not $b.On) { return }
    if ($Global:CCH.Settings.Boost.Priority) {
        foreach ($n in $running) {
            foreach ($p in @(Get-Process -Name $n -ErrorAction SilentlyContinue)) {
                if ($b.Boosted.ContainsKey($p.Id)) { continue }
                try { $p.PriorityClass = 'High'; $b.Boosted[$p.Id] = $n; Write-Log "Game Boost: $n set to High priority." } catch { $b.Boosted[$p.Id] = $n }
            }
        }
    }
    if ($Global:CCH.Settings.Boost.Roblox -and ($running -contains 'RobloxPlayerBeta')) { Sync-RobloxFlags }
}

# ------------------------------------------------------------------ wiring
function Connect-Events {
    $ui = $Global:UI
    $w = $Global:CCH.Window

    $ui.BtnMin.Add_Click({ $Global:CCH.Window.WindowState = 'Minimized' })
    $ui.BtnMax.Add_Click({ if ($Global:CCH.Window.WindowState -eq 'Maximized') { $Global:CCH.Window.WindowState = 'Normal' } else { $Global:CCH.Window.WindowState = 'Maximized' } })
    $ui.BtnClose.Add_Click({ $Global:CCH.Window.Close() })
    $w.Add_StateChanged({
        if ($Global:CCH.Window.WindowState -eq 'Maximized') { $Global:UI.RootGrid.Margin = New-Object Windows.Thickness 7; $Global:UI.BtnMax.Content = [string][char]0xE923 }
        else { $Global:UI.RootGrid.Margin = New-Object Windows.Thickness 0; $Global:UI.BtnMax.Content = [string][char]0xE922 }
    })

    foreach ($n in $Global:NavMap.Keys) {
        $ui[$n].Tag = $Global:NavMap[$n]
        $ui[$n].Add_Checked({ Show-Page ([string]$this.Tag) })
    }
    $ui.TitleBoostPill.Add_MouseLeftButtonUp({ Show-Page 'PageBoost' })
    $ui.TitlePlanPill.Add_MouseLeftButtonUp({ Show-Page 'PagePremium' })
    $ui.BtnStatOptim.Add_Click({ Show-Page 'PageOptim' })
    $ui.BtnStatPremium.Add_Click({ Show-Page 'PagePremium' })
    $ui.BtnDashScan.Add_Click({ Show-Page 'PageScan' })
    $ui.ScDebloat.Add_Click({ Show-Page 'PageDebloat' })
    $ui.ScBoost.Add_Click({ Show-Page 'PageBoost' })
    $ui.ScTools.Add_Click({ Show-Page 'PageTools' })
    $ui.ScTheme.Add_Click({ Show-Page 'PageTheme' })

    $ui.BtnApplyAll.Add_Click({ Request-ApplyRecommended '' })
    $ui.BtnOptimApplyReco.Add_Click({ Request-ApplyRecommended 'optim' })
    $ui.BtnDebloatApplyReco.Add_Click({ Request-ApplyRecommended 'debloat' })
    $ui.BtnDashRestore.Add_Click({ Invoke-Tool 'restore' })

    $ui.OptimSearch.Add_TextChanged({ $Global:CCH.Filter.optim.Search = $Global:UI.OptimSearch.Text.Trim(); Update-Filter 'optim' })
    $ui.DebloatSearch.Add_TextChanged({ $Global:CCH.Filter.debloat.Search = $Global:UI.DebloatSearch.Text.Trim(); Update-Filter 'debloat' })
    $ui.OptimRecoOnly.Add_Click({ $Global:CCH.Filter.optim.RecoOnly = [bool]$Global:UI.OptimRecoOnly.IsChecked; Update-Filter 'optim' })
    $ui.DebloatRecoOnly.Add_Click({ $Global:CCH.Filter.debloat.RecoOnly = [bool]$Global:UI.DebloatRecoOnly.IsChecked; Update-Filter 'debloat' })

    $ui.BtnRescan.Add_Click({
        try {
            Invoke-FullScan
            Set-BusyText 'Building interface...' 93
            Build-Cards
            Update-AllViews
            Update-PremiumUI
        } catch {
            Write-Log "Rescan error: $($_.Exception.Message)"
            Hide-ScanLayer; Show-Toast ('Scan failed: ' + $_.Exception.Message) 'error'; return
        }
        Complete-ScanLayer { Show-Toast 'Scan complete.' }
    })
    $ui.BtnCopyReport.Add_Click({ [Windows.Clipboard]::SetText((Get-ScanReport $Global:CCH.Scan)); Show-Toast 'Report copied to clipboard.' })

    $ui.BtnRedeem.Add_Click({
        $r = Invoke-Redeem $Global:UI.CodeBox.Text
        $Global:UI.RedeemMsg.Text = $r.Msg
        if ($r.Ok) {
            $Global:UI.RedeemMsg.Foreground = $Global:CCH.Window.Resources['GoodBrush']
            $Global:UI.CodeBox.Text = ''
            Update-PremiumUI
            Update-AllViews
        } else { $Global:UI.RedeemMsg.Foreground = $Global:CCH.Window.Resources['BadBrush'] }
    })
    $ui.CodeBox.Add_KeyDown({ if ($_.Key -eq 'Return') { $Global:UI.BtnRedeem.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) } })

    $ui.BtnBoost.Add_Click({ if ($Global:CCH.Boost.On) { Stop-Boost } else { Start-Boost } })
    foreach ($k in @('Power', 'Kill', 'Browsers', 'Priority', 'Ram', 'Roblox')) {
        $cb = $ui['BoostOpt' + $k]
        $cb.IsChecked = [bool]$Global:CCH.Settings.Boost[$k]
        $cb.Tag = $k
        $cb.Add_Click({ $Global:CCH.Settings.Boost[[string]$this.Tag] = [bool]$this.IsChecked; Save-Settings })
    }

    $ui.BtnHex.Add_Click({
        $h = $Global:UI.HexBox.Text.Trim()
        if (-not $h.StartsWith('#')) { $h = '#' + $h }
        if ($h -match '^#[0-9a-fA-F]{6}$') { $Global:CCH.Settings.Accent = $h.ToUpper(); Apply-Theme; Save-Settings; Show-Toast 'Accent colour updated.' }
        else { Show-Toast 'Enter a colour like #FF9A1F' 'error' }
    })
    $ui.HexBox.Add_TextChanged({
        $h = $Global:UI.HexBox.Text.Trim()
        if ($h -match '^#[0-9a-fA-F]{6}$') { $Global:UI.HexPreview.Background = New-Brush $h }
    })
    $ui.SetAutoRestore.IsChecked = [bool]$Global:CCH.Settings.AutoRestore
    $ui.SetConfirmRisky.IsChecked = [bool]$Global:CCH.Settings.ConfirmRisky
    $ui.SetAutoRestore.Add_Click({ $Global:CCH.Settings.AutoRestore = [bool]$Global:UI.SetAutoRestore.IsChecked; Save-Settings })
    $ui.SetConfirmRisky.Add_Click({ $Global:CCH.Settings.ConfirmRisky = [bool]$Global:UI.SetConfirmRisky.IsChecked; Save-Settings })
    $ui.SetServer.Text = [string]$Global:CCH.Settings.LicenseServer
    $ui.BtnSaveServer.Add_Click({ $Global:CCH.Settings.LicenseServer = $Global:UI.SetServer.Text.Trim(); Save-Settings; Show-Toast 'License server saved.' })
    $ui.SetUpdateUrl.Text = [string]$Global:CCH.Settings.UpdateUrl
    $ui.SetAutoUpdate.IsChecked = [bool]$Global:CCH.Settings.AutoUpdate
    $ui.BtnSaveUpdate.Add_Click({
        $u = $Global:UI.SetUpdateUrl.Text.Trim()
        if ($u -and $u -notmatch '^https://') { Show-Toast 'Update URL must start with https://' 'error'; return }
        $Global:CCH.Settings.UpdateUrl = $u; Save-Settings; Show-Toast 'Update source saved.'
    })
    $ui.SetAutoUpdate.Add_Click({ $Global:CCH.Settings.AutoUpdate = [bool]$Global:UI.SetAutoUpdate.IsChecked; Save-Settings })

    $ui.ModalNo.Add_Click({ $Global:UI.ModalLayer.Visibility = 'Collapsed'; $Global:CCH.ModalAction = $null })
    $ui.ModalYes.Add_Click({
        $Global:UI.ModalLayer.Visibility = 'Collapsed'
        $a = $Global:CCH.ModalAction; $arg = $Global:CCH.ModalArg
        $Global:CCH.ModalAction = $null; $Global:CCH.ModalArg = $null
        if ($a) { & $a $arg }
    })

    $w.Add_Closing({
        if ($Global:CCH.Boost.On) { try { Stop-Boost } catch { } }
        try { if ($Global:Vibe.Player) { $Global:Vibe.Player.Stop(); $Global:Vibe.Player.Close() } } catch { }
        try { $Global:UsageTimer.Stop(); $Global:BoostTimer.Stop() } catch { }
    })
}

# ==================================================================================================
#  VIBES - original anime mascots + original lo-fi music (both can be switched off)
# ==================================================================================================

$Global:Mascots = [ordered]@{ kuro = 'Kuro'; momo = 'Momo'; cola = 'Cola'; mint = 'Mint'; sakura = 'Sakura'; yuki = 'Yuki' }
$Global:AvatarOptions = [ordered]@{ kuro = 'Kuro'; shadow = 'Shadow'; noir = 'Noir'; momo = 'Momo'; cola = 'Cola'; mint = 'Mint'; sakura = 'Sakura'; yuki = 'Yuki'; cat = 'Cat logo'; custom = 'My picture' }
$Global:Tracks  = [ordered]@{ 'cola-cafe' = 'Cola Cafe'; 'midnight-mint' = 'Midnight Mint'; 'sakura-rain' = 'Sakura Rain'; 'neon-drive' = 'Neon Drive' }
$Global:MascotLines = @(
    'Charger in. That alone is worth 20 percent.',
    'Run Game Boost before you launch, not after.',
    'Close the browser. It is eating your RAM.',
    'Roblox: Manual mode, quality 1-3, max FPS 120.',
    'Keep the vents clear. Heat throttles everything.',
    'Apply the green ones first. They matter most.',
    'Everything here is reversible. Experiment.',
    'A second RAM stick beats any tweak on this laptop.',
    'Low FPS is usually RAM or heat, not the GPU.',
    'Done tuning? Hit Game Boost and go.'
)
$Global:Vibe = @{ Player = $null; Current = ''; CurrentTitle = ''; Playing = $false; PausedForGame = $false; Mascot = 'kuro'; Images = @{}; Source = 'lofi'; Mine = @(); MineIdx = 0 }

function Get-MascotImage([string]$Key) {
    if ($Global:Vibe.Images.ContainsKey($Key)) { return $Global:Vibe.Images[$Key] }
    $p = Join-Path $Global:AppDir ('assets\vibes\' + $Key + '.png')
    if (-not (Test-Path $p)) { return $null }
    $bmp = New-Object Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.UriSource = New-Object Uri $p
    $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.EndInit()
    $bmp.Freeze()
    $Global:Vibe.Images[$Key] = $bmp
    return $bmp
}

function Set-MascotLine {
    $name = $Global:Mascots[$Global:Vibe.Mascot]
    $line = $Global:MascotLines[(Get-Random -Maximum $Global:MascotLines.Count)]
    Start-Talk $Global:UI.MascotDash $Global:UI.MascotSay ($name + ': ' + $line)
}

function Update-MascotLayout {
    $show = [bool]$Global:CCH.Settings.VibesArt -and $Global:CCH.Window.ActualWidth -ge 1220
    $v = 'Collapsed'; if ($show) { $v = 'Visible' }
    $Global:UI.MascotDashBox.Visibility = $v
}

function Update-Mascots {
    $s = $Global:CCH.Settings
    $key = [string]$s.Mascot
    if ($key -eq 'random' -or -not $Global:Mascots.Contains($key)) { $key = @($Global:Mascots.Keys)[(Get-Random -Maximum $Global:Mascots.Count)] }
    $Global:Vibe.Mascot = $key
    $img = $null
    if ($s.VibesArt) { $img = Get-MascotImage $key }
    $vis = 'Collapsed'; if ($img) { $vis = 'Visible' }
    foreach ($n in @('MascotDash', 'MascotBoost', 'MascotPrem', 'MascotTheme', 'MascotSupport')) {
        $Global:UI[$n].Source = $img
        $Global:UI[$n].Visibility = $vis
    }
    Set-MascotLine
    Update-MascotLayout
}

# ------------------------------------------------------------------ music
function Get-TrackList {
    return @($Global:Tracks.Keys | Where-Object { Test-Path (Join-Path $Global:AppDir ('assets\music\' + $_ + '.mp3')) })
}

function Init-Music {
    $p = New-Object Windows.Media.MediaPlayer
    $p.Add_MediaEnded({ Invoke-TrackEnded })
    $p.Add_MediaFailed({
        Write-Log ('Music could not play: ' + $_.ErrorException.Message)
        $Global:Vibe.Playing = $false
        Update-MusicUI
    })
    $Global:Vibe.Player = $p
}

function Start-Track([string]$Key) {
    $f = Join-Path $Global:AppDir ('assets\music\' + $Key + '.mp3')
    if (-not (Test-Path $f)) { return }
    $p = $Global:Vibe.Player
    $p.Open((New-Object Uri $f))
    $p.Volume = [double]$Global:CCH.Settings.Volume / 100.0
    $p.Play()
    $Global:Vibe.Current = $Key
    $Global:Vibe.Playing = $true
    $Global:Vibe.PausedForGame = $false
    Update-MusicUI
}

function Get-RandomTrack([string]$Except = '') {
    $list = @(Get-TrackList | Where-Object { $_ -ne $Except })
    if ($list.Count -eq 0) { $list = @(Get-TrackList) }
    if ($list.Count -eq 0) { return '' }
    return $list[(Get-Random -Maximum $list.Count)]
}

function Scan-MyMusic {
    $exts = @('.mp3', '.m4a', '.flac', '.wav', '.ogg', '.wma', '.aac')
    $roots = @([Environment]::GetFolderPath('MyMusic'), [Environment]::GetFolderPath('MyVideos'), (Join-Path $env:USERPROFILE 'Downloads'), [Environment]::GetFolderPath('Desktop'))
    $found = New-Object System.Collections.ArrayList
    foreach ($r in $roots) {
        if ($r -and (Test-Path $r)) {
            foreach ($f in @(Get-ChildItem -LiteralPath $r -Recurse -File -ErrorAction SilentlyContinue)) {
                if ($exts -contains $f.Extension.ToLower()) { [void]$found.Add($f.FullName); if ($found.Count -ge 3000) { break } }
            }
        }
        if ($found.Count -ge 3000) { break }
    }
    $Global:Vibe.Mine = @($found.ToArray() | Sort-Object { Get-Random })
    $Global:Vibe.MineIdx = 0
    Write-Log "Music library: found $($Global:Vibe.Mine.Count) songs on this PC."
    return $Global:Vibe.Mine.Count
}

function Play-Mine([int]$Index) {
    if ($Global:Vibe.Mine.Count -eq 0) { return }
    $n = $Global:Vibe.Mine.Count
    $i = (($Index % $n) + $n) % $n
    $Global:Vibe.MineIdx = $i
    $f = $Global:Vibe.Mine[$i]
    try {
        $p = $Global:Vibe.Player
        $p.Open((New-Object Uri $f)); $p.Volume = [double]$Global:CCH.Settings.Volume / 100.0; $p.Play()
        $Global:Vibe.Current = 'mine'; $Global:Vibe.CurrentTitle = [IO.Path]::GetFileNameWithoutExtension($f)
        $Global:Vibe.Playing = $true; $Global:Vibe.PausedForGame = $false
        Update-MusicUI
    } catch { Write-Log "Could not play $f : $($_.Exception.Message)" }
}

function Start-MyMusic {
    $Global:Vibe.Source = 'mine'
    if ($Global:Vibe.Mine.Count -eq 0) {
        Show-Busy 'Finding your music...' 'Scanning your Music, Downloads and Videos folders'
        [void](Scan-MyMusic); Hide-Busy
    }
    if ($Global:Vibe.Mine.Count -eq 0) { Show-Toast 'No music files found in your Music, Downloads, Videos or Desktop folders.' 'info'; return }
    $Global:CCH.Settings.VibesMusic = $true; $Global:UI.SetMusic.IsChecked = $true; Save-Settings
    Play-Mine 0
    Show-Toast ("Playing your music ({0} songs found)." -f $Global:Vibe.Mine.Count)
}

function Start-Music {
    if (-not $Global:Vibe.Player) { return }
    if ($Global:Vibe.Source -eq 'mine') {
        if ($Global:Vibe.Current -eq 'mine') { $Global:Vibe.Player.Play(); $Global:Vibe.Playing = $true; $Global:Vibe.PausedForGame = $false; Update-MusicUI }
        else { Start-MyMusic }
        return
    }
    $sel = [string]$Global:CCH.Settings.Track
    if ($Global:Vibe.Current) {
        $Global:Vibe.Player.Play()
        $Global:Vibe.Playing = $true; $Global:Vibe.PausedForGame = $false
        Update-MusicUI
        return
    }
    if ($sel -eq 'shuffle' -or -not (@(Get-TrackList) -contains $sel)) { $sel = Get-RandomTrack }
    if ($sel) { Start-Track $sel } else { Write-Log 'No music files found in assets\music.' }
}

function Stop-Music {
    if ($Global:Vibe.Player) { $Global:Vibe.Player.Pause() }
    $Global:Vibe.Playing = $false
    Update-MusicUI
}

function Invoke-TrackEnded {
    if ($Global:Vibe.Source -eq 'mine') { Play-Mine ($Global:Vibe.MineIdx + 1); return }
    if ([string]$Global:CCH.Settings.Track -eq 'shuffle') { Start-Track (Get-RandomTrack $Global:Vibe.Current) }
    else { $Global:Vibe.Player.Position = [TimeSpan]::Zero; $Global:Vibe.Player.Play() }
}

function Invoke-NextTrack {
    if ($Global:Vibe.Source -eq 'mine') { if (-not $Global:CCH.Settings.VibesMusic) { Set-MusicEnabled $true }; Play-Mine ($Global:Vibe.MineIdx + 1); return }
    $list = @(Get-TrackList)
    if ($list.Count -eq 0) { return }
    $i = [array]::IndexOf($list, $Global:Vibe.Current)
    $next = $list[($i + 1) % $list.Count]
    if ([string]$Global:CCH.Settings.Track -ne 'shuffle') { $Global:CCH.Settings.Track = $next; Save-Settings; Update-VibeChips }
    if (-not $Global:CCH.Settings.VibesMusic) { Set-MusicEnabled $true }
    Start-Track $next
}

function Set-MusicEnabled([bool]$On) {
    $Global:CCH.Settings.VibesMusic = $On
    Save-Settings
    $Global:UI.SetMusic.IsChecked = $On
    if ($On) { Start-Music } else { Stop-Music }
}

function Update-MusicUI {
    $ui = $Global:UI
    if ($Global:Vibe.Playing) {
        $ui.MusicIcon.Text = [string][char]0xE769
        if ($Global:Vibe.Current -eq 'mine') { $ui.MusicTitle.Text = $Global:Vibe.CurrentTitle } else { $ui.MusicTitle.Text = $Global:Tracks[$Global:Vibe.Current] }
        $ui.MusicTitle.Foreground = $Global:CCH.Window.Resources['TextBrush']
    } elseif ($Global:Vibe.PausedForGame) {
        $ui.MusicIcon.Text = [string][char]0xE768
        $ui.MusicTitle.Text = 'Paused while gaming'
        $ui.MusicTitle.Foreground = $Global:CCH.Window.Resources['SubTextBrush']
    } else {
        $ui.MusicIcon.Text = [string][char]0xE768
        $ui.MusicTitle.Text = 'Music off'
        if ($Global:CCH.Settings.VibesMusic -and $Global:Vibe.Current) { $ui.MusicTitle.Text = 'Paused' }
        $ui.MusicTitle.Foreground = $Global:CCH.Window.Resources['SubTextBrush']
    }
}

function Invoke-VibesTick([string[]]$RunningGames) {
    $s = $Global:CCH.Settings
    if (-not $s.VibesMusic -or -not $s.MusicGamePause -or -not $Global:Vibe.Player) { return }
    $gaming = (@($RunningGames).Count -gt 0)
    if ($gaming -and $Global:Vibe.Playing) {
        $Global:Vibe.Player.Pause(); $Global:Vibe.Playing = $false; $Global:Vibe.PausedForGame = $true; Update-MusicUI
    } elseif (-not $gaming -and $Global:Vibe.PausedForGame) {
        $Global:Vibe.Player.Play(); $Global:Vibe.Playing = $true; $Global:Vibe.PausedForGame = $false; Update-MusicUI
    }
}

# ------------------------------------------------------------------ settings UI
function Build-VibeChips {
    $ui = $Global:UI
    $ui.MascotChips.Children.Clear(); $ui.TrackChips.Children.Clear()
    $mList = @($Global:Mascots.Keys) + @('random')
    foreach ($k in $mList) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $Global:CCH.Window.FindResource('Chip')
        $rb.GroupName = 'vibe_mascot'
        if ($k -eq 'random') { $rb.Content = 'Random' } else { $rb.Content = $Global:Mascots[$k] }
        $rb.Tag = $k
        $rb.Add_Click({ $Global:CCH.Settings.Mascot = [string]$this.Tag; Save-Settings; Update-Mascots })
        [void]$ui.MascotChips.Children.Add($rb)
    }
    $tList = @($Global:Tracks.Keys) + @('shuffle', 'mine')
    foreach ($k in $tList) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $Global:CCH.Window.FindResource('Chip')
        $rb.GroupName = 'vibe_track'
        if ($k -eq 'shuffle') { $rb.Content = 'Shuffle' } elseif ($k -eq 'mine') { $rb.Content = 'My music' } else { $rb.Content = $Global:Tracks[$k] }
        $rb.Tag = $k
        $rb.Add_Click({
            $k = [string]$this.Tag
            $Global:CCH.Settings.Track = $k; Save-Settings
            if ($k -eq 'mine') { Start-MyMusic; return }
            $Global:Vibe.Source = 'lofi'; $Global:Vibe.Current = ''
            if ($Global:CCH.Settings.VibesMusic) {
                if ($k -eq 'shuffle') { Start-Track (Get-RandomTrack) } else { Start-Track $k }
            }
        })
        [void]$ui.TrackChips.Children.Add($rb)
    }
    Update-VibeChips
}

function Update-VibeChips {
    foreach ($rb in @($Global:UI.MascotChips.Children)) { $rb.IsChecked = ([string]$rb.Tag -eq [string]$Global:CCH.Settings.Mascot) }
    foreach ($rb in @($Global:UI.TrackChips.Children)) { $rb.IsChecked = ([string]$rb.Tag -eq [string]$Global:CCH.Settings.Track) }
}

function Connect-Vibes {
    $ui = $Global:UI
    $s = $Global:CCH.Settings
    $ui.SetArt.IsChecked = [bool]$s.VibesArt
    $ui.SetMusic.IsChecked = [bool]$s.VibesMusic
    $ui.SetMusicGame.IsChecked = [bool]$s.MusicGamePause
    $ui.SetFx.IsChecked = [bool]$s.VibesFx
    $ui.SetStartSound.IsChecked = [bool]$s.StartSound
    $ui.SetVolume.Value = [double]$s.Volume
    $ui.SetVolumeTxt.Text = ('{0}%' -f [int]$s.Volume)

    $ui.SetArt.Add_Click({ $Global:CCH.Settings.VibesArt = [bool]$Global:UI.SetArt.IsChecked; Save-Settings; Update-Mascots })
    $ui.SetMusic.Add_Click({ Set-MusicEnabled ([bool]$Global:UI.SetMusic.IsChecked) })
    $ui.SetFx.Add_Click({ $Global:CCH.Settings.VibesFx = [bool]$Global:UI.SetFx.IsChecked; Save-Settings; if ($Global:CCH.Settings.VibesFx) { Show-Fx 'sparkle' '' } })
    $ui.SetStartSound.Add_Click({ $Global:CCH.Settings.StartSound = [bool]$Global:UI.SetStartSound.IsChecked; Save-Settings; if ($Global:CCH.Settings.StartSound) { Play-ReadyChime } })
    $ui.BtnReplayTutorial.Add_Click({ Start-Tutorial })
    $ui.SetMusicGame.Add_Click({
        $Global:CCH.Settings.MusicGamePause = [bool]$Global:UI.SetMusicGame.IsChecked; Save-Settings
        if (-not $Global:CCH.Settings.MusicGamePause -and $Global:Vibe.PausedForGame) { Start-Music }
    })
    $ui.SetVolume.Add_ValueChanged({
        $v = [int][math]::Round($Global:UI.SetVolume.Value)
        $Global:CCH.Settings.Volume = $v
        $Global:UI.SetVolumeTxt.Text = "$v%"
        if ($Global:Vibe.Player) { $Global:Vibe.Player.Volume = $v / 100.0 }
    })
    $ui.SetVolume.Add_PreviewMouseUp({ Save-Settings })
    $ui.MusicPill.Add_MouseLeftButtonUp({ Set-MusicEnabled (-not $Global:Vibe.Playing) })
    $ui.MusicNext.Add_MouseLeftButtonUp({ Invoke-NextTrack })
    $ui.MascotDashBox.Add_MouseLeftButtonUp({ Set-MascotLine })
    $Global:CCH.Window.Add_SizeChanged({ Update-MascotLayout })
    if ([string]$Global:CCH.Settings.Track -eq 'mine') { $Global:Vibe.Source = 'mine' }
    Build-VibeChips
}

# ------------------------------------------------------------------ profile picture
function Get-AvatarFile {
    $a = [string]$Global:CCH.Settings.Avatar
    $default = Join-Path $Global:AppDir 'assets\vibes\kuro-avatar.png'
    if ($a -eq 'custom') {
        $f = Join-Path $Global:DataDir 'avatar.img'
        if (Test-Path $f) { return $f }
        return $default
    }
    if ($a -eq 'cat') { return (Join-Path $Global:AppDir 'assets\Kuro.png') }
    $f = Join-Path $Global:AppDir ('assets\vibes\' + $a + '-avatar.png')
    if (Test-Path $f) { return $f }
    return $default
}

function Update-Avatar {
    $f = Get-AvatarFile
    try {
        $bmp = New-Object Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit()
        $bmp.UriSource = New-Object Uri $f
        $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bmp.CreateOptions = [Windows.Media.Imaging.BitmapCreateOptions]::IgnoreImageCache
        $bmp.DecodePixelWidth = 192
        $bmp.EndInit()
        $bmp.Freeze()
        $brush = New-Object Windows.Media.ImageBrush $bmp
        $brush.Stretch = [Windows.Media.Stretch]::UniformToFill
        $brush.Freeze()
        $Global:UI.AvatarImg.Fill = $brush
        $Global:UI.AvatarPreview.Fill = $brush
    } catch {
        Write-Log "Profile picture could not be loaded: $($_.Exception.Message)"
    }
    foreach ($rb in @($Global:UI.AvatarChips.Children)) { $rb.IsChecked = ([string]$rb.Tag -eq [string]$Global:CCH.Settings.Avatar) }
}

function Select-AvatarFile {
    $d = New-Object Microsoft.Win32.OpenFileDialog
    $d.Title = 'Choose a profile picture'
    $d.Filter = 'Pictures (*.png;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.jpg;*.jpeg;*.bmp;*.gif'
    if ($d.ShowDialog($Global:CCH.Window) -ne $true) { Update-Avatar; return }
    try {
        if ((Get-Item -LiteralPath $d.FileName).Length -gt 15MB) { Show-Toast 'That picture is too big (max 15 MB).' 'error'; return }
        Copy-Item -LiteralPath $d.FileName -Destination (Join-Path $Global:DataDir 'avatar.img') -Force -ErrorAction Stop
        $Global:CCH.Settings.Avatar = 'custom'
        Save-Settings
        Update-Avatar
        Show-Toast 'Profile picture updated.'
    } catch { Show-Toast ('Could not use that picture: ' + $_.Exception.Message) 'error' }
}

function Connect-Avatar {
    $ui = $Global:UI
    $ui.AvatarChips.Children.Clear()
    foreach ($k in $Global:AvatarOptions.Keys) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $Global:CCH.Window.FindResource('Chip')
        $rb.GroupName = 'avatar_pick'
        $rb.Content = $Global:AvatarOptions[$k]
        $rb.Tag = $k
        $rb.Add_Click({
            $k = [string]$this.Tag
            if ($k -eq 'custom' -and -not (Test-Path (Join-Path $Global:DataDir 'avatar.img'))) { Select-AvatarFile; return }
            $Global:CCH.Settings.Avatar = $k; Save-Settings; Update-Avatar
        })
        [void]$ui.AvatarChips.Children.Add($rb)
    }
    $ui.BtnAvatarPick.Add_Click({ Select-AvatarFile })
    $ui.AvatarBtn.Add_MouseLeftButtonUp({ Show-Page 'PageTheme' })
    Update-Avatar
}

# ------------------------------------------------------------------ voice + tips
$Global:Speech = @{ Synth = $null; Tried = $false }
$Global:KuroGreetings = @('Welcome back.')
$Global:KuroTips = @(
    'On a laptop, battery mode can cut your FPS roughly in half. Keep it plugged in.',
    'In Roblox: Graphics Mode Manual, quality 1-3, Maximum Frame Rate 120.',
    'If the scan shows UHD Graphics instead of Iris Xe, you are running single-channel RAM. A matching second stick is the biggest upgrade.',
    'Browsers and Discord hold onto RAM. Close them before a session.',
    'Game Boost frees RAM and closes background apps. Run it before you launch.',
    'Every change is backed up. Revert everything undoes the lot in one click.',
    'A 60 Hz screen only draws 60 frames, but higher FPS still lowers input delay.',
    'Heat is the hidden FPS killer on thin laptops. Keep the vents clear.'
)

function Get-Greeting { return $Global:KuroGreetings[(Get-Random -Maximum $Global:KuroGreetings.Count)] }
# Voice removed - mascots "speak" visually (typewriter bubble + motion) instead of audio.
function Speak-Line([string]$Text) { }
function Stop-Speech { }

$Global:TipTimer = $null
function Start-TipLoop {
    if ($Global:TipTimer) { return }
    $Global:TipTimer = New-Object Windows.Threading.DispatcherTimer
    $Global:TipTimer.Interval = [TimeSpan]::FromSeconds(50)
    $Global:TipTimer.Add_Tick({
        try {
            if ($Global:UI.TutorialLayer.Visibility -eq 'Visible') { return }
            $tip = $Global:KuroTips[(Get-Random -Maximum $Global:KuroTips.Count)]
            Start-Talk $Global:UI.MascotDash $Global:UI.MascotSay ('Kuro: ' + $tip)
        } catch { }
    })
    $Global:TipTimer.Start()
}

# ==================================================================================================
#  SUPPORT / ABOUT
# ==================================================================================================

$Global:DiscordUrl = 'https://discord.gg/t65frAtq5'

function Open-Discord {
    try { Start-Process $Global:DiscordUrl } catch { Show-Toast ('Could not open the browser. Go to ' + $Global:DiscordUrl) 'error' }
}

function Get-BugReport {
    $s = $Global:CCH.Scan
    $lines = @()
    $lines += '**Kuro bug report**'
    $lines += '```'
    $lines += "Version : $($Global:CCH_Version)  (Premium: $($Global:CCH.Premium))"
    if ($s) {
        $lines += "Windows : $($s.OS) $($s.OSVer) build $($s.Build)"
        $lines += "Device  : $($s.Class) - $($s.Maker) $($s.Model)"
        $lines += "CPU     : $($s.CpuFull)"
        $lines += "GPU     : $($s.MainGpu)"
        $lines += "RAM     : $($s.RamGB) GB    Storage: $($s.DiskType)"
    }
    $lines += 'Last log lines:'
    try { $lines += @(Get-Content -Path $Global:LogFile -Tail 25 -ErrorAction Stop) } catch { $lines += '(no log)' }
    try { if (Test-Path (Join-Path $Global:DataDir 'error.txt')) { $lines += 'Last error:'; $lines += @(Get-Content -Path (Join-Path $Global:DataDir 'error.txt') -Tail 8) } } catch { }
    $lines += '```'
    $lines += 'What happened: (describe the bug here)'
    # hide the Windows user name / PC name before the report is pasted publicly
    $text = $lines -join "`r`n"
    foreach ($secret in @($env:USERNAME, $env:COMPUTERNAME, $env:USERPROFILE)) {
        if ($secret -and $secret.Length -gt 2) { $text = $text.Replace($secret, '<hidden>') }
    }
    $lines = @($text)
    $lines += 'Steps to reproduce: '
    return ($lines -join "`r`n")
}

function Connect-Support {
    $ui = $Global:UI
    $ui.DiscordLinkTxt.Text = $Global:DiscordUrl.Replace('https://', '')
    $ui.AboutVersion.Text = "Kuro v$($Global:CCH_Version)"
    $ui.BtnDiscord.Add_Click({ Open-Discord })
    $ui.BtnHelp.Add_Click({ Open-Discord })
    $ui.BtnBuy.Add_Click({ Open-Discord; Show-Toast 'Opening Discord - ask in the server for a Premium code, then redeem it on the Premium page.' 'info' })
    $ui.BtnBuyPrem.Add_Click({ Open-Discord; Show-Toast 'Opening Discord - ask in the server for a Premium code, then redeem it here.' 'info' })
    $ui.BtnBug.Add_Click({
        try { [Windows.Clipboard]::SetText((Get-BugReport)) } catch { }
        Open-Discord
        Show-Toast 'Bug report copied! Paste it (Ctrl+V) in the bug-report channel and add what happened.' 'info'
    })
    $ui.BtnAboutLog.Add_Click({ Start-Process 'explorer.exe' $Global:DataDir })
    $ui.BtnAboutReadme.Add_Click({ $r = Join-Path $Global:AppDir 'README.md'; if (Test-Path $r) { Start-Process 'notepad.exe' ('"' + $r + '"') } })
}

# ==================================================================================================
#  ANIME TASK EFFECTS  (sparkle bursts, success banner, speed-lines) - all optional via Vibes
#  Lightweight: a handful of vector shapes animated on the composition thread, auto-removed.
# ==================================================================================================

function New-StarGeometry([double]$R) {
    $i = $R * 0.30
    $pts = "{0},0 {1},{1} 0,{0} -{1},{1} -{0},0 -{1},-{1} 0,-{0} {1},-{1}" -f $R, $i
    return [Windows.Media.Geometry]::Parse("M $pts Z")
}

function Add-FxAnim($Target, $Prop, [double]$From, [double]$To, [double]$Secs, [double]$Delay = 0, $Ease = $null, [scriptblock]$Done = $null) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    $a.From = $From; $a.To = $To
    $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds($Secs))
    if ($Delay -gt 0) { $a.BeginTime = [TimeSpan]::FromSeconds($Delay) }
    if ($Ease) { $a.EasingFunction = $Ease }
    if ($Done) { $a.Add_Completed($Done) }
    $Target.BeginAnimation($Prop, $a)
}

function Get-FxColors {
    $acc = [string]$Global:CCH.Settings.Accent
    $mascot = $Global:Vibe.Mascot
    $extra = '#EC4899'
    switch ($mascot) { 'mint' { $extra = '#2DD4BF' } 'sakura' { $extra = '#A855F7' } 'cola' { $extra = '#FF9A1F' } 'kuro' { $extra = '#EC4899' } }
    return @($acc, '#FFFFFF', '#FFE27A', $extra)
}

function Add-Sparkle($cx, $cy, $color, $r, $dur, $delay, $dx, $dy, $spin) {
    $layer = $Global:UI.FxLayer
    $star = New-Object Windows.Shapes.Path
    $star.Data = New-StarGeometry $r
    $star.Fill = (New-Brush $color)
    [Windows.Controls.Canvas]::SetLeft($star, $cx)
    [Windows.Controls.Canvas]::SetTop($star, $cy)
    $sc = New-Object Windows.Media.ScaleTransform(0.1, 0.1)
    $tr = New-Object Windows.Media.TranslateTransform(0, 0)
    $rt = New-Object Windows.Media.RotateTransform(0)
    $tg = New-Object Windows.Media.TransformGroup
    $tg.Children.Add($sc); $tg.Children.Add($rt); $tg.Children.Add($tr)
    $star.RenderTransform = $tg
    $star.Opacity = 0
    [void]$layer.Children.Add($star)
    $back = New-Object Windows.Media.Animation.BackEase; $back.Amplitude = 0.7; $back.EasingMode = 'EaseOut'
    $cub = New-Object Windows.Media.Animation.CubicEase; $cub.EasingMode = 'EaseOut'
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.1 1.0 ($dur * 0.5) $delay $back
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.1 1.0 ($dur * 0.5) $delay $back
    Add-FxAnim $tr ([Windows.Media.TranslateTransform]::XProperty) 0 $dx $dur $delay $cub
    Add-FxAnim $tr ([Windows.Media.TranslateTransform]::YProperty) 0 $dy $dur $delay $cub
    if ($spin) { Add-FxAnim $rt ([Windows.Media.RotateTransform]::AngleProperty) 0 $spin $dur $delay }
    Add-FxAnim $star ([Windows.UIElement]::OpacityProperty) 1 0 ($dur * 0.9) ($delay + $dur * 0.25) $null { try { $Global:UI.FxLayer.Children.Remove($star) } catch { } }.GetNewClosure()
}

function Add-Ring($cx, $cy, $color, $r0, $r1, $dur) {
    $layer = $Global:UI.FxLayer
    $e = New-Object Windows.Shapes.Ellipse
    $e.Width = $r0 * 2; $e.Height = $r0 * 2
    $e.Stroke = (New-Brush $color); $e.StrokeThickness = 5; $e.Opacity = 0.9
    [Windows.Controls.Canvas]::SetLeft($e, $cx - $r0)
    [Windows.Controls.Canvas]::SetTop($e, $cy - $r0)
    $sc = New-Object Windows.Media.ScaleTransform(1, 1, $r0, $r0)
    $e.RenderTransform = $sc
    [void]$layer.Children.Add($e)
    $cub = New-Object Windows.Media.Animation.CubicEase; $cub.EasingMode = 'EaseOut'
    $f = $r1 / $r0
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.4 $f $dur 0 $cub
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.4 $f $dur 0 $cub
    Add-FxAnim $e ([Windows.UIElement]::OpacityProperty) 0.9 0 $dur 0 $null { try { $Global:UI.FxLayer.Children.Remove($e) } catch { } }.GetNewClosure()
}

function Add-Banner($cx, $cy, [string]$text, $color) {
    if (-not $text) { return }
    $layer = $Global:UI.FxLayer
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Orientation = 'Horizontal'
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text
    $tb.FontSize = 46; $tb.FontWeight = 'Bold'
    $tb.Foreground = (New-Brush $color)
    $tb.Effect = (New-Object Windows.Media.Effects.DropShadowEffect -Property @{ Color = [Windows.Media.Colors]::Black; BlurRadius = 14; ShadowDepth = 0; Opacity = 0.6 })
    [void]$panel.Children.Add($tb)
    $panel.Measure((New-Object Windows.Size ([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $w = $panel.DesiredSize.Width; $h = $panel.DesiredSize.Height
    [Windows.Controls.Canvas]::SetLeft($panel, $cx - $w / 2)
    [Windows.Controls.Canvas]::SetTop($panel, $cy - $h / 2)
    $sc = New-Object Windows.Media.ScaleTransform(0.5, 0.5, $w / 2, $h / 2)
    $tr = New-Object Windows.Media.TranslateTransform(0, 0)
    $tg = New-Object Windows.Media.TransformGroup; $tg.Children.Add($sc); $tg.Children.Add($tr)
    $panel.RenderTransform = $tg
    $panel.Opacity = 0
    [void]$layer.Children.Add($panel)
    $back = New-Object Windows.Media.Animation.BackEase; $back.Amplitude = 0.5; $back.EasingMode = 'EaseOut'
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.5 1.0 0.45 0 $back
    Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.5 1.0 0.45 0 $back
    Add-FxAnim $panel ([Windows.UIElement]::OpacityProperty) 0 1 0.3
    Add-FxAnim $tr ([Windows.Media.TranslateTransform]::YProperty) 0 -42 1.5 0.5
    Add-FxAnim $panel ([Windows.UIElement]::OpacityProperty) 1 0 0.6 1.0 $null { try { $Global:UI.FxLayer.Children.Remove($panel) } catch { } }.GetNewClosure()
}

function Add-SpeedLines($color) {
    $layer = $Global:UI.FxLayer
    $W = [double]$Global:CCH.Window.ActualWidth; $H = [double]$Global:CCH.Window.ActualHeight
    $rng = New-Object Random
    for ($i = 0; $i -lt 9; $i++) {
        $len = $rng.Next(90, 220)
        $rect = New-Object Windows.Shapes.Rectangle
        $rect.Width = $len; $rect.Height = $rng.Next(2, 5)
        $rect.RadiusX = 2; $rect.RadiusY = 2
        $rect.Fill = (New-Brush $color); $rect.Opacity = 0
        $y = $rng.Next(80, [int]$H - 40)
        [Windows.Controls.Canvas]::SetTop($rect, $y)
        [Windows.Controls.Canvas]::SetLeft($rect, $W + 40)
        $tr = New-Object Windows.Media.TranslateTransform(0, 0)
        $rect.RenderTransform = $tr
        [void]$layer.Children.Add($rect)
        $cub = New-Object Windows.Media.Animation.CubicEase; $cub.EasingMode = 'EaseOut'
        $delay = $rng.NextDouble() * 0.25
        Add-FxAnim $tr ([Windows.Media.TranslateTransform]::XProperty) 0 (-($W + 120)) 0.6 $delay $cub $null
        Add-FxAnim $rect ([Windows.UIElement]::OpacityProperty) 0.85 0 0.55 $delay $null { try { $Global:UI.FxLayer.Children.Remove($rect) } catch { } }.GetNewClosure()
    }
}

function Bounce-Mascot {
    try {
        if (-not $Global:CCH.Settings.VibesArt) { return }
        $img = $Global:UI.MascotDash
        if (-not $img -or $img.Visibility -ne 'Visible' -or $img.ActualWidth -le 0) { return }
        $sc = New-Object Windows.Media.ScaleTransform(1, 1)
        $img.RenderTransformOrigin = New-Object Windows.Point 0.5, 1.0
        $img.RenderTransform = $sc
        $el = New-Object Windows.Media.Animation.ElasticEase; $el.Oscillations = 2; $el.Springiness = 4; $el.EasingMode = 'EaseOut'
        Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleXProperty) 1.12 1.0 0.8 0 $el
        Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleYProperty) 0.9 1.0 0.8 0 $el
    } catch { }
}

function Show-Fx([string]$Kind, [string]$Text = '') {
    if (-not $Global:CCH.Settings.VibesFx) { return }
    try {
        $win = $Global:CCH.Window
        $W = [double]$win.ActualWidth; $H = [double]$win.ActualHeight
        if ($W -le 0) { return }
        $cx = ($W + 72) / 2    # bias toward content area (sidebar is 72)
        $cy = $H * 0.42
        $cols = Get-FxColors
        $rng = New-Object Random
        switch ($Kind) {
            'sparkle' {
                for ($i = 0; $i -lt 10; $i++) {
                    $ang = $rng.NextDouble() * 6.283
                    $dist = $rng.Next(60, 150)
                    Add-Sparkle $cx $cy $cols[$rng.Next($cols.Count)] ($rng.Next(9, 20)) (0.9 + $rng.NextDouble() * 0.4) ($rng.NextDouble() * 0.2) ([Math]::Cos($ang) * $dist) ([Math]::Sin($ang) * $dist - 30) ($rng.Next(-120, 120))
                }
                Bounce-Mascot
            }
            'success' {
                Add-Ring $cx $cy $cols[0] 40 260 0.7
                for ($i = 0; $i -lt 22; $i++) {
                    $ang = $rng.NextDouble() * 6.283
                    $dist = $rng.Next(80, 230)
                    Add-Sparkle $cx $cy $cols[$rng.Next($cols.Count)] ($rng.Next(10, 26)) (1.0 + $rng.NextDouble() * 0.6) ($rng.NextDouble() * 0.25) ([Math]::Cos($ang) * $dist) ([Math]::Sin($ang) * $dist - 40) ($rng.Next(-180, 180))
                }
                Add-Banner $cx $cy $Text $cols[0]
                Bounce-Mascot
            }
            'blast' {
                Add-SpeedLines $cols[0]; Add-SpeedLines $cols[3]
                Add-Ring $cx $cy $cols[0] 24 380 0.85
                Add-Ring $cx $cy $cols[3] 52 460 1.05
                for ($i = 0; $i -lt 28; $i++) {
                    $ang = $rng.NextDouble() * 6.283
                    $dist = $rng.Next(100, 300)
                    Add-Sparkle $cx $cy $cols[$rng.Next($cols.Count)] ($rng.Next(11, 28)) (1.0 + $rng.NextDouble() * 0.7) ($rng.NextDouble() * 0.3) ([Math]::Cos($ang) * $dist) ([Math]::Sin($ang) * $dist - 40) ($rng.Next(-220, 220))
                }
                Add-Banner $cx $cy $Text $cols[0]
                Bounce-Mascot
            }
            'powerup' {
                Add-Ring $cx $cy $cols[0] 28 340 0.85
                Add-Ring $cx $cy $cols[3] 55 400 1.0
                Add-SpeedLines $cols[0]
                for ($i = 0; $i -lt 20; $i++) {
                    $ang = $rng.NextDouble() * 6.283
                    $dist = $rng.Next(90, 260)
                    Add-Sparkle $cx $cy $cols[$rng.Next($cols.Count)] ($rng.Next(10, 26)) (1.0 + $rng.NextDouble() * 0.6) ($rng.NextDouble() * 0.3) ([Math]::Cos($ang) * $dist) ([Math]::Sin($ang) * $dist - 40) ($rng.Next(-200, 200))
                }
                Add-Banner $cx $cy $Text $cols[0]
                Bounce-Mascot
            }
            'boost' {
                Add-SpeedLines $cols[3]
                Add-Ring $cx $cy $cols[3] 50 300 0.75
                for ($i = 0; $i -lt 18; $i++) {
                    $ang = $rng.NextDouble() * 6.283
                    $dist = $rng.Next(90, 240)
                    Add-Sparkle $cx $cy $cols[$rng.Next($cols.Count)] ($rng.Next(10, 24)) (1.0 + $rng.NextDouble() * 0.5) ($rng.NextDouble() * 0.2) ([Math]::Cos($ang) * $dist) ([Math]::Sin($ang) * $dist - 40) ($rng.Next(-180, 180))
                }
                Add-Banner $cx $cy $Text $cols[3]
                Bounce-Mascot
            }
        }
    } catch { Write-Log "FX error: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ rainbow spinner + power-up
function ConvertFrom-Hsv([double]$h, [double]$s, [double]$v) {
    $h = $h % 360.0
    $c = $v * $s; $x = $c * (1 - [Math]::Abs((($h / 60.0) % 2) - 1)); $m = $v - $c
    $r = 0.0; $g = 0.0; $b = 0.0
    switch ([int][Math]::Floor($h / 60.0)) {
        0 { $r = $c; $g = $x } 1 { $r = $x; $g = $c } 2 { $g = $c; $b = $x }
        3 { $g = $x; $b = $c } 4 { $r = $x; $b = $c } default { $r = $c; $b = $x }
    }
    return ('#{0:X2}{1:X2}{2:X2}' -f [int](($r + $m) * 255), [int](($g + $m) * 255), [int](($b + $m) * 255))
}

function Init-Spinner {
    try {
        $cv = $Global:UI.SpinnerCanvas
        if (-not $cv) { return }
        $cv.Children.Clear()
        $n = 12; $cx = 52.0; $cy = 52.0; $rad = 43.0
        for ($i = 0; $i -lt $n; $i++) {
            $ang = ($i / [double]$n) * 6.28318
            $frac = $i / [double]($n - 1)
            $dot = New-Object Windows.Shapes.Ellipse
            $sz = 5.0 + 8.0 * $frac
            $dot.Width = $sz; $dot.Height = $sz
            $dot.Fill = (New-Brush (ConvertFrom-Hsv ($frac * 320) 0.85 1.0))
            $dot.Opacity = 0.18 + 0.82 * $frac
            [Windows.Controls.Canvas]::SetLeft($dot, $cx + $rad * [Math]::Cos($ang) - $sz / 2)
            [Windows.Controls.Canvas]::SetTop($dot, $cy + $rad * [Math]::Sin($ang) - $sz / 2)
            [void]$cv.Children.Add($dot)
        }
        $f = Join-Path $Global:AppDir 'assets\vibes\kuro-avatar.png'
        if (Test-Path $f) {
            $bmp = New-Object Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit(); $bmp.UriSource = New-Object Uri $f
            $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.DecodePixelWidth = 120; $bmp.EndInit(); $bmp.Freeze()
            $br = New-Object Windows.Media.ImageBrush $bmp
            $br.Stretch = [Windows.Media.Stretch]::UniformToFill; $br.Freeze()
            $Global:UI.SpinnerFace.Fill = $br
        }
    } catch { Write-Log "Spinner init error: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ mascot "speaking" animation
$Global:TalkTimer = $null
function Nudge-Talk($img) {
    try {
        if (-not $img -or $img.Visibility -ne 'Visible') { return }
        $sc = New-Object Windows.Media.ScaleTransform(1, 1)
        $rt = New-Object Windows.Media.RotateTransform(0)
        $tg = New-Object Windows.Media.TransformGroup; $tg.Children.Add($sc); $tg.Children.Add($rt)
        $img.RenderTransformOrigin = New-Object Windows.Point 0.5, 1.0
        $img.RenderTransform = $tg
        $el = New-Object Windows.Media.Animation.ElasticEase; $el.Oscillations = 2; $el.Springiness = 5; $el.EasingMode = 'EaseOut'
        Add-FxAnim $rt ([Windows.Media.RotateTransform]::AngleProperty) -5 0 0.7 0 $el
        Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleYProperty) 1.06 1.0 0.6 0 $el
        Add-FxAnim $sc ([Windows.Media.ScaleTransform]::ScaleXProperty) 0.97 1.0 0.6 0 $el
    } catch { }
}

function Start-Talk($img, $tb, [string]$Text) {
    if (-not $tb) { return }
    try { if ($Global:TalkTimer) { $Global:TalkTimer.Stop() } } catch { }
    $tb.Text = ''
    $full = [string]$Text
    $idx = @{ v = 0 }
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(20)
    $timer.Add_Tick({
        if ($idx.v -ge $full.Length) { $timer.Stop(); return }
        $idx.v = [Math]::Min($full.Length, $idx.v + 1)
        $tb.Text = $full.Substring(0, $idx.v)
    }.GetNewClosure())
    $Global:TalkTimer = $timer
    $timer.Start()
    Nudge-Talk $img
}

# ------------------------------------------------------------------ page fade transition
function Fade-In($el) {
    try {
        if (-not $el) { return }
        $a = New-Object Windows.Media.Animation.DoubleAnimation
        $a.From = 0.0; $a.To = 1.0
        $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(190))
        $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseOut'; $a.EasingFunction = $ease
        $el.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
    } catch { }
}

# ------------------------------------------------------------------ Game Boost engine rev (replaces confetti)
$Global:Sfx = @{ Player = $null; Ready = $null; Rev = $null }
function Play-Engine {
    if (-not $Global:CCH.Settings.VibesFx) { return }
    try {
        $f = Join-Path $Global:AppDir 'assets\sfx\engine.mp3'
        if (-not (Test-Path $f)) { return }
        if (-not $Global:Sfx.Player) { $Global:Sfx.Player = New-Object Windows.Media.MediaPlayer }
        $Global:Sfx.Player.Open((New-Object Uri $f))
        $Global:Sfx.Player.Volume = [Math]::Max(0.45, [double]$Global:CCH.Settings.Volume / 100.0)
        $Global:Sfx.Player.Position = [TimeSpan]::Zero
        $Global:Sfx.Player.Play()
    } catch { }
}

function Get-ArcPath([double]$cx, [double]$cy, [double]$r, [double]$a0, [double]$sweep) {
    $a1 = $a0 + $sweep
    $p0 = New-Object Windows.Point (($cx + $r * [Math]::Cos($a0 * [Math]::PI / 180)), ($cy + $r * [Math]::Sin($a0 * [Math]::PI / 180)))
    $p1 = New-Object Windows.Point (($cx + $r * [Math]::Cos($a1 * [Math]::PI / 180)), ($cy + $r * [Math]::Sin($a1 * [Math]::PI / 180)))
    $seg = New-Object Windows.Media.ArcSegment $p1, (New-Object Windows.Size $r, $r), 0.0, ($sweep -gt 180), ([Windows.Media.SweepDirection]::Clockwise), $true
    $fig = New-Object Windows.Media.PathFigure; $fig.StartPoint = $p0; $fig.IsClosed = $false; [void]$fig.Segments.Add($seg)
    $geo = New-Object Windows.Media.PathGeometry; [void]$geo.Figures.Add($fig)
    return $geo
}

function Show-BoostEngine {
    Play-Engine
    if (-not $Global:CCH.Settings.VibesFx) { return }
    try {
        $layer = $Global:UI.FxLayer
        $win = $Global:CCH.Window
        $W = [double]$win.ActualWidth; $H = [double]$win.ActualHeight
        if ($W -le 0) { return }
        $cx = ($W + 72) / 2; $cy = $H * 0.42; $r = 118.0
        $cols = Get-FxColors
        $grp = New-Object Windows.Controls.Canvas
        [void]$layer.Children.Add($grp)
        # track arc
        $track = New-Object Windows.Shapes.Path
        $track.Stroke = (New-Brush ([string]$Global:BgThemes[[string]$Global:CCH.Settings.Bg].Panel2)); $track.StrokeThickness = 14
        $track.StrokeStartLineCap = 'Round'; $track.StrokeEndLineCap = 'Round'
        $track.Data = Get-ArcPath $cx $cy $r 135 270
        [void]$grp.Children.Add($track)
        # value arc
        $val = New-Object Windows.Shapes.Path
        $val.Stroke = (New-Brush $cols[0]); $val.StrokeThickness = 14
        $val.StrokeStartLineCap = 'Round'; $val.StrokeEndLineCap = 'Round'
        [void]$grp.Children.Add($val)
        # tick marks
        for ($i = 0; $i -le 10; $i++) {
            $ang = (135 + $i * 27) * [Math]::PI / 180
            $ln = New-Object Windows.Shapes.Line
            $ln.X1 = $cx + ($r + 12) * [Math]::Cos($ang); $ln.Y1 = $cy + ($r + 12) * [Math]::Sin($ang)
            $ln.X2 = $cx + ($r + 22) * [Math]::Cos($ang); $ln.Y2 = $cy + ($r + 22) * [Math]::Sin($ang)
            $ln.Stroke = (New-Brush $(if ($i -ge 8) { '#FF5A5F' } else { $cols[1] })); $ln.StrokeThickness = 3; $ln.Opacity = 0.7
            [void]$grp.Children.Add($ln)
        }
        # number + label
        $num = New-Object Windows.Controls.TextBlock
        $num.Text = '0'; $num.FontSize = 62; $num.FontWeight = 'Bold'; $num.Foreground = (New-Brush $cols[1])
        [Windows.Controls.Canvas]::SetLeft($num, $cx - 60); [Windows.Controls.Canvas]::SetTop($num, $cy - 58); $num.Width = 120; $num.TextAlignment = 'Center'
        [void]$grp.Children.Add($num)
        $lbl = New-Object Windows.Controls.TextBlock
        $lbl.Text = 'GAME BOOST'; $lbl.FontSize = 15; $lbl.FontWeight = 'Bold'; $lbl.Foreground = (New-Brush $cols[0])
        [Windows.Controls.Canvas]::SetLeft($lbl, $cx - 80); [Windows.Controls.Canvas]::SetTop($lbl, $cy + 18); $lbl.Width = 160; $lbl.TextAlignment = 'Center'
        [void]$grp.Children.Add($lbl)
        # sweep timer 0 -> 100
        $state = @{ v = 0.0 }
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(26)
        $t.Add_Tick({
            $state.v += 3.6
            if ($state.v -ge 100) {
                $state.v = 100; $t.Stop()
                $fade = New-Object Windows.Media.Animation.DoubleAnimation
                $fade.From = 1; $fade.To = 0; $fade.BeginTime = [TimeSpan]::FromMilliseconds(600)
                $fade.Duration = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(450))
                $fade.Add_Completed({ try { $layer.Children.Remove($grp) } catch { } }.GetNewClosure())
                $grp.BeginAnimation([Windows.UIElement]::OpacityProperty, $fade)
            }
            $frac = $state.v / 100.0
            $val.Data = Get-ArcPath $cx $cy $r 135 (270 * $frac)
            $num.Text = [string][int]$state.v
            if ($state.v -ge 80) { $num.Foreground = (New-Brush '#FF5A5F'); $val.Stroke = (New-Brush '#FF5A5F') }
        }.GetNewClosure())
        $t.Start()
        Bounce-Mascot
    } catch { Write-Log "Boost engine FX error: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ loading ring (startup + PC scan)
# Full-window splash: progress ring around the app icon, name + version badge, status line.
# Progress is driven by Set-BusyText calls during the scan; a timer eases the ring toward the target.
$Global:Scan = @{ Shown = 0.0; Target = 0.0; Phase = 'idle'; Timer = $null; Then = $null; DoneTicks = 0; Chimed = $false; Ticks = $null; TickLit = -1 }

function Get-AccentColor {
    try { return [Windows.Media.ColorConverter]::ConvertFromString([string]$Global:CCH.Settings.Accent) }
    catch { return [Windows.Media.ColorConverter]::ConvertFromString('#E86A9C') }
}

function Draw-ScanRing([double]$Pct) {
    $ui = $Global:UI
    $p = [Math]::Max(0.0, [Math]::Min(100.0, $Pct))
    $sweep = [Math]::Max(0.5, [Math]::Min(359.9, 3.6 * $p))
    $ui.ScanArc.Data = Get-ArcPath 75 75 70 -90 $sweep
    if ($ui.ScanRpm) { $ui.ScanRpm.Text = ('{0:N0} RPM' -f ([Math]::Round($p * 80 / 50) * 50)) }
    $lit = [int][Math]::Floor($p * 40 / 100)
    if ($Global:Scan.Ticks -and $lit -ne $Global:Scan.TickLit) {
        $acc = Get-AccentColor
        $on = New-Object Windows.Media.SolidColorBrush $acc
        $hot = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(0xFF, 0x4D, 0x4D))
        $off = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, 255, 255, 255))
        for ($i = 0; $i -lt $Global:Scan.Ticks.Count; $i++) {
            $Global:Scan.Ticks[$i].Stroke = $(if ($i -le $lit) { if ($i -ge 35) { $hot } else { $on } } else { $off })
        }
        $Global:Scan.TickLit = $lit
    }
    $a = (-90 + $sweep) * [Math]::PI / 180
    [Windows.Controls.Canvas]::SetLeft($ui.ScanHead, 75 + 70 * [Math]::Cos($a) - 4.5)
    [Windows.Controls.Canvas]::SetTop($ui.ScanHead, 75 + 70 * [Math]::Sin($a) - 4.5)
}

function Init-ScanLayer {
    $ui = $Global:UI
    $acc = Get-AccentColor
    $amber = [Windows.Media.ColorConverter]::ConvertFromString('#F6B85A')
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.MappingMode = [Windows.Media.BrushMappingMode]::Absolute
    $g.StartPoint = New-Object Windows.Point 5, 75
    $g.EndPoint = New-Object Windows.Point 145, 75
    [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop $amber, 0.0))
    [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop $acc, 1.0))
    $ui.ScanArc.Stroke = $g

    $glow = New-Object Windows.Media.RadialGradientBrush
    [void]$glow.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0x30, $acc.R, $acc.G, $acc.B)), 0.0))
    [void]$glow.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0x10, $amber.R, $amber.G, $amber.B)), 0.45))
    [void]$glow.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.Color]::FromArgb(0x00, $acc.R, $acc.G, $acc.B)), 1.0))
    $ui.ScanGlow.Fill = $glow

    $ui.ScanBadge.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x26, $acc.R, $acc.G, $acc.B))
    $ui.ScanBadge.BorderBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x55, $acc.R, $acc.G, $acc.B))
    $ui.ScanVer.Foreground = New-Object Windows.Media.SolidColorBrush $acc
    $ui.ScanVer.Text = 'V' + $Global:CCH_Version

    $f = Join-Path $Global:AppDir 'assets\Kuro.png'
    if (Test-Path $f) {
        try {
            $bmp = New-Object Windows.Media.Imaging.BitmapImage
            $bmp.BeginInit(); $bmp.UriSource = New-Object Uri $f
            $bmp.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bmp.DecodePixelWidth = 168; $bmp.EndInit(); $bmp.Freeze()
            $br = New-Object Windows.Media.ImageBrush $bmp
            $br.Stretch = [Windows.Media.Stretch]::UniformToFill
            $ui.ScanIcon.Background = $br
        } catch { }
    }
    $ui.ScanIcon.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 1
    $ui.ScanRpm.Foreground = New-Object Windows.Media.SolidColorBrush $acc

    # tachometer ticks around the ring (40 ticks, a long one every 5 = 1,000 RPM up to 8,000)
    $ui.ScanTicks.Children.Clear()
    $ticks = New-Object System.Collections.ArrayList
    for ($i = 0; $i -le 40; $i++) {
        $a = (-90 + $i * 9) * [Math]::PI / 180
        $major = ($i % 5 -eq 0)
        $r1 = 76.0; $r2 = $(if ($major) { 83.0 } else { 79.5 })
        $ln = New-Object Windows.Shapes.Line
        $ln.X1 = 75 + $r1 * [Math]::Cos($a); $ln.Y1 = 75 + $r1 * [Math]::Sin($a)
        $ln.X2 = 75 + $r2 * [Math]::Cos($a); $ln.Y2 = 75 + $r2 * [Math]::Sin($a)
        $ln.StrokeThickness = $(if ($major) { 2.0 } else { 1.2 })
        $ln.StrokeStartLineCap = 'Round'; $ln.StrokeEndLineCap = 'Round'
        $ln.Stroke = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x30, 255, 255, 255))
        [void]$ui.ScanTicks.Children.Add($ln); [void]$ticks.Add($ln)
    }
    $Global:Scan.Ticks = $ticks.ToArray()
    $Global:Scan.TickLit = -1

    if (-not $Global:Scan.Timer) {
        $t = New-Object Windows.Threading.DispatcherTimer ([Windows.Threading.DispatcherPriority]::Render)
        $t.Interval = [TimeSpan]::FromMilliseconds(16)
        $t.Add_Tick({ try { Step-ScanLayer } catch { } })
        $Global:Scan.Timer = $t
    }
}

function Show-ScanLayer([string]$Status = 'Starting...') {
    $ui = $Global:UI
    if (-not $ui.ScanLayer) { return }
    Init-ScanLayer
    $Global:Scan.Shown = 0.0; $Global:Scan.Target = 3.0; $Global:Scan.Phase = 'run'; $Global:Scan.Then = $null; $Global:Scan.Chimed = $false
    $ui.ScanStatus.Text = $Status
    $ui.ScanLayer.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
    $ui.ScanLayer.Opacity = 1.0
    $ui.ScanLayer.Visibility = 'Visible'
    Draw-ScanRing 0
    if ($Global:CCH.Settings.StartSound) {
        # race-engine rev while the ring winds up, then the chime when ready
        try {
            $f = Join-Path $Global:AppDir 'assets\sfx\engine.mp3'
            if (Test-Path $f) {
                if (-not $Global:Sfx.Rev) { $Global:Sfx.Rev = New-Object Windows.Media.MediaPlayer }
                $Global:Sfx.Rev.Open((New-Object Uri $f))
                $Global:Sfx.Rev.Volume = [Math]::Max(0.35, [double]$Global:CCH.Settings.Volume / 100.0 * 0.8)
                $Global:Sfx.Rev.Play()
            }
        } catch { }
    }
    $Global:Scan.Timer.Start()
    Pump-UI
}

function Set-ScanProgress([double]$Pct, [string]$Status) {
    $ui = $Global:UI
    if ($Status) { $ui.ScanStatus.Text = $Status }
    if ($Pct -ge 0 -and $Pct -gt $Global:Scan.Target) { $Global:Scan.Target = [Math]::Min(99.0, $Pct) }
    # the scan runs on the UI thread, so also move the ring here in case timer ticks are starved
    $s = [double]$Global:Scan.Shown
    $s = $s + ($Global:Scan.Target - $s) * 0.6
    $Global:Scan.Shown = $s
    Draw-ScanRing $s
}

function Complete-ScanLayer([scriptblock]$Then) {
    if (-not $Global:UI.ScanLayer -or $Global:UI.ScanLayer.Visibility -ne 'Visible') { if ($Then) { & $Then }; return }
    $Global:Scan.Then = $Then
    $Global:Scan.Target = 100.0
    $Global:Scan.Phase = 'finish'
    if (-not $Global:Scan.Timer.IsEnabled) { $Global:Scan.Timer.Start() }
}

function Hide-ScanLayer {
    $Global:Scan.Phase = 'idle'
    if ($Global:Scan.Timer) { $Global:Scan.Timer.Stop() }
    if ($Global:UI.ScanLayer) { $Global:UI.ScanLayer.Visibility = 'Collapsed' }
}

function Step-ScanLayer {
    $sc = $Global:Scan
    $ui = $Global:UI
    if ($sc.Phase -eq 'idle') { $sc.Timer.Stop(); return }
    if ($sc.Phase -eq 'run' -or $sc.Phase -eq 'finish') {
        $speed = $(if ($sc.Phase -eq 'finish') { 0.16 } else { 0.08 })
        $d = $sc.Target - $sc.Shown
        $sc.Shown = $sc.Shown + [Math]::Max([Math]::Min($d, 0.35), $d * $speed)
        # creep forward slowly during long steps so the ring never looks frozen
        if ($sc.Phase -eq 'run' -and $d -lt 0.3 -and $sc.Target -lt 96) { $sc.Target = $sc.Target + 0.03 }
        Draw-ScanRing $sc.Shown
        if ($sc.Phase -eq 'finish' -and $sc.Shown -ge 99.6) {
            Draw-ScanRing 100
            $sc.Phase = 'ready'; $sc.DoneTicks = [DateTime]::UtcNow.Ticks
            $ui.ScanStatus.Text = 'Ready'
            $ui.ScanStatus.Foreground = New-Object Windows.Media.SolidColorBrush (Get-AccentColor)
            if (-not $sc.Chimed) { $sc.Chimed = $true; Play-ReadyChime }
            try {
                $el = New-Object Windows.Media.Animation.ElasticEase; $el.Oscillations = 1; $el.Springiness = 4; $el.EasingMode = 'EaseOut'
                foreach ($dp in @([Windows.Media.ScaleTransform]::ScaleXProperty, [Windows.Media.ScaleTransform]::ScaleYProperty)) {
                    $a = New-Object Windows.Media.Animation.DoubleAnimation 1.12, 1.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(650)))
                    $a.EasingFunction = $el
                    $ui.ScanIcon.RenderTransform.BeginAnimation($dp, $a)
                }
            } catch { }
        }
        return
    }
    if ($sc.Phase -eq 'ready') {
        if (([DateTime]::UtcNow.Ticks - $sc.DoneTicks) / 1e4 -lt 850) { return }
        $sc.Phase = 'fade'; $sc.DoneTicks = [DateTime]::UtcNow.Ticks
        $a = New-Object Windows.Media.Animation.DoubleAnimation 1.0, 0.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(380)))
        $ui.ScanLayer.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
        return
    }
    if ($sc.Phase -eq 'fade') {
        if (([DateTime]::UtcNow.Ticks - $sc.DoneTicks) / 1e4 -lt 400) { return }
        $then = $sc.Then; $sc.Then = $null
        $ui.ScanLayer.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        $ui.ScanLayer.Opacity = 1.0
        $ui.ScanStatus.Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#8E949C'))
        Hide-ScanLayer
        if ($then) { try { & $then } catch { Write-Log "After-scan error: $($_.Exception.Message)" } }
    }
}

function Play-ReadyChime {
    if (-not $Global:CCH.Settings.StartSound) { return }
    try {
        $f = Join-Path $Global:AppDir 'assets\sfx\ready.mp3'
        if (-not (Test-Path $f)) { return }
        if (-not $Global:Sfx.Ready) { $Global:Sfx.Ready = New-Object Windows.Media.MediaPlayer }
        $Global:Sfx.Ready.Open((New-Object Uri $f))
        $Global:Sfx.Ready.Volume = [Math]::Max(0.5, [double]$Global:CCH.Settings.Volume / 100.0)
        $Global:Sfx.Ready.Position = [TimeSpan]::Zero
        $Global:Sfx.Ready.Play()
    } catch { }
}

# ==================================================================================================
#  ASK KURO  -  offline keyword help-bot (no internet, no real AI; a built-in FAQ assistant)
# ==================================================================================================

$Global:ChatFaq = @(
    @{ K = @('120', 'fps', 'frame', 'boost fps', 'more fps', 'increase'); A = "To chase 120 FPS: 1) Plug in your charger. 2) Dashboard > Apply all recommended. 3) Turn on Game Boost before you play. 4) In Roblox set Graphics Quality 1-3 and Max Frame Rate 120. On integrated graphics, light Roblox games can hit 120; heavy ones sit around 50-90." }
    @{ K = @('roblox'); A = "For Roblox: turn on the Roblox tweaks in Optimizations, then in-game press Esc > Settings: Graphics Mode = Manual, Quality 1-3, Maximum Frame Rate = 120. The old FPS-unlocker flags were blocked by Roblox in 2025; the in-game setting is the way now." }
    @{ K = @('premium', 'code', 'buy', 'unlock', 'pro', 'purchase'); A = "Premium unlocks the PRO tweaks and Game Boost. Grab a one-time code from our Discord, then paste it on the Premium page and hit Redeem. Each code works once and locks to your PC." }
    @{ K = @('redeem', 'activate', 'enter code'); A = "Go to the Premium page (star icon), type your CCH-XXXX-XXXX-XXXX code into the box and click Redeem. If it says invalid, check for typos - codes never contain 0, O, 1 or I." }
    @{ K = @('backup', 'undo', 'revert', 'restore', 'broke', 'broken', 'reverse'); A = "Nothing is permanent. Every tweak can be toggled off, and Tools > Revert everything undoes all of them at once. There's also a System Restore point created on your first change each day." }
    @{ K = @('antivirus', 'virus', 'defender', 'smartscreen', 'blocked', 'trust', 'safe', 'malware'); A = "Kuro is safe - it's new and unsigned, so SmartScreen/antivirus can warn. Click More info > Run anyway, and allow the folder in your antivirus. It never touches Defender, Windows Update or your files. You can scan the zip on virustotal.com if you want proof." }
    @{ K = @('music', 'song', 'sound', 'lofi', 'turn off music'); A = "Music is the pill in the title bar - click to play/pause, arrow to skip. To change or silence it, go to Colours, Vibes & Settings > Vibes and toggle the music or set the volume." }
    @{ K = @('mascot', 'anime', 'kuro', 'character', 'turn off', 'disable anime', 'girl'); A = "That's me. You can change which mascot shows, pick a different profile picture, or switch the anime art and effects off entirely in Colours, Vibes & Settings > Vibes." }
    @{ K = @('ram', 'memory', 'upgrade', 'slow', 'lag', 'stutter'); A = "Biggest wins on a low-end laptop: 1) dual-channel RAM (add a matching stick - if the scanner shows 'UHD' instead of 'Iris Xe' you're single-channel). 2) An SSD if you're on a hard drive. 3) Stay plugged in. Software tweaks add ~5-20% on top." }
    @{ K = @('driver', 'gpu', 'graphics', 'update driver'); A = "Update your graphics driver from Tools > Update GPU driver - it opens the right Intel/NVIDIA/AMD page for your card. New drivers regularly add FPS and fix stutter." }
    @{ K = @('bug', 'report', 'crash', 'error', 'not working', 'problem'); A = "Sorry about that! Use Support > Report a bug - it copies your PC info and recent log for you, then opens Discord so you can paste it. The more detail, the faster we fix it." }
    @{ K = @('discord', 'help', 'support', 'contact'); A = "The Discord is the place for help, bug reports and Premium codes. Hit 'Join our Discord' at the top of this page." }
    @{ K = @('safe for my pc', 'damage', 'risk', 'brick', 'harm'); A = "It's built to be safe: medium-risk tweaks ask first, everything is backed up, and it never disables security features. If anything feels off, Tools > Revert everything puts it all back." }
    @{ K = @('hi', 'hey', 'hello', 'yo', 'sup'); A = "Hey. Ask me anything about Kuro - FPS, Premium, Game Boost, bugs, whatever. Or tap one of the buttons above." }
    @{ K = @('thanks', 'thank', 'ty', 'cheers'); A = "Anytime. Now go get those frames." }
)
$Global:ChatChipQs = @('How do I get 120 FPS?', 'How do I buy Premium?', 'Is this safe?', 'Antivirus blocked it', 'How do I undo changes?')

function Get-ChatAnswer([string]$Text) {
    $t = ' ' + ($Text.ToLower() -replace '[^a-z0-9 ]', ' ') + ' '
    $best = $null; $bestScore = 0
    foreach ($f in $Global:ChatFaq) {
        $score = 0
        foreach ($k in $f.K) { if ($t -like ('*' + $k.ToLower() + '*')) { $score += $k.Length } }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $f }
    }
    if ($best) { return $best.A }
    return "I'm a simple offline helper, so I didn't quite catch that. Try asking about FPS, Premium codes, Game Boost, backups, or antivirus warnings - or join the Discord and a human will help you out."
}

function Add-ChatBubble([string]$Role, [string]$Text) {
    $isUser = ($Role -eq 'user')
    $border = New-Object Windows.Controls.Border
    $border.CornerRadius = New-Object Windows.CornerRadius $(if ($isUser) { '12,12,2,12' } else { '12,12,12,2' })
    $border.Padding = New-Object Windows.Thickness 13, 9, 13, 9
    $border.Margin = New-Object Windows.Thickness 0, 0, 0, 8
    $border.MaxWidth = 440
    $border.HorizontalAlignment = $(if ($isUser) { 'Right' } else { 'Left' })
    if ($isUser) {
        $border.Background = $Global:CCH.Window.Resources['AccentBrush']
    } else {
        $border.Background = $Global:CCH.Window.Resources['Panel2Brush']
        $border.BorderBrush = $Global:CCH.Window.Resources['AccentBrush']
        $border.BorderThickness = New-Object Windows.Thickness 1
    }
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.TextWrapping = 'Wrap'
    $tb.FontSize = 13
    if ($isUser) { $tb.Foreground = $Global:CCH.Window.Resources['OnAccentBrush'] } else { $tb.Foreground = $Global:CCH.Window.Resources['TextBrush'] }
    $border.Child = $tb
    [void]$Global:UI.ChatLog.Children.Add($border)
    $Global:UI.ChatScroll.ScrollToEnd()
}

function Send-ChatMessage([string]$Text) {
    $Text = $Text.Trim()
    if (-not $Text) { return }
    Add-ChatBubble 'user' $Text
    $Global:UI.ChatInput.Text = ''
    $ans = Get-ChatAnswer $Text
    Add-ChatBubble 'bot' $ans
}

function Connect-Chat {
    $ui = $Global:UI
    try { $ui.ChatAvatar.Source = (Get-MascotImage 'kuro') } catch { }
    Add-ChatBubble 'bot' "Hey, I'm Kuro - your offline helper. Ask me about FPS, Premium, Game Boost, bugs, or anything else. For real-person help, the Discord button up top is your friend."
    foreach ($q in $Global:ChatChipQs) {
        $rb = New-Object Windows.Controls.Button
        $rb.Style = $Global:CCH.Window.FindResource('GhostBtn')
        $rb.Content = $q
        $rb.Margin = New-Object Windows.Thickness 0, 0, 8, 8
        $rb.Padding = New-Object Windows.Thickness 12, 6, 12, 6
        $rb.FontSize = 12
        $rb.Add_Click({ Send-ChatMessage ([string]$this.Content) }.GetNewClosure())
        [void]$ui.ChatChips.Children.Add($rb)
    }
    $ui.BtnChatSend.Add_Click({ Send-ChatMessage $Global:UI.ChatInput.Text })
    $ui.ChatInput.Add_KeyDown({ if ($_.Key -eq 'Return') { Send-ChatMessage $Global:UI.ChatInput.Text } })
}

# ==================================================================================================
#  FIRST-RUN TUTORIAL  (Kuro walks new users through the app)
# ==================================================================================================

$Global:TutorialSteps = @(
    @{ Page = 'PageDash';    Title = 'Hey, I''m Kuro'; Body = "Welcome to Kuro. I'll give you the 20-second tour. This is your Dashboard - your ""% Optimized"" score and the top tweaks picked for your exact PC live here." }
    @{ Page = 'PageDash';    Title = 'One-click optimize'; Body = "See 'Apply all recommended'? That applies every tweak that suits your laptop in one go. Everything is backed up, so you can undo it any time." }
    @{ Page = 'PageScan';    Title = 'Know your PC'; Body = "The Scanner shows your real specs and honest FPS expectations - and tells you the single best upgrade for your machine. Worth a read." }
    @{ Page = 'PageBoost';   Title = 'Game Boost'; Body = "Before you play, hit Game Boost. It frees RAM, closes background junk, maxes your power mode and gives your game priority. Turn it off and everything goes back." }
    @{ Page = 'PageOptim';   Title = 'All the tweaks'; Body = "Every tweak lives here, grouped and searchable. Green means 'recommended for your PC'. Flip any switch; flip it back if you change your mind." }
    @{ Page = 'PageTheme';   Title = 'Make it yours'; Body = "Change my look, the colours, the music and effects here - or switch me off entirely if you want. Your call." }
    @{ Page = 'PageSupport'; Title = 'Stuck? Ask me'; Body = "Questions or bugs? Ask me on the Support page, or jump into the Discord. That's it - go get those frames!" }
)
$Global:TutorialIdx = 0

function Show-TutorialStep {
    $i = $Global:TutorialIdx
    $steps = $Global:TutorialSteps
    if ($i -ge $steps.Count) { Stop-Tutorial; return }
    $st = $steps[$i]
    Show-Page $st.Page
    $Global:UI.TutorialImg.Source = (Get-MascotImage 'kuro')
    $Global:UI.TutorialTitle.Text = $st.Title
    $Global:UI.TutorialBody.Text = $st.Body
    $Global:UI.TutorialStep.Text = ('Step {0} of {1}' -f ($i + 1), $steps.Count)
    $Global:UI.BtnTutNext.Content = $(if ($i -eq $steps.Count - 1) { "Let's go!" } else { 'Next' })
    Start-Talk $Global:UI.TutorialImg $Global:UI.TutorialBody $st.Body
}

function Start-Tutorial {
    $Global:TutorialIdx = 0
    $Global:UI.TutorialLayer.Visibility = 'Visible'
    Show-TutorialStep
}

function Stop-Tutorial {
    $Global:UI.TutorialLayer.Visibility = 'Collapsed'
    $Global:CCH.Settings.TutorialDone = $true
    Save-Settings
    Show-Page 'PageDash'
    Start-TipLoop
    Show-Fx 'sparkle' ''
}

function Connect-Tutorial {
    $Global:UI.BtnTutNext.Add_Click({ $Global:TutorialIdx++; Show-TutorialStep })
    $Global:UI.BtnTutSkip.Add_Click({ Stop-Tutorial })
}

# ==================================================================================================
#  AUTO-UPDATE  (optional) - pulls changed files from the owner's update URL so users never redownload.
#  Downloads each changed file to <file>.kuroupd, verifies its SHA-256 against the signed manifest, and
#  applies them on the next launch (see the apply step in 01-core). Needs the owner to host the folder.
# ==================================================================================================

function Get-FileSha256([string]$Path) {
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        $fs = [IO.File]::OpenRead($Path)
        try { $h = $sha.ComputeHash($fs) } finally { $fs.Close(); $sha.Dispose() }
        return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
    } catch { return '' }
}

function Get-UpdateBase {
    $u = [string]$Global:CCH.Settings.UpdateUrl
    if (-not $u) { $u = [string]$Global:DefaultUpdateUrl }
    return $u.TrimEnd('/')
}

function Get-UpdateManifest {
    $base = Get-UpdateBase
    if (-not $base) { return $null }
    if ($base -notmatch '^https://') { Write-Log 'Update URL must start with https://'; return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        return Invoke-RestMethod -Uri ($base + '/manifest.json') -TimeoutSec 20 -ErrorAction Stop
    } catch { Write-Log "Update check failed: $($_.Exception.Message)"; return $null }
}

function Test-NewerVersion([string]$Remote, [string]$Local) {
    try {
        $r = [version]($Remote -replace '[^0-9.]', ''); $l = [version]($Local -replace '[^0-9.]', '')
        return ($r -gt $l)
    } catch { return ($Remote -ne $Local) }
}

# One worker for both the manual and the background check.
# - Never downgrades (remote older than local = nothing to do).
# - Same or newer version: every file in the manifest is hashed; any missing/changed file is downloaded.
#   So a file that failed last time, or got deleted/damaged, is repaired on the next check.
# - All or nothing: if any file fails to download or verify, every file staged in this run is discarded
#   and the whole update retries later, so users never end up with half of one version and half of another.
$Global:UpdateWorker = {
    param($app, $ver, $url)
    $r = @{ changed = 0; failed = 0; version = ''; error = ''; newer = $false }
    $staged = New-Object System.Collections.ArrayList
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $base = $url.TrimEnd('/')
        # The manifest must carry the owner's signature (manifest.sig). The private key is never on GitHub,
        # so a hijacked GitHub account or a tampered download cannot push an update that Kuro accepts.
        $pub = '<RSAKeyValue><Modulus>3y3mawPtmS9z5Q2awo74NrwUqwYsw40RPh/nohG5fTthf1kZsAi4MTso5Zy1xFPPtT/PYJuIrktOhKGJ/9vAg50LOhvP2ODj1ukvC6bJR0VHbMlJx1wn1Fdi5QWsERnce3qMaOaD/d5iuXPWRvXbnLXkh6EMI26PLlNYj+09T05DcL9gN69/+eFGSpUWmoYZqqcqJAKLwkgbCGi4QTnRgBJM7UAKcLTWwV6Cg/b0ypgX4dy6SpEhPehSdEjgWeUPC4cCSWYGM1MYtn44KgPqH2PEax06Fcatu9w5SGOu4qfLAFpkjByH+nxcPv17wvMD9z27JuN01n2iCjlYGm13jMmYBZqKEY+ugEOLFpOOxNHPur4AalCQBrpqV9JsaSfuEL20Dko1llIiWmfRc1JKuywsvMPdrM3w38FeRnOwNvtOQSP4eQAWsBRZ/mOXD8/AFSUcB5POsFngO5gYJyc7HbQH3C/U0/5IjlbwiYH3lfveG3F4mQroFVitqXynatXF</Modulus><Exponent>AQAB</Exponent></RSAKeyValue>'
        $nc = [DateTime]::UtcNow.Ticks
        $wc = New-Object Net.WebClient
        try {
            $mb = $wc.DownloadData($base + '/manifest.json?nocache=' + $nc)
            $sg = ($wc.DownloadString($base + '/manifest.sig?nocache=' + $nc)).Trim()
        } finally { $wc.Dispose() }
        $rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
        try { $rsa.FromXmlString($pub); $okSig = $rsa.VerifyData($mb, 'SHA256', [Convert]::FromBase64String($sg)) } catch { $okSig = $false } finally { $rsa.Dispose() }
        if (-not $okSig) { $r.error = 'The update was not signed by the Kuro owner, so it was refused.'; $r.failed = 1; return $r }
        $mt = [Text.Encoding]::UTF8.GetString($mb)
        if ($mt.Length -gt 0 -and $mt[0] -eq [char]0xFEFF) { $mt = $mt.Substring(1) }
        $m = $mt | ConvertFrom-Json
        $r.version = [string]$m.version
        $rv = [version](([string]$m.version) -replace '[^0-9.]', ''); $lv = [version]($ver -replace '[^0-9.]', '')
        if ($rv -lt $lv) { return $r }
        $r.newer = ($rv -gt $lv)
        foreach ($prop in $m.files.PSObject.Properties) {
            $rel = [string]$prop.Name; $want = ([string]$prop.Value).ToLowerInvariant()
            if ($rel -match '\.kuroupd$' -or $rel -eq 'manifest.json' -or $rel -eq 'manifest.sig' -or $rel -like '*..*' -or $rel -match '^[\\/]' -or $rel -match ':') { continue }
            if ($want -notmatch '^[0-9a-f]{64}$') { continue }
            $local = Join-Path $app $rel
            if (Test-Path -LiteralPath $local) {
                $sha = [Security.Cryptography.SHA256]::Create(); $fs = [IO.File]::OpenRead($local)
                try { $cur = (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $fs.Close(); $sha.Dispose() }
                if ($cur -eq $want) { continue }
            }
            $tmp = $local + '.kuroupd'; $dir = Split-Path -Parent $tmp
            try {
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                Invoke-WebRequest -Uri ($base + '/' + (($rel -replace '\\', '/') -replace ' ', '%20')) -OutFile $tmp -TimeoutSec 180 -UseBasicParsing -ErrorAction Stop
                $sha = [Security.Cryptography.SHA256]::Create(); $fs = [IO.File]::OpenRead($tmp)
                try { $dh = (($sha.ComputeHash($fs) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $fs.Close(); $sha.Dispose() }
                if ($dh -eq $want) { [void]$staged.Add($tmp) } else { $r.failed++; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            } catch { $r.failed++; Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    } catch { $r.error = $_.Exception.Message }
    if ($r.failed -gt 0 -or $r.error) {
        foreach ($t in $staged) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
        $r.changed = 0
    } else { $r.changed = $staged.Count }
    return $r
}

function Restart-Kuro {
    $ps1 = Join-Path $Global:AppDir 'Kuro.ps1'
    $cmd = 'timeout /t 2 /nobreak >nul & start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "' + $ps1 + '"'
    try {
        Start-Process -FilePath 'cmd.exe' -ArgumentList ('/c ' + $cmd) -WindowStyle Hidden -ErrorAction Stop | Out-Null
        Write-Log 'Restarting to install the update.'
        $Global:CCH.Window.Close()
    } catch { Show-Toast ('Could not restart: ' + $_.Exception.Message + ' Close and reopen Kuro instead.') 'error' }
}

function Show-UpdateReady($Res) {
    $Global:UpdateJob.Staged = $true
    Write-Log "Update: $($Res.changed) file(s) staged for v$($Res.version)."
    $what = $(if ($Res.newer) { "Kuro v$($Res.version) is downloaded" } else { "A small update ($($Res.changed) file(s)) is downloaded" })
    Show-Modal 'Update ready' ("$what and checked. It installs when Kuro restarts.") 'Restart now' 'Later' { Restart-Kuro } $null 'star'
}

function Invoke-Update([bool]$Silent = $true) {
    $base = Get-UpdateBase
    if (-not $base) { if (-not $Silent) { Show-Toast 'No update URL is set (Settings).' 'info' }; return }
    if ($base -notmatch '^https://') { if (-not $Silent) { Show-Toast 'The update URL must start with https://' 'error' }; return }
    if (-not $Silent) { Show-Busy 'Checking for updates...' 'Every file is checked against the newest version' }
    $res = & $Global:UpdateWorker $Global:AppDir $Global:CCH_Version $base
    if (-not $Silent) { Hide-Busy }
    if ($res.error) { Write-Log "Update check failed: $($res.error)"; if (-not $Silent) { Show-Toast 'Could not reach the update server.' 'error' }; return }
    if ($res.failed -gt 0) { Write-Log "Update v$($res.version): $($res.failed) file(s) failed; nothing installed, will retry."; if (-not $Silent) { Show-Toast "Update found, but $($res.failed) file(s) could not be downloaded. Nothing was changed; it will retry." 'error' }; return }
    if ($res.changed -gt 0) { Show-UpdateReady $res; return }
    if (-not $Silent) { Show-Toast ("You're up to date (v$($Global:CCH_Version)). Every file checked.") }
}

$Global:UpdateJob = @{ PS = $null; Handle = $null; Timer = $null; Every = $null; Busy = $false }
function Start-UpdateCheck {
    $updBase = Get-UpdateBase
    if (-not $Global:CCH.Settings.AutoUpdate -or -not $updBase) { return }
    if ($updBase -notmatch '^https://') { return }
    if ($Global:UpdateJob.Busy -or $Global:UpdateJob.Staged) { return }
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Global:UpdateWorker.ToString()).AddArgument($Global:AppDir).AddArgument($Global:CCH_Version).AddArgument($updBase)
        $Global:UpdateJob.PS = $ps; $Global:UpdateJob.Handle = $ps.BeginInvoke(); $Global:UpdateJob.Busy = $true
        if (-not $Global:UpdateJob.Timer) {
            $timer = New-Object Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromSeconds(1.5)
            $timer.Add_Tick({
                if (-not $Global:UpdateJob.Handle.IsCompleted) { return }
                $Global:UpdateJob.Timer.Stop(); $Global:UpdateJob.Busy = $false
                $res = $null
                try { $res = @($Global:UpdateJob.PS.EndInvoke($Global:UpdateJob.Handle))[0] } catch { }
                try { $Global:UpdateJob.PS.Dispose() } catch { }
                if (-not $res) { return }
                if ($res.error) { Write-Log "Auto-update check failed: $($res.error)"; return }
                if ($res.failed -gt 0) { Write-Log "Auto-update v$($res.version): $($res.failed) file(s) failed; nothing installed, will retry."; return }
                if ([int]$res.changed -gt 0) { Show-UpdateReady $res }
            })
            $Global:UpdateJob.Timer = $timer
        }
        $Global:UpdateJob.Timer.Start()
        # check again every 3 hours while Kuro stays open
        if (-not $Global:UpdateJob.Every) {
            $e = New-Object Windows.Threading.DispatcherTimer
            $e.Interval = [TimeSpan]::FromHours(3)
            $e.Add_Tick({ try { Start-UpdateCheck } catch { } })
            $e.Start(); $Global:UpdateJob.Every = $e
        }
    } catch { $Global:UpdateJob.Busy = $false; Write-Log "Update check could not start: $($_.Exception.Message)" }
}

# ==================================================================================================
#  MACROS  - auto-clicker / key / scroll macros (input automation via SendInput; no game memory access)
#  Mouse triggers use a low-level MOUSE hook (physical buttons only, injected input ignored);
#  keyboard triggers are polled with GetAsyncKeyState (no keyboard hook). Engine loads on first use.
# ==================================================================================================

$Global:MacroCs = @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public class KuroMacroSlot {
    public bool Enabled;
    public int Trigger;
    public int TriggerVk;
    public bool Toggle;
    public int Action;
    public int ActionVk;
    public double Cps = 10;
    public double JitterPct = 10;
    public int BowHoldMs = 500;
    public bool ToggledOn;
    public bool PrevTriggerDown;
    public double NextAt;
    public bool WheelFlip;
    public bool BowHolding;
    public bool WasActive;
    public double DutyPct;
    public bool SecondPending;
    public double SecondAt;
    public uint SecondFlag;
}

public class KuroSeqStep {
    public int Kind;
    public int Vk;
    public int Mods;
    public int Button;
    public int X;
    public int Y;
    public int Ms = 30;
    public int Ms2;
    public int Count = 1;
    public double Cps = 10;
    public string Text = "";
}

public class KuroSeq {
    public bool Enabled;
    public int Trigger;
    public int TriggerVk;
    public int Mode;
    public int Repeat = 1;
    public KuroSeqStep[] Steps = new KuroSeqStep[0];
    public volatile bool Running;
    public volatile bool Cancel;
    public volatile int Pos = -1;
    public bool PrevDown;
    public bool ToggleOn;
}

public static class KuroMacro {
    [StructLayout(LayoutKind.Sequential)]
    struct MOUSEINPUT { public int dx; public int dy; public int mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }
    [StructLayout(LayoutKind.Explicit)]
    struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct INPUT { public uint type; public InputUnion U; }
    [StructLayout(LayoutKind.Sequential)]
    struct POINT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public POINT pt; }
    [StructLayout(LayoutKind.Sequential)]
    struct MSLLHOOKSTRUCT { public POINT pt; public uint mouseData; public uint flags; public uint time; public IntPtr dwExtraInfo; }

    delegate IntPtr LowLevelProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint uCode, uint uMapType);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint uPeriod);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint uPeriod);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SetWindowsHookEx(int idHook, LowLevelProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string lpModuleName);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
    [DllImport("user32.dll")] static extern bool PostThreadMessage(uint idThread, uint Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int nIndex);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
    [StructLayout(LayoutKind.Sequential)]
    struct KBDLLHOOKSTRUCT { public uint vkCode; public uint scanCode; public uint flags; public uint time; public IntPtr dwExtraInfo; }

    const uint LDOWN = 0x0002, LUP = 0x0004, RDOWN = 0x0008, RUP = 0x0010, WHEEL = 0x0800;

    public static volatile KuroMacroSlot[] Slots = new KuroMacroSlot[0];
    public static volatile bool Running;
    public static volatile bool Paused;
    public static volatile bool RobloxOnly = true;
    public static volatile int PauseVk = 0x77;
    public static volatile bool Active;
    public static volatile bool PhysLeft, PhysRight, PhysMiddle, PhysX1, PhysX2;
    public static volatile string LastError = "";
    static long sent;
    public static volatile KuroSeq[] Seqs = new KuroSeq[0];
    public static long SentCount() { return Interlocked.Read(ref sent); }

    static Thread worker;
    static Thread hookThread;
    static volatile uint hookThreadId;
    static IntPtr hookId = IntPtr.Zero;
    static LowLevelProc hookDelegate;
    static IntPtr fgHwnd = IntPtr.Zero;
    static bool fgOk;
    static int InputSize = Marshal.SizeOf(typeof(INPUT));

    static IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam) {
        try {
            if (nCode >= 0) {
                MSLLHOOKSTRUCT h = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                if ((h.flags & 0x03u) == 0) {
                    long msg = wParam.ToInt64();
                    if (msg == 0x0201) PhysLeft = true;
                    else if (msg == 0x0202) PhysLeft = false;
                    else if (msg == 0x0204) PhysRight = true;
                    else if (msg == 0x0205) PhysRight = false;
                    else if (msg == 0x0207) PhysMiddle = true;
                    else if (msg == 0x0208) PhysMiddle = false;
                    else if (msg == 0x020B || msg == 0x020C) {
                        uint xb = (h.mouseData >> 16) & 0xFFFFu;
                        bool down = (msg == 0x020B);
                        if (xb == 1) PhysX1 = down; else if (xb == 2) PhysX2 = down;
                    }
                }
            }
        } catch { }
        return CallNextHookEx(hookId, nCode, wParam, lParam);
    }

    static void HookThreadMain() {
        try {
            hookThreadId = GetCurrentThreadId();
            hookDelegate = new LowLevelProc(HookProc);
            IntPtr mod = IntPtr.Zero;
            try { mod = GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName); } catch { }
            hookId = SetWindowsHookEx(14, hookDelegate, mod, 0);
            if (hookId == IntPtr.Zero) { LastError = "Mouse hook could not start (error " + Marshal.GetLastWin32Error() + "). Keyboard triggers still work."; return; }
            MSG m;
            while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        } catch (Exception e) { LastError = e.Message; }
        finally {
            if (hookId != IntPtr.Zero) { UnhookWindowsHookEx(hookId); hookId = IntPtr.Zero; }
        }
    }

    static bool ForegroundOk() {
        if (!RobloxOnly) return true;
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return false;
        if (h == fgHwnd) return fgOk;
        bool ok = false;
        try {
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            string n = Process.GetProcessById((int)pid).ProcessName;
            ok = n.Equals("RobloxPlayerBeta", StringComparison.OrdinalIgnoreCase) || n.Equals("Windows10Universal", StringComparison.OrdinalIgnoreCase);
        } catch { ok = false; }
        fgHwnd = h; fgOk = ok;
        return ok;
    }

    static INPUT MouseIn(uint flags, int data) {
        INPUT i = new INPUT();
        i.type = 0;
        i.U.mi.dwFlags = flags;
        i.U.mi.mouseData = data;
        return i;
    }

    static INPUT KeyIn(int vk, bool up) {
        INPUT i = new INPUT();
        i.type = 1;
        i.U.ki.wVk = (ushort)vk;
        i.U.ki.wScan = (ushort)MapVirtualKey((uint)vk, 0);
        uint f = up ? 2u : 0u;
        if (IsExtended(vk)) f |= 1u;
        i.U.ki.dwFlags = f;
        return i;
    }

    static bool IsExtended(int vk) {
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E || vk == 0x5B || vk == 0x5C || vk == 0x5D
            || vk == 0x6F || vk == 0x90 || vk == 0xA3 || vk == 0xA5;
    }

    static INPUT CharIn(char c, bool up) {
        INPUT i = new INPUT();
        i.type = 1;
        i.U.ki.wVk = 0;
        i.U.ki.wScan = (ushort)c;
        i.U.ki.dwFlags = up ? 6u : 4u;
        return i;
    }

    static INPUT MoveIn(int dx, int dy, uint flags) {
        INPUT i = new INPUT();
        i.type = 0;
        i.U.mi.dx = dx;
        i.U.mi.dy = dy;
        i.U.mi.dwFlags = flags;
        return i;
    }

    static uint BtnDown(int b) { return b == 1 ? RDOWN : (b == 2 ? 0x0020u : LDOWN); }
    static uint BtnUp(int b) { return b == 1 ? RUP : (b == 2 ? 0x0040u : LUP); }

    public static int[] CursorPos() {
        POINT p;
        if (!GetCursorPos(out p)) return new int[] { 0, 0 };
        return new int[] { p.x, p.y };
    }

    static void Send(params INPUT[] arr) { SendInput((uint)arr.Length, arr, InputSize); }

    static bool KeyDown(int vk) { return vk > 0 && (GetAsyncKeyState(vk) & 0x8000) != 0; }

    static bool TriggerDown(KuroMacroSlot s) {
        switch (s.Trigger) {
            case 0: return PhysLeft;
            case 1: return PhysRight;
            case 2: return PhysX1;
            case 3: return PhysX2;
            case 4: return PhysMiddle;
            case 5: return KeyDown(s.TriggerVk);
        }
        return false;
    }

    static bool TrigDown(int trigger, int vk) {
        switch (trigger) {
            case 0: return PhysLeft;
            case 1: return PhysRight;
            case 2: return PhysX1;
            case 3: return PhysX2;
            case 4: return PhysMiddle;
            case 5: return KeyDown(vk);
        }
        return false;
    }

    // ---------------- step sequences ----------------
    static bool SleepCancel(KuroSeq q, int ms) {
        if (ms <= 0) return !q.Cancel;
        Stopwatch w = Stopwatch.StartNew();
        while (w.ElapsedMilliseconds < ms) {
            if (q.Cancel) return false;
            if (KeyDown(PauseVk)) { q.Cancel = true; return false; }
            long left = ms - w.ElapsedMilliseconds;
            Thread.Sleep((int)Math.Max(1, Math.Min(5, left)));
        }
        return !q.Cancel;
    }

    static void ClickOnce(int b) { Send(MoveIn(0, 0, BtnDown(b)), MoveIn(0, 0, BtnUp(b))); }

    static void RunStep(KuroSeq q, KuroSeqStep s, bool[] keys, bool[] btns) {
        int vk = s.Vk & 0xFF;
        int b = Math.Max(0, Math.Min(2, s.Button));
        switch (s.Kind) {
            case 0:
                if (vk == 0) return;
                Send(KeyIn(vk, false)); keys[vk] = true;
                SleepCancel(q, Math.Max(1, s.Ms));
                Send(KeyIn(vk, true)); keys[vk] = false;
                break;
            case 1: ClickOnce(b); break;
            case 2: SleepCancel(q, s.Ms); break;
            case 3: {
                double cps = Math.Max(1.0, Math.Min(50.0, s.Cps));
                int n = Math.Max(1, Math.Min(1000, s.Count));
                for (int c = 0; c < n && !q.Cancel; c++) {
                    ClickOnce(b);
                    if (c < n - 1 && !SleepCancel(q, (int)(1000.0 / cps))) break;
                }
                break;
            }
            case 4: {
                string t = s.Text ?? "";
                int gap = Math.Max(0, Math.Min(500, s.Ms));
                for (int c = 0; c < t.Length && c < 500 && !q.Cancel; c++) {
                    char ch = t[c];
                    if (ch == '\r') continue;
                    if (ch == '\n') Send(KeyIn(0x0D, false), KeyIn(0x0D, true));
                    else Send(CharIn(ch, false), CharIn(ch, true));
                    if (gap > 0 && !SleepCancel(q, gap)) break;
                }
                break;
            }
            case 5: {
                if (vk == 0) return;
                int[] mods = new int[] { 0x11, 0x10, 0x12, 0x5B };
                for (int m = 0; m < 4; m++) if ((s.Mods & (1 << m)) != 0) { Send(KeyIn(mods[m], false)); keys[mods[m]] = true; }
                Send(KeyIn(vk, false), KeyIn(vk, true));
                for (int m = 3; m >= 0; m--) if ((s.Mods & (1 << m)) != 0) { Send(KeyIn(mods[m], true)); keys[mods[m]] = false; }
                break;
            }
            case 6: ClickOnce(b); SleepCancel(q, 40); ClickOnce(b); break;
            case 7: {
                int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
                if (vw < 2 || vh < 2) return;
                int ax = (int)(((long)(s.X - vx) * 65535) / (vw - 1));
                int ay = (int)(((long)(s.Y - vy) * 65535) / (vh - 1));
                Send(MoveIn(ax, ay, 0x0001u | 0x8000u | 0x4000u));
                break;
            }
            case 8: Send(MoveIn(s.X, s.Y, 0x0001u)); break;
            case 9: {
                int n = Math.Max(-100, Math.Min(100, s.Count));
                int dir = n < 0 ? -120 : 120;
                for (int c = 0; c < Math.Abs(n) && !q.Cancel; c++) {
                    Send(MouseIn(WHEEL, dir));
                    if (c < Math.Abs(n) - 1 && !SleepCancel(q, 15)) break;
                }
                break;
            }
            case 10: {
                int lo = Math.Max(0, Math.Min(s.Ms, s.Ms2)), hi = Math.Max(s.Ms, s.Ms2);
                SleepCancel(q, lo + Rng.Next(Math.Max(1, hi - lo + 1)));
                break;
            }
            case 11: break;
            case 12: if (vk != 0) { Send(KeyIn(vk, false)); keys[vk] = true; } break;
            case 13: if (vk != 0) { Send(KeyIn(vk, true)); keys[vk] = false; } break;
            case 14: Send(MouseIn(BtnDown(b), 0)); btns[b] = true; break;
            case 15: Send(MouseIn(BtnUp(b), 0)); btns[b] = false; break;
        }
    }

    static Random Rng = new Random();

    static void RunSeq(KuroSeq q, int plays, int delayMs) {
        bool[] keys = new bool[256];
        bool[] btns = new bool[3];
        timeBeginPeriod(1);
        try {
            if (delayMs > 0 && !SleepCancel(q, delayMs)) return;
            int n = 0;
            while (!q.Cancel && (plays < 0 || n < plays)) {
                Stopwatch sw = Stopwatch.StartNew();
                KuroSeqStep[] st = q.Steps;
                for (int i = 0; i < st.Length && !q.Cancel; i++) {
                    if (KeyDown(PauseVk)) { q.Cancel = true; break; }
                    q.Pos = i;
                    if (st[i] != null) RunStep(q, st[i], keys, btns);
                }
                n++;
                // never loop faster than 100 plays a second, even with empty or instant blocks
                long el = sw.ElapsedMilliseconds;
                if (el < 10 && !SleepCancel(q, (int)(10 - el))) break;
            }
        } catch (Exception e) { LastError = e.Message; }
        finally {
            for (int k = 0; k < 256; k++) if (keys[k]) Send(KeyIn(k, true));
            for (int k = 0; k < 3; k++) if (btns[k]) Send(MouseIn(BtnUp(k), 0));
            q.Pos = -1;
            q.Running = false;
            timeEndPeriod(1);
        }
    }

    static void StartSeq(KuroSeq q, int plays, int delayMs) {
        if (q.Running || q.Steps == null || q.Steps.Length == 0) return;
        q.Cancel = false;
        q.Running = true;
        Thread t = new Thread(delegate() { RunSeq(q, plays, delayMs); });
        t.IsBackground = true;
        t.Priority = ThreadPriority.AboveNormal;
        t.Start();
    }

    public static bool TestSeq(KuroSeq q, int delayMs) {
        if (q == null || q.Running) return false;
        StartSeq(q, 1, delayMs);
        return q.Running;
    }

    public static void CancelSeqs() {
        KuroSeq[] a = Seqs;
        for (int i = 0; i < a.Length; i++) if (a[i] != null) { a[i].Cancel = true; a[i].ToggleOn = false; }
    }

    static void TickSeqs(bool allowed, ref bool any) {
        KuroSeq[] seqs = Seqs;
        for (int j = 0; j < seqs.Length; j++) {
            KuroSeq q = seqs[j];
            if (q == null) continue;
            bool down = q.Enabled && TrigDown(q.Trigger, q.TriggerVk);
            bool edge = down && !q.PrevDown;
            q.PrevDown = down;
            if (!allowed || !q.Enabled) {
                if (q.Running) q.Cancel = true;
                q.ToggleOn = false;
                continue;
            }
            switch (q.Mode) {
                case 0: if (edge) StartSeq(q, 1, 0); break;
                case 1: if (edge) StartSeq(q, Math.Max(1, Math.Min(1000, q.Repeat)), 0); break;
                case 2:
                    if (down && !q.Running) StartSeq(q, -1, 0);
                    else if (!down && q.Running) q.Cancel = true;
                    break;
                case 3:
                    if (edge) {
                        q.ToggleOn = !q.ToggleOn;
                        if (q.ToggleOn) StartSeq(q, -1, 0); else q.Cancel = true;
                    }
                    break;
            }
            if (q.Running) any = true;
        }
    }

    // ---------------- recorder (only while the user records) ----------------
    static volatile bool recOn;
    static Thread recThread;
    static volatile uint recThreadId;
    static IntPtr recKb = IntPtr.Zero, recMs = IntPtr.Zero;
    static LowLevelProc recKbDel, recMsDel;
    static System.Collections.Generic.List<string> recEv = new System.Collections.Generic.List<string>();
    static Stopwatch recClock;
    static bool[] recDown = new bool[256];
    static uint ownPid = (uint)Process.GetCurrentProcess().Id;

    static bool RecOwnWindow() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return false;
        uint pid; GetWindowThreadProcessId(h, out pid);
        return pid == ownPid;
    }

    static void RecAdd(string type, int code, int x, int y) {
        lock (recEv) { if (recEv.Count < 5000) recEv.Add(recClock.ElapsedMilliseconds + "|" + type + "|" + code + "|" + x + "|" + y); }
    }

    static IntPtr RecKbProc(int nCode, IntPtr wParam, IntPtr lParam) {
        try {
            if (nCode >= 0 && recOn) {
                KBDLLHOOKSTRUCT k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                if ((k.flags & 0x10u) == 0 && !RecOwnWindow()) {
                    int vk = (int)(k.vkCode & 0xFF);
                    long msg = wParam.ToInt64();
                    if (vk != PauseVk) {
                        if (msg == 0x0100 || msg == 0x0104) { if (!recDown[vk]) { recDown[vk] = true; RecAdd("kd", vk, 0, 0); } }
                        else if (msg == 0x0101 || msg == 0x0105) { if (recDown[vk]) { recDown[vk] = false; RecAdd("ku", vk, 0, 0); } }
                    }
                }
            }
        } catch { }
        return CallNextHookEx(recKb, nCode, wParam, lParam);
    }

    static IntPtr RecMsProc(int nCode, IntPtr wParam, IntPtr lParam) {
        try {
            if (nCode >= 0 && recOn) {
                MSLLHOOKSTRUCT h = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                if ((h.flags & 0x03u) == 0 && !RecOwnWindow()) {
                    long msg = wParam.ToInt64();
                    if (msg == 0x0201) RecAdd("md", 0, h.pt.x, h.pt.y);
                    else if (msg == 0x0202) RecAdd("mu", 0, h.pt.x, h.pt.y);
                    else if (msg == 0x0204) RecAdd("md", 1, h.pt.x, h.pt.y);
                    else if (msg == 0x0205) RecAdd("mu", 1, h.pt.x, h.pt.y);
                    else if (msg == 0x0207) RecAdd("md", 2, h.pt.x, h.pt.y);
                    else if (msg == 0x0208) RecAdd("mu", 2, h.pt.x, h.pt.y);
                    else if (msg == 0x020A) RecAdd("wh", (short)((h.mouseData >> 16) & 0xFFFF), h.pt.x, h.pt.y);
                }
            }
        } catch { }
        return CallNextHookEx(recMs, nCode, wParam, lParam);
    }

    static void RecThreadMain() {
        try {
            recThreadId = GetCurrentThreadId();
            recKbDel = new LowLevelProc(RecKbProc);
            recMsDel = new LowLevelProc(RecMsProc);
            IntPtr mod = IntPtr.Zero;
            try { mod = GetModuleHandle(Process.GetCurrentProcess().MainModule.ModuleName); } catch { }
            recKb = SetWindowsHookEx(13, recKbDel, mod, 0);
            recMs = SetWindowsHookEx(14, recMsDel, mod, 0);
            if (recKb == IntPtr.Zero && recMs == IntPtr.Zero) { LastError = "Recorder could not start (error " + Marshal.GetLastWin32Error() + ")."; recOn = false; return; }
            MSG m;
            while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
        } catch (Exception e) { LastError = e.Message; }
        finally {
            if (recKb != IntPtr.Zero) { UnhookWindowsHookEx(recKb); recKb = IntPtr.Zero; }
            if (recMs != IntPtr.Zero) { UnhookWindowsHookEx(recMs); recMs = IntPtr.Zero; }
            recThreadId = 0;
        }
    }

    public static bool Recording { get { return recOn; } }

    public static string RecStart() {
        if (recOn) return "ok";
        try {
            lock (recEv) { recEv.Clear(); }
            recDown = new bool[256];
            recClock = Stopwatch.StartNew();
            recOn = true;
            recThread = new Thread(RecThreadMain);
            recThread.IsBackground = true;
            recThread.Start();
            return "ok";
        } catch (Exception e) { recOn = false; return e.Message; }
    }

    public static string[] RecStop() {
        recOn = false;
        for (int k = 0; k < 20 && recThreadId == 0 && recThread != null && recThread.IsAlive; k++) Thread.Sleep(10);
        if (recThreadId != 0) PostThreadMessage(recThreadId, 0x0012, IntPtr.Zero, IntPtr.Zero);
        lock (recEv) { return recEv.ToArray(); }
    }

    static bool SameButton(KuroMacroSlot s) {
        return (s.Trigger == 0 && s.Action == 0) || (s.Trigger == 1 && (s.Action == 1 || s.Action == 2));
    }

    static void ClickButton(bool right, bool same) {
        uint d = right ? RDOWN : LDOWN;
        uint u = right ? RUP : LUP;
        if (same) Send(MouseIn(u, 0), MouseIn(d, 0));
        else Send(MouseIn(d, 0), MouseIn(u, 0));
    }

    static void Release(KuroMacroSlot s) {
        if (s.BowHolding) { Send(MouseIn(RUP, 0)); s.BowHolding = false; return; }
        if (SameButton(s)) {
            if (s.Action == 0) Send(MouseIn(LUP, 0));
            else if (s.Action == 1) Send(MouseIn(RUP, 0));
        }
    }

    static void WorkerMain() {
        timeBeginPeriod(1);
        Stopwatch sw = Stopwatch.StartNew();
        Random rng = new Random();
        bool pausePrev = false;
        try {
            while (Running) {
                bool p = KeyDown(PauseVk);
                if (p && !pausePrev) Paused = !Paused;
                pausePrev = p;
                bool focus = ForegroundOk();
                double now = sw.Elapsed.TotalMilliseconds;
                bool any = false;
                KuroMacroSlot[] slots = Slots;
                for (int i = 0; i < slots.Length; i++) {
                    KuroMacroSlot s = slots[i];
                    if (s == null) continue;
                    bool trig = s.Enabled && TriggerDown(s);
                    bool act;
                    if (s.Toggle) {
                        if (trig && !s.PrevTriggerDown) s.ToggledOn = !s.ToggledOn;
                        s.PrevTriggerDown = trig;
                        act = s.Enabled && s.ToggledOn;
                    } else {
                        s.PrevTriggerDown = trig;
                        act = trig;
                    }
                    if (Paused || !focus) act = false;
                    if (!act) {
                        if (s.SecondPending) { Send(MouseIn(s.SecondFlag, 0)); s.SecondPending = false; }
                        if (s.WasActive) { Release(s); s.WasActive = false; }
                        s.NextAt = 0;
                        continue;
                    }
                    s.WasActive = true;
                    any = true;
                    if (s.SecondPending && now >= s.SecondAt) { Send(MouseIn(s.SecondFlag, 0)); s.SecondPending = false; }
                    if (now < s.NextAt) continue;
                    double cps = Math.Max(0.5, Math.Min(60.0, s.Cps));
                    double interval = 1000.0 / cps;
                    double jit = Math.Max(0.0, Math.Min(50.0, s.JitterPct)) / 100.0;
                    switch (s.Action) {
                        case 0: case 1: {
                            bool right = s.Action == 1, same = SameButton(s);
                            double duty = Math.Max(0.0, Math.Min(90.0, s.DutyPct)) / 100.0;
                            if (duty <= 0.0 || s.SecondPending) { ClickButton(right, same); break; }
                            // duty cycle: hold the button down for duty x interval, but always leave >= 5 ms up
                            double down = Math.Max(1.0, Math.Min(interval * duty, interval - 5.0));
                            uint d = right ? RDOWN : LDOWN, u = right ? RUP : LUP;
                            if (same) { Send(MouseIn(u, 0)); s.SecondFlag = d; s.SecondAt = now + Math.Max(1.0, interval - down); }
                            else { Send(MouseIn(d, 0)); s.SecondFlag = u; s.SecondAt = now + down; }
                            s.SecondPending = true;
                            break;
                        }
                        case 2:
                            if (!s.BowHolding) {
                                Send(MouseIn(RDOWN, 0));
                                s.BowHolding = true;
                                s.NextAt = now + Math.Max(30, s.BowHoldMs);
                                continue;
                            }
                            Send(MouseIn(RUP, 0));
                            s.BowHolding = false;
                            interval = Math.Max(40.0, interval - s.BowHoldMs);
                            break;
                        case 3: Send(MouseIn(WHEEL, 120)); break;
                        case 4: Send(MouseIn(WHEEL, -120)); break;
                        case 5: Send(MouseIn(WHEEL, s.WheelFlip ? -120 : 120)); s.WheelFlip = !s.WheelFlip; break;
                        case 6: if (s.ActionVk > 0) Send(KeyIn(s.ActionVk, false), KeyIn(s.ActionVk, true)); break;
                    }
                    Interlocked.Increment(ref sent);
                    interval = interval * (1.0 + (rng.NextDouble() * 2.0 - 1.0) * jit);
                    s.NextAt = now + Math.Max(5.0, interval);
                }
                TickSeqs(!Paused && focus, ref any);
                Active = any;
                Thread.Sleep(any ? 1 : 8);
            }
        } catch (Exception e) { LastError = e.Message; }
        finally {
            KuroMacroSlot[] fs = Slots;
            for (int k = 0; k < fs.Length; k++) {
                if (fs[k] != null && fs[k].WasActive) { Release(fs[k]); fs[k].WasActive = false; }
            }
            Active = false;
            timeEndPeriod(1);
        }
    }

    public static string Start() {
        if (Running) return "ok";
        try {
            LastError = "";
            Paused = false;
            Running = true;
            hookThread = new Thread(HookThreadMain);
            hookThread.IsBackground = true;
            hookThread.Start();
            worker = new Thread(WorkerMain);
            worker.IsBackground = true;
            worker.Priority = ThreadPriority.AboveNormal;
            worker.Start();
            return "ok";
        } catch (Exception e) { Running = false; return e.Message; }
    }

    public static void Stop() {
        Running = false;
        CancelSeqs();
        try { if (worker != null) worker.Join(300); } catch { }
        for (int k = 0; k < 20 && hookThreadId == 0 && hookThread != null && hookThread.IsAlive; k++) Thread.Sleep(10);
        if (hookThreadId != 0) { PostThreadMessage(hookThreadId, 0x0012, IntPtr.Zero, IntPtr.Zero); hookThreadId = 0; }
        PhysLeft = false; PhysRight = false; PhysMiddle = false; PhysX1 = false; PhysX2 = false;
        Active = false;
    }
}
'@

$Global:Macro = @{ Loaded = $false; Error = ''; Configs = @(); Slots = $null; Cards = @(); Timer = $null; Cps = 0.0; CpsTicks = 0; CpsCount = 0 }
$Global:MacroTriggers = @('Left mouse', 'Right mouse', 'Mouse 4 (side)', 'Mouse 5 (side)', 'Middle mouse', 'Keyboard key')
$Global:MacroActions  = @('Left click', 'Right click', 'Bow (hold + release)', 'Scroll up', 'Scroll down', 'Scroll up + down', 'Press a key')
# speed range + unit per action
$Global:MacroRange = @{ 0 = @(1, 30, 'clicks/s'); 1 = @(1, 30, 'clicks/s'); 2 = @(1, 5, 'shots/s'); 3 = @(5, 60, 'scrolls/s'); 4 = @(5, 60, 'scrolls/s'); 5 = @(5, 60, 'scrolls/s'); 6 = @(1, 30, 'presses/s') }
# Defaults are starting points only - tune speed and bow charge to your game and settings.
$Global:MacroPresets = @(
    @{ Name = 'Bedwars PvP';   Enabled = $false; Trigger = 0; TriggerVk = 0;    Toggle = $false; Action = 0; ActionVk = 0; Cps = 12; Jitter = 15; BowHoldMs = 500; Duty = 0 }
    @{ Name = 'Bedwars Build'; Enabled = $false; Trigger = 1; TriggerVk = 0;    Toggle = $false; Action = 1; ActionVk = 0; Cps = 14; Jitter = 10; BowHoldMs = 500; Duty = 0 }
    @{ Name = 'Bedwars Bow';   Enabled = $false; Trigger = 3; TriggerVk = 0;    Toggle = $false; Action = 2; ActionVk = 0; Cps = 2;  Jitter = 10; BowHoldMs = 500; Duty = 0 }
    @{ Name = 'Da Hood macro'; Enabled = $false; Trigger = 5; TriggerVk = 0x58; Toggle = $false; Action = 5; ActionVk = 0; Cps = 30; Jitter = 10; BowHoldMs = 500; Duty = 0 }
)

function Initialize-MacroEngine {
    if ($Global:Macro.Loaded) { return $true }
    if (-not ('KuroMacro' -as [type])) {
        try { Add-Type -TypeDefinition $Global:MacroCs -Language CSharp -ErrorAction Stop }
        catch {
            $Global:Macro.Error = $_.Exception.Message
            Write-Log "Macro engine failed to load: $($Global:Macro.Error)"
            return $false
        }
    }
    $Global:Macro.Loaded = $true
    try { Sync-SeqEngine } catch { Write-Log "Macro builder sync failed: $($_.Exception.Message)" }
    return $true
}

function Get-MacroConfigs {
    $saved = @($Global:CCH.Settings.Macros)
    $out = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Global:MacroPresets.Count; $i++) {
        $p = $Global:MacroPresets[$i].Clone()
        if ($i -lt $saved.Count -and $null -ne $saved[$i]) {
            foreach ($k in @($p.Keys)) {
                $v = $null
                if ($saved[$i] -is [hashtable]) { if ($saved[$i].ContainsKey($k)) { $v = $saved[$i][$k] } }
                elseif ($saved[$i].PSObject.Properties[$k]) { $v = $saved[$i].$k }
                if ($null -ne $v) { $p[$k] = $v }
            }
        }
        [void]$out.Add($p)
    }
    return , $out.ToArray()
}

function Save-MacroConfigs {
    $Global:CCH.Settings.Macros = @($Global:Macro.Configs)
    Save-Settings
}

function Sync-MacroEngine {
    if (-not $Global:Macro.Loaded) { return }
    $cfgs = $Global:Macro.Configs
    if (-not $Global:Macro.Slots -or $Global:Macro.Slots.Length -ne $cfgs.Count) {
        $arr = New-Object 'KuroMacroSlot[]' $cfgs.Count
        for ($i = 0; $i -lt $cfgs.Count; $i++) { $arr[$i] = New-Object KuroMacroSlot }
        $Global:Macro.Slots = $arr
        [KuroMacro]::Slots = $arr
    }
    for ($i = 0; $i -lt $cfgs.Count; $i++) {
        $c = $cfgs[$i]; $s = $Global:Macro.Slots[$i]
        $s.Enabled = [bool]$c.Enabled
        $s.Trigger = [int]$c.Trigger
        $s.TriggerVk = [int]$c.TriggerVk
        $s.Toggle = [bool]$c.Toggle
        $s.Action = [int]$c.Action
        $s.ActionVk = [int]$c.ActionVk
        $s.Cps = [double]$c.Cps
        $s.JitterPct = [double]$c.Jitter
        $s.BowHoldMs = [int]$c.BowHoldMs
        $s.DutyPct = [double]$c.Duty
        if (-not $s.Toggle) { $s.ToggledOn = $false }
    }
    [KuroMacro]::RobloxOnly = [bool]$Global:CCH.Settings.MacroRobloxOnly
}

function Get-KeyName([int]$Vk) {
    if ($Vk -le 0) { return 'not set' }
    try { return ([System.Windows.Input.KeyInterop]::KeyFromVirtualKey($Vk)).ToString() } catch { return ('0x{0:X2}' -f $Vk) }
}

$Global:MacroTrigShort = @('Left', 'Right', 'Mouse 4', 'Mouse 5', 'Middle', 'Key')
$Global:MacroActShort  = @('Left click', 'Right click', 'Bow', 'Scroll up', 'Scroll down', 'Scroll both', 'Key')
$Global:MacroActIcon   = @(0xE7FC, 0xE7B8, 0xE945, 0xE8CB, 0xE8CB, 0xE8CB, 0xE765)

$Global:MacroRowTpl = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
      <TextBlock Text="%T%" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
      <TextBlock Text="%S%" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
    </StackPanel>
    %C%
  </Grid>
</Border>
'@

function New-MacroRow([string]$Title, [string]$Sub, [string]$Ctrl) {
    $x = $Global:MacroRowTpl.Replace('%T%', [Security.SecurityElement]::Escape($Title)).Replace('%S%', [Security.SecurityElement]::Escape($Sub)).Replace('%C%', $Ctrl)
    return [Windows.Markup.XamlReader]::Parse($x)
}

$Global:MacroCardTpl = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Margin="0,0,14,12" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="20,14,20,4">
  <StackPanel>
    <Grid x:Name="Hd" Background="Transparent" Cursor="Hand" Margin="0,0,0,10">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Border x:Name="IcBox" Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0" VerticalAlignment="Center">
        <TextBlock x:Name="Ic" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel Grid.Column="1" VerticalAlignment="Center">
        <TextBlock x:Name="Nm" FontSize="15" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
        <TextBlock x:Name="Ds" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
      </StackPanel>
      <TextBlock x:Name="Chev" Grid.Column="2" FontFamily="Segoe MDL2 Assets" FontSize="12" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center" Margin="12,0,16,0"/>
      <CheckBox x:Name="En" Grid.Column="3" Style="{DynamicResource Switch}" VerticalAlignment="Center"/>
    </Grid>
    <StackPanel x:Name="Body"/>
  </StackPanel>
</Border>
'@

function New-SegGroup([int]$Slot, [string]$Field, [string[]]$Labels, [scriptblock]$OnClick = $null) {
    $wrap = New-Object Windows.Controls.Border
    $wrap.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel2Brush')
    $wrap.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
    $wrap.BorderThickness = New-Object Windows.Thickness 1; $wrap.CornerRadius = New-Object Windows.CornerRadius 9; $wrap.Padding = New-Object Windows.Thickness 3
    $wrap.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($wrap, 1)
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $wrap.Child = $sp
    $style = $Global:CCH.Window.Resources['Seg']
    $btns = New-Object System.Collections.ArrayList
    for ($v = 0; $v -lt $Labels.Count; $v++) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $style
        $rb.Content = $Labels[$v]
        $rb.GroupName = ('m{0}{1}' -f $Slot, $Field)
        $rb.Tag = ('{0}|{1}|{2}' -f $Slot, $Field, $v)
        if ($OnClick) { $rb.Tag = $v; $rb.Add_Click($OnClick); [void]$sp.Children.Add($rb); [void]$btns.Add($rb); continue }
        $rb.Add_Click({
            $p = ([string]$this.Tag).Split('|')
            $i = [int]$p[0]; $f = $p[1]; $val = [int]$p[2]
            if ($f -eq 'Toggle') { Set-MacroField $i 'Toggle' ($val -eq 1) } else { Set-MacroField $i $f $val }
        })
        [void]$sp.Children.Add($rb); [void]$btns.Add($rb)
    }
    return @{ Root = $wrap; Buttons = $btns.ToArray() }
}

function New-MacroSlider([double]$Min, [double]$Max) {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($sp, 1)
    $sl = New-Object Windows.Controls.Slider
    $sl.Style = $Global:CCH.Window.Resources['VolSlider']
    $sl.Width = 230; $sl.Minimum = $Min; $sl.Maximum = $Max; $sl.VerticalAlignment = 'Center'
    $tx = New-Object Windows.Controls.TextBlock
    $tx.Width = 96; $tx.TextAlignment = 'Right'; $tx.VerticalAlignment = 'Center'
    $tx.FontWeight = [Windows.FontWeights]::SemiBold; $tx.FontSize = 13
    $tx.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'TextBrush')
    [void]$sp.Children.Add($sl); [void]$sp.Children.Add($tx)
    return @{ Root = $sp; Slider = $sl; Text = $tx }
}

function New-KeyBox {
    $tb = New-Object Windows.Controls.TextBox
    $tb.Style = $Global:CCH.Window.Resources['Input']
    $tb.IsReadOnly = $true; $tb.Cursor = [Windows.Input.Cursors]::Hand; $tb.Width = 190; $tb.FontSize = 13; $tb.Padding = New-Object Windows.Thickness 12, 7, 12, 7
    $tb.HorizontalContentAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($tb, 1)
    return $tb
}

function Add-MacroRow($Body, [string]$Title, [string]$Sub, $Ctrl) {
    $row = New-MacroRow $Title $Sub ''
    [void]$row.Child.Children.Add($Ctrl)
    [void]$Body.Children.Add($row)
    return $row
}

function Get-MacroSummary($c) {
    $r = $Global:MacroRange[[int]$c.Action]
    $trig = $Global:MacroTriggers[[int]$c.Trigger]
    if ([int]$c.Trigger -eq 5) { $trig = Get-KeyName ([int]$c.TriggerVk) }
    $how = $(if ($c.Toggle) { "Press $trig to toggle" } else { "Hold $trig" })
    $act = $Global:MacroActions[[int]$c.Action]
    if ([int]$c.Action -eq 6) { $act = 'Press ' + (Get-KeyName ([int]$c.ActionVk)) }
    return ('{0}  {1}  {2}  {1}  {3} {4}' -f $how, [char]0x00B7, $act, [int]$c.Cps, $r[2])
}

function Update-MacroCard([int]$i) {
    $c = $Global:Macro.Configs[$i]; $k = $Global:Macro.Cards[$i]
    if (-not $c -or -not $k) { return }
    $Global:Macro.Updating = $true
    $k.Nm.Text = [string]$c.Name
    $k.En.IsChecked = [bool]$c.Enabled
    $k.Ic.Text = [string][char]$Global:MacroActIcon[[int]$c.Action]
    $k.Body.Visibility = $(if ($k.Open) { 'Visible' } else { 'Collapsed' })
    $k.Chev.Text = $(if ($k.Open) { [string][char]0xE70E } else { [string][char]0xE70D })
    for ($v = 0; $v -lt $k.TrSeg.Buttons.Count; $v++) { $k.TrSeg.Buttons[$v].IsChecked = ($v -eq [int]$c.Trigger) }
    $k.MdSeg.Buttons[0].IsChecked = (-not [bool]$c.Toggle); $k.MdSeg.Buttons[1].IsChecked = [bool]$c.Toggle
    for ($v = 0; $v -lt $k.AcSeg.Buttons.Count; $v++) { $k.AcSeg.Buttons[$v].IsChecked = ($v -eq [int]$c.Action) }
    $k.TrKeyRow.Visibility = $(if ([int]$c.Trigger -eq 5) { 'Visible' } else { 'Collapsed' })
    $k.TrKey.Text = Get-KeyName ([int]$c.TriggerVk)
    $k.AcKeyRow.Visibility = $(if ([int]$c.Action -eq 6) { 'Visible' } else { 'Collapsed' })
    $k.AcKey.Text = Get-KeyName ([int]$c.ActionVk)
    $r = $Global:MacroRange[[int]$c.Action]
    $k.Sp.Slider.Minimum = $r[0]; $k.Sp.Slider.Maximum = $r[1]
    $cps = [double]$c.Cps
    if ($cps -lt $r[0]) { $cps = $r[0] }; if ($cps -gt $r[1]) { $cps = $r[1] }
    $c.Cps = $cps
    $k.Sp.Slider.Value = $cps; $k.Sp.Text.Text = ('{0} {1}' -f [int]$cps, $r[2])
    $k.BwRow.Visibility = $(if ([int]$c.Action -eq 2) { 'Visible' } else { 'Collapsed' })
    $k.DtRow.Visibility = $(if ([int]$c.Action -le 1) { 'Visible' } else { 'Collapsed' })
    $k.Dt.Slider.Value = [double]$c.Duty
    Update-MacroDuty $i
    $k.Bw.Slider.Value = [double]$c.BowHoldMs; $k.Bw.Text.Text = ('{0} ms' -f [int]$c.BowHoldMs)
    $k.Jt.Slider.Value = [double]$c.Jitter; $k.Jt.Text.Text = ('+/- {0}%' -f [int]$c.Jitter)
    $k.Ds.Text = Get-MacroSummary $c
    $k.Root.Opacity = $(if ($c.Enabled) { 1.0 } else { 0.86 })
    $Global:Macro.Updating = $false
    Update-MacroCount
}

# duty-cycle readout + little waveform, matching the engine's clamp (>= 1 ms down, >= 5 ms up)
function Update-MacroDuty([int]$i) {
    $c = $Global:Macro.Configs[$i]; $k = $Global:Macro.Cards[$i]
    if (-not $k -or -not $k.DtWave) { return }
    $interval = 1000.0 / [math]::Max(0.5, [double]$c.Cps)
    $duty = [math]::Max(0.0, [math]::Min(90.0, [double]$c.Duty))
    $k.Dt.Text.Text = ('{0}%' -f [int]$duty)
    if ($duty -le 0) { $down = 0.0 } else { $down = [math]::Max(1.0, [math]::Min($interval * $duty / 100.0, $interval - 5.0)) }
    $up = $interval - $down
    $limit = ''
    if ($duty -gt 0 -and $down -lt $interval * $duty / 100.0) { $limit = ('   Limited to {0:0.0}% at this speed' -f (100.0 * $down / $interval)) }
    $k.DtInfo.Text = $(if ($duty -le 0) { ('Instant clicks, {0:0.0} ms apart' -f $interval) } else { ('Down {0:0.0} ms  {2}  Up {1:0.0} ms' -f $down, $up, [char]0x00B7) + $limit })
    $cv = $k.DtWave; $cv.Children.Clear()
    $w = $cv.Width; $h = $cv.Height; $per = $w / 3.0
    $fig = New-Object Windows.Media.PathFigure
    $fig.StartPoint = New-Object Windows.Point 0, ($h - 3)
    for ($p = 0; $p -lt 3; $p++) {
        $x0 = $p * $per + 4
        $dw = $(if ($duty -le 0) { 2.0 } else { [math]::Max(2.0, $per * $down / $interval) })
        foreach ($pt in @(@($x0, ($h - 3)), @($x0, 3), @(($x0 + $dw), 3), @(($x0 + $dw), ($h - 3)))) {
            [void]$fig.Segments.Add((New-Object Windows.Media.LineSegment (New-Object Windows.Point $pt[0], $pt[1]), $true))
        }
    }
    [void]$fig.Segments.Add((New-Object Windows.Media.LineSegment (New-Object Windows.Point $w, ($h - 3)), $true))
    $geo = New-Object Windows.Media.PathGeometry; [void]$geo.Figures.Add($fig)
    $path = New-Object Windows.Shapes.Path
    $path.Data = $geo; $path.StrokeThickness = 2; $path.StrokeLineJoin = 'Round'
    $path.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, 'AccentBrush')
    [void]$cv.Children.Add($path)
}

function Update-MacroCount {
    try {
        $n = @($Global:Macro.Configs | Where-Object { $_.Enabled }).Count
        if ($Global:Seq) { $n += @($Global:Seq.Lib | Where-Object { $_.Enabled }).Count }
        $Global:UI.MacroActiveTxt.Text = [string]$n
    } catch { }
}

function Set-MacroField([int]$i, [string]$Field, $Value) {
    $Global:Macro.Configs[$i][$Field] = $Value
    Update-MacroCard $i
    Sync-MacroEngine
    Save-MacroConfigs
}

function Build-MacroCards {
    $Global:UI.MacroWrap.Children.Clear()
    $cards = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Global:Macro.Configs.Count; $i++) {
        $root = [Windows.Markup.XamlReader]::Parse($Global:MacroCardTpl)
        $k = @{ Root = $root; Open = [bool]$Global:Macro.Configs[$i].Enabled }
        foreach ($n in @('Hd', 'Ic', 'Nm', 'Ds', 'Chev', 'En', 'Body')) { $k[$n] = $root.FindName($n); if ($k[$n]) { $k[$n].Tag = $i } }
        $body = $k.Body

        $k.TrSeg = New-SegGroup $i 'Trigger' $Global:MacroTrigShort
        [void](Add-MacroRow $body 'Trigger' 'What starts the macro.' $k.TrSeg.Root)
        $k.TrKey = New-KeyBox; $k.TrKey.Tag = $i
        $k.TrKeyRow = Add-MacroRow $body 'Trigger key' 'Click the box, then press a key. Esc cancels.' $k.TrKey
        $k.MdSeg = New-SegGroup $i 'Toggle' @('Hold', 'Toggle')
        [void](Add-MacroRow $body 'Mode' 'Hold runs while the trigger is down. Toggle starts and stops on each press.' $k.MdSeg.Root)
        $k.AcSeg = New-SegGroup $i 'Action' $Global:MacroActShort
        [void](Add-MacroRow $body 'Action' 'What the macro sends.' $k.AcSeg.Root)
        $k.AcKey = New-KeyBox; $k.AcKey.Tag = $i
        $k.AcKeyRow = Add-MacroRow $body 'Key to press' 'Click the box, then press the key to spam.' $k.AcKey
        $k.Sp = New-MacroSlider 1 30; $k.Sp.Slider.Tag = $i
        [void](Add-MacroRow $body 'Speed' 'How fast the action repeats.' $k.Sp.Root)
        $k.Dt = New-MacroSlider 0 90; $k.Dt.Slider.Tag = $i
        $dv = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($dv, 1); $dv.VerticalAlignment = 'Center'
        $k.Dt.Root.SetValue([Windows.Controls.Grid]::ColumnProperty, 0)
        [void]$dv.Children.Add($k.Dt.Root)
        $k.DtWave = New-Object Windows.Controls.Canvas; $k.DtWave.Width = 326; $k.DtWave.Height = 30; $k.DtWave.Margin = New-Object Windows.Thickness 0, 8, 0, 0; $k.DtWave.ClipToBounds = $true
        [void]$dv.Children.Add($k.DtWave)
        $k.DtInfo = New-Object Windows.Controls.TextBlock; $k.DtInfo.FontSize = 11.5; $k.DtInfo.Margin = New-Object Windows.Thickness 0, 4, 0, 0
        $k.DtInfo.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'SubTextBrush')
        [void]$dv.Children.Add($k.DtInfo)
        $k.DtRow = Add-MacroRow $body 'Click duty cycle' 'How long each click holds the button down. 0% = instant click.' $dv
        $k.Bw = New-MacroSlider 50 1500; $k.Bw.Slider.Tag = $i
        $k.BwRow = Add-MacroRow $body 'Bow charge' 'How long the bow is drawn before each release.' $k.Bw.Root
        $k.Jt = New-MacroSlider 0 40; $k.Jt.Slider.Tag = $i
        [void](Add-MacroRow $body 'Randomize' 'Varies the timing a little so it is not perfectly even.' $k.Jt.Root)

        $k.Hd.Add_MouseLeftButtonUp({
            param($s, $e)
            try {
                $d = $e.OriginalSource
                while ($d -and $d -ne $s) { if ($d -is [Windows.Controls.CheckBox]) { return }; $d = [Windows.Media.VisualTreeHelper]::GetParent($d) }
            } catch { }
            $i = [int]$s.Tag
            $Global:Macro.Cards[$i].Open = -not $Global:Macro.Cards[$i].Open
            Update-MacroCard $i
            if ($Global:Macro.Cards[$i].Open) { Fade-In $Global:Macro.Cards[$i].Body }
        })
        $k.En.Add_Click({
            $i = [int]$this.Tag
            if ([bool]$this.IsChecked) { $Global:Macro.Cards[$i].Open = $true }
            Set-MacroField $i 'Enabled' ([bool]$this.IsChecked)
        })
        foreach ($box in @($k.TrKey, $k.AcKey)) {
            $box.Add_GotKeyboardFocus({ $this.Text = 'Press a key...' })
            $box.Add_LostKeyboardFocus({ Update-MacroCard ([int]$this.Tag) })
        }
        $k.TrKey.Add_PreviewKeyDown({
            $_.Handled = $true
            $key = $_.Key; if ([string]$key -eq 'System') { $key = $_.SystemKey }
            if ([string]$key -eq 'Escape') { [System.Windows.Input.Keyboard]::ClearFocus(); return }
            $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
            $i = [int]$this.Tag
            if ($vk -eq 0x77) { Show-Toast 'F8 is reserved for pause/resume.' 'info'; return }
            if ([int]$Global:Macro.Configs[$i].Action -eq 6 -and $vk -eq [int]$Global:Macro.Configs[$i].ActionVk) { Show-Toast 'The trigger key must be different from the key being pressed.' 'error'; return }
            Set-MacroField $i 'TriggerVk' $vk
            [System.Windows.Input.Keyboard]::ClearFocus()
        })
        $k.AcKey.Add_PreviewKeyDown({
            $_.Handled = $true
            $key = $_.Key; if ([string]$key -eq 'System') { $key = $_.SystemKey }
            if ([string]$key -eq 'Escape') { [System.Windows.Input.Keyboard]::ClearFocus(); return }
            $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
            $i = [int]$this.Tag
            if ($vk -eq 0x77) { Show-Toast 'F8 is reserved for pause/resume.' 'info'; return }
            if ([int]$Global:Macro.Configs[$i].Trigger -eq 5 -and $vk -eq [int]$Global:Macro.Configs[$i].TriggerVk) { Show-Toast 'The key being pressed must be different from the trigger key.' 'error'; return }
            Set-MacroField $i 'ActionVk' $vk
            [System.Windows.Input.Keyboard]::ClearFocus()
        })
        $k.Sp.Slider.Add_ValueChanged({
            if ($Global:Macro.Updating) { return }
            $i = [int]$this.Tag; $v = [math]::Round($this.Value)
            $c = $Global:Macro.Configs[$i]; $c.Cps = $v
            $r = $Global:MacroRange[[int]$c.Action]
            $Global:Macro.Cards[$i].Sp.Text.Text = ('{0} {1}' -f [int]$v, $r[2])
            $Global:Macro.Cards[$i].Ds.Text = Get-MacroSummary $c
            Update-MacroDuty $i
            Sync-MacroEngine
        })
        $k.Bw.Slider.Add_ValueChanged({
            if ($Global:Macro.Updating) { return }
            $i = [int]$this.Tag; $v = [int]([math]::Round($this.Value / 10) * 10)
            $Global:Macro.Configs[$i].BowHoldMs = $v
            $Global:Macro.Cards[$i].Bw.Text.Text = ('{0} ms' -f $v)
            Sync-MacroEngine
        })
        $k.Dt.Slider.Add_ValueChanged({
            if ($Global:Macro.Updating) { return }
            $i = [int]$this.Tag
            $Global:Macro.Configs[$i].Duty = [math]::Round($this.Value)
            Update-MacroDuty $i
            Sync-MacroEngine
        })
        $k.Jt.Slider.Add_ValueChanged({
            if ($Global:Macro.Updating) { return }
            $i = [int]$this.Tag; $v = [math]::Round($this.Value)
            $Global:Macro.Configs[$i].Jitter = $v
            $Global:Macro.Cards[$i].Jt.Text.Text = ('+/- {0}%' -f [int]$v)
            Sync-MacroEngine
        })
        foreach ($sl in @($k.Sp.Slider, $k.Bw.Slider, $k.Jt.Slider, $k.Dt.Slider)) { $sl.Add_PreviewMouseUp({ Save-MacroConfigs }) }
        [void]$cards.Add($k)
        [void]$Global:UI.MacroWrap.Children.Add($root)
    }
    $Global:Macro.Cards = $cards.ToArray()
    for ($i = 0; $i -lt $Global:Macro.Configs.Count; $i++) { Update-MacroCard $i }
}

function Update-MacroStatus {
    $ui = $Global:UI
    $res = $Global:CCH.Window.Resources
    if (-not $Global:Macro.Loaded -or -not [KuroMacro]::Running) {
        $ui.MacroStatusTxt.Text = 'Off'; $ui.MacroStatusDot.Fill = $res['SubTextBrush']; $ui.MacroCpsTxt.Text = '0'; return
    }
    $nowTicks = [DateTime]::UtcNow.Ticks
    $count = [KuroMacro]::SentCount()
    if ($Global:Macro.CpsTicks) {
        $dt = ($nowTicks - $Global:Macro.CpsTicks) / 1e7
        if ($dt -gt 0.05) {
            $inst = ($count - $Global:Macro.CpsCount) / $dt
            $Global:Macro.Cps = 0.6 * $inst + 0.4 * [double]$Global:Macro.Cps
            if ($inst -eq 0 -and $Global:Macro.Cps -lt 0.5) { $Global:Macro.Cps = 0 }
        }
    }
    $Global:Macro.CpsTicks = $nowTicks; $Global:Macro.CpsCount = $count
    $ui.MacroCpsTxt.Text = [string][int][math]::Round([double]$Global:Macro.Cps)
    $err = [string][KuroMacro]::LastError
    if ($err) { $ui.MacroErr.Text = $err; $ui.MacroErr.Visibility = 'Visible' }
    if ([KuroMacro]::Paused) { $ui.MacroStatusTxt.Text = 'Paused'; $ui.MacroStatusDot.Fill = $res['WarnBrush'] }
    elseif ([KuroMacro]::Active) { $ui.MacroStatusTxt.Text = 'Running'; $ui.MacroStatusDot.Fill = $res['GoodBrush'] }
    else { $ui.MacroStatusTxt.Text = 'Ready'; $ui.MacroStatusDot.Fill = $res['AccentBrush'] }
}

function Set-MacrosEnabled([bool]$On) {
    $ui = $Global:UI
    if ($On) {
        if (-not (Initialize-MacroEngine)) {
            $ui.MacroMaster.IsChecked = $false
            $ui.MacroErr.Text = 'The macro engine could not load: ' + $Global:Macro.Error
            $ui.MacroErr.Visibility = 'Visible'
            return
        }
        Sync-MacroEngine
        $r = [KuroMacro]::Start()
        if ($r -ne 'ok') {
            $ui.MacroMaster.IsChecked = $false
            $ui.MacroErr.Text = 'Macros could not start: ' + $r; $ui.MacroErr.Visibility = 'Visible'
            return
        }
        $ui.MacroErr.Visibility = 'Collapsed'
        if (-not $Global:Macro.Timer) {
            $t = New-Object Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromMilliseconds(250)
            $t.Add_Tick({ try { Update-MacroStatus } catch { } })
            $Global:Macro.Timer = $t
        }
        $Global:Macro.Timer.Start()
        $enabled = @($Global:Macro.Configs | Where-Object { $_.Enabled }).Count
        if ($enabled -eq 0) { Show-Toast 'Macros are on, but no macro is switched on yet. Turn one on below.' 'info' }
        else { Show-Toast ("Macros on ($enabled active). Press F8 to pause.") }
        Write-Log 'Macros started.'
    } else {
        if ($Global:Macro.Loaded) { [KuroMacro]::Stop() }
        if ($Global:Macro.Timer) { $Global:Macro.Timer.Stop() }
        Write-Log 'Macros stopped.'
    }
    Update-MacroStatus
}

function Connect-Macros {
    $ui = $Global:UI
    $Global:Macro.Configs = Get-MacroConfigs
    Build-MacroCards
    $ui.MacroRobloxOnly.IsChecked = [bool]$Global:CCH.Settings.MacroRobloxOnly
    $ui.MacroRobloxOnly.Add_Click({
        $Global:CCH.Settings.MacroRobloxOnly = [bool]$Global:UI.MacroRobloxOnly.IsChecked; Save-Settings
        if ($Global:Macro.Loaded) { [KuroMacro]::RobloxOnly = [bool]$Global:CCH.Settings.MacroRobloxOnly }
    })
    $ui.MacroMaster.IsChecked = $false
    $ui.MacroMaster.Add_Click({ Set-MacrosEnabled ([bool]$Global:UI.MacroMaster.IsChecked) })
    $Global:CCH.Window.Add_Closing({ try { if ($Global:Macro.Loaded) { [KuroMacro]::Stop() } } catch { } })
    try { Connect-SeqBuilder } catch { Write-Log "Macro builder failed to start: $($_.Exception.Message)"; $ui.MacroErr.Text = 'Macro builder problem: ' + $_.Exception.Message; $ui.MacroErr.Visibility = 'Visible' }
}

# ==================================================================================================
#  ROBLOX GRAPHICS  - one 20-step "Looks vs FPS" slider.
#  Only flags on Roblox's FastFlag allowlist (introduced 29 Sep 2025) are written; anything else
#  would be ignored by the client. Flags go into ClientAppSettings.json of every installed version
#  (Set-RobloxFlags in 02-tweaks) and are re-applied after Roblox updates via Sync-RobloxFlags.
# ==================================================================================================

# every key the slider may write, so moving to a lighter step also removes the heavier ones
$Global:RbxSliderKeys = @(
    'DFIntDebugFRMQualityLevelOverride',
    'DFFlagTextureQualityOverrideEnabled', 'DFIntTextureQualityOverride',
    'FIntDebugForceMSAASamples',
    'FIntFRMMinGrassDistance', 'FIntFRMMaxGrassDistance',
    'FFlagDebugSkyGray',
    'DFFlagDebugPauseVoxelizer',
    'DFIntCSGLevelOfDetailSwitchingDistance', 'DFIntCSGLevelOfDetailSwitchingDistanceL12',
    'DFIntCSGLevelOfDetailSwitchingDistanceL23', 'DFIntCSGLevelOfDetailSwitchingDistanceL34'
)
$Global:RbxPresets = @(
    @{ N = 'Quality';     S = 3;  I = 0xE890 }
    @{ N = 'Balanced';    S = 8;  I = 0xE713 }
    @{ N = 'Performance'; S = 14; I = 0xE945 }
    @{ N = 'Max FPS';     S = 20; I = 0xEC4A }
)
$Global:Rbx = @{ Step = 8; Stairs = @(); PresetBtns = @() }

function Get-RbxStep([int]$N) {
    $N = [math]::Max(1, [math]::Min(20, $N))
    $f = [ordered]@{}
    $level = [int][math]::Round(21 - ($N - 1) * 20.0 / 19.0)
    $tex = $(if ($N -le 5) { 3 } elseif ($N -le 10) { 2 } elseif ($N -le 15) { 1 } else { 0 })
    $aa = $(if ($N -le 4) { 4 } elseif ($N -le 9) { 2 } else { 1 })
    $f['DFIntDebugFRMQualityLevelOverride'] = [string]$level
    $f['DFFlagTextureQualityOverrideEnabled'] = 'True'
    $f['DFIntTextureQualityOverride'] = [string]$tex
    $f['FIntDebugForceMSAASamples'] = [string]$aa
    $grass = 'Full grass'
    if ($N -ge 16) { $f['FIntFRMMinGrassDistance'] = '0'; $f['FIntFRMMaxGrassDistance'] = '0'; $grass = 'No grass' }
    elseif ($N -ge 9) { $f['FIntFRMMinGrassDistance'] = '0'; $f['FIntFRMMaxGrassDistance'] = '100'; $grass = 'Less grass' }
    $sky = 'Normal'; if ($N -ge 12) { $f['FFlagDebugSkyGray'] = 'True'; $sky = 'Gray' }
    $light = 'Normal'; if ($N -ge 17) { $f['DFFlagDebugPauseVoxelizer'] = 'True'; $light = 'Frozen (lighter)' }
    $parts = 'Normal'
    if ($N -ge 19) {
        foreach ($k in @('DFIntCSGLevelOfDetailSwitchingDistance', 'DFIntCSGLevelOfDetailSwitchingDistanceL12', 'DFIntCSGLevelOfDetailSwitchingDistanceL23', 'DFIntCSGLevelOfDetailSwitchingDistanceL34')) { $f[$k] = '0' }
        $parts = 'Lowest'
    }
    $texName = @('Lowest', 'Low', 'Medium', 'High')[$tex]
    $aaName = $(if ($aa -le 1) { 'Off (1x)' } else { "${aa}x" })
    $name = $(if ($N -le 5) { 'Quality' } elseif ($N -le 10) { 'Balanced' } elseif ($N -le 15) { 'Performance' } else { 'Max FPS' })
    $bits = @("$texName textures", "$aaName anti-aliasing".Replace('Off (1x) anti-aliasing', 'no anti-aliasing'), $grass.ToLower(), "graphics level $level")
    if ($sky -eq 'Gray') { $bits += 'gray sky' }
    if ($light -ne 'Normal') { $bits += 'frozen lighting' }
    if ($parts -ne 'Normal') { $bits += 'lowest part detail' }
    $looks = [int][math]::Round(10 - ($N - 1) * 9.0 / 19.0)
    return @{
        N = $N; Name = $name; Flags = $f; Summary = ($bits -join ', ')
        Looks = $looks; Fps = 11 - $looks
        Details = [ordered]@{
            'GRAPHICS LEVEL' = "$level of 21"; 'TEXTURES' = $texName; 'ANTI-ALIASING' = $aaName; 'GRASS' = $grass
            'SKY' = $sky; 'LIGHTING' = $light; 'PART DETAIL' = $parts; 'FPS CAP' = "Roblox's setting"
        }
    }
}

function Get-RbxColor([double]$T) {
    $a = [Windows.Media.ColorConverter]::ConvertFromString('#E9C46A')
    $b = Get-AccentColor
    return [Windows.Media.Color]::FromRgb([byte]($a.R + ($b.R - $a.R) * $T), [byte]($a.G + ($b.G - $a.G) * $T), [byte]($a.B + ($b.B - $a.B) * $T))
}

function Build-RbxPage {
    $ui = $Global:UI
    $g = $ui.RbxStairs
    $g.Children.Clear(); $g.ColumnDefinitions.Clear()
    $bars = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt 20; $i++) {
        $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star)
        [void]$g.ColumnDefinitions.Add($cd)
        $b = New-Object Windows.Controls.Border
        $b.Height = 16 + $i * 2.6
        $b.VerticalAlignment = 'Bottom'
        $b.Margin = New-Object Windows.Thickness 2, 0, 2, 0
        $b.CornerRadius = New-Object Windows.CornerRadius 5
        $b.BorderThickness = New-Object Windows.Thickness 1
        $b.Cursor = [Windows.Input.Cursors]::Hand
        $b.Tag = $i + 1
        $b.ToolTip = (Get-RbxStep ($i + 1)).Name + ' - step ' + ($i + 1)
        $b.Add_MouseLeftButtonUp({ $Global:UI.RbxSlider.Value = [int]$this.Tag })
        [Windows.Controls.Grid]::SetColumn($b, $i)
        [void]$g.Children.Add($b); [void]$bars.Add($b)
    }
    $Global:Rbx.Stairs = $bars.ToArray()

    $ui.RbxPresets.Children.Clear()
    $btns = New-Object System.Collections.ArrayList
    for ($p = 0; $p -lt $Global:RbxPresets.Count; $p++) {
        $pr = $Global:RbxPresets[$p]
        $bt = New-Object Windows.Controls.Button
        $bt.Style = $Global:CCH.Window.Resources['GhostBtn']
        $bt.Padding = New-Object Windows.Thickness 10, 10, 10, 10
        $bt.Margin = New-Object Windows.Thickness $(if ($p -eq 0) { 0 } else { 5 }), 0, $(if ($p -eq 3) { 0 } else { 5 }), 0
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.HorizontalAlignment = 'Center'
        $ic = New-Object Windows.Controls.TextBlock; $ic.Text = [string][char]$pr.I; $ic.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'
        $ic.FontSize = 12; $ic.VerticalAlignment = 'Center'; $ic.Margin = New-Object Windows.Thickness 0, 0, 8, 0
        [void]$sp.Children.Add($ic)
        $tx = New-Object Windows.Controls.TextBlock; $tx.Text = $pr.N; $tx.FontSize = 13; $tx.VerticalAlignment = 'Center'
        [void]$sp.Children.Add($tx)
        $bt.Content = $sp; $bt.Tag = $pr.S
        $bt.Add_Click({ $Global:UI.RbxSlider.Value = [int]$this.Tag })
        [void]$ui.RbxPresets.Children.Add($bt); [void]$btns.Add($bt)
    }
    $Global:Rbx.PresetBtns = $btns.ToArray()
}

function New-RbxMeter($Panel, [int]$Filled, [string]$OnHex) {
    $Panel.Children.Clear()
    for ($i = 0; $i -lt 10; $i++) {
        $r = New-Object Windows.Controls.Border
        $r.Width = 22; $r.Height = 5; $r.CornerRadius = New-Object Windows.CornerRadius 2.5
        $r.Margin = New-Object Windows.Thickness 3, 0, 0, 0
        if ($i -lt $Filled) { $r.Background = New-Brush2 $OnHex } else { $r.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'LineBrush') }
        [void]$Panel.Children.Add($r)
    }
}

function Update-RbxPage {
    $ui = $Global:UI
    $n = [int][math]::Round($ui.RbxSlider.Value)
    $Global:Rbx.Step = $n
    $st = Get-RbxStep $n
    $ui.RbxStepName.Text = $st.Name
    $ui.RbxBadge.Text = $st.Name
    $ui.RbxStepTxt.Text = "Step $n of 20  $([char]0x00B7)  " + $st.Summary.Substring(0, 1).ToUpper() + $st.Summary.Substring(1)
    New-RbxMeter $ui.RbxLooksBar $st.Looks '#C9B26A'
    New-RbxMeter $ui.RbxFpsBar $st.Fps '#3DDC84'
    for ($i = 0; $i -lt $Global:Rbx.Stairs.Count; $i++) {
        $b = $Global:Rbx.Stairs[$i]
        if ($i -lt $n) {
            $c = Get-RbxColor ($i / 19.0)
            $alpha = $(if ($i -eq $n - 1) { 255 } else { 215 })
            $b.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($alpha, $c.R, $c.G, $c.B))
            $b.BorderBrush = $(if ($i -eq $n - 1) { New-Brush2 '#FFFFFF' 0xB0 } else { New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0, 0, 0, 0)) })
        } else {
            $b.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel2Brush')
            $b.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        }
    }
    foreach ($bt in $Global:Rbx.PresetBtns) {
        if ([int]$bt.Tag -eq $n) { $bt.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'AccentBrush'); $bt.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'AccentSoftBrush') }
        else { $bt.ClearValue([Windows.Controls.Control]::BorderBrushProperty); $bt.ClearValue([Windows.Controls.Control]::BackgroundProperty) }
    }
    $ui.RbxDetails.Children.Clear()
    $k = 0
    foreach ($key in $st.Details.Keys) {
        $card = New-Object Windows.Controls.Border
        $card.CornerRadius = New-Object Windows.CornerRadius 9; $card.Padding = New-Object Windows.Thickness 12, 9, 12, 10
        $card.Margin = New-Object Windows.Thickness $(if ($k % 4 -eq 0) { 0 } else { 5 }), 0, $(if ($k % 4 -eq 3) { 0 } else { 5 }), 10
        $card.BorderThickness = New-Object Windows.Thickness 1
        $card.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel2Brush')
        $card.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush')
        $sp = New-Object Windows.Controls.StackPanel
        $l = New-SeqText $key 10.5 'SubTextBrush' $true
        $v = New-SeqText ([string]$st.Details[$key]) 14 'TextBrush' $true; $v.Margin = New-Object Windows.Thickness 0, 4, 0, 0
        [void]$sp.Children.Add($l); [void]$sp.Children.Add($v)
        $card.Child = $sp
        [void]$ui.RbxDetails.Children.Add($card)
        $k++
    }
    $applied = [int]$Global:CCH.Settings.RbxStep
    if ($applied -le 0) { $ui.RbxApplied.Text = 'Nothing applied yet. Roblox is using its own graphics settings.' }
    elseif ($applied -eq $n) { $ui.RbxApplied.Text = "Step $applied is applied. Restart Roblox to see it." }
    else { $ui.RbxApplied.Text = "Step $applied is applied. Click Apply to switch to step $n." }
}

# read-only look at Roblox's own saved settings (documented SavedQualityLevel enum: 0 = Automatic, 1-10)
function Update-RbxNow {
    $ui = $Global:UI
    $dir = Join-Path $env:LOCALAPPDATA 'Roblox'
    $f = @(Get-ChildItem -Path $dir -Filter 'GlobalBasicSettings_*.xml' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    if ($f.Count -eq 0) { $ui.RbxNowTxt.Text = "Roblox's own settings: file not found"; return }
    try {
        $x = New-Object Xml.XmlDocument
        $x.XmlResolver = $null
        $x.LoadXml([IO.File]::ReadAllText($f[0].FullName))
        $parts = @()
        $q = $x.SelectSingleNode("//*[@name='SavedQualityLevel']")
        if ($q) {
            $v = 0; [void][int]::TryParse(($q.InnerText -replace '[^0-9]', ''), [ref]$v)
            $parts += $(if ($v -eq 0) { 'Graphics: Automatic' } else { "Graphics: $v of 10" })
        }
        $c = $x.SelectSingleNode("//*[@name='FramerateCap']")
        if ($c -and $c.InnerText) { $parts += ('FPS cap value: ' + $c.InnerText.Trim()) }
        if ($parts.Count -eq 0) { $ui.RbxNowTxt.Text = "Roblox's own settings: no graphics values found" }
        else { $ui.RbxNowTxt.Text = "Roblox's own settings now: " + ($parts -join '  ' + [char]0x00B7 + '  ') }
    } catch { $ui.RbxNowTxt.Text = "Roblox's own settings: could not be read" }
}

function Invoke-RbxApply {
    $n = $Global:Rbx.Step
    $st = Get-RbxStep $n
    try { Set-RobloxFlags $st.Flags $Global:RbxSliderKeys }
    catch { Show-Toast $_.Exception.Message 'error'; return }
    $Global:RbxFlagSets['rbx_slider'] = $st.Flags
    # the two older Roblox tweaks write the same flags; keep them from fighting the slider
    $list = @($Global:CCH.Settings.RobloxEnabled | Where-Object { $_ -and $_ -ne 'rbx_lowend' -and $_ -ne 'rbx_potato' -and $_ -ne 'rbx_slider' })
    $list += 'rbx_slider'
    $Global:CCH.Settings.RobloxEnabled = $list
    $Global:CCH.Settings.RbxStep = $n
    Save-Settings
    foreach ($t in $Global:Tweaks) { if ($t.Id -eq 'rbx_lowend' -or $t.Id -eq 'rbx_potato') { try { $t.Applied = Test-Tweak $t } catch { } } }
    try { Update-AllViews } catch { }
    Update-RbxPage
    Show-Fx 'success' ($st.Name.ToUpper() + ' APPLIED')
    Show-Toast "Step $n applied. Close and reopen Roblox to see it."
}

function Invoke-RbxReset {
    try { Set-RobloxFlags $null $Global:RbxSliderKeys } catch { Show-Toast $_.Exception.Message 'error'; return }
    $Global:RbxFlagSets.Remove('rbx_slider')
    $Global:CCH.Settings.RobloxEnabled = @($Global:CCH.Settings.RobloxEnabled | Where-Object { $_ -and $_ -ne 'rbx_slider' })
    $Global:CCH.Settings.RbxStep = 0
    Save-Settings
    Update-RbxPage
    Show-Toast "Removed Kuro's graphics settings. Roblox is back to its own."
}

function Connect-RobloxGfx {
    $ui = $Global:UI
    $saved = [int]$Global:CCH.Settings.RbxStep
    if ($saved -gt 0) { $Global:RbxFlagSets['rbx_slider'] = (Get-RbxStep $saved).Flags }
    Build-RbxPage
    $ui.RbxSlider.Value = $(if ($saved -gt 0) { $saved } else { 8 })
    $ui.RbxSlider.Add_ValueChanged({ Update-RbxPage })
    $ui.BtnRbxApply.Add_Click({ Invoke-RbxApply })
    $ui.BtnRbxReset.Add_Click({
        Show-Modal 'Reset Roblox graphics?' "This removes every setting Kuro's slider added. Roblox goes back to its own graphics settings next time it starts." 'Reset' 'Cancel' { Invoke-RbxReset }
    })
    Update-RbxPage
}

# ==================================================================================================
#  MACRO BUILDER  - step-by-step macros (blocks), recorder, test-play, share codes.
#  Library is stored in %ProgramData%\Kuro\macros.json. Playback runs in the KuroMacro engine (05h).
# ==================================================================================================

$Global:SeqFile = Join-Path $Global:DataDir 'macros.json'
$Global:Seq = @{ Lib = (New-Object System.Collections.ArrayList); Sel = -1; Block = -1; Engine = @(); TestQ = $null; Timer = $null; Rec = 'idle'; RecAt = 0; Rows = @() }

$Global:SeqKinds = @(
    @{ N = 'Press key';         I = 0xE765; C = '#3B82F6' }
    @{ N = 'Click';             I = 0xE7C9; C = '#8B5CF6' }
    @{ N = 'Wait';              I = 0xE916; C = '#F59E0B' }
    @{ N = 'Auto-click';        I = 0xE945; C = '#22C55E' }
    @{ N = 'Type text';         I = 0xE8D2; C = '#14B8A6' }
    @{ N = 'Key combo';         I = 0xE765; C = '#6366F1' }
    @{ N = 'Double click';      I = 0xE7C9; C = '#A855F7' }
    @{ N = 'Move mouse';        I = 0xE707; C = '#10B981' }
    @{ N = 'Move by';           I = 0xE72A; C = '#0EA5A4' }
    @{ N = 'Scroll';            I = 0xE8CB; C = '#EC4899' }
    @{ N = 'Wait random';       I = 0xE8B1; C = '#F97316' }
    @{ N = 'Label';             I = 0xE8EC; C = '#9CA3AF' }
    @{ N = 'Hold key down';     I = 0xE765; C = '#3B82F6' }
    @{ N = 'Let go of key';     I = 0xE765; C = '#60A5FA' }
    @{ N = 'Mouse button down'; I = 0xE7C9; C = '#8B5CF6' }
    @{ N = 'Mouse button up';   I = 0xE7C9; C = '#C084FC' }
)
$Global:SeqBtnNames  = @('Left', 'Right', 'Middle')
$Global:SeqModeNames = @('Once', 'Repeat', 'While held', 'Toggle loop')
$Global:SeqMaxSteps  = 500

# ------------------------------------------------------------------ data model
function Get-IntIn($v, [int]$Min, [int]$Max, [int]$Def) {
    $n = 0
    if (-not [int]::TryParse([string]$v, [ref]$n)) { $d = 0.0; if ([double]::TryParse([string]$v, [ref]$d)) { $n = [int][math]::Round($d) } else { return $Def } }
    return [int][math]::Max($Min, [math]::Min($Max, $n))
}

function New-SeqStep([int]$K) {
    $s = @{ K = $K; Vk = 0; Mods = 0; Btn = 0; X = 0; Y = 0; Ms = 30; Ms2 = 0; Count = 1; Cps = 10; Text = '' }
    switch ($K) {
        0 { $s.Vk = 0x31 }
        2 { $s.Ms = 100 }
        3 { $s.Count = 10; $s.Cps = 12 }
        4 { $s.Text = 'gg'; $s.Ms = 15 }
        5 { $s.Vk = 0x43; $s.Mods = 1 }
        7 { $p = $null; try { $p = [KuroMacro]::CursorPos() } catch { }; if ($p) { $s.X = $p[0]; $s.Y = $p[1] } }
        9 { $s.Count = 1 }
        10 { $s.Ms = 80; $s.Ms2 = 160 }
        11 { $s.Text = 'Note' }
        12 { $s.Vk = 0x57 }
        13 { $s.Vk = 0x57 }
    }
    return $s
}

function ConvertTo-SeqStep($o) {
    $g = { param($n) if ($o -is [hashtable]) { $o[$n] } elseif ($o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    $k = Get-IntIn (& $g 'K') 0 15 -1
    if ($k -lt 0) { return $null }
    $txt = [string](& $g 'Text'); if ($txt.Length -gt 500) { $txt = $txt.Substring(0, 500) }
    $cps = 10.0; [void][double]::TryParse([string](& $g 'Cps'), [ref]$cps); $cps = [math]::Max(1, [math]::Min(50, $cps))
    return @{
        K = $k
        Vk = Get-IntIn (& $g 'Vk') 0 255 0
        Mods = Get-IntIn (& $g 'Mods') 0 15 0
        Btn = Get-IntIn (& $g 'Btn') 0 2 0
        X = Get-IntIn (& $g 'X') -100000 100000 0
        Y = Get-IntIn (& $g 'Y') -100000 100000 0
        Ms = Get-IntIn (& $g 'Ms') 0 60000 30
        Ms2 = Get-IntIn (& $g 'Ms2') 0 60000 0
        Count = Get-IntIn (& $g 'Count') -1000 1000 1
        Cps = $cps
        Text = $txt
    }
}

function ConvertTo-SeqMacro($o) {
    $g = { param($n) if ($o -is [hashtable]) { $o[$n] } elseif ($o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    $name = [string](& $g 'Name'); if (-not $name) { $name = 'My macro' }; if ($name.Length -gt 40) { $name = $name.Substring(0, 40) }
    $id = [string](& $g 'Id'); if (-not $id) { $id = [guid]::NewGuid().ToString('N').Substring(0, 12) }
    $steps = New-Object System.Collections.ArrayList
    foreach ($st in @(& $g 'Steps')) {
        if ($null -eq $st -or $steps.Count -ge $Global:SeqMaxSteps) { continue }
        $c = ConvertTo-SeqStep $st
        if ($c) { [void]$steps.Add($c) }
    }
    return @{
        Id = $id; Name = $name
        Enabled = [bool](& $g 'Enabled')
        Trigger = Get-IntIn (& $g 'Trigger') 0 5 5
        TriggerVk = Get-IntIn (& $g 'TriggerVk') 0 255 0
        Mode = Get-IntIn (& $g 'Mode') 0 3 0
        Repeat = Get-IntIn (& $g 'Repeat') 1 1000 3
        Steps = $steps
    }
}

function Load-SeqLibrary {
    $Global:Seq.Lib.Clear()
    if (Test-Path $Global:SeqFile) {
        try {
            $j = [IO.File]::ReadAllText($Global:SeqFile) | ConvertFrom-Json
            foreach ($m in @($j)) { if ($m) { [void]$Global:Seq.Lib.Add((ConvertTo-SeqMacro $m)) } }
        } catch { Write-Log "Macro library could not be read: $($_.Exception.Message)" }
    }
}

function Save-SeqLibrary {
    try {
        $arr = @($Global:Seq.Lib | ForEach-Object { $m = $_.Clone(); $m.Steps = @($_.Steps); $m })
        $json = '[]'
        if ($arr.Count -gt 0) { $json = ConvertTo-Json -InputObject $arr -Depth 6 }
        [IO.File]::WriteAllText($Global:SeqFile, $json, $Global:Utf8NoBom)
        $Global:UI.SeqSavedTxt.Text = (Get-SeqCountText) + ', saved'
    } catch { Write-Log "Macro library could not be saved: $($_.Exception.Message)" }
    Sync-SeqEngine
    Update-MacroCount
}

function Get-SeqSel { if ($Global:Seq.Sel -ge 0 -and $Global:Seq.Sel -lt $Global:Seq.Lib.Count) { return $Global:Seq.Lib[$Global:Seq.Sel] } else { return $null } }

function Get-SeqCountText {
    $m = Get-SeqSel; if (-not $m) { return '0 steps' }
    $n = $m.Steps.Count
    return $(if ($n -eq 1) { '1 step' } else { "$n steps" })
}

# ------------------------------------------------------------------ engine bridge
function New-KuroSeq($m, [bool]$Enabled) {
    $q = New-Object KuroSeq
    $q.Enabled = $Enabled
    $q.Trigger = [int]$m.Trigger; $q.TriggerVk = [int]$m.TriggerVk
    $q.Mode = [int]$m.Mode; $q.Repeat = [int]$m.Repeat
    $arr = New-Object 'KuroSeqStep[]' $m.Steps.Count
    for ($i = 0; $i -lt $m.Steps.Count; $i++) {
        $s = $m.Steps[$i]; $t = New-Object KuroSeqStep
        $t.Kind = [int]$s.K; $t.Vk = [int]$s.Vk; $t.Mods = [int]$s.Mods; $t.Button = [int]$s.Btn
        $t.X = [int]$s.X; $t.Y = [int]$s.Y; $t.Ms = [int]$s.Ms; $t.Ms2 = [int]$s.Ms2
        $t.Count = [int]$s.Count; $t.Cps = [double]$s.Cps; $t.Text = [string]$s.Text
        $arr[$i] = $t
    }
    $q.Steps = $arr
    return $q
}

function Sync-SeqEngine {
    if (-not $Global:Macro.Loaded) { return }
    # stop anything still playing from the old list before swapping it out
    [KuroMacro]::CancelSeqs()
    $list = New-Object System.Collections.ArrayList
    foreach ($m in $Global:Seq.Lib) {
        $ok = [bool]$m.Enabled -and $m.Steps.Count -gt 0 -and -not ([int]$m.Trigger -eq 5 -and [int]$m.TriggerVk -eq 0)
        if ($ok) { [void]$list.Add((New-KuroSeq $m $true)) }
    }
    $arr = New-Object 'KuroSeq[]' $list.Count
    for ($i = 0; $i -lt $list.Count; $i++) { $arr[$i] = $list[$i] }
    [KuroMacro]::Seqs = $arr
}

# ------------------------------------------------------------------ text helpers
function Get-SeqKeyName([int]$Vk) { if ($Vk -le 0) { return 'a key' } else { return (Get-KeyName $Vk) } }

function Get-SeqStepMs($s) {
    switch ([int]$s.K) {
        0 { return [int]$s.Ms }
        2 { return [int]$s.Ms }
        3 { return [int](([math]::Max(1, [int]$s.Count) - 1) * 1000 / [math]::Max(1, [double]$s.Cps)) }
        4 { return [int]($s.Text.Length * [int]$s.Ms) }
        6 { return 40 }
        9 { return [int](([math]::Max(1, [math]::Abs([int]$s.Count)) - 1) * 15) }
        10 { return [int](([int]$s.Ms + [int]$s.Ms2) / 2) }
        11 { return 0 }
    }
    return 1
}

function Get-SeqStepText($s) {
    $b = $Global:SeqBtnNames[[int]$s.Btn]
    switch ([int]$s.K) {
        0 { return 'Press ' + (Get-SeqKeyName $s.Vk) }
        1 { return "$b click" }
        2 { return "Wait $([int]$s.Ms) ms" }
        3 { return "$([int]$s.Count) $($b.ToLower()) clicks at $([int]$s.Cps)/s" }
        4 { $t = [string]$s.Text; if ($t.Length -gt 28) { $t = $t.Substring(0, 28) + '...' }; return 'Type "' + $t + '"' }
        5 {
            $p = @(); $mn = @('Ctrl', 'Shift', 'Alt', 'Win')
            for ($m = 0; $m -lt 4; $m++) { if (([int]$s.Mods -band (1 -shl $m)) -ne 0) { $p += $mn[$m] } }
            $p += (Get-SeqKeyName $s.Vk); return ($p -join ' + ')
        }
        6 { return "Double $($b.ToLower()) click" }
        7 { return "Move to $([int]$s.X), $([int]$s.Y)" }
        8 { return "Move by $([int]$s.X), $([int]$s.Y)" }
        9 { $n = [int]$s.Count; return $(if ($n -lt 0) { "Scroll down $(-$n)" } else { "Scroll up $n" }) }
        10 { return "Wait $([int]$s.Ms)-$([int]$s.Ms2) ms" }
        11 { return '# ' + [string]$s.Text }
        12 { return 'Hold ' + (Get-SeqKeyName $s.Vk) + ' down' }
        13 { return 'Let go of ' + (Get-SeqKeyName $s.Vk) }
        14 { return "$b button down" }
        15 { return "$b button up" }
    }
    return ''
}

function Get-SeqTrigText($m) {
    if ([int]$m.Trigger -eq 5) { $t = $(if ([int]$m.TriggerVk -gt 0) { Get-KeyName ([int]$m.TriggerVk) } else { 'no key set' }) }
    else { $t = $Global:MacroTriggers[[int]$m.Trigger] }
    switch ([int]$m.Mode) {
        0 { return "Press $t  $([char]0x00B7)  plays once" }
        1 { return "Press $t  $([char]0x00B7)  plays $([int]$m.Repeat) times" }
        2 { return "Hold $t  $([char]0x00B7)  loops while held" }
        3 { return "Press $t  $([char]0x00B7)  loops until pressed again" }
    }
}

function Format-SeqMs([int]$Ms) { if ($Ms -ge 1000) { return ('{0:0.0} s' -f ($Ms / 1000.0)) } else { return "$Ms ms" } }

# ------------------------------------------------------------------ small UI factories
function New-Brush2([string]$Hex, [int]$Alpha = 255) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb($Alpha, $c.R, $c.G, $c.B)); $b.Freeze(); return $b
}

function New-SeqChip([int]$K, [double]$Size = 26) {
    $meta = $Global:SeqKinds[$K]
    $bd = New-Object Windows.Controls.Border
    $bd.Width = $Size; $bd.Height = $Size; $bd.CornerRadius = New-Object Windows.CornerRadius 7
    $bd.Background = New-Brush2 $meta.C 0x40
    $bd.BorderBrush = New-Brush2 $meta.C 0x90; $bd.BorderThickness = New-Object Windows.Thickness 1
    $tx = New-Object Windows.Controls.TextBlock
    $tx.Text = [string][char]$meta.I
    $tx.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'
    $tx.FontSize = [math]::Round($Size * 0.48)
    $tx.Foreground = New-Brush2 $meta.C
    $tx.HorizontalAlignment = 'Center'; $tx.VerticalAlignment = 'Center'
    $bd.Child = $tx
    return $bd
}

function New-SeqText([string]$T, [double]$Size = 13, [string]$Res = 'TextBrush', [bool]$Bold = $false) {
    $tx = New-Object Windows.Controls.TextBlock
    $tx.Text = $T; $tx.FontSize = $Size; $tx.VerticalAlignment = 'Center'
    $tx.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $Res)
    if ($Bold) { $tx.FontWeight = [Windows.FontWeights]::SemiBold }
    return $tx
}

function New-SeqNumBox([int]$Value, [int]$Width = 110) {
    $tb = New-Object Windows.Controls.TextBox
    $tb.Style = $Global:CCH.Window.Resources['Input']
    $tb.Width = $Width; $tb.FontSize = 13; $tb.Padding = New-Object Windows.Thickness 10, 7, 10, 7
    $tb.HorizontalContentAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
    $tb.Text = [string]$Value
    [Windows.Controls.Grid]::SetColumn($tb, 1)
    return $tb
}

function New-SeqSegs([string[]]$Labels, [int]$Sel, [scriptblock]$OnPick) {
    $g = New-SegGroup 0 ('s' + [guid]::NewGuid().ToString('N').Substring(0, 8)) $Labels $OnPick
    for ($v = 0; $v -lt $g.Buttons.Count; $v++) { $g.Buttons[$v].IsChecked = ($v -eq $Sel) }
    return $g.Root
}

# ------------------------------------------------------------------ library tab
function Update-SeqLibrary {
    $ui = $Global:UI
    $ui.SeqLibList.Children.Clear()
    $ui.SeqLibEmpty.Visibility = $(if ($Global:Seq.Lib.Count -eq 0) { 'Visible' } else { 'Collapsed' })
    for ($i = 0; $i -lt $Global:Seq.Lib.Count; $i++) {
        $m = $Global:Seq.Lib[$i]
        $row = New-Object Windows.Controls.Border
        $row.CornerRadius = New-Object Windows.CornerRadius 10
        $row.Padding = New-Object Windows.Thickness 14, 10, 14, 10
        $row.Margin = New-Object Windows.Thickness 0, 0, 0, 8
        $row.BorderThickness = New-Object Windows.Thickness 1
        $row.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel2Brush')
        if ($i -eq $Global:Seq.Sel) { $row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') }
        else { $row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') }
        $g = New-Object Windows.Controls.Grid
        foreach ($w in @('Auto', '*', 'Auto', 'Auto', 'Auto', 'Auto')) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { $cd.Width = [Windows.GridLength]::Auto }
            [void]$g.ColumnDefinitions.Add($cd)
        }
        $k0 = $(if ($m.Steps.Count -gt 0) { [int]$m.Steps[0].K } else { 11 })
        $chip = New-SeqChip $k0 32; $chip.Margin = New-Object Windows.Thickness 0, 0, 12, 0
        [void]$g.Children.Add($chip)
        $sp = New-Object Windows.Controls.StackPanel; $sp.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($sp, 1)
        [void]$sp.Children.Add((New-SeqText $m.Name 14 'TextBrush' $true))
        $total = 0; foreach ($s in $m.Steps) { $total += (Get-SeqStepMs $s) }
        $sub = New-SeqText ((Get-SeqTrigText $m) + "  $([char]0x00B7)  $($m.Steps.Count) blocks, " + (Format-SeqMs $total)) 12 'SubTextBrush'
        $sub.TextTrimming = 'CharacterEllipsis'; $sub.Margin = New-Object Windows.Thickness 0, 2, 0, 0
        [void]$sp.Children.Add($sub)
        [void]$g.Children.Add($sp)

        $en = New-Object Windows.Controls.CheckBox
        $en.Style = $Global:CCH.Window.Resources['Switch']; $en.IsChecked = [bool]$m.Enabled; $en.Tag = $i
        $en.VerticalAlignment = 'Center'; $en.Margin = New-Object Windows.Thickness 12, 0, 12, 0
        $en.ToolTip = 'Switch this macro on or off'
        $pl = New-Object Windows.Controls.Button
        $pl.Style = $Global:CCH.Window.Resources['GhostBtn']; $pl.Tag = $i; $pl.ToolTip = 'Play once (after 3 seconds)'
        $pl.Padding = New-Object Windows.Thickness 10, 7, 10, 7; $pl.Margin = New-Object Windows.Thickness 12, 0, 0, 0
        $pt = New-Object Windows.Controls.TextBlock; $pt.Text = [string][char]0xE768; $pt.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'; $pt.FontSize = 11
        $pt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'AccentBrush'); $pl.Content = $pt
        [Windows.Controls.Grid]::SetColumn($pl, 2)
        $pl.Add_Click({ Select-SeqMacro ([int]$this.Tag); Invoke-SeqTest })
        [void]$g.Children.Add($pl)
        [Windows.Controls.Grid]::SetColumn($en, 3)
        $en.Add_Click({
            $i = [int]$this.Tag; $m = $Global:Seq.Lib[$i]
            if ([bool]$this.IsChecked -and [int]$m.Trigger -eq 5 -and [int]$m.TriggerVk -eq 0) {
                $this.IsChecked = $false
                Show-Toast 'Set a trigger key for this macro first (Settings tab).' 'info'
                Select-SeqMacro $i; Show-MacTab 'Set'; return
            }
            if ([bool]$this.IsChecked -and $m.Steps.Count -eq 0) {
                $this.IsChecked = $false; Show-Toast 'This macro has no blocks yet.' 'info'; return
            }
            $m.Enabled = [bool]$this.IsChecked
            Save-SeqLibrary
            if ($m.Enabled -and -not [bool]$Global:UI.MacroMaster.IsChecked) { Show-Toast 'Saved. Turn on Macros in the General box to start it.' 'info' }
        })
        [void]$g.Children.Add($en)

        $ed = New-Object Windows.Controls.Button
        $ed.Style = $Global:CCH.Window.Resources['GhostBtn']; $ed.Content = 'Edit'; $ed.Tag = $i
        $ed.Padding = New-Object Windows.Thickness 14, 7, 14, 7; $ed.Margin = New-Object Windows.Thickness 0, 0, 6, 0
        [Windows.Controls.Grid]::SetColumn($ed, 4)
        $ed.Add_Click({ Select-SeqMacro ([int]$this.Tag); Show-MacTab 'Steps' })
        [void]$g.Children.Add($ed)

        $del = New-Object Windows.Controls.Button
        $del.Style = $Global:CCH.Window.Resources['GhostBtn']; $del.Tag = $i
        $del.Padding = New-Object Windows.Thickness 11, 7, 11, 7; $del.ToolTip = 'Delete'
        $dt = New-Object Windows.Controls.TextBlock; $dt.Text = [string][char]0xE74D; $dt.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'; $dt.FontSize = 12
        $dt.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, 'BadBrush')
        $del.Content = $dt
        [Windows.Controls.Grid]::SetColumn($del, 5)
        $del.Add_Click({
            $i = [int]$this.Tag
            Show-Modal 'Delete this macro?' ("'" + $Global:Seq.Lib[$i].Name + "' will be removed from your library. This cannot be undone.") 'Delete' 'Cancel' {
                param($idx)
                $Global:Seq.Lib.RemoveAt([int]$idx)
                if ($Global:Seq.Sel -eq [int]$idx) { $Global:Seq.Sel = -1; $Global:Seq.Block = -1 }
                elseif ($Global:Seq.Sel -gt [int]$idx) { $Global:Seq.Sel-- }
                Save-SeqLibrary; Update-SeqAll
            } $i
        })
        [void]$g.Children.Add($del)

        $row.Child = $g
        $row.Tag = $i; $row.Cursor = [Windows.Input.Cursors]::Hand
        $row.Add_MouseLeftButtonUp({
            param($s, $e)
            try { $d = $e.OriginalSource; while ($d -and $d -ne $s) { if ($d -is [Windows.Controls.Primitives.ButtonBase]) { return }; $d = [Windows.Media.VisualTreeHelper]::GetParent($d) } } catch { }
            Select-SeqMacro ([int]$s.Tag); Show-MacTab 'Steps'
        })
        [void]$ui.SeqLibList.Children.Add($row)
    }
}

function Select-SeqMacro([int]$i) {
    $Global:Seq.Sel = $i
    $m = Get-SeqSel
    $Global:Seq.Block = $(if ($m -and $m.Steps.Count -gt 0) { 0 } else { -1 })
    Update-SeqAll
}

function New-SeqMacro {
    $m = ConvertTo-SeqMacro @{ Name = ('My macro ' + ($Global:Seq.Lib.Count + 1)); Trigger = 5; TriggerVk = 0; Mode = 0; Repeat = 3; Steps = @() }
    [void]$Global:Seq.Lib.Add($m)
    Save-SeqLibrary
    Select-SeqMacro ($Global:Seq.Lib.Count - 1)
    Show-MacTab 'Steps'
    Show-Toast 'New macro made. Add blocks or click Record, then set its trigger in Settings.' 'info'
}

# ------------------------------------------------------------------ steps tab
function Build-SeqPalette {
    $ui = $Global:UI
    $ui.SeqPalette.Children.Clear()
    for ($k = 0; $k -lt $Global:SeqKinds.Count; $k++) {
        $meta = $Global:SeqKinds[$k]
        $b = New-Object Windows.Controls.Button
        $b.Cursor = [Windows.Input.Cursors]::Hand
        $b.Tag = $k; $b.Margin = New-Object Windows.Thickness 0, 0, 8, 8
        $b.ToolTip = 'Add a ' + $meta.N + ' block'
        $tpl = [Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border x:Name="b" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="9" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="5,4,10,4"><ContentPresenter VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger></ControlTemplate.Triggers></ControlTemplate>')
        $b.Template = $tpl
        $b.Background = New-Brush2 $meta.C 0x18
        $b.BorderBrush = New-Brush2 $meta.C 0x60
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        $chip = New-SeqChip $k 24; $chip.Margin = New-Object Windows.Thickness 0, 0, 8, 0
        [void]$sp.Children.Add($chip)
        [void]$sp.Children.Add((New-SeqText $meta.N 12.5 'TextBrush' $true))
        $plus = New-SeqText '+' 14 'SubTextBrush'; $plus.Margin = New-Object Windows.Thickness 8, 0, 0, 1
        [void]$sp.Children.Add($plus)
        $b.Content = $sp
        $b.Add_Click({ Add-SeqBlock ([int]$this.Tag) })
        [void]$ui.SeqPalette.Children.Add($b)
    }
}

function Add-SeqBlock([int]$K) {
    $m = Get-SeqSel; if (-not $m) { return }
    if ($m.Steps.Count -ge $Global:SeqMaxSteps) { Show-Toast "A macro can have up to $($Global:SeqMaxSteps) blocks." 'error'; return }
    $at = $(if ($Global:Seq.Block -ge 0) { $Global:Seq.Block + 1 } else { $m.Steps.Count })
    $m.Steps.Insert($at, (New-SeqStep $K))
    $Global:Seq.Block = $at
    Save-SeqLibrary
    Update-SeqSteps
}

function Update-SeqTimeline($m) {
    $ui = $Global:UI
    $tl = $ui.SeqTimeline
    $tl.Children.Clear(); $tl.ColumnDefinitions.Clear()
    $total = 0; foreach ($s in $m.Steps) { $total += (Get-SeqStepMs $s) }
    $n = $m.Steps.Count
    $ui.SeqPlayTxt.Text = (Format-SeqMs $total) + ' - ' + $(if ($n -eq 1) { '1 block' } else { "$n blocks" })
    if ($n -eq 0) { return }
    $min = [math]::Max(1.0, $total / 60.0)
    for ($i = 0; $i -lt $n; $i++) {
        $s = $m.Steps[$i]
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = New-Object Windows.GridLength ([math]::Max($min, [double](Get-SeqStepMs $s))), ([Windows.GridUnitType]::Star)
        [void]$tl.ColumnDefinitions.Add($cd)
        $r = New-Object Windows.Controls.Border
        $r.Background = New-Brush2 $Global:SeqKinds[[int]$s.K].C $(if ($i -eq $Global:Seq.Block) { 255 } else { 0xB0 })
        $r.Margin = New-Object Windows.Thickness 0, 0, 1, 0
        $r.ToolTip = ("{0}. {1}" -f ($i + 1), (Get-SeqStepText $s))
        [Windows.Controls.Grid]::SetColumn($r, $i)
        [void]$tl.Children.Add($r)
    }
}

function Update-SeqSteps {
    $ui = $Global:UI
    $m = Get-SeqSel
    $ui.SeqNoneTxt.Visibility = $(if ($m) { 'Collapsed' } else { 'Visible' })
    $ui.SeqStepsBody.Visibility = $(if ($m) { 'Visible' } else { 'Collapsed' })
    if (-not $m) { return }
    if ($Global:Seq.Block -ge $m.Steps.Count) { $Global:Seq.Block = $m.Steps.Count - 1 }
    $ui.SeqTitle.Text = 'Build it: ' + $m.Name
    $ui.SeqSavedTxt.Text = (Get-SeqCountText) + ', saved'
    Update-SeqTimeline $m

    $ui.SeqBlockList.Children.Clear()
    $rows = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $m.Steps.Count; $i++) {
        $s = $m.Steps[$i]
        $row = New-Object Windows.Controls.Border
        $row.CornerRadius = New-Object Windows.CornerRadius 9
        $row.Padding = New-Object Windows.Thickness 8, 6, 10, 6
        $row.Margin = New-Object Windows.Thickness 0, 0, 0, 6
        $row.BorderThickness = New-Object Windows.Thickness 1.5
        $row.Cursor = [Windows.Input.Cursors]::Hand; $row.Tag = $i
        $row.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'Panel2Brush')
        if ($i -eq $Global:Seq.Block) { $row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') }
        else { $row.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') }
        $g = New-Object Windows.Controls.Grid
        foreach ($w in @('Auto', 'Auto', '*', 'Auto')) {
            $cd = New-Object Windows.Controls.ColumnDefinition
            if ($w -eq '*') { $cd.Width = New-Object Windows.GridLength 1, ([Windows.GridUnitType]::Star) } else { $cd.Width = [Windows.GridLength]::Auto }
            [void]$g.ColumnDefinitions.Add($cd)
        }
        [void]$g.Children.Add((New-SeqChip ([int]$s.K) 28))
        $idx = New-SeqText ([string]($i + 1)) 11.5 'SubTextBrush'; $idx.Margin = New-Object Windows.Thickness 10, 0, 14, 0; $idx.MinWidth = 18
        [Windows.Controls.Grid]::SetColumn($idx, 1); [void]$g.Children.Add($idx)
        $tx = New-SeqText (Get-SeqStepText $s) 13.5 'TextBrush' $true; $tx.TextTrimming = 'CharacterEllipsis'
        [Windows.Controls.Grid]::SetColumn($tx, 2); [void]$g.Children.Add($tx)
        $pill = New-Object Windows.Controls.Border
        $pill.CornerRadius = New-Object Windows.CornerRadius 8; $pill.Padding = New-Object Windows.Thickness 8, 2, 8, 2
        $pill.SetResourceReference([Windows.Controls.Border]::BackgroundProperty, 'PanelBrush')
        $pill.Child = (New-SeqText (Format-SeqMs (Get-SeqStepMs $s)) 11.5 'SubTextBrush')
        [Windows.Controls.Grid]::SetColumn($pill, 3); [void]$g.Children.Add($pill)
        $row.Child = $g
        $row.Add_MouseLeftButtonUp({ param($s, $e) $Global:Seq.Block = [int]$s.Tag; Update-SeqSteps })
        [void]$ui.SeqBlockList.Children.Add($row); [void]$rows.Add($row)
    }
    $Global:Seq.Rows = $rows.ToArray()
    Update-SeqEditor
}

# --- block editor
function Add-SeqField([string]$Title, [string]$Sub, $Ctrl) {
    $row = New-MacroRow $Title $Sub ''
    [void]$row.Child.Children.Add($Ctrl)
    [void]$Global:UI.SeqFields.Children.Add($row)
}

function Set-SeqBlockField([string]$Field, $Value, [bool]$Rebuild = $false) {
    $m = Get-SeqSel; if (-not $m -or $Global:Seq.Block -lt 0) { return }
    $m.Steps[$Global:Seq.Block][$Field] = $Value
    Save-SeqLibrary
    if ($Rebuild) { Update-SeqSteps } else { Update-SeqStepsLight }
}

# refresh list texts and timeline without rebuilding the editor (keeps focus in text boxes)
function Update-SeqStepsLight {
    $m = Get-SeqSel; if (-not $m) { return }
    $i = $Global:Seq.Block
    if ($i -ge 0 -and $i -lt $Global:Seq.Rows.Count) {
        $g = $Global:Seq.Rows[$i].Child
        $g.Children[2].Text = Get-SeqStepText $m.Steps[$i]
        $g.Children[3].Child.Text = Format-SeqMs (Get-SeqStepMs $m.Steps[$i])
        $Global:UI.SeqEdSub.Text = Get-SeqStepText $m.Steps[$i]
    }
    Update-SeqTimeline $m
}

function New-SeqNumField([string]$Field, [int]$Min, [int]$Max, [int]$Width = 110) {
    $s = (Get-SeqSel).Steps[$Global:Seq.Block]
    $tb = New-SeqNumBox ([int]$s[$Field]) $Width
    $tb.Tag = "$Field|$Min|$Max"
    $commit = {
        $p = ([string]$this.Tag).Split('|')
        $v = Get-IntIn $this.Text ([int]$p[1]) ([int]$p[2]) ([int]$p[1])
        $this.Text = [string]$v
        Set-SeqBlockField $p[0] $v
    }
    $tb.Add_LostKeyboardFocus($commit)
    $tb.Add_KeyDown({ if ($_.Key -eq 'Return') { [System.Windows.Input.Keyboard]::ClearFocus() } })
    return $tb
}

function New-SeqKeyField([string]$Field) {
    $s = (Get-SeqSel).Steps[$Global:Seq.Block]
    $tb = New-KeyBox
    $tb.Text = Get-SeqKeyName ([int]$s[$Field])
    $tb.Tag = $Field
    $tb.Add_GotKeyboardFocus({ $this.Text = 'Press a key...' })
    $tb.Add_LostKeyboardFocus({ $s = (Get-SeqSel).Steps[$Global:Seq.Block]; $this.Text = Get-SeqKeyName ([int]$s[[string]$this.Tag]) })
    $tb.Add_PreviewKeyDown({
        $_.Handled = $true
        $key = $_.Key; if ([string]$key -eq 'System') { $key = $_.SystemKey }
        if ([string]$key -eq 'Escape') { [System.Windows.Input.Keyboard]::ClearFocus(); return }
        $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
        if ($vk -eq 0x77) { Show-Toast 'F8 is reserved for stop/pause.' 'info'; return }
        Set-SeqBlockField ([string]$this.Tag) ([int]$vk)
        [System.Windows.Input.Keyboard]::ClearFocus()
    })
    return $tb
}

function New-SeqBtnField {
    $s = (Get-SeqSel).Steps[$Global:Seq.Block]
    return (New-SeqSegs $Global:SeqBtnNames ([int]$s.Btn) { Set-SeqBlockField 'Btn' ([int]$this.Tag) })
}

function Update-SeqEditor {
    $ui = $Global:UI
    $m = Get-SeqSel
    $i = $Global:Seq.Block
    if (-not $m -or $i -lt 0 -or $i -ge $m.Steps.Count) { $ui.SeqEditorCard.Visibility = 'Collapsed'; return }
    $ui.SeqEditorCard.Visibility = 'Visible'
    $s = $m.Steps[$i]
    $ui.SeqEdTitle.Text = "Block $($i + 1): " + $Global:SeqKinds[[int]$s.K].N
    $ui.SeqEdSub.Text = Get-SeqStepText $s
    $ui.BtnSeqUp.IsEnabled = ($i -gt 0)
    $ui.BtnSeqDown.IsEnabled = ($i -lt $m.Steps.Count - 1)
    $ui.SeqFields.Children.Clear()
    switch ([int]$s.K) {
        0 {
            Add-SeqField 'Key' 'Click the box, then press the key.' (New-SeqKeyField 'Vk')
            Add-SeqField 'Hold for' 'How long the key stays down, in milliseconds.' (New-SeqNumField 'Ms' 1 10000)
        }
        1 { Add-SeqField 'Button' 'Which mouse button to click.' (New-SeqBtnField) }
        2 { Add-SeqField 'Wait' 'Pause before the next block, in milliseconds.' (New-SeqNumField 'Ms' 0 60000) }
        3 {
            Add-SeqField 'Button' 'Which mouse button to click.' (New-SeqBtnField)
            Add-SeqField 'Clicks' 'How many clicks this block sends.' (New-SeqNumField 'Count' 1 1000)
            Add-SeqField 'Speed' 'Clicks per second (1 to 50).' (New-SeqNumField 'Cps' 1 50)
        }
        4 {
            $tb = New-Object Windows.Controls.TextBox
            $tb.Style = $Global:CCH.Window.Resources['Input']; $tb.Width = 300; $tb.MaxLength = 500; $tb.FontSize = 13
            $tb.Text = [string]$s.Text; [Windows.Controls.Grid]::SetColumn($tb, 1)
            $tb.Add_LostKeyboardFocus({ Set-SeqBlockField 'Text' ([string]$this.Text) })
            Add-SeqField 'Text' 'Typed letter by letter into the active window.' $tb
            Add-SeqField 'Gap between letters' 'Milliseconds between each letter.' (New-SeqNumField 'Ms' 0 500)
        }
        5 {
            $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; [Windows.Controls.Grid]::SetColumn($sp, 1)
            $names = @('Ctrl', 'Shift', 'Alt', 'Win')
            for ($b = 0; $b -lt 4; $b++) {
                $cb = New-Object Windows.Controls.CheckBox
                $cb.Style = $Global:CCH.Window.Resources['Switch']; $cb.Content = $names[$b]; $cb.Tag = $b
                $cb.Margin = New-Object Windows.Thickness 0, 0, 14, 0
                $cb.IsChecked = (([int]$s.Mods -band (1 -shl $b)) -ne 0)
                $cb.Add_Click({ $s = (Get-SeqSel).Steps[$Global:Seq.Block]; $bit = 1 -shl [int]$this.Tag; $v = [int]$s.Mods; if ($this.IsChecked) { $v = $v -bor $bit } else { $v = $v -band (-bnot $bit) }; Set-SeqBlockField 'Mods' $v })
                [void]$sp.Children.Add($cb)
            }
            Add-SeqField 'Hold these' 'Held down while the key below is pressed.' $sp
            Add-SeqField 'Key' 'Click the box, then press the key.' (New-SeqKeyField 'Vk')
        }
        6 { Add-SeqField 'Button' 'Which mouse button to double click.' (New-SeqBtnField) }
        7 {
            Add-SeqField 'X' 'Screen position from the left, in pixels.' (New-SeqNumField 'X' -100000 100000)
            Add-SeqField 'Y' 'Screen position from the top, in pixels.' (New-SeqNumField 'Y' -100000 100000)
            $pick = New-Object Windows.Controls.Button
            $pick.Style = $Global:CCH.Window.Resources['GhostBtn']; $pick.Content = 'Use my mouse in 3 s'; $pick.Padding = New-Object Windows.Thickness 14, 7, 14, 7
            [Windows.Controls.Grid]::SetColumn($pick, 1)
            $pick.Add_Click({ Start-SeqPickPos })
            Add-SeqField 'Pick the spot' 'Click, then hold your mouse where it should go.' $pick
        }
        8 {
            Add-SeqField 'Left / right' 'Pixels to move sideways. Minus goes left.' (New-SeqNumField 'X' -10000 10000)
            Add-SeqField 'Up / down' 'Pixels to move up or down. Minus goes up.' (New-SeqNumField 'Y' -10000 10000)
        }
        9 { Add-SeqField 'Notches' 'Wheel notches. Plus scrolls up, minus scrolls down.' (New-SeqNumField 'Count' -100 100) }
        10 {
            Add-SeqField 'Shortest' 'Shortest wait, in milliseconds.' (New-SeqNumField 'Ms' 0 60000)
            Add-SeqField 'Longest' 'Longest wait, in milliseconds.' (New-SeqNumField 'Ms2' 0 60000)
        }
        11 {
            $tb = New-Object Windows.Controls.TextBox
            $tb.Style = $Global:CCH.Window.Resources['Input']; $tb.Width = 300; $tb.MaxLength = 80; $tb.FontSize = 13
            $tb.Text = [string]$s.Text; [Windows.Controls.Grid]::SetColumn($tb, 1)
            $tb.Add_LostKeyboardFocus({ Set-SeqBlockField 'Text' ([string]$this.Text) })
            Add-SeqField 'Note' 'Just a label to keep long macros readable. It does nothing.' $tb
        }
        { $_ -eq 12 -or $_ -eq 13 } { Add-SeqField 'Key' 'Click the box, then press the key.' (New-SeqKeyField 'Vk') }
        { $_ -eq 14 -or $_ -eq 15 } { Add-SeqField 'Button' 'Which mouse button.' (New-SeqBtnField) }
    }
}

function Move-SeqBlock([int]$Dir) {
    $m = Get-SeqSel; $i = $Global:Seq.Block
    if (-not $m -or $i -lt 0) { return }
    $j = $i + $Dir
    if ($j -lt 0 -or $j -ge $m.Steps.Count) { return }
    $t = $m.Steps[$i]; $m.Steps[$i] = $m.Steps[$j]; $m.Steps[$j] = $t
    $Global:Seq.Block = $j
    Save-SeqLibrary; Update-SeqSteps
}

function Copy-SeqBlock {
    $m = Get-SeqSel; $i = $Global:Seq.Block
    if (-not $m -or $i -lt 0) { return }
    if ($m.Steps.Count -ge $Global:SeqMaxSteps) { Show-Toast "A macro can have up to $($Global:SeqMaxSteps) blocks." 'error'; return }
    $m.Steps.Insert($i + 1, $m.Steps[$i].Clone())
    $Global:Seq.Block = $i + 1
    Save-SeqLibrary; Update-SeqSteps
}

function Remove-SeqBlock {
    $m = Get-SeqSel; $i = $Global:Seq.Block
    if (-not $m -or $i -lt 0) { return }
    $m.Steps.RemoveAt($i)
    if ($Global:Seq.Block -ge $m.Steps.Count) { $Global:Seq.Block = $m.Steps.Count - 1 }
    if ($m.Steps.Count -eq 0 -and $m.Enabled) { $m.Enabled = $false }
    Save-SeqLibrary; Update-SeqSteps
}

# --- pick a screen position for "Move mouse"
function Start-SeqPickPos {
    if (-not (Initialize-MacroEngine)) { Show-Toast ('Macro engine could not load: ' + $Global:Macro.Error) 'error'; return }
    $Global:Seq.PickAt = [DateTime]::UtcNow.AddSeconds(3)
    $Global:Seq.Picking = $true
    Show-Toast 'Hold your mouse where it should go... 3 seconds.' 'info'
    Start-SeqTimer
}

# ------------------------------------------------------------------ test + record (one shared timer)
function Start-SeqTimer {
    if (-not $Global:Seq.Timer) {
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(100)
        $t.Add_Tick({ try { Step-SeqTimer } catch { Write-Log "Macro builder timer: $($_.Exception.Message)" } })
        $Global:Seq.Timer = $t
    }
    $Global:Seq.Timer.Start()
}

function Step-SeqTimer {
    $sq = $Global:Seq; $ui = $Global:UI
    $busy = $false
    if ($sq.Picking) {
        $busy = $true
        if ([DateTime]::UtcNow -ge $sq.PickAt) {
            $sq.Picking = $false
            $p = [KuroMacro]::CursorPos()
            $m = Get-SeqSel
            if ($m -and $sq.Block -ge 0 -and [int]$m.Steps[$sq.Block].K -eq 7) {
                $m.Steps[$sq.Block].X = [int]$p[0]; $m.Steps[$sq.Block].Y = [int]$p[1]
                Save-SeqLibrary; Update-SeqSteps
                Show-Toast "Saved the spot $($p[0]), $($p[1])."
            }
        }
    }
    if ($sq.TestQ) {
        $busy = $true
        $pos = [int]$sq.TestQ.Pos
        for ($r = 0; $r -lt $sq.Rows.Count; $r++) {
            if ($r -eq $pos) { $sq.Rows[$r].SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'GoodBrush') }
            elseif ($r -eq $sq.Block) { $sq.Rows[$r].SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'AccentBrush') }
            else { $sq.Rows[$r].SetResourceReference([Windows.Controls.Border]::BorderBrushProperty, 'LineBrush') }
        }
        $left = ($sq.TestAt - [DateTime]::UtcNow).TotalSeconds
        if ($left -gt 0) { $ui.SeqTestTxt.Text = ('Starts in {0}...' -f [int][math]::Ceiling($left)) } else { $ui.SeqTestTxt.Text = 'Stop (F8)' }
        if (-not $sq.TestQ.Running) {
            $sq.TestQ = $null
            $ui.SeqTestTxt.Text = 'Test'
            Update-SeqSteps
            Show-Toast 'Test finished.'
        }
    }
    if ($sq.Rec -eq 'count') {
        $busy = $true
        $left = ($sq.RecAt - [DateTime]::UtcNow).TotalSeconds
        if ($left -gt 0) { $ui.SeqRecTxt.Text = ('Recording in {0}...' -f [int][math]::Ceiling($left)) }
        else {
            $r = [KuroMacro]::RecStart()
            if ($r -ne 'ok') { $sq.Rec = 'idle'; $ui.SeqRecTxt.Text = 'Record'; Show-Toast ('Recorder could not start: ' + $r) 'error' }
            else { $sq.Rec = 'rec'; $ui.SeqRecTxt.Text = 'Stop recording'; $ui.SeqRecDot.Fill = $Global:CCH.Window.Resources['BadBrush'] }
        }
    } elseif ($sq.Rec -eq 'rec') {
        $busy = $true
        $ui.SeqRecDot.Opacity = $(if ($ui.SeqRecDot.Opacity -gt 0.6) { 0.35 } else { 1.0 })
    }
    if (-not $busy) { $sq.Timer.Stop() }
}

function Invoke-SeqTest {
    $sq = $Global:Seq; $m = Get-SeqSel
    if (-not $m) { return }
    if ($sq.TestQ) { $sq.TestQ.Cancel = $true; return }
    if ($m.Steps.Count -eq 0) { Show-Toast 'Add a block first.' 'info'; return }
    if ($sq.Rec -ne 'idle') { Show-Toast 'Stop recording first.' 'info'; return }
    if (-not (Initialize-MacroEngine)) { Show-Toast ('Macro engine could not load: ' + $Global:Macro.Error) 'error'; return }
    $q = New-KuroSeq $m $true
    if (-not [KuroMacro]::TestSeq($q, 3000)) { Show-Toast 'Could not start the test.' 'error'; return }
    $sq.TestQ = $q; $sq.TestAt = [DateTime]::UtcNow.AddSeconds(3)
    Show-Toast 'Playing once in 3 seconds. Click into your game now. F8 stops it.' 'info'
    Start-SeqTimer
}

function Convert-SeqRecording([string[]]$Lines, [bool]$WithPos) {
    $ev = New-Object System.Collections.ArrayList
    foreach ($l in $Lines) {
        $p = $l.Split('|'); if ($p.Count -lt 5) { continue }
        [void]$ev.Add(@{ T = [long]$p[0]; Ty = $p[1]; C = [int]$p[2]; X = [int]$p[3]; Y = [int]$p[4]; Used = $false })
    }
    $steps = New-Object System.Collections.ArrayList
    $last = -1
    $addWait = {
        param($t)
        if ($last -ge 0) { $gap = [int]($t - $last); if ($gap -ge 10) { [void]$steps.Add((ConvertTo-SeqStep @{ K = 2; Ms = [math]::Min(60000, $gap) })) } }
    }
    for ($i = 0; $i -lt $ev.Count; $i++) {
        if ($steps.Count -ge $Global:SeqMaxSteps - 2) { break }
        $e = $ev[$i]; if ($e.Used) { continue }
        $n = $(if ($i + 1 -lt $ev.Count) { $ev[$i + 1] } else { $null })
        switch ($e.Ty) {
            'kd' {
                & $addWait $e.T
                if ($n -and $n.Ty -eq 'ku' -and $n.C -eq $e.C) {
                    [void]$steps.Add((ConvertTo-SeqStep @{ K = 0; Vk = $e.C; Ms = [math]::Max(1, [int]($n.T - $e.T)) }))
                    $n.Used = $true; $last = $n.T
                } else { [void]$steps.Add((ConvertTo-SeqStep @{ K = 12; Vk = $e.C })); $last = $e.T }
            }
            'ku' { & $addWait $e.T; [void]$steps.Add((ConvertTo-SeqStep @{ K = 13; Vk = $e.C })); $last = $e.T }
            'md' {
                & $addWait $e.T
                if ($WithPos) { [void]$steps.Add((ConvertTo-SeqStep @{ K = 7; X = $e.X; Y = $e.Y })) }
                if ($n -and $n.Ty -eq 'mu' -and $n.C -eq $e.C -and ($n.T - $e.T) -lt 250) {
                    [void]$steps.Add((ConvertTo-SeqStep @{ K = 1; Btn = $e.C })); $n.Used = $true; $last = $n.T
                } else { [void]$steps.Add((ConvertTo-SeqStep @{ K = 14; Btn = $e.C })); $last = $e.T }
            }
            'mu' { & $addWait $e.T; [void]$steps.Add((ConvertTo-SeqStep @{ K = 15; Btn = $e.C })); $last = $e.T }
            'wh' {
                & $addWait $e.T
                $notches = [int][math]::Round($e.C / 120.0); if ($notches -eq 0) { $notches = $(if ($e.C -lt 0) { -1 } else { 1 }) }
                $t = $e.T
                # merge a fast run of wheel notches in the same direction into one block
                for ($j = $i + 1; $j -lt $ev.Count; $j++) {
                    $w = $ev[$j]
                    if ($w.Ty -ne 'wh' -or ($w.T - $t) -gt 80 -or ([math]::Sign($w.C) -ne [math]::Sign($e.C))) { break }
                    $notches += [int][math]::Round($w.C / 120.0); $w.Used = $true; $t = $w.T
                }
                [void]$steps.Add((ConvertTo-SeqStep @{ K = 9; Count = $notches })); $last = $t
            }
        }
    }
    return $steps.ToArray()
}

function Invoke-SeqRecord {
    $sq = $Global:Seq; $ui = $Global:UI; $m = Get-SeqSel
    if (-not $m) { return }
    if ($sq.Rec -eq 'count') { $sq.Rec = 'idle'; $ui.SeqRecTxt.Text = 'Record'; return }
    if ($sq.Rec -eq 'rec') {
        $lines = @([KuroMacro]::RecStop())
        $sq.Rec = 'idle'; $ui.SeqRecTxt.Text = 'Record'; $ui.SeqRecDot.Opacity = 1.0
        $ui.SeqRecDot.Fill = $Global:CCH.Window.Resources['TextBrush']
        $new = @(Convert-SeqRecording $lines ([bool]$ui.SeqRecPos.IsChecked))
        if ($new.Count -eq 0) { Show-Toast 'Nothing was recorded. Keys and clicks inside Kuro are ignored, so play in your game window.' 'info'; return }
        $room = $Global:SeqMaxSteps - $m.Steps.Count
        if ($room -le 0) { Show-Toast "This macro is already at the $($Global:SeqMaxSteps)-block limit." 'error'; return }
        if ($new.Count -gt $room) { $new = $new[0..([math]::Max(0, $room - 1))]; Show-Toast "Recording trimmed to fit the $($Global:SeqMaxSteps)-block limit." 'info' }
        foreach ($s in $new) { [void]$m.Steps.Add($s) }
        $Global:Seq.Block = $m.Steps.Count - 1
        Save-SeqLibrary; Update-SeqSteps
        Show-Toast "Recorded $($new.Count) blocks. Tidy them up below, then Test."
        return
    }
    if ($sq.TestQ) { Show-Toast 'Wait for the test to finish first.' 'info'; return }
    if (-not (Initialize-MacroEngine)) { Show-Toast ('Macro engine could not load: ' + $Global:Macro.Error) 'error'; return }
    $sq.Rec = 'count'; $sq.RecAt = [DateTime]::UtcNow.AddSeconds(3)
    Show-Toast 'Recording starts in 3 seconds. Switch to your game, play, then come back and click Stop.' 'info'
    Start-SeqTimer
}

# ------------------------------------------------------------------ settings tab
function Update-SeqSettings {
    $ui = $Global:UI; $m = Get-SeqSel
    $ui.SeqSetNone.Visibility = $(if ($m) { 'Collapsed' } else { 'Visible' })
    $ui.SeqSetCard.Visibility = $(if ($m) { 'Visible' } else { 'Collapsed' })
    $ui.SeqSetRows.Children.Clear()
    if (-not $m) { return }
    $add = { param($t, $s, $c) $row = New-MacroRow $t $s ''; [void]$row.Child.Children.Add($c); [void]$Global:UI.SeqSetRows.Children.Add($row); $row }

    $nm = New-Object Windows.Controls.TextBox
    $nm.Style = $Global:CCH.Window.Resources['Input']; $nm.Width = 240; $nm.MaxLength = 40; $nm.FontSize = 13; $nm.Text = $m.Name
    [Windows.Controls.Grid]::SetColumn($nm, 1)
    $nm.Add_LostKeyboardFocus({ $m = Get-SeqSel; $v = ([string]$this.Text).Trim(); if (-not $v) { $v = 'My macro' }; $m.Name = $v; Save-SeqLibrary; $Global:UI.SeqTitle.Text = 'Build it: ' + $v })
    $first = & $add 'Name' 'Shown in your library.' $nm
    $first.BorderThickness = New-Object Windows.Thickness 0

    $trig = New-SeqSegs $Global:MacroTrigShort ([int]$m.Trigger) { $m = Get-SeqSel; $m.Trigger = [int]$this.Tag; Save-SeqLibrary; Update-SeqSettings }
    [void](& $add 'Trigger' 'What starts the macro.' $trig)
    if ([int]$m.Trigger -eq 5) {
        $kb = New-KeyBox
        $kb.Text = $(if ([int]$m.TriggerVk -gt 0) { Get-KeyName ([int]$m.TriggerVk) } else { 'not set' })
        $kb.Add_GotKeyboardFocus({ $this.Text = 'Press a key...' })
        $kb.Add_LostKeyboardFocus({ $m = Get-SeqSel; $this.Text = $(if ([int]$m.TriggerVk -gt 0) { Get-KeyName ([int]$m.TriggerVk) } else { 'not set' }) })
        $kb.Add_PreviewKeyDown({
            $_.Handled = $true
            $key = $_.Key; if ([string]$key -eq 'System') { $key = $_.SystemKey }
            if ([string]$key -eq 'Escape') { [System.Windows.Input.Keyboard]::ClearFocus(); return }
            $vk = [System.Windows.Input.KeyInterop]::VirtualKeyFromKey($key)
            if ($vk -eq 0x77) { Show-Toast 'F8 is reserved for stop/pause.' 'info'; return }
            $m = Get-SeqSel; $m.TriggerVk = [int]$vk; Save-SeqLibrary
            [System.Windows.Input.Keyboard]::ClearFocus()
        })
        [void](& $add 'Trigger key' 'Click the box, then press a key.' $kb)
    }
    $mode = New-SeqSegs $Global:SeqModeNames ([int]$m.Mode) { $m = Get-SeqSel; $m.Mode = [int]$this.Tag; Save-SeqLibrary; Update-SeqSettings }
    [void](& $add 'Plays' 'Once per press, a set number of times, while you hold the trigger, or on/off with each press.' $mode)
    if ([int]$m.Mode -eq 1) {
        $rp = New-SeqNumBox ([int]$m.Repeat) 110
        $rp.Add_LostKeyboardFocus({ $m = Get-SeqSel; $v = Get-IntIn $this.Text 1 1000 1; $this.Text = [string]$v; $m.Repeat = $v; Save-SeqLibrary })
        $rp.Add_KeyDown({ if ($_.Key -eq 'Return') { [System.Windows.Input.Keyboard]::ClearFocus() } })
        [void](& $add 'Times' 'How many times it plays per press (1 to 1000).' $rp)
    }
    $en = New-Object Windows.Controls.CheckBox
    $en.Style = $Global:CCH.Window.Resources['Switch']; $en.IsChecked = [bool]$m.Enabled; $en.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($en, 1)
    $en.Add_Click({
        $m = Get-SeqSel
        if ([bool]$this.IsChecked -and (([int]$m.Trigger -eq 5 -and [int]$m.TriggerVk -eq 0) -or $m.Steps.Count -eq 0)) {
            $this.IsChecked = $false; Show-Toast 'Set a trigger key and add at least one block first.' 'info'; return
        }
        $m.Enabled = [bool]$this.IsChecked; Save-SeqLibrary
    })
    [void](& $add 'Switched on' 'Runs whenever Macros is on in the General box. F8 stops it.' $en)
}

# ------------------------------------------------------------------ share tab
function Export-SeqCode($m) {
    $o = @{ Name = $m.Name; Trigger = $m.Trigger; TriggerVk = $m.TriggerVk; Mode = $m.Mode; Repeat = $m.Repeat; Steps = @($m.Steps) }
    $json = ConvertTo-Json -InputObject $o -Depth 5 -Compress
    $raw = [Text.Encoding]::UTF8.GetBytes($json)
    $ms = New-Object IO.MemoryStream
    $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress)
    $gz.Write($raw, 0, $raw.Length); $gz.Close()
    return 'KURO1:' + [Convert]::ToBase64String($ms.ToArray())
}

function Import-SeqCode([string]$Code) {
    $c = ($Code -replace '\s', '')
    if (-not $c.StartsWith('KURO1:')) { throw 'That is not a Kuro macro code. Codes start with KURO1:' }
    $b64 = $c.Substring(6)
    if ($b64.Length -gt 400000) { throw 'That code is too long.' }
    $bytes = [Convert]::FromBase64String($b64)
    $in = New-Object IO.MemoryStream (, $bytes)
    $gz = New-Object IO.Compression.GZipStream($in, [IO.Compression.CompressionMode]::Decompress)
    $out = New-Object IO.MemoryStream
    $buf = New-Object byte[] 8192
    while (($n = $gz.Read($buf, 0, $buf.Length)) -gt 0) { $out.Write($buf, 0, $n); if ($out.Length -gt 2MB) { throw 'That code is too big.' } }
    $gz.Close()
    $o = [Text.Encoding]::UTF8.GetString($out.ToArray()) | ConvertFrom-Json
    $m = ConvertTo-SeqMacro $o
    $m.Id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $m.Enabled = $false
    return $m
}

function Update-SeqShare {
    $ui = $Global:UI; $m = Get-SeqSel
    $ui.SeqShareSub.Text = $(if ($m) { "Send or add macros. Sharing: '" + $m.Name + "'" } else { 'Pick a macro in the Library to share it. You can still add shared ones.' })
    $ui.BtnSeqCopyCode.IsEnabled = [bool]$m
    $ui.BtnSeqSaveFile.IsEnabled = [bool]$m
}

function Add-SeqImported([string]$Text, [string]$From) {
    try {
        $m = Import-SeqCode $Text
        [void]$Global:Seq.Lib.Add($m)
        Save-SeqLibrary
        Select-SeqMacro ($Global:Seq.Lib.Count - 1)
        Show-MacTab 'Steps'
        Show-Toast ("Added '" + $m.Name + "' from $From with $($m.Steps.Count) blocks. It is switched off until you turn it on.")
    } catch { Show-Toast ('Could not add it: ' + $_.Exception.Message) 'error' }
}

function Save-SeqFile {
    $m = Get-SeqSel; if (-not $m) { return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Kuro macro (*.kuromacro)|*.kuromacro'
    $dlg.FileName = (($m.Name -replace '[\\/:*?"<>|]', '_') + '.kuromacro')
    if ($dlg.ShowDialog()) {
        try { [IO.File]::WriteAllText($dlg.FileName, (Export-SeqCode $m), $Global:Utf8NoBom); Show-Toast 'Saved. Send the file to a friend.' }
        catch { Show-Toast ('Could not save: ' + $_.Exception.Message) 'error' }
    }
}

function Open-SeqFile {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Kuro macro (*.kuromacro;*.txt)|*.kuromacro;*.txt'
    if ($dlg.ShowDialog()) {
        $fi = New-Object IO.FileInfo $dlg.FileName
        if ($fi.Length -gt 1MB) { Show-Toast 'That file is too big to be a macro.' 'error'; return }
        Add-SeqImported ([IO.File]::ReadAllText($dlg.FileName)) 'the file'
    }
}

function Get-SeqLink {
    $u = ([string]$Global:UI.SeqLinkIn.Text).Trim()
    $uri = $null
    if (-not [Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { Show-Toast 'Paste a full https:// link.' 'info'; return }
    Show-Busy 'Downloading macro...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 15 -MaximumRedirection 3 -ErrorAction Stop
        $txt = [string]$r.Content
        Hide-Busy
        if ($txt.Length -gt 1MB) { Show-Toast 'That download is too big to be a macro.' 'error'; return }
        Add-SeqImported $txt $uri.Host
        $Global:UI.SeqLinkIn.Text = ''
    } catch { Hide-Busy; Show-Toast ('Download failed: ' + $_.Exception.Message) 'error' }
}

function Copy-SeqMacro {
    $m = Get-SeqSel; if (-not $m) { Show-Toast 'Pick a macro first.' 'info'; return }
    $c = ConvertTo-SeqMacro @{ Name = ($m.Name + ' copy'); Trigger = $m.Trigger; TriggerVk = $m.TriggerVk; Mode = $m.Mode; Repeat = $m.Repeat; Steps = @($m.Steps | ForEach-Object { $_.Clone() }) }
    [void]$Global:Seq.Lib.Add($c)
    Save-SeqLibrary
    Select-SeqMacro ($Global:Seq.Lib.Count - 1)
    Show-Toast "Made a copy. It is switched off."
}

# ------------------------------------------------------------------ tabs + wiring
function Show-MacTab([string]$Name) {
    $ui = $Global:UI
    foreach ($t in @('Quick', 'Lib', 'Steps', 'Set', 'Share')) {
        $ui[('MacPanel' + $t)].Visibility = $(if ($t -eq $Name) { 'Visible' } else { 'Collapsed' })
        if ($t -eq $Name) { $ui[('MacTab' + $t)].IsChecked = $true }
    }
    switch ($Name) {
        'Lib' { Update-SeqLibrary }
        'Steps' { Update-SeqSteps }
        'Set' { Update-SeqSettings }
        'Share' { Update-SeqShare }
    }
    Fade-In $ui[('MacPanel' + $Name)]
}

function Update-SeqAll {
    Update-SeqLibrary
    Update-SeqSteps
    Update-SeqSettings
    Update-SeqShare
}

function Connect-SeqBuilder {
    $ui = $Global:UI
    Load-SeqLibrary
    if ($Global:Seq.Lib.Count -eq 0 -and -not $Global:CCH.Settings.SeqExampleDone) {
        # one harmless starter so the builder isn't empty: hold Q to spam the Space key (switched off)
        [void]$Global:Seq.Lib.Add((ConvertTo-SeqMacro @{ Name = 'Example: jump spam'; Trigger = 5; TriggerVk = 0x51; Mode = 2; Repeat = 3; Steps = @(
            @{ K = 11; Text = 'Hold Q to jump over and over' }, @{ K = 0; Vk = 0x20; Ms = 40 }, @{ K = 2; Ms = 120 }) }))
        $Global:CCH.Settings.SeqExampleDone = $true; Save-Settings
        Save-SeqLibrary
    }
    Build-SeqPalette
    foreach ($t in @('Quick', 'Lib', 'Steps', 'Set', 'Share')) {
        $ui[('MacTab' + $t)].Tag = $t
        $ui[('MacTab' + $t)].Add_Click({ Show-MacTab ([string]$this.Tag) })
    }
    $ui.BtnSeqNew.Add_Click({ New-SeqMacro })
    $ui.BtnSeqImportGo.Add_Click({ Show-MacTab 'Share' })
    $ui.BtnSeqRecord.Add_Click({ Invoke-SeqRecord })
    $ui.BtnSeqTest.Add_Click({ Invoke-SeqTest })
    $ui.BtnSeqUp.Add_Click({ Move-SeqBlock -1 })
    $ui.BtnSeqDown.Add_Click({ Move-SeqBlock 1 })
    $ui.BtnSeqCopy.Add_Click({ Copy-SeqBlock })
    $ui.BtnSeqRemove.Add_Click({ Remove-SeqBlock })
    $ui.BtnSeqCopyCode.Add_Click({ $m = Get-SeqSel; if ($m) { [Windows.Clipboard]::SetText((Export-SeqCode $m)); Show-Toast 'Code copied. Paste it to a friend.' } })
    $ui.BtnSeqSaveFile.Add_Click({ Save-SeqFile })
    $ui.BtnSeqOpenFile.Add_Click({ Open-SeqFile })
    $ui.BtnSeqPaste.Add_Click({ $t = ''; try { $t = [Windows.Clipboard]::GetText() } catch { }; if (-not $t) { Show-Toast 'Copy a KURO1: code first, then click Paste code.' 'info'; return }; Add-SeqImported $t 'the clipboard' })
    $ui.BtnSeqDownload.Add_Click({ Get-SeqLink })
    $ui.BtnSeqDup.Add_Click({ Copy-SeqMacro })
    $Global:CCH.Window.Add_Closing({ try { if ([KuroMacro]::Recording) { [void][KuroMacro]::RecStop() } } catch { } })
    if ($Global:Seq.Lib.Count -gt 0) { $Global:Seq.Sel = 0; $Global:Seq.Block = $(if ($Global:Seq.Lib[0].Steps.Count -gt 0) { 0 } else { -1 }) }
    Update-SeqAll
    Update-MacroCount
}

# ==================================================================================================
#  WINDOW HELPERS (stream-proof, click-through overlays, global hotkey) + PING page
# ==================================================================================================

$Global:KuroWinCs = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class KuroWin {
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowDisplayAffinity(IntPtr hWnd, uint affinity);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    public static bool KeyDown(int vk) { return (GetAsyncKeyState(vk) & 0x8000) != 0; }

    // 0x11 = WDA_EXCLUDEFROMCAPTURE (Windows 10 2004+), 0x01 = WDA_MONITOR (black box on older builds)
    public static string Protect(IntPtr h, bool on) {
        if (h == IntPtr.Zero) return "no window";
        if (!on) { SetWindowDisplayAffinity(h, 0); return "ok"; }
        if (SetWindowDisplayAffinity(h, 0x11)) return "ok";
        if (SetWindowDisplayAffinity(h, 0x01)) return "monitor";
        return "error " + Marshal.GetLastWin32Error();
    }

    public static void ClickThrough(IntPtr h) {
        // WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
        int ex = GetWindowLong(h, -20);
        SetWindowLong(h, -20, ex | 0x20 | 0x80000 | 0x80 | 0x8000000);
    }

    public static int ForegroundPid() {
        IntPtr h = GetForegroundWindow();
        if (h == IntPtr.Zero) return 0;
        uint pid; GetWindowThreadProcessId(h, out pid);
        return (int)pid;
    }

    // foreground window rectangle in physical pixels, or null if minimised
    public static int[] ForegroundRect() {
        IntPtr h = GetForegroundWindow();
        RECT r;
        if (h == IntPtr.Zero || IsIconic(h) || !GetWindowRect(h, out r)) return null;
        return new int[] { r.Left, r.Top, r.Right, r.Bottom };
    }
}
'@

function Initialize-KuroWin {
    if ('KuroWin' -as [type]) { return $true }
    try { Add-Type -TypeDefinition $Global:KuroWinCs -Language CSharp -ErrorAction Stop; return $true }
    catch { Write-Log "Window helper failed to load: $($_.Exception.Message)"; return $false }
}

function Get-Hwnd($Window) {
    try { return (New-Object Windows.Interop.WindowInteropHelper $Window).Handle } catch { return [IntPtr]::Zero }
}

# ------------------------------------------------------------------ stream proof
# Every Kuro window (main window, Game Bar, crosshair) registers here so the setting covers all of them.
$Global:KuroWindows = New-Object System.Collections.ArrayList

function Register-KuroWindow($Window) {
    if (-not $Global:KuroWindows.Contains($Window)) { [void]$Global:KuroWindows.Add($Window) }
    if ($Global:CCH.Settings.StreamProof -and $Global:CCH.Premium) { [void](Set-WindowProof $Window $true) }
}

function Set-WindowProof($Window, [bool]$On) {
    if (-not (Initialize-KuroWin)) { return 'helper missing' }
    $h = Get-Hwnd $Window
    if ($h -eq [IntPtr]::Zero) { return 'not shown yet' }
    return [KuroWin]::Protect($h, $On)
}

function Set-StreamProof([bool]$On) {
    if ($On -and -not (Confirm-Premium)) {
        foreach ($cb in @('SetStreamProof', 'GbStreamProof')) { if ($Global:UI[$cb]) { $Global:UI[$cb].IsChecked = $false } }
        Show-PremiumPrompt 'Stream proof'
        return
    }
    $Global:CCH.Settings.StreamProof = $On
    Save-Settings
    $results = @()
    foreach ($w in @($Global:KuroWindows)) { $results += (Set-WindowProof $w $On) }
    foreach ($cb in @('SetStreamProof', 'GbStreamProof')) { if ($Global:UI[$cb]) { $Global:UI[$cb].IsChecked = $On } }
    if (-not $On) { Show-Toast 'Stream proof off. Kuro shows up in captures again.'; return }
    if ($results -contains 'monitor') { Show-Toast 'Stream proof on, but this Windows version shows Kuro as a black box in captures instead of hiding it. Update Windows 10 to 2004 or newer for full hiding.' 'info' }
    elseif (@($results | Where-Object { $_ -like 'error*' }).Count) { Show-Toast ('Stream proof could not be applied: ' + (($results | Where-Object { $_ -like 'error*' }) -join ', ')) 'error' }
    else { Show-Toast 'Stream proof on. Kuro, its Game Bar and crosshair are hidden from screenshots, recordings and screen share.' }
}

# ------------------------------------------------------------------ PING page
$Global:DnsServers = @(
    @{ N = 'Cloudflare'; A = '1.1.1.1'; B = '1.0.0.1' }
    @{ N = 'Google';     A = '8.8.8.8'; B = '8.8.4.4' }
    @{ N = 'Quad9';      A = '9.9.9.9'; B = '149.112.112.112' }
    @{ N = 'OpenDNS';    A = '208.67.222.222'; B = '208.67.220.220' }
    @{ N = 'AdGuard';    A = '94.140.14.14'; B = '94.140.15.15' }
)
$Global:DnsTestNames = @('roblox.com', 'discord.com', 'google.com', 'microsoft.com', 'youtube.com', 'cloudflare.com')

function Get-PingTweaks { return @($Global:Tweaks | Where-Object { $_.Id -eq 'netthrottle' -or $_.Id -eq 'nagle' }) }

function Update-PingPage {
    $ui = $Global:UI
    $tw = Get-PingTweaks
    $thr = $tw | Where-Object { $_.Id -eq 'netthrottle' }
    $nag = $tw | Where-Object { $_.Id -eq 'nagle' }
    if ($thr) { $ui.PingThrottle.IsChecked = [bool]$thr.Applied }
    if ($nag) { $ui.PingNagle.IsChecked = [bool]$nag.Applied }
    $on = @($tw | Where-Object { $_.Applied }).Count
    $ui.PingStatus.Text = $(if ($on -eq 2) { 'Both applied.' } elseif ($on -eq 1) { 'One of two applied.' } else { 'Not applied.' })
    $qos = $null
    try { $qos = Get-NetQosPolicy -Name 'Kuro Roblox' -ErrorAction SilentlyContinue } catch { }
    $ui.PingQosTxt.Text = $(if ($qos) { 'Set up: Roblox packets are tagged as urgent (DSCP 46).' } else { "Tags Roblox's packets as urgent. Only helps if your router honours QoS tags." })
    $ui.BtnPingQos.Content = $(if ($qos) { 'Remove' } else { 'Set up' })
    $cur = Get-ActiveDns
    $ui.PingDnsTxt.Text = $(if ($cur) { 'Now using: ' + ($cur.Servers -join ', ') + $(if ($cur.Dhcp) { ' (from your router)' } else { '' }) } else { 'Quicker joining and loading. It does not change in-game ping.' })
}

function Set-PingTweak([string]$Id, [bool]$On) {
    $t = $Global:Tweaks | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $t) { return }
    if ($On -and $t.Premium -and -not (Confirm-Premium)) { Show-PremiumPrompt $t.Name; Update-PingPage; return }
    $r = Set-TweakState $t $On
    if (-not $r.Ok) { Show-Toast ('Failed: ' + $r.Msg) 'error' }
    try { Update-AllViews } catch { }
    Update-PingPage
}

function Get-ActiveDns {
    try {
        $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $route) { return $null }
        $idx = $route.InterfaceIndex
        $srv = @((Get-DnsClientServerAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
        $guid = (Get-NetAdapter -InterfaceIndex $idx -ErrorAction Stop).InterfaceGuid
        $static = [string](Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid" -Name NameServer -ErrorAction SilentlyContinue).NameServer
        return @{ Index = $idx; Servers = $srv; Dhcp = [string]::IsNullOrWhiteSpace($static) }
    } catch { return $null }
}

function Measure-DnsServer([string]$Ip) {
    $times = @()
    foreach ($n in $Global:DnsTestNames) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try { $null = Resolve-DnsName -Name $n -Server $Ip -Type A -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop; $times += $sw.Elapsed.TotalMilliseconds }
        catch { $times += 2000 }
        Pump-UI
    }
    $sorted = @($times | Sort-Object)
    return [double]$sorted[[int][math]::Floor($sorted.Count / 2)]
}

function Invoke-DnsFind {
    $ui = $Global:UI
    $cur = Get-ActiveDns
    $list = @($Global:DnsServers)
    if ($cur -and $cur.Servers.Count -gt 0 -and -not ($Global:DnsServers | Where-Object { $_.A -eq $cur.Servers[0] })) {
        $list += @{ N = 'Your current DNS'; A = $cur.Servers[0]; B = $(if ($cur.Servers.Count -gt 1) { $cur.Servers[1] } else { '' }); Current = $true }
    }
    Show-Busy 'Testing DNS servers...' 'Asks each one for a few common addresses'
    $res = @()
    $i = 0
    foreach ($d in $list) {
        $i++; Set-BusyText ("Testing {0} ({1}/{2})..." -f $d.N, $i, $list.Count)
        $res += @{ D = $d; Ms = (Measure-DnsServer $d.A) }
    }
    Hide-Busy
    $res = @($res | Sort-Object { $_.Ms })
    $ui.PingDnsList.Children.Clear()
    $rank = 0
    foreach ($r in $res) {
        $rank++
        $row = New-MacroRow ("{0}. {1}  -  {2}" -f $rank, $r.D.N, $(if ($r.Ms -ge 2000) { 'no answer' } else { ('{0:0} ms' -f $r.Ms) })) ($r.D.A + $(if ($r.D.B) { ', ' + $r.D.B } else { '' })) ''
        if (-not $r.D.Current -and $r.Ms -lt 2000) {
            $b = New-Object Windows.Controls.Button
            $b.Style = $Global:CCH.Window.Resources[$(if ($rank -eq 1) { 'AccentBtn' } else { 'GhostBtn' })]
            $b.Content = 'Use this'; $b.Padding = New-Object Windows.Thickness 14, 7, 14, 7; $b.VerticalAlignment = 'Center'
            $b.Tag = $r.D
            [Windows.Controls.Grid]::SetColumn($b, 1)
            $b.Add_Click({ Set-Dns $this.Tag })
            [void]$row.Child.Children.Add($b)
        }
        [void]$ui.PingDnsList.Children.Add($row)
    }
    $ui.PingDnsCard.Visibility = 'Visible'
}

function Set-Dns($D) {
    $cur = Get-ActiveDns
    if (-not $cur) { Show-Toast 'Could not find your active network adapter.' 'error'; return }
    if (-not $Global:CCH.Settings.DnsBackup) {
        $Global:CCH.Settings.DnsBackup = @{ Index = $cur.Index; Servers = @($cur.Servers); Dhcp = $cur.Dhcp }
        Save-Settings
    }
    try {
        $addr = @($D.A); if ($D.B) { $addr += $D.B }
        Set-DnsClientServerAddress -InterfaceIndex $cur.Index -ServerAddresses $addr -ErrorAction Stop
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Log "DNS set to $($D.N) ($($addr -join ', ')) on interface $($cur.Index)"
        Show-Toast "Now using $($D.N) DNS."
    } catch { Show-Toast ('Could not change DNS: ' + $_.Exception.Message) 'error' }
    Update-PingPage
}

function Restore-Dns {
    $b = $Global:CCH.Settings.DnsBackup
    if (-not $b) { Show-Toast 'Kuro has not changed your DNS.' 'info'; return }
    try {
        $idx = [int]$b.Index
        if ([bool]$b.Dhcp -or @($b.Servers).Count -eq 0) { Set-DnsClientServerAddress -InterfaceIndex $idx -ResetServerAddresses -ErrorAction Stop }
        else { Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses @($b.Servers) -ErrorAction Stop }
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        $Global:CCH.Settings.DnsBackup = $null; Save-Settings
        Show-Toast 'DNS is back to how it was.'
    } catch { Show-Toast ('Could not restore DNS: ' + $_.Exception.Message) 'error' }
    Update-PingPage
}

function Switch-RobloxQos {
    try {
        $q = Get-NetQosPolicy -Name 'Kuro Roblox' -ErrorAction SilentlyContinue
        if ($q) { Remove-NetQosPolicy -Name 'Kuro Roblox' -Confirm:$false -ErrorAction Stop; Show-Toast 'Roblox QoS rule removed.' }
        else {
            New-NetQosPolicy -Name 'Kuro Roblox' -AppPathNameMatchCondition 'RobloxPlayerBeta.exe' -DSCPAction 46 -NetworkProfile All -ErrorAction Stop | Out-Null
            Show-Toast 'Roblox traffic is now tagged as urgent (DSCP 46).'
        }
    } catch { Show-Toast ('QoS change failed: ' + $_.Exception.Message) 'error' }
    Update-PingPage
}

function Connect-Ping {
    $ui = $Global:UI
    $ui.PingThrottle.Add_Click({ Set-PingTweak 'netthrottle' ([bool]$Global:UI.PingThrottle.IsChecked) })
    $ui.PingNagle.Add_Click({ Set-PingTweak 'nagle' ([bool]$Global:UI.PingNagle.IsChecked) })
    $ui.BtnPingApply.Add_Click({ Set-PingTweak 'netthrottle' $true; Set-PingTweak 'nagle' $true })
    $ui.BtnPingUndo.Add_Click({ Set-PingTweak 'netthrottle' $false; Set-PingTweak 'nagle' $false })
    $ui.BtnPingQos.Add_Click({ Switch-RobloxQos })
    $ui.BtnPingDns.Add_Click({ Invoke-DnsFind })
    $ui.BtnPingDnsReset.Add_Click({ Restore-Dns })
}

# ==================================================================================================
#  CURSOR / CROSSHAIR BUILDER  - layered shapes, on-screen crosshair overlay, Roblox cursor files.
#  Roblox cursor PNGs live in Versions\version-*\content\textures\Cursors\KeyboardMouse
#  (ArrowCursor.png, ArrowFarCursor.png; around 64x64 recommended). Originals are backed up first.
# ==================================================================================================

$Global:CrossFile = Join-Path $Global:DataDir 'cursor.json'
$Global:CrossBackupDir = Join-Path $Global:DataDir 'cursor-backup'
$Global:CrossShapes = @('Dot', 'Ring', 'Square', 'Plus', 'X', 'Split', 'Diamond', 'Triangle', 'Bar', 'Arrow', 'Oval', 'Star', 'Arc')
$Global:CrossColors = @('#FFFFFF', '#000000', '#FF3B5C', '#E86A9C', '#FFB020', '#FFE14D', '#3DDC84', '#22D3EE', '#3B82F6', '#A855F7')
$Global:CrossMax = 8
$Global:Cross = @{ Layers = (New-Object System.Collections.ArrayList); Sel = 0; Tab = 0; Overlay = $null; Timer = $null; Updating = $false }

function New-CrossLayer([int]$Shape = 3) {
    return @{ Shape = $Shape; Size = 7.0; Thick = 2.0; Round = 0.0; Gap = 2.0; Rotate = 0.0; OffX = 0.0; OffY = 0.0; Mirror = 0
              Color = '#FFFFFF'; Opacity = 100.0; Outline = 1.0; OutColor = '#000000'; Glow = 0.0 }
}

function ConvertTo-CrossLayer($o) {
    $l = New-CrossLayer
    foreach ($k in @($l.Keys)) {
        $v = $null
        if ($o -is [hashtable]) { if ($o.ContainsKey($k)) { $v = $o[$k] } } elseif ($o.PSObject.Properties[$k]) { $v = $o.$k }
        if ($null -eq $v) { continue }
        if ($k -eq 'Color' -or $k -eq 'OutColor') { if ([string]$v -match '^#[0-9A-Fa-f]{6}$') { $l[$k] = [string]$v } }
        elseif ($k -eq 'Shape') { $l[$k] = Get-IntIn $v 0 ($Global:CrossShapes.Count - 1) 3 }
        elseif ($k -eq 'Mirror') { $l[$k] = Get-IntIn $v 0 3 0 }
        else { $d = 0.0; if ([double]::TryParse([string]$v, [ref]$d)) { $l[$k] = $d } }
    }
    $l.Size = [math]::Max(0.5, [math]::Min(32, $l.Size)); $l.Thick = [math]::Max(0.5, [math]::Min(12, $l.Thick))
    $l.Round = [math]::Max(0, [math]::Min(100, $l.Round)); $l.Gap = [math]::Max(0, [math]::Min(24, $l.Gap))
    $l.Rotate = [math]::Max(-180, [math]::Min(180, $l.Rotate)); $l.OffX = [math]::Max(-28, [math]::Min(28, $l.OffX)); $l.OffY = [math]::Max(-28, [math]::Min(28, $l.OffY))
    $l.Opacity = [math]::Max(5, [math]::Min(100, $l.Opacity)); $l.Outline = [math]::Max(0, [math]::Min(4, $l.Outline)); $l.Glow = [math]::Max(0, [math]::Min(12, $l.Glow))
    return $l
}

function Load-Cross {
    $Global:Cross.Layers.Clear()
    if (Test-Path $Global:CrossFile) {
        # assign first: in Windows PowerShell 5.1 ConvertFrom-Json emits a JSON array as ONE object
        try { $arr = [IO.File]::ReadAllText($Global:CrossFile) | ConvertFrom-Json; foreach ($o in @($arr)) { if ($o -and $Global:Cross.Layers.Count -lt $Global:CrossMax) { [void]$Global:Cross.Layers.Add((ConvertTo-CrossLayer $o)) } } } catch { }
    }
    if ($Global:Cross.Layers.Count -eq 0) {
        [void]$Global:Cross.Layers.Add((New-CrossLayer 3))
        $dot = New-CrossLayer 0; $dot.Size = 2; $dot.Color = '#E86A9C'; $dot.Outline = 0
        [void]$Global:Cross.Layers.Add($dot)
    }
    $Global:Cross.Sel = 0
}

function Save-Cross {
    try {
        $json = ConvertTo-Json -InputObject @($Global:Cross.Layers) -Depth 4
        [IO.File]::WriteAllText($Global:CrossFile, $json, $Global:Utf8NoBom)
    } catch { Write-Log "Cursor could not be saved: $($_.Exception.Message)" }
}

# ------------------------------------------------------------------ geometry
function New-RectGeo([double]$X, [double]$Y, [double]$W, [double]$H, [double]$R) {
    $g = New-Object Windows.Media.RectangleGeometry (New-Object Windows.Rect $X, $Y, $W, $H)
    $g.RadiusX = $R; $g.RadiusY = $R
    return $g
}

function New-PolyGeo([double[]]$Pts, [bool]$Closed = $true) {
    $f = New-Object Windows.Media.PathFigure
    $f.StartPoint = New-Object Windows.Point $Pts[0], $Pts[1]
    for ($i = 2; $i -lt $Pts.Count; $i += 2) { [void]$f.Segments.Add((New-Object Windows.Media.LineSegment (New-Object Windows.Point $Pts[$i], $Pts[$i + 1]), $true)) }
    $f.IsClosed = $Closed; $f.IsFilled = $Closed
    $g = New-Object Windows.Media.PathGeometry; [void]$g.Figures.Add($f)
    return $g
}

# returns @{ Geo; Stroke } - Stroke = $true for outline-only shapes (ring, arc)
function Get-CrossGeometry($L) {
    $s = [double]$L.Size; $t = [double]$L.Thick; $gap = [double]$L.Gap
    $rr = [math]::Max(0.0, [double]$L.Round) / 100.0
    $grp = New-Object Windows.Media.GeometryGroup
    $grp.FillRule = 'Nonzero'
    $stroke = $false
    switch ([int]$L.Shape) {
        0 { [void]$grp.Children.Add((New-Object Windows.Media.EllipseGeometry (New-Object Windows.Point 0, 0), ($s / 2), ($s / 2))) }
        1 { [void]$grp.Children.Add((New-Object Windows.Media.EllipseGeometry (New-Object Windows.Point 0, 0), $s, $s)); $stroke = $true }
        2 { [void]$grp.Children.Add((New-RectGeo (-$s / 2) (-$s / 2) $s $s ($rr * $s / 2))) }
        { $_ -eq 3 -or $_ -eq 4 -or $_ -eq 5 } {
            if ([int]$L.Shape -eq 5) { $gap = [math]::Max($gap, $s * 0.6) }
            $r = $rr * $t / 2
            [void]$grp.Children.Add((New-RectGeo $gap (-$t / 2) $s $t $r))
            [void]$grp.Children.Add((New-RectGeo (-$gap - $s) (-$t / 2) $s $t $r))
            [void]$grp.Children.Add((New-RectGeo (-$t / 2) $gap $t $s $r))
            [void]$grp.Children.Add((New-RectGeo (-$t / 2) (-$gap - $s) $t $s $r))
            if ($gap -le 0) { [void]$grp.Children.Add((New-RectGeo (-$t / 2) (-$t / 2) $t $t 0)) }
            if ([int]$L.Shape -eq 4) { $grp.Transform = New-Object Windows.Media.RotateTransform 45 }
        }
        6 { $g = New-RectGeo (-$s / 2) (-$s / 2) $s $s ($rr * $s / 2); $g.Transform = New-Object Windows.Media.RotateTransform 45; [void]$grp.Children.Add($g) }
        7 { $h = $s * 0.866; [void]$grp.Children.Add((New-PolyGeo @(0, (-$h * 2 / 3), ($s / 2), ($h / 3), (-$s / 2), ($h / 3)))) }
        8 { [void]$grp.Children.Add((New-RectGeo (-$s) (-$t / 2) ($s * 2) $t ($rr * $t / 2))) }
        9 {
            $k = $s / 10.0
            $pts = @(0, 0, 0, 16, 4, 12, 7, 19, 9, 18, 6, 11, 11, 11) | ForEach-Object { [double]$_ * $k }
            [void]$grp.Children.Add((New-PolyGeo $pts))
        }
        10 { [void]$grp.Children.Add((New-Object Windows.Media.EllipseGeometry (New-Object Windows.Point 0, 0), ($s / 2), ($s * 0.32))) }
        11 {
            $pts = @()
            for ($i = 0; $i -lt 10; $i++) {
                $a = (-90 + $i * 36) * [math]::PI / 180; $rad = $(if ($i % 2 -eq 0) { $s / 2 } else { $s / 4.6 })
                $pts += ($rad * [math]::Cos($a)); $pts += ($rad * [math]::Sin($a))
            }
            [void]$grp.Children.Add((New-PolyGeo ([double[]]$pts)))
        }
        12 {
            $f = New-Object Windows.Media.PathFigure
            $a0 = 210 * [math]::PI / 180; $a1 = 330 * [math]::PI / 180
            $f.StartPoint = New-Object Windows.Point ($s * [math]::Cos($a0)), ($s * [math]::Sin($a0))
            [void]$f.Segments.Add((New-Object Windows.Media.ArcSegment (New-Object Windows.Point ($s * [math]::Cos($a1)), ($s * [math]::Sin($a1))), (New-Object Windows.Size $s, $s), 0, $false, ([Windows.Media.SweepDirection]::Clockwise), $true))
            $f.IsFilled = $false
            $pg = New-Object Windows.Media.PathGeometry; [void]$pg.Figures.Add($f)
            [void]$grp.Children.Add($pg); $stroke = $true
        }
    }
    return @{ Geo = $grp; Stroke = $stroke }
}

function New-CrossBrush([string]$Hex, [double]$Opacity = 100) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb([byte](255 * $Opacity / 100.0), $c.R, $c.G, $c.B))
    $b.Freeze(); return $b
}

# draws all layers into a Canvas whose (0,0) is the crosshair centre; caller positions the canvas
function New-CrossVisual($Layers, [double]$Scale = 1.0) {
    $root = New-Object Windows.Controls.Canvas
    foreach ($L in $Layers) {
        $copies = @(, @(1, 1))   # leading comma keeps it a list of pairs (plain @(@(1,1)) flattens to 1,1)
        switch ([int]$L.Mirror) { 1 { $copies += , @(-1, 1) } 2 { $copies += , @(1, -1) } 3 { $copies += , @(-1, 1); $copies += , @(1, -1); $copies += , @(-1, -1) } }
        foreach ($m in $copies) {
            $info = Get-CrossGeometry $L
            $tg = New-Object Windows.Media.TransformGroup
            [void]$tg.Children.Add((New-Object Windows.Media.RotateTransform ([double]$L.Rotate)))
            [void]$tg.Children.Add((New-Object Windows.Media.TranslateTransform ([double]$L.OffX), ([double]$L.OffY)))
            [void]$tg.Children.Add((New-Object Windows.Media.ScaleTransform ($m[0] * $Scale), ($m[1] * $Scale)))
            $fill = New-CrossBrush $L.Color $L.Opacity
            if ([double]$L.Outline -gt 0) {
                $o = New-Object Windows.Shapes.Path
                $o.Data = $info.Geo; $o.RenderTransform = $tg
                $o.Stroke = New-CrossBrush $L.OutColor $L.Opacity
                $o.StrokeLineJoin = 'Round'; $o.StrokeStartLineCap = 'Round'; $o.StrokeEndLineCap = 'Round'
                $o.StrokeThickness = $(if ($info.Stroke) { [double]$L.Thick + 2 * [double]$L.Outline } else { 2 * [double]$L.Outline })
                [void]$root.Children.Add($o)
            }
            $p = New-Object Windows.Shapes.Path
            $p.Data = $info.Geo; $p.RenderTransform = $tg
            if ($info.Stroke) { $p.Stroke = $fill; $p.StrokeThickness = [double]$L.Thick; $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round' }
            else { $p.Fill = $fill }
            if ([double]$L.Glow -gt 0) {
                $fx = New-Object Windows.Media.Effects.DropShadowEffect
                $fx.Color = [Windows.Media.ColorConverter]::ConvertFromString($L.Color); $fx.ShadowDepth = 0; $fx.BlurRadius = [double]$L.Glow * $Scale; $fx.Opacity = 0.9
                $p.Effect = $fx
            }
            [void]$root.Children.Add($p)
        }
    }
    return $root
}

# 64x64 transparent PNG, crosshair centred (Roblox draws its cursor images centred on the pointer)
function Save-CrossPng([string]$Path, [int]$Px = 64) {
    $host2 = New-Object Windows.Controls.Canvas
    $host2.Width = $Px; $host2.Height = $Px
    $v = New-CrossVisual $Global:Cross.Layers 1.0
    [Windows.Controls.Canvas]::SetLeft($v, $Px / 2); [Windows.Controls.Canvas]::SetTop($v, $Px / 2)
    [void]$host2.Children.Add($v)
    $host2.Measure((New-Object Windows.Size $Px, $Px)); $host2.Arrange((New-Object Windows.Rect 0, 0, $Px, $Px)); $host2.UpdateLayout()
    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $Px, $Px, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($host2)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    [void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create($Path)
    try { $enc.Save($fs) } finally { $fs.Close() }
}

# ------------------------------------------------------------------ Roblox cursor files
function Get-RbxCursorTargets {
    $out = @()
    foreach ($d in Get-RobloxVersionDirs) {
        foreach ($rel in @('content\textures\Cursors\KeyboardMouse', 'content\textures\KeyboardMouse\Cursors')) {
            $dir = Join-Path $d.FullName $rel
            if (-not (Test-Path $dir)) { continue }
            foreach ($n in @('ArrowCursor.png', 'ArrowFarCursor.png')) {
                $f = Join-Path $dir $n
                if (Test-Path $f) { $out += @{ Ver = $d.Name; File = $f; Name = $n } }
            }
        }
        if ($Global:CCH.Settings.RbxCursorLock) {
            $lk = Join-Path $d.FullName 'content\textures\MouseLockedCursor.png'
            if (Test-Path $lk) { $out += @{ Ver = $d.Name; File = $lk; Name = 'MouseLockedCursor.png' } }
        }
    }
    return $out
}

function Invoke-RbxCursorApply([bool]$Quiet = $false) {
    $targets = @(Get-RbxCursorTargets)
    if ($targets.Count -eq 0) { if (-not $Quiet) { Show-Toast "Roblox's cursor files were not found. Is Roblox installed?" 'error' }; return $false }
    $png = Join-Path $Global:DataDir 'kuro-cursor.png'
    try { Save-CrossPng $png 64 } catch { if (-not $Quiet) { Show-Toast ('Could not draw the cursor: ' + $_.Exception.Message) 'error' }; return $false }
    $n = 0
    foreach ($t in $targets) {
        try {
            $bdir = Join-Path $Global:CrossBackupDir $t.Ver
            if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Force -Path $bdir | Out-Null }
            $bak = Join-Path $bdir $t.Name
            if (-not (Test-Path $bak)) { Copy-Item -LiteralPath $t.File -Destination $bak -Force -ErrorAction Stop }
            Copy-Item -LiteralPath $png -Destination $t.File -Force -ErrorAction Stop
            $n++
        } catch { Write-Log "Cursor write failed for $($t.File): $($_.Exception.Message)" }
    }
    $Global:CCH.Settings.RbxCursor = $true; Save-Settings
    if (-not $Quiet) { Show-Toast "Cursor saved into Roblox ($n files). Restart Roblox to see it." }
    return $true
}

function Restore-RbxCursor {
    $n = 0
    foreach ($d in Get-RobloxVersionDirs) {
        $bdir = Join-Path $Global:CrossBackupDir $d.Name
        if (-not (Test-Path $bdir)) { continue }
        foreach ($t in @(Get-RbxCursorTargets | Where-Object { $_.Ver -eq $d.Name })) {
            $bak = Join-Path $bdir $t.Name
            if (Test-Path $bak) { try { Copy-Item -LiteralPath $bak -Destination $t.File -Force -ErrorAction Stop; $n++ } catch { } }
        }
        $lk = Join-Path $bdir 'MouseLockedCursor.png'
        $lkT = Join-Path $d.FullName 'content\textures\MouseLockedCursor.png'
        if ((Test-Path $lk) -and (Test-Path $lkT)) { try { Copy-Item -LiteralPath $lk -Destination $lkT -Force } catch { } }
    }
    $Global:CCH.Settings.RbxCursor = $false; Save-Settings
    Show-Toast "Roblox's own cursor is back ($n files). Restart Roblox to see it."
}

# re-apply after a Roblox update installed a fresh version folder (no backup for it yet)
function Sync-RbxCursor {
    if (-not $Global:CCH.Settings.RbxCursor) { return }
    foreach ($d in Get-RobloxVersionDirs) {
        if (-not (Test-Path (Join-Path $Global:CrossBackupDir $d.Name))) { [void](Invoke-RbxCursorApply $true); Write-Log 'Re-applied Kuro cursor after a Roblox update.'; return }
    }
}

# ------------------------------------------------------------------ on-screen crosshair overlay
function Show-CrossOverlay([bool]$On, [bool]$Persist = $true) {
    $c = $Global:Cross
    if (-not $On) {
        if ($c.Timer) { $c.Timer.Stop() }
        if ($c.Overlay) { $c.Overlay.Close(); $c.Overlay = $null }
        if ($Persist) { $Global:CCH.Settings.CrossShow = $false; Save-Settings }
        if ($Global:UI.CrossShow) { $Global:UI.CrossShow.IsChecked = $false }
        return
    }
    if (-not (Initialize-KuroWin)) { Show-Toast 'The crosshair overlay could not start.' 'error'; return }
    if (-not $c.Overlay) {
        $w = New-Object Windows.Window
        $w.WindowStyle = 'None'; $w.AllowsTransparency = $true; $w.Background = [Windows.Media.Brushes]::Transparent
        $w.Topmost = $true; $w.ShowInTaskbar = $false; $w.ShowActivated = $false; $w.ResizeMode = 'NoResize'
        $w.Width = 160; $w.Height = 160; $w.Title = 'Kuro crosshair'
        $w.Add_SourceInitialized({ param($s, $e) try { [KuroWin]::ClickThrough((Get-Hwnd $s)) } catch { } })
        $c.Overlay = $w
        Update-CrossOverlay
        $w.Show()
        Register-KuroWindow $w
    }
    if (-not $c.Timer) {
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromMilliseconds(500)
        $t.Add_Tick({ try { Move-CrossOverlay } catch { } })
        $c.Timer = $t
    }
    $c.Timer.Start()
    Move-CrossOverlay
    if ($Persist) { $Global:CCH.Settings.CrossShow = $true; Save-Settings }
    if ($Global:UI.CrossShow) { $Global:UI.CrossShow.IsChecked = $true }
}

function Update-CrossOverlay {
    $w = $Global:Cross.Overlay; if (-not $w) { return }
    $cv = New-Object Windows.Controls.Canvas
    $v = New-CrossVisual $Global:Cross.Layers 1.0
    [Windows.Controls.Canvas]::SetLeft($v, 80); [Windows.Controls.Canvas]::SetTop($v, 80)
    [void]$cv.Children.Add($v)
    $w.Content = $cv
}

# centre on the game window when one is in front, otherwise on the main screen
function Move-CrossOverlay {
    $w = $Global:Cross.Overlay; if (-not $w) { return }
    $src = [Windows.PresentationSource]::FromVisual($Global:CCH.Window)
    $sx = 1.0; $sy = 1.0
    if ($src -and $src.CompositionTarget) { $sx = $src.CompositionTarget.TransformToDevice.M11; $sy = $src.CompositionTarget.TransformToDevice.M22 }
    $cx = [Windows.SystemParameters]::PrimaryScreenWidth / 2; $cy = [Windows.SystemParameters]::PrimaryScreenHeight / 2
    if ($Global:GameBar -and $Global:GameBar.Game) {
        $r = [KuroWin]::ForegroundRect()
        if ($r) { $cx = (($r[0] + $r[2]) / 2.0) / $sx; $cy = (($r[1] + $r[3]) / 2.0) / $sy }
    }
    $w.Left = $cx - 80; $w.Top = $cy - 80
}

# ------------------------------------------------------------------ builder page
function Update-CrossPreview {
    $ui = $Global:UI
    $ui.CrossCanvas.Children.Clear()
    $v = New-CrossVisual $Global:Cross.Layers 4.0
    [Windows.Controls.Canvas]::SetLeft($v, $ui.CrossCanvas.Width / 2); [Windows.Controls.Canvas]::SetTop($v, $ui.CrossCanvas.Height / 2)
    [void]$ui.CrossCanvas.Children.Add($v)
    Update-CrossOverlay
}

function Update-CrossLayers {
    $ui = $Global:UI
    $ui.CrossLayerList.Children.Clear()
    for ($i = 0; $i -lt $Global:Cross.Layers.Count; $i++) {
        $L = $Global:Cross.Layers[$i]
        $b = New-Object Windows.Controls.RadioButton
        $b.Style = $Global:CCH.Window.Resources['Seg']; $b.GroupName = 'CrossLayers'
        $b.Content = ("{0} {1}" -f ($i + 1), $Global:CrossShapes[[int]$L.Shape]); $b.Tag = $i
        $b.IsChecked = ($i -eq $Global:Cross.Sel)
        $b.Add_Click({ $Global:Cross.Sel = [int]$this.Tag; Update-CrossEditor })
        [void]$ui.CrossLayerList.Children.Add($b)
    }
    $ui.CrossLayerCount.Text = "$($Global:Cross.Sel + 1) of $($Global:Cross.Layers.Count) layers"
    $ui.BtnCrossAdd.IsEnabled = ($Global:Cross.Layers.Count -lt $Global:CrossMax)
    $ui.BtnCrossDel.IsEnabled = ($Global:Cross.Layers.Count -gt 1)
}

function Set-CrossField([string]$F, $V) {
    $L = $Global:Cross.Layers[$Global:Cross.Sel]
    $L[$F] = $V
    $Global:Cross.Layers[$Global:Cross.Sel] = ConvertTo-CrossLayer $L
    Save-Cross
    Update-CrossPreview
}

function Add-CrossSlider([string]$Title, [string]$Field, [double]$Min, [double]$Max, [string]$Fmt, [double]$Step = 0.1) {
    $L = $Global:Cross.Layers[$Global:Cross.Sel]
    $s = New-MacroSlider $Min $Max
    $s.Slider.Width = 260
    $s.Slider.Value = [double]$L[$Field]
    $s.Text.Text = ($Fmt -f [double]$L[$Field])
    $s.Slider.Tag = "$Field|$Fmt|$Step"
    $s.Slider.Add_ValueChanged({
        if ($Global:Cross.Updating) { return }
        $p = ([string]$this.Tag).Split('|'); $st = [double]$p[2]
        $v = [math]::Round($this.Value / $st) * $st
        $this.Parent.Children[1].Text = ($p[1] -f $v)
        Set-CrossField $p[0] $v
    })
    $row = New-MacroRow $Title '' ''
    $row.Padding = New-Object Windows.Thickness 0, 7, 0, 7
    [void]$row.Child.Children.Add($s.Root)
    [void]$Global:UI.CrossFields.Children.Add($row)
}

function Add-CrossSwatches([string]$Title, [string]$Field) {
    $L = $Global:Cross.Layers[$Global:Cross.Sel]
    $wp = New-Object Windows.Controls.WrapPanel; $wp.MaxWidth = 380; $wp.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($wp, 1)
    foreach ($hex in $Global:CrossColors) {
        $b = New-Object Windows.Controls.Button
        $b.Width = 26; $b.Height = 26; $b.Margin = New-Object Windows.Thickness 0, 0, 6, 6; $b.Cursor = [Windows.Input.Cursors]::Hand
        $b.Template = [Windows.Markup.XamlReader]::Parse('<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button"><Border CornerRadius="7" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="2"/></ControlTemplate>')
        $b.Background = New-CrossBrush $hex
        if ([string]$L[$Field] -eq $hex) { $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'AccentBrush') } else { $b.BorderBrush = New-CrossBrush '#FFFFFF' 25 }
        $b.Tag = "$Field|$hex"
        $b.Add_Click({ $p = ([string]$this.Tag).Split('|'); Set-CrossField $p[0] $p[1]; Update-CrossEditor })
        [void]$wp.Children.Add($b)
    }
    $hexBox = New-Object Windows.Controls.TextBox
    $hexBox.Style = $Global:CCH.Window.Resources['Input']; $hexBox.Width = 96; $hexBox.FontFamily = New-Object Windows.Media.FontFamily 'Consolas'
    $hexBox.Text = [string]$L[$Field]; $hexBox.Tag = $Field; $hexBox.Margin = New-Object Windows.Thickness 0, 0, 0, 6
    $hexBox.Add_LostKeyboardFocus({ $v = ([string]$this.Text).Trim(); if ($v -notmatch '^#') { $v = '#' + $v }; if ($v -match '^#[0-9A-Fa-f]{6}$') { Set-CrossField ([string]$this.Tag) $v.ToUpper() } else { Show-Toast 'Use a colour like #FF3B5C.' 'info' }; Update-CrossEditor })
    $hexBox.Add_KeyDown({ if ($_.Key -eq 'Return') { [System.Windows.Input.Keyboard]::ClearFocus() } })
    [void]$wp.Children.Add($hexBox)
    $row = New-MacroRow $Title 'Pick a colour or type a hex code.' ''
    [void]$row.Child.Children.Add($wp)
    [void]$Global:UI.CrossFields.Children.Add($row)
}

function Update-CrossEditor {
    $ui = $Global:UI
    $Global:Cross.Updating = $true
    Update-CrossLayers
    $L = $Global:Cross.Layers[$Global:Cross.Sel]
    $ui.CrossFields.Children.Clear()
    $ui.CrossShapeGrid.Visibility = $(if ($Global:Cross.Tab -eq 0) { 'Visible' } else { 'Collapsed' })
    for ($i = 0; $i -lt $ui.CrossShapeGrid.Children.Count; $i++) {
        $b = $ui.CrossShapeGrid.Children[$i]
        if ($i -eq [int]$L.Shape) { $b.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty, 'AccentBrush'); $b.SetResourceReference([Windows.Controls.Control]::BackgroundProperty, 'AccentSoftBrush') }
        else { $b.ClearValue([Windows.Controls.Control]::BorderBrushProperty); $b.ClearValue([Windows.Controls.Control]::BackgroundProperty) }
    }
    switch ($Global:Cross.Tab) {
        0 {
            Add-CrossSlider 'Size' 'Size' 0.5 32 '{0:0.0}' 0.5
            if (@(1, 3, 4, 5, 8, 12) -contains [int]$L.Shape) { Add-CrossSlider 'Thickness' 'Thick' 0.5 12 '{0:0.0}' 0.1 }
            if (@(2, 3, 4, 5, 6, 8) -contains [int]$L.Shape) { Add-CrossSlider 'Roundness' 'Round' 0 100 '{0:0} %' 1 }
            if (@(3, 4, 5) -contains [int]$L.Shape) { Add-CrossSlider 'Gap' 'Gap' 0 24 '{0:0.0}' 0.5 }
            $seg = New-SeqSegs @('Off', 'Sides', 'Up/down', 'Both') ([int]$L.Mirror) { Set-CrossField 'Mirror' ([int]$this.Tag) }
            $row = New-MacroRow 'Mirror' 'Copies the layer to the other side. Use with left/right or up/down.' ''; [void]$row.Child.Children.Add($seg); [void]$ui.CrossFields.Children.Add($row)
            Add-CrossSlider 'Rotate' 'Rotate' -180 180 '{0:0} deg' 1
            Add-CrossSlider 'Left / right' 'OffX' -28 28 '{0:0.0}' 0.5
            Add-CrossSlider 'Up / down' 'OffY' -28 28 '{0:0.0}' 0.5
        }
        1 {
            Add-CrossSwatches 'Colour' 'Color'
            Add-CrossSlider 'Opacity' 'Opacity' 5 100 '{0:0} %' 1
        }
        2 {
            Add-CrossSlider 'Outline' 'Outline' 0 4 '{0:0.0}' 0.5
            Add-CrossSwatches 'Outline colour' 'OutColor'
            Add-CrossSlider 'Glow' 'Glow' 0 12 '{0:0}' 1
        }
    }
    $Global:Cross.Updating = $false
    Update-CrossPreview
}

function Build-CrossShapes {
    $ui = $Global:UI
    $ui.CrossShapeGrid.Children.Clear()
    for ($i = 0; $i -lt $Global:CrossShapes.Count; $i++) {
        $b = New-Object Windows.Controls.Button
        $b.Style = $Global:CCH.Window.Resources['GhostBtn']
        $b.Margin = New-Object Windows.Thickness 0, 0, 6, 6; $b.Padding = New-Object Windows.Thickness 4, 8, 4, 6
        $sp = New-Object Windows.Controls.StackPanel
        $cv = New-Object Windows.Controls.Canvas; $cv.Width = 28; $cv.Height = 26
        $L = New-CrossLayer $i; $L.Size = $(if ($i -eq 1 -or $i -eq 12) { 4.5 } elseif ($i -eq 9) { 7 } else { 7 }); $L.Thick = 1.6; $L.Gap = $(if ($i -eq 5) { 3 } else { 1 }); $L.Outline = 0
        $L.Size = $(if (@(3, 4, 5, 8) -contains $i) { 4.5 } else { $L.Size })
        $v = New-CrossVisual @($L) 1.6
        [Windows.Controls.Canvas]::SetLeft($v, 14); [Windows.Controls.Canvas]::SetTop($v, 13)
        [void]$cv.Children.Add($v)
        [void]$sp.Children.Add($cv)
        $tx = New-Object Windows.Controls.TextBlock; $tx.Text = $Global:CrossShapes[$i]; $tx.FontSize = 11; $tx.HorizontalAlignment = 'Center'; $tx.Margin = New-Object Windows.Thickness 0, 4, 0, 0
        [void]$sp.Children.Add($tx)
        $b.Content = $sp; $b.Tag = $i
        $b.Add_Click({ Set-CrossField 'Shape' ([int]$this.Tag); Update-CrossEditor })
        [void]$ui.CrossShapeGrid.Children.Add($b)
    }
}

function Set-CrossPreset([string]$Name) {
    $Global:Cross.Layers.Clear()
    switch ($Name) {
        'plus' { $a = New-CrossLayer 3; $a.Size = 6; $a.Thick = 2; $a.Gap = 3; [void]$Global:Cross.Layers.Add($a) }
        'dot' { $a = New-CrossLayer 0; $a.Size = 4; [void]$Global:Cross.Layers.Add($a) }
        'ringdot' { $a = New-CrossLayer 1; $a.Size = 9; $a.Thick = 1.5; [void]$Global:Cross.Layers.Add($a); $b = New-CrossLayer 0; $b.Size = 2.5; $b.Color = '#FF3B5C'; [void]$Global:Cross.Layers.Add($b) }
        'tee' {
            foreach ($arm in @(@(-6, 0, 0), @(6, 0, 0), @(0, 6, 90))) {
                $l = New-CrossLayer 8; $l.Size = 3; $l.Thick = 2; $l.OffX = $arm[0]; $l.OffY = $arm[1]; $l.Rotate = $arm[2]
                [void]$Global:Cross.Layers.Add($l)
            }
        }
    }
    $Global:Cross.Sel = 0
    Save-Cross; Update-CrossEditor
}

function Connect-Cross {
    $ui = $Global:UI
    Load-Cross
    Build-CrossShapes
    foreach ($n in @('CrossTabShape', 'CrossTabColor', 'CrossTabFx')) { $ui[$n].Add_Click({ $Global:Cross.Tab = @('CrossTabShape', 'CrossTabColor', 'CrossTabFx').IndexOf([string]$this.Name); Update-CrossEditor }) }
    $ui.BtnCrossAdd.Add_Click({
        if ($Global:Cross.Layers.Count -ge $Global:CrossMax) { return }
        $l = New-CrossLayer 0; $l.Size = 2
        [void]$Global:Cross.Layers.Add($l); $Global:Cross.Sel = $Global:Cross.Layers.Count - 1
        Save-Cross; Update-CrossEditor
    })
    $ui.BtnCrossDup.Add_Click({
        if ($Global:Cross.Layers.Count -ge $Global:CrossMax) { Show-Toast "Up to $($Global:CrossMax) layers." 'info'; return }
        $Global:Cross.Layers.Insert($Global:Cross.Sel + 1, $Global:Cross.Layers[$Global:Cross.Sel].Clone()); $Global:Cross.Sel++
        Save-Cross; Update-CrossEditor
    })
    $ui.BtnCrossDel.Add_Click({
        if ($Global:Cross.Layers.Count -le 1) { return }
        $Global:Cross.Layers.RemoveAt($Global:Cross.Sel)
        if ($Global:Cross.Sel -ge $Global:Cross.Layers.Count) { $Global:Cross.Sel = $Global:Cross.Layers.Count - 1 }
        Save-Cross; Update-CrossEditor
    })
    foreach ($p in @('plus', 'dot', 'ringdot', 'tee')) { $ui[('BtnCrossPre_' + $p)].Tag = $p; $ui[('BtnCrossPre_' + $p)].Add_Click({ Set-CrossPreset ([string]$this.Tag) }) }
    $ui.CrossShow.Add_Click({ Show-CrossOverlay ([bool]$Global:UI.CrossShow.IsChecked) })
    $ui.CrossRbxLock.IsChecked = [bool]$Global:CCH.Settings.RbxCursorLock
    $ui.CrossRbxLock.Add_Click({ $Global:CCH.Settings.RbxCursorLock = [bool]$Global:UI.CrossRbxLock.IsChecked; Save-Settings })
    $ui.BtnCrossRbx.Add_Click({ [void](Invoke-RbxCursorApply) })
    $ui.BtnCrossRbxReset.Add_Click({ Restore-RbxCursor })
    $ui.BtnCrossPng.Add_Click({
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = 'PNG image (*.png)|*.png'; $dlg.FileName = 'kuro-cursor.png'
        if ($dlg.ShowDialog()) { try { Save-CrossPng $dlg.FileName 64; Show-Toast 'Saved.' } catch { Show-Toast $_.Exception.Message 'error' } }
    })
    Update-CrossEditor
    try { Sync-RbxCursor } catch { }
    if ($Global:CCH.Settings.CrossShow) { Show-CrossOverlay $true }
}

# ==================================================================================================
#  GAME BAR  - detects the game in front, applies that game's profile (boost, crosshair, macros),
#  and opens a small overlay with Alt+K. Detection is by process name of the foreground window.
# ==================================================================================================

$Global:GameNames = @{
    'RobloxPlayerBeta' = 'Roblox'; 'FortniteClient-Win64-Shipping' = 'Fortnite'; 'VALORANT-Win64-Shipping' = 'Valorant'
    'cs2' = 'Counter-Strike 2'; 'r5apex' = 'Apex Legends'; 'GTA5' = 'GTA V'; 'Minecraft.Windows' = 'Minecraft (Bedrock)'
    'javaw' = 'Minecraft (Java)'; 'RocketLeague' = 'Rocket League'; 'FiveM' = 'FiveM'; 'TslGame' = 'PUBG'; 'Overwatch' = 'Overwatch 2'
    'League of Legends' = 'League of Legends'; 'GenshinImpact' = 'Genshin Impact'; 'eldenring' = 'Elden Ring'; 'Warframe.x64' = 'Warframe'
    'destiny2' = 'Destiny 2'; 'RainbowSix' = 'Rainbow Six Siege'; 'cod' = 'Call of Duty'; 'FallGuys_client_game' = 'Fall Guys'
}
$Global:GameBar = @{ Game = $null; Proc = ''; Pid = 0; Since = $null; Front = $false; AutoBoost = $false; AutoMacros = $false; AutoCross = $false
                     Timer = $null; KeyTimer = $null; KeyPrev = $false; Win = $null; Ui = @{}; Cpu = 0; LastStats = [DateTime]::MinValue }

function Get-GameProfile([string]$Proc) {
    $all = $Global:CCH.Settings.GameProfiles
    $p = $null
    if ($all -is [hashtable]) { $p = $all[$Proc] } elseif ($all -and $all.PSObject.Properties[$Proc]) { $p = $all.$Proc }
    $o = @{ Boost = $false; Cross = $false; Macros = $false }
    if ($p) { foreach ($k in @('Boost', 'Cross', 'Macros')) { $v = $(if ($p -is [hashtable]) { $p[$k] } elseif ($p.PSObject.Properties[$k]) { $p.$k } else { $null }); if ($null -ne $v) { $o[$k] = [bool]$v } } }
    return $o
}

function Set-GameProfile([string]$Proc, [string]$Key, [bool]$Val) {
    $all = @{}
    $cur = $Global:CCH.Settings.GameProfiles
    if ($cur -is [hashtable]) { $all = $cur } elseif ($cur) { foreach ($pp in $cur.PSObject.Properties) { $all[$pp.Name] = Get-GameProfile $pp.Name } }
    $p = Get-GameProfile $Proc; $p[$Key] = $Val; $all[$Proc] = $p
    $Global:CCH.Settings.GameProfiles = $all
    Save-Settings
}

# ------------------------------------------------------------------ detection
function Get-FrontGame {
    if (-not (Initialize-KuroWin)) { return $null }
    $fpid = [KuroWin]::ForegroundPid()
    if ($fpid -le 0) { return $null }
    if ($fpid -eq $PID) { return @{ Self = $true } }
    $p = $null
    try { $p = Get-Process -Id $fpid -ErrorAction Stop } catch { return $null }
    $n = $p.ProcessName
    if (-not ($Global:BoostGames -contains $n)) { return $null }
    if ($n -eq 'javaw' -and ([string]$p.MainWindowTitle) -notlike '*Minecraft*') { return $null }
    $name = $Global:GameNames[$n]; if (-not $name) { $name = $n }
    return @{ Proc = $n; Name = $name; Pid = $fpid }
}

function Step-GameDetect {
    $gb = $Global:GameBar
    if (-not $Global:CCH.Settings.GameAuto) { return }
    $g = Get-FrontGame
    if ($g -and $g.Self) { return }   # Kuro itself in front: keep the current state
    if ($g) {
        if ($gb.Pid -ne $g.Pid) { if ($gb.Game) { Exit-Game }; Enter-Game $g }
        $gb.Front = $true
    } else {
        $gb.Front = $false
        if ($gb.Game) {
            $alive = $true
            try { $null = Get-Process -Id $gb.Pid -ErrorAction Stop } catch { $alive = $false }
            if (-not $alive) { Exit-Game }
        }
    }
    # a profile-driven crosshair only shows while the game is in front
    if ($gb.AutoCross -and $Global:Cross.Overlay) {
        $Global:Cross.Overlay.Visibility = $(if ($gb.Front) { 'Visible' } else { 'Hidden' })
    }
    Update-GamePage
}

function Enter-Game($g) {
    $gb = $Global:GameBar
    $gb.Game = $g.Name; $gb.Proc = $g.Proc; $gb.Pid = $g.Pid; $gb.Since = [DateTime]::Now
    Write-Log "Game detected: $($g.Name) (pid $($g.Pid))"
    $p = Get-GameProfile $g.Proc
    $done = @()
    if ($p.Boost -and -not $Global:CCH.Boost.On) {
        if (Confirm-Premium) { try { Start-Boost; $gb.AutoBoost = $true; $done += 'Game Boost' } catch { } }
        else { $done += 'Game Boost needs Premium' }
    }
    if ($p.Macros -and -not [bool]$Global:UI.MacroMaster.IsChecked) {
        $Global:UI.MacroMaster.IsChecked = $true; Set-MacrosEnabled $true
        if ([bool]$Global:UI.MacroMaster.IsChecked) { $gb.AutoMacros = $true; $done += 'macros' }
    }
    if ($p.Cross -and -not $Global:Cross.Overlay) { Show-CrossOverlay $true $false; $gb.AutoCross = $true; $done += 'crosshair' }
    if ($g.Proc -eq 'RobloxPlayerBeta') { try { Sync-RobloxFlags; Sync-RbxCursor } catch { } }
    $msg = "$($g.Name) detected."
    if ($done.Count) { $msg += ' Turned on: ' + ($done -join ', ') + '.' }
    $msg += ' Alt+K opens the Game Bar.'
    Show-Toast $msg
}

function Exit-Game {
    $gb = $Global:GameBar
    Write-Log "Game closed: $($gb.Game)"
    if ($gb.AutoBoost -and $Global:CCH.Boost.On) { try { Stop-Boost } catch { } }
    if ($gb.AutoMacros -and [bool]$Global:UI.MacroMaster.IsChecked) { $Global:UI.MacroMaster.IsChecked = $false; Set-MacrosEnabled $false }
    if ($gb.AutoCross) { Show-CrossOverlay $false $false }
    $gb.Game = $null; $gb.Proc = ''; $gb.Pid = 0; $gb.Since = $null; $gb.Front = $false
    $gb.AutoBoost = $false; $gb.AutoMacros = $false; $gb.AutoCross = $false
    if ($gb.Win -and $gb.Win.IsVisible) { Update-GameBarWin }
}

# ------------------------------------------------------------------ page
function Update-GamePage {
    $ui = $Global:UI
    $gb = $Global:GameBar
    if (-not $ui.GameNowTxt) { return }
    if (-not $Global:CCH.Settings.GameAuto) { $ui.GameNowTxt.Text = 'Game detection is off.'; $ui.GameNowDot.Fill = $Global:CCH.Window.Resources['SubTextBrush']; return }
    if ($gb.Game) {
        $mins = [int]([DateTime]::Now - $gb.Since).TotalMinutes
        $ui.GameNowTxt.Text = "Playing $($gb.Game)  $([char]0x00B7)  $mins min" + $(if (-not $gb.Front) { '  (in the background)' } else { '' })
        $ui.GameNowDot.Fill = $Global:CCH.Window.Resources['GoodBrush']
    } else {
        $ui.GameNowTxt.Text = 'Waiting for a game. Open one and Kuro will notice it.'
        $ui.GameNowDot.Fill = $Global:CCH.Window.Resources['SubTextBrush']
    }
}

function Build-GameProfiles {
    $ui = $Global:UI
    $ui.GameProfileList.Children.Clear()
    $procs = @('RobloxPlayerBeta') + @($Global:BoostGames | Where-Object { $_ -ne 'RobloxPlayerBeta' })
    foreach ($proc in $procs) {
        $name = $Global:GameNames[$proc]; if (-not $name) { $name = $proc }
        $p = Get-GameProfile $proc
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.VerticalAlignment = 'Center'
        [Windows.Controls.Grid]::SetColumn($sp, 1)
        foreach ($k in @('Boost', 'Cross', 'Macros')) {
            $cb = New-Object Windows.Controls.CheckBox
            $cb.Style = $Global:CCH.Window.Resources['Switch']
            $cb.Content = @{ Boost = 'Boost'; Cross = 'Crosshair'; Macros = 'Macros' }[$k]
            $cb.Margin = New-Object Windows.Thickness 14, 0, 0, 0
            $cb.IsChecked = [bool]$p[$k]; $cb.Tag = "$proc|$k"
            $cb.Add_Click({ $t = ([string]$this.Tag).Split('|'); Set-GameProfile $t[0] $t[1] ([bool]$this.IsChecked) })
            [void]$sp.Children.Add($cb)
        }
        $row = New-MacroRow $name $(if ($proc -eq 'RobloxPlayerBeta') { 'Also re-applies your Roblox graphics and cursor.' } else { "$proc.exe" }) ''
        [void]$row.Child.Children.Add($sp)
        [void]$ui.GameProfileList.Children.Add($row)
    }
}

# ------------------------------------------------------------------ overlay window (fixed dark glass palette)
$Global:GameBarXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kuro Game Bar" Width="640" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI Variable Text, Segoe UI">
  <Window.Resources>
    <Style x:Key="GbBtn" TargetType="Button">
      <Setter Property="Foreground" Value="#F2F2F2"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Background" Value="#1C2024"/><Setter Property="BorderBrush" Value="#2C3238"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="10" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="12,10">
          <ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.85"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border CornerRadius="16" Background="#EE111416" BorderBrush="#33FFFFFF" BorderThickness="1" Padding="18,16">
    <StackPanel>
      <Grid Margin="0,0,0,14">
        <StackPanel Orientation="Horizontal">
          <Border x:Name="GbIcon" Width="34" Height="34" CornerRadius="9" Margin="0,0,10,0"/>
          <StackPanel VerticalAlignment="Center">
            <TextBlock Text="Kuro Game Bar" FontSize="15" FontWeight="SemiBold" Foreground="#F4F4F2"/>
            <TextBlock x:Name="GbGame" Text="No game detected" FontSize="12" Foreground="#9AA0A8"/>
          </StackPanel>
        </StackPanel>
        <Button x:Name="GbClose" HorizontalAlignment="Right" VerticalAlignment="Center" Style="{StaticResource GbBtn}" Margin="0" Padding="0">
          <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#C8CCD2"/>
        </Button>
      </Grid>
      <UniformGrid Columns="4" Margin="0,0,0,12">
        <Border CornerRadius="10" Background="#1C2024" Padding="12,8" Margin="0,0,8,0"><StackPanel><TextBlock x:Name="GbCpu" Text="-" FontSize="20" FontWeight="Bold" Foreground="#F4F4F2"/><TextBlock Text="CPU" FontSize="11" Foreground="#9AA0A8"/></StackPanel></Border>
        <Border CornerRadius="10" Background="#1C2024" Padding="12,8" Margin="0,0,8,0"><StackPanel><TextBlock x:Name="GbRam" Text="-" FontSize="20" FontWeight="Bold" Foreground="#F4F4F2"/><TextBlock Text="RAM used" FontSize="11" Foreground="#9AA0A8"/></StackPanel></Border>
        <Border CornerRadius="10" Background="#1C2024" Padding="12,8" Margin="0,0,8,0"><StackPanel><TextBlock x:Name="GbTime" Text="-" FontSize="20" FontWeight="Bold" Foreground="#F4F4F2"/><TextBlock Text="In game" FontSize="11" Foreground="#9AA0A8"/></StackPanel></Border>
        <Border CornerRadius="10" Background="#1C2024" Padding="12,8"><StackPanel><TextBlock x:Name="GbClock" Text="-" FontSize="20" FontWeight="Bold" Foreground="#F4F4F2"/><TextBlock Text="Time" FontSize="11" Foreground="#9AA0A8"/></StackPanel></Border>
      </UniformGrid>
      <WrapPanel x:Name="GbButtons"/>
      <StackPanel x:Name="GbRbx" Margin="0,4,0,0">
        <TextBlock Text="Roblox graphics" FontSize="12" FontWeight="SemiBold" Foreground="#9AA0A8" Margin="2,0,0,6"/>
        <WrapPanel x:Name="GbRbxBtns"/>
      </StackPanel>
      <TextBlock Text="Alt+K or Esc closes  &#183;  F8 pauses macros" FontSize="11" Foreground="#6E747C" Margin="2,6,0,0"/>
    </StackPanel>
  </Border>
</Window>
'@

function New-GbButton([string]$Glyph, [string]$Label) {
    $b = New-Object Windows.Controls.Button
    $b.Style = $Global:GameBar.Win.Resources['GbBtn']; $b.Width = 190
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $ic = New-Object Windows.Controls.TextBlock; $ic.Text = $Glyph; $ic.FontFamily = New-Object Windows.Media.FontFamily 'Segoe MDL2 Assets'; $ic.FontSize = 14
    $ic.VerticalAlignment = 'Center'; $ic.Margin = New-Object Windows.Thickness 0, 0, 10, 0; $ic.Foreground = New-CrossBrush '#F4F4F2'
    $tx = New-Object Windows.Controls.TextBlock; $tx.Text = $Label; $tx.FontSize = 13; $tx.VerticalAlignment = 'Center'; $tx.Foreground = New-CrossBrush '#F4F4F2'
    [void]$sp.Children.Add($ic); [void]$sp.Children.Add($tx)
    $b.Content = $sp
    return $b
}

function Initialize-GameBarWin {
    $gb = $Global:GameBar
    if ($gb.Win) { return }
    $w = [Windows.Markup.XamlReader]::Parse($Global:GameBarXaml)
    $gb.Win = $w
    foreach ($n in @('GbIcon', 'GbGame', 'GbClose', 'GbCpu', 'GbRam', 'GbTime', 'GbClock', 'GbButtons', 'GbRbx', 'GbRbxBtns')) { $gb.Ui[$n] = $w.FindName($n) }
    $f = Join-Path $Global:AppDir 'assets\Kuro.png'
    if (Test-Path $f) { try { $bmp = New-Object Windows.Media.Imaging.BitmapImage (New-Object Uri $f); $gb.Ui.GbIcon.Background = New-Object Windows.Media.ImageBrush $bmp } catch { } }
    $defs = @(
        @{ K = 'rec'; G = [string][char]0xE7C8; L = 'Record' }
        @{ K = 'boost'; G = [string][char]0xE945; L = 'Game Boost' }
        @{ K = 'cross'; G = [string][char]0xE710; L = 'Crosshair' }
        @{ K = 'macro'; G = [string][char]0xE765; L = 'Macros' }
        @{ K = 'proof'; G = [string][char]0xE72E; L = 'Stream proof' }
        @{ K = 'music'; G = [string][char]0xE8D6; L = 'Music' }
    )
    $gb.Btns = @{}
    foreach ($d in $defs) {
        $b = New-GbButton $d.G $d.L; $b.Tag = $d.K
        $b.Add_Click({ Invoke-GameBarAction ([string]$this.Tag) })
        [void]$gb.Ui.GbButtons.Children.Add($b); $gb.Btns[$d.K] = $b
    }
    foreach ($pr in $Global:RbxPresets) {
        $b = New-GbButton ([string][char]$pr.I) $pr.N; $b.Width = 140; $b.Tag = $pr.S
        $b.Add_Click({ $Global:UI.RbxSlider.Value = [int]$this.Tag; Invoke-RbxApply; Update-GameBarWin })
        [void]$gb.Ui.GbRbxBtns.Children.Add($b)
    }
    $gb.Ui.GbClose.Add_Click({ Hide-GameBar })
    $w.Add_KeyDown({ if ($_.Key -eq 'Escape') { Hide-GameBar } })
    $w.Add_Deactivated({ Hide-GameBar })
    $w.Add_SourceInitialized({ param($s, $e) Register-KuroWindow $s })
}

function Invoke-GameBarAction([string]$K) {
    switch ($K) {
        'rec' { Invoke-ScreenRecord }
        'boost' { if ($Global:CCH.Boost.On) { Stop-Boost } else { Start-Boost } }
        'cross' { Show-CrossOverlay (-not [bool]$Global:Cross.Overlay); $Global:GameBar.AutoCross = $false }
        'macro' { $on = -not [bool]$Global:UI.MacroMaster.IsChecked; $Global:UI.MacroMaster.IsChecked = $on; Set-MacrosEnabled $on; $Global:GameBar.AutoMacros = $false }
        'proof' { Set-StreamProof (-not [bool]$Global:CCH.Settings.StreamProof) }
        'music' { if ($Global:Vibe.Playing) { Stop-Music } else { Start-Music } }
    }
    Update-GameBarWin
}

function Set-GbState($b, [bool]$On, [string]$Label) {
    $acc = Get-AccentColor
    if ($On) { $b.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(0x40, $acc.R, $acc.G, $acc.B)); $b.BorderBrush = New-Object Windows.Media.SolidColorBrush $acc }
    else { $b.Background = New-CrossBrush '#1C2024'; $b.BorderBrush = New-CrossBrush '#2C3238' }
    $b.Content.Children[1].Text = $Label
}

function Update-GameBarWin {
    $gb = $Global:GameBar; if (-not $gb.Win) { return }
    $u = $gb.Ui
    $u.GbGame.Text = $(if ($gb.Game) { "Playing $($gb.Game)" } else { 'No game detected' })
    $u.GbTime.Text = $(if ($gb.Since) { ('{0} min' -f [int]([DateTime]::Now - $gb.Since).TotalMinutes) } else { '-' })
    $u.GbClock.Text = [DateTime]::Now.ToString('HH:mm')
    try { $u.GbCpu.Text = ([string][CchNative]::CpuPercent()) + '%' } catch { $u.GbCpu.Text = '-' }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $u.GbRam.Text = ('{0}%' -f [int](100 - 100.0 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize))
    } catch { $u.GbRam.Text = '-' }
    Set-GbState $gb.Btns['rec'] ([bool]$Global:CCH.Recording) $(if ($Global:CCH.Recording) { 'Stop recording' } else { 'Record' })
    Set-GbState $gb.Btns['boost'] ([bool]$Global:CCH.Boost.On) $(if ($Global:CCH.Boost.On) { 'Boost: on' } else { 'Game Boost' })
    Set-GbState $gb.Btns['cross'] ([bool]$Global:Cross.Overlay) $(if ($Global:Cross.Overlay) { 'Crosshair: on' } else { 'Crosshair' })
    Set-GbState $gb.Btns['macro'] ([bool]$Global:UI.MacroMaster.IsChecked) $(if ($Global:UI.MacroMaster.IsChecked) { 'Macros: on' } else { 'Macros' })
    Set-GbState $gb.Btns['proof'] ([bool]$Global:CCH.Settings.StreamProof) $(if ($Global:CCH.Settings.StreamProof) { 'Stream proof: on' } elseif ($Global:CCH.Premium) { 'Stream proof' } else { 'Stream proof (PRO)' })
    Set-GbState $gb.Btns['boost'] ([bool]$Global:CCH.Boost.On) $(if ($Global:CCH.Boost.On) { 'Boost: on' } elseif ($Global:CCH.Premium) { 'Game Boost' } else { 'Game Boost (PRO)' })
    Set-GbState $gb.Btns['music'] ([bool]$Global:Vibe.Playing) $(if ($Global:Vibe.Playing) { 'Music: playing' } else { 'Music' })
    $u.GbRbx.Visibility = $(if ($gb.Proc -eq 'RobloxPlayerBeta' -or -not $gb.Game) { 'Visible' } else { 'Collapsed' })
}

function Show-GameBar {
    Initialize-GameBarWin
    $w = $Global:GameBar.Win
    Update-GameBarWin
    # centre on the game window if one is in front
    try {
        $r = [KuroWin]::ForegroundRect()
        $src = [Windows.PresentationSource]::FromVisual($Global:CCH.Window)
        if ($r -and $src) {
            $sx = $src.CompositionTarget.TransformToDevice.M11; $sy = $src.CompositionTarget.TransformToDevice.M22
            $w.WindowStartupLocation = 'Manual'
            $w.Left = (($r[0] + $r[2]) / 2.0) / $sx - $w.Width / 2
            $w.Top = ($r[1] / $sy) + 60
        }
    } catch { }
    $w.Show(); [void]$w.Activate()
    if ($Global:CCH.Settings.StreamProof -and $Global:CCH.Premium) { [void](Set-WindowProof $w $true) }
}

function Hide-GameBar { if ($Global:GameBar.Win -and $Global:GameBar.Win.IsVisible) { $Global:GameBar.Win.Hide() } }

function Switch-GameBar {
    if ($Global:GameBar.Win -and $Global:GameBar.Win.IsVisible) { Hide-GameBar } else { Show-GameBar }
}

function Connect-GameBar {
    $ui = $Global:UI
    [void](Initialize-KuroWin)
    $Global:CCH.Window.Add_SourceInitialized({ Register-KuroWindow $Global:CCH.Window })
    $ui.GameAuto.IsChecked = [bool]$Global:CCH.Settings.GameAuto
    $ui.GameAuto.Add_Click({ $Global:CCH.Settings.GameAuto = [bool]$Global:UI.GameAuto.IsChecked; Save-Settings; if (-not $Global:CCH.Settings.GameAuto -and $Global:GameBar.Game) { Exit-Game }; Update-GamePage })
    foreach ($n in @('SetStreamProof', 'GbStreamProof')) {
        if ($ui[$n]) { $ui[$n].IsChecked = [bool]$Global:CCH.Settings.StreamProof; $ui[$n].Add_Click({ Set-StreamProof ([bool]$this.IsChecked) }) }
    }
    $ui.BtnGameBarOpen.Add_Click({ Show-GameBar })
    Build-GameProfiles
    Update-GamePage

    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(1500)
    $t.Add_Tick({ try { Step-GameDetect; if ($Global:GameBar.Win -and $Global:GameBar.Win.IsVisible) { Update-GameBarWin } } catch { Write-Log "Game detect: $($_.Exception.Message)" } })
    $t.Start(); $Global:GameBar.Timer = $t

    # Alt+K, polled (no message hook needed); works while a game is in front
    $k = New-Object Windows.Threading.DispatcherTimer
    $k.Interval = [TimeSpan]::FromMilliseconds(60)
    $k.Add_Tick({
        try {
            $down = [KuroWin]::KeyDown(0x12) -and [KuroWin]::KeyDown(0x4B)
            if ($down -and -not $Global:GameBar.KeyPrev) { Switch-GameBar }
            $Global:GameBar.KeyPrev = $down
        } catch { }
    })
    $k.Start(); $Global:GameBar.KeyTimer = $k
    $Global:CCH.Window.Add_Closing({ try { if ($Global:GameBar.Win) { $Global:GameBar.Win.Close() }; Show-CrossOverlay $false $false } catch { } })
}

# ==================================================================================================
#  PREMIUM GATES + WELCOME BANNER
#  - Shows a "Thanks for buying Premium" banner at the top centre whenever Premium turns on
#    (code redeemed, or restored by logging in). Not shown on a normal start-up.
#  - Puts a visible lock card over Premium-only areas while on the Free plan.
#    The real checks stay in the features themselves (Confirm-Premium), so a lock card
#    is only the visual part.
# ==================================================================================================

$Global:PremGate = @{ Known = $false; Was = $false; Locks = @(); BannerTimer = $null }

# Premium-only areas: element name in the UI, title for the lock card, what it does
$Global:PremLockDefs = @(
    @{ El = 'BoostMain';   T = 'Game Boost is a Premium feature'; D = 'One click before you play: frees RAM, closes background apps, maxes the power mode and gives your game CPU priority.' }
    @{ El = 'GbProofCard'; T = 'Stream proof is a Premium feature'; D = 'Hides Kuro, its Game Bar and crosshair from screenshots, OBS, Discord screen share and recordings.' }
)

function New-PremiumLockCard([string]$Title, [string]$Desc) {
    $x = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" CornerRadius="12" Padding="18,14" Margin="0,0,14,12"
        Background="{DynamicResource AccentSoftBrush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Border Width="38" Height="38" CornerRadius="10" Background="{DynamicResource AccentBrush}" Margin="0,0,14,0" VerticalAlignment="Center">
      <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,14,0">
      <TextBlock Text="%T%" FontSize="14.5" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
      <TextBlock Text="%D%" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
    </StackPanel>
  </Grid>
</Border>
'@
    $x = $x.Replace('%T%', [Security.SecurityElement]::Escape($Title)).Replace('%D%', [Security.SecurityElement]::Escape($Desc))
    $card = [Windows.Markup.XamlReader]::Parse($x)
    $b = New-Object Windows.Controls.Button
    $b.Style = $Global:CCH.Window.Resources['AccentBtn']; $b.Content = 'Unlock Premium'; $b.Padding = New-Object Windows.Thickness 16, 8, 16, 8
    $b.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($b, 2)
    $b.Add_Click({ Show-Page 'PagePremium' })
    [void]$card.Child.Children.Add($b)
    return $card
}

function Initialize-PremiumLocks {
    $locks = @()
    foreach ($d in $Global:PremLockDefs) {
        $el = $Global:UI[$d.El]
        if (-not $el) { continue }
        $parent = [Windows.Media.VisualTreeHelper]::GetParent($el)
        if (-not ($parent -is [Windows.Controls.Panel])) { $parent = $el.Parent }
        if (-not ($parent -is [Windows.Controls.Panel])) { continue }
        $card = New-PremiumLockCard $d.T $d.D
        $parent.Children.Insert($parent.Children.IndexOf($el), $card)
        $locks += @{ El = $el; Card = $card }
    }
    $Global:PremGate.Locks = $locks
}

function Update-PremiumLocks {
    $prem = [bool]$Global:CCH.Premium
    foreach ($l in $Global:PremGate.Locks) {
        $l.Card.Visibility = $(if ($prem) { 'Collapsed' } else { 'Visible' })
        $l.El.IsEnabled = $prem
        $l.El.Opacity = $(if ($prem) { 1.0 } else { 0.45 })
    }
    $ui = $Global:UI
    if ($ui.SetStreamProof) {
        $ui.SetStreamProof.IsEnabled = $prem
        $ui.SetProofTxt.Text = 'Stream proof: hide Kuro from screenshots and screen share' + $(if ($prem) { '' } else { '  (Premium)' })
    }
    if ($ui.GbStreamProof) { $ui.GbStreamProof.IsEnabled = $prem }
    if ($ui.BtnDiscordRole) { $ui.BtnDiscordRole.Visibility = $(if ($prem -and $Global:DiscordBotUrl) { 'Visible' } else { 'Collapsed' }) }
    # Premium is only known after the start-up check, so apply a saved stream-proof setting here
    if ($prem -and $Global:CCH.Settings.StreamProof) { foreach ($w in @($Global:KuroWindows)) { [void](Set-WindowProof $w $true) } }
    # losing Premium (revoked, tamper, moved PC) switches Premium-only features off
    if (-not $prem) {
        if ($Global:CCH.Settings.StreamProof) {
            $Global:CCH.Settings.StreamProof = $false; Save-Settings
            foreach ($w in @($Global:KuroWindows)) { [void](Set-WindowProof $w $false) }
            foreach ($cb in @('SetStreamProof', 'GbStreamProof')) { if ($ui[$cb]) { $ui[$cb].IsChecked = $false } }
        }
        if ($Global:CCH.Boost -and $Global:CCH.Boost.On) { try { Stop-Boost } catch { } }
    }
}

# called at the end of Update-PremiumUI
function Step-PremiumGate {
    $prem = [bool]$Global:CCH.Premium
    if ($Global:PremGate.Known -and $prem -and -not $Global:PremGate.Was) { Show-PremiumWelcome }
    $Global:PremGate.Known = $true
    $Global:PremGate.Was = $prem
    Update-PremiumLocks
}

function Show-PremiumWelcome {
    $ui = $Global:UI
    $b = $ui.PremBanner
    if (-not $b) { return }
    $acc = Get-AccentColor
    $g = New-Object Windows.Media.LinearGradientBrush
    $g.StartPoint = New-Object Windows.Point 0, 0; $g.EndPoint = New-Object Windows.Point 1, 1
    [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#F6B85A')), 0.0))
    [void]$g.GradientStops.Add((New-Object Windows.Media.GradientStop $acc, 1.0))
    $b.Background = $g
    $tt = New-Object Windows.Media.TranslateTransform 0, -90
    $b.RenderTransform = $tt
    $b.Opacity = 0; $b.Visibility = 'Visible'
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(520))
    $ease = New-Object Windows.Media.Animation.BackEase; $ease.Amplitude = 0.45; $ease.EasingMode = 'EaseOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation (-90.0), 0.0, $dur; $a.EasingFunction = $ease
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a)
    $b.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation 0, 1, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(300)))))
    try { Show-Fx 'sparkle' '' } catch { }
    try { $was = $Global:CCH.Settings.StartSound; $Global:CCH.Settings.StartSound = $true; Play-ReadyChime; $Global:CCH.Settings.StartSound = $was } catch { }
    Write-Log 'Premium activated - welcome banner shown.'
    if (-not $Global:PremGate.BannerTimer) {
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(6)
        $t.Add_Tick({ $this.Stop(); Hide-PremiumWelcome })
        $Global:PremGate.BannerTimer = $t
        $b.Add_MouseLeftButtonUp({ Hide-PremiumWelcome })
    }
    $Global:PremGate.BannerTimer.Stop(); $Global:PremGate.BannerTimer.Start()
}

function Hide-PremiumWelcome {
    $b = $Global:UI.PremBanner
    if (-not $b -or $b.Visibility -ne 'Visible') { return }
    if ($Global:PremGate.BannerTimer) { $Global:PremGate.BannerTimer.Stop() }
    $tt = $b.RenderTransform
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(320))
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0.0, (-90.0), $dur
    $a.Add_Completed({ $Global:UI.PremBanner.Visibility = 'Collapsed' })
    if ($tt -is [Windows.Media.TranslateTransform]) { $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a) } else { $b.Visibility = 'Collapsed' }
    $b.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation 1, 0, $dur))
}


# ------------------------------------------------------------------ Discord Premium role
# Asks the Kuro bot for a single-use 6-digit code proving this PC holds a redeemed licence;
# the user types /premium <code> in the Kuro Discord to get the Premium role.
function Get-DiscordRoleCode {
    if (-not $Global:CCH.Premium) { Show-PremiumPrompt 'Discord Premium role'; return }
    if (-not $Global:DiscordBotUrl) { Show-Toast 'The Kuro Discord bot is not set up yet.' 'info'; return }
    $info = Get-LicenseInfo
    if (-not $info -or -not $info.hash) { Show-Toast "Couldn't find this PC's Premium licence. Redeem your code again, then try this." 'error'; return }
    Show-Busy 'Getting your Discord code...'
    $r = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $body = ConvertTo-Json -Compress -InputObject @{ hash = [string]$info.hash; machine = (Get-MachineId) }
        $r = Invoke-RestMethod -Uri ($Global:DiscordBotUrl + '/discord-code') -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop
    } catch { $r = $null }
    Hide-Busy
    if (-not $r) { Show-Toast "Couldn't reach the Kuro bot. Check your internet and try again." 'error'; return }
    if (-not $r.ok) { Show-Toast $(if ($r.reason -eq 'not_premium') { 'The server does not see an active Premium licence for this PC. Use /bug in the Discord if that is wrong.' } else { 'Something went wrong. Try again in a minute.' }) 'error'; return }
    $code = [string]$r.code
    try { [Windows.Clipboard]::SetText('/premium ' + $code) } catch { }
    Show-Modal 'Your Discord code' ("Your code is  $code`n`nIn the Kuro Discord, type:  /premium $code`n(It's already copied, so you can just paste it.)`n`nThe code works once and lasts 15 minutes.") 'Open Discord' 'Close' { Open-Discord } $null 'star'
}


# ==================================================================================================
#  TIMED KEYS RUNNING OUT
#  A 1 day / 3 day / 1 week key switches itself off: Premium turns off, every Premium tweak that is
#  still on gets reverted from Kuro's backup (the same as switching it off by hand), Game Boost and
#  stream proof stop, and the user is told why. Free tweaks the user chose are left alone.
# ==================================================================================================
$Global:PremExpiry = @{ Pending = $false; Timer = $null }

function Start-PremiumClock {
    # checks once a minute while Kuro is open, so a key that ends mid-session is handled straight away
    if ($Global:PremExpiry.Timer) { return }
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(60)
    $t.Add_Tick({
        try {
            $exp = Get-LicenseExpiry
            if ($exp -le 0) { return }
            if (Test-LicenseExpired) { $Global:CCH.Premium = $false; Request-PremiumExpiry }
            elseif ($Global:CCH.Premium) {
                $left = Format-TimeLeft ($exp - (Get-NowMs))
                $Global:UI.StatPremiumSub.Text = 'Timed key: ' + $left
                $Global:UI.PremStatus.Text = 'Premium is active on this PC  -  ' + $left
            }
        } catch { Write-Log "Premium clock: $($_.Exception.Message)" }
    })
    $t.Start()
    $Global:PremExpiry.Timer = $t
}

function Request-PremiumExpiry {
    # run it on the dispatcher so it never fires half-way through building the UI
    if ($Global:PremExpiry.Pending) { return }
    $Global:PremExpiry.Pending = $true
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromMilliseconds(4000)
    $t.Add_Tick({ $this.Stop(); try { Invoke-PremiumExpiry } catch { Write-Log "Premium expiry: $($_.Exception.Message)" } finally { $Global:PremExpiry.Pending = $false } })
    $t.Start()
}

function Invoke-PremiumExpiry {
    $info = Get-LicenseInfo
    if (-not $info -or -not $info.expires) { return }
    $days = [int]$info.days
    $what = $(if ($days -gt 0) { Get-KeyLengthText $days } else { 'timed' })
    # keep a record, then remove the licence so nothing treats this PC as Premium any more
    try { Move-Item -LiteralPath $Global:LicFile -Destination (Join-Path $Global:DataDir 'license.expired.dat') -Force -ErrorAction Stop }
    catch { try { Remove-Item -LiteralPath $Global:LicFile -Force -ErrorAction SilentlyContinue } catch { } }
    $Global:CCH.Premium = $false
    Write-Log "Timed Premium key ($what) ended - switching Premium off and reverting Premium changes."
    # Premium-only things that are running right now
    try { if ($Global:CCH.Boost -and $Global:CCH.Boost.On) { Stop-Boost } } catch { }
    # every Premium tweak that is still applied goes back to how the PC was before it
    $list = @($Global:Tweaks | Where-Object { $_.Premium -and $_.Applied })
    $reverted = 0; $failed = 0
    if ($list.Count) {
        Show-Busy 'Your Premium time is up' 'Putting Premium changes back...'
        $i = 0
        foreach ($t in $list) {
            $i++
            Set-BusyText ("[{0}/{1}]  Restoring {2}" -f $i, $list.Count, $t.Name)
            $r = Set-TweakState $t $false
            if ($r.Ok) { $reverted++ } else { $failed++ }
            Refresh-Tweak $t
            Pump-UI
        }
        Hide-Busy
    }
    Update-PremiumUI
    Update-AllViews
    $msg = "Your $what Premium key has ended, so Premium is now switched off on this PC."
    if ($reverted) { $msg += "`n`nKuro put back the $reverted Premium change" + $(if ($reverted -ne 1) { 's' } else { '' }) + ' it had made, so those settings are exactly how they were before.' }
    if ($failed) { $msg += "`n$failed could not be put back automatically - use Settings > Restore everything, or ask in the Kuro Discord." }
    $msg += "`n`nAll free features keep working. Want Premium again? Grab another key in the Kuro Discord."
    Show-Modal 'Your Premium time is up' $msg 'Get another key' 'OK' { Show-Page 'PagePremium' } $null 'star'
}

# ==================================================================================================
#  LIVE COMMUNITY STATS (dashboard): online now / active users, premium users, buyers.
#  Each copy sends an anonymous check-in every 15 minutes: a random-looking install id (a hash that
#  cannot be turned back into the PC's ID), whether Premium is on, and the Kuro version. Nothing else.
#  Users can switch the check-in off in Settings; they still see the numbers.
# ==================================================================================================

$Global:LiveStats = @{ PS = $null; Handle = $null; Poll = $null; Every = $null; Busy = $false; Last = $null }

function Get-StatsId { return (Get-Sha256Hex ('kuro-stats|' + (Get-MachineId))).Substring(0, 32) }

function Format-StatNum([int]$N) { if ($N -ge 10000) { return ('{0:0.#}k' -f ($N / 1000.0)) } else { return ('{0:N0}' -f $N) } }

function Update-LiveStatsUI($R) {
    $ui = $Global:UI
    if (-not $ui.StatUsers) { return }
    if (-not $R -or -not $R.ok) {
        $why = $(if (-not (Get-LicenseServer)) { 'No Kuro server is set up yet.' } elseif ($R -and $R.reason -eq 'no_stats_db') { 'The server has no stats database yet.' } else { "Couldn't reach the Kuro server." })
        if (-not $Global:LiveStats.Last) {
            foreach ($n in @('StatUsers', 'StatPremUsers', 'StatBuyers')) { $ui[$n].Text = '-' }
            $ui.StatUsersSub.Text = 'Active in the last 24 hours'
        }
        $ui.LiveStatsNote.Text = $why + $(if ($Global:LiveStats.Last) { ' Showing the last numbers.' } else { '' })
        return
    }
    $Global:LiveStats.Last = $R
    $ui.StatUsers.Text = Format-StatNum ([int]$R.active)
    $ui.StatUsersSub.Text = ('Active today  {0}  {1} online now' -f [char]0x00B7, (Format-StatNum ([int]$R.online)))
    $ui.StatPremUsers.Text = Format-StatNum ([int]$R.premium)
    $ui.StatBuyers.Text = Format-StatNum ([int]$R.buyers)
    $ui.LiveStatsNote.Text = 'Live from the Kuro server  ' + [char]0x00B7 + '  updated ' + [DateTime]::Now.ToString('HH:mm') + $(if (-not $Global:CCH.Settings.ShareStats) { '  ' + [char]0x00B7 + "  this PC isn't counted" } else { '' })
}

$Global:LiveStatsWorker = {
    param($server, $share, $id, $premium, $version)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if ($share) {
            $body = ConvertTo-Json -InputObject @{ id = $id; premium = [bool]$premium; version = $version } -Compress
            return (Invoke-RestMethod -Uri ($server + '/hello') -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop)
        }
        return (Invoke-RestMethod -Uri ($server + '/stats') -Method Post -Body '{}' -ContentType 'application/json' -TimeoutSec 15 -ErrorAction Stop)
    } catch { return @{ ok = $false; reason = 'network' } }
}

function Invoke-LiveStats {
    $ls = $Global:LiveStats
    if ($ls.Busy) { return }
    $server = Get-LicenseServer
    if (-not $server) { Update-LiveStatsUI $null; return }
    try {
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Global:LiveStatsWorker.ToString()).AddArgument($server).AddArgument([bool]$Global:CCH.Settings.ShareStats).AddArgument((Get-StatsId)).AddArgument([bool]$Global:CCH.Premium).AddArgument($Global:CCH_Version)
        $ls.PS = $ps; $ls.Handle = $ps.BeginInvoke(); $ls.Busy = $true
        if (-not $ls.Poll) {
            $t = New-Object Windows.Threading.DispatcherTimer
            $t.Interval = [TimeSpan]::FromMilliseconds(500)
            $t.Add_Tick({
                $ls = $Global:LiveStats
                if (-not $ls.Handle -or -not $ls.Handle.IsCompleted) { return }
                $ls.Poll.Stop(); $ls.Busy = $false
                $r = $null
                try { $r = @($ls.PS.EndInvoke($ls.Handle))[0] } catch { }
                try { $ls.PS.Dispose() } catch { }
                Update-LiveStatsUI $r
            })
            $ls.Poll = $t
        }
        $ls.Poll.Start()
    } catch { $ls.Busy = $false; Write-Log "Live stats failed: $($_.Exception.Message)" }
}

function Start-LiveStats {
    $ui = $Global:UI
    if ($ui.SetShareStats) {
        $ui.SetShareStats.IsChecked = [bool]$Global:CCH.Settings.ShareStats
        $ui.SetShareStats.Add_Click({ $Global:CCH.Settings.ShareStats = [bool]$Global:UI.SetShareStats.IsChecked; Save-Settings; Invoke-LiveStats })
    }
    if ($ui.BtnStatsRefresh) { $ui.BtnStatsRefresh.Add_Click({ Invoke-LiveStats }) }
    Invoke-LiveStats
    $e = New-Object Windows.Threading.DispatcherTimer
    $e.Interval = [TimeSpan]::FromMinutes(15)
    $e.Add_Tick({ Invoke-LiveStats })
    $e.Start(); $Global:LiveStats.Every = $e
}

# ==================================================================================================
#  GREETING BANNER  - guessed entirely from the PC's clock and calendar (no location, no internet):
#  time of day + season (month, flipped for southern-hemisphere regions) -> e.g. on a winter night:
#  "A late worm in the cold night" / "...make sure you get to bed."
#  Late at night a bedtime reminder can come back every 90 minutes while Kuro is open.
# ==================================================================================================

$Global:Greet = @{ Nudge = $null; LastNudge = [DateTime]::MinValue; HideTimer = $null }
$Global:SouthernRegions = @('AU', 'NZ', 'ZA', 'AR', 'CL', 'UY', 'PY', 'BR', 'BO', 'PE', 'NA', 'BW', 'ZW', 'MZ', 'MG', 'LS', 'SZ', 'FJ')

function Get-Season([DateTime]$D) {
    $m = $D.Month
    $south = $false
    try { $south = $Global:SouthernRegions -contains ([Globalization.RegionInfo]::CurrentRegion.TwoLetterISORegionName) } catch { }
    if ($south) { $m = (($m + 5) % 12) + 1 }   # shift six months
    if ($m -eq 12 -or $m -le 2) { return 'winter' }
    if ($m -le 5) { return 'spring' }
    if ($m -le 8) { return 'summer' }
    return 'autumn'
}

function Get-DayPart([int]$H) {
    if ($H -lt 5) { return 'latenight' }
    if ($H -lt 8) { return 'dawn' }
    if ($H -lt 12) { return 'morning' }
    if ($H -lt 17) { return 'afternoon' }
    if ($H -lt 21) { return 'evening' }
    return 'night'
}

function Get-TimeGreeting {
    $now = [DateTime]::Now
    $part = Get-DayPart $now.Hour
    $season = Get-Season $now
    $t = $now.ToString('HH:mm')
    $late = ($part -eq 'night' -or $part -eq 'latenight')
    # "cold" is a guess: winter, or the chilly ends of the day in autumn and spring
    $cold = ($season -eq 'winter') -or (($season -eq 'autumn' -or $season -eq 'spring') -and ($late -or $part -eq 'dawn'))
    $g = @{ Title = ''; Sub = ''; Icon = ''; Mood = 'day' }
    if ($late) {
        $g.Mood = 'night'; $g.Icon = [string][char]0x263E
        if ($cold) { $g.Title = 'A late worm in the cold night' }
        elseif ($season -eq 'summer') { $g.Title = 'Night owl on a warm night' }
        else { $g.Title = "Still up at $t?" }
        if ($season -eq 'winter') { $g.Icon = [string][char]0x2744 }
        $g.Sub = $(if ($part -eq 'latenight') { "It's $t. One more round, then make sure you get to bed. Sleep helps your aim too." } else { "It's getting late. Make sure you go to bed after this session." })
        return $g
    }
    switch ($part) {
        'dawn' {
            $g.Icon = [string][char]0x2600
            $g.Title = $(if ($cold) { 'Up before the sun, and it''s chilly' } else { 'Up before the sun' })
            $g.Sub = 'Early bird gets the W. Everything is tuned and ready.'
        }
        'morning' {
            $g.Icon = [string][char]0x2600
            $g.Title = @{ winter = 'Cold winter morning, warm PC'; spring = 'Good morning, spring is here'; summer = 'Good morning, sunshine'; autumn = 'Crisp autumn morning' }[$season]
            $g.Sub = 'Kuro is ready when you are. Have a good one.'
        }
        'afternoon' {
            $g.Icon = [string][char]0x2600
            $g.Title = @{ winter = 'Winter afternoon session'; spring = 'Spring afternoon session'; summer = 'Sunny afternoon session'; autumn = 'Cozy autumn afternoon' }[$season]
            $g.Sub = "Don't forget water and a quick stretch between games."
        }
        default {
            $g.Icon = [string][char]0x263C
            $g.Title = @{ winter = 'Dark already? Perfect gaming weather'; spring = 'Good evening'; summer = 'Golden hour gaming'; autumn = 'Cozy autumn evening' }[$season]
            $g.Sub = 'Settle in, everything is optimized.'
            if ($season -eq 'winter') { $g.Mood = 'night'; $g.Icon = [string][char]0x263E }
        }
    }
    return $g
}

function Show-GreetBanner {
    $ui = $Global:UI
    $b = $ui.GreetBanner
    if (-not $b) { return }
    if ($ui.PremBanner -and $ui.PremBanner.Visibility -eq 'Visible') { return }
    $g = Get-TimeGreeting
    $ui.GreetTitle.Text = $g.Title
    $ui.GreetSub.Text = $g.Sub
    $ui.GreetIcon.Text = $g.Icon
    $stops = @{ night = @('#1E2547', '#4A3A78'); day = @('#F6B85A', '') }[$g.Mood]
    $c1 = [Windows.Media.ColorConverter]::ConvertFromString($stops[0])
    $c2 = $(if ($stops[1]) { [Windows.Media.ColorConverter]::ConvertFromString($stops[1]) } else { Get-AccentColor })
    $br = New-Object Windows.Media.LinearGradientBrush
    $br.StartPoint = New-Object Windows.Point 0, 0; $br.EndPoint = New-Object Windows.Point 1, 1
    [void]$br.GradientStops.Add((New-Object Windows.Media.GradientStop $c1, 0.0))
    [void]$br.GradientStops.Add((New-Object Windows.Media.GradientStop $c2, 1.0))
    $b.Background = $br
    $tt = New-Object Windows.Media.TranslateTransform 0, (-90.0)
    $b.RenderTransform = $tt
    $b.Opacity = 0; $b.Visibility = 'Visible'
    $ease = New-Object Windows.Media.Animation.BackEase; $ease.Amplitude = 0.4; $ease.EasingMode = 'EaseOut'
    $a = New-Object Windows.Media.Animation.DoubleAnimation (-90.0), 0.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(520)))
    $a.EasingFunction = $ease
    $tt.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a)
    $b.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation 0.0, 1.0, (New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(300)))))
    if (-not $Global:Greet.HideTimer) {
        $t = New-Object Windows.Threading.DispatcherTimer
        $t.Interval = [TimeSpan]::FromSeconds(10)
        $t.Add_Tick({ $this.Stop(); Hide-GreetBanner })
        $Global:Greet.HideTimer = $t
        $b.Add_MouseLeftButtonUp({ Hide-GreetBanner })
    }
    $Global:Greet.HideTimer.Stop(); $Global:Greet.HideTimer.Start()
}

function Hide-GreetBanner {
    $b = $Global:UI.GreetBanner
    if (-not $b -or $b.Visibility -ne 'Visible') { return }
    if ($Global:Greet.HideTimer) { $Global:Greet.HideTimer.Stop() }
    $dur = New-Object Windows.Duration ([TimeSpan]::FromMilliseconds(320))
    $a = New-Object Windows.Media.Animation.DoubleAnimation 0.0, (-90.0), $dur
    $a.Add_Completed({ $Global:UI.GreetBanner.Visibility = 'Collapsed' })
    if ($b.RenderTransform -is [Windows.Media.TranslateTransform]) { $b.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, $a) } else { $b.Visibility = 'Collapsed' }
    $b.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Object Windows.Media.Animation.DoubleAnimation 1.0, 0.0, $dur))
}

function Invoke-Greeting {
    if (-not $Global:CCH.Settings.Greet) { return }
    Show-GreetBanner
}

function Start-Greetings {
    $ui = $Global:UI
    if ($ui.SetGreet) {
        $ui.SetGreet.IsChecked = [bool]$Global:CCH.Settings.Greet
        $ui.SetGreet.Add_Click({ $Global:CCH.Settings.Greet = [bool]$Global:UI.SetGreet.IsChecked; Save-Settings; if ($Global:CCH.Settings.Greet) { Invoke-Greeting } })
        $ui.SetBedtime.IsChecked = [bool]$Global:CCH.Settings.Bedtime
        $ui.SetBedtime.Add_Click({ $Global:CCH.Settings.Bedtime = [bool]$Global:UI.SetBedtime.IsChecked; Save-Settings })
    }
    $t = New-Object Windows.Threading.DispatcherTimer
    $t.Interval = [TimeSpan]::FromSeconds(2.5)
    $t.Add_Tick({ $this.Stop(); if (-not ($Global:UI.TutorialLayer -and $Global:UI.TutorialLayer.Visibility -eq 'Visible')) { Invoke-Greeting } })
    $t.Start()
    # late-night bedtime reminder (23:00-05:00), at most every 90 minutes while Kuro is open
    $n = New-Object Windows.Threading.DispatcherTimer
    $n.Interval = [TimeSpan]::FromMinutes(10)
    $n.Add_Tick({
        $s = $Global:CCH.Settings
        $h = [DateTime]::Now.Hour
        if (-not $s.Greet -or -not $s.Bedtime -or -not ($h -ge 23 -or $h -lt 5)) { return }
        if (([DateTime]::Now - $Global:Greet.LastNudge).TotalMinutes -lt 90) { return }
        $Global:Greet.LastNudge = [DateTime]::Now
        Invoke-Greeting
    })
    $n.Start(); $Global:Greet.Nudge = $n
    $h0 = [DateTime]::Now.Hour
    if ($h0 -ge 23 -or $h0 -lt 5) { $Global:Greet.LastNudge = [DateTime]::Now }
}

# ==================================================================================================
#  STARTUP
# ==================================================================================================

$Global:MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Kuro" Width="1120" Height="680" MinWidth="900" MinHeight="540"
        WindowStartupLocation="CenterScreen" WindowStyle="None" ResizeMode="CanResize"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource TextBrush}"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display">
  <WindowChrome.WindowChrome>
    <WindowChrome CaptionHeight="46" ResizeBorderThickness="6" CornerRadius="0" GlassFrameThickness="0" UseAeroCaptionButtons="False"/>
  </WindowChrome.WindowChrome>

  <Window.Resources>
    <!-- ======== Theme brushes (replaced at runtime by the colour panel) ======== -->
    <SolidColorBrush x:Key="BgBrush" Color="#0B0F17"/>
    <SolidColorBrush x:Key="SidebarBrush" Color="#0D121B"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#131A26"/>
    <SolidColorBrush x:Key="Panel2Brush" Color="#1A2331"/>
    <SolidColorBrush x:Key="LineBrush" Color="#243045"/>
    <SolidColorBrush x:Key="TextBrush" Color="#F2F4F8"/>
    <SolidColorBrush x:Key="SubTextBrush" Color="#8C96AA"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#FF9A1F"/>
    <SolidColorBrush x:Key="AccentSoftBrush" Color="#2EFF9A1F"/>
    <SolidColorBrush x:Key="OnAccentBrush" Color="#111111"/>
    <SolidColorBrush x:Key="GoodBrush" Color="#3DDC84"/>
    <SolidColorBrush x:Key="WarnBrush" Color="#FFB020"/>
    <SolidColorBrush x:Key="BadBrush" Color="#FF5A5F"/>
    <SolidColorBrush x:Key="BlueBrush" Color="#3B82F6"/>
    <LinearGradientBrush x:Key="HeroBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FF9A1F" Offset="0"/>
      <GradientStop Color="#7A3A00" Offset="1"/>
    </LinearGradientBrush>

    <!-- ======== Sidebar nav button ======== -->
    <Style x:Key="NavBtn" TargetType="RadioButton">
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="44"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="GroupName" Value="Nav"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="19"/>
      <Setter Property="Foreground" Value="{DynamicResource SubTextBrush}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid>
              <Border x:Name="bg" CornerRadius="12" Background="Transparent"/>
              <Border x:Name="bar" Width="3" CornerRadius="2" HorizontalAlignment="Left" Margin="-12,12,0,12" Background="{DynamicResource AccentBrush}" Visibility="Collapsed"/>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bg" Property="Background" Value="{DynamicResource Panel2Brush}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="bg" Property="Background" Value="{DynamicResource AccentSoftBrush}"/>
                <Setter TargetName="bar" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsChecked" Value="True">
          <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
        </Trigger>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- ======== Buttons ======== -->
    <Style x:Key="AccentBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource OnAccentBrush}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="9" Background="{DynamicResource AccentBrush}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.72"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Background" Value="{DynamicResource Panel2Brush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Padding" Value="14,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="9" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="TileBtn" TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Padding="18,16">
              <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Top"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="b" Property="Background" Value="{DynamicResource Panel2Brush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Width" Value="46"/>
      <Setter Property="Height" Value="46"/>
      <Setter Property="Foreground" Value="{DynamicResource SubTextBrush}"/>
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="10"/>
      <Setter Property="WindowChrome.IsHitTestVisibleInChrome" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Panel2Brush}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="WinCloseBtn" TargetType="Button" BasedOn="{StaticResource WinBtn}">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#E81123"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Toggle switch ======== -->
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <ContentPresenter VerticalAlignment="Center" Margin="0,0,10,0"/>
              <Grid Width="44" Height="24">
                <Border x:Name="track" CornerRadius="12" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1"/>
                <Grid x:Name="knob" Width="16" Height="16" HorizontalAlignment="Left" Margin="4,0,0,0">
                  <Ellipse x:Name="knobDot" Fill="#8C96AA"/>
                  <Path x:Name="knobTick" Data="M4.5,9 L7.4,11.6 L12,5.6" Stroke="{DynamicResource AccentBrush}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
                </Grid>
              </Grid>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                <Setter TargetName="knobDot" Property="Fill" Value="White"/>
                <Setter TargetName="knobTick" Property="Visibility" Value="Visible"/>
                <Setter TargetName="knob" Property="Width" Value="18"/>
                <Setter TargetName="knob" Property="Height" Value="18"/>
                <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Filter chip ======== -->
    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{DynamicResource SubTextBrush}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="9" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" Padding="14,7">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource AccentSoftBrush}"/>
                <Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsChecked" Value="True">
          <Setter Property="Foreground" Value="{DynamicResource AccentBrush}"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- ======== Segmented option (one pill inside a segment group) ======== -->
    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Foreground" Value="{DynamicResource SubTextBrush}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="7" Background="Transparent" Padding="12,6,12,7" Margin="1,0">
              <Grid>
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                <Border x:Name="u" Height="2" Width="14" CornerRadius="1" Background="{DynamicResource AccentBrush}" VerticalAlignment="Bottom" Margin="0,0,0,-6" Visibility="Collapsed"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#14FFFFFF"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{DynamicResource PanelBrush}"/>
                <Setter TargetName="u" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsChecked" Value="True">
          <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
          <Setter Property="FontWeight" Value="SemiBold"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- ======== Inputs ======== -->
    <Style x:Key="Input" TargetType="TextBox">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="12,9"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="b" CornerRadius="9" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Thin scrollbar ======== -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="MinWidth" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border CornerRadius="4" Background="{DynamicResource LineBrush}" Margin="1,2"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="8"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="Transparent">
                  <Track x:Name="PART_Track" IsDirectionReversed="False">
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border CornerRadius="4" Background="{DynamicResource LineBrush}" Margin="2,1"/>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>

    <!-- ======== Usage meter ======== -->
    <Style x:Key="Meter" TargetType="ProgressBar">
      <Setter Property="Height" Value="8"/>
      <Setter Property="Minimum" Value="0"/>
      <Setter Property="Maximum" Value="100"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" CornerRadius="4" Background="{DynamicResource Panel2Brush}"/>
              <Border x:Name="PART_Indicator" CornerRadius="4" HorizontalAlignment="Left" Background="{TemplateBinding Foreground}"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Discord button ======== -->
    <Style x:Key="DiscordBtn" TargetType="Button">
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Padding" Value="20,11"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="#5865F2" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#4752C4"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Volume slider ======== -->
    <Style x:Key="VolSlider" TargetType="Slider">
      <Setter Property="Height" Value="22"/>
      <Setter Property="IsMoveToPointEnabled" Value="True"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Slider">
            <Grid VerticalAlignment="Center">
              <Border Height="6" CornerRadius="3" Background="{DynamicResource Panel2Brush}"/>
              <Track x:Name="PART_Track">
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="Slider.DecreaseLarge" Focusable="False" IsTabStop="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Height="6" CornerRadius="3" Background="{DynamicResource AccentBrush}"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="Slider.IncreaseLarge" Focusable="False" IsTabStop="False">
                    <RepeatButton.Template>
                      <ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate>
                    </RepeatButton.Template>
                  </RepeatButton>
                </Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb Width="18" Height="18">
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb"><Ellipse Fill="White" Stroke="{DynamicResource AccentBrush}" StrokeThickness="3"/></ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- ======== Text + card styles ======== -->
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="20"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="28"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    </Style>
    <Style x:Key="H3" TargetType="TextBlock">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Foreground" Value="{DynamicResource SubTextBrush}"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Icon" TargetType="TextBlock">
      <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>

  <Grid x:Name="RootGrid">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="72"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>
    <Grid.RowDefinitions>
      <RowDefinition Height="46"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- ================= Title bar ================= -->
    <Border Grid.Row="0" Grid.ColumnSpan="2" Background="{DynamicResource SidebarBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,0,0,1"/>
    <StackPanel Grid.Row="0" Grid.ColumnSpan="2" Orientation="Horizontal" VerticalAlignment="Center" Margin="18,0,0,0">
      <Viewbox Width="26" Height="26" Margin="0,0,9,0">
        <Canvas Width="30" Height="30">
          <Path Stroke="{DynamicResource AccentBrush}" StrokeThickness="2.4" Data="M7,8 L4,2.5 L11.5,6.5 M23,8 L26,2.5 L18.5,6.5"/>
          <Ellipse Canvas.Left="6" Canvas.Top="7" Width="18" Height="18" Stroke="{DynamicResource AccentBrush}" StrokeThickness="2.4"/>
          <Path Stroke="{DynamicResource AccentBrush}" StrokeThickness="2.2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M10.5,20.5 L19.5,11.5"/>
        </Canvas>
      </Viewbox>
      <TextBlock Text="KURO" FontSize="17" FontWeight="Bold" VerticalAlignment="Center" Foreground="{DynamicResource TextBrush}" Padding="0,0,0,1">
        <TextBlock.LayoutTransform><ScaleTransform ScaleX="1.05"/></TextBlock.LayoutTransform>
      </TextBlock>
      <Border x:Name="TitleBoostPill" Margin="16,0,0,0" CornerRadius="6" Padding="9,3" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center" Cursor="Hand" WindowChrome.IsHitTestVisibleInChrome="True">
        <StackPanel Orientation="Horizontal">
          <Ellipse x:Name="TitleBoostDot" Width="7" Height="7" Fill="#8C96AA" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <TextBlock x:Name="TitleBoostText" Text="GAME BOOST OFF" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
        </StackPanel>
      </Border>
      <Border x:Name="TitlePlanPill" Margin="8,0,0,0" CornerRadius="6" Padding="9,3" Background="{DynamicResource AccentSoftBrush}" VerticalAlignment="Center" Cursor="Hand" WindowChrome.IsHitTestVisibleInChrome="True">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="&#xE735;" Style="{StaticResource Icon}" FontSize="10" Foreground="{DynamicResource AccentBrush}" Margin="0,0,6,0"/>
          <TextBlock x:Name="TitlePlan" Text="FREE" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center"/>
        </StackPanel>
      </Border>
      <Border x:Name="MusicPill" Margin="8,0,0,0" CornerRadius="6" Padding="9,3" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center" Cursor="Hand" WindowChrome.IsHitTestVisibleInChrome="True" ToolTip="Play or pause the chill music">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="MusicIcon" Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource AccentBrush}" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <TextBlock x:Name="MusicTitle" Text="Music off" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
        </StackPanel>
      </Border>
      <Border x:Name="MusicNext" Margin="4,0,0,0" CornerRadius="6" Padding="7,4" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalAlignment="Center" Cursor="Hand" WindowChrome.IsHitTestVisibleInChrome="True" ToolTip="Next track">
        <TextBlock Text="&#xE893;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
      </Border>
    </StackPanel>
    <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnMin" Style="{StaticResource WinBtn}" Content="&#xE921;"/>
      <Button x:Name="BtnMax" Style="{StaticResource WinBtn}" Content="&#xE922;"/>
      <Button x:Name="BtnClose" Style="{StaticResource WinCloseBtn}" Content="&#xE8BB;"/>
    </StackPanel>

    <!-- ================= Sidebar ================= -->
    <Border Grid.Row="1" Grid.Column="0" Background="{DynamicResource SidebarBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,0,1,0">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Disabled">
          <StackPanel HorizontalAlignment="Center" Margin="0,10,0,6">
            <RadioButton x:Name="NavDash" Style="{StaticResource NavBtn}" Content="&#xE80F;" ToolTip="Dashboard" IsChecked="True"/>
            <RadioButton x:Name="NavOptim" Style="{StaticResource NavBtn}" Content="&#xEC4A;" ToolTip="Optimizations"/>
            <RadioButton x:Name="NavDebloat" Style="{StaticResource NavBtn}" Content="&#xEA99;" ToolTip="Debloat"/>
            <RadioButton x:Name="NavBoost" Style="{StaticResource NavBtn}" Content="&#xE7FC;" ToolTip="Game Boost"/>
            <RadioButton x:Name="NavMacro" Style="{StaticResource NavBtn}" Content="&#xE765;" ToolTip="Macros"/>
            <RadioButton x:Name="NavRoblox" Style="{StaticResource NavBtn}" Content="&#xE890;" ToolTip="Roblox graphics"/>
            <RadioButton x:Name="NavCross" Style="{StaticResource NavBtn}" Content="&#xE710;" ToolTip="Cursor and crosshair"/>
            <RadioButton x:Name="NavPing" Style="{StaticResource NavBtn}" Content="&#xE701;" ToolTip="Ping"/>
            <RadioButton x:Name="NavGame" Style="{StaticResource NavBtn}" Content="&#xE7F4;" ToolTip="Game Bar and stream proof"/>
            <RadioButton x:Name="NavScan" Style="{StaticResource NavBtn}" Content="&#xE9D9;" ToolTip="PC Scanner"/>
            <RadioButton x:Name="NavTools" Style="{StaticResource NavBtn}" Content="&#xE90F;" ToolTip="Tools"/>
            <Border Height="1" Width="28" Background="{DynamicResource LineBrush}" Margin="0,6"/>
            <RadioButton x:Name="NavPremium" Style="{StaticResource NavBtn}" Content="&#xE735;" ToolTip="Premium"/>
            <RadioButton x:Name="NavTheme" Style="{StaticResource NavBtn}" Content="&#xE790;" ToolTip="Colours, Vibes and Settings"/>
            <RadioButton x:Name="NavSupport" Style="{StaticResource NavBtn}" Content="&#xE897;" ToolTip="Support, Discord and About"/>
          </StackPanel>
        </ScrollViewer>
        <Border x:Name="AvatarBtn" Grid.Row="1" Margin="0,6,0,12" Width="42" Height="42" CornerRadius="21" BorderThickness="2" BorderBrush="{DynamicResource AccentBrush}" Cursor="Hand" ToolTip="Change your profile picture">
          <Ellipse x:Name="AvatarImg" Fill="{DynamicResource AccentSoftBrush}"/>
        </Border>
      </Grid>
    </Border>

    <!-- ================= Pages ================= -->
    <Grid Grid.Row="1" Grid.Column="1">

      <!-- ===== DASHBOARD ===== -->
      <ScrollViewer x:Name="PageDash" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,32,32">
          <Grid Margin="0,0,0,20">
            <StackPanel>
              <TextBlock Text="Dashboard" Style="{StaticResource H1}"/>
              <TextBlock x:Name="DashWelcome" Text="Scanning your PC..." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
            </StackPanel>
            <Border HorizontalAlignment="Right" VerticalAlignment="Center" CornerRadius="10" Padding="14,8" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE7F8;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                <TextBlock x:Name="DashDevice" Text="Detecting device..." FontWeight="SemiBold" VerticalAlignment="Center"/>
              </StackPanel>
            </Border>
          </Grid>

          <!-- stat row -->
          <UniformGrid Columns="3" Margin="-6,0,-6,16">
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,16">
              <Grid>
                <StackPanel>
                  <TextBlock Text="&#xEC4A;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Left"/>
                  <TextBlock x:Name="StatActive" Text="0" FontSize="26" FontWeight="Bold" Margin="0,8,0,0"/>
                  <TextBlock Text="Optimizations active" Style="{StaticResource Sub}"/>
                </StackPanel>
                <Button x:Name="BtnStatOptim" Style="{StaticResource GhostBtn}" Content="View" Padding="12,6" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
              </Grid>
            </Border>
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,16">
              <Grid>
                <StackPanel>
                  <TextBlock Text="&#xE945;" Style="{StaticResource Icon}" Foreground="{DynamicResource WarnBrush}" HorizontalAlignment="Left"/>
                  <TextBlock x:Name="StatReco" Text="0" FontSize="26" FontWeight="Bold" Margin="0,8,0,0"/>
                  <TextBlock Text="Recommended for your PC, not yet active" Style="{StaticResource Sub}"/>
                </StackPanel>
              </Grid>
            </Border>
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,16">
              <Grid>
                <StackPanel>
                  <TextBlock Text="&#xE735;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Left"/>
                  <TextBlock x:Name="StatPremium" Text="Free" FontSize="26" FontWeight="Bold" Margin="0,8,0,0"/>
                  <TextBlock x:Name="StatPremiumSub" Text="Redeem a code to unlock Premium" Style="{StaticResource Sub}"/>
                </StackPanel>
                <Button x:Name="BtnStatPremium" Style="{StaticResource GhostBtn}" Content="Open" Padding="12,6" HorizontalAlignment="Right" VerticalAlignment="Bottom"/>
              </Grid>
            </Border>
          </UniformGrid>

          <!-- live community stats -->
          <Grid Margin="0,0,0,8">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse Width="8" Height="8" Fill="{DynamicResource GoodBrush}" Margin="0,0,8,0"/>
              <TextBlock Text="Kuro community" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
              <TextBlock x:Name="LiveStatsNote" Text="Connecting..." Style="{StaticResource Sub}" FontSize="11.5" Margin="12,1,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <Button x:Name="BtnStatsRefresh" HorizontalAlignment="Right" Style="{StaticResource GhostBtn}" Padding="9,5" ToolTip="Refresh">
              <TextBlock Text="&#xE72C;" Style="{StaticResource Icon}" FontSize="11"/>
            </Button>
          </Grid>
          <UniformGrid Columns="3" Margin="-6,0,-6,16">
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,14">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE716;" Style="{StaticResource Icon}" FontSize="14" Foreground="{DynamicResource AccentBrush}" Margin="0,0,8,0"/>
                  <TextBlock Text="Active users" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock x:Name="StatUsers" Text="-" FontSize="26" FontWeight="Bold" Margin="0,6,0,0"/>
                <TextBlock x:Name="StatUsersSub" Text="Active in the last 24 hours" Style="{StaticResource Sub}" FontSize="12"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,14">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE735;" Style="{StaticResource Icon}" FontSize="14" Foreground="{DynamicResource AccentBrush}" Margin="0,0,8,0"/>
                  <TextBlock Text="Premium users" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock x:Name="StatPremUsers" Text="-" FontSize="26" FontWeight="Bold" Margin="0,6,0,0"/>
                <TextBlock Text="Using Premium in the last 30 days" Style="{StaticResource Sub}" FontSize="12"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Margin="6,0" Padding="18,14">
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE719;" Style="{StaticResource Icon}" FontSize="14" Foreground="{DynamicResource AccentBrush}" Margin="0,0,8,0"/>
                  <TextBlock Text="Buyers" FontSize="12.5" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock x:Name="StatBuyers" Text="-" FontSize="26" FontWeight="Bold" Margin="0,6,0,0"/>
                <TextBlock Text="Premium codes bought and redeemed" Style="{StaticResource Sub}" FontSize="12"/>
              </StackPanel>
            </Border>
          </UniformGrid>

          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="16"/>
              <ColumnDefinition Width="350"/>
            </Grid.ColumnDefinitions>

            <!-- left: score + recommendations -->
            <Border Grid.Column="0" Style="{StaticResource Card}" VerticalAlignment="Top">
              <StackPanel>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="160"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel x:Name="MascotDashBox" Grid.Column="2" Margin="8,-14,-8,-20" VerticalAlignment="Bottom" Width="172" Cursor="Hand" ToolTip="Click me!">
                    <Border x:Name="MascotBubble" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1" CornerRadius="12,12,12,2" Padding="10,6" Margin="0,0,0,4">
                      <TextBlock x:Name="MascotSay" Text="" FontSize="11.5" TextWrapping="Wrap" Foreground="{DynamicResource TextBrush}"/>
                    </Border>
                    <Image x:Name="MascotDash" Height="190" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
                  </StackPanel>
                  <Grid Width="150" Height="150" HorizontalAlignment="Left">
                    <Ellipse Width="132" Height="132" Stroke="{DynamicResource Panel2Brush}" StrokeThickness="12"/>
                    <Path x:Name="RingArc" Stroke="{DynamicResource AccentBrush}" StrokeThickness="12" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                    <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                      <TextBlock x:Name="RingPct" Text="0%" FontSize="28" FontWeight="Bold" HorizontalAlignment="Center"/>
                      <TextBlock Text="optimized" Style="{StaticResource Sub}" HorizontalAlignment="Center"/>
                    </StackPanel>
                  </Grid>
                  <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="12,0,0,0">
                    <TextBlock x:Name="OptTitle" Text="0% Optimized" FontSize="26" FontWeight="Bold"/>
                    <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                      <TextBlock Text="&#xE946;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource SubTextBrush}" Margin="0,0,8,0"/>
                      <TextBlock x:Name="OptMsg" Text="Checking..." Style="{StaticResource Sub}"/>
                    </StackPanel>
                    <Border Background="{DynamicResource Panel2Brush}" CornerRadius="8" Padding="12,7" Margin="0,12,0,0" HorizontalAlignment="Left">
                      <TextBlock x:Name="OptCount" Text="..." FontSize="12.5" Foreground="{DynamicResource SubTextBrush}"/>
                    </Border>
                    <WrapPanel Margin="0,14,0,0">
                      <Button x:Name="BtnApplyAll" Style="{StaticResource AccentBtn}" Margin="0,0,10,0">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,8,0"/>
                          <TextBlock Text="Apply all recommended"/>
                        </StackPanel>
                      </Button>
                      <Button x:Name="BtnDashRestore" Style="{StaticResource GhostBtn}" Content="Create restore point" Margin="0,0,0,0"/>
                    </WrapPanel>
                  </StackPanel>
                </Grid>
                <Border Height="1" Background="{DynamicResource LineBrush}" Margin="0,20,0,16"/>
                <Grid Margin="0,0,0,12">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE73E;" Style="{StaticResource Icon}" Foreground="{DynamicResource GoodBrush}" Margin="0,0,10,0"/>
                    <TextBlock Text="Recommended for your PC" Style="{StaticResource H3}"/>
                  </StackPanel>
                  <TextBlock x:Name="DashRecoHint" Text="Top picks based on your hardware scan" Style="{StaticResource Sub}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <StackPanel x:Name="DashRecoList"/>
              </StackPanel>
            </Border>

            <!-- right column -->
            <StackPanel Grid.Column="2">
              <Border Style="{StaticResource Card}" Margin="0,0,0,16">
                <StackPanel>
                  <Grid Margin="0,0,0,12">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE7F4;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                      <TextBlock Text="Hardware" Style="{StaticResource H3}"/>
                    </StackPanel>
                    <Button x:Name="BtnDashScan" Style="{StaticResource GhostBtn}" Content="Full scan" Padding="10,5" HorizontalAlignment="Right"/>
                  </Grid>
                  <TextBlock x:Name="HwClass" Text="..." FontSize="17" FontWeight="Bold" TextWrapping="Wrap"/>
                  <TextBlock x:Name="HwCpu" Text="CPU: ..." Style="{StaticResource Sub}" Margin="0,8,0,0"/>
                  <TextBlock x:Name="HwGpu" Text="GPU: ..." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
                  <TextBlock x:Name="HwRam" Text="RAM: ..." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
                  <TextBlock x:Name="HwDisk" Text="Storage: ..." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}" Margin="0,0,0,16">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
                    <TextBlock Text="&#xE9D9;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                    <TextBlock Text="Live usage" Style="{StaticResource H3}"/>
                  </StackPanel>
                  <Grid Margin="0,0,0,12">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="*"/><ColumnDefinition Width="46"/></Grid.ColumnDefinitions>
                    <TextBlock Text="CPU" VerticalAlignment="Center"/>
                    <ProgressBar x:Name="UsageCpuBar" Grid.Column="1" Style="{StaticResource Meter}" Foreground="{DynamicResource GoodBrush}" Value="0"/>
                    <TextBlock x:Name="UsageCpuTxt" Grid.Column="2" Text="0%" HorizontalAlignment="Right" Foreground="{DynamicResource SubTextBrush}"/>
                  </Grid>
                  <Grid Margin="0,0,0,12">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="*"/><ColumnDefinition Width="46"/></Grid.ColumnDefinitions>
                    <TextBlock Text="RAM" VerticalAlignment="Center"/>
                    <ProgressBar x:Name="UsageRamBar" Grid.Column="1" Style="{StaticResource Meter}" Foreground="{DynamicResource BlueBrush}" Value="0"/>
                    <TextBlock x:Name="UsageRamTxt" Grid.Column="2" Text="0%" HorizontalAlignment="Right" Foreground="{DynamicResource SubTextBrush}"/>
                  </Grid>
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="46"/><ColumnDefinition Width="*"/><ColumnDefinition Width="46"/></Grid.ColumnDefinitions>
                    <TextBlock Text="GPU" VerticalAlignment="Center"/>
                    <ProgressBar x:Name="UsageGpuBar" Grid.Column="1" Style="{StaticResource Meter}" Foreground="{DynamicResource AccentBrush}" Value="0"/>
                    <TextBlock x:Name="UsageGpuTxt" Grid.Column="2" Text="0%" HorizontalAlignment="Right" Foreground="{DynamicResource SubTextBrush}"/>
                  </Grid>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                    <TextBlock Text="&#xE8A9;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                    <TextBlock Text="Shortcuts" Style="{StaticResource H3}"/>
                  </StackPanel>
                  <UniformGrid Columns="2" Margin="-4">
                    <Button x:Name="ScDebloat" Style="{StaticResource TileBtn}" Margin="4">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xEA99;" FontFamily="Segoe MDL2 Assets" FontSize="24" HorizontalAlignment="Center" Foreground="{DynamicResource AccentBrush}"/>
                        <TextBlock Text="Debloat" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                      </StackPanel>
                    </Button>
                    <Button x:Name="ScBoost" Style="{StaticResource TileBtn}" Margin="4">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE7FC;" FontFamily="Segoe MDL2 Assets" FontSize="24" HorizontalAlignment="Center" Foreground="{DynamicResource AccentBrush}"/>
                        <TextBlock Text="Game Boost" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                      </StackPanel>
                    </Button>
                    <Button x:Name="ScTools" Style="{StaticResource TileBtn}" Margin="4">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="24" HorizontalAlignment="Center" Foreground="{DynamicResource AccentBrush}"/>
                        <TextBlock Text="Tools" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                      </StackPanel>
                    </Button>
                    <Button x:Name="ScTheme" Style="{StaticResource TileBtn}" Margin="4">
                      <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE790;" FontFamily="Segoe MDL2 Assets" FontSize="24" HorizontalAlignment="Center" Foreground="{DynamicResource AccentBrush}"/>
                        <TextBlock Text="Colours &amp; Vibes" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                      </StackPanel>
                    </Button>
                  </UniformGrid>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== OPTIMIZATIONS ===== -->
      <ScrollViewer x:Name="PageOptim" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <Grid Margin="0,0,14,18">
            <StackPanel>
              <TextBlock Text="Optimizations" Style="{StaticResource H1}"/>
              <TextBlock Text="Registry, power and game tweaks. Every change is backed up and can be switched off again." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
            </StackPanel>
            <Button x:Name="BtnOptimApplyReco" Style="{StaticResource AccentBtn}" HorizontalAlignment="Right" VerticalAlignment="Center" Content="Apply recommended on this page"/>
          </Grid>
          <WrapPanel x:Name="ChipsOptim" Margin="0,0,0,6"/>
          <Grid Margin="0,0,14,16">
            <Grid.ColumnDefinitions><ColumnDefinition Width="320"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid>
              <TextBox x:Name="OptimSearch" Style="{StaticResource Input}" Padding="36,9,12,9"/>
              <TextBlock Text="&#xE721;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource SubTextBrush}" Margin="14,0,0,0" HorizontalAlignment="Left" IsHitTestVisible="False"/>
            </Grid>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
              <TextBlock x:Name="OptimCount" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="0,0,18,0"/>
              <CheckBox x:Name="OptimRecoOnly" Style="{StaticResource Switch}" Content="Recommended only" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
          <WrapPanel x:Name="OptimWrap"/>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== DEBLOAT ===== -->
      <ScrollViewer x:Name="PageDebloat" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <Grid Margin="0,0,14,18">
            <StackPanel>
              <TextBlock Text="Windows Debloat" Style="{StaticResource H1}"/>
              <TextBlock Text="Remove pre-installed apps, stop background services and turn off telemetry to free RAM and CPU for your games." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
            </StackPanel>
            <Button x:Name="BtnDebloatApplyReco" Style="{StaticResource AccentBtn}" HorizontalAlignment="Right" VerticalAlignment="Center" Content="Apply recommended on this page"/>
          </Grid>
          <WrapPanel x:Name="ChipsDebloat" Margin="0,0,0,6"/>
          <Grid Margin="0,0,14,16">
            <Grid.ColumnDefinitions><ColumnDefinition Width="320"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Grid>
              <TextBox x:Name="DebloatSearch" Style="{StaticResource Input}" Padding="36,9,12,9"/>
              <TextBlock Text="&#xE721;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource SubTextBrush}" Margin="14,0,0,0" HorizontalAlignment="Left" IsHitTestVisible="False"/>
            </Grid>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
              <TextBlock x:Name="DebloatCount" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="0,0,18,0"/>
              <CheckBox x:Name="DebloatRecoOnly" Style="{StaticResource Switch}" Content="Recommended only" VerticalAlignment="Center"/>
            </StackPanel>
          </Grid>
          <WrapPanel x:Name="DebloatWrap"/>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== GAME BOOST ===== -->
      <ScrollViewer x:Name="PageBoost" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,32,32">
          <TextBlock Text="Game Boost" Style="{StaticResource H1}"/>
          <TextBlock Text="One click before you play: frees RAM, closes background apps, maxes the power mode and gives your game CPU priority. Turn it off when you're done and everything is restored." Style="{StaticResource Sub}" Margin="0,4,0,20"/>
          <Grid x:Name="BoostMain">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Style="{StaticResource Card}" Padding="26">
              <Grid>
              <Image x:Name="MascotBoost" Height="190" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="-14,-16,0,0" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
              <StackPanel>
                <Grid Width="170" Height="170" HorizontalAlignment="Center" Margin="0,4,0,16">
                  <Ellipse x:Name="BoostRing" Stroke="{DynamicResource LineBrush}" StrokeThickness="6"/>
                  <Ellipse Margin="16" Fill="{DynamicResource Panel2Brush}"/>
                  <TextBlock x:Name="BoostIcon" Text="&#xE7FC;" FontFamily="Segoe MDL2 Assets" FontSize="54" HorizontalAlignment="Center" VerticalAlignment="Center" Foreground="{DynamicResource SubTextBrush}"/>
                </Grid>
                <TextBlock x:Name="BoostStatus" Text="Game Boost is off" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center"/>
                <TextBlock x:Name="BoostSub" Text="Premium feature" Style="{StaticResource Sub}" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,4,0,18"/>
                <Button x:Name="BtnBoost" Style="{StaticResource AccentBtn}" HorizontalAlignment="Center" Padding="34,12" FontSize="15" Content="Activate Game Boost"/>
                <Border Background="{DynamicResource Panel2Brush}" CornerRadius="10" Padding="14,10" Margin="0,20,0,0">
                  <StackPanel>
                    <TextBlock Text="Detected games" FontWeight="SemiBold"/>
                    <TextBlock x:Name="BoostGames" Text="No supported game running" Style="{StaticResource Sub}" Margin="0,4,0,0"/>
                  </StackPanel>
                </Border>
                <TextBlock x:Name="BoostLog" Style="{StaticResource Sub}" Margin="0,12,0,0" FontSize="12"/>
              </StackPanel>
              </Grid>
            </Border>
            <StackPanel Grid.Column="2">
              <Border Style="{StaticResource Card}" Margin="0,0,0,16">
                <StackPanel>
                  <TextBlock Text="Boost options" Style="{StaticResource H3}" Margin="0,0,0,14"/>
                  <Grid Margin="0,0,0,12"><TextBlock Text="Best performance power mode" VerticalAlignment="Center"/><CheckBox x:Name="BoostOptPower" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="0,0,0,12"><TextBlock Text="Close background apps (OneDrive, Widgets, Phone Link...)" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,60,0"/><CheckBox x:Name="BoostOptKill" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="0,0,0,12"><TextBlock Text="Also close web browsers" VerticalAlignment="Center"/><CheckBox x:Name="BoostOptBrowsers" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="0,0,0,12"><TextBlock Text="High CPU priority for running games" VerticalAlignment="Center"/><CheckBox x:Name="BoostOptPriority" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                  <Grid Margin="0,0,0,12"><TextBlock Text="Free up RAM when boost starts" VerticalAlignment="Center"/><CheckBox x:Name="BoostOptRam" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                  <Grid><TextBlock Text="Re-apply Roblox FastFlags after Roblox updates" VerticalAlignment="Center"/><CheckBox x:Name="BoostOptRoblox" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                </StackPanel>
              </Border>
              <Border Style="{StaticResource Card}">
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                    <TextBlock Text="&#xE7FC;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                    <TextBlock Text="Roblox: getting to 120 FPS" Style="{StaticResource H3}"/>
                  </StackPanel>
                  <TextBlock Style="{StaticResource Sub}" LineHeight="20">
                    <Run Text="1.  Turn on the Roblox tweaks in Optimizations &gt; Roblox &amp; Games."/><LineBreak/>
                    <Run Text="2.  In Roblox press Esc &gt; Settings: Graphics Mode = Manual, Graphics Quality = 1 to 3."/><LineBreak/>
                    <Run Text="3.  Set Maximum Frame Rate to 120 or 144 (Roblox's own setting; the old FPS unlocker flags no longer work)."/><LineBreak/>
                    <Run Text="4.  Plug in your charger and turn on Game Boost before joining."/><LineBreak/>
                    <Run Text="5.  On a 60 Hz screen you will only see 60 frames, but higher FPS still lowers input delay."/>
                  </TextBlock>
                </StackPanel>
              </Border>
            </StackPanel>
          </Grid>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== SCANNER ===== -->
      <ScrollViewer x:Name="PageScan" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <Grid Margin="0,0,14,18">
            <StackPanel>
              <TextBlock Text="PC Scanner" Style="{StaticResource H1}"/>
              <TextBlock Text="Everything Kuro knows about your hardware, and what it means for gaming." Style="{StaticResource Sub}" Margin="0,4,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Button x:Name="BtnCopyReport" Style="{StaticResource GhostBtn}" Content="Copy report" Margin="0,0,10,0"/>
              <Button x:Name="BtnRescan" Style="{StaticResource AccentBtn}" Content="Rescan"/>
            </StackPanel>
          </Grid>
          <Border Style="{StaticResource Card}" Margin="0,0,14,16" Padding="24">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="DEVICE PROFILE" FontSize="11" FontWeight="Bold" Foreground="{DynamicResource AccentBrush}"/>
                <TextBlock x:Name="ScanClass" Text="Scanning..." FontSize="24" FontWeight="Bold" Margin="0,4,0,0"/>
                <TextBlock x:Name="ScanClassSub" Style="{StaticResource Sub}" Margin="0,4,0,10"/>
                <WrapPanel x:Name="ScanTags"/>
              </StackPanel>
              <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="20,0,0,0">
                <TextBlock x:Name="ScanScore" Text="--" FontSize="40" FontWeight="Bold" HorizontalAlignment="Center" Foreground="{DynamicResource AccentBrush}"/>
                <TextBlock Text="gaming score / 100" Style="{StaticResource Sub}" HorizontalAlignment="Center"/>
              </StackPanel>
            </Grid>
          </Border>
          <WrapPanel x:Name="ScanCards"/>
          <Border Style="{StaticResource Card}" Margin="0,0,14,16">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <TextBlock Text="&#xE9D9;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                <TextBlock Text="Realistic FPS expectations" Style="{StaticResource H3}"/>
              </StackPanel>
              <TextBlock x:Name="ScanExpect" Style="{StaticResource Sub}" LineHeight="20"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,14,0">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                <TextBlock Text="&#xE82F;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                <TextBlock Text="Advice for your PC" Style="{StaticResource H3}"/>
              </StackPanel>
              <StackPanel x:Name="ScanAdvice"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== MACROS ===== -->
      <ScrollViewer x:Name="PagePing" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Ping" Style="{StaticResource H1}"/>
          <TextBlock Text="Windows network settings that can lower latency, plus a DNS finder. No app can move the game server closer to you." Style="{StaticResource Sub}" Margin="0,4,14,18" TextWrapping="Wrap"/>
          <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,8">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE709;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Lower ping" Style="{StaticResource H3}"/>
                  <TextBlock Text="Windows network settings, undoable" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Games first on the network" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Turns off Windows network throttling." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><CheckBox x:Name="PingThrottle" Style="{StaticResource Switch}"/></StackPanel>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Send small packets at once" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Turns off Nagle&apos;s delay on your adapters (Premium)." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><CheckBox x:Name="PingNagle" Style="{StaticResource Switch}"/></StackPanel>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Status" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock x:Name="PingStatus" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="BtnPingUndo" Style="{StaticResource GhostBtn}" Content="Undo" Padding="14,8" Margin="0,0,8,0"/><Button x:Name="BtnPingApply" Style="{StaticResource AccentBtn}" Content="Apply" Padding="18,8"/></StackPanel>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Roblox traffic first (QoS)" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock x:Name="PingQosTxt" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="BtnPingQos" Style="{StaticResource GhostBtn}" Content="Set up" Padding="16,8"/></StackPanel>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Fastest DNS" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock x:Name="PingDnsTxt" FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="BtnPingDnsReset" Style="{StaticResource GhostBtn}" Content="Restore" Padding="14,8" Margin="0,0,8,0"/><Button x:Name="BtnPingDns" Style="{StaticResource AccentBtn}" Content="Find" Padding="18,8"/></StackPanel>
                </Grid>
              </Border>
            </StackPanel>
          </Border>
          <Border x:Name="PingDnsCard" Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,8" Visibility="Collapsed">
            <StackPanel>
              <TextBlock Text="DNS results" Style="{StaticResource H3}"/>
              <TextBlock Text="Median time to look up six common sites. Lower is better. This speeds up joining and loading, not in-game ping." Style="{StaticResource Sub}" FontSize="12" Margin="0,2,0,8" TextWrapping="Wrap"/>
              <StackPanel x:Name="PingDnsList"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageCross" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Cursor and crosshair" Style="{StaticResource H1}"/>
          <TextBlock Text="Stack shapes into your own crosshair. Show it on screen over any game, or save it as Roblox's cursor." Style="{StaticResource Sub}" Margin="0,4,14,18" TextWrapping="Wrap"/>
          <Grid Margin="0,0,14,14">
            <Grid.ColumnDefinitions><ColumnDefinition Width="300"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Style="{StaticResource Card}" Padding="16" Margin="0,0,14,0" VerticalAlignment="Top">
              <StackPanel>
                <Border CornerRadius="10" ClipToBounds="True" Background="#14171A" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <Grid>
                    <Grid.Background>
                      <DrawingBrush TileMode="Tile" Viewport="0,0,16,16" ViewportUnits="Absolute">
                        <DrawingBrush.Drawing><GeometryDrawing Geometry="M0,0 L16,0 M0,0 L0,16"><GeometryDrawing.Pen><Pen Brush="#1FFFFFFF" Thickness="1"/></GeometryDrawing.Pen></GeometryDrawing></DrawingBrush.Drawing>
                      </DrawingBrush>
                    </Grid.Background>
                    <Canvas x:Name="CrossCanvas" Width="266" Height="240"/>
                  </Grid>
                </Border>
                <TextBlock Text="Preview at 4x size" Style="{StaticResource Sub}" FontSize="11" Margin="2,6,0,10"/>
                <WrapPanel Margin="0,0,0,6">
                  <Button x:Name="BtnCrossPre_plus" Style="{StaticResource GhostBtn}" Content="Plus" Padding="10,6" Margin="0,0,6,6"/>
                  <Button x:Name="BtnCrossPre_dot" Style="{StaticResource GhostBtn}" Content="Dot" Padding="10,6" Margin="0,0,6,6"/>
                  <Button x:Name="BtnCrossPre_ringdot" Style="{StaticResource GhostBtn}" Content="Ring + dot" Padding="10,6" Margin="0,0,6,6"/>
                  <Button x:Name="BtnCrossPre_tee" Style="{StaticResource GhostBtn}" Content="T shape" Padding="10,6" Margin="0,0,6,6"/>
                </WrapPanel>
                <CheckBox x:Name="CrossShow" Style="{StaticResource Switch}" Margin="0,4,0,10"><TextBlock Text="Show on screen" FontSize="13" Foreground="{DynamicResource TextBrush}"/></CheckBox>
                <Button x:Name="BtnCrossRbx" Style="{StaticResource AccentBtn}" Content="Save as Roblox cursor" Padding="14,9" Margin="0,0,0,8"/>
                <Button x:Name="BtnCrossRbxReset" Style="{StaticResource GhostBtn}" Content="Restore Roblox cursor" Padding="14,8" Margin="0,0,0,8"/>
                <CheckBox x:Name="CrossRbxLock" Style="{StaticResource Switch}" Margin="0,2,0,8"><TextBlock Text="Shift-lock cursor too" FontSize="12.5" Foreground="{DynamicResource SubTextBrush}"/></CheckBox>
                <Button x:Name="BtnCrossPng" Style="{StaticResource GhostBtn}" Content="Save as PNG" Padding="14,8"/>
              </StackPanel>
            </Border>
            <Border Grid.Column="1" Style="{StaticResource Card}" Padding="18,14,18,8" VerticalAlignment="Top">
              <StackPanel>
                <Grid Margin="0,0,0,10">
                  <Border HorizontalAlignment="Left" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="10" Padding="4">
                    <StackPanel Orientation="Horizontal">
                      <RadioButton x:Name="CrossTabShape" GroupName="CrossTabs" Style="{StaticResource Seg}" Content="Shape" IsChecked="True"/>
                      <RadioButton x:Name="CrossTabColor" GroupName="CrossTabs" Style="{StaticResource Seg}" Content="Colour"/>
                      <RadioButton x:Name="CrossTabFx" GroupName="CrossTabs" Style="{StaticResource Seg}" Content="Effects"/>
                    </StackPanel>
                  </Border>
                  <TextBlock x:Name="CrossLayerCount" HorizontalAlignment="Right" VerticalAlignment="Center" Style="{StaticResource Sub}" FontSize="12"/>
                </Grid>
                <Grid Margin="0,0,0,10">
                  <WrapPanel x:Name="CrossLayerList" Margin="0,0,200,0"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top">
                    <Button x:Name="BtnCrossAdd" Style="{StaticResource GhostBtn}" Content="+ Layer" Padding="10,6" Margin="0,0,6,0"/>
                    <Button x:Name="BtnCrossDup" Style="{StaticResource GhostBtn}" Content="Copy" Padding="10,6" Margin="0,0,6,0"/>
                    <Button x:Name="BtnCrossDel" Style="{StaticResource GhostBtn}" Content="Delete" Padding="10,6"/>
                  </StackPanel>
                </Grid>
                <UniformGrid x:Name="CrossShapeGrid" Columns="7" Margin="0,0,0,8"/>
                <StackPanel x:Name="CrossFields"/>
              </StackPanel>
            </Border>
          </Grid>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageGame" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Game Bar" Style="{StaticResource H1}"/>
          <TextBlock Text="Kuro notices which game you are playing and switches on what you picked for it. Press Alt+K in-game for the Game Bar." Style="{StaticResource Sub}" Margin="0,4,14,18" TextWrapping="Wrap"/>
          <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,8">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE7FC;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Game detection" Style="{StaticResource H3}"/>
                  <TextBlock Text="Watches which window is in front" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Ellipse x:Name="GameNowDot" Width="9" Height="9" Fill="#8C96AA" Margin="0,0,10,0"/>
                    <TextBlock x:Name="GameNowTxt" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                  </StackPanel>
                  <Button x:Name="BtnGameBarOpen" HorizontalAlignment="Right" Style="{StaticResource AccentBtn}" Content="Open Game Bar  (Alt+K)" Padding="16,8"/>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Detect games" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Turns profiles on and off as you open and close games." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><CheckBox x:Name="GameAuto" Style="{StaticResource Switch}"/></StackPanel>
                </Grid>
              </Border>
            </StackPanel>
          </Border>
          <Border x:Name="GbProofCard" Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,8">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE72E;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Stream proof" Style="{StaticResource H3}"/>
                  <TextBlock Text="Hide Kuro from captures" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Hide Kuro from captures" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Kuro, its Game Bar and crosshair disappear from screenshots, OBS, Discord screen share and Windows recordings. They stay visible to you. Needs Windows 10 2004 or newer. Cameras and capture cards still see your screen." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><CheckBox x:Name="GbStreamProof" Style="{StaticResource Switch}"/></StackPanel>
                </Grid>
              </Border>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,8">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE8F1;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Game profiles" Style="{StaticResource H3}"/>
                  <TextBlock Text="What turns on when each game is in front" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <StackPanel x:Name="GameProfileList"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageRoblox" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Roblox graphics" Style="{StaticResource H1}"/>
          <TextBlock Text="Trade looks for FPS with one slider. Only uses settings Roblox still allows apps to change." Style="{StaticResource Sub}" Margin="0,4,14,18"/>
          <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,14">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE945;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Performance" Style="{StaticResource H3}"/>
                  <TextBlock Text="Looks vs. FPS" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <Grid>
                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                  <TextBlock x:Name="RbxStepName" Text="Balanced" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center"/>
                  <Border CornerRadius="8" Padding="9,3" Margin="12,2,0,0" VerticalAlignment="Center" Background="{DynamicResource AccentSoftBrush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE945;" Style="{StaticResource Icon}" FontSize="11" Foreground="{DynamicResource AccentBrush}" Margin="0,0,6,0"/>
                      <TextBlock x:Name="RbxBadge" Text="Balanced" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}"/>
                    </StackPanel>
                  </Border>
                </StackPanel>
                <Border HorizontalAlignment="Right" VerticalAlignment="Center" CornerRadius="12" Padding="10,4" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <StackPanel Orientation="Horizontal">
                    <Ellipse Width="6" Height="6" Fill="{DynamicResource SubTextBrush}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBlock x:Name="RbxNowTxt" Text="Roblox's own settings: not read yet" FontSize="11.5" Foreground="{DynamicResource SubTextBrush}"/>
                  </StackPanel>
                </Border>
              </Grid>
              <TextBlock x:Name="RbxStepTxt" Style="{StaticResource Sub}" FontSize="12" Margin="0,6,0,14" TextWrapping="Wrap"/>
              <UniformGrid Columns="2" Margin="0,0,0,16">
                <Border Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="9" Padding="12,9" Margin="0,0,8,0">
                  <Grid>
                    <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE890;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0" Foreground="{DynamicResource TextBrush}"/><TextBlock Text="Looks" FontSize="12.5" Foreground="{DynamicResource TextBrush}"/></StackPanel>
                    <StackPanel x:Name="RbxLooksBar" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </Border>
                <Border Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="9" Padding="12,9" Margin="8,0,0,0">
                  <Grid>
                    <StackPanel Orientation="Horizontal"><TextBlock Text="&#xEC4A;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0" Foreground="{DynamicResource TextBrush}"/><TextBlock Text="FPS" FontSize="12.5" Foreground="{DynamicResource TextBrush}"/></StackPanel>
                    <StackPanel x:Name="RbxFpsBar" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                  </Grid>
                </Border>
              </UniformGrid>
              <Grid x:Name="RbxStairs" Height="66" Margin="0,0,0,8"/>
              <Slider x:Name="RbxSlider" Style="{StaticResource VolSlider}" Minimum="1" Maximum="20" SmallChange="1" LargeChange="1" IsSnapToTickEnabled="True" TickFrequency="1" Value="8" Margin="0,4,0,14"/>
              <UniformGrid x:Name="RbxPresets" Columns="4" Margin="0,0,0,14"/>
              <UniformGrid x:Name="RbxDetails" Columns="4" Margin="0,0,0,10"/>
              <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                <Button x:Name="BtnRbxApply" Style="{StaticResource AccentBtn}" Content="Apply to Roblox" Padding="18,9" Margin="0,0,10,0"/>
                <Button x:Name="BtnRbxReset" Style="{StaticResource GhostBtn}" Content="Reset to Roblox defaults" Padding="16,9"/>
              </StackPanel>
              <TextBlock x:Name="RbxApplied" Style="{StaticResource Sub}" FontSize="12" Margin="0,10,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,14">
            <StackPanel>
              <TextBlock Text="Frame-rate cap" Style="{StaticResource H3}"/>
              <TextBlock Text="Roblox no longer lets apps change the FPS limit (it was removed from the allowed settings in September 2025). Set Maximum Frame Rate in Roblox's own in-game Settings menu instead. Changes here take effect the next time Roblox starts." Style="{StaticResource Sub}" FontSize="12" TextWrapping="Wrap" Margin="0,4,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <ScrollViewer x:Name="PageMacro" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Macros" Style="{StaticResource H1}"/>
          <TextBlock Text="Auto-clicker and key macros for PvP, bows, building and movement." Style="{StaticResource Sub}" Margin="0,4,14,18"/>
          <UniformGrid Columns="4" Margin="0,0,4,16">
            <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,10,0">
              <StackPanel>
                <Border Height="56" CornerRadius="10" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <TextBlock x:Name="MacroCpsTxt" Text="0" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="CPS" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Bottom" Margin="6,0,0,5"/>
                  </StackPanel>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="2,10,0,0">
                  <TextBlock Text="&#xE7FC;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource TextBrush}" Margin="0,0,7,0"/>
                  <TextBlock Text="Live CPS" FontWeight="SemiBold" FontSize="13" Foreground="{DynamicResource TextBrush}"/>
                </StackPanel>
                <TextBlock Text="Inputs Kuro is sending now" Style="{StaticResource Sub}" FontSize="11.5" Margin="2,2,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,10,0">
              <StackPanel>
                <Border Height="56" CornerRadius="10" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Ellipse x:Name="MacroStatusDot" Width="9" Height="9" Fill="#8C96AA" VerticalAlignment="Center" Margin="0,0,9,0"/>
                    <TextBlock x:Name="MacroStatusTxt" Text="Off" FontSize="17" FontWeight="Bold" Foreground="{DynamicResource TextBrush}" VerticalAlignment="Center"/>
                  </StackPanel>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="2,10,0,0">
                  <TextBlock Text="&#xE945;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource TextBrush}" Margin="0,0,7,0"/>
                  <TextBlock Text="Status" FontWeight="SemiBold" FontSize="13" Foreground="{DynamicResource TextBrush}"/>
                </StackPanel>
                <TextBlock Text="Off, ready, running or paused" Style="{StaticResource Sub}" FontSize="11.5" Margin="2,2,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,10,0">
              <StackPanel>
                <Border Height="56" CornerRadius="10" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <TextBlock x:Name="MacroActiveTxt" Text="0" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="on" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}" VerticalAlignment="Bottom" Margin="6,0,0,5"/>
                  </StackPanel>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="2,10,0,0">
                  <TextBlock Text="&#xE73E;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource TextBrush}" Margin="0,0,7,0"/>
                  <TextBlock Text="Switched on" FontWeight="SemiBold" FontSize="13" Foreground="{DynamicResource TextBrush}"/>
                </StackPanel>
                <TextBlock Text="Macros set to run" Style="{StaticResource Sub}" FontSize="11.5" Margin="2,2,0,0"/>
              </StackPanel>
            </Border>
            <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,10,0">
              <StackPanel>
                <Border Height="56" CornerRadius="10" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1">
                  <Border HorizontalAlignment="Center" VerticalAlignment="Center" CornerRadius="6" BorderBrush="{DynamicResource SubTextBrush}" BorderThickness="1,1,1,3" Padding="12,3">
                    <TextBlock Text="F8" FontSize="15" FontWeight="Bold" Foreground="{DynamicResource TextBrush}"/>
                  </Border>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="2,10,0,0">
                  <TextBlock Text="&#xE765;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource TextBrush}" Margin="0,0,7,0"/>
                  <TextBlock Text="Pause key" FontWeight="SemiBold" FontSize="13" Foreground="{DynamicResource TextBrush}"/>
                </StackPanel>
                <TextBlock Text="Pause or resume everything" Style="{StaticResource Sub}" FontSize="11.5" Margin="2,2,0,0"/>
              </StackPanel>
            </Border>
          </UniformGrid>
          <Border Style="{StaticResource Card}" Margin="0,0,14,16" Padding="20,16,20,6">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                  <TextBlock Text="&#xE713;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                </Border>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="General" Style="{StaticResource H3}"/>
                  <TextBlock Text="Master switch and where macros may run" Style="{StaticResource Sub}" FontSize="12"/>
                </StackPanel>
              </StackPanel>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Macros" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Turns every macro on or off. Always off when Kuro starts." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <CheckBox x:Name="MacroMaster" Grid.Column="1" Style="{StaticResource Switch}" VerticalAlignment="Center"/>
                </Grid>
              </Border>
              <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                    <TextBlock Text="Roblox only" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                    <TextBlock Text="Macros only fire while Roblox is the active window." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                  </StackPanel>
                  <CheckBox x:Name="MacroRobloxOnly" Grid.Column="1" Style="{StaticResource Switch}" VerticalAlignment="Center"/>
                </Grid>
              </Border>
              <TextBlock x:Name="MacroErr" Style="{StaticResource Sub}" Foreground="{DynamicResource BadBrush}" Margin="0,0,0,10" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
          <Grid Margin="0,0,14,14">
            <Border HorizontalAlignment="Left" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="10" Padding="4">
              <StackPanel Orientation="Horizontal">
                <RadioButton x:Name="MacTabQuick" GroupName="MacTabs" Style="{StaticResource Seg}" Content="Quick macros" FontSize="13" IsChecked="True"/>
                <RadioButton x:Name="MacTabLib" GroupName="MacTabs" Style="{StaticResource Seg}" Content="Library" FontSize="13"/>
                <RadioButton x:Name="MacTabSteps" GroupName="MacTabs" Style="{StaticResource Seg}" Content="Steps" FontSize="13"/>
                <RadioButton x:Name="MacTabSet" GroupName="MacTabs" Style="{StaticResource Seg}" Content="Settings" FontSize="13"/>
                <RadioButton x:Name="MacTabShare" GroupName="MacTabs" Style="{StaticResource Seg}" Content="Share" FontSize="13"/>
              </StackPanel>
            </Border>
          </Grid>

          <!-- quick macros -->
          <StackPanel x:Name="MacPanelQuick">
            <TextBlock Text="Click a macro to open its settings. Some games do not allow macros." Style="{StaticResource Sub}" FontSize="12" Margin="2,0,0,12"/>
            <StackPanel x:Name="MacroWrap"/>
          </StackPanel>

          <!-- library -->
          <StackPanel x:Name="MacPanelLib" Visibility="Collapsed">
            <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16">
              <StackPanel>
                <Grid>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,280,0">
                    <TextBlock Text="Macro library" Style="{StaticResource H3}"/>
                    <TextBlock Text="Your own step-by-step macros. Each one has its own trigger and can be switched on by itself." Style="{StaticResource Sub}" FontSize="12" Margin="0,2,0,0"/>
                  </StackPanel>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="BtnSeqImportGo" Style="{StaticResource GhostBtn}" Content="Add shared" Padding="14,8" Margin="0,0,8,0"/>
                    <Button x:Name="BtnSeqDup" Style="{StaticResource GhostBtn}" Content="Duplicate" Padding="14,8" Margin="0,0,8,0"/>
                    <Button x:Name="BtnSeqNew" Style="{StaticResource AccentBtn}" Content="+  New macro" Padding="16,8"/>
                  </StackPanel>
                </Grid>
                <TextBlock x:Name="SeqLibEmpty" Text="No macros yet. Click New macro, then add blocks or record yourself playing." Style="{StaticResource Sub}" Margin="0,16,0,4"/>
                <StackPanel x:Name="SeqLibList" Margin="0,14,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>

          <!-- steps -->
          <StackPanel x:Name="MacPanelSteps" Visibility="Collapsed">
            <TextBlock x:Name="SeqNoneTxt" Text="Pick a macro in the Library, or click New macro there." Style="{StaticResource Sub}" Margin="2,0,0,12"/>
            <StackPanel x:Name="SeqStepsBody">
              <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16">
                <StackPanel>
                  <Grid>
                    <StackPanel VerticalAlignment="Center" Margin="0,0,250,0">
                      <TextBlock x:Name="SeqTitle" Text="Build it" Style="{StaticResource H3}"/>
                      <TextBlock Text="Record keys and clicks, or add blocks." Style="{StaticResource Sub}" FontSize="12" Margin="0,2,0,0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <Button x:Name="BtnSeqRecord" Style="{StaticResource GhostBtn}" Padding="14,8" Margin="0,0,8,0">
                        <StackPanel Orientation="Horizontal"><Ellipse x:Name="SeqRecDot" Width="8" Height="8" Fill="{DynamicResource TextBrush}" VerticalAlignment="Center" Margin="0,0,9,0"/><TextBlock x:Name="SeqRecTxt" Text="Record"/></StackPanel>
                      </Button>
                      <Button x:Name="BtnSeqTest" Style="{StaticResource GhostBtn}" Padding="14,8">
                        <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE768;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock x:Name="SeqTestTxt" Text="Test"/></StackPanel>
                      </Button>
                    </StackPanel>
                  </Grid>
                  <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                    <Border CornerRadius="10" Padding="9,3" Background="#1F3DDC84" BorderBrush="#663DDC84" BorderThickness="1">
                      <TextBlock x:Name="SeqSavedTxt" Text="saved" FontSize="11.5" FontWeight="SemiBold" Foreground="{DynamicResource GoodBrush}"/>
                    </Border>
                    <CheckBox x:Name="SeqRecPos" Style="{StaticResource Switch}" Margin="16,0,0,0" VerticalAlignment="Center">
                      <TextBlock Text="Record where I click" FontSize="12" Foreground="{DynamicResource SubTextBrush}"/>
                    </CheckBox>
                  </StackPanel>
                  <WrapPanel x:Name="SeqPalette" Margin="0,14,0,4"/>
                  <Grid Margin="0,12,0,6">
                    <TextBlock Text="One play" FontSize="12" FontWeight="SemiBold" Foreground="{DynamicResource SubTextBrush}"/>
                    <TextBlock x:Name="SeqPlayTxt" HorizontalAlignment="Right" FontSize="12" Foreground="{DynamicResource SubTextBrush}"/>
                  </Grid>
                  <Border CornerRadius="5" Height="10" Background="{DynamicResource Panel2Brush}" ClipToBounds="True">
                    <Grid x:Name="SeqTimeline"/>
                  </Border>
                  <StackPanel x:Name="SeqBlockList" Margin="0,14,0,0"/>
                </StackPanel>
              </Border>
              <Border x:Name="SeqEditorCard" Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,6">
                <StackPanel>
                  <Grid Margin="0,0,0,6">
                    <StackPanel VerticalAlignment="Center" Margin="0,0,330,0">
                      <TextBlock x:Name="SeqEdTitle" Style="{StaticResource H3}"/>
                      <TextBlock x:Name="SeqEdSub" Style="{StaticResource Sub}" FontSize="12" Margin="0,2,0,0"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                      <Button x:Name="BtnSeqUp" Style="{StaticResource GhostBtn}" Padding="11,8" Margin="0,0,6,0" ToolTip="Move up"><TextBlock Text="&#xE74A;" Style="{StaticResource Icon}" FontSize="12"/></Button>
                      <Button x:Name="BtnSeqDown" Style="{StaticResource GhostBtn}" Padding="11,8" Margin="0,0,6,0" ToolTip="Move down"><TextBlock Text="&#xE74B;" Style="{StaticResource Icon}" FontSize="12"/></Button>
                      <Button x:Name="BtnSeqCopy" Style="{StaticResource GhostBtn}" Padding="12,8" Margin="0,0,6,0">
                        <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE8C8;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,7,0"/><TextBlock Text="Copy"/></StackPanel>
                      </Button>
                      <Button x:Name="BtnSeqRemove" Style="{StaticResource GhostBtn}" Padding="12,8" Foreground="{DynamicResource BadBrush}">
                        <StackPanel Orientation="Horizontal"><TextBlock Text="&#xE74D;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,7,0"/><TextBlock Text="Remove"/></StackPanel>
                      </Button>
                    </StackPanel>
                  </Grid>
                  <StackPanel x:Name="SeqFields"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </StackPanel>

          <!-- settings of the selected macro -->
          <StackPanel x:Name="MacPanelSet" Visibility="Collapsed">
            <TextBlock x:Name="SeqSetNone" Text="Pick a macro in the Library first." Style="{StaticResource Sub}" Margin="2,0,0,12"/>
            <Border x:Name="SeqSetCard" Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,6">
              <StackPanel x:Name="SeqSetRows"/>
            </Border>
          </StackPanel>

          <!-- share -->
          <StackPanel x:Name="MacPanelShare" Visibility="Collapsed">
            <Border Style="{StaticResource Card}" Margin="0,0,14,14" Padding="20,16,20,10">
              <StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <Border Width="36" Height="36" CornerRadius="10" Background="{DynamicResource AccentSoftBrush}" Margin="0,0,12,0">
                    <TextBlock Text="&#xE72D;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center"/>
                  </Border>
                  <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="Share and download" Style="{StaticResource H3}"/>
                    <TextBlock x:Name="SeqShareSub" Text="Send or add macros" Style="{StaticResource Sub}" FontSize="12"/>
                  </StackPanel>
                </StackPanel>
                <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                      <TextBlock Text="Share this macro" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                      <TextBlock Text="A code or a .kuromacro file." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="BtnSeqSaveFile" Style="{StaticResource GhostBtn}" Padding="14,8" Margin="8,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE896;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock Text="Save file"/></StackPanel></Button><Button x:Name="BtnSeqCopyCode" Style="{StaticResource AccentBtn}" Padding="14,8" Margin="8,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE8C8;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock Text="Copy code"/></StackPanel></Button></StackPanel>
                  </Grid>
                </Border>
                <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                      <TextBlock Text="Add a shared macro" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                      <TextBlock Text="Paste a code or open a file." FontSize="12" Foreground="{DynamicResource SubTextBrush}" TextWrapping="Wrap" Margin="0,2,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center"><Button x:Name="BtnSeqOpenFile" Style="{StaticResource GhostBtn}" Padding="14,8" Margin="8,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE8B7;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock Text="Open file"/></StackPanel></Button><Button x:Name="BtnSeqPaste" Style="{StaticResource AccentBtn}" Padding="14,8" Margin="8,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE77F;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock Text="Paste code"/></StackPanel></Button></StackPanel>
                  </Grid>
                </Border>
                <Border BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,1,0,0" Padding="0,12">
                  <Grid>
                    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                    <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
                      <TextBlock Text="Download from a link" FontSize="14" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}"/>
                      <TextBlock Text="An https link to a .kuromacro file or code." FontSize="12" Foreground="{DynamicResource SubTextBrush}" Margin="0,2,0,0"/>
                    </StackPanel>
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                      <TextBox x:Name="SeqLinkIn" Style="{StaticResource Input}" Width="260" FontSize="12.5" Tag="https://..."/>
                      <Button x:Name="BtnSeqDownload" Style="{StaticResource GhostBtn}" Padding="14,8" Margin="8,0,0,0"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE896;" Style="{StaticResource Icon}" FontSize="12" Margin="0,0,8,0"/><TextBlock Text="Download"/></StackPanel></Button>
                    </StackPanel>
                  </Grid>
                </Border>
                <Border CornerRadius="9" Padding="12,9" Margin="0,8,0,4" Background="{DynamicResource AccentSoftBrush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="3,0,0,0">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE946;" Style="{StaticResource Icon}" FontSize="13" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                    <TextBlock Text="Shared macros arrive switched off, so their trigger does nothing until you turn them on." FontSize="12.5" Foreground="{DynamicResource TextBrush}"/>
                  </StackPanel>
                </Border>
                <TextBox x:Name="SeqShareOut" Visibility="Collapsed"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== TOOLS ===== -->
      <ScrollViewer x:Name="PageTools" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,18,32">
          <TextBlock Text="Tools" Style="{StaticResource H1}"/>
          <TextBlock Text="Quick maintenance actions. These run once; they are not permanent changes." Style="{StaticResource Sub}" Margin="0,4,0,20"/>
          <WrapPanel x:Name="ToolsWrap"/>
          <Border Style="{StaticResource Card}" Margin="0,4,14,0">
            <StackPanel>
              <TextBlock Text="Activity log" Style="{StaticResource H3}" Margin="0,0,0,10"/>
              <TextBox x:Name="ToolsLog" Style="{StaticResource Input}" IsReadOnly="True" Height="190" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" VerticalContentAlignment="Top" VerticalScrollBarVisibility="Auto"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== PREMIUM ===== -->
      <ScrollViewer x:Name="PagePremium" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,32,32">
          <Border CornerRadius="12" Background="{DynamicResource HeroBrush}" Padding="30,28" Margin="0,0,0,18">
            <Grid>
              <StackPanel>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE735;" FontFamily="Segoe MDL2 Assets" FontSize="26" Foreground="White" VerticalAlignment="Center" Margin="0,0,12,0"/>
                  <TextBlock Text="Kuro Premium" FontSize="30" FontWeight="Bold" Foreground="White"/>
                </StackPanel>
                <TextBlock x:Name="PremStatus" Text="You're on the Free plan" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0"/>
                <TextBlock x:Name="PremSub" Text="Redeem a one-time code to unlock every tweak, Game Boost and one-click optimize." Foreground="#DDFFFFFF" TextWrapping="Wrap" Margin="0,4,180,0"/>
              </StackPanel>
              <Image x:Name="MascotPrem" Height="170" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,-24,-6,-28" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                <TextBlock Text="&#xE77B;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                <TextBlock Text="Your account" Style="{StaticResource H3}"/>
              </StackPanel>
              <TextBlock Text="Sign up so your Premium follows you if you move to a new PC. Log in there and it restores automatically." Style="{StaticResource Sub}" Margin="0,4,0,12"/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBox x:Name="AccUser" Grid.Column="0" Style="{StaticResource Input}" MaxLength="32" FontSize="14"/>
                <PasswordBox x:Name="AccPass" Grid.Column="2" FontSize="14" Padding="12,9" MaxLength="64" Background="{DynamicResource Panel2Brush}" Foreground="{DynamicResource TextBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" VerticalContentAlignment="Center"/>
                <StackPanel Grid.Column="3" Orientation="Horizontal" Margin="12,0,0,0">
                  <Button x:Name="BtnLogin" Style="{StaticResource AccentBtn}" Content="Log in" Padding="18,9"/>
                  <Button x:Name="BtnSignup" Style="{StaticResource GhostBtn}" Content="Sign up" Padding="16,9" Margin="8,0,0,0"/>
                  <Button x:Name="BtnLogout" Style="{StaticResource GhostBtn}" Content="Log out" Padding="16,9" Margin="8,0,0,0" Visibility="Collapsed"/>
                </StackPanel>
              </Grid>
              <TextBlock Text="Username" Style="{StaticResource Sub}" FontSize="11" Margin="2,5,0,0"/>
              <Grid Margin="0,10,0,0">
                <TextBlock x:Name="AccMsg" Style="{StaticResource Sub}" FontWeight="SemiBold" VerticalAlignment="Center"/>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                  <Button x:Name="BtnDiscordRole" Style="{StaticResource AccentBtn}" Content="Get my Discord role" Padding="14,7" Margin="0,0,8,0" Visibility="Collapsed"/>
                  <Button x:Name="BtnAccountBuy" Style="{StaticResource GhostBtn}" Content="Get Premium on Discord" Padding="14,7"/>
                </StackPanel>
              </Grid>
            </StackPanel>
          </Border>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="16"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <Border Style="{StaticResource Card}" VerticalAlignment="Top">
              <StackPanel>
                <TextBlock Text="Redeem a code" Style="{StaticResource H3}"/>
                <TextBlock Text="Codes look like CCH-XXXX-XXXX-XXXX. Each code works once and is locked to the PC it is redeemed on." Style="{StaticResource Sub}" Margin="0,4,0,14"/>
                <TextBox x:Name="CodeBox" Style="{StaticResource Input}" FontFamily="Consolas" FontSize="16" CharacterCasing="Upper" MaxLength="24"/>
                <Button x:Name="BtnRedeem" Style="{StaticResource AccentBtn}" Content="Redeem code" HorizontalAlignment="Left" Margin="0,12,0,0" Padding="22,10"/>
                <TextBlock x:Name="RedeemMsg" Style="{StaticResource Sub}" Margin="0,12,0,0" FontWeight="SemiBold"/>
                <Border Height="1" Background="{DynamicResource LineBrush}" Margin="0,16,0,14"/>
                <TextBlock Text="Don't have a code yet?" Style="{StaticResource H3}"/>
                <TextBlock Text="Premium codes are sold in the Kuro Discord server." Style="{StaticResource Sub}" Margin="0,4,0,12"/>
                <Button x:Name="BtnBuyPrem" Style="{StaticResource DiscordBtn}" HorizontalAlignment="Left">
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="&#xE8BD;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <TextBlock Text="Buy a code on Discord"/>
                  </StackPanel>
                </Button>
              </StackPanel>
            </Border>
            <Border Grid.Column="2" Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="What Premium unlocks" Style="{StaticResource H3}" Margin="0,0,0,12"/>
                <StackPanel x:Name="PerksList"/>
              </StackPanel>
            </Border>
          </Grid>
        </StackPanel>
      </ScrollViewer>

      <!-- ===== THEME + SETTINGS ===== -->
      <ScrollViewer x:Name="PageTheme" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,32,32">
          <TextBlock Text="Colours, Vibes and Settings" Style="{StaticResource H1}"/>
          <TextBlock Text="Make Kuro yours. Changes apply instantly and are saved." Style="{StaticResource Sub}" Margin="0,4,0,20"/>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <StackPanel>
              <TextBlock Text="Accent colour" Style="{StaticResource H3}" Margin="0,0,0,12"/>
              <WrapPanel x:Name="AccentSwatches"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                <TextBox x:Name="HexBox" Style="{StaticResource Input}" Width="150" FontFamily="Consolas" MaxLength="7"/>
                <Button x:Name="BtnHex" Style="{StaticResource GhostBtn}" Content="Use custom colour" Margin="10,0,0,0"/>
                <Border x:Name="HexPreview" Width="38" Height="38" CornerRadius="9" Margin="10,0,0,0" Background="{DynamicResource AccentBrush}"/>
              </StackPanel>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <StackPanel>
              <TextBlock Text="Background theme" Style="{StaticResource H3}" Margin="0,0,0,12"/>
              <WrapPanel x:Name="BgSwatches"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Border Width="96" Height="96" CornerRadius="48" BorderThickness="3" BorderBrush="{DynamicResource AccentBrush}" VerticalAlignment="Top" Margin="0,0,22,0">
                <Ellipse x:Name="AvatarPreview" Fill="{DynamicResource AccentSoftBrush}"/>
              </Border>
              <StackPanel Grid.Column="1">
                <TextBlock Text="Profile picture" Style="{StaticResource H3}"/>
                <TextBlock Text="Shown at the bottom of the sidebar. Pick a Kuro character or use any picture from your PC." Style="{StaticResource Sub}" Margin="0,4,0,12"/>
                <WrapPanel x:Name="AvatarChips"/>
                <Button x:Name="BtnAvatarPick" Style="{StaticResource GhostBtn}" Content="Choose a picture from my PC..." HorizontalAlignment="Left" Margin="0,4,0,0"/>
              </StackPanel>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <Grid>
              <StackPanel Margin="0,0,210,0">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="&#xE8D6;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                  <TextBlock Text="Vibes" Style="{StaticResource H3}"/>
                </StackPanel>
                <TextBlock Text="Cute mascots and original lo-fi music made just for Kuro. Switch either off any time." Style="{StaticResource Sub}" Margin="0,4,0,14"/>
                <Grid Margin="0,0,0,10"><TextBlock Text="Show anime mascots" VerticalAlignment="Center"/><CheckBox x:Name="SetArt" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <WrapPanel x:Name="MascotChips" Margin="0,0,0,8"/>
                <Grid Margin="0,0,0,10"><TextBlock Text="Play chill lo-fi music" VerticalAlignment="Center"/><CheckBox x:Name="SetMusic" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid Margin="0,0,0,10"><TextBlock Text="Pause the music while a game is running" VerticalAlignment="Center"/><CheckBox x:Name="SetMusicGame" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid Margin="0,0,0,10"><TextBlock Text="Anime effects when a task finishes" VerticalAlignment="Center"/><CheckBox x:Name="SetFx" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid Margin="0,0,0,10"><TextBlock Text="Welcome chime when Kuro finishes loading" VerticalAlignment="Center"/><CheckBox x:Name="SetStartSound" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid Margin="0,0,0,10"><TextBlock Text="Greeting banner when Kuro opens (time of day and season)" VerticalAlignment="Center"/><CheckBox x:Name="SetGreet" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid Margin="0,0,0,10"><TextBlock Text="Bedtime reminders late at night (every 90 minutes after 23:00)" VerticalAlignment="Center"/><CheckBox x:Name="SetBedtime" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Grid x:Name="SetProofRow" Margin="0,0,0,10"><TextBlock x:Name="SetProofTxt" Text="Stream proof: hide Kuro from screenshots and screen share" VerticalAlignment="Center"/><CheckBox x:Name="SetStreamProof" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
                <Button x:Name="BtnReplayTutorial" Style="{StaticResource GhostBtn}" Content="Replay the tutorial" HorizontalAlignment="Left" Margin="0,2,0,0"/>
                <Grid Margin="0,0,0,12">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="50"/></Grid.ColumnDefinitions>
                  <TextBlock Text="Volume" VerticalAlignment="Center" Margin="0,0,16,0"/>
                  <Slider x:Name="SetVolume" Grid.Column="1" Minimum="0" Maximum="100" Style="{StaticResource VolSlider}" VerticalAlignment="Center"/>
                  <TextBlock x:Name="SetVolumeTxt" Grid.Column="2" Text="35%" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{DynamicResource SubTextBrush}"/>
                </Grid>
                <WrapPanel x:Name="TrackChips"/>
              </StackPanel>
              <Image x:Name="MascotTheme" Width="200" HorizontalAlignment="Right" VerticalAlignment="Center" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
            </Grid>
          </Border>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <StackPanel>
              <TextBlock Text="Safety" Style="{StaticResource H3}" Margin="0,0,0,12"/>
              <Grid Margin="0,0,0,12"><TextBlock Text="Create a System Restore point before the first change of the day" VerticalAlignment="Center"/><CheckBox x:Name="SetAutoRestore" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
              <Grid><TextBlock Text="Ask before applying medium-risk tweaks" VerticalAlignment="Center"/><CheckBox x:Name="SetConfirmRisky" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="License server (optional, for owners)" Style="{StaticResource H3}"/>
              <TextBlock Text="Leave empty to use the built-in Kuro server. Only change this if you run your own." Style="{StaticResource Sub}" Margin="0,4,0,12"/>
              <StackPanel Orientation="Horizontal">
                <TextBox x:Name="SetServer" Style="{StaticResource Input}" Width="420" FontSize="13"/>
                <Button x:Name="BtnSaveServer" Style="{StaticResource GhostBtn}" Content="Save" Margin="10,0,0,0"/>
              </StackPanel>
              <Grid Margin="0,12,0,0"><TextBlock Text="Count this PC in the live user numbers (anonymous: no name, IP or PC details are stored)" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,60,0"/><CheckBox x:Name="SetShareStats" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
              <TextBlock Text="Auto-update source (https URL where you host the Kuro folder)" Style="{StaticResource H3}" Margin="0,18,0,0"/>
              <TextBlock Text="Set this and users get new files automatically - they never redownload. Leave empty to turn auto-update off (see owner guide)." Style="{StaticResource Sub}" Margin="0,4,0,12"/>
              <StackPanel Orientation="Horizontal">
                <TextBox x:Name="SetUpdateUrl" Style="{StaticResource Input}" Width="420" FontSize="13"/>
                <Button x:Name="BtnSaveUpdate" Style="{StaticResource GhostBtn}" Content="Save" Margin="10,0,0,0"/>
              </StackPanel>
              <Grid Margin="0,12,0,0"><TextBlock Text="Automatically check for updates on launch" VerticalAlignment="Center"/><CheckBox x:Name="SetAutoUpdate" Style="{StaticResource Switch}" HorizontalAlignment="Right"/></Grid>
              <TextBlock x:Name="AboutTxt" Style="{StaticResource Sub}" Margin="0,18,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>
      <!-- ===== SUPPORT / ABOUT ===== -->
      <ScrollViewer x:Name="PageSupport" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel Margin="32,26,32,32">
          <Border CornerRadius="12" Background="{DynamicResource HeroBrush}" Padding="30,28" Margin="0,0,0,18">
            <Grid>
              <StackPanel Margin="0,0,200,0">
                <TextBlock Text="Support and Community" FontSize="30" FontWeight="Bold" Foreground="White"/>
                <TextBlock Text="Join the Kuro Discord to report bugs, get help with your PC, suggest new tweaks and buy Premium codes." Foreground="#E6FFFFFF" FontSize="14" TextWrapping="Wrap" Margin="0,8,0,18"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="BtnDiscord" Style="{StaticResource DiscordBtn}">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE8BD;" FontFamily="Segoe MDL2 Assets" VerticalAlignment="Center" Margin="0,0,10,0"/>
                      <TextBlock Text="Join our Discord"/>
                    </StackPanel>
                  </Button>
                  <TextBlock x:Name="DiscordLinkTxt" Text="discord.gg" Foreground="#DDFFFFFF" VerticalAlignment="Center" Margin="16,0,0,0" FontFamily="Consolas"/>
                </StackPanel>
              </StackPanel>
              <Image x:Name="MascotSupport" Height="180" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,-26,-6,-28" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
            </Grid>
          </Border>
          <UniformGrid Columns="3" Margin="-7,0,-7,16">
            <Button x:Name="BtnBug" Style="{StaticResource TileBtn}" Margin="7,0" Height="150">
              <StackPanel>
                <Border Width="40" Height="40" CornerRadius="11" Background="#26FF5A5F" HorizontalAlignment="Left">
                  <TextBlock Text="&#xEBE8;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="#FF6B6B" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="Report a bug" FontSize="15" FontWeight="SemiBold" Margin="0,12,0,0"/>
                <TextBlock Text="Copies a bug report with your PC info to the clipboard and opens Discord. Paste it in the bug-report channel." FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource SubTextBrush}" Margin="0,4,0,0"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnBuy" Style="{StaticResource TileBtn}" Margin="7,0" Height="150">
              <StackPanel>
                <Border Width="40" Height="40" CornerRadius="11" Background="{DynamicResource AccentSoftBrush}" HorizontalAlignment="Left">
                  <TextBlock Text="&#xE735;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="{DynamicResource AccentBrush}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="Buy Premium" FontSize="15" FontWeight="SemiBold" Margin="0,12,0,0"/>
                <TextBlock Text="Get a one-time Premium code from the Discord server, then redeem it on the Premium page." FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource SubTextBrush}" Margin="0,4,0,0"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnHelp" Style="{StaticResource TileBtn}" Margin="7,0" Height="150">
              <StackPanel>
                <Border Width="40" Height="40" CornerRadius="11" Background="#263B82F6" HorizontalAlignment="Left">
                  <TextBlock Text="&#xE8F2;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="#60A5FA" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock Text="Get help and suggest tweaks" FontSize="15" FontWeight="SemiBold" Margin="0,12,0,0"/>
                <TextBlock Text="Ask the community for FPS help, share your results or suggest new optimizations." FontSize="12" TextWrapping="Wrap" Foreground="{DynamicResource SubTextBrush}" Margin="0,4,0,0"/>
              </StackPanel>
            </Button>
          </UniformGrid>
          <Border Style="{StaticResource Card}" Margin="0,0,0,16">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                <Image x:Name="ChatAvatar" Width="34" Height="34" Margin="0,0,10,0"/>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="Ask Kuro" Style="{StaticResource H3}"/>
                  <TextBlock Text="Offline helper - answers common questions instantly (no internet)." Style="{StaticResource Sub}"/>
                </StackPanel>
              </StackPanel>
              <Border Background="{DynamicResource Panel2Brush}" CornerRadius="12" Padding="4" Margin="0,10,0,10">
                <ScrollViewer x:Name="ChatScroll" Height="240" VerticalScrollBarVisibility="Auto" Padding="8">
                  <StackPanel x:Name="ChatLog"/>
                </ScrollViewer>
              </Border>
              <WrapPanel x:Name="ChatChips" Margin="0,0,0,10"/>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBox x:Name="ChatInput" Style="{StaticResource Input}" Padding="12,10"/>
                <Button x:Name="BtnChatSend" Grid.Column="1" Style="{StaticResource AccentBtn}" Content="Send" Margin="10,0,0,0" Padding="18,10"/>
              </Grid>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource Card}">
            <StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,10">
                <TextBlock Text="&#xE946;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,10,0"/>
                <TextBlock Text="About Kuro" Style="{StaticResource H3}"/>
              </StackPanel>
              <TextBlock x:Name="AboutVersion" FontSize="20" FontWeight="Bold"/>
              <TextBlock Style="{StaticResource Sub}" LineHeight="20" Margin="0,6,0,0">
                <Run Text="Kuro is a free FPS optimizer made for low-end office laptops and gaming PCs. It scans your hardware, recommends tweaks that suit your PC and backs up every change so you can undo it at any time."/>
                <LineBreak/><LineBreak/>
                <Run Text="The mascots and the lo-fi tracks Cola Cafe, Midnight Mint and Sakura Rain are original works made for Kuro."/>
                <LineBreak/>
                <Run Text="Kuro is not affiliated with Roblox, Microsoft, Intel, NVIDIA, AMD or Discord."/>
              </TextBlock>
              <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
                <Button x:Name="BtnAboutLog" Style="{StaticResource GhostBtn}" Content="Open log and backup folder" Margin="0,0,10,0"/>
                <Button x:Name="BtnAboutReadme" Style="{StaticResource GhostBtn}" Content="Open README"/>
              </StackPanel>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>
    </Grid>

    <!-- ================= Overlays ================= -->
    <Canvas x:Name="FxLayer" Grid.RowSpan="2" Grid.ColumnSpan="2" IsHitTestVisible="False" ClipToBounds="True"/>
    <Border x:Name="GreetBanner" Grid.RowSpan="2" Grid.ColumnSpan="2" Panel.ZIndex="59" Visibility="Collapsed" Cursor="Hand"
            HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,14,0,0" CornerRadius="14" Padding="16,12,22,12" MaxWidth="560"
            BorderBrush="#55FFFFFF" BorderThickness="1" ToolTip="Click to close">
      <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.45" Color="#000000"/></Border.Effect>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Width="40" Height="40" CornerRadius="20" Background="#2EFFFFFF" Margin="0,0,14,0" VerticalAlignment="Center">
          <TextBlock x:Name="GreetIcon" FontFamily="Segoe UI Symbol" FontSize="20" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="GreetTitle" FontSize="15.5" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
          <TextBlock x:Name="GreetSub" FontSize="12.5" Foreground="#E6FFFFFF" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </Grid>
    </Border>
    <Border x:Name="PremBanner" Grid.RowSpan="2" Grid.ColumnSpan="2" Panel.ZIndex="60" Visibility="Collapsed" Cursor="Hand"
            HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,14,0,0" CornerRadius="14" Padding="18,12,22,12"
            BorderBrush="#66FFFFFF" BorderThickness="1" RenderTransformOrigin="0.5,0">
      <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.45" Color="#000000"/></Border.Effect>
      <StackPanel Orientation="Horizontal">
        <Border Width="38" Height="38" CornerRadius="19" Background="#33FFFFFF" Margin="0,0,14,0">
          <TextBlock Text="&#xE735;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Thanks for buying Premium!" FontSize="15.5" FontWeight="Bold" Foreground="White"/>
          <TextBlock x:Name="PremBannerSub" Text="Premium is activated. Everything is unlocked." FontSize="12.5" Foreground="#E6FFFFFF" Margin="0,2,0,0"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <Border x:Name="Toast" Grid.RowSpan="2" Grid.ColumnSpan="2" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,28,28" CornerRadius="12" Padding="18,12" Background="{DynamicResource Panel2Brush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1" Visibility="Collapsed" MaxWidth="460">
      <StackPanel Orientation="Horizontal">
        <TextBlock x:Name="ToastIcon" Text="&#xE73E;" Style="{StaticResource Icon}" Foreground="{DynamicResource AccentBrush}" Margin="0,0,12,0"/>
        <TextBlock x:Name="ToastText" Text="" TextWrapping="Wrap" MaxWidth="400" VerticalAlignment="Center"/>
      </StackPanel>
    </Border>

    <Grid x:Name="BusyLayer" Grid.RowSpan="2" Grid.ColumnSpan="2" Background="#B3000000" Visibility="Collapsed">
      <Border Style="{StaticResource Card}" HorizontalAlignment="Center" VerticalAlignment="Center" Padding="40,32" MinWidth="380">
        <StackPanel>
          <Grid Width="104" Height="104" HorizontalAlignment="Center">
            <Canvas x:Name="SpinnerCanvas" Width="104" Height="104" RenderTransformOrigin="0.5,0.5">
              <Canvas.RenderTransform><RotateTransform x:Name="BusyRotate" Angle="0" CenterX="52" CenterY="52"/></Canvas.RenderTransform>
            </Canvas>
            <Ellipse Width="62" Height="62" HorizontalAlignment="Center" VerticalAlignment="Center" Fill="{DynamicResource Panel2Brush}"/>
            <Ellipse x:Name="SpinnerFace" Width="58" Height="58" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Grid>
          <TextBlock x:Name="BusyText" Text="Working..." FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,18,0,0" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="420"/>
          <TextBlock x:Name="BusySub" Text="" Style="{StaticResource Sub}" HorizontalAlignment="Center" TextAlignment="Center" Margin="0,6,0,0" MaxWidth="420"/>
        </StackPanel>
      </Border>
    </Grid>

    <Grid x:Name="ScanLayer" Grid.RowSpan="2" Grid.ColumnSpan="2" Background="#0F1112" Visibility="Collapsed" Panel.ZIndex="40">
      <Ellipse x:Name="ScanGlow" Width="640" Height="640" HorizontalAlignment="Center" VerticalAlignment="Center" IsHitTestVisible="False"/>
      <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
        <Grid Width="150" Height="150" HorizontalAlignment="Center" Margin="0,8,0,0">
          <Canvas x:Name="ScanTicks" HorizontalAlignment="Left" VerticalAlignment="Top"/>
          <Ellipse Width="140" Height="140" Stroke="#1CFFFFFF" StrokeThickness="3.5" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          <Path x:Name="ScanArc" StrokeThickness="3.5" StrokeStartLineCap="Round" StrokeEndLineCap="Round" HorizontalAlignment="Left" VerticalAlignment="Top"/>
          <Canvas HorizontalAlignment="Left" VerticalAlignment="Top">
            <Ellipse x:Name="ScanHead" Width="9" Height="9" Fill="#FFF4DC"/>
          </Canvas>
          <Border x:Name="ScanIcon" Width="84" Height="84" CornerRadius="20" HorizontalAlignment="Center" VerticalAlignment="Center" BorderBrush="#24FFFFFF" BorderThickness="1" Background="#1A1D20" RenderTransformOrigin="0.5,0.5"/>
        </Grid>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,22,0,0">
          <TextBlock Text="Kuro" FontSize="26" FontWeight="Bold" Foreground="#F4F4F2" VerticalAlignment="Center"/>
          <Border x:Name="ScanBadge" CornerRadius="6" Padding="7,2" Margin="10,3,0,0" VerticalAlignment="Center" BorderThickness="1">
            <TextBlock x:Name="ScanVer" Text="V0" FontSize="11" FontWeight="Bold"/>
          </Border>
        </StackPanel>
        <TextBlock x:Name="ScanRpm" Text="0 RPM" FontFamily="Consolas" FontSize="12" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,8,0,0"/>
        <TextBlock x:Name="ScanStatus" Text="Starting..." FontSize="13" Foreground="#8E949C" HorizontalAlignment="Center" Margin="0,4,0,0"/>
      </StackPanel>
    </Grid>

    <Grid x:Name="TutorialLayer" Grid.RowSpan="2" Grid.ColumnSpan="2" Background="#CC000000" Visibility="Collapsed" Panel.ZIndex="50">
      <Border HorizontalAlignment="Center" VerticalAlignment="Center" Width="460" CornerRadius="18" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="2" Padding="0">
        <StackPanel>
          <Grid>
            <Border CornerRadius="16,16,0,0" Height="118" Background="{DynamicResource HeroBrush}"/>
            <Image x:Name="TutorialImg" Height="150" HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,-6" Stretch="Uniform" RenderOptions.BitmapScalingMode="HighQuality"/>
          </Grid>
          <StackPanel Margin="28,18,28,24">
            <TextBlock x:Name="TutorialTitle" Text="" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center" TextAlignment="Center"/>
            <TextBlock x:Name="TutorialBody" Text="" Style="{StaticResource Sub}" FontSize="14" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,10,0,0" LineHeight="21" MinHeight="72"/>
            <TextBlock x:Name="TutorialStep" Text="" FontSize="12" Foreground="{DynamicResource SubTextBrush}" HorizontalAlignment="Center" Margin="0,14,0,14"/>
            <Grid>
              <Button x:Name="BtnTutSkip" Style="{StaticResource GhostBtn}" Content="Skip" HorizontalAlignment="Left" Padding="18,9"/>
              <Button x:Name="BtnTutNext" Style="{StaticResource AccentBtn}" Content="Next" HorizontalAlignment="Right" Padding="24,9"/>
            </Grid>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>

    <Grid x:Name="ModalLayer" Grid.RowSpan="2" Grid.ColumnSpan="2" Background="#B3000000" Visibility="Collapsed">
      <Border Style="{StaticResource Card}" HorizontalAlignment="Center" VerticalAlignment="Center" Padding="28,24" Width="480">
        <StackPanel>
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="ModalIcon" Text="&#xE7BA;" Style="{StaticResource Icon}" FontSize="20" Foreground="{DynamicResource WarnBrush}" Margin="0,0,12,0"/>
            <TextBlock x:Name="ModalTitle" Text="Are you sure?" FontSize="18" FontWeight="Bold"/>
          </StackPanel>
          <TextBlock x:Name="ModalMsg" Style="{StaticResource Sub}" Margin="0,12,0,20" LineHeight="20"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="ModalNo" Style="{StaticResource GhostBtn}" Content="Cancel" Margin="0,0,10,0"/>
            <Button x:Name="ModalYes" Style="{StaticResource AccentBtn}" Content="Continue"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

function Start-Kuro {
    Load-Settings
    Load-Backup

    $win = [Windows.Markup.XamlReader]::Parse($Global:MainXaml)
    $win.Dispatcher.Add_UnhandledException({
        Write-Log ('UI error: ' + $_.Exception.Message)
        $_.Handled = $true
        try { Show-Toast ('Something went wrong: ' + $_.Exception.Message) 'error' } catch { }
    })
    $Global:CCH.Window = $win
    foreach ($m in [regex]::Matches($Global:MainXaml, 'x:Name="([A-Za-z0-9_]+)"')) {
        $n = $m.Groups[1].Value
        $el = $win.FindName($n)
        if ($el) { $Global:UI[$n] = $el }
    }

    $icon = Join-Path $Global:AppDir 'assets\Kuro.ico'
    if (Test-Path $icon) { try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $icon)) } catch { } }

    Build-Swatches
    Apply-Theme
    Build-Tools
    Connect-Events
    Init-Music
    Connect-Vibes
    Connect-Support
    Connect-Avatar
    Connect-Chat
    Connect-Account
    Connect-Macros
    try { Connect-RobloxGfx } catch { Write-Log "Roblox graphics page failed: $($_.Exception.Message)" }
    try { Connect-Ping } catch { Write-Log "Ping page failed: $($_.Exception.Message)" }
    try { Connect-Cross } catch { Write-Log "Crosshair page failed: $($_.Exception.Message)" }
    try { Connect-GameBar } catch { Write-Log "Game Bar failed: $($_.Exception.Message)" }
    try { Initialize-PremiumLocks } catch { Write-Log "Premium locks failed: $($_.Exception.Message)" }
    $Global:UI.BtnDiscordRole.Add_Click({ Get-DiscordRoleCode })
    Connect-Tutorial
    Init-Spinner
    Update-Mascots
    Update-MusicUI
    Init-Perf
    $Global:UI.AboutTxt.Text = "Kuro v$($Global:CCH_Version)  -  $($Global:Tweaks.Count) optimizations  -  data folder: $($Global:DataDir)"
    Write-Log "Kuro $($Global:CCH_Version) started."

    $Global:UsageTimer = New-Object Windows.Threading.DispatcherTimer
    $Global:UsageTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
    $Global:UsageTimer.Add_Tick({
        $Global:Perf.Tick++
        if ($Global:UI.PageDash.Visibility -eq 'Visible' -and $Global:CCH.Window.WindowState -ne 'Minimized') { try { Update-Usage } catch { } }
    })

    $Global:BoostTimer = New-Object Windows.Threading.DispatcherTimer
    $Global:BoostTimer.Interval = [TimeSpan]::FromSeconds(4)
    $Global:BoostTimer.Add_Tick({
        try {
            $games = @(Update-BoostGames)
            Invoke-VibesTick $games
            if ($Global:CCH.Boost.On) { Invoke-BoostTick }
            if ($Global:CCH.Premium -and -not (Test-ScriptIntegrity)) {
                $Global:CCH.Premium = $false; $Global:CCH.Tampered = $true
                foreach ($t in $Global:Tweaks) { Refresh-Tweak $t }
                Update-MusicUI
                Show-Toast 'This copy of Kuro was modified, so Premium has been locked.' 'error'
            }
        } catch { }
    })

    $win.Add_ContentRendered({
        try {
            Invoke-FullScan
            Set-BusyText 'Building interface...' 93
            Build-Cards
            Update-PremiumUI
            Update-AllViews
            Update-BoostUI
        } catch {
            Write-Log "Startup error: $($_.Exception.Message)"
            Hide-Busy; Hide-ScanLayer
            Show-Fatal 'Startup problem' $_
        }
        Hide-Busy
        Complete-ScanLayer { Invoke-AfterStartup }
    })

    Show-ScanLayer 'Starting...'
    [void]$win.ShowDialog()
}

# runs once the loading ring has finished and faded out
function Invoke-AfterStartup {
    if ($Global:CCH.Settings.VibesMusic) { try { Start-Music } catch { Write-Log "Music error: $($_.Exception.Message)" } }
    try { Start-UpdateCheck } catch { Write-Log "Update check error: $($_.Exception.Message)" }
    try { Update-LegacyShortcuts } catch { }
    try { Start-LiveStats } catch { Write-Log "Live stats error: $($_.Exception.Message)" }
    try { Start-Greetings } catch { Write-Log "Greeting error: $($_.Exception.Message)" }
    $Global:UsageTimer.Start()
    $Global:BoostTimer.Start()
    if (-not $Global:CCH.Settings.ShortcutDone) {
        try { New-AppShortcuts } catch { Write-Log "Shortcut creation failed: $($_.Exception.Message)" }
        $Global:CCH.Settings.ShortcutDone = $true; Save-Settings
    }
    if ($Global:CCH.Tampered) {
        Show-Toast 'This copy of Kuro looks modified, so Premium is locked. Download a fresh copy from the Discord to use Premium.' 'error'
    } elseif (-not (Test-Path $Global:BackupFile)) {
        Show-Toast "Scan complete: $($Global:CCH.Scan.Class). Recommended tweaks are marked in green." 'info'
    }
    if (-not $Global:CCH.Settings.TutorialDone) { try { Start-Tutorial } catch { Write-Log "Tutorial error: $($_.Exception.Message)" } }
    else { Start-TipLoop }
}

try {
    $null = Start-Kuro
} catch {
    Show-Fatal 'Could not start' $_
}
if ($Global:CCH_Debug) { try { Stop-Transcript | Out-Null } catch { }; Write-Host 'Kuro closed. You can copy any red error text above.' -ForegroundColor Yellow }
