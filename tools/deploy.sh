#!/usr/bin/env bash
#
# Upload the config and macros in this repo to a FluidNC controller.
#
#   ./tools/deploy.sh 192.168.0.23
#   ./tools/deploy.sh 192.168.0.23 --restart
#   BOARD=192.168.0.23 ./tools/deploy.sh --restart
#   ./tools/deploy.sh 192.168.0.23 --restart --yes    # no prompt (scripted use)
#
# Files go to the controller's internal flash (LocalFS), which is where the
# macros must live — $SD/Run= only looks at an SD card and reports success
# when there isn't one.

set -euo pipefail

BOARD="${BOARD:-}"
RESTART=false
ASSUME_YES=false

for arg in "$@"; do
    case "$arg" in
        --restart) RESTART=true ;;
        --yes|-y)  ASSUME_YES=true ;;
        -h|--help) sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
        --*)       echo "unknown option: $arg" >&2; exit 2 ;;
        *)         BOARD="$arg" ;;
    esac
done

if [[ -z "${BOARD}" ]]; then
    echo "usage: $0 <board-ip> [--restart] [--yes]" >&2
    exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=(
    "${REPO}/config/config.yaml"
    "${REPO}/macros/tc.nc"
    "${REPO}/macros/measuretool.nc"
    "${REPO}/macros/findzposition.nc"
    "${REPO}/macros/dustshoe_unload.nc"
    "${REPO}/macros/dustshoe_load.nc"
    "${REPO}/macros/zprobe.nc"
)

api() { curl -sS --max-time "${2:-15}" --get --data-urlencode "commandText=$1" "http://${BOARD}/command"; }

# --- is it there, and is it FluidNC? ---
# [ESP...] commands return their output in the HTTP response. Plain commands
# like ? and $LocalFS/List do NOT — FluidNC sends those to the websocket, so
# curl sees nothing useful. That rules out reading machine state from here.
echo "Contacting ${BOARD} ..."
INFO="$(api '[ESP800]' || true)"
if [[ -z "${INFO}" ]]; then
    echo "No response. Wrong address, or the board is off or off-network." >&2
    exit 1
fi
if [[ "${INFO}" != *FluidNC* ]]; then
    echo "Something answered but it does not look like FluidNC:" >&2
    echo "${INFO}" >&2
    exit 1
fi
echo "  $(echo "${INFO}" | tr -d '\r' | head -2 | paste -sd' ' -)"

# --- machine state has to be confirmed by a human ---
# There is no plain-HTTP way to read Idle/Run/Hold, so this cannot be checked
# automatically. Uploading mid-job is bad; $Bye mid-job is worse.
if ! ${ASSUME_YES}; then
    if [[ ! -t 0 ]]; then
        echo "Not a terminal and --yes not given. Refusing to deploy unattended." >&2
        exit 1
    fi
    echo
    echo "Confirm the machine is idle — not running a job, not mid tool change."
    read -r -p "Upload to ${BOARD}? [y/N] " reply
    [[ "${reply}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# --- upload ---
echo
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }
    name="$(basename "$f")"
    size="$(wc -c < "$f" | tr -d ' ')"
    printf '  %-20s %6s bytes ... ' "${name}" "${size}"
    # <filename>S is FluidNC's size field; it verifies the transfer end to end
    curl -sS --max-time 30 \
         -F "${name}S=${size}" \
         -F "file=@${f};filename=${name}" \
         "http://${BOARD}/files" > /dev/null
    echo "ok"
done

# --- verify: /files returns a JSON listing over plain HTTP ---
echo
echo "On the controller now:"
curl -sS --max-time 15 "http://${BOARD}/files?path=/" | tr ',' '\n' | grep -i 'name\|size' || true

if ${RESTART}; then
    echo
    echo "Restarting ..."

    # [ESP444]RESTART, not $Bye.
    #
    # FluidNC's /command endpoint runs a command only when it begins "[ESP" or
    # "$/" (WebUIServer.cpp, _handle_web_command). Anything else goes to
    # WSChannels::runGCode, which needs a websocket belonging to the caller's
    # own HTTP session. curl has none, so getWSChannel(0, "") matches nothing
    # and the server answers 500 "WebSocket dead". $Bye is a real command --
    # it works typed into the WebUI console, which has a session -- but it is
    # unreachable over HTTP, and discarding that 500 made this script claim a
    # restart that never happened. [ESP444]RESTART is what the WebUI's own
    # restart dialog sends.
    # 2 s, because the reply never comes: restart() calls
    # protocol_send_event(&fullResetEvent) and the board resets before the HTTP
    # response is flushed, so curl is cut off with 0 bytes. That is the
    # successful case, so the timeout and the error text are both expected. A
    # refusal, by contrast, answers immediately.
    reply="$(api '[ESP444]RESTART' 2 2>/dev/null || true)"
    case "${reply}" in
        *"Authentication failed"*|*"Parameter must be"*|*"WebSocket dead"*)
            echo "  controller refused it: ${reply}" >&2
            exit 1
            ;;
    esac

    # Confirm it went down and came back. The case worth catching is a
    # config.yaml that will not parse: the board reboots and never rejoins.
    start=${SECONDS}
    sleep 3
    printf '  waiting for it to come back '
    back=false
    for _ in $(seq 20); do
        sleep 2
        if api '[ESP800]' 3 2>/dev/null | grep -q FluidNC; then back=true; break; fi
        printf '.'
    done
    echo

    if ${back}; then
        echo "  back up after $((SECONDS - start)) s."
        echo "Re-home before moving: \$H   then  M61 Q<n>"
    else
        echo "  no answer after $((SECONDS - start)) s."
        echo "  Check the controller. A config.yaml that will not parse stops it"
        echo "  rejoining the network, and only the serial console says why."
    fi
else
    echo
    echo "Config needs a restart to take effect. Type \$Bye in the WebUI console"
    echo "  (that works - it has a websocket session), or re-run with --restart."
    echo "Macros are live immediately."
fi
