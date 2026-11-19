# Torch Triple X DiagROM

A standalone diagnostic ROM for the 1980s Torch Triple X computer.

TorchDiagROM replaces the original Caretaker firmware with independently developed diagnostic software for the Hitachi HD6303 service processor and Motorola 68010 main processor.

Unlike the original startup sequence, TorchDiagROM can test the machine's main memory while executing entirely from video RAM. This allows it to detect memory faults that might otherwise prevent the computer from booting.

## Features — v0.9

- Independent HD6303 startup and hardware diagnostics
- 64 KB video RAM testing
- 68010 bootstrap loaded and executed from video RAM
- Full 1 MB main RAM testing
- Additional 1 MB Limpet expansion RAM testing
- Memory fault reporting, including address, expected value, actual value and XOR mask
- 68010 bus-error detection
- Audible diagnostic beep codes
- Original Torch bitmap font
- Pale-green-on-black diagnostic display with configurable palette

## Building

The project uses:

- ASxxxx (`as6801`) for HD6303 assembly
- VASM (`vasmm68k_mot`) for 68010 assembly
- Python 3 for ROM generation
- GNU Make for the build process

Build with:

```bash
make clean
make
```

See the included build documentation for input files and toolchain requirements.

## Testing

Development and testing have been carried out using the [Torch Triple X Emulator](https://github.com/Crashedfiesta/torch-triple-x-emulator).

The emulator includes optional fault-injection facilities for testing VRAM, main DRAM, Limpet expansion RAM and bus errors.

## Hardware status

Version 0.9 has been tested successfully in the emulator with healthy and deliberately faulty memory configurations.

**Operation on original Torch Triple X hardware has not yet been validated.**

## Project status

Experimental retrocomputing and hardware diagnostic project. Further development will focus on hardware compatibility, additional diagnostics and testing on a physical Torch Triple X.
