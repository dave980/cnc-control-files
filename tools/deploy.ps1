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
    (Join-Path $repo 'macros\findzposition.nc'),
    (Join-Path $repo 'macros\dustshoe_unload.nc'),
    (Join-Path $repo 'macros\dustshoe_load.nc')
)

# -s, not -sS. With $ErrorActionPreference = 'Stop', anything a native command
# writes to stderr becomes a terminating NativeCommandError in PowerShell 5.1,
# and "2>$null" does not prevent it -- a curl timeout here killed the script
# mid-restart. Every caller treats an empty reply as "no answer", which is all
# the detail any of them need; $LASTEXITCODE carries the reason if it matters.
function Invoke-Api([string]$cmd, [int]$TimeoutSec = 15) {
    & $curl -s --max-time $TimeoutSec --get --data-urlencode "commandText=$cmd" "http://$Board/command"
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
    & $curl -s --max-time 30 `
        -F "${name}S=$size" `
        -F "file=@${fwd};filename=$name" `
        "http://$Board/files" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "upload of $name failed" }
    Write-Host "ok"
}

# --- verify: /files returns a JSON listing over plain HTTP ---
Write-Host ""
Write-Host "On the controller now:"
$listing = & $curl -s --max-time 15 "http://$Board/files?path=/"
($listing -split ',') | Where-Object { $_ -match 'name|size' } | ForEach-Object { Write-Host "  $_" }

if ($Restart) {
    Write-Host ""
    Write-Host "Restarting ..."

    # [ESP444]RESTART, not $Bye.
    #
    # FluidNC's /command endpoint runs a command only when it begins "[ESP" or
    # "$/" (WebUIServer.cpp, _handle_web_command). Anything else goes to
    # WSChannels::runGCode, which needs a websocket belonging to the caller's
    # own HTTP session. curl has none, so getWSChannel(0, "") matches nothing
    # and the server answers 500 "WebSocket dead". $Bye is a real command --
    # it works typed into the WebUI console, which has a session -- but it is
    # unreachable over HTTP, and this script used to discard the 500 and claim
    # a restart that never happened. [ESP444]RESTART is what the WebUI's own
    # restart dialog sends.
    #
    # 2 s, because the reply never comes: restart() calls
    # protocol_send_event(&fullResetEvent) and the board resets before the HTTP
    # response is flushed, so the request is cut off with 0 bytes. That is the
    # successful case. A refusal, by contrast, answers immediately.
    $reply = Invoke-Api '[ESP444]RESTART' 2
    if ($reply -match 'Authentication failed|Parameter must be|WebSocket dead') {
        Write-Host "  controller refused it: $reply"
        throw "restart refused"
    }

    # Confirm it went down and came back. The case worth catching is a
    # config.yaml that will not parse: the board reboots and never rejoins.
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Seconds 3
    Write-Host -NoNewline "  waiting for it to come back "
    $back = $false
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Seconds 2
        if ((Invoke-Api '[ESP800]' 3) -match 'FluidNC') { $back = $true; break }
        Write-Host -NoNewline "."
    }
    Write-Host ""

    if ($back) {
        Write-Host ("  back up after {0:n0} s." -f $sw.Elapsed.TotalSeconds)
        Write-Host 'Re-home before moving: $H   then  M61 Q<n>'
    } else {
        Write-Host ("  no answer after {0:n0} s." -f $sw.Elapsed.TotalSeconds)
        Write-Host "  Check the controller. A config.yaml that will not parse stops it"
        Write-Host "  rejoining the network, and only the serial console says why."
    }
} else {
    Write-Host ""
    Write-Host 'Config needs a restart to take effect. Type $Bye in the WebUI console'
    Write-Host "  (that works - it has a websocket session), or re-run with -Restart."
    Write-Host "Macros are live immediately."
}
