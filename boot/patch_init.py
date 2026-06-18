#!/usr/bin/env python3
"""Apply binary patches to Android init binary for PIX-SMB400 USB Boot."""
import sys

PATCHES = [
    (0xcd1d,  b'\xd0', b'\xe0', "SELinux bypass"),
    (0x14160, b'\x2f', b'\x5f', "prop.default redirect"),
]

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/initramfs_work/init"
with open(path, 'r+b') as f:
    for offset, expected, replacement, name in PATCHES:
        f.seek(offset)
        actual = f.read(1)
        if actual == replacement:
            print(f"[=] {name}: already patched")
        elif actual == expected:
            f.seek(offset)
            f.write(replacement)
            print(f"[+] {name}: patched OK")
        else:
            print(f"[!] {name}: unexpected byte {actual.hex()} at 0x{offset:x} (wrong init version?)")
            sys.exit(1)
