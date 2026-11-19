#!/usr/bin/env python3
"""Embed 68010 bank-1 code, original Torch font and reset vectors into 6303 ROM.
ROM: D000-D7FF = 68010 code, D800-DAFF = font, DB00-DB0B = vectors.
SP copies them into separate physical VRAM regions before host release.
"""
from pathlib import Path
import argparse, zlib
p=argparse.ArgumentParser()
p.add_argument('base',type=Path)
p.add_argument('bootstrap',type=Path)
p.add_argument('font',type=Path)
p.add_argument('output',type=Path)
a=p.parse_args()
rom=bytearray(a.base.read_bytes())
raw=a.bootstrap.read_bytes()
font=a.font.read_bytes()
if len(rom)!=0x4000: raise SystemExit('Expected 16K 6303 ROM')
if len(font)!=760: raise SystemExit('Expected 760 font bytes')
if font[(ord('A')-32)*8:(ord('A')-32)*8+8].hex()!='183c66667e666600':
    raise SystemExit('Font signature incorrect')
# VASM -Fbin with .org $0 and .org $8000 should output the gap.
if not 0x8000 < len(raw) <= 0x8800:
    raise SystemExit(f'Expected full sparse 68010 image of 0x8001..0x8800 bytes, got 0x{len(raw):X}; check VASM listing/origin')
vec=raw[:12]
if vec[:4]!=bytes.fromhex('0000F7F0'): raise SystemExit('Bad 68010 SSP')
pc=int.from_bytes(vec[4:8],'big')
berr=int.from_bytes(vec[8:12],'big')
if not (0x8000<=pc<len(raw) and 0x8000<=berr<len(raw)):
    raise SystemExit(f'68010 vectors not in bank-1 code: PC={pc:08X}, BERR={berr:08X}')
code=raw[0x8000:]
if any(raw[12:0x8000]):
    raise SystemExit('68010 assembly unexpectedly emitted bytes in reserved gap $000C..$7FFF')
if any(rom[off:off+size] != b'\xff'*size for off,size in ((0x1000,0x800),(0x1800,0x300),(0x1B00,12))):
    raise SystemExit('6303 machine code overlaps reserved D000-DB0B payload')
rom[0x1000:0x1800]=code.ljust(0x800,b'\xff')
rom[0x1800:0x1B00]=font.ljust(0x300,b'\0')
rom[0x1B00:0x1B0C]=vec
if rom[0x3FFE:0x4000] != bytes.fromhex('C000'):
    raise SystemExit('Invalid HD6303 reset vector')
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_bytes(rom)
print(f'Created {a.output}: 16KB ROM, 68010 code {len(code)} bytes, Torch font {len(font)} bytes')
print(f'68010 PC ${pc:08X}, BERR handler ${berr:08X}, SSP $0000F7F0, CRC32 {zlib.crc32(rom):08X}')
