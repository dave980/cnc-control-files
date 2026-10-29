# Getting files onto the controller

## Why there is no direct GitHub → board path

The board sits on your LAN with a private address. GitHub-hosted Actions runners
are in GitHub's cloud and cannot route to it, and FluidNC has no outbound pull
of its own — it never fetches anything. So the push has to originate from a
machine that can already see the board.

Three ways to arrange that, in order of how much machinery they need:

| | How | Good for |
|---|---|---|
| Manual | `./tools/deploy.sh <board-ip>` | Normal use |
| Git hook | `post-merge` hook calling the script | Deploy on every `git pull` |
| Self-hosted runner | GitHub Actions runner on a LAN machine | Deploy on every push to `main` |

## On Windows

The repo clones to something like
`C:\Users\<you>\Documents\GitHub\cnc-control-files`. Two options:

**Git Bash** — run `tools/deploy.sh` unchanged. Git for Windows ships bash and
curl, so nothing extra is needed.

**PowerShell** — run `tools\deploy.ps1`, which does the same thing using
`curl.exe` (included in Windows 10 1803 and later):

```
.\tools\deploy.ps1 -Board 192.168.0.23
.\tools\deploy.ps1 -Board 192.168.0.23 -Restart
```

If PowerShell refuses to run it, the execution policy is blocking local
scripts. Either unblock the file or run it for one session only:

```
powershell -ExecutionPolicy Bypass -File .\tools\deploy.ps1 -Board 192.168.0.23
```

### Double-clicking it

`tools\deploy.cmd` is the double-click entry point. It shows which commit is
checked out, does a fast-forward-only `git pull` so you can see what changed,
runs `deploy.ps1`, and leaves the window open at the end.

To put it on the desktop: right-click `deploy.cmd` → **Send to** → **Desktop
(create shortcut)**. Don't copy the file to the desktop — the shortcut has to
point at the one inside the repo, because the script locates the config and
macros relative to its own position.

The board address is set near the top of the file (`set BOARD=192.168.0.23`).
Editing it there is fine; it is also accepted as an argument if you ever need a
second machine.

The confirmation prompt still applies — a double click gets you as far as being
asked whether the machine is idle, not past it. `git pull --ff-only` refuses to
merge if you have local commits, rather than quietly combining them.

