#!/usr/bin/env python3
"""PIXT into an on-chip I/O register (HTOTAL), every pixel option that changes
the written bits: Replace, transparency, plane mask, AND, ADD, XOR with T; PSIZE
8 (two bit offsets) and 16; PIXT Rs,*Rd and *Rs,*Rd. The register is read back
into A2. The check is equality between modes: run with CYCLE_ACCURATE=1 and =0
and compare registers (REVIEW_6 finding 3: accurate mode ignored the keep mask
for I/O writes).
Usage: iocases.py <cases.txt>
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cases as C
out_cases = []
REG = 0xC0000030   # HTOTAL, plain 16-bit register
SRC = C.DATA_BASE
for psize in (8, 16):
    for off in ((0, 8) if psize == 8 else (0,)):
        for a0 in (0x0000ABCD, 0x00000000, 0x00001200):
            for opt, ctrl, extra in (('Repl', 0, []), ('T', C.CTRL_T, []),
                                     ('PMASK', 0, [(C.PMASK_ADDR, 0x0F0F)]),
                                     ('AND', 0b00001 << 10, []), ('ADD', 0b10000 << 10, []),
                                     ('XORT', C.CTRL_T | (0b00110 << 10), [])):
                io = [(C.PSIZE_ADDR, psize), (C.CONVDP_ADDR, 19)] + extra
                setup = ['MOVI 0x%08X, A0, L' % a0, 'MOVI 0x%08X, A1, L' % (REG + off),
                         'MOVI 0x%08X, A3, L' % REG, 'MOVI 0x%08X, A4, L' % SRC,
                         'MOVI 0x%08X, A6, L' % REG, 'MOVI 0x5A3C, A5', 'MOVE A5, *A6, 0',
                         'MOVI 0x%08X, A5, L' % (0x9876 ^ a0), 'MOVE A5, *A4, 0']
                for form, t in (('RsRd', 'PIXT A0, *A1'), ('m2m', 'PIXT *A4, *A1')):
                    out_cases.append(C.Case('IOPIX %s %s ps%d off%d a0%04X' % (form, opt, psize, off, a0 & 0xFFFF),
                                            '0', [t, 'MOVE *A3, A2, 0'], 1, 0, 1, io=io, ctrl=ctrl, setup=setup))
C.all_cases = lambda: out_cases
C.main()
