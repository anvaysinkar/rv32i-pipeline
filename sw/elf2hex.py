#!/usr/bin/env python3
"""elf2hex.py - turn a flat binary into a $readmemh file (one 32-bit word per line).

usage: elf2hex.py input.bin output.hex
"""
import sys

def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    data += b"\x00" * (-len(data) % 4)
    if not data:                 # keep $readmemh happy when a section is empty
        data = b"\x00" * 4
    with open(sys.argv[2], "w") as f:
        for i in range(0, len(data), 4):
            f.write("%08x\n" % int.from_bytes(data[i:i + 4], "little"))

if __name__ == "__main__":
    main()
