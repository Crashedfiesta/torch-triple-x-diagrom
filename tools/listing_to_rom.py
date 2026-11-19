#!/usr/bin/env python3
"""Strictly extract ASxxxx HD6303 absolute listing bytes into a 16K EPROM.

Designed only for this one-module, no-relocations ROM experiment.
Use aslink/IHX for larger or relocatable multi-module projects.
"""
import argparse
from pathlib import Path
import re
import struct
import zlib

parser = argparse.ArgumentParser()
parser.add_argument('listing', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()

rom = bytearray([0xFF] * 0x4000)
seen = set()
count = 0
# ASxxxx listing lines: "   C000 0F ... [ 2]  10  sei"
# We accept an address followed by consecutive full 2-digit byte tokens,
# ending before the [cycle count] or source line number.
for lineno, line in enumerate(args.listing.read_text().splitlines(), 1):
    # ASxxxx places machine bytes immediately after the address, separated
    # by SINGLE spaces. Label-only rows have a wide blank field before the
    # source line number; never treat that number as assembled data.
    m = re.match(r'^\s{3}([0-9A-Fa-f]{4}) ((?:[0-9A-Fa-f]{2} )+)', line)
    if not m:
        continue
    addr = int(m.group(1), 16)
    values = [int(part, 16) for part in m.group(2).split()]
    for j, val in enumerate(values):
        at = addr + j
        if not 0xC000 <= at <= 0xFFFF:
            raise SystemExit(f'ERROR: output byte outside ROM at ${at:04X} (listing line {lineno})')
        if at in seen:
            raise SystemExit(f'ERROR: duplicate byte at ${at:04X} (listing line {lineno})')
        seen.add(at)
        rom[at - 0xC000] = val
        count += 1

if count < 60:
    raise SystemExit(f'ERROR: extracted only {count} bytes; check .lst format')
if not all(a in seen for a in (0xC000, 0xC001, 0xC002, 0xFFFE, 0xFFFF)):
    raise SystemExit('ERROR: missing program start or reset vector')
if rom[0] != 0x0F:  # SEI opcode
    raise SystemExit(f'ERROR: unexpected first opcode ${rom[0]:02X}; wanted SEI (0F)')
if rom[0x3FFE:0x4000] != b'\xC0\x00':
    raise SystemExit('ERROR: reset vector must point to $C000')
if any(rom[pos:pos+2] != b'\xC0\x00' for pos in range(0x3FF0,0x4000,2)):
    raise SystemExit('ERROR: unexpected exception vector')
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_bytes(rom)
print(f'Created {args.output} ({len(rom)} bytes; {count} assembled bytes)')
print(f'Reset vector: ${struct.unpack_from(">H",rom,0x3FFE)[0]:04X}; CRC32: {zlib.crc32(rom):08X}')
