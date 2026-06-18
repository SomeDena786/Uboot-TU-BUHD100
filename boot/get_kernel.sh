#!/usr/bin/env bash
# get_kernel.sh — Extract kernel.img from PIX-SMB400 firmware
#
# Usage:
#   bash get_kernel.sh [-o <output_dir>]
#
# Requires: wget or curl, unzip, openssl
# Output: <output_dir>/kernel.img  (default: current directory)

set -euo pipefail

FIRMWARE_URL="https://www.pixela.co.jp/products/smarttuner/pix_smb400/data/pix_smb400_rev24.24.zip"
ZIP_NAME="pix_smb400_rev24.24.zip"
ENC_NAME="update_pix_smb400_rev24.24.enc"
BIN_NAME="update_pix_smb400_rev24.24.bin"

OUTPUT_DIR="."

usage() {
    echo "Usage: bash $(basename "$0") [-o <output_dir>]"
    echo "  -o <dir>   output directory for kernel.img (default: .)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "[!] unknown option: $1"; usage ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# --- 1. Download ---
echo "[*] Downloading: $FIRMWARE_URL"
if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$WORK_DIR/$ZIP_NAME" "$FIRMWARE_URL"
else
    curl -# -L -o "$WORK_DIR/$ZIP_NAME" "$FIRMWARE_URL"
fi
echo "[+] Download complete"

# --- 2. Unzip -> .enc ---
echo "[*] Extracting ZIP..."
unzip -q "$WORK_DIR/$ZIP_NAME" -d "$WORK_DIR"
echo "[+] Extracted: $ENC_NAME"

# --- 3. Decrypt -> .bin (Android OTA zip) ---
# openssl exits non-zero due to non-standard padding; || true lets us verify the output ourselves
echo "[*] Decrypting (AES-256-CBC)..."
openssl aes-256-cbc -d \
    -in  "$WORK_DIR/$ENC_NAME" \
    -out "$WORK_DIR/$BIN_NAME" \
    -md md5 \
    -pass "pass:;0]nD<JU2ruvl&:'*n0O" 2>&1 | grep -v "deprecated key derivation" || true
python3 -c "import zipfile, sys; sys.exit(0 if zipfile.is_zipfile('$WORK_DIR/$BIN_NAME') else 1)" \
    || { echo "[!] Decryption failed: output is not a valid zip"; exit 1; }
echo "[+] Decryption complete"

# --- 4. Extract boot.img, strip 0x6000-byte HiSilicon header -> kernel.img ---
echo "[*] Extracting boot.img..."
unzip -q -o "$WORK_DIR/$BIN_NAME" boot.img -d "$WORK_DIR"
echo "[*] Stripping HiSilicon header (0x6000 bytes) -> kernel.img..."
dd if="$WORK_DIR/boot.img" of="$OUTPUT_DIR/kernel.img" bs=24576 skip=1 2>/dev/null

echo ""
echo "[+] Done: $OUTPUT_DIR/kernel.img"
ls -lh "$OUTPUT_DIR/kernel.img"
