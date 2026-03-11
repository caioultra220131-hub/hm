[CmdletBinding()]
param(
    [string]$ThreadName,
    [string]$ExecutorThreadName,
    [string]$Message,
    [string]$WindowTitleRegex,
    [double]$ComposerClickXRatio = 0.470,
    [double]$ComposerClickYRatio = 0.905
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ('ThreadWork.NativeMethods' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace ThreadWork
{
    public static class NativeMethods
    {
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

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

function Get-CurrentPattern {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [System.Windows.Automation.AutomationPattern]$Pattern
    )

    $patternObject = $null
    if ($Element -and $Element.TryGetCurrentPattern($Pattern, [ref]$patternObject)) {
        return $patternObject
    }

    return $null
}

function Get-ForegroundWindowElement {
    $handle = [ThreadWork.NativeMethods]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        return $null
    }

    try {
        return [System.Windows.Automation.AutomationElement]::FromHandle($handle)
    }
    catch {
        return $null
    }
}

function Get-TopLevelWindows {
    param([string]$TitleRegex)

    $allChildren = [System.Windows.Automation.AutomationElement]::RootElement.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )

    $windows = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    foreach ($child in $allChildren) {
        if ($child.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($child.Current.Name)) {
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($TitleRegex) -and $child.Current.Name -notmatch $TitleRegex) {
            continue
        }

        $windows.Add($child)
    }

    return $windows
}

function Get-SearchRoots {
    param([string]$TitleRegex)

    $roots = New-Object System.Collections.Generic.List[System.Windows.Automation.AutomationElement]
    $foregroundWindow = Get-ForegroundWindowElement
    if ($foregroundWindow) {
        $roots.Add($foregroundWindow)
    }

    foreach ($window in (Get-TopLevelWindows -TitleRegex $TitleRegex)) {
        if ($foregroundWindow -and $window.Current.NativeWindowHandle -eq $foregroundWindow.Current.NativeWindowHandle) {
            continue
        }

        $roots.Add($window)
    }

    if ($roots.Count -eq 0) {
        $roots.Add([System.Windows.Automation.AutomationElement]::RootElement)
    }

    return $roots
}

function Get-ThreadAliases {
    param([string]$Name)

    switch -Regex ($Name.Trim()) {
        '^Test$' { return @('Test', 'T') }
        '^T$' { return @('T', 'Test') }
        default { return @($Name) }
    }
}

function Get-ControlTypeRank {
    param([System.Windows.Automation.AutomationElement]$Element)

    switch ($Element.Current.ControlType.ProgrammaticName) {
        'ControlType.ListItem' { return 0 }
        'ControlType.TabItem' { return 1 }
        'ControlType.Button' { return 2 }
        'ControlType.TreeItem' { return 3 }
        default { return 4 }
    }
}

function Test-IsSidebarCandidate {
    param([System.Windows.Rect]$Bounds)

    return (
        $Bounds.Left -ge 0 -and
        $Bounds.Left -lt 500 -and
        $Bounds.Top -ge 0 -and
        $Bounds.Width -gt 80 -and
        $Bounds.Width -lt 500
    )
}

function Find-ThreadElement {
    param(
        [string]$Name,
        [string]$TitleRegex
    )

    $controlTypeConditions = @(
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Button
        )),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::ListItem
        )),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TreeItem
        )),
        (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        ))
    )

    $candidateCondition = New-Object System.Windows.Automation.OrCondition($controlTypeConditions)
    $aliases = Get-ThreadAliases -Name $Name

    $matches = @()
    foreach ($root in (Get-SearchRoots -TitleRegex $TitleRegex)) {
        $candidates = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $candidateCondition)
        foreach ($candidate in $candidates) {
            if ($candidate.Current.IsOffscreen) {
                continue
            }

            $bounds = $candidate.Current.BoundingRectangle
            if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
                continue
            }

            foreach ($alias in $aliases) {
                $candidateName = $candidate.Current.Name
                $isExactMatch = $candidateName -eq $alias
                $isPrefixMatch = $candidateName.StartsWith($alias, [System.StringComparison]::OrdinalIgnoreCase)

                if ($isExactMatch -or $isPrefixMatch) {
                    $matches += [pscustomobject]@{
                        Element          = $candidate
                        Name             = $candidateName
                        MatchRank        = if ($isExactMatch) { 0 } else { 1 }
                        SidebarRank      = if (Test-IsSidebarCandidate -Bounds $bounds) { 0 } else { 1 }
                        ControlTypeRank  = Get-ControlTypeRank -Element $candidate
                        Left             = $bounds.Left
                        Top              = $bounds.Top
                        NameLength       = $candidateName.Length
                    }
                }
            }
        }
    }

    if (-not $matches) {
        return $null
    }

    return (
        $matches |
        Sort-Object -Property @(
            @{ Expression = 'MatchRank'; Descending = $false },
            @{ Expression = 'SidebarRank'; Descending = $false },
            @{ Expression = 'ControlTypeRank'; Descending = $false },
            @{ Expression = 'Left'; Descending = $false },
            @{ Expression = 'Top'; Descending = $false },
            @{ Expression = 'NameLength'; Descending = $false }
        ) |
        Select-Object -First 1
    ).Element
}

