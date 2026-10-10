#!/usr/bin/env python3
"""Negative XY coordinates and window clipping, for sim/dropin/tb_negxy_sys.sv.

The 1988 User's Guide, 4.3: X and Y are 16-bit signed; the window is restricted to positive coordinates, so
pixels with negative X or Y always lie outside it. 4.3.1 / Figure 4-11: a pixel's address is
OFFSET + ((Y << log2 pitch) OR (X << log2 PSIZE)). 7.10: with W=3 only the pixels inside the window are
drawn; with W=2 an array (or pixel) is drawn only if it lies entirely inside.

Every case draws with arrays or pixels that start above or left of (0,0), or across the window's edges, at
PSIZE 8, Replace, and the model below predicts every non-zero memory word in the drawing area from those
rules alone (not from the RTL). Instructions: FILL XY, PIXBLT L,XY, PIXBLT XY,XY, PIXBLT B,XY, PIXT
Rs,*Rd.XY, DRAV and LINE.

  negxy.py gen <prefix>          writes <prefix>_cases.txt (for the bench) and <prefix>_expect.txt
  negxy.py check <prefix> <log>  compares the bench's DUMP lines with the expectation
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'accuracy'))
import cases as C  # noqa: E402

CODE = 0x0010_0000
DONE = 0x0030_0000                     # the program writes 0x0D0E here when it has finished
OFFSET = 0x0020_0000                   # XY origin; rows of 4096 bits (CONVDP/CONVSP 19)
ROWS = 64                              # drawing area dumped by the bench: rows 0..63 from OFFSET
SRC_LIN = 0x0040_0000                  # linear source arrays (outside the dumped area)
PITCH, PSIZE = 4096, 8
CONV = 19                              # 31 - log2(4096)
COLOR0, COLOR1 = 0x11, 0x5A
IO = [(0xC000_0150, PSIZE), (0xC000_0140, CONV), (0xC000_0130, CONV), (0xC000_0160, 0)]  # PSIZE CONVDP CONVSP PMASK
CONTROL = 0xC000_00B0


def xy(x, y):
    return ((y & 0xFFFF) << 16) | (x & 0xFFFF)


def addr(x, y):
    """4.3.1, for a pixel inside the (positive) window."""
    assert x >= 0 and y >= 0 and x * PSIZE < PITCH
    return OFFSET + ((y * PITCH) | (x * PSIZE))


class Mem:
    def __init__(self):
        self.w = {}

    def set_pixel(self, a, v):
        word, sh = a >> 4, a & 15
        old = self.w.get(word, 0)
        self.w[word] = (old & ~(0xFF << sh) | ((v & 0xFF) << sh)) & 0xFFFF

    def pixel(self, a):
        return (self.w.get(a >> 4, 0) >> (a & 15)) & 0xFF

    def bit(self, a):
        return (self.w.get(a >> 4, 0) >> (a & 15)) & 1


def inside(x, y, win):
    (x0, y0), (x1, y1) = win
    return x0 <= x <= x1 and y0 <= y <= y1


class Case:
    def __init__(self, name, w, win, lines, init=None, convsp=CONV):
        self.name, self.w, self.win, self.lines, self.convsp = name, w, win, lines, convsp
        self.init = init or Mem()
        self.expect = Mem()
        self.expect.w = dict(self.init.w)


def program(c):
    (wx0, wy0), (wx1, wy1) = c.win
    lines = ['START: SETF 16, 0, 0']
    io = [(a, c.convsp if a == 0xC000_0130 else v) for a, v in IO]
    for a, v in io + [(CONTROL, c.w << 6)]:
        lines += ['MOVI 0x%08X, A14, L' % a, 'MOVI 0x%08X, A13, L' % v, 'MOVE A13, *A14, 0']
    lines += ['MOVI 0x%08X, B4, L' % OFFSET, 'MOVI 0x%08X, B5, L' % xy(wx0, wy0),
              'MOVI 0x%08X, B6, L' % xy(wx1, wy1), 'MOVI 0x%08X, B8, L' % (COLOR0 * 0x01010101),
              'MOVI 0x%08X, B9, L' % (COLOR1 * 0x01010101)]
    lines += c.lines
    lines += ['SETF 16, 0, 0', 'MOVI 0x%08X, A1, L' % DONE, 'MOVI 0x0D0E, A0', 'MOVE A0, *A1, 0',
              'HALT: JRUC HALT']
    words, labels = C.assemble(lines, CODE)
    out = [(CODE >> 4) + i for i in range(len(words))], words
    return list(zip(*out)), labels['START']


def array_cases():
    out = []
    wins = {'win(2,1)-(20,10)': ((2, 1), (20, 10)), 'win(0,0)-(30,20)': ((0, 0), (30, 20))}
    starts = [(-5, -3), (-1, 2), (-12, 4), (3, -2), (0, 0), (4, 3), (-40, 5), (25, 18)]
    dx, dy = 12, 5
    for wname, win in wins.items():
        for w in (3, 2):
            for (x0, y0) in starts:
                drawn_all = all(inside(x0 + i, y0 + j, win) for i in range(dx) for j in range(dy))

                def draws(x, y):
                    return inside(x, y, win) and (w == 3 or drawn_all)
                regs = ['MOVI 0x%08X, B2, L' % xy(x0, y0), 'MOVI 0x%08X, B3, L' % PITCH,
                        'MOVI 0x%08X, B7, L' % xy(dx, dy)]
                tag = '(%d,%d) W=%d %s' % (x0, y0, w, wname)
                # FILL XY
                c = Case('FILL XY ' + tag, w, win, regs + ['FILL XY'])
                for j in range(dy):
                    for i in range(dx):
                        if draws(x0 + i, y0 + j):
                            c.expect.set_pixel(addr(x0 + i, y0 + j), COLOR1)
                out.append(c)
                # PIXBLT L,XY: source pixel (i,j) at SRC_LIN + j*SPTCH + i*8
                init = Mem()
                sp = 256
                # 4-15/12-1xx: with window clipping a linear source needs a power-of-two SPTCH and CONVSP
                # to match it (the clipped rows are skipped with CONVSP): LMO(256) = 23
                csp = 23
                for j in range(dy):
                    for i in range(dx):
                        init.set_pixel(SRC_LIN + j * sp + i * PSIZE, 0x80 + j * 16 + i)
                c = Case('PIXBLT L,XY ' + tag, w, win,
                         regs + ['MOVI 0x%08X, B0, L' % SRC_LIN, 'MOVI 0x%08X, B1, L' % sp, 'PIXBLT L, XY'],
                         init, csp)
                for j in range(dy):
                    for i in range(dx):
                        if draws(x0 + i, y0 + j):
                            c.expect.set_pixel(addr(x0 + i, y0 + j), init.pixel(SRC_LIN + j * sp + i * PSIZE))
                out.append(c)
                # PIXBLT XY,XY: source at (200+i, 40+j) in the same XY space (CONVSP)
                init = Mem()
                for j in range(dy):
                    for i in range(dx):
                        init.set_pixel(addr(200 + i, 40 + j), 0x40 + j * 16 + i)
                c = Case('PIXBLT XY,XY ' + tag, w, win,
                         regs + ['MOVI 0x%08X, B0, L' % xy(200, 40), 'MOVI 0x%08X, B1, L' % PITCH,
                                 'PIXBLT XY, XY'], init)
                for j in range(dy):
                    for i in range(dx):
                        if draws(x0 + i, y0 + j):
                            c.expect.set_pixel(addr(x0 + i, y0 + j), init.pixel(addr(200 + i, 40 + j)))
                out.append(c)
                # PIXBLT B,XY: source bit (i,j) at SRC_LIN + j*SPTCH + i
                init = Mem()
                for j in range(dy):
                    for i in range(dx):
                        if (i * 7 + j * 3) % 5 < 2:
                            a = SRC_LIN + j * sp + i
                            init.w[a >> 4] = init.w.get(a >> 4, 0) | (1 << (a & 15))
                c = Case('PIXBLT B,XY ' + tag, w, win,
                         regs + ['MOVI 0x%08X, B0, L' % SRC_LIN, 'MOVI 0x%08X, B1, L' % sp, 'PIXBLT B, XY'],
                         init, csp)
                for j in range(dy):
                    for i in range(dx):
                        if draws(x0 + i, y0 + j):
                            bit = init.bit(SRC_LIN + j * sp + i)
                            c.expect.set_pixel(addr(x0 + i, y0 + j), COLOR1 if bit else COLOR0)
                out.append(c)
    return out


def pixel_cases():
    out = []
    win = ((2, 1), (20, 10))
    pts = [(-1, 5), (5, -1), (-1, -1), (3, 3), (-32768, 4), (4, -32768), (2, 1), (20, 10), (21, 5), (1, 5)]
    for w in (3, 2):
        for (x, y) in pts:
            c = Case('PIXT Rs,*Rd.XY (%d,%d) W=%d' % (x, y, w), w, win,
                     ['MOVI 0x%08X, A0, L' % 0x3C, 'MOVI 0x%08X, A2, L' % xy(x, y), 'PIXT A0, *A2.XY'])
            if inside(x, y, win):
                c.expect.set_pixel(addr(x, y), 0x3C)
            out.append(c)
    # DRAV: eight steps from a point above-left of the window, (+1,+1) each
    for (x, y) in [(-3, -2), (-6, 3), (0, -4), (18, 8)]:
        lines = ['MOVI 0x%08X, A5, L' % xy(1, 1), 'MOVI 0x%08X, A2, L' % xy(x, y)] + ['DRAV A5, A2'] * 8
        c = Case('DRAV x8 from (%d,%d) W=3' % (x, y), 3, win, lines)
        for k in range(8):
            if inside(x + k, y + k, win):
                c.expect.set_pixel(addr(x + k, y + k), COLOR1)
        out.append(c)
    # LINE 0: a horizontal line (INC1 = INC2 = one step in X), COUNT pixels from DADDR
    for (x, y, step, n) in [(-4, 3, 1, 10), (5, 4, -1, 9), (-30000, 6, 1, 6), (18, 5, 1, 6)]:
        lines = ['MOVI 0xFFFFFFF1, B0, L', 'MOVI 0x%08X, B2, L' % xy(x, y), 'MOVI 0x%08X, B3, L' % PITCH,
                 'MOVI 0x00030016, B7, L', 'MOVI 0x%08X, B10, L' % n,
                 'MOVI 0x%08X, B11, L' % xy(step, 0), 'MOVI 0x%08X, B12, L' % xy(step, 0),
                 'MOVI 0xFFFFFFFF, B13, L', 'LINE 0']
        c = Case('LINE 0 from (%d,%d) dx %d x%d W=3' % (x, y, step, n), 3, win, lines)
        for k in range(n):
            if inside(x + k * step, y, win):
                c.expect.set_pixel(addr(x + k * step, y), COLOR1)
        out.append(c)
    return out


def main():
    mode, prefix = sys.argv[1], sys.argv[2]
    cases = array_cases() + pixel_cases()
    lo, hi = OFFSET >> 4, (OFFSET + ROWS * PITCH) >> 4
    if mode == 'gen':
        with open(prefix + '_cases.txt', 'w') as f, open(prefix + '_expect.txt', 'w') as e:
            for n, c in enumerate(cases):
                words, start = program(c)
                f.write('CASE %d %08X\n' % (n, start))
                for a, w in sorted(c.init.w.items()):
                    f.write('W %08X %04X\n' % (a, w))
                for a, w in words:
                    f.write('W %08X %04X\n' % (a, w))
                f.write('END\n')
                e.write('CASE %d %s\n' % (n, c.name))
                for a, w in sorted(c.expect.w.items()):
                    if lo <= a < hi and w:
                        e.write('%08X %04X\n' % (a, w))
        print('%d cases' % len(cases))
        return
    # check
    exp, names, got, done = {}, {}, {}, set()
    cur = None
    for l in open(prefix + '_expect.txt'):
        p = l.split()
        if p[0] == 'CASE':
            cur = int(p[1]); names[cur] = ' '.join(p[2:]); exp[cur] = {}
        else:
            exp[cur][int(p[0], 16)] = int(p[1], 16)
    for l in open(sys.argv[3]):
        p = l.split()
        if p[:1] == ['DUMP']:
            got.setdefault(int(p[1]), {})[int(p[2], 16)] = int(p[3], 16)
        elif p[:1] == ['DONE']:
            done.add(int(p[1]))
    bad = 0
    for n in sorted(exp):
        g = got.get(n, {})
        if n not in done:
            print('FAIL %d %s: did not finish' % (n, names[n])); bad += 1
        elif g != exp[n]:
            bad += 1
            diff = sorted(set(g) | set(exp[n]))
            diff = [a for a in diff if g.get(a) != exp[n].get(a)]
            print('FAIL %d %s: %d words differ, e.g. %s' % (n, names[n], len(diff), ', '.join(
                '%08X got %04X want %04X' % (a, g.get(a, 0), exp[n].get(a, 0)) for a in diff[:3])))
    print('%s: %d of %d cases as the guide predicts' % ('PASS' if bad == 0 else 'FAIL', len(exp) - bad, len(exp)))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
