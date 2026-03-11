[CmdletBinding()]
param(
    [string]$ThreadName,
    [string]$ExecutorThreadName,
    [string]$Message,
    [string]$WindowTitleRegex
)

$rootScript = Join-Path $PSScriptRoot '..\run-thread-work.ps1'
if (-not (Test-Path -LiteralPath $rootScript)) {
    throw "Root script not found: $rootScript"
}

& $rootScript @PSBoundParameters
