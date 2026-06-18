#!/usr/bin/env bash
# build_initramfs.sh — PIX-SMB400 initramfs_patched.uimg のビルドスクリプト
#
# 使い方:
#   bash release/boot/build_initramfs.sh <firmware_cpio>
#
#   <firmware_cpio>: kernel.img を binwalk で展開して取り出した initramfs cpio ファイル
#                   例: _kernel.img.extracted/988000
#
# 必要なもの: docker, python3
# 出力: release/boot/initramfs_patched.uimg（上書き）
#
# 詳細は release/BOOT.md を参照。

set -euo pipefail

CPIO_SRC="${1:-}"
if [ -z "$CPIO_SRC" ]; then
    echo "Usage: bash $(basename "$0") <path/to/cpio_file>"
    echo "  例: bash boot/build_initramfs.sh /path/to/_kernel.img.extracted/988000"
    exit 1
fi

if [ ! -f "$CPIO_SRC" ]; then
    echo "[!] ファイルが見つかりません: $CPIO_SRC"
    echo "    kernel.img を binwalk で展開し、取り出した cpio ファイルを指定してください。"
    exit 1
fi

# 後続で作業ディレクトリへ cd するため、相対パスをここで絶対パスに解決しておく。
CPIO_ABS="$(realpath "$CPIO_SRC")"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY_DIR="$SCRIPT_DIR/initramfs_overlay"
PATCH_SCRIPT="$SCRIPT_DIR/patch_init.py"
WORK_DIR="${WORK_DIR:-/tmp/smb400_initramfs_work}"
OUT="$SCRIPT_DIR/initramfs_patched.uimg"

echo "[*] Work dir: $WORK_DIR"
echo "[*] CPIO src: $CPIO_SRC"
echo "[*] Overlay:  $OVERLAY_DIR"
echo "[*] Output:   $OUT"
echo ""

# --- 1. initramfs を展開 ---
rm -rf "$WORK_DIR" && mkdir -p "$WORK_DIR"
echo "[*] initramfs を展開中..."
(cd "$WORK_DIR" && cpio -idm --no-absolute-filenames -F "$CPIO_ABS" 2>/dev/null)
echo "[+] 展開完了"

# --- 2. init バイナリにパッチ ---
echo "[*] init バイナリにパッチを適用中..."
python3 "$PATCH_SCRIPT" "$WORK_DIR/init"

# --- 3. オーバーレイを適用 ---
echo "[*] オーバーレイを適用中..."

# default.prop: 元の initramfs ではシンボリックリンク → 実ファイルに置き換え
rm -f "$WORK_DIR/default.prop"
cp "$OVERLAY_DIR/default.prop"          "$WORK_DIR/default.prop"
cp "$OVERLAY_DIR/dhclient.conf"         "$WORK_DIR/dhclient.conf"
cp "$OVERLAY_DIR/init.pixboot.rc"       "$WORK_DIR/init.pixboot.rc"
cp "$OVERLAY_DIR/init_pix_netdbg.sh"    "$WORK_DIR/init_pix_netdbg.sh"
mkdir -p "$WORK_DIR/initrc"
cp "$OVERLAY_DIR/initrc/logd.rc"        "$WORK_DIR/initrc/logd.rc"

# デバイス起動時に /data/local/tmp/ に自動デプロイされるスクリプト群
cp "$OVERLAY_DIR/start_proxy.sh"     "$WORK_DIR/start_proxy.sh"
cp "$OVERLAY_DIR/crash_guard.sh"     "$WORK_DIR/crash_guard.sh"
cp "$OVERLAY_DIR/stop_android_tv.sh" "$WORK_DIR/stop_android_tv.sh"
cp "$OVERLAY_DIR/smb400_tuner.sh"    "$WORK_DIR/smb400_tuner.sh"

# init.rc への import 挿入（冪等）
if ! grep -q 'import /init.pixboot.rc' "$WORK_DIR/init.rc"; then
    sed -i '0,/^import \/init\.usb\.rc$/s||import /init.usb.rc\nimport /init.pixboot.rc|' \
        "$WORK_DIR/init.rc"
    echo "[+] init.rc: import /init.pixboot.rc を挿入"
else
    echo "[=] init.rc: import /init.pixboot.rc は既に存在"
fi

echo "[+] オーバーレイ適用完了"

# --- 4. パーミッション設定 ---
find "$WORK_DIR" -name "*.rc"  | xargs chmod 644
find "$WORK_DIR" -name "*.sh"  | xargs chmod 755
chmod 755 "$WORK_DIR/init"
chmod 644 "$WORK_DIR/default.prop" "$WORK_DIR/dhclient.conf"

# --- 5. Docker で cpio + uimg をビルド ---
echo "[*] Docker で uimg をビルド中..."
mkdir -p "$(dirname "$OUT")"

docker run --rm \
    -v "$WORK_DIR:/initramfs_work" \
    -v "$(dirname "$OUT"):/out" \
    ubuntu:22.04 bash -c "
apt-get update -qq && apt-get install -y -qq u-boot-tools cpio gzip 2>/dev/null
cd /initramfs_work
find . | sort | cpio -o -H newc 2>/dev/null | gzip -9 > /tmp/initramfs_patched.cpio.gz
mkimage -A arm -O linux -T ramdisk -C gzip \
    -a 0x04000000 -e 0x04000000 \
    -n 'patched-initramfs' \
    -d /tmp/initramfs_patched.cpio.gz \
    /out/initramfs_patched.uimg
echo '[+] ビルド完了'
ls -lh /out/initramfs_patched.uimg
"

echo ""
echo "[+] 完了: $OUT"
