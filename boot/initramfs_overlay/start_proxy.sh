#!/system/bin/sh
# start_mirakurun.sh — start Mirakurun-BS4K on SMB400 via chroot + Alpine ARM32.
#
# Requires root (ADB shell is root by default on SMB400).
# Alpine rootfs + Node.js must be set up first (see setup_proot.sh / make setup-mirakurun-runtime).

ROOTFS=/data/local/tmp/mirakurun-root
MIRAKURUN=/data/local/tmp/mirakurun
LOG=/data/local/tmp/mirakurun.log
PIDFILE=/data/local/tmp/mirakurun-start.pid

# --- Preflight: start only if the Mirakurun setup is fully present. ---
# If anything required is missing we exit immediately WITHOUT stopping
# Android TV, so a not-yet-provisioned device is left completely untouched.
# (This runs before the singleton check / pidfile write on purpose.)
REQUIRED="
$ROOTFS/usr/bin/node
$MIRAKURUN/lib/server.js
$MIRAKURUN/config/server.yml
$MIRAKURUN/config/tuners.yml
$MIRAKURUN/config/channels.yml
/data/local/tmp/tuner-stream-bs-ng
/data/local/tmp/b61dec
"
missing=""
for f in $REQUIRED; do
    [ -e "$f" ] || missing="$missing $f"
done
if [ -n "$missing" ]; then
    echo "[mirakurun] not starting — missing file(s):$missing" >> "$LOG"
    exit 0
fi

# ACAS master key is optional for startup but required for descrambling.
if [ ! -s /data/local/tmp/.acas_key ]; then
    echo "[mirakurun] warning: /data/local/tmp/.acas_key missing — streams will be scrambled." >> "$LOG"
fi

# Singleton: if another instance is already running, exit immediately.
if [ -f "$PIDFILE" ]; then
    existing=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$existing" ] && kill -0 "$existing" 2>/dev/null; then
        echo "[mirakurun] already running (pid=$existing), exiting." >> "$LOG"
        exit 0
    fi
fi
echo $$ > "$PIDFILE"

# Free memory by stopping unused Android TV components (display, audio, camera,
# DRM, OEM apps, etc.).  OEM tuner services are also stopped here so b61dec can
# claim the ACAS smartcard.  See stop_android_tv.sh for the full list.
export LOG
sh /data/local/tmp/stop_android_tv.sh

# Kill stale processes from a previous session.
pkill -f "mirakurun-proxy" 2>/dev/null || true
pkill -f "node.*server\.js" 2>/dev/null || true
pkill -f "Mirakurun:" 2>/dev/null || true
pkill -f "tunertest_oem" 2>/dev/null || true
pkill -f "tunertest" 2>/dev/null || true
pkill -f "tuner-stream" 2>/dev/null || true
pkill -f "b61dec" 2>/dev/null || true

# --- Bind-mount host directories into the Alpine rootfs ---
mkdir -p "$ROOTFS/data/local/tmp" "$ROOTFS/system" "$ROOTFS/vendor"
mkdir -p "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/dev"

# Mount only if not already mounted (check by looking for a well-known file)
if ! test -f "$ROOTFS/data/local/tmp/mirakurun/lib/server.js"; then
    mount --bind /data/local/tmp "$ROOTFS/data/local/tmp" 2>/dev/null || true
fi
if ! test -d "$ROOTFS/system/bin"; then
    mount --bind /system "$ROOTFS/system" 2>/dev/null || true
fi
if ! test -d "$ROOTFS/vendor/lib"; then
    mount --bind /vendor "$ROOTFS/vendor" 2>/dev/null || true
fi

# Essential kernel filesystems inside chroot
mount -t proc proc "$ROOTFS/proc" 2>/dev/null || true
mount -t sysfs sysfs "$ROOTFS/sys" 2>/dev/null || true
mount -t tmpfs tmpfs "$ROOTFS/dev" 2>/dev/null || true
# Create minimal /dev nodes inside chroot
mknod -m 666 "$ROOTFS/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/zero" c 1 5 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/urandom" c 1 9 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/random" c 1 8 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/tty" c 5 0 2>/dev/null || true

# Fix Alpine's /var/run symlink (→ /run which may not exist)
rm -f "$ROOTFS/var/run" 2>/dev/null
mkdir -p "$ROOTFS/var/run" "$ROOTFS/run"

# Create Mirakurun data directories.
mkdir -p "$MIRAKURUN/db" "$MIRAKURUN/logo-data" "$MIRAKURUN/config"

# --- Launch the brick-prevention watchdog (independent of Mirakurun) ---
# crash_guard kills crash_dump32 fork-bombs and frees memory before OOM.
# Only start it if not already running.
GUARD=/data/local/tmp/crash_guard.sh
GUARD_PID=/data/local/tmp/crash_guard.pid
guard_running=0
if [ -f "$GUARD_PID" ]; then
    gp=$(cat "$GUARD_PID" 2>/dev/null)
    if [ -n "$gp" ] && kill -0 "$gp" 2>/dev/null; then
        guard_running=1
    fi
fi
if [ "$guard_running" = 0 ]; then
    setsid sh "$GUARD" >> /data/local/tmp/crash_guard.log 2>&1 &
    echo "[mirakurun] crash_guard watchdog launched (pid=$!)" >> "$LOG"
else
    echo "[mirakurun] crash_guard already running (pid=$gp)" >> "$LOG"
fi

echo "[mirakurun] Starting Mirakurun-BS4K via chroot + Alpine ARM32..." >> "$LOG"

# Ensure the mirakurun bind mount is present right before launch.
if ! test -f "$ROOTFS/data/local/tmp/mirakurun/lib/server.js"; then
    mount --bind /data/local/tmp "$ROOTFS/data/local/tmp" 2>/dev/null || true
fi

# Run Mirakurun ONCE — intentionally NO restart loop.
# On this device a crash-looping decoder can spawn a crash_dump32 fork-bomb
# and brick the box, so we never auto-restart.  If node exits, we log and
# stop; recover with `make start` or a reboot.
chroot "$ROOTFS" /bin/sh -l -c "
    export SERVER_CONFIG_PATH=/data/local/tmp/mirakurun/config/server.yml
    export TUNERS_CONFIG_PATH=/data/local/tmp/mirakurun/config/tuners.yml
    export CHANNELS_CONFIG_PATH=/data/local/tmp/mirakurun/config/channels.yml
    export SERVICES_DB_PATH=/data/local/tmp/mirakurun/db/services.json
    export PROGRAMS_DB_PATH=/data/local/tmp/mirakurun/db/programs.json
    export LOGO_DATA_DIR_PATH=/data/local/tmp/mirakurun/logo-data
    cd /data/local/tmp/mirakurun
    node --max-semi-space-size=32 \
         --max-old-space-size=256 \
         lib/server.js
" >> "$LOG" 2>&1
code=$?

echo "[mirakurun] process exited (code=$code) — not restarting (safe mode)." >> "$LOG"
rm -f "$PIDFILE" 2>/dev/null || true
exit 0
