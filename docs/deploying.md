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

## tools/deploy.sh

```
./tools/deploy.sh 192.168.1.50             # upload only
./tools/deploy.sh 192.168.1.50 --restart   # upload then $Bye
```

It uploads `config/config.yaml` and the three macros to **internal flash**
(LocalFS), then lists what landed.

**It refuses to upload unless the machine reports Idle, Alarm or Sleep.** That
check is the point of the script rather than a nicety — an upload mid-job would
be bad, and a `$Bye` mid-job worse.

Config changes need a restart. Macros take effect immediately, because `tc.nc`
is read from flash each time M6 fires.

## The HTTP API it uses

Confirmed against FluidNC's `WebUIServer.cpp`:

| Endpoint | Does |
|---|---|
| `POST /files` | Upload to LocalFS. Path comes from the multipart filename; `path=` sets the directory |
| `GET /files?path=/` | List LocalFS |
| `POST /upload` | Upload to the SD card instead |
| `GET /command?commandText=...` | Run a command — `?`, `$LocalFS/List`, `$Bye` |

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
