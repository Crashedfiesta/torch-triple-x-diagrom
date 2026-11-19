#!/usr/bin/env python3
"""Extract the original ERMA 8x8 ASCII font from the 16KB Caretaker v1.3 ROM."""
from pathlib import Path
import argparse
p=argparse.ArgumentParser()
p.add_argument('caretaker_rom',type=Path)
p.add_argument('output',type=Path)
a=p.parse_args()
r=a.caretaker_rom.read_bytes()
if len(r)!=16384: raise SystemExit('Caretaker ROM must be 16384 bytes')
# ERMA embedded in ROM at offset $1000; font at ERMA offset $21F8.
f=r[0x31F8:0x31F8+95*8]
if f[(ord('A')-32)*8:(ord('A')-32)*8+8].hex()!='183c66667e666600':
    raise SystemExit('Font signature mismatch: expected Caretaker V1.3')
a.output.write_bytes(f)
print(f'Extracted {len(f)} font bytes to {a.output}')
