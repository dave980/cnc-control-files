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
./tools/deploy.sh 192.168.0.23 --restart   # upload then $Bye
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
through `websocketCommand`, so the output goes to the websocket and curl sees
nothing useful.

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
