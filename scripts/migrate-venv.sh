#!/bin/bash
# Migrates the OctoPrint venv (~/oprint) to a newer Python using OctoPrint's official venv-tool.
#
# Usage (on the Pi, as the user OctoPrint runs as - NOT with sudo):
#   ./migrate-venv.sh [PATH_TO_NEW_PYTHON]          default: /usr/local/bin/python3.12
#   VENV=/path/to/venv ./migrate-venv.sh ...       if your venv isn't ~/oprint (OctoPi default)
#
# Make sure no print is running: OctoPrint is stopped during the migration.
# On failure the venv-tool restores the old venv, and OctoPrint is always restarted.
set -euo pipefail
if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this with sudo - run it as the user OctoPrint runs as (e.g. pi)." >&2
  exit 1
fi
PYTHON="${1:-/usr/local/bin/python3.12}"
VENV="${VENV:-$HOME/oprint}"
STAMP="$(date +%Y%m%d-%H%M%S)"

"$PYTHON" --version
[ -x "$VENV/bin/octoprint" ] || { echo "No OctoPrint venv found at $VENV (set VENV=...)" >&2; exit 1; }

# Extra safety net on top of the venv-tool's own rollback: a full copy of the old venv
mkdir -p ~/venv-backups
tar czf ~/venv-backups/oprint-backup-"$STAMP".tar.gz -C "$(dirname "$VENV")" "$(basename "$VENV")"
"$VENV"/bin/pip freeze > ~/venv-backups/pip-freeze-before-"$STAMP".txt

cd ~
curl -fLO https://get.octoprint.org/octoprint-venv-tool
chmod +x octoprint-venv-tool
./octoprint-venv-tool export-plugins --output ~/venv-backups/plugins-"$STAMP".json "$VENV"

# Some plugins pin old libraries with no prebuilt wheels for the new Python (e.g. Timelapse+
# pins Pillow<10), so they compile from source. Older Pillow can't find Debian's multiarch
# library dirs on its own, so point the compiler at them explicitly.
MULTIARCH="$(gcc -print-multiarch)"
export CFLAGS="-I/usr/include -I/usr/include/$MULTIARCH"
export LDFLAGS="-L/usr/lib/$MULTIARCH"

sudo systemctl stop octoprint
trap 'sudo systemctl start octoprint' EXIT
./octoprint-venv-tool recreate-venv "$VENV" --python="$PYTHON"

"$VENV"/bin/python --version
"$VENV"/bin/octoprint --version