function Get-ContainingWindow {
    param([System.Windows.Automation.AutomationElement]$Element)

    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $current = $Element
    while ($current) {
        if ($current.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) {
            return $current
        }

        $current = $walker.GetParent($current)
    }

    return $null
}

function Activate-Window {
    param([System.Windows.Automation.AutomationElement]$Window)

    if (-not $Window) {
        return
    }

    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    if ($handle -eq [IntPtr]::Zero) {
        return
    }

    [ThreadWork.NativeMethods]::ShowWindow($handle, 5) | Out-Null
    [ThreadWork.NativeMethods]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 200
}

function Click-ElementCenter {
    param([System.Windows.Automation.AutomationElement]$Element)

    $bounds = $Element.Current.BoundingRectangle
    $centerX = [int][Math]::Round($bounds.Left + ($bounds.Width / 2))
    $centerY = [int][Math]::Round($bounds.Top + ($bounds.Height / 2))

    [ThreadWork.NativeMethods]::SetCursorPos($centerX, $centerY) | Out-Null
    Start-Sleep -Milliseconds 100
    [ThreadWork.NativeMethods]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [ThreadWork.NativeMethods]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
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

function Click-ThreadHotspot {
    param([System.Windows.Automation.AutomationElement]$Element)

    $bounds = $Element.Current.BoundingRectangle
    $targetX = [int][Math]::Round($bounds.Left + [Math]::Min(80, $bounds.Width * 0.25))
    $targetY = [int][Math]::Round($bounds.Top + ($bounds.Height / 2))

    Click-ScreenPoint -X $targetX -Y $targetY
}

function Click-ComposerHotspot {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [double]$XRatio,
        [double]$YRatio
    )

    if (-not $Window) {
        return
    }

    $bounds = $Window.Current.BoundingRectangle
    if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
        return
    }

    $targetX = [int][Math]::Round($bounds.Left + ($bounds.Width * $XRatio))
    $targetY = [int][Math]::Round($bounds.Top + ($bounds.Height * $YRatio))

    Click-ScreenPoint -X $targetX -Y $targetY
}

function Open-ThreadElement {
    param([System.Windows.Automation.AutomationElement]$Element)

    if ($Element.Current.ControlType -eq [System.Windows.Automation.ControlType]::ListItem -and (Test-IsSidebarCandidate -Bounds $Element.Current.BoundingRectangle)) {
        Click-ThreadHotspot -Element $Element
        return
    }

    $invokePattern = Get-CurrentPattern -Element $Element -Pattern ([System.Windows.Automation.InvokePattern]::Pattern)
    if ($invokePattern) {
        ([System.Windows.Automation.InvokePattern]$invokePattern).Invoke()
        return
    }

    $selectionPattern = Get-CurrentPattern -Element $Element -Pattern ([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if ($selectionPattern) {
        ([System.Windows.Automation.SelectionItemPattern]$selectionPattern).Select()
        return
    }

    try {
        $Element.SetFocus()
    }
    catch {
        Write-Verbose "Thread element does not accept focus; using direct click fallback."
    }

    Click-ElementCenter -Element $Element
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

    Set-Clipboard -Value $Text
    Start-Sleep -Milliseconds 120
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 180

    if ($hadClipboardText) {
        Set-Clipboard -Value $previousClipboardText
    }
}

function Send-ThreadMessage {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string]$Text,
        [double]$ComposerXRatio,
        [double]$ComposerYRatio
    )

    Activate-Window -Window $Window
    Click-ComposerHotspot -Window $Window -XRatio $ComposerXRatio -YRatio $ComposerYRatio
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
        [System.Windows.Forms.SendKeys]::SendWait((Convert-ToSendKeysLiteral -Text $Text))
        Start-Sleep -Milliseconds 150
    }

    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
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

Write-Host "Searching for thread '$resolvedThreadName'..."
$threadElement = Find-ThreadElement -Name $resolvedThreadName -TitleRegex $resolvedWindowTitleRegex
if (-not $threadElement) {
    $scopeDescription = if ([string]::IsNullOrWhiteSpace($resolvedWindowTitleRegex)) {
        'the foreground window and top-level windows'
    }
    else {
        "windows matching /$resolvedWindowTitleRegex/"
    }

    throw "Could not find thread '$resolvedThreadName' in $scopeDescription."
}

$threadWindow = Get-ContainingWindow -Element $threadElement
Activate-Window -Window $threadWindow
Open-ThreadElement -Element $threadElement

Write-Host "Opened thread '$resolvedThreadName'. Waiting 5 seconds..."
Start-Sleep -Seconds 5

$activeWindow = Get-ForegroundWindowElement
if (-not $activeWindow) {
    $activeWindow = $threadWindow
}

if (-not $activeWindow) {
    throw 'Could not resolve the target window after opening the thread.'
}

Write-Host "Sending message: $resolvedMessage"
Send-ThreadMessage -Window $activeWindow -Text $resolvedMessage -ComposerXRatio $ComposerClickXRatio -ComposerYRatio $ComposerClickYRatio
Write-Host "Wake-up message sent to thread '$resolvedThreadName'."
