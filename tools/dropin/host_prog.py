#!/usr/bin/env python3
"""Program and vectors for sim/dropin/tb_host_sys.sv, written as '<word address hex> <word hex>' lines.
The host loads these through HSTADR/HSTDATA while the 34010 is held halted (8.8, host-present reset).

  START   counts in A0 and stores it at COUNTER forever (the work the host interrupts)
  NMIH    NMI handler: A4 += 1, A5 = 0xAAAA, RETI
  HIH     host interrupt handler: A6 += 1, clears INTIN and sets INTOUT (HSTCTLL bits 3, 7), RETI
  CDT     reached through the NMI vector at the end: sets and clears CONTROL.CD (5.4.6) around a delay
          that changes every pass, counting passes at COUNTER2 (a fetch is in flight when each CD write lands)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'accuracy'))
import cases as C  # noqa: E402

CODE = 0x0010_0000
COUNTER = 0x0020_0000
COUNTER2 = 0x0020_0100
CDT_PTR = 0x0060_0000                 # CDT's address, for the bench


def main():
    lines = [
        'START: SETF 16, 0, 0',
        'MOVI 0xC0000110, A2, L',        # INTENB
        'MOVI 0x0200, A3',               # HIE (bit 9)
        'MOVE A3, *A2, 0',
        'SETF 32, 0, 0',
        'MOVI 0x%08X, A1, L' % COUNTER,
        'MOVI 0x5A5A0000, A0, L',        # counter starts with a non-zero high word, so both halves change
        'EINT',
        'LOOP: ADDI 0x00010001, A0, L',  # both 16-bit halves change on every store
        'MOVE A0, *A1, 0',
        'JRUC LOOP',
        'NMIH: MOVI 0x0000AAAA, A5, L',
        'ADDK 1, A4',
        'RETI',
        'HIH: ADDK 1, A6',
        'SETF 16, 0, 0',
        'MOVI 0xC00000F0, A8, L',         # HSTCTLL
        'MOVI 0x0080, A9',                # INTOUT = 1 (tell the host), INTIN = 0 (taken)
        'MOVE A9, *A8, 0',
        'SETF 32, 0, 0',
        'RETI',
        'CDT: SETF 16, 0, 0',
        'MOVI 0x%08X, A2, L' % C.CONTROL_ADDR,
        'MOVI 0x8000, A3',               # CD = 1
        'CLR A4',                        # CD = 0
        'MOVI 0x%08X, A1, L' % COUNTER2,
        'CLR A0',
        'CLR A7',
        'CDL: MOVE A3, *A2, 0',
        'MOVE A7, A5',
        'ADDK 1, A5',
        'CDD: DSJS A5, CDD',
        'MOVE A4, *A2, 0',
        'ADDK 1, A0',
        'MOVE A0, *A1, 0',
        'ADDK 1, A7',
        'ANDI 7, A7',
        'JRUC CDL',
    ]
    words, labels = C.assemble(lines, CODE)
    out = ['%08X %04X' % ((CODE >> 4) + i, w) for i, w in enumerate(words)]
    out += ['%08X %04X' % (CDT_PTR >> 4, labels['CDT'] & 0xFFFF), '%08X %04X' % ((CDT_PTR >> 4) + 1, labels['CDT'] >> 16)]
    for vec, lab in ((0xFFFFFFE0, 'START'), (0xFFFFFEE0, 'NMIH'), (0xFFFFFEC0, 'HIH')):
        a = labels[lab]
        out += ['%08X %04X' % (vec >> 4, a & 0xFFFF), '%08X %04X' % ((vec >> 4) + 1, a >> 16)]
    open(sys.argv[1], 'w').write('\n'.join(out) + '\n')
    print(len(out), 'words; LOOP at %08X NMIH at %08X' % (labels['LOOP'], labels['NMIH']))


if __name__ == '__main__':
    main()
