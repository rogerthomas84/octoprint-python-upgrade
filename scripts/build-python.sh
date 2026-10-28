#!/bin/bash
# Builds Python from source and installs it to /usr/local alongside the system Python.
# Uses "make altinstall" so /usr/bin/python3 (used by the OS, apt and certbot) is untouched.
#
# Usage (on the Pi, as a user with sudo rights):  ./build-python.sh [PYTHON_VERSION]
# Example:                                         ./build-python.sh 3.12.16
#
# Safe to re-run: an interrupted or failed build resumes where it left off.
set -euo pipefail
PYVER="${1:-3.12.16}"
PYMINOR="${PYVER%.*}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user (e.g. pi), not with sudo. It calls sudo itself where needed." >&2
  exit 1
fi

# Build dependencies. libjpeg/libfreetype aren't needed by Python itself, but plugins that
# pin old versions of Pillow (e.g. Timelapse+) have to compile it against them later.
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev libffi-dev zlib1g-dev libbz2-dev \
  libsqlite3-dev libreadline-dev liblzma-dev libncurses-dev libgdbm-dev uuid-dev tk-dev \
  libjpeg-dev libfreetype-dev

mkdir -p ~/src && cd ~/src
if [ ! -d "Python-${PYVER}" ]; then
  curl -fLO "https://www.python.org/ftp/python/${PYVER}/Python-${PYVER}.tar.xz"
  tar xf "Python-${PYVER}.tar.xz"
fi
cd "Python-${PYVER}"
[ -f Makefile ] || ./configure --prefix=/usr/local --with-ensurepip=install

# gcc can crash ("internal compiler error: Segmentation fault") on Parser/parser.c when a
# 2GB Pi runs 4 compile jobs at once, so use fewer parallel jobs when memory is tight.
MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [ "$MEM_MB" -lt 3000 ]; then JOBS=2; else JOBS=4; fi
make -j"$JOBS"
sudo make altinstall

"/usr/local/bin/python${PYMINOR}" --version
"/usr/local/bin/python${PYMINOR}" -c 'import ssl, sqlite3, bz2, lzma, ctypes, zlib, readline, uuid; print("stdlib modules OK,", ssl.OPENSSL_VERSION)'
echo "Installed /usr/local/bin/python${PYMINOR}"
