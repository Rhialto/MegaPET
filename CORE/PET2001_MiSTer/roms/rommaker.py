#! /usr/pkg/bin/python3.10

import argparse
import os.path
import sys
from typing import List

ROM = [0] * 65536

# A table with start addresses and hints when those might apply.
# Most general are strings that indicate "kernel" or "editor" since
# those have the same start address in all versions.
# "basic" could begin at either B000 (version 4) or C000 (1+2).
# There are too many editor roms to mention but all start at E000.
# Some are 2 KB, some are 4 KB.

start_addresses = {
        0x9000: ["9000"],
        0xa000: ["a000"],
        0xb000: ["b000", "901465-19", "901465-23", "basic-4",],
        0xc000: ["c000", "901439-01", "901447-01", "901439-09", "901447-09", "basic-1",
                         "901465-01", "901439-13", "901447-20", "basic-2",
                         "901465-20"],               # basic-4
        0xc800: ["c800", "901439-05", "901447-02",   # basic-1
                         "901447-21", ],             # basic-2
        0xd000: ["d000", "901439-02", "901447-03",   # basic-1
                         "901465-02", "901439-15",  "901447-22",  # basic-2
                         "901465-21"],               # basic-4
        0xd800: ["d800", "901439-06", "901447-04",   # basic-1
                         "901439-16", "901447-23"],  # basic-2
        0xe000: ["e000", "edit",
                         "901439-03", "901447-04",   # edit-1
                         "901439-17", "901447-24",   # edit-2
                         "901499-01", "901474-04", "901474-02"],
        0xef00: ["ef00"],
        0xf000: ["f000", "901439-04",  "901447-06",  # kernel-1
                         "901465-03", "901439-18", "901447-25",   # kernel-2
                         "901465-22",                # kernel-4
                         "kernel", "kernal",],
        0xf800: ["f800", "901439-07", "901447-07",   # kernel-1
                         "901439-19", "901447-26",]  # kernel-2
};

presets = {
        "2001":         [ "basic-1.901439-09-05-02-06.bin", "edit-1-n.901439-03.bin",          "kernal-1.901439-04-07.bin", ],
        "2001+ieee":    [ "basic-1.901439-09-05-02-06.bin", "edit-1-n.901439-03.bin",          "kernal-1.ef00-901439-04-07+ieee-patch.bin", ],
        "3032":         [ "basic-2.901465-01-02.bin",       "edit-2-n.901447-24.bin",          "kernal-2.901465-03.bin", ],
        "3032b":        [ "basic-2.901465-01-02.bin",       "edit-2-b.901474-01.bin",          "kernal-2.901465-03.bin", ],
        "4032n-nocrtc": [ "basic-4.901465-23-20-21.bin",    "edit-4-n.901447-29.bin",          "kernal-4.901465-22.bin", ],
        "4032b-nocrtc": [ "basic-4.901465-23-20-21.bin",    "edit-4-b.901474-02.bin",          "kernal-4.901465-22.bin", ],
        "4032n":        [ "basic-4.901465-23-20-21.bin",    "edit-4-40-n-50Hz.901498-01.bin",  "kernal-4.901465-22.bin", ],
        "4032b":        [ "basic-4.901465-23-20-21.bin",    "edit-4-40-b-50Hz.ts.bin",         "kernal-4.901465-22.bin", ],
        "8032b":        [ "basic-4.901465-23-20-21.bin",    "edit-4-80-b-50Hz.901474-04_.bin", "kernal-4.901465-22.bin", ],
};

def find_start_address(name, guess):
    lname = name.lower()

    for addr in sorted(start_addresses.keys()):
        for txt in start_addresses[addr]:
            if txt in lname:
                print(f"Choosing {addr:#04x} for file '{name}' because of '{txt}'.")
                return addr

    if guess is None or guess > 0xFFFF:
        guess = 0x8000

    print(f"I don't know about file '{name}' so I just guess {guess:#04x}.")

    return guess

def add_file_data(name, data, guess):
    start = find_start_address(name, guess)

    a = start
    for byte in data:
        ROM[a] = int(byte)
        a += 1

    # The new value for `guess` will be just after this file.
    return a

def main(args):
    output = args.output
    inputs = args.inputfiles

    if args.preset:
        p = args.preset[0]

        if p in presets.keys():
            output = p
            inputs = presets[p] + inputs
        else:
            print("Available presets:\n")
            for k in presets.keys():
                print(f"    {k}:     {presets[k]}")
            return


    # Initially we don't know where to put a file.
    guess = None

    # Initialize ROM with "open space"
    for a in range(0x9000, 0x10000):
        ROM[a] = int(a / 256)

    # Read files given in the command line.
    for fn in inputs:
        if not os.path.exists(fn) and fn.startswith("0x"):
            guess = int(fn, 0)
            print(f"New default guess: 0x{guess:04x}")
        else:
            with open(fn, "rb") as file:
                data = file.read()
                guess = add_file_data(fn, data, guess)

    # Write binary file for loading
    with open(output + ".rom", "wb") as file:
        file.write(bytearray(ROM[0x8000:]))

    # Write hex dump file for Vivado
    with open(output + ".hex", "w") as file:
        for b in ROM[0x8000:]:
            file.write(f"{b:02x}\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
            prog='rommaker',
            description='Create combined ROM files (32 KB) from separate ones')
    parser.add_argument('-o', '--output', default="rom")
    parser.add_argument('-p', '--preset', nargs=1)
    parser.add_argument('inputfiles', nargs='*')
    args = parser.parse_args()

    main(args)