**You do not need to pull first.** The pull is part of the script. And if it
fails, the script now stops instead of uploading: a refused pull used to print
its error and carry on to deploy whatever was on disk, which looks identical to
a successful deploy of the new files. Local commits in the way, a diverged
branch, no network and a credential prompt all land there. The escape hatch, if
you really do mean to deploy the working tree as it stands, is to skip the
wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File tools\deploy.ps1 -Board 192.168.0.23 -Restart
```

The check has to be written `if errorlevel 1`. Inside a parenthesised `cmd`
block `%ERRORLEVEL%` is expanded once, at parse time, so `if %ERRORLEVEL% neq 0`
tests the value from before `git` ran and never fires.

### Do not keep this repo in OneDrive

A git repository inside a OneDrive folder is a known source of trouble.
OneDrive syncs the `.git` directory itself, so it can upload loose objects and
index files mid-operation, produce `cnc-control-files-DESKTOP-xxx` conflicted
copies, and with Files On-Demand it can leave files as cloud placeholders that
tools see as empty. Microsoft's own guidance is not to sync dev repos.

Move it somewhere outside OneDrive:

```
C:\Users\<you>\GitHub\cnc-control-files
```

Clone it fresh there rather than dragging the folder, so nothing carries over
half-synced state. For a config repo controlling a machine with a 2.2 kW
spindle, a silently corrupted checkout is not a risk worth running.

### Line endings

Git on Windows checks out CRLF by default. That happens to be harmless here —
FluidNC's `InputFile::readLine` skips `\r` outright, so CRLF macros run fine —
but `.gitattributes` pins LF anyway to keep diffs clean between machines.

## tools/deploy.sh

```
./tools/deploy.sh 192.168.0.23             # upload only
./tools/deploy.sh 192.168.0.23 --restart   # upload, reboot, wait for it
./tools/deploy.sh 192.168.0.23 --yes       # skip the confirmation prompt
```

It uploads `config/config.yaml` and the three macros to **internal flash**
(LocalFS), then lists what landed.

**Machine state cannot be checked automatically** — see the API note below. The
script verifies the board is reachable and really is FluidNC, then asks you to
confirm the machine is idle. Without a terminal it refuses outright unless
`--yes` is given, so a cron job or CI run cannot deploy silently by accident.

Config changes need a restart. Macros take effect immediately, because `tc.nc`
is read from flash each time M6 fires.

## The HTTP API it uses

Confirmed against FluidNC's `WebUIServer.cpp`:

| Endpoint | Does |
|---|---|
| `POST /files` | Upload to LocalFS. Path comes from the multipart filename; `path=` sets the directory |
| `GET /files?path=/` | List LocalFS |
| `POST /upload` | Upload to the SD card instead |
| `GET /command?commandText=...` | Run a command |

**The `/command` endpoint splits two ways, and it matters.** Commands starting
with `[ESP` or `$/` go through `synchronousCommand` and their output comes back
in the HTTP response. Everything else — `?`, `$LocalFS/List`, `$Bye` — goes
through `websocketCommand`.

That second path does not just lose the output. It **does not run the command
at all** unless a websocket belonging to the caller's own HTTP session is
already open:

```cpp
// WebUIServer.cpp
websocketCommand(request, cmd.c_str(), getPageid(request), auth_level);
//   -> WSChannels::runGCode(pageid, cmd, session)
//        -> getWSChannel(pageid, session)   // nullptr -> returns error
//   -> request->send(500, "text/plain", "WebSocket dead")
```

`getPageid` returns 0 when there is no `PAGEID=` parameter, and curl sends no
session cookie, so `getWSChannel(0, "")` looks for a channel whose session is
the empty string. A browser's websocket carries a real session string and does
not match. The answer is `500 WebSocket dead` and the command is discarded.

This cost an evening. `deploy.ps1` sent `$Bye` to restart the board, threw the
500 away, and printed "Restarting ..." — while the controller carried on
running, still showing the WebUI's "files have changed" notice. The tell was
that the notice survived a deploy but not a real reboot.

**To restart over HTTP, send `[ESP444]RESTART`** — what the WebUI's own restart
dialog uses, registered in `WebCommands.cpp`:

```cpp
new WebCommand("RESTART", WEBCMD, WA, "ESP444", "System/Control", setSystemMode);
```

`$Bye` is the same action (`FileCommands.cpp` registers it with a null
`grblName`, so it is console-only) and works fine typed into the WebUI console,
because that channel has a session. It is simply unreachable over HTTP.

Both scripts now send `[ESP444]RESTART` and then poll `[ESP800]` until the
board answers again, so a config that fails to parse on boot shows up as a
board that never comes back rather than as a silent success.

### The restart request never completes, and that is success

`restart()` calls `protocol_send_event(&fullResetEvent)`. The board resets
before the HTTP response is flushed, so the request dies with 0 bytes
received:

```
curl: (28) Operation timed out after 15005 milliseconds with 0 bytes received
```

That is what a working restart looks like. Both scripts give this one call a
2 s timeout and ignore the result. A *refusal* — bad auth, wrong parameter —
answers immediately instead, which is why checking the reply still means
something.

### Why the scripts use `curl -s`, not `-sS`

`-S` tells curl to print errors to stderr even in silent mode. In PowerShell
5.1 with `$ErrorActionPreference = 'Stop'`, **anything** a native command
writes to stderr is turned into a terminating `NativeCommandError` — and
`2>$null` does not prevent it:

```
curl.exe : curl: (28) Operation timed out ...
    + CategoryInfo : NotSpecified: (...) [], RemoteException
    + FullyQualifiedErrorId : NativeCommandError
```

So the expected timeout above killed `deploy.ps1` in the middle of the restart,
after the reboot had already been triggered. With plain `-s`, curl stays quiet,
exits non-zero, and every caller's existing "empty reply means no answer" check
does the right thing. `$LASTEXITCODE` is there when the reason matters.

This is a PowerShell hazard, not a curl one, but `deploy.sh` suppresses stderr
on the same call so a successful restart does not print an alarming error.

So over plain HTTP you can read:

- `[ESP800]` — firmware info, which is what the script uses to confirm it is
  talking to FluidNC
- `[ESP420]` — system stats
- `GET /files?path=/` — the LocalFS listing, as JSON

But **not** machine state. `?` returns its status report over the websocket
only, which is why the idle check is a human confirmation rather than an
automated gate. Reading state from a script would mean a websocket client.

A form field named `<filename>S` carrying the byte count is optional, but worth
sending: FluidNC compares it against what actually arrived and fails the upload
on a mismatch. The script always sends it.

## Deploying on every push — and why not to

A self-hosted runner on your LAN can do it:

```yaml
name: deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - run: ./tools/deploy.sh ${{ secrets.BOARD_IP }}
```

Note there is no `--restart`. **Think hard before automating this at all.**
A commit that pushes a broken config to a machine with a 2.2 kW spindle and
10 mm of Z clearance over the tool changer is a different class of mistake from
a bad commit in software. The soft limits, the pocket coordinates and the VFD
speed map all live in that file.

Deliberate deployment, by hand, after reading the diff, is the right default for
a machine. Automate the *pull*, not the push to the controller.
