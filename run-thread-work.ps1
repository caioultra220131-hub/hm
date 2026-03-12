[CmdletBinding()]
param(
    [string]$ThreadName,
    [string]$ExecutorThreadName,
    [string]$Message,
    [string]$WindowTitleRegex,
    [double]$ComposerClickXRatio = 0.470,
    [double]$ComposerClickYRatio = 0.800,
    [ValidateRange(1, 10)]
    [int]$SelectionAttempts = 1,
    [ValidateRange(200, 10000)]
    [int]$SelectionTimeoutMs = 1200,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms

$script:ThreadWorkLogPath = if ([string]::IsNullOrWhiteSpace($LogPath)) {
    Join-Path $PSScriptRoot 'tmp\thread-work-last.log'
}
else {
    $LogPath
}
$script:ThreadWorkMutex = $null
$script:ThreadWorkMutexAcquired = $false

function Write-ThreadWorkLog {
    param([string]$Message)

    try {
        $logDirectory = Split-Path -Path $script:ThreadWorkLogPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not (Test-Path -LiteralPath $logDirectory)) {
            New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        }

        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK'
        Add-Content -LiteralPath $script:ThreadWorkLogPath -Value "[$timestamp] $Message"
    }
    catch {
        # Logging must never block the wake-up flow.
    }
}

function Get-ThreadWorkMutexName {
    $workspaceKey = ($PSScriptRoot -replace '[^A-Za-z0-9]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($workspaceKey)) {
        $workspaceKey = 'workspace'
    }

    return "Local\CodexThreadWork_$workspaceKey"
}

function Enter-ThreadWorkMutex {
    $mutexName = Get-ThreadWorkMutexName
    $script:ThreadWorkMutex = New-Object System.Threading.Mutex($false, $mutexName)

    try {
        $script:ThreadWorkMutexAcquired = $script:ThreadWorkMutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $script:ThreadWorkMutexAcquired = $true
    }

    if (-not $script:ThreadWorkMutexAcquired) {
        throw 'Another run-thread-work.ps1 instance is already active. Wait for it to finish or terminate the stuck wake-up process before retrying.'
    }
}

function Exit-ThreadWorkMutex {
    if ($script:ThreadWorkMutexAcquired -and $script:ThreadWorkMutex) {
        try {
            $script:ThreadWorkMutex.ReleaseMutex()
        }
        catch {
            # Ignore release errors during shutdown.
        }
    }

    if ($script:ThreadWorkMutex) {
        $script:ThreadWorkMutex.Dispose()
    }

    $script:ThreadWorkMutex = $null
    $script:ThreadWorkMutexAcquired = $false
}

if (-not ('ThreadWork.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ThreadWork
{
    public static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    }
}
'@
}

function Get-ThreadWorkConfig {
    $configPath = Join-Path $PSScriptRoot 'thread-work.config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        return $null
    }

    return Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
}

function Resolve-Setting {
    param(
        [string]$ExplicitValue,
        [object]$Config,
        [string]$PropertyName,
        [string]$DefaultValue
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }

    if ($null -ne $Config -and $null -ne $Config.PSObject.Properties[$PropertyName]) {
        $configValue = [string]$Config.$PropertyName
        if (-not [string]::IsNullOrWhiteSpace($configValue)) {
            return $configValue
        }
    }

    return $DefaultValue
}

function Get-ThreadAliases {
    param([string]$Name)

    switch -Regex ($Name.Trim()) {
        '^Test$' { return @('Test', 'T') }
        '^T$' { return @('T', 'Test') }
        default { return @($Name) }
    }
}

function Get-DefaultThreadTargets {
    # Default layout assumes four Codex windows snapped in a stable 2x2 grid.
    # The final click point is resolved inside each window rectangle by the
    # composer ratios, so the click lands in the thread input box instead of
    # the window center.
    return @{
        H    = [pscustomobject]@{ LeftRatio = 0.000; TopRatio = 0.000; WidthRatio = 0.500; HeightRatio = 0.500; ComposerYRatio = 0.800 }
        A    = [pscustomobject]@{ LeftRatio = 0.500; TopRatio = 0.000; WidthRatio = 0.500; HeightRatio = 0.500; ComposerYRatio = 0.800 }
        B    = [pscustomobject]@{ LeftRatio = 0.000; TopRatio = 0.500; WidthRatio = 0.500; HeightRatio = 0.500; ComposerYRatio = 0.840 }
        T    = [pscustomobject]@{ LeftRatio = 0.500; TopRatio = 0.500; WidthRatio = 0.500; HeightRatio = 0.500; ComposerYRatio = 0.840 }
        Test = [pscustomobject]@{ LeftRatio = 0.500; TopRatio = 0.500; WidthRatio = 0.500; HeightRatio = 0.500; ComposerYRatio = 0.840 }
    }
}

