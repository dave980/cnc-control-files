#!/usr/bin/env bash
#
# Upload the config and macros in this repo to a FluidNC controller.
#
#   ./tools/deploy.sh 192.168.1.50            # upload, do not restart
#   ./tools/deploy.sh 192.168.1.50 --restart  # upload then $Bye
#   BOARD=192.168.1.50 ./tools/deploy.sh
#
# Files go to the controller's internal flash (LocalFS), which is where the
# macros must live — $SD/Run= only looks at an SD card and reports success
# when there isn't one.

set -euo pipefail

BOARD="${1:-${BOARD:-}}"
[[ "${BOARD}" == --* ]] && BOARD="${BOARD:-}"
RESTART=false
for arg in "$@"; do [[ "$arg" == "--restart" ]] && RESTART=true; done

if [[ -z "${BOARD}" ]]; then
    echo "usage: $0 <board-ip> [--restart]" >&2
    exit 2
fi

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES=(
    "${REPO}/config/config.yaml"
    "${REPO}/macros/tc.nc"
    "${REPO}/macros/measuretool.nc"
    "${REPO}/macros/findzposition.nc"
)

cmd() { curl -sS --max-time 10 --get --data-urlencode "commandText=$1" "http://${BOARD}/command"; }

# --- refuse to touch a machine that is doing something ---
echo "Checking ${BOARD} ..."
STATUS="$(cmd '?' || true)"
if [[ -z "${STATUS}" ]]; then
    echo "No response from ${BOARD}. Wrong address, or the board is off." >&2
    exit 1
fi
echo "  ${STATUS}"

case "${STATUS}" in
    *Idle*|*Alarm*|*Sleep*) ;;
    *)
        echo "Machine is not Idle. Refusing to upload mid-operation." >&2
        echo "Stop the job, then run this again." >&2
        exit 1
        ;;
esac

# --- upload ---
for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || { echo "missing: $f" >&2; exit 1; }
    name="$(basename "$f")"
    size="$(wc -c < "$f" | tr -d ' ')"
    printf '  %-20s %6s bytes ... ' "${name}" "${size}"
    # <filename>S is FluidNC's size field; it verifies the upload end to end
    curl -sS --max-time 30 \
         -F "path=/" \
         -F "${name}S=${size}" \
         -F "file=@${f};filename=${name}" \
         "http://${BOARD}/files" > /dev/null
    echo "ok"
done

# --- verify ---
echo "Files on the controller:"
cmd '$LocalFS/List' || true

if ${RESTART}; then
    echo "Restarting ..."
    cmd '$Bye' || true
    echo "Config takes effect now. Re-home before moving: \$H"
else
    echo
    echo "Config changes need a restart to take effect: \$Bye (or re-run with --restart)."
    echo "Macros are live immediately."
fi
