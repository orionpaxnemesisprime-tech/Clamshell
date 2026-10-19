#!/usr/bin/env python3
# Builds a homebrew test ROM from ARM9/ARM7 assembly using Xcode's clang (no devkit needed).
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: Scripts/make-test-rom.py <rom-source-dir> <output.nds>
#
# The source dir holds arm9.s and arm7.s. Both must be position-independent within one
# .text section (no relocations); they are loaded at fixed addresses by direct boot.
# The header deliberately leaves the logo area zeroed: Clamshell boots with FreeBIOS, which
# does not check it, and we never ship third-party logo data.

import hashlib
import os
import struct
import subprocess
import sys
import tempfile

ARM9_ADDRESS = 0x02000000
ARM7_ADDRESS = 0x037F8000
ARM9_ROM_OFFSET = 0x200  # < 0x4000 marks the image as homebrew for melonDS
MIN_ROM_SIZE = 0x1000


def assemble(source, cpu_arch):
    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, "out.o")
        subprocess.run(
            ["xcrun", "clang", f"--target={cpu_arch}-none-eabi", "-c", source, "-o", obj],
            check=True,
        )
        with open(obj, "rb") as f:
            return text_section(f.read(), source)


def text_section(elf, name):
    if elf[:4] != b"\x7fELF" or elf[4] != 1 or elf[5] != 1:
        sys.exit(f"{name}: expected a 32-bit little-endian ELF object")
    shoff, = struct.unpack_from("<I", elf, 0x20)
    shentsize, shnum, shstrndx = struct.unpack_from("<HHH", elf, 0x2E)

    def section(i):
        return struct.unpack_from("<IIIIIIIIII", elf, shoff + i * shentsize)

    strtab = section(shstrndx)
    names = elf[strtab[4]:strtab[4] + strtab[5]]

    text = None
    for i in range(shnum):
        sh_name, sh_type, _, _, offset, size, *_ = section(i)
        sec_name = names[sh_name:names.index(b"\0", sh_name)].decode()
        if sh_type in (4, 9) and sec_name.endswith(".text"):  # SHT_RELA, SHT_REL
            sys.exit(f"{name}: has relocations; code must be position-independent")
        if sec_name == ".text":
            text = elf[offset:offset + size]
    if not text:
        sys.exit(f"{name}: no .text section")
    return text


def align(value, alignment):
    return (value + alignment - 1) & ~(alignment - 1)


def crc16(data):
    crc = 0xFFFF
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def build(src_dir, title):
    arm9 = assemble(os.path.join(src_dir, "arm9.s"), "armv5te")
    arm7 = assemble(os.path.join(src_dir, "arm7.s"), "armv4t")
    arm9 += b"\0" * (align(len(arm9), 4) - len(arm9))
    arm7 += b"\0" * (align(len(arm7), 4) - len(arm7))

    arm7_offset = align(ARM9_ROM_OFFSET + len(arm9), 0x200)
    used_size = arm7_offset + len(arm7)

    header = bytearray(0x200)
    header[0x000:0x00C] = title.upper().encode("ascii")[:12].ljust(12, b"\0")
    header[0x00C:0x010] = b"####"  # homebrew game code
    header[0x010:0x012] = b"00"
    struct.pack_into("<IIII", header, 0x020, ARM9_ROM_OFFSET, ARM9_ADDRESS, ARM9_ADDRESS, len(arm9))
    struct.pack_into("<IIII", header, 0x030, arm7_offset, ARM7_ADDRESS, ARM7_ADDRESS, len(arm7))
    struct.pack_into("<II", header, 0x080, used_size, 0x4000)
    struct.pack_into("<H", header, 0x15E, crc16(header[:0x15E]))

    rom = bytearray(max(MIN_ROM_SIZE, align(used_size, 0x200)))
    rom[:0x200] = header
    rom[ARM9_ROM_OFFSET:ARM9_ROM_OFFSET + len(arm9)] = arm9
    rom[arm7_offset:arm7_offset + len(arm7)] = arm7
    return bytes(rom)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__ or "usage: make-test-rom.py <rom-source-dir> <output.nds>")
    src_dir, output = sys.argv[1], sys.argv[2]
    rom = build(src_dir, os.path.basename(os.path.normpath(src_dir)))
    with open(output, "wb") as f:
        f.write(rom)
    print(f"{output}: {len(rom)} bytes, sha256 {hashlib.sha256(rom).hexdigest()}")


if __name__ == "__main__":
    main()