function Merge-ThreadTargets {
    param(
        [hashtable]$BaseTargets,
        [object]$ConfigTargets
    )

    $merged = @{}
    foreach ($key in $BaseTargets.Keys) {
        $merged[$key] = $BaseTargets[$key]
    }

    if ($null -eq $ConfigTargets) {
        return $merged
    }

    foreach ($property in $ConfigTargets.PSObject.Properties) {
        $merged[$property.Name] = $property.Value
    }

    return $merged
}

function Get-TargetPropertyValue {
    param(
        [object]$Target,
        [string[]]$Names
    )

    if ($null -eq $Target) {
        return $null
    }

    if ($Target -is [hashtable]) {
        foreach ($name in $Names) {
            if ($Target.ContainsKey($name)) {
                return $Target[$name]
            }
        }
    }

    foreach ($name in $Names) {
        $property = $Target.PSObject.Properties[$name]
        if ($null -ne $property) {
            return $property.Value
        }
    }

    return $null
}

function Resolve-ThreadTargetPoint {
    param(
        [string]$Name,
        [object]$Config,
        [double]$ComposerXRatio,
        [double]$ComposerYRatio
    )

    $targets = Get-DefaultThreadTargets
    if ($null -ne $Config -and $null -ne $Config.PSObject.Properties['ThreadTargets']) {
        $targets = Merge-ThreadTargets -BaseTargets $targets -ConfigTargets $Config.ThreadTargets
    }

    $target = $null
    foreach ($alias in (Get-ThreadAliases -Name $Name)) {
        if ($targets.ContainsKey($alias)) {
            $target = $targets[$alias]
            break
        }
    }

    if ($null -eq $target) {
        throw "No coordinate target was configured for thread '$Name'."
    }

    $screenBounds = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    $xValue = Get-TargetPropertyValue -Target $target -Names @('X', 'x')
    $yValue = Get-TargetPropertyValue -Target $target -Names @('Y', 'y')
    if ($null -ne $xValue -and $null -ne $yValue) {
        return [pscustomobject]@{
            X = [int][Math]::Round([double]$xValue)
            Y = [int][Math]::Round([double]$yValue)
        }
    }

    $xRatio = Get-TargetPropertyValue -Target $target -Names @('XRatio', 'xRatio', 'x_ratio')
    $yRatio = Get-TargetPropertyValue -Target $target -Names @('YRatio', 'yRatio', 'y_ratio')
    if ($null -ne $xRatio -and $null -ne $yRatio) {
        return [pscustomobject]@{
            X = [int][Math]::Round($screenBounds.Left + ($screenBounds.Width * [double]$xRatio))
            Y = [int][Math]::Round($screenBounds.Top + ($screenBounds.Height * [double]$yRatio))
        }
    }

    $leftRatio = Get-TargetPropertyValue -Target $target -Names @('LeftRatio', 'leftRatio', 'left_ratio')
    $topRatio = Get-TargetPropertyValue -Target $target -Names @('TopRatio', 'topRatio', 'top_ratio')
    $widthRatio = Get-TargetPropertyValue -Target $target -Names @('WidthRatio', 'widthRatio', 'width_ratio')
    $heightRatio = Get-TargetPropertyValue -Target $target -Names @('HeightRatio', 'heightRatio', 'height_ratio')
    if ($null -eq $leftRatio -or $null -eq $topRatio -or $null -eq $widthRatio -or $null -eq $heightRatio) {
        throw "Thread '$Name' target must define either X/Y, XRatio/YRatio, or LeftRatio/TopRatio/WidthRatio/HeightRatio."
    }

    $resolvedComposerXRatio = Get-TargetPropertyValue -Target $target -Names @('ComposerXRatio', 'composerXRatio', 'composer_x_ratio')
    if ($null -eq $resolvedComposerXRatio) {
        $resolvedComposerXRatio = $ComposerXRatio
    }

    $resolvedComposerYRatio = Get-TargetPropertyValue -Target $target -Names @('ComposerYRatio', 'composerYRatio', 'composer_y_ratio')
    if ($null -eq $resolvedComposerYRatio) {
        $resolvedComposerYRatio = $ComposerYRatio
    }

    $windowLeft = $screenBounds.Left + ($screenBounds.Width * [double]$leftRatio)
    $windowTop = $screenBounds.Top + ($screenBounds.Height * [double]$topRatio)
    $windowWidth = $screenBounds.Width * [double]$widthRatio
    $windowHeight = $screenBounds.Height * [double]$heightRatio

    return [pscustomobject]@{
        X = [int][Math]::Round($windowLeft + ($windowWidth * [double]$resolvedComposerXRatio))
        Y = [int][Math]::Round($windowTop + ($windowHeight * [double]$resolvedComposerYRatio))
    }
}

