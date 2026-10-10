#!/usr/bin/env python3
"""Programs for sim/dropin/tb_two_gsp_sys.sv: the Exterminator's two GSPs (guide 9.9.1, Table 9-1).
Writes <out>_1.txt (GSP #1, internal video timing) and <out>_2.txt (GSP #2, external sync on GSP #1's
HSYNC/VSYNC) as '<word address hex> <word hex>' lines. Register values are the ones the game writes
(MAME survey of exterm and exterm [slave]): GSP #2's are exactly Table 9-1's.
Each program writes its video registers, DPYCTL last, then stores a counter at COUNTER forever.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'accuracy'))
import cases as C  # noqa: E402

CODE = 0x0010_0000
COUNTER = 0x0020_0000
REGS = ('HESYNC', 'HEBLNK', 'HSBLNK', 'HTOTAL', 'VESYNC', 'VEBLNK', 'VSBLNK', 'VTOTAL',
        'DPYCTL', 'DPYSTRT', 'DPYINT')
GSP = {
    1: dict(HESYNC=0x0009, HEBLNK=0x0028, HSBLNK=0x0128, HTOTAL=0x013D, VESYNC=0x000E, VEBLNK=0x0010,
            VSBLNK=0x0100, VTOTAL=0x0107, DPYSTRT=0xFFFC, DPYINT=0x0100, DPYCTL=0xF010),
    2: dict(HESYNC=0x00A5, HEBLNK=0x0025, HSBLNK=0x0125, HTOTAL=0xFFFF, VESYNC=0x0088, VEBLNK=0x0010,
            VSBLNK=0x0100, VTOTAL=0xFFFF, DPYSTRT=0x07FD, DPYINT=0x0100, DPYCTL=0xD010),
}


def program(n):
    v = GSP[n]
    lines = ['START: SETF 16, 0, 0']
    for r in [r for r in REGS if r != 'DPYCTL'] + ['DPYCTL']:
        lines += ['MOVI 0x%08X, A1, L' % (0xC0000000 + REGS.index(r) * 0x10),
                  'MOVI 0x%08X, A0, L' % v[r],
                  'MOVE A0, *A1, 0']
    lines += ['SETF 32, 0, 0',
              'MOVI 0x%08X, A1, L' % COUNTER,
              'CLR A0',
              'LOOP: ADDK 1, A0',
              'MOVE A0, *A1, 0',
              'JRUC LOOP']
    words, labels = C.assemble(lines, CODE)
    out = ['%08X %04X' % ((CODE >> 4) + i, w) for i, w in enumerate(words)]
    a = labels['START']
    out += ['%08X %04X' % (0xFFFFFFE0 >> 4, a & 0xFFFF), '%08X %04X' % ((0xFFFFFFE0 >> 4) + 1, a >> 16)]
    return out


def main():
    for n in (1, 2):
        open('%s_%d.txt' % (sys.argv[1], n), 'w').write('\n'.join(program(n)) + '\n')


if __name__ == '__main__':
    main()
