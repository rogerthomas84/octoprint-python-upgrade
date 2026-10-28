# Upgrading OctoPrint's Python on OctoPi (without reflashing)

If your OctoPrint shows this warning:

> Your Python version 3.9.2 is past its end of life (2025-10-31). OctoPrint 2.0.\* will be the
> last version to support this Python version. You should upgrade as soon as possible!

this guide shows how to move OctoPrint onto a newer Python **in place**, over SSH, keeping your
settings, plugins, printer profiles, files and timelapses. There's no need to flash a new SD card.

It was written while upgrading two Raspberry Pi 4 Model B boards running **OctoPi 1.0.0** (Raspberry Pi OS
"Bullseye", Python 3.9.2) with **OctoPrint 1.11.8** to **Python 3.12.16**. The same steps should work on
other OctoPi 1.0.x / Bullseye installs.

## Contents

- [Which approach should I use?](#which-approach-should-i-use)
- [How it works](#how-it-works)
- [What you need](#what-you-need)
- [Step 0: Back up](#step-0-back-up)
- [Step 1: Check your Pi](#step-1-check-your-pi)
- [Step 2: Build a newer Python](#step-2-build-a-newer-python)
- [Step 3: Migrate OctoPrint to the new Python](#step-3-migrate-octoprint-to-the-new-python)
- [Step 4: Verify](#step-4-verify)
- [Step 5: Clean up (optional)](#step-5-clean-up-optional)
- [Troubleshooting](#troubleshooting)
- [Rolling back](#rolling-back)
- [Doing it by hand (without the scripts)](#doing-it-by-hand-without-the-scripts)
- [References](#references)

---

## Which approach should I use?

There are two ways to get a newer Python under OctoPrint:

| | **A. Reflash a newer OctoPi image** | **B. In-place upgrade (this guide)** |
|---|---|---|
| How | Back up → flash latest OctoPi (Bookworm, Python 3.11) → restore backup | Build a newer Python next to the old one → recreate OctoPrint's venv with it |
| Needs physical access | Yes (SD card) | No, SSH only |
| OS gets upgraded too | Yes | No, still Bullseye |
| System config kept (haproxy, TLS certs, certbot, cron, Wi-Fi…) | No, you redo it | Yes, untouched |
| Time | ~30-60 min per Pi | ~30-60 min per Pi (mostly compiling) |

The OctoPrint project recommends **A** where possible. **B** is a good fit if your Pi is
remote or headless, you have custom system config (TLS certificates, certbot, reverse proxy) you don't
want to redo, or you just want the warning gone with minimal disruption.

## How it works

On OctoPi, OctoPrint doesn't run on the system Python directly. It runs inside a Python
**virtual environment ("venv")** at `~/oprint`. The process is:

1. **Build a newer Python from source** and install it to `/usr/local/bin/python3.12` with
   `make altinstall`. The system Python (`/usr/bin/python3`, 3.9) is **not** replaced. The OS, `apt`
   and tools like certbot keep using it, so nothing else on the Pi is affected.
2. **Recreate `~/oprint` using the new Python** with OctoPrint's official
   [`octoprint-venv-tool`](https://github.com/OctoPrint/venv-tool). It records your installed plugins,
   builds a fresh venv with the new Python, reinstalls OctoPrint and every plugin into it, and
   **automatically restores the old venv if anything fails**.

Your OctoPrint data (`~/.octoprint`: settings, users, uploads, timelapses, plugin data) lives outside the
venv and isn't touched.

### Which Python version?

OctoPrint 1.11.x supports Python 3.7 to 3.13 (`requires_python <3.14`). This guide uses **3.12**:

- Supported upstream until October 2028.
- Old enough that most plugins work with it. Python 3.13 removed some long-deprecated standard library
  modules that older plugins may still import.

To use a different version, pass it to the build script (e.g. `3.13.x`) and point the migration at
`/usr/local/bin/python3.13`. Check OctoPrint's supported range first:
`curl -s https://pypi.org/pypi/OctoPrint/json | grep -o '"requires_python":"[^"]*"'`.

## What you need

- OctoPi (or any Raspberry Pi OS install where OctoPrint runs from a venv) that you can SSH into.
- A user with `sudo` rights. On OctoPi that's `pi` by default.
- ~1 GB free disk space. The Python source build uses ~400 MB, and a backup copy of the venv is kept.
- Internet access from the Pi, to download Python source, the venv-tool and plugins.
- **No print running.** OctoPrint is stopped for a few minutes during step 3.
- This repository on your computer:

  ```bash
  git clone https://github.com/rogerthomas84/octoprint-python-upgrade.git
  cd octoprint-python-upgrade
  ```

Throughout this guide, replace:

| Placeholder | Meaning | OctoPi default |
|---|---|---|
| `USER` | SSH user on the Pi | `pi` |
| `HOST` | Pi's hostname or IP address | `octopi.local` |

If you have several Pis, do them **one at a time** and check each before moving on. You can safely run
step 2 (building Python) on all of them at once, because it doesn't affect OctoPrint.

> **Tip:** passwordless SSH makes everything smoother: `ssh-copy-id USER@HOST`

## Step 0: Back up

In OctoPrint, go to **Settings → Backup & Restore → Create backup**, then download the `.zip` to your computer.
The migration script also keeps its own copy of the old venv (see [Rolling back](#rolling-back)), but take a
proper OctoPrint backup anyway.

## Step 1: Check your Pi

```bash
ssh USER@HOST 'bash -s' < scripts/check-status.sh
```

Example output:

```
OctoPi version:   1.0.0
OS:               Raspbian GNU/Linux 11 (bullseye) (armv7l)
Model:            Raspberry Pi 4 Model B Rev 1.2
RAM:              1.8Gi   Free disk: 51G
System python3:   Python 3.9.2
OctoPrint venv:   /home/pi/oprint -> Python 3.9.2
OctoPrint:        octoprint, version 1.11.8
Service:          active
Extra Pythons:
Third-party plugins installed in the venv:
  OctoPrint-PrintTimeGenius 2.5.1
  OctoPrint-PrusaMMU 2026.6.20
  Themeify 1.2.2
  TimelapsePlus 1.4.1
  ...
Last printer state: "Operational"
```

Save this output. It's your record of which plugins you had before.

## Step 2: Build a newer Python

Copy the scripts to the Pi and run the build:

```bash
scp scripts/*.sh USER@HOST:
ssh USER@HOST
./build-python.sh 3.12.16
```

This installs build dependencies with `apt`, downloads the Python source to `~/src`, compiles it and
installs `/usr/local/bin/python3.12`. On a Pi 4 it takes roughly **15-30 minutes**. It finishes with:

```
Python 3.12.16
stdlib modules OK, OpenSSL 1.1.1w  11 Sep 2023
Installed /usr/local/bin/python3.12
```

The `stdlib modules OK` line confirms SSL, SQLite, compression and the other modules OctoPrint
needs were built. If any of them failed to build, this line errors out instead.

> **If your SSH connection might drop**, run it in the background and follow the log:
> `nohup ./build-python.sh 3.12.16 > build.log 2>&1 &` then `tail -f build.log`.
> If it does get interrupted, just run it again: it resumes where it stopped.

## Step 3: Migrate OctoPrint to the new Python

Make sure nothing is printing, then on the Pi (as `USER`, **not** with `sudo`):

```bash
./migrate-venv.sh /usr/local/bin/python3.12
```

The script:

1. Saves a full copy of the current venv and a list of its packages and plugins to `~/venv-backups/`.
2. Downloads the official `octoprint-venv-tool` from `get.octoprint.org`.
3. Stops OctoPrint.
4. Runs `octoprint-venv-tool recreate-venv ~/oprint --python=/usr/local/bin/python3.12`, which rebuilds the
   venv and reinstalls OctoPrint and all your plugins.
5. Starts OctoPrint again. It does this even if the migration fails, in which case the venv-tool has
   already put your old venv back.

A successful run ends like this:

```
Installing plugin export /tmp/plugin-export-xxxx.json into recreated venv /home/pi/oprint...
Installing https://github.com/eyal0/OctoPrint-PrintTimeGenius/archive/master.zip...
...
Recreation of /home/pi/oprint successful, removing backup...
... done!

/home/pi/oprint has been recreated with /usr/local/bin/python3.12!
Python 3.12.16
octoprint, version 1.11.8
```

This takes 5-15 minutes, longer if a plugin needs something compiled.

> **Note:** plugins are reinstalled from the plugin repository, so some may come back at a slightly
> newer version than you had. That's normal.

## Step 4: Verify

1. Run the status check again and compare it with step 1:

   ```bash
   ssh USER@HOST 'bash -s' < scripts/check-status.sh
   ```

   `OctoPrint venv` should now show `Python 3.12.16`, and the same plugins should be listed.

2. Open OctoPrint in your browser and force-reload (Ctrl/Cmd+Shift+R). The Python end-of-life
   warning should be gone.

3. Look at **Settings → Plugin Manager** for any plugin marked disabled or incompatible.

4. Check the startup log for errors:

   ```bash
   ssh USER@HOST "grep -E 'Detected environment| - ERROR |Traceback' ~/.octoprint/logs/octoprint.log | tail"
   ```

   You should see `Detected environment is Python 3.12.16`. Warnings about plugin templates not being
   autoescaped are unrelated to this upgrade and were there before.

5. Connect to your printer and run a short test print.

## Step 5: Clean up (optional)

Once you're happy everything works (give it a few prints), you can reclaim ~500 MB:

```bash
sudo rm -rf ~/src            # Python source and build files (sudo: "make altinstall" leaves root-owned caches)
rm -rf ~/venv-backups        # old venv copy (removes the ability to roll back easily)
rm -f ~/octoprint-venv-tool
```

Leave `/usr/local/bin/python3.12` in place: OctoPrint now runs on it.

---

## Troubleshooting

### Build fails with `internal compiler error: Segmentation fault` (on `Parser/parser.c`)

The Pi ran short of memory compiling Python's huge generated parser with several jobs in parallel.
This happened on a **2 GB** Pi 4 with OctoPi's default 100 MB swap. `build-python.sh` already uses 2 parallel
jobs on Pis with under 3 GB of RAM. If it still happens, re-run it (it resumes), or run `make -j1` by hand
in `~/src/Python-3.12.16`, then `sudo make altinstall`.

### Migration fails: `Failed building wheel for pillow` / `The headers or library files could not be found for zlib`

Some plugins pin an old library that has no prebuilt package for the new Python, so pip compiles it from source.
In our case **Timelapse+** requires `Pillow<10`, which means Pillow 9.5.0. That version predates Python 3.12, and
its build can't find Debian's multi-architecture library directory (`/usr/lib/arm-linux-gnueabihf`), even
with `zlib1g-dev` installed.

`migrate-venv.sh` handles this by exporting `CFLAGS`/`LDFLAGS` that point at those directories, and
`build-python.sh` installs `libjpeg-dev` and `libfreetype-dev`. If you hit something similar with another
package, read the pip error, `apt install` the missing `-dev` package, and re-run `migrate-venv.sh`.

When a plugin fails, the venv-tool **rolls back automatically** and OctoPrint comes back on the old Python,
so nothing is lost. If you'd rather migrate without a problem plugin and sort it out afterwards, run the tool
directly with `--ignore-plugin-errors`:

```bash
sudo systemctl stop octoprint
./octoprint-venv-tool recreate-venv ~/oprint --python=/usr/local/bin/python3.12 --ignore-plugin-errors
sudo systemctl start octoprint
```

### Printer won't connect after the upgrade

First check the printer is actually powered on. A Prusa still shows up on USB (`/dev/ttyACM0`) when
its power supply is off, but it won't answer, so OctoPrint's auto-detect tries every baud rate and ends in
`Offline after error`. The upgrade doesn't touch serial settings. Power the printer on and click **Connect**.

### `Do not run this with sudo`

The scripts must run as the user OctoPrint runs as (`pi` on OctoPi). If the venv were rebuilt as root, the files
would be owned by root and OctoPrint couldn't update itself or install plugins. The scripts call
`sudo` themselves for the steps that need it.

### What about my TLS certificate / certbot / haproxy?

They're unaffected. They live in `/etc` and certbot runs on the system Python (`/usr/bin/python3`),
which this process doesn't change. You can confirm certbot still works with `certbot --version`.

---

## Rolling back

**If the migration fails**, the venv-tool restores your old venv automatically. Nothing to do.

**If it succeeds but you want to go back to the old Python**, restore the copy `migrate-venv.sh` saved:

```bash
ls ~/venv-backups/                          # find oprint-backup-YYYYMMDD-HHMMSS.tar.gz
sudo systemctl stop octoprint
mv ~/oprint ~/oprint-py312
tar xzf ~/venv-backups/oprint-backup-YYYYMMDD-HHMMSS.tar.gz -C ~
sudo systemctl start octoprint
```

As a last resort, flash a fresh OctoPi image and restore the backup `.zip` from [step 0](#step-0-back-up).

---

## Doing it by hand (without the scripts)

The scripts just wrap these commands. Run them on the Pi as `USER`:

```bash
# --- Build Python 3.12 alongside the system Python ---
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev libffi-dev zlib1g-dev libbz2-dev \
  libsqlite3-dev libreadline-dev liblzma-dev libncurses-dev libgdbm-dev uuid-dev tk-dev \
  libjpeg-dev libfreetype-dev
mkdir -p ~/src && cd ~/src
curl -fLO https://www.python.org/ftp/python/3.12.16/Python-3.12.16.tar.xz
tar xf Python-3.12.16.tar.xz && cd Python-3.12.16
./configure --prefix=/usr/local --with-ensurepip=install
make -j2                       # -j4 is fine on 4 GB+ Pis
sudo make altinstall           # "altinstall" = don't replace /usr/bin/python3
/usr/local/bin/python3.12 --version

# --- Back up the current venv ---
mkdir -p ~/venv-backups
tar czf ~/venv-backups/oprint-backup.tar.gz -C ~ oprint

# --- Recreate the OctoPrint venv with the new Python ---
cd ~
curl -fLO https://get.octoprint.org/octoprint-venv-tool && chmod +x octoprint-venv-tool
./octoprint-venv-tool export-plugins --output ~/venv-backups/plugins.json ~/oprint
export CFLAGS="-I/usr/include -I/usr/include/$(gcc -print-multiarch)"
export LDFLAGS="-L/usr/lib/$(gcc -print-multiarch)"
sudo systemctl stop octoprint
./octoprint-venv-tool recreate-venv ~/oprint --python=/usr/local/bin/python3.12
sudo systemctl start octoprint
~/oprint/bin/python --version
```

## Files in this repository

| File | Runs on | Purpose |
|---|---|---|
| `scripts/check-status.sh` | Pi | Prints OctoPi/OS/Python/OctoPrint versions, plugins and printer state |
| `scripts/build-python.sh` | Pi | Builds and installs a newer Python to `/usr/local` (resumable) |
| `scripts/migrate-venv.sh` | Pi | Backs up and recreates the OctoPrint venv on the new Python |

## References

- [OctoPrint FAQ: OctoPrint tells me my Python environment is outdated, how do I upgrade?](https://community.octoprint.org/t/61076)
- [OctoPrint FAQ: Unsupported Python environment](https://faq.octoprint.org/unsupported-python-environment)
- [OctoPrint venv-tool](https://github.com/OctoPrint/venv-tool)
- [Python release status / end-of-life dates](https://devguide.python.org/versions/)

## Disclaimer

Provided as-is. It worked on the setups described above, but back up first and don't run it during a print.
