<#
.SYNOPSIS
    Upload the config and macros in this repo to a FluidNC controller.

.EXAMPLE
    .\tools\deploy.ps1 -Board 192.168.0.23
    .\tools\deploy.ps1 -Board 192.168.0.23 -Restart
    .\tools\deploy.ps1 -Board 192.168.0.23 -Restart -Yes

.NOTES
    Uses curl.exe, which ships with Windows 10 1803 and later. Files go to the
    controller's internal flash (LocalFS) — $SD/Run= only looks at an SD card
    and reports success when there isn't one.
#>
param(
    [Parameter(Mandatory = $true)][string]$Board,
    [switch]$Restart,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$curl = "$env:SystemRoot\System32\curl.exe"
if (-not (Test-Path $curl)) {
    $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
}
if (-not $curl) {
    throw "curl.exe not found. Windows 10 1803+ includes it; otherwise install curl or use Git Bash with tools/deploy.sh"
}

$repo  = Split-Path -Parent $PSScriptRoot
$files = @(
    (Join-Path $repo 'config\config.yaml'),
    (Join-Path $repo 'macros\tc.nc'),
    (Join-Path $repo 'macros\measuretool.nc'),
    (Join-Path $repo 'macros\findzposition.nc')
)

function Invoke-Api([string]$cmd) {
    & $curl -sS --max-time 15 --get --data-urlencode "commandText=$cmd" "http://$Board/command" 2>$null
}

# --- is it there, and is it FluidNC? ---
# [ESP...] commands return output in the HTTP response. Plain commands like ?
# and $LocalFS/List do not — FluidNC sends those to the websocket, so there is
# no way to read machine state from here.
Write-Host "Contacting $Board ..."
$info = Invoke-Api '[ESP800]'
if ([string]::IsNullOrWhiteSpace($info)) {
    throw "No response from $Board. Wrong address, or the board is off or off-network."
}
if ($info -notmatch 'FluidNC') {
    Write-Host $info
    throw "Something answered but it does not look like FluidNC."
}
Write-Host ("  " + (($info -split "`n" | Select-Object -First 2) -join ' ').Trim())

# --- machine state has to be confirmed by a human ---
if (-not $Yes) {
    Write-Host ""
    Write-Host "Confirm the machine is idle - not running a job, not mid tool change."
    $reply = Read-Host "Upload to $Board? [y/N]"
    if ($reply -notmatch '^[Yy]$') { Write-Host "Aborted."; exit 1 }
}

# --- upload ---
Write-Host ""
foreach ($f in $files) {
    if (-not (Test-Path $f)) { throw "missing: $f" }
    $name = Split-Path -Leaf $f
    $size = (Get-Item $f).Length
    $fwd  = $f -replace '\\', '/'
    Write-Host ("  {0,-20} {1,6} bytes ... " -f $name, $size) -NoNewline
    # <filename>S is FluidNC's size field; it verifies the transfer end to end
    & $curl -sS --max-time 30 `
        -F "${name}S=$size" `
        -F "file=@${fwd};filename=$name" `
        "http://$Board/files" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "upload of $name failed" }
    Write-Host "ok"
}

# --- verify: /files returns a JSON listing over plain HTTP ---
Write-Host ""
Write-Host "On the controller now:"
$listing = & $curl -sS --max-time 15 "http://$Board/files?path=/"
($listing -split ',') | Where-Object { $_ -match 'name|size' } | ForEach-Object { Write-Host "  $_" }

if ($Restart) {
    Write-Host ""
    Write-Host "Restarting ..."
    Invoke-Api '$Bye' | Out-Null
    Write-Host 'Re-home before moving: $H   then  M61 Q<n>'
} else {
    Write-Host ""
    Write-Host 'Config needs a restart to take effect: $Bye (or re-run with -Restart).'
    Write-Host "Macros are live immediately."
}
