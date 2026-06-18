#!/system/bin/sh
# stop_android_tv.sh — free memory by stopping unused Android TV components.
#
# Called automatically by start_mirakurun.sh.
# Safe to run multiple times (idempotent).
#
# What is stopped:
#   - Java apps: OEM TV apps, streaming services, launcher, Google apps
#     (force-stopped processes won't restart unless explicitly launched)
#   - Init services: audio, camera, Bluetooth, DRM, media playback, IR, CEC
#
# What is deliberately left running:
#   - adbd         : ADB access
#   - netd/wificond/wpa_supplicant : TCP networking (ADB over Wi-Fi/LAN)
#   - surfaceflinger/gralloc/hwcomposer : stopping surfaceflinger causes
#     WindowManagerService to crash -> system_server restart -> everything
#     restarts. The ~13 MB cost is acceptable.
#   - zygote/system_server/lmkd : Android core — must not stop
#   - teecd/keymaster/keystore  : TEE / secure storage (used by some HALs)
#   - vold/healthd              : storage + battery monitoring

LOG=${LOG:-/data/local/tmp/mirakurun.log}
_log() { echo "[stop_atv] $*" >> "$LOG"; }

_mem() { grep MemAvailable /proc/meminfo | tr -dc '0-9'; }

_log "=== starting: MemAvailable=$(_mem) kB ==="

# ============================================================
# 1. OEM tuner / ACAS card holder (must go first so b61dec can claim the card)
# ============================================================
stop pix_airtuner  2>/dev/null || true
stop airtuner      2>/dev/null || true
stop airtuner_4k   2>/dev/null || true
pkill -9 tunertest_oem 2>/dev/null || true
pkill -9 tunertest     2>/dev/null || true
pkill -9 airtuner  2>/dev/null || true
_log "OEM tuner services stopped"

# ============================================================
# 2. Java apps — am force-stop frees the RSS immediately;
#    Android does not auto-restart stopped apps.
# ============================================================
am force-stop jp.pixela.xit.smarttuner           2>/dev/null || true  # 178+66 MB OEM tuner app
am force-stop jp.pixela.atv_app                  2>/dev/null || true  # 160 MB  OEM main UI
am force-stop jp.pixela.system.px_setup          2>/dev/null || true  #  76 MB
am force-stop jp.pixela.system.pxprecoresetup    2>/dev/null || true  #  55 MB
am force-stop jp.pixela.system.pxbizsettings     2>/dev/null || true  #  62 MB
am force-stop jp.pixela.system.pxchannel         2>/dev/null || true  #  57 MB
am force-stop jp.pixela.system.px_event_service  2>/dev/null || true  #  53 MB
am force-stop jp.pixela.system.pxhwservice       2>/dev/null || true  #  69 MB
am force-stop jp.pixela.pis_iot_edge             2>/dev/null || true  #  55 MB
am force-stop jp.happyon.android                 2>/dev/null || true  # 164 MB  streaming
am force-stop com.netflix.ninja                  2>/dev/null || true  # 177 MB  streaming
am force-stop com.android.vending                2>/dev/null || true  # 149 MB  Play Store
am force-stop com.google.android.tvlauncher      2>/dev/null || true  # 138 MB  TV launcher
am force-stop com.google.android.katniss         2>/dev/null || true  # 230 MB  voice assistant
am force-stop com.google.android.apps.mediashell 2>/dev/null || true  # 133 MB  Chromecast
am force-stop com.google.android.videos          2>/dev/null || true  # 108 MB  TV video app
am force-stop com.google.android.webview         2>/dev/null || true  # 174 MB  WebView
am force-stop com.google.android.backdrop        2>/dev/null || true  # 198 MB  ambient display (restarts WebView + binder spam)
am force-stop com.google.android.tvrecommendations 2>/dev/null || true # 103 MB
am force-stop com.google.android.tv             2>/dev/null || true   #  69 MB
am force-stop com.google.android.remote.tv.services 2>/dev/null || true # 64 MB
am force-stop com.google.android.partnersetup   2>/dev/null || true   #  54 MB
am force-stop com.android.providers.tv          2>/dev/null || true   #  63 MB
am force-stop com.android.tv.settings           2>/dev/null || true   #  96 MB
am force-stop com.android.systemui              2>/dev/null || true   #  88 MB  (no display needed)
am force-stop com.android.bluetooth             2>/dev/null || true   #  78 MB  (no BT needed)
am force-stop com.google.android.inputmethod.latin 2>/dev/null || true #  87 MB  (no keyboard)
am force-stop com.google.process.gapps          2>/dev/null || true
am force-stop com.hisilicon.android.hiRMService 2>/dev/null || true   #  66 MB
# GMS (com.google.android.gms.persistent / .gms) is a persistent service;
# force-stop is attempted but it will quickly restart — acceptable.
am force-stop com.google.android.gms            2>/dev/null || true
_log "Java apps force-stopped"

# ============================================================
# 3. Init services — only stop HALs with NO restarting app clients.
#
# Audio / DRM / Media / Display HALs are intentionally left running.
# Stopping them causes restarted background apps (videos, backdrop, webview)
# to hold dead hwbinder handles and flood the kernel binder log with
# BR_DEAD_REPLY (0x7205) spam indefinitely.  The per-process memory cost of
# these HALs is 1–15 MB each — not worth the binder damage.
# ============================================================

# Camera (no camera app restarts after force-stop)
stop camera-provider-2-4  2>/dev/null || true
stop cameraserver         2>/dev/null || true

# HDMI CEC (no CEC app restarts)
stop cec-hal-1-0     2>/dev/null || true

# Bluetooth (no BT app restarts)
stop bluetooth-1-0   2>/dev/null || true

# IR remote receiver (not needed, no restart)
stop ir_user         2>/dev/null || true

# Package installer (not installing apps)
stop installd        2>/dev/null || true

# Storage / stats daemons (not needed at runtime)
stop storaged        2>/dev/null || true

_log "Init services stopped"

# ============================================================
# 4. Drop caches to reclaim page cache from killed processes
# ============================================================
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

sleep 1
_log "=== done: MemAvailable=$(_mem) kB ==="
