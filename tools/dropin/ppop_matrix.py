#!/usr/bin/env python3
"""Pixel-processing matrix for the system-level bench (sim/accuracy/tb_accuracy.sv).

Every defined PPOP x PSIZE cell (A0051: Boolean 0x00-0x0F at PSIZE 1/2/4/8/16, arithmetic 0x10-0x15 at
PSIZE 4/8/16), with transparency off/on and plane mask off/on, for FILL L, PIXBLT L,L, PIXBLT B,L,
PIXT Rs,*Rd and DRAV. Each case runs through tms34010_system, so in CYCLE_ACCURATE=1 the plane mask and
transparency go through the memory fabric's field sequencer (C6) exactly as in a game core.

The check is equality: registers and the memory hash of every case must be the same in both modes.
Upstream's tb_graphics_ppop_matrix proves upstream mode against an independent model of every cell; equality
carries that to the accurate model. The cycle figures are not checked here (expected counts are 0).

Usage: ppop_matrix.py <cases.txt>   then   Vtb_accuracy +CASES=<cases.txt>  in each mode, and compare.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'accuracy'))
import cases as C  # noqa: E402

DB = C.DATA_BASE
SRC = DB + 0x800
ROWS = 2
PMASK_VAL = 0x5AA5
COLOR = 0x0000A5C3            # zero pixels at every size, for transparency
SRC_LONGS = (0x00001234, 0x56000078, 0x0F00F000)   # zero and non-zero pixels at every size


def dest_pattern():
    """Written inside the measured loop (no '; pre'), so both passes of the loop start from the same
    destination and the final memory is one application of the operation: XOR, XNOR and NOT D would
    otherwise undo themselves on the second pass."""
    out = ['SETF 32, 0, 0', 'MOVI 0x96C3A51E, A5, L', 'MOVI 0x%08X, A6, L' % DB, 'MOVI 0x00001000, A7, L']
    for r in range(ROWS):
        out += ['MOVE A5, *A6, 0', 'MOVE A5, *A6(32), 0', 'MOVE A5, *A6(64), 0', 'MOVE A5, *A6(96), 0']
        if r + 1 < ROWS:
            out += ['ADD A7, A6']
    return out + ['SETF 16, 0, 0']


def src_pattern():
    out = ['SETF 32, 0, 0']
    for r in range(ROWS):
        for w in range(4):
            out += ['MOVI 0x%08X, A5, L' % SRC_LONGS[(r + w) % 3],
                    'MOVI 0x%08X, A6, L' % (SRC + r * 0x1000 + 32 * w), 'MOVE A5, *A6, 0']
    return [l + ' ; pre' for l in out + ['SETF 16, 0, 0']]


def forms(psize):
    """name, test, setup. Destination starts one pixel into a word (a partial first word) and runs past
    two word boundaries."""
    off = psize if psize < 16 else 0
    dx = max(1, 40 // psize)
    dydx = (ROWS << 16) | dx
    yield ('FILL L', 'FILL L', dest_pattern() + [
        'MOVI 0x%08X, B2, L' % (DB + off), 'MOVI 0x00001000, B3, L',
        'MOVI 0x%08X, B7, L' % dydx, 'MOVI 0x%08X, B9, L' % COLOR])
    yield ('PIXBLT L,L', 'PIXBLT L, L', dest_pattern() + src_pattern() + [
        'MOVI 0x%08X, B0, L' % (SRC + 3 * psize % 16), 'MOVI 0x00001000, B1, L',
        'MOVI 0x%08X, B2, L' % (DB + off), 'MOVI 0x00001000, B3, L',
        'MOVI 0x%08X, B7, L' % dydx])
    yield ('PIXBLT B,L', 'PIXBLT B, L', dest_pattern() + src_pattern() + [
        'MOVI 0x%08X, B0, L' % (SRC + 3), 'MOVI 0x00001000, B1, L',
        'MOVI 0x%08X, B2, L' % (DB + off), 'MOVI 0x00001000, B3, L',
        'MOVI 0x%08X, B7, L' % dydx, 'MOVI 0x%08X, B8, L' % 0x0000_3C3C,
        'MOVI 0x%08X, B9, L' % COLOR])
    yield ('PIXT Rs,*Rd', 'PIXT A0, *A1', dest_pattern() + [
        'MOVI 0x%08X, A0, L' % 0x0000_A5C3, 'MOVI 0x%08X, A1, L' % (DB + 5 * psize)])
    yield ('PIXT Rs,*Rd zero', 'PIXT A0, *A1', dest_pattern() + [
        'MOVI 0x00000000, A0, L', 'MOVI 0x%08X, A1, L' % (DB + 3 * psize)])
    yield ('DRAV', 'DRAV A5, A2', dest_pattern() + [
        'MOVI 0x00001000, B3, L', 'MOVI 0x%08X, B4, L' % DB, 'MOVI 0x%08X, B9, L' % COLOR,
        'MOVI 0x00010003, A2, L', 'MOVI 0x00010001, A5, L'])


def misaligned_source_cases():
    """PIXBLT L,L and L,XY with a source that is not pixel-aligned (the JPM boards do this at PSIZE 8),
    every source bit offset 1..15, with Replace, T and an arithmetic operation."""
    out = []
    for psize in (4, 8, 16):
        dx = max(1, 40 // psize)
        for soff in range(1, 16):
            if soff % psize == 0:
                continue
            for ppop, t in ((0, 0), (0, 1), (0x10, 0)):
                io = [(C.PSIZE_ADDR, psize), (C.CONVDP_ADDR, 19), (C.CONVSP_ADDR, 19)]
                ctrl = (ppop << 10) | (C.CTRL_T if t else 0)
                out.append(C.Case('MISALIGNED-SRC PIXBLT L,L psize%d soff%d ppop%02X T%d' % (psize, soff, ppop, t),
                                  '12-182', 'PIXBLT L, L', 0, -1, 0, io=io, ctrl=ctrl,
                                  setup=dest_pattern() + src_pattern() + [
                                      'MOVI 0x%08X, B0, L' % (SRC + soff), 'MOVI 0x00001000, B1, L',
                                      'MOVI 0x%08X, B2, L' % (DB + psize), 'MOVI 0x00001000, B3, L',
                                      'MOVI 0x%08X, B7, L' % ((ROWS << 16) | dx)]))
                out.append(C.Case('MISALIGNED-SRC PIXBLT L,XY psize%d soff%d ppop%02X T%d' % (psize, soff, ppop, t),
                                  '12-185', 'PIXBLT L, XY', 0, -1, 0, io=io, ctrl=ctrl,
                                  setup=dest_pattern() + src_pattern() + [
                                      'MOVI 0x%08X, B0, L' % (SRC + soff), 'MOVI 0x00001000, B1, L',
                                      'MOVI 0x00010003, B2, L', 'MOVI 0x00001000, B3, L',
                                      'MOVI 0x%08X, B4, L' % DB, 'MOVI 0x%08X, B7, L' % ((ROWS << 16) | dx)]))
    return out


def all_cases():
    out = []
    for psize in (1, 2, 4, 8, 16):
        ppops = list(range(16)) + (list(range(16, 22)) if psize >= 4 else [])
        for fname, test, setup in forms(psize):
            for ppop in ppops:
                for t in (0, 1):
                    for pm in (0, 1):
                        io = [(C.PSIZE_ADDR, psize), (C.CONVDP_ADDR, 19), (C.CONVSP_ADDR, 19)]
                        if pm:
                            io.append((C.PMASK_ADDR, PMASK_VAL))
                        name = 'MATRIX %s psize%d ppop%02X T%d PM%d' % (fname, psize, ppop, t, pm)
                        out.append(C.Case(name, '7.7', test, 0, -1, 0, io=io,
                                          ctrl=(ppop << 10) | (C.CTRL_T if t else 0), setup=setup))
    return out + misaligned_source_cases()


def main():
    lines, n = [], 0
    for case in all_cases():
        words, labels = case.program(0)
        assert (labels['DONE'] - labels['LOOP']) // 16 <= 128, case.name
        lines.append('case %d %s %s 0 0 0 %08X %08X %08X %08X %d %08X' % (
            n, case.name.replace(' ', '_').replace(',', '_'), case.page, labels['T'], labels['N'],
            labels['DONE'], case.sp, len(words), C.CODE_BASE))
        lines += ['%04X' % w for w in words]
        n += 1
    with open(sys.argv[1], 'w') as f:
        f.write('\n'.join(lines) + '\nend\n')
    print('%d runs written to %s' % (n, sys.argv[1]))


if __name__ == '__main__':
    main()
