#!/bin/bash
# Prints the facts you need before (and after) upgrading OctoPrint's Python.
# Usage (on the Pi):  ./check-status.sh          or from your computer:  ssh USER@HOST 'bash -s' < check-status.sh
VENV="${VENV:-$HOME/oprint}"
echo "OctoPi version:   $(cat /etc/octopi_version 2>/dev/null || echo 'n/a (not OctoPi)')"
echo "OS:               $(. /etc/os-release; echo "$PRETTY_NAME") ($(uname -m))"
echo "Model:            $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
echo "RAM:              $(free -h | awk '/^Mem:/{print $2}')   Free disk: $(df -h / | awk 'NR==2{print $4}')"
echo "System python3:   $(/usr/bin/python3 --version 2>&1)"
echo "OctoPrint venv:   $VENV -> $("$VENV"/bin/python --version 2>&1)"
echo "OctoPrint:        $("$VENV"/bin/octoprint --version 2>&1)"
echo "Service:          $(systemctl is-active octoprint 2>&1)"
echo "Extra Pythons:    $(ls /usr/local/bin/python3.* 2>/dev/null | grep -E 'python3\.[0-9]+$' | tr '\n' ' ')"
echo "Third-party plugins installed in the venv:"
"$VENV"/bin/python - <<'PY' 2>/dev/null
from importlib.metadata import distributions
for d in sorted(distributions(), key=lambda d: d.metadata["Name"].lower()):
    if any(ep.group == "octoprint.plugin" for ep in d.entry_points):
        print(f"  {d.metadata['Name']} {d.version}")
PY
echo "Last printer state: $(grep 'monitoring state' ~/.octoprint/logs/octoprint.log 2>/dev/null | tail -1 | sed -E 's/.* to //')"