function Click-ScreenPoint {
    param(
        [int]$X,
        [int]$Y
    )

    [ThreadWork.NativeMethods]::SetCursorPos($X, $Y) | Out-Null
    Start-Sleep -Milliseconds 100
    [ThreadWork.NativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [ThreadWork.NativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
}

function Convert-ToSendKeysLiteral {
    param([string]$Text)

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Text.ToCharArray()) {
        switch ($character) {
            '+' { [void]$builder.Append('{+}') }
            '^' { [void]$builder.Append('{^}') }
            '%' { [void]$builder.Append('{%}') }
            '~' { [void]$builder.Append('{~}') }
            '(' { [void]$builder.Append('{(}') }
            ')' { [void]$builder.Append('{)}') }
            default { [void]$builder.Append($character) }
        }
    }

    return $builder.ToString()
}

function Send-TextByPaste {
    param([string]$Text)

    $hadClipboardText = $false
    $previousClipboardText = $null

    try {
        $previousClipboardText = Get-Clipboard -Raw -ErrorAction Stop
        $hadClipboardText = $true
    }
    catch {
        $hadClipboardText = $false
    }

    Write-ThreadWorkLog "Setting clipboard text: $Text"
    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 120
    Write-ThreadWorkLog 'Sending Ctrl+V to paste.'
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 180

    if ($hadClipboardText) {
        Write-ThreadWorkLog 'Restoring previous clipboard text.'
        Set-Clipboard -Value $previousClipboardText
    }
}

function Send-ThreadMessage {
    param(
        [int]$X,
        [int]$Y,
        [string]$Text
    )

    Write-ThreadWorkLog "Clicking thread composer at ($X,$Y)."
    Click-ScreenPoint -X $X -Y $Y
    Start-Sleep -Milliseconds 300

    $pasted = $false
    try {
        Send-TextByPaste -Text $Text
        $pasted = $true
    }
    catch {
        Write-Warning 'Clipboard paste failed. Falling back to direct SendKeys.'
    }

    if (-not $pasted) {
        Write-ThreadWorkLog 'Paste failed; falling back to direct SendKeys text input.'
        [System.Windows.Forms.SendKeys]::SendWait((Convert-ToSendKeysLiteral -Text $Text))
        Start-Sleep -Milliseconds 150
    }

    Write-ThreadWorkLog 'Sending Enter key.'
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Write-ThreadWorkLog 'Send pipeline completed.'
}

$config = Get-ThreadWorkConfig
$resolvedThreadName = Resolve-Setting -ExplicitValue $ThreadName -Config $config -PropertyName 'TargetThreadName' -DefaultValue ''
$resolvedExecutor = Resolve-Setting -ExplicitValue $ExecutorThreadName -Config $config -PropertyName 'ExecutorThreadName' -DefaultValue ''
$resolvedBaseMessage = Resolve-Setting -ExplicitValue $Message -Config $config -PropertyName 'Message' -DefaultValue 'work run'
$resolvedWindowTitleRegex = Resolve-Setting -ExplicitValue $WindowTitleRegex -Config $config -PropertyName 'WindowTitleRegex' -DefaultValue ''

if ([string]::IsNullOrWhiteSpace($resolvedThreadName)) {
    throw 'No thread name was provided. Pass -ThreadName or add TargetThreadName to thread-work.config.json.'
}

$resolvedMessage = if ([string]::IsNullOrWhiteSpace($resolvedExecutor)) {
    $resolvedBaseMessage
}
else {
    "$resolvedBaseMessage, $resolvedExecutor finish"
}

try {
    Enter-ThreadWorkMutex
    Set-Content -LiteralPath $script:ThreadWorkLogPath -Value ''
    Write-ThreadWorkLog "Thread wake-up started. target=$resolvedThreadName executor=$resolvedExecutor message=$resolvedMessage"

    if (-not [string]::IsNullOrWhiteSpace($resolvedWindowTitleRegex)) {
        Write-ThreadWorkLog "WindowTitleRegex '$resolvedWindowTitleRegex' is ignored in fixed-coordinate mode."
    }

    if ($SelectionAttempts -ne 1 -or $SelectionTimeoutMs -ne 1200) {
        Write-ThreadWorkLog 'SelectionAttempts and SelectionTimeoutMs are ignored in fixed-coordinate mode.'
    }

    $targetPoint = Resolve-ThreadTargetPoint `
        -Name $resolvedThreadName `
        -Config $config `
        -ComposerXRatio $ComposerClickXRatio `
        -ComposerYRatio $ComposerClickYRatio
    Write-Host "Clicking thread '$resolvedThreadName' composer at ($($targetPoint.X), $($targetPoint.Y))..."
    Send-ThreadMessage -X $targetPoint.X -Y $targetPoint.Y -Text $resolvedMessage
    Write-Host "Wake-up message sent to thread '$resolvedThreadName'."
}
catch {
    Write-ThreadWorkLog "ERROR: $($_.Exception.Message)"
    throw
}
finally {
    Exit-ThreadWorkMutex
}
