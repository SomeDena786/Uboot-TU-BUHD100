# TU-BUHD100 USB Boot (root ADB)

[pix-smb400-mirakurun](https://github.com/tsuyopon123/pix-smb400-mirakurun) を
TU-BUHD100 (Panasonic OEM, Hi3798CV200) 向けに修正したもの。

## PIX-SMB400 との差分

| ファイル | 変更内容 | 理由 |
|---|---|---|
| `boot/initramfs_overlay/default.prop` | `persist.sys.usb.config=none` → `adb`、`service.adb.tcp.port=5555` 追加 | 元の `none` だと init.usb.rc が adbd を SIGKILL するため |
| `boot/make_usb_boot.py` | `phy_addr=2,1` → `phy_addr=2,3` | TU-BUHD100 の Ethernet PHY アドレスが異なる (f9841000, rgmii, phy_addr=3) |
| `kernel_tubuhd100.img` | TU-BUHD100 ファームウェアから抽出したカーネル | initramfs の cpio ソースに使用。init バイナリは SMB400 と同一 (MD5: 9ce50b95ce81a86f3bf8e4b42bbb9faa) |

それ以外のファイル (`patch_init.py`, `build_initramfs.sh`, overlay スクリプト群) は
オリジナルと同一。

## ディレクトリ構成

```
TU-BUHD100/
├── README.md                          このファイル
├── kernel_tubuhd100.img               ビルドに必要なカーネルイメージ (11,370,752 bytes)
└── boot/
    ├── build_initramfs.sh             initramfs ビルドスクリプト (Docker 使用)
    ├── make_usb_boot.py               bootargs.bin / root_rsa_pub_crc.bin 生成
    ├── patch_init.py                  init バイナリパッチ (SELinux bypass + prop redirect)
    ├── get_kernel.sh                  カーネル抽出ヘルパー
    ├── initramfs_patched.uimg         ビルド済み initramfs (そのまま USB にコピー可)
    ├── initramfs_overlay/             initramfs に適用するオーバーレイファイル群
    │   ├── default.prop               ★ 修正済み (persist.sys.usb.config=adb)
    │   ├── init.pixboot.rc            起動時サービス定義
    │   ├── init_pix_netdbg.sh         Ethernet DHCP + ADB IP 通知
    │   ├── dhclient.conf
    │   ├── initrc/logd.rc
    │   ├── crash_guard.sh
    │   ├── smb400_tuner.sh
    │   ├── start_proxy.sh
    │   └── stop_android_tv.sh
    └── usb_boot_files/                ビルド済み USB ブートファイル
        ├── bootargs.bin               ★ 修正済み (phy_addr=2,3)
        ├── root_rsa_pub_crc.bin       RSA 公開鍵 + CRC
        └── rsa_key.pem                RSA 秘密鍵 (再ビルド時に必要)
```

## USB メモリの準備 (ビルド済みファイルを使う場合)

```bash
# USB メモリを FAT32 でフォーマットし、以下の 3 ファイルをルートにコピー:
#   boot/usb_boot_files/bootargs.bin
#   boot/usb_boot_files/root_rsa_pub_crc.bin
#   boot/initramfs_patched.uimg
```

## ゼロからビルドする場合

```bash
# 1. initramfs をビルド (Docker 必要、python3 + pycryptodome 必要)
#    kernel_tubuhd100.img を binwalk で展開して cpio を取り出す
binwalk -e kernel_tubuhd100.img
bash boot/build_initramfs.sh _kernel_tubuhd100.img.extracted/988000

# 2. bootargs.bin / root_rsa_pub_crc.bin を生成
pip install pycryptodome
python3 boot/make_usb_boot.py

# 3. USB メモリにコピー
#    bootargs.bin, root_rsa_pub_crc.bin, initramfs_patched.uimg → USB ルート
```

## 起動手順

1. USB メモリを TU-BUHD100 の USB ポートに挿す
2. USB ブートピンをショートしながら電源 ON
3. シリアルコンソール (115200 8N1) で起動ログを確認
4. `PIXDBG: *** ADB: adb connect <IP>:5555 ***` または `ip addr show eth0` で IP 確認
5. `adb connect <IP>:5555` で接続

```
$ adb connect 10.0.5.29:5555
connected to 10.0.5.29:5555

$ adb -s 10.0.5.29:5555 shell id
uid=0(root) gid=0(root) ... context=u:r:su:s0
```

`uid=2000(shell)` の場合は eMMC 通常ブート (USB ブート失敗)。

## ファームウェア
※解凍に必要なパスワードはPIX-SMB400のものと同一みたい

## 検証環境
Rev.24.24 (恐らく最新版にしてから導入した方がいいかも）
