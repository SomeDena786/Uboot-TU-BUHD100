#!/system/bin/sh
# crash_guard.sh — brick-prevention watchdog for SMB400 Mirakurun.
#
# Background:
#   On Android 8 a crashing process's own debuggerd handler forks crash_dump32.
#   Under memory pressure crash_dump32 itself crashes during ELF load, forking
#   another crash_dump32 — a self-sustaining fork bomb that exhausted kernel
#   slab/pagetables and bricked the device (required USB rescue boot).
#
# This watchdog runs OUTSIDE the Alpine chroot, in the Android shell, as a
# lightweight independent loop. It does three things every POLL seconds:
#   1. If crash_dump32 count > CD_MAX  -> kill the chain + Node.
#   2. If MemAvailable < MEM_SOFT_KB   -> run stop_android_tv.sh to reclaim
#      memory from restarted Android TV apps (they drift back over time).
#   3. If MemAvailable < MEM_FLOOR_KB  -> kill Node as last resort before OOM.

POLL=5                 # seconds between checks
CD_MAX=4               # max tolerated concurrent crash_dump32 processes
MEM_SOFT_KB=600000     # reclaim from Android TV apps when below this (kB)
MEM_FLOOR_KB=350000    # kill Node if MemAvailable still below this after reclaim
RECLAIM_COOLDOWN=120   # minimum seconds between stop_android_tv.sh calls
STOP_ATV=/data/local/tmp/stop_android_tv.sh
LOG=/data/local/tmp/crash_guard.log

# Ignore SIGTERM so no accidental kill brings down the watchdog.
trap '' TERM INT

# Give ourselves CPU priority so we still run under memory pressure.
renice -n -5 $$ 2>/dev/null || true

# Record our PID for the singleton check in start_mirakurun.sh.
echo $$ > /data/local/tmp/crash_guard.pid

echo "[crash_guard] started pid=$$ POLL=${POLL}s CD_MAX=${CD_MAX} MEM_SOFT=${MEM_SOFT_KB}kB MEM_FLOOR=${MEM_FLOOR_KB}kB" >> "$LOG"

last_reclaim=0

while true; do
    # --- 1. crash_dump32 fork-bomb detection ---
    cd_count=$(pgrep crash_dump32 2>/dev/null | wc -l)
    if [ "$cd_count" -gt "$CD_MAX" ]; then
        echo "[crash_guard] crash_dump32 count=$cd_count > $CD_MAX — killing chain + Node" >> "$LOG"
        pkill -9 crash_dump32 2>/dev/null
        pkill -9 -f "lib/server.js" 2>/dev/null
        pkill -9 -f "Mirakurun:" 2>/dev/null
        pkill -9 node 2>/dev/null
    fi

    # --- 2. soft memory threshold: reclaim from Android TV apps ---
    mem=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -dc '0-9')
    [ -z "$mem" ] && mem=999999
    now=$(date +%s 2>/dev/null || echo 0)
    elapsed=$((now - last_reclaim))
    if [ "$mem" -lt "$MEM_SOFT_KB" ] && [ "$elapsed" -gt "$RECLAIM_COOLDOWN" ]; then
        echo "[crash_guard] MemAvailable=${mem}kB < ${MEM_SOFT_KB}kB — reclaiming from Android TV apps" >> "$LOG"
        sh "$STOP_ATV" 2>/dev/null
        last_reclaim=$now
        mem=$(grep MemAvailable /proc/meminfo 2>/dev/null | tr -dc '0-9')
        [ -z "$mem" ] && mem=999999
        echo "[crash_guard] after reclaim: MemAvailable=${mem}kB" >> "$LOG"
    fi

    # --- 3. hard floor: kill Node if still critical after reclaim ---
    if [ "$mem" -lt "$MEM_FLOOR_KB" ]; then
        echo "[crash_guard] MemAvailable=${mem}kB < ${MEM_FLOOR_KB}kB — killing Node to prevent OOM" >> "$LOG"
        pkill -9 -f "lib/server.js" 2>/dev/null
        pkill -9 -f "Mirakurun:" 2>/dev/null
        pkill -9 node 2>/dev/null
        pkill -9 crash_dump32 2>/dev/null
    fi

    sleep "$POLL"
done
