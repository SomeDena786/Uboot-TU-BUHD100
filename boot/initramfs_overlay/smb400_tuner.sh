#!/system/bin/sh
# smb400-tuner.sh — tuner command wrapper for Mirakurun on SMB400.
#
# Usage (invoked by Mirakurun via tuners.yml):
#   smb400-tuner.sh <channel>
#
# Channel format determines operating mode:
#   GR:   integer 13-62    → tuner-stream-ng  (MPEG-TS, ISDB-T)
#   BS:   BSxx_y           → tuner-stream-bs  (MPEG-TS, ISDB-S)
#   BS4K: integer ≥40000   → tuner-stream-bs-ng | b61dec (descrambled TLV, ISDB-S3)
#
# BS4K descrambling note:
#   Scrambled TLV is unreadable by Mirakurun's TLVFilter → we descramble here,
#   inside the tuner command, before output.  tuners.yml sets tlvDecoder: null.
#   b61dec and tuner-stream-bs-ng run via chroot /proc/1/root to access the
#   Android linker paths required by libstationtv_*/libhi_msp.
#
# ACAS key (BS4K only): device-specific, never committed to git.
#   echo '<64-hex>' > /data/local/tmp/.acas_key ; chmod 600 /data/local/tmp/.acas_key

CHANNEL=$1
if [ -z "$CHANNEL" ]; then
    echo "smb400-tuner.sh: missing channel argument" >&2
    exit 1
fi

BINDIR=/data/local/tmp

case "$CHANNEL" in
    BS[0-9][0-9]_[0-9])
        # BS (ISDB-S): BSxx_y — extract TP number and stream index from channel name
        TPSTR=${CHANNEL#BS}       # "BS03_1" → "03_1"
        TPSTR=${TPSTR%_*}         # "03_1"   → "03"
        TP=$((TPSTR + 0))         # strip leading zero: "03" → 3
        STREAM_ID=${CHANNEL##*_}  # "BS03_1" → "1"
        IF_KHZ=$((1049480 + (TP - 1) / 2 * 38360))
        # Background + wait so we can clean up tunertest on exit
        "$BINDIR/tuner-stream-bs" 0 1 "$IF_KHZ" "$STREAM_ID" &
        BS_PID=$!
        trap "kill -9 $BS_PID 2>/dev/null; pkill -9 tunertest 2>/dev/null; exit 0" TERM INT
        wait $BS_PID
        pkill -9 tunertest 2>/dev/null || true
        ;;
    4[0-9][0-9][0-9][0-9])
        # BS4K (ISDB-S3): 5-digit stream ID — static IF frequency lookup
        ACAS_KEY=$(cat /data/local/tmp/.acas_key 2>/dev/null | tr -d '[:space:]')
        if [ -z "$ACAS_KEY" ] || [ "${#ACAS_KEY}" -ne 64 ]; then
            echo "smb400-tuner.sh: ACAS key missing or invalid at /data/local/tmp/.acas_key" >&2
            exit 1
        fi
        case "$CHANNEL" in
            45168|45169|45170) IF_KHZ=1164560 ;;  # BS7  transponder
            45232|45234)       IF_KHZ=1241280 ;;  # BS11 transponder
            45328|45329|45330) IF_KHZ=1356360 ;;  # BS17 transponder
            *) echo "smb400-tuner.sh: unknown BS4K channel '$CHANNEL'" >&2; exit 1 ;;
        esac
        # Pipeline runs in host Android context (chroot to host root) so Android
        # shared libs are accessible.  Run in background so trap fires on SIGTERM.
        chroot /proc/1/root /system/bin/sh -c \
            "$BINDIR/tuner-stream-bs-ng 0 2 $IF_KHZ $CHANNEL | $BINDIR/b61dec -key $ACAS_KEY" &
        CHROOT_PID=$!
        trap "kill -9 $CHROOT_PID 2>/dev/null; pkill -9 -f 'tuner-stream-bs-ng 0 2 $IF_KHZ' 2>/dev/null; pkill -9 -f 'b61dec -key $ACAS_KEY' 2>/dev/null; pkill -9 tunertest 2>/dev/null; exit 0" TERM INT
        wait $CHROOT_PID
        # tuner-stream-bs-ng spawns tunertest as a child but does not kill it on exit
        pkill -9 -f "tuner-stream-bs-ng 0 2 $IF_KHZ" 2>/dev/null || true
        pkill -9 tunertest 2>/dev/null || true
        ;;
    [0-9]*)
        # GR (ISDB-T): integer channel 13-62
        # ifKHz = 473143 + (ch - 13) * 6000
        IF_KHZ=$((473143 + (CHANNEL - 13) * 6000))
        exec "$BINDIR/tuner-stream-ng" 0 0 0x20 "$IF_KHZ" 6000
        ;;
    *)
        echo "smb400-tuner.sh: unknown channel format '$CHANNEL'" >&2
        exit 1
        ;;
esac
