#!/usr/bin/env python3
"""Instruction-timing cases for sim/accuracy/tb_accuracy.sv.

Each case is a small program: a preamble that sets CONTROL (refresh off,
cache on or off) and the registers, then a loop that runs the instruction
under test twice. The bench measures the second pass.

Expected states come from the TMS34010 User's Guide, June 1988 revision
(SPVU001A, page numbers of that edition), Section 12
"Machine States" lines and the Section 13 tables. One machine state is
CLKS_PER_STATE core clocks.

Usage: cases.py <out_cases.txt>
"""

import sys

CODE_BASE = 0x0010_0000          # bit address
DATA_BASE = 0x0020_0000
STACK_TOP = 0x0030_0000
CONTROL_ADDR = 0xC000_00B0
CTRL_RR_OFF = 0b11 << 3           # refresh disabled (page 6-14)
CTRL_CD = 1 << 15                 # cache disable (page 6-15)
CTRL_RR = CTRL_RR_OFF             # main(): 'refresh' turns DRAM refresh on
SCREEN_IO = []                    # main(): 'screen' adds video timing and screen refresh

# ---------------------------------------------------------------- encoder ---


def reg(r):
    """'A0'..'A15', 'B0'..'B15', 'SP' -> (file bit, index)."""
    r = r.upper()
    if r == 'SP':
        return 0, 15
    return (1 if r[0] == 'B' else 0), int(r[1:])


def rs_rd(base, rs, rd):
    fs, s = reg(rs)
    fd, d = reg(rd)
    assert fs == fd or 'SP' in (rs.upper(), rd.upper()), (rs, rd)
    return [base | (s << 5) | (fd << 4) | d]


def rd_only(base, rd):
    f, d = reg(rd)
    return [base | (f << 4) | d]


def k_rd(base, k, rd):
    f, d = reg(rd)
    return [base | ((k & 31) << 5) | (f << 4) | d]


def lo_hi(v):
    v &= 0xFFFF_FFFF
    return [v & 0xFFFF, v >> 16]


ALU_RR = {
    'ADD': 0x4000, 'ADDC': 0x4200, 'SUB': 0x4400, 'SUBB': 0x4600,
    'CMP': 0x4800, 'BTST': 0x4A00, 'MOVE': 0x4C00,
    'AND': 0x5000, 'ANDN': 0x5200, 'OR': 0x5400, 'XOR': 0x5600,
    'DIVS': 0x5800, 'DIVU': 0x5A00, 'MPYS': 0x5C00, 'MPYU': 0x5E00,
    'SLA': 0x6000, 'SLL': 0x6200, 'SRA': 0x6400, 'SRL': 0x6600,
    'RL': 0x6800, 'LMO': 0x6A00, 'MODS': 0x6C00, 'MODU': 0x6E00,
    'ADDXY': 0xE000, 'SUBXY': 0xE200, 'CMPXY': 0xE400, 'CPW': 0xE600,
    'CVXYL': 0xE800, 'MOVX': 0xEC00, 'MOVY': 0xEE00,
}
RD_ONLY = {
    'ABS': 0x0380, 'NEG': 0x03A0, 'NEGB': 0x03C0, 'NOT': 0x03E0,
    'GETPC': 0x0140, 'GETST': 0x0180, 'PUTST': 0x01A0, 'JUMP': 0x0160,
    'EXGPC': 0x0120, 'CALL': 0x0920,
}
NO_OPERAND = {
    'NOP': 0x0300, 'CLRC': 0x0320, 'SETC': 0x0DE0, 'DINT': 0x0360,
    'EINT': 0x0D60, 'POPST': 0x01C0, 'PUSHST': 0x01E0, 'RETI': 0x0940,
}
CC = {'UC': 0, 'P': 1, 'LS': 2, 'HI': 3, 'LT': 4, 'GE': 5, 'LE': 6, 'GT': 7,
      'C': 8, 'NC': 9, 'EQ': 10, 'NE': 11, 'V': 12, 'NV': 13, 'N': 14,
      'NN': 15}
# MOVE field forms: opcode base, F in bit 9 (page 12-16 summary table)
MOVE_FIELD = {
    'Rs,*Rd': 0x8000, '*Rs,Rd': 0x8400, '*Rs,*Rd': 0x8800,
    'Rs,*Rd+': 0x9000, '*Rs+,Rd': 0x9400, '*Rs+,*Rd+': 0x9800,
    'Rs,-*Rd': 0xA000, '-*Rs,Rd': 0xA400, '-*Rs,-*Rd': 0xA800,
    'Rs,*Rd(D)': 0xB000, '*Rs(D),Rd': 0xB400, '*Rs(D),*Rd(D)': 0xB800,
    '*Rs(D),*Rd+': 0xD000,
}
PIXT_FORM = {
    'Rs,*Rd': 0xF800, 'Rs,*Rd.XY': 0xF000, '*Rs,Rd': 0xFA00,
    '*Rs,*Rd': 0xFC00, '*Rs.XY,Rd': 0xF200, '*Rs.XY,*Rd.XY': 0xF400,
}
MOVB_FORM = {
    'Rs,*Rd': 0x8C00, '*Rs,Rd': 0x8E00, '*Rs,*Rd': 0x9C00,
    'Rs,*Rd(D)': 0xAC00, '*Rs(D),Rd': 0xAE00, '*Rs(D),*Rd(D)': 0xBC00,
}


def asm(text, here, labels):
    """Assemble one instruction. Returns a list of 16-bit words.

    `here` is the bit address of the instruction, `labels` maps names to bit
    addresses (pass 2) or is empty (pass 1, sizes only)."""
    op, _, rest = text.strip().partition(' ')
    op = op.upper()
    a = [x.strip() for x in rest.split(',')] if rest.strip() else []

    def lab(name):
        return labels.get(name, here)

    if op in NO_OPERAND:
        return [NO_OPERAND[op]]
    if op == 'REV':
        return rd_only(0x0020, a[0])
    if op in RD_ONLY:
        return rd_only(RD_ONLY[op], a[0])
    if op == 'MOVE' and len(a) == 2 and '*' not in rest and '@' not in rest:
        return rs_rd(0x4C00, a[0], a[1])
    if op in ALU_RR and len(a) == 2 and a[0][0].upper() in 'AB' or \
            (op in ALU_RR and a and a[0].upper() == 'SP'):
        return rs_rd(ALU_RR[op], a[0], a[1])
    if op in ('ADDK', 'SUBK', 'MOVK'):
        base = {'ADDK': 0x1000, 'SUBK': 0x1400, 'MOVK': 0x1800}[op]
        return k_rd(base, int(a[0], 0), a[1])
    if op == 'INC':
        return k_rd(0x1000, 1, a[0])
    if op == 'DEC':
        return k_rd(0x1400, 1, a[0])
    if op == 'CLR':
        return rs_rd(0x5600, a[0], a[0])
    if op == 'BTST':                                   # K form
        return k_rd(0x1C00, ~int(a[0], 0), a[1])
    if op in ('SLA', 'SLL', 'RL'):
        base = {'SLA': 0x2000, 'SLL': 0x2400, 'RL': 0x3000}[op]
        return k_rd(base, int(a[0], 0), a[1])
    if op in ('SRA', 'SRL'):
        base = {'SRA': 0x2800, 'SRL': 0x2C00}[op]
        return k_rd(base, -int(a[0], 0), a[1])
    if op in ('MOVI', 'ADDI', 'CMPI', 'SUBI', 'ANDI', 'ORI', 'XORI', 'ANDNI'):
        v = int(a[0], 0) if a[0][0] in '-0123456789' else lab(a[0])
        long_form = (len(a) > 2 and a[2].upper() == 'L') or \
            op in ('ANDI', 'ORI', 'XORI', 'ANDNI') or not (-32768 <= v <= 32767)
        if op in ('SUBI', 'CMPI'):
            v = ~v                                     # one's complement (12-41, 12-225)
        if op == 'ANDI':
            v = ~v                                     # stored complemented (12-43); ANDNI as given (12-45)
        if long_form:
            base = {'MOVI': 0x09E0, 'ADDI': 0x0B20, 'CMPI': 0x0B60,
                    'SUBI': 0x0D00, 'ANDI': 0x0B80, 'ANDNI': 0x0B80,
                    'ORI': 0x0BA0, 'XORI': 0x0BC0}[op]
            return rd_only(base, a[1]) + lo_hi(v)
        base = {'MOVI': 0x09C0, 'ADDI': 0x0B00, 'CMPI': 0x0B40,
                'SUBI': 0x0BE0}[op]
        return rd_only(base, a[1]) + [v & 0xFFFF]
    if op == 'SETF':
        fs, fe = int(a[0], 0), int(a[1], 0)
        f = int(a[2], 0) if len(a) > 2 else 0
        return [0x0540 | (f << 9) | (fe << 5) | (fs & 31)]
    if op in ('SEXT', 'ZEXT'):
        f = int(a[1], 0) if len(a) > 1 else 0
        return rd_only((0x0500 if op == 'SEXT' else 0x0520) | (f << 9), a[0])
    if op == 'EXGF':
        f = int(a[1], 0) if len(a) > 1 else 0
        return rd_only(0xD500 | (f << 9), a[0])
    if op == 'RETS':
        return [0x0960 | (int(a[0], 0) if a else 0)]
    if op == 'TRAP':
        return [0x0900 | int(a[0], 0)]
    if op == 'EMU':
        return [0x0100]
    if op in ('MMTM', 'MMFM'):
        f, rp = reg(a[0])
        mask = 0
        for r in a[1:]:
            _, n = reg(r)
            # MMTM list: bit 15-N is register N; MMFM: bit N (AGENTS.md, 12-94/12-96)
            mask |= (1 << (15 - n)) if op == 'MMTM' else (1 << n)
        return [(0x0980 if op == 'MMTM' else 0x09A0) | (f << 4) | rp, mask]
    if op == 'DSJS':
        f, d = reg(a[0])
        disp = (lab(a[1]) - (here + 16)) // 16
        back = disp < 0
        assert abs(disp) <= 31 or not labels, ('DSJS out of range', text, disp)
        return [0x3800 | (int(back) << 10) | ((abs(disp) & 31) << 5) | (f << 4) | d]
    if op in ('DSJ', 'DSJEQ', 'DSJNE'):
        base = {'DSJ': 0x0D80, 'DSJEQ': 0x0DA0, 'DSJNE': 0x0DC0}[op]
        disp = (lab(a[1]) - (here + 32)) // 16
        return rd_only(base, a[0]) + [disp & 0xFFFF]
    if op.startswith('JR') and op != 'JRS':
        cc = CC[op[2:]] if op[2:] in CC else None
        long_form = len(a) > 1 and a[1].upper() == 'L'
        if long_form:
            disp = (lab(a[0]) - (here + 32)) // 16
            return [0xC000 | (cc << 8), disp & 0xFFFF]
        disp = (lab(a[0]) - (here + 16)) // 16
        assert -127 <= disp <= 127 and disp != 0 or not labels, (text, disp)
        return [0xC000 | (cc << 8) | (disp & 0xFF)]
    if op.startswith('JA'):
        cc = CC[op[2:]]
        return [0xC080 | (cc << 8)] + lo_hi(lab(a[0]))
    if op == 'CALLA':
        return [0x0D5F] + lo_hi(lab(a[0]))
    if op == 'CALLR':
        return [0x0D3F, ((lab(a[0]) - (here + 32)) // 16) & 0xFFFF]
    if op in ('MOVE', 'MOVB'):
        return asm_move(op, a, here, labels)
    if op == 'PIXT':
        rs, rd = a[0], a[1]
        form = ('*Rs' if rs.startswith('*') else 'Rs') + ('.XY' if rs.endswith('.XY') else '') \
            + ',' + ('*Rd' if rd.startswith('*') else 'Rd') + ('.XY' if rd.endswith('.XY') else '')
        clean = lambda x: x.lstrip('*').replace('.XY', '')
        return rs_rd(PIXT_FORM[form], clean(rs), clean(rd))
    if op == 'LINE':
        return [0xDF9A if a and a[0] == '1' else 0xDF1A]
    if op == 'FILL':
        return [0x0FC0 if a[0].upper() == 'L' else 0x0FE0]
    if op == 'PIXBLT':
        return [{('L', 'L'): 0x0F00, ('L', 'XY'): 0x0F20, ('XY', 'L'): 0x0F40, ('XY', 'XY'): 0x0F60,
                 ('B', 'L'): 0x0F80, ('B', 'XY'): 0x0FA0}[(a[0].upper(), a[1].upper())]]
    if op == 'DRAV':
        return rs_rd(0xF600, a[0], a[1])
    raise ValueError('cannot assemble: ' + text)


def asm_move(op, a, here, labels):
    """MOVE/MOVB field forms. Operand syntax: Rs | *Rs | *Rs+ | -*Rs |
    *Rs(disp) | @addr, then optional field select F (MOVE only)."""
    f = 0
    if op == 'MOVE' and len(a) == 3:
        f = int(a[2], 0)

    def shape(x):
        x = x.strip()
        if x.startswith('@'):
            return '@', None, int(x[1:], 0)
        if x.startswith('-*'):
            return '-*R', x[2:], None
        if x.startswith('*') and x.endswith('+'):
            return '*R+', x[1:-1], None
        if x.startswith('*') and '(' in x:
            r, disp = x[1:].split('(')
            return '*R(D)', r, int(disp.rstrip(')'), 0)
        if x.startswith('*'):
            return '*R', x[1:], None
        return 'R', x, None

    s_kind, s_reg, s_val = shape(a[0])
    d_kind, d_reg, d_val = shape(a[1])
    s_name = {'R': 'Rs', '*R': '*Rs', '*R+': '*Rs+', '-*R': '-*Rs', '*R(D)': '*Rs(D)'}.get(s_kind)
    d_name = {'R': 'Rd', '*R': '*Rd', '*R+': '*Rd+', '-*R': '-*Rd', '*R(D)': '*Rd(D)'}.get(d_kind)
    if s_kind == '@' or d_kind == '@':
        if op == 'MOVE':
            if s_kind == 'R' and d_kind == '@':
                return rd_only(0x0580 | (f << 9), s_reg) + lo_hi(d_val)
            if s_kind == '@' and d_kind == 'R':
                return rd_only(0x05A0 | (f << 9), d_reg) + lo_hi(s_val)
            if s_kind == '@' and d_kind == '*R+':
                return rd_only(0xD400 | (f << 9), d_reg) + lo_hi(s_val)
            if s_kind == '@' and d_kind == '@':
                return [0x05C0 | (f << 9)] + lo_hi(s_val) + lo_hi(d_val)
        else:
            if s_kind == 'R' and d_kind == '@':
                return rd_only(0x05E0, s_reg) + lo_hi(d_val)
            if s_kind == '@' and d_kind == 'R':
                return rd_only(0x07E0, d_reg) + lo_hi(s_val)
            if s_kind == '@' and d_kind == '@':
                return [0x0340] + lo_hi(s_val) + lo_hi(d_val)
        raise ValueError('absolute MOVE form')
    key = s_name + ',' + d_name
    table = MOVE_FIELD if op == 'MOVE' else MOVB_FORM
    base = table[key] | ((f << 9) if op == 'MOVE' else 0)
    words = rs_rd(base, s_reg, d_reg)
    if s_kind == '*R(D)':
        words.append(s_val & 0xFFFF)
    if d_kind == '*R(D)':
        words.append(d_val & 0xFFFF)
    return words


def assemble(lines, base):
    """Two-pass assembler over [label:] instruction lines."""
    labels = {}
    for pass_no in (1, 2):
        here = base
        words = []
        for line in lines:
            line = line.split(';')[0].strip()
            if not line:
                continue
            while ':' in line.split(' ')[0]:
                name, _, line = line.partition(':')
                labels[name.strip()] = here
                line = line.strip()
            if not line:
                continue
            w = asm(line, here, labels if pass_no == 2 else {})
            words += w
            here += 16 * len(w)
    return words, labels


# ------------------------------------------------------------------ cases ---


class Case:
    def __init__(self, name, page, test, hit, hidden, dis, setup=(),
                 sub=(), mem=None, sp=STACK_TOP, fill=('NOP',) * 12, io=(), ctrl=0, note=''):
        """hit, hidden, dis: the figures printed in the guide (dis = -1: none
        printed). note: why the model is expected to differ from them (an
        entry of docs/cycle_accuracy.md "Where the guide disagrees")."""
        self.name, self.page, self.note = name, page, note
        self.test = test if isinstance(test, (list, tuple)) else [test]
        self.hit, self.hidden, self.dis = hit, hidden, dis
        self.setup, self.sub, self.mem, self.sp = list(setup), list(sub), mem or {}, sp
        self.fill = list(fill)
        self.io, self.ctrl = list(io), ctrl

    def program(self, cd):
        ctrl = CTRL_RR | (CTRL_CD if cd else 0) | self.ctrl
        io_lines = []
        for addr, val in self.io:
            io_lines += ['MOVI 0x%08X, A14, L' % addr, 'MOVI 0x%08X, A13, L' % val,
                         'MOVE A13, *A14, 0']
        # Lines marked "; pre" (memory patterns) run once, before the loop,
        # so the measured loop stays small enough for the instruction cache.
        pre = [l for l in self.setup if l.endswith('; pre')]
        setup = [l for l in self.setup if not l.endswith('; pre')]
        # 'screen' mode: the video registers are written once, before the loop.
        screen = (['SETF 16, 0, 0'] + sum((['MOVI 0x%08X, A14, L' % a, 'MOVI 0x%08X, A13, L' % v,
                                            'MOVE A13, *A14, 0'] for a, v in SCREEN_IO), [])
                  if SCREEN_IO else [])
        lines = screen + pre + [
            'MOVI 0x%08X, A14, L' % CONTROL_ADDR,
            'MOVI 0x%04X, A13' % ctrl,
            'SETF 16, 0, 0',
            'MOVE A13, *A14, 0',
            'MOVI 0x%08X, SP, L' % self.sp,
            'MOVK 2, A12',
            'LOOP: NOP',
        ] + io_lines + setup + ['NOP'] * 12 + [
            'T: ' + self.test[0],
        ] + self.test[1:] + [
            'N: ' + self.fill[0],
        ] + self.fill[1:] + [
            'E: DSJ A12, LOOP',
            'DONE: JRUC DONE',
        ] + self.sub
        return assemble(lines, CODE_BASE)


def move_cases():
    """Section 13.2 tables 13-1 and 13-2, one case per alignment."""
    # (alignment, field size, bit offset into the word)
    aligns = {'A': (16, 0), 'B': (8, 0), 'C': (32, 0), 'D': (24, 8),
              'E': (24, 0), 'F': (16, 8), 'G': (32, 8)}
    out = []
    # Table 13-2 register-to-memory, page 13-6: (hit, hidden, disabled)
    t132 = {
        'Rs,*Rd':     {'A': (1, 1, 5), 'B': (1, 3, 7), 'C': (1, 3, 7), 'D': (1, 5, 9),
                       'E': (1, 5, 9), 'F': (1, 7, 11), 'G': (1, 9, 13)},
        'Rs,*Rd+':    {'A': (1, 1, 5), 'B': (1, 3, 7), 'C': (1, 3, 7), 'D': (1, 5, 9),
                       'E': (1, 5, 9), 'F': (1, 7, 11), 'G': (1, 9, 13)},
        'Rs,-*Rd':    {'A': (2, 1, 6), 'B': (2, 3, 8), 'C': (2, 3, 8), 'D': (2, 5, 10),
                       'E': (2, 5, 10), 'F': (2, 7, 12), 'G': (2, 9, 14)},
        'Rs,*Rd(D)':  {'A': (3, 1, 9), 'B': (3, 3, 12), 'C': (3, 3, 12), 'D': (3, 5, 14),
                       'E': (3, 5, 14), 'F': (3, 7, 13), 'G': (3, 9, 18)},
    }
    for form, row in t132.items():
        for al, (h, hid, d) in row.items():
            fs, off = aligns[al]
            addr = DATA_BASE + off + (fs if form == 'Rs,-*Rd' else 0)
            dst = {'Rs,*Rd': '*A1', 'Rs,*Rd+': '*A1+', 'Rs,-*Rd': '-*A1',
                   'Rs,*Rd(D)': '*A1(0)'}[form]
            out.append(Case('MOVE %s %s fs%d' % (form, al, fs), '13-6 T13-2',
                            'MOVE A0, %s, 0' % dst, h, hid, d,
                            note=('store-off-%s' % al.lower()) if (form == 'Rs,*Rd(D)' and al in 'AF') else '',
                            setup=['SETF %d, 0, 0' % (fs & 31),
                                   'MOVI 0x12345678, A0, L',
                                   'MOVI 0x%08X, A1, L' % addr]))
    # Table 13-1 memory-to-register, page 13-5: A/B, C-F, G
    t131 = {
        '*Rs,Rd':   ((3, 6), (5, 8), (7, 10)),
        '*Rs+,Rd':  ((3, 6), (5, 8), (7, 10)),
        '-*Rs,Rd':  ((4, 7), (6, 9), (8, 11)),
        '*Rs(D),Rd': ((5, 11), (7, 13), (9, 15)),
    }
    for form, cols in t131.items():
        for al in 'ABCDEFG':
            fs, off = aligns[al]
            h, d = cols[0] if al in 'AB' else cols[2] if al == 'G' else cols[1]
            addr = DATA_BASE + off + (fs if form == '-*Rs,Rd' else 0)
            src = {'*Rs,Rd': '*A1', '*Rs+,Rd': '*A1+', '-*Rs,Rd': '-*A1',
                   '*Rs(D),Rd': '*A1(0)'}[form]
            out.append(Case('MOVE %s %s fs%d' % (form, al, fs), '13-5 T13-1',
                            'MOVE %s, A0, 0' % src, h, 0, d,
                            setup=['SETF %d, 0, 0' % (fs & 31),
                                   'MOVI 0x%08X, A1, L' % addr]))
    return out


def general_cases():
    """Section 12 per-instruction Machine States (page in the guide)."""
    c = []
    one = [('ABS A0', '12-35'), ('ADD A1, A0', '12-36'), ('ADDC A1, A0', '12-37'),
           ('ADDK 5, A0', '12-40'), ('ADDXY A1, A0', '12-41'), ('AND A1, A0', '12-42'),
           ('ANDN A1, A0', '12-44'), ('BTST 5, A0', '12-46'), ('CLR A0', '12-51'),
           ('CLRC', '12-52'), ('CMP A1, A0', '12-53'), ('CMPXY A1, A0', '12-56'),
           ('CPW A1, A0', '12-58'), ('DEC A0', '12-61'), ('EXGF A0, 0', '12-78'),
           ('GETPC A0', '12-89'), ('GETST A0', '12-90'), ('INC A0', '12-91'),
           ('LMO A1, A0', '12-108'), ('MOVE A1, A0', '12-126'), ('MOVK 5, A0', '12-161'),
           ('MOVX A1, A0', '12-162'), ('MOVY A1, A0', '12-163'), ('NEG A0', '12-168'),
           ('NEGB A0', '12-169'), ('NOP', '12-170'), ('NOT A0', '12-171'),
           ('OR A1, A0', '12-172'), ('XOR A1, A0', '12-255'),
           ('RL 5, A0', '12-234'), ('RL A1, A0', '12-235'), ('SETC', '12-236'),
           ('SETF 16, 0, 0', '12-237'), ('SLL 5, A0', '12-241'), ('SLL A1, A0', '12-242'),
           ('SRA 5, A0', '12-243'), ('SRA A1, A0', '12-244'), ('SRL 5, A0', '12-245'),
           ('SRL A1, A0', '12-246'), ('SUB A1, A0', '12-247'), ('SUBB A1, A0', '12-248'),
           ('SUBK 5, A0', '12-251'), ('SUBXY A1, A0', '12-252'), ('ZEXT A0, 0', '12-257')]
    setup = ['MOVI 0x00030004, A1, L', 'MOVI 0x00500060, A0, L']
    for t, p in one:
        c.append(Case(t, p, t, 1, 0, 4, setup=setup))
    c += [
        Case('SETF 16,0,1', '12-237', 'SETF 16, 0, 1', 2, 0, 5),
        Case('BTST A1,A0', '12-47', 'BTST A1, A0', 2, 0, 5, setup=setup),
        Case('JUMP A0', '12-98', 'JUMP A0', 2, 0, 5, setup=['MOVI N, A0, L']),
        Case('CVXYL A1,A0', '12-59', 'CVXYL A1, A0', 3, 0, 6, setup=setup),
        Case('SEXT A0,0', '12-238', 'SEXT A0, 0', 3, 0, 6, setup=setup),
        Case('SLA 5,A0', '12-239', 'SLA 5, A0', 3, 0, 6, setup=setup),
        Case('SLA A1,A0', '12-240', 'SLA A1, A0', 3, 0, 6, setup=setup),
        Case('DINT', '12-62', 'DINT', 3, 0, 6),
        Case('EINT', '12-76', 'EINT', 3, 0, 6),
        Case('PUTST A0', '12-229', 'PUTST A0', 3, 0, 6, setup=['MOVK 0, A0']),
        Case('MOVI IW', '12-159', 'MOVI 0x1234, A0', 2, 0, 8),
        Case('MOVI IL', '12-160', 'MOVI 0x12345678, A0, L', 3, 0, 12),
        Case('ADDI IW', '12-38', 'ADDI 0x1234, A0', 2, 0, 8),
        Case('ADDI IL', '12-39', 'ADDI 0x12345678, A0, L', 3, 0, 12),
        Case('ANDI IL', '12-43', 'ANDI 0x12345678, A0', 3, 0, 12),
        Case('CMPI IW', '12-54', 'CMPI 0x1234, A0', 2, 0, 8),
        Case('CMPI IL', '12-55', 'CMPI 0x12345678, A0, L', 3, 0, 12),
        Case('ORI IL', '12-173', 'ORI 0x12345678, A0', 3, 0, 12),
        Case('SUBI IW', '12-249', 'SUBI 0x1234, A0', 2, 0, 8),
        Case('SUBI IL', '12-250', 'SUBI 0x12345678, A0, L', 3, 0, 12),
        Case('XORI IL', '12-256', 'XORI 0x12345678, A0', 3, 0, 12),
        # 5 + FS1/2 (FS1 = 32 after reset); MPYU +1 when Rs is negative.
        Case('MPYS FS1=32', '12-165', 'MPYS A1, A0', 21, 0, 24, setup=setup),
        Case('MPYS FS1=16', '12-165', 'MPYS A1, A0', 13, 0, 16, setup=setup + ['SETF 16, 0, 1']),
        Case('MPYS FS1=8', '12-165', 'MPYS A1, A0', 9, 0, 12, setup=setup + ['SETF 8, 0, 1']),
        Case('MPYU FS1=32', '12-167', 'MPYU A1, A0', 21, 0, 24, setup=setup),
        Case('MPYU FS1=32 Rs negative', '12-167', 'MPYU A1, A0', 22, 0, 25,
             setup=['MOVI 0x80030004, A1, L', 'MOVI 0x00500060, A0, L']),
        Case('MPYU FS1=16 Rs negative', '12-167', 'MPYU A1, A0', 14, 0, 17,
             setup=['MOVI 0x00038004, A1, L', 'MOVI 0x00500060, A0, L', 'SETF 16, 0, 1']),
        Case('EMU', '12-77', 'EMU', 8, 0, 11),
        # Rd even: 64-bit dividend in Rd:Rd+1 (pages 12-50, 12-52), divisor in A2.
        Case('DIVS Rd even', '12-63', 'DIVS A2, A0', 40, 0, 43,
             setup=['MOVI 7, A2', 'MOVI 0, A0', 'MOVI 1000, A1']),
        Case('DIVS Rd odd', '12-63', 'DIVS A2, A1', 39, 0, 42,
             setup=['MOVI 7, A2', 'MOVI 1000, A1']),
        Case('DIVU Rd even', '12-65', 'DIVU A2, A0', 37, 0, 40,
             setup=['MOVI 7, A2', 'MOVI 0, A0', 'MOVI 1000, A1']),
        Case('DIVU Rd odd', '12-65', 'DIVU A2, A1', 37, 0, 40,
             setup=['MOVI 7, A2', 'MOVI 1000, A1']),
        Case('MODS', '12-113', 'MODS A2, A1', 40, 0, 43, setup=['MOVI 7, A2', 'MOVI 1000, A1']),
        Case('MODU', '12-114', 'MODU A2, A1', 35, 0, 38, setup=['MOVI 7, A2', 'MOVI 1000, A1']),
        # Jumps: page 12-81/12-83/12-79/12-62/12-57
        Case('JRUC short taken', '12-95', ['JRUC N', 'NOP'], 2, 0, 5),
        Case('JREQ short not taken', '12-95', 'JREQ E', 1, 0, 4, setup=['MOVK 1, A0', 'MOVE A0, A0']),
        Case('JRUC long taken', '12-97', ['JRUC N, L', 'NOP'], 3, 0, 6, note='jump-ext-off'),
        Case('JREQ long not taken', '12-97', 'JREQ E, L', 4, 0, 7, setup=['MOVK 1, A0', 'MOVE A0, A0'],
             note='jump-ext-off'),
        Case('JAUC taken', '12-93', ['JAUC N', 'NOP'], 3, 0, 6, note='jump-ext-off'),
        Case('JAEQ not taken', '12-93', 'JAEQ E', 4, 0, 7, setup=['MOVK 1, A0', 'MOVE A0, A0'],
             note='jump-ext-off'),
        Case('DSJS taken', '12-75', ['DSJS A2, N', 'NOP'], 2, 0, 5, setup=['MOVK 9, A2']),
        Case('DSJS not taken', '12-75', 'DSJS A2, N', 3, 0, 6, setup=['MOVK 1, A2']),
        Case('DSJ taken', '12-70', ['DSJ A2, N', 'NOP'], 3, 0, 9, setup=['MOVK 9, A2']),
        Case('DSJ not taken', '12-70', 'DSJ A2, N', 2, 0, 8, setup=['MOVK 1, A2']),
        # Stack: page 12-35/12-37/12-36/12-205/12-204/12-207
        # Two-instruction cases measure the instruction labelled M, ending at
        # MN; NOPs let the other instruction's hidden writes finish first.
        Case('CALL SP aligned', '12-48', ['M: CALL A0'], 3, 3, 9, setup=['MOVI S, A0, L'],
             sub=['S: NOP'] + ['NOP'] * 11 + ['RETS']),
        Case('CALLR SP aligned', '12-50', ['M: CALLR S'], 3, 2, 11,
             sub=['S: NOP'] + ['NOP'] * 11 + ['RETS']),
        Case('CALLA SP aligned', '12-49', ['M: CALLA S'], 4, 2, 15,
             sub=['S: NOP'] + ['NOP'] * 11 + ['RETS']),
        Case('RETS aligned', '12-232', ['CALLR S', 'MN: NOP'], 7, 0, 10,
             sub=['S: NOP'] + ['NOP'] * 11 + ['M: RETS']),
        Case('PUSHST SP aligned', '12-228', ['M: PUSHST', 'MN: NOP'] + ['NOP'] * 12 + ['POPST'],
             2, 3, 8),
        Case('POPST SP aligned', '12-227', ['PUSHST'] + ['NOP'] * 12 + ['M: POPST', 'MN: NOP'],
             8, 0, 11),
        Case('MMTM 4 regs aligned', '12-112',
             ['M: MMTM SP, A0, A1, A2, A3', 'MN: NOP'] + ['NOP'] * 16 + ['MMFM SP, A0, A1, A2, A3'],
             2 + 4 * 4, 2, 8 + 4 * 4 + 2),
        Case('MMFM 4 regs aligned', '12-110',
             ['MMTM SP, A0, A1, A2, A3'] + ['NOP'] * 16 + ['M: MMFM SP, A0, A1, A2, A3', 'MN: NOP'],
             3 + 4 * 4, 2, 11 + 4 * 4, note='mmfm-hidden'),
        Case('MMTM 1 reg aligned', '12-112',
             ['M: MMTM SP, A0', 'MN: NOP'] + ['NOP'] * 16 + ['MMFM SP, A0'],
             2 + 4 * 1, 2, 8 + 4 * 1 + 2),
        Case('MMFM 1 reg aligned', '12-110',
             ['MMTM SP, A0'] + ['NOP'] * 16 + ['M: MMFM SP, A0', 'MN: NOP'],
             3 + 4 * 1, 2, 11 + 4 * 1, note='mmfm-hidden'),
    ]
    return c


PSIZE_ADDR, CONVDP_ADDR, CONVSP_ADDR = 0xC000_0150, 0xC000_0140, 0xC000_0130
PPOPS = [('Replace', 0b00000, 0), ('AND', 0b00001, 0), ('ADD', 0b10000, 0),
         ('ADDS', 0b10001, 1), ('SUB', 0b10010, 1), ('SUBS', 0b10011, 2), ('MAX', 0b10100, 1)]


def _row(hits, hid, off):
    return [(h, hid, h + hid + off) for h in hits]


# Printed figures, Machine States of each form (cache hit, hidden, cache off)
# for Replace, Boolean, ADD, ADDS, SUB, SUBS, MIN/MAX; PSIZE < 16 then 16.
PIXT_STATES = {
    'PIXT Rs,*Rd': ('12-214', 'PIXT A0, *A1', [
        [(2, 3, 8), (4, 3, 10), (4, 3, 11), (5, 3, 11), (5, 3, 12), (6, 3, 11), (5, 3, 10)],
        _row((2, 4, 4, 5, 5, 6, 5), 1, 3)]),
    'PIXT Rs,*Rd.XY': ('12-216', 'PIXT A0, *A2.XY', [
        _row((4, 6, 6, 7, 7, 8, 7), 3, 3), _row((4, 6, 6, 7, 7, 8, 7), 1, 3)]),
    'PIXT *Rs,Rd': ('12-218', 'PIXT *A1, A0', [[(4, 0, 7)], [(4, 0, 7)]]),
    'PIXT *Rs,*Rd': ('12-221', 'PIXT *A1, *A3', [
        _row((4, 6, 6, 7, 7, 8, 7), 3, 3), _row((4, 6, 6, 7, 7, 8, 7), 1, 3)]),
    'PIXT *Rs.XY,Rd': ('12-222', 'PIXT *A2.XY, A0', [[(6, 0, 9)], [(6, 0, 9)]]),
    'PIXT *Rs.XY,*Rd.XY': ('12-225', 'PIXT *A2.XY, *A4.XY', [
        _row((7, 9, 9, 10, 10, 11, 10), 3, 3), _row((7, 9, 9, 10, 10, 11, 10), 1, 3)]),
    'DRAV': ('12-68', 'DRAV A5, A2', [
        _row((4, 6, 7, 7, 7, 8, 7), 3, 3), _row((4, 6, 6, 7, 7, 8, 7), 1, 3)]),
}
# Where the model is expected to differ from the printed figure.
PIXT_NOTES = {
    ('PIXT Rs,*Rd', 8, 'ADD'): 'pixt-off-row', ('PIXT Rs,*Rd', 8, 'SUB'): 'pixt-off-row',
    ('PIXT Rs,*Rd', 8, 'SUBS'): 'pixt-off-row', ('PIXT Rs,*Rd', 8, 'MAX'): 'pixt-off-row',
    ('DRAV', 8, 'ADD'): 'drav-add',
}


def pixel_cases():
    """PIXT and DRAV, pages 12-190..12-203 and 12-54..12-56, every pixel
    processing column (Boolean: AND; MIN/MAX: MAX) at PSIZE 8 and 16."""
    out = []
    xy_setup = ['MOVI 0x00001000, B1, L',                 # SPTCH
                'MOVI 0x00001000, B3, L',                 # DPTCH
                'MOVI 0x%08X, B4, L' % DATA_BASE,          # OFFSET
                'MOVI 0x12345678, B9, L']                  # COLOR1 (DRAV)
    for psize in (8, 16):
        io = [(PSIZE_ADDR, psize), (CONVDP_ADDR, 19), (CONVSP_ADDR, 19)]
        for name, (page, test, rows) in PIXT_STATES.items():
            row = rows[0 if psize < 16 else 1]
            for (pname, code, _), (hit, hid, dis) in zip(PPOPS, row):
                out.append(Case('%s %s psize%d' % (name, pname, psize), page, test, hit, hid, dis,
                                io=io, ctrl=code << 10,
                                note=PIXT_NOTES.get((name, psize, pname), ''),
                                setup=xy_setup + ['MOVI 0x0000ABCD, A0, L',
                                                  'MOVI 0x%08X, A1, L' % DATA_BASE,
                                                  'MOVI 0x00020003, A2, L',
                                                  'MOVI 0x%08X, A3, L' % (DATA_BASE + 0x100),
                                                  'MOVI 0x00040005, A4, L',
                                                  'MOVI 0x00010001, A5, L']))
    return out


ALIGNS = {'A': (16, 0), 'B': (8, 0), 'C': (32, 0), 'D': (24, 8),
          'E': (24, 0), 'F': (16, 8), 'G': (32, 8)}
# Table 13-3 index -> source and destination alignment (Figure 13-1) with one
# field size: (name, field size, source bit offset, destination bit offset).
M2M_IDX = {1: ('AA', 16, 0, 0), 2: ('BB', 8, 0, 0), 3: ('AF', 16, 0, 8), 4: ('FA', 16, 8, 0),
           5: ('FB', 8, 12, 0), 6: ('CC', 32, 0, 0), 7: ('DD', 24, 8, 8), 8: ('FF', 16, 8, 8),
           9: ('CG', 32, 0, 8), 10: ('GC', 32, 8, 0), 11: ('GD', 24, 12, 8), 12: ('GF', 20, 14, 4),
           13: ('GG', 32, 8, 8)}
# Table 13-4 (page 13-7, read from the page image): form -> {index: (cache hit,
# hidden, cache off)}.
M2M_T134 = {
    '*Rs,*Rd':   {1: (3, 1, 7), 2: (3, 3, 9), 3: (3, 7, 13), 4: (5, 1, 9), 5: (5, 3, 11),
                  6: (5, 3, 11), 7: (5, 5, 13), 8: (5, 7, 15), 9: (5, 9, 17), 10: (7, 3, 13),
                  11: (7, 5, 15), 12: (5, 7, 17), 13: (9, 9, 21)},
    '*Rs+,*Rd+': {1: (4, 0, 7), 2: (4, 2, 9), 3: (4, 6, 13), 4: (6, 0, 9), 5: (6, 2, 11),
                  6: (6, 2, 11), 7: (6, 4, 13), 8: (6, 6, 15), 9: (6, 8, 17), 10: (8, 2, 13),
                  11: (8, 4, 15), 12: (6, 6, 17), 13: (10, 8, 21)},
    '-*Rs,-*Rd': {1: (4, 1, 8), 2: (4, 3, 10), 3: (4, 7, 14), 4: (6, 1, 10), 5: (6, 3, 12),
                  6: (6, 3, 12), 7: (6, 5, 14), 8: (6, 7, 15), 9: (6, 9, 18), 10: (8, 3, 14),
                  11: (8, 5, 16), 12: (6, 7, 18), 13: (10, 9, 22)},
    '*Rs(S),*Rd+': {1: (5, 1, 12), 2: (5, 3, 14), 3: (5, 7, 18), 4: (7, 1, 14), 5: (7, 3, 16),
                    6: (7, 3, 13), 7: (7, 5, 15), 8: (7, 7, 16), 9: (7, 9, 19), 10: (9, 3, 18),
                    11: (9, 5, 20), 12: (7, 7, 22), 13: (11, 9, 26)},
    '*Rs(S),*Rd(D)': {1: (5, 1, 15), 2: (5, 3, 17), 3: (5, 7, 21), 4: (7, 1, 17), 5: (7, 3, 19),
                      6: (7, 3, 16), 7: (7, 5, 18), 8: (7, 7, 19), 9: (7, 9, 22), 10: (9, 3, 21),
                      11: (9, 5, 23), 12: (7, 7, 25), 13: (11, 9, 29)},
    '@S,*Rd+':   {1: (5, 1, 15), 2: (5, 3, 17), 3: (5, 7, 21), 4: (7, 1, 17), 5: (7, 3, 19),
                  6: (7, 3, 16), 7: (7, 5, 18), 8: (7, 7, 19), 9: (7, 9, 22), 10: (9, 3, 21),
                  11: (9, 5, 23), 12: (7, 7, 25), 13: (11, 9, 29)},
    '@S,@D':     {1: (7, 1, 23), 2: (7, 3, 25), 3: (7, 7, 29), 4: (9, 1, 25), 5: (9, 3, 27),
                  6: (9, 3, 24), 7: (9, 5, 26), 8: (9, 7, 27), 9: (9, 9, 30), 10: (11, 3, 29),
                  11: (11, 5, 31), 12: (9, 7, 33), 13: (13, 9, 37)},
}
MOVB_T134 = {
    '*Rs,*Rd':       {2: (3, 3, 7), 3: (3, 7, 13), 5: (5, 3, 11), 8: (5, 7, 15)},
    '*Rs(D),*Rd(D)': {2: (5, 3, 7), 3: (5, 7, 21), 5: (6, 3, 13), 8: (7, 7, 19)},
    '@S,@D':         {2: (7, 3, 7), 3: (7, 7, 29), 5: (6, 3, 12), 8: (9, 7, 27)},
}
EXT_FORMS = ('*Rs(S),*Rd+', '*Rs(S),*Rd(D)', '@S,*Rd+', '@S,@D')


def m2m_note(form, idx, movb=False):
    """The docs/cycle_accuracy.md entry that explains a printed figure the
    model doesn't give, if any."""
    if movb:
        return 'movb-m2m' if (idx == 2 or (idx in (5, 8) and form != '*Rs,*Rd')) else ''
    if idx == 12:
        return 'm2m-col12'
    if form in EXT_FORMS and idx in (6, 7, 8, 9):
        return 'm2m-ext-off'
    if form == '-*Rs,-*Rd' and idx == 8:
        return 'm2m-predec-8'
    return ''


def m2m_cases():
    out = []
    src_base, dst_base = DATA_BASE, DATA_BASE + 0x400
    for movb, table in ((False, M2M_T134), (True, MOVB_T134)):
        for form, row in table.items():
            for idx, (hit, hid, dis) in row.items():
                al, fs, soff, doff = M2M_IDX[idx]
                if movb:                      # a byte: B at offset 0, F at 12
                    fs, soff, doff = 8, 12 * (al[0] == 'F'), 12 * (al[1] == 'F')
                pre = fs if form == '-*Rs,-*Rd' else 0
                sp, dp = src_base + soff + pre, dst_base + doff + pre
                op, f = ('MOVB', '') if movb else ('MOVE', ', 0')
                test = {'*Rs,*Rd': '%s *A1, *A3%s', '*Rs+,*Rd+': '%s *A1+, *A3+%s',
                        '-*Rs,-*Rd': '%s -*A1, -*A3%s', '*Rs(S),*Rd+': '%s *A1(0), *A3+%s',
                        '*Rs(S),*Rd(D)': '%s *A1(0), *A3(0)%s', '*Rs(D),*Rd(D)': '%s *A1(0), *A3(0)%s',
                        '@S,*Rd+': '%s @0x%08X, *A3+%s' % ('%s', sp, '%s'),
                        '@S,@D': '%s @0x%08X, @0x%08X%s' % ('%s', sp, dp, '%s')}[form] % (op, f)
                out.append(Case('%s %s idx%d %s fs%d' % (op, form, idx, al, fs), '13-7 T13-4', test,
                                hit, hid, dis, note=m2m_note(form, idx, movb),
                                setup=['SETF %d, 0, 0' % (fs & 31), 'MOVI 0x%08X, A1, L' % sp,
                                       'MOVI 0x%08X, A3, L' % dp]))
    # MOVB (Tables 13-1, 13-2): byte fields are alignment B or F.
    for al, (lh, sh) in {'B': (3, (1, 3)), 'F': (5, (1, 7))}.items():
        off = 0 if al == 'B' else 12          # F: the byte straddles two words
        out.append(Case('MOVB *Rs,Rd %s' % al, '13-5 T13-1', 'MOVB *A1, A0', lh, 0, lh + 3,
                        setup=['MOVI 0x%08X, A1, L' % (DATA_BASE + off)]))
        out.append(Case('MOVB Rs,*Rd %s' % al, '13-6 T13-2', 'MOVB A0, *A1', sh[0], sh[1],
                        sh[0] + sh[1] + 3,
                        setup=['MOVI 0x%08X, A1, L' % (DATA_BASE + off), 'MOVI 0x5A, A0']))
    # Sign extension (Table 13-1 note 1): FE=1 adds one state to MOVE loads.
    for al in 'ABEF':
        fs, off = ALIGNS[al]
        if fs == 32:
            continue
        hit = 3 if al in 'AB' else 5
        out.append(Case('MOVE *Rs,Rd %s fs%d sign-extend' % (al, fs), '13-5 T13-1 note 1',
                        'MOVE *A1, A0, 0', hit + 1, 0, hit + 4,
                        setup=['SETF %d, 1, 0' % fs, 'MOVI 0x%08X, A1, L' % (DATA_BASE + off)]))
    return out


def stack_nonaligned_cases():
    """Pages 12-35..12-37, 12-204..12-207 with SP not word-aligned."""
    sp = STACK_TOP + 8
    nops = ['NOP'] * 11
    return [
        Case('CALL SP nonaligned', '12-48', ['M: CALL A0'], 3, 9, 15, sp=sp,
             setup=['MOVI S, A0, L'], sub=['S: NOP'] + nops + ['RETS']),
        Case('CALLR SP nonaligned', '12-50', ['M: CALLR S'], 3, 8, 17, sp=sp,
             sub=['S: NOP'] + nops + ['RETS']),
        Case('CALLA SP nonaligned', '12-49', ['M: CALLA S'], 4, 8, 21, sp=sp,
             sub=['S: NOP'] + nops + ['RETS']),
        Case('RETS nonaligned', '12-232', ['CALLR S', 'MN: NOP'], 9, 0, 12, sp=sp,
             sub=['S: NOP'] + nops + ['M: RETS']),
        Case('PUSHST SP nonaligned', '12-228', ['M: PUSHST', 'MN: NOP'] + ['NOP'] * 12 + ['POPST'],
             2, 8, 13, sp=sp),
        Case('POPST SP nonaligned', '12-227', ['PUSHST'] + ['NOP'] * 12 + ['M: POPST', 'MN: NOP'],
             10, 0, 13, sp=sp),
    ]


def fill_transfer(n, rows, al, g, rmw):
    """Table 13-6 (13-11) with G from Table 13-7 (13-13) and the 13.3.2.6
    alignment/graphics adjustment."""
    if n == 1:
        k, e = {'A': (1, 2), 'B': (2, 2), 'C': (2, 1), 'D': (2, 1)}[al]
    elif n == 2:
        k, e = {'A': (2, 2), 'B': (3, 2), 'C': (3, 2), 'D': (4, 1)}[al]
    else:
        k, e = {'A': (1, 2), 'B': (2, 5), 'C': (3, 2), 'D': (4, 1)}[al]
    t = (k + n * g) * rows + e
    if rmw:
        t -= {'A': 0, 'B': 2, 'C': 2, 'D': 4}[al] * rows
    return t


def dest_pattern(base, rows, pitch=0x1000, longs=2):
    """Store a non-zero pattern in the destination rows first, so pixel
    processing, plane masking and transparency have something to work on."""
    out = ['SETF 32, 0, 0', 'MOVI 0x96C3A51E, A5, L']
    for r in range(rows):
        for w in range(longs):
            out += ['MOVI 0x%08X, A6, L' % (base + r * pitch + 32 * w), 'MOVE A5, *A6, 0']
    return [l + ' ; pre' for l in out + ['SETF 16, 0, 0']]


def fill_cases():
    """FILL, 13.3 (SPVU001A 13-10..13-16): setup (Table 13-5) + transfer
    (Table 13-6) at PSIZE 4. Row shapes: N words per row with the leading /
    trailing edge on a word boundary or not (alignments A-D, Figure 13-5)."""
    out = []
    rows = 3
    shapes = {  # (N, alignment): (bit offset of the first pixel, DX)
        (1, 'A'): (0, 4), (1, 'B'): (0, 2), (1, 'C'): (8, 2), (1, 'D'): (4, 2),
        (2, 'A'): (0, 8), (2, 'B'): (0, 6), (2, 'C'): (8, 6), (2, 'D'): (4, 6),
        (4, 'A'): (0, 16), (4, 'B'): (0, 14), (4, 'C'): (8, 14), (4, 'D'): (4, 14)}
    ops = [('Replace', 0b00000, 0, [], 2, False), ('AND', 0b00001, 0, [], 4, False),
           ('ADDS', 0b10001, 0, [], 5, False), ('SUBS', 0b10011, 0, [], 6, False),
           ('Replace T', 0b00000, CTRL_T, [], 4, True),
           ('AND PMASK', 0b00001, 0, [(PMASK_ADDR, 0x1111)], 6, True)]
    for (n, al), (off, dx) in shapes.items():
        for oname, code, ctrl, io, g, rmw in ops:
            hit = 4 + fill_transfer(n, rows, al, g, rmw)
            note = 'short-d-adjust' if (n == 1 and al == 'D' and rmw) else ''
            out.append(Case('FILL L %s N%d %s psize4 L%d' % (al, n, oname, rows),
                            '13-10 T13-5/13-6/13-7', 'FILL L', hit, -1, hit + 3, note=note,
                            io=[(PSIZE_ADDR, 4)] + io, ctrl=(code << 10) | ctrl,
                            setup=dest_pattern(DATA_BASE, rows) + [
                                   'MOVI 0x%08X, B2, L' % (DATA_BASE + off),    # DADDR
                                   'MOVI 0x00001000, B3, L',                     # DPTCH
                                   'MOVI 0x%08X, B7, L' % ((rows << 16) | dx),    # DYDX
                                   'MOVI 0x5A5A5A5A, B9, L']))                   # COLOR1
    # Other pixel sizes, for the per-pixel arithmetic of the word datapath:
    # a long row of 4 words, edges D (both partial) where the size allows.
    for psize, off, dx, al in ((1, 3, 58, 'D'), (2, 2, 28, 'D'), (8, 8, 6, 'D'), (16, 0, 4, 'A')):
        for oname, code, ctrl, io, g, rmw in ops[2:]:
            hit = 4 + fill_transfer(4, rows, al, g, rmw)
            out.append(Case('FILL L %s N4 %s psize%d L%d' % (al, oname, psize, rows),
                            '13-10 T13-5/13-6/13-7', 'FILL L', hit, -1, hit + 3,
                            io=[(PSIZE_ADDR, psize)] + io, ctrl=(code << 10) | ctrl,
                            setup=dest_pattern(DATA_BASE, rows, longs=3) + [
                                   'MOVI 0x%08X, B2, L' % (DATA_BASE + off), 'MOVI 0x00001000, B3, L',
                                   'MOVI 0x%08X, B7, L' % ((rows << 16) | dx), 'MOVI 0x5A3C96E1, B9, L']))
    # FILL XY (setup 6), and W=3 preclipping (Table 13-5): the array fits (9),
    # the start corner moves (16), the far corner moves (12), both (20).
    # Array X 8..23, Y 4..6 (PSIZE 4: X 8 is bit 32, word aligned; 16 pixels,
    # N = 4, alignment A when unclipped).
    xy = ['MOVI 0x00040008, B2, L', 'MOVI 0x00001000, B3, L', 'MOVI 0x%08X, B4, L' % DATA_BASE,
          'MOVI 0x00030010, B7, L', 'MOVI 0x5A5A5A5A, B9, L']
    io = [(PSIZE_ADDR, 4), (CONVDP_ADDR, 19)]
    for name, w, win, setup_states, n, al, l in (
            ('W=0', 0, (0x00000000, 0x00000000), 6, 4, 'A', 3),
            ('W=3 fits', 3, (0x00000000, 0x00FF00FF), 9, 4, 'A', 3),
            ('W=3 start adjust', 3, (0x0005000C, 0x00FF00FF), 16, 3, 'A', 2),   # X 12..23, Y 5..6
            ('W=3 dimension adjust', 3, (0x00000000, 0x00050013), 12, 3, 'A', 2),  # X 8..19, Y 4..5
            ('W=3 adjust both', 3, (0x0005000C, 0x00050013), 20, 2, 'A', 1)):  # X 12..19, Y 5
        hit = setup_states + fill_transfer(n, l, al, 2, False)
        out.append(Case('FILL XY %s psize4' % name, '13-10 T13-5/13-6', 'FILL XY', hit, -1, hit + 3,
                        io=io, ctrl=w << 6,
                        setup=xy + ['MOVI 0x%08X, B5, L' % win[0], 'MOVI 0x%08X, B6, L' % win[1]]))
    return out


# Table 13-9 (SPVU001A 13-20) as printed: {PBH: {class: {D>=S '>' / D<S '<':
# {alignment: (row constant k, end e)}}}; per-word term (2+G)N except where noted.
PBLT_T139 = {
    0: {'short': {'>': {'A': (4, 5), 'B': (6, 3), 'C': (6, 3), 'D': (6, 3)},
                  '<': {'A': (4, 5), 'B': (6, 3), 'C': (6, 3), 'D': (6, 3)}},
        'medium': {'>': {'A': (2, 5), 'B': (4, 3), 'C': (4, 5), 'D': (6, 3)},
                   '<': {'A': (4, 4), 'B': (6, 2), 'C': (6, 4), 'D': (8, 2)}},
        'long': {'>': {'A': (0, 5), 'B': (2, 3), 'C': (2, 5), 'D': (2, 3)},
                 '<': {'A': (2, 4), 'B': (4, 2), 'C': (4, 4), 'D': (6, 2)}}},
    1: {'short': {'>': {'A': (3, 8), 'B': (4, 7), 'C': (4, 7), 'D': (4, 7)},
                  '<': {'A': (3, 8), 'B': (4, 7), 'C': (4, 7), 'D': (4, 7)}},
        'medium': {'>': {'A': (2, 4), 'B': (4, 3), 'C': (4, 4), 'D': (6, 3)},
                   '<': {'A': (4, 5), 'B': (5, 4), 'C': (6, 5), 'D': (7, 4)}},
        'long': {'>': {'A': (1, 4), 'B': (3, 3), 'C': (3, 4), 'D': (5, 3)},
                 '<': {'A': (3, 5), 'B': (4, 4), 'C': (5, 5), 'D': (6, 4)}}}}


def pblt_transfer(pbh, n, rows, rel, al, g, rmw):
    """Table 13-9 as printed (PBH=0 long: D>=S D per word (4+G), D<S per word
    2G), less the 13.4.2.7 adjustment."""
    cls = 'short' if n == 1 else 'medium' if n == 2 else 'long'
    k, e = PBLT_T139[pbh][cls][rel][al]
    if n == 1:
        t = (k + g) * rows + e
    elif n == 2:
        t = (k + 4 + 2 * g) * rows + e
    else:
        per = (4 + g) if (pbh == 0 and rel == '>' and al == 'D') else \
              (2 * g) if (pbh == 0 and rel == '<') else (2 + g)
        t = (k + per * n) * rows + e
    if rmw:
        t -= {'A': 0, 'B': 2, 'C': 2, 'D': 4}[al] * rows
    return t


def pblt_note(pbh, n, rel, al, g, rmw):
    """The docs entry explaining a printed Table 13-9 figure the model doesn't give."""
    if n == 1 and al == 'D' and rmw:
        return 'short-d-adjust'
    if pbh == 1 and n == 1 and rel == '<':
        return 'pblt-short-ds'
    if pbh == 0 and n >= 3 and ((al == 'D' and rel == '>') or (rel == '<' and g != 2)):
        return 'pblt-misprint'
    return ''


def pblt_two_src(pbh, d_lo, rowbits, s_lo):
    """Whether the row's first destination word needs two source words
    (D < S, 13.4.2.4), in the direction of travel."""
    if pbh == 0:
        b0 = min(rowbits, 16 - (d_lo % 16))
        s_first = s_lo
    else:
        d_hi = d_lo + rowbits
        b0 = min(rowbits, (d_hi % 16) or 16)
        s_first = s_lo + rowbits - b0
    return (s_first % 16) + b0 > 16


def pblt_cases():
    """PIXBLT L,L (13.4, SPVU001A 13-18..13-25): setup 7 (Table 13-8) plus the
    transfer of Table 13-9 at PSIZE 4, both PBH directions, D>=S and D<S."""
    out = []
    rows = 3
    shapes = {(1, 'A'): (0, 4), (1, 'B'): (0, 2), (1, 'C'): (8, 2), (1, 'D'): (4, 2),
              (2, 'A'): (0, 8), (2, 'B'): (0, 6), (2, 'C'): (8, 6), (2, 'D'): (4, 6),
              (4, 'A'): (0, 16), (4, 'B'): (0, 14), (4, 'C'): (8, 14), (4, 'D'): (4, 14)}
    ops = [('Replace', 0b00000, 0, [], 2, False), ('AND', 0b00001, 0, [], 4, False),
           ('ADDS', 0b10001, 0, [], 5, False), ('SUBS', 0b10011, 0, [], 6, False),
           ('Replace T', 0b00000, CTRL_T, [], 4, True),
           ('AND PMASK', 0b00001, 0, [(PMASK_ADDR, 0x1111)], 6, True)]
    src_base, dst_base = DATA_BASE + 0x800, DATA_BASE
    for pbh in (0, 1):
        for (n, al), (d_off, dx) in shapes.items():
            rowbits = dx * 4
            done = set()
            for s_off in (0, 4, 8, 12):
                rel = '<' if pblt_two_src(pbh, d_off, rowbits, s_off) else '>'
                if rel in done:
                    continue
                done.add(rel)
                for oname, code, ctrl, io, g, rmw in ops:
                    hit = 7 + pblt_transfer(pbh, n, rows, rel, al, g, rmw)
                    note = pblt_note(pbh, n, rel, al, g, rmw)
                    # PBH=1: L,L takes the pointers as supplied, one past the row's end.
                    sa = src_base + s_off + (rowbits if pbh else 0)
                    da = dst_base + d_off + (rowbits if pbh else 0)
                    out.append(Case('PIXBLT L,L PBH%d D%sS %s N%d %s psize4 L%d' % (
                                        pbh, '>=' if rel == '>' else '<', al, n, oname, rows),
                                    '13-18 T13-8/13-9/13-10', 'PIXBLT L, L', hit, -1, hit + 3,
                                    note=note, io=[(PSIZE_ADDR, 4)] + io,
                                    ctrl=(code << 10) | ctrl | (pbh << 8),
                                    setup=dest_pattern(dst_base, rows) + [
                                        'MOVI 0x3C5A96E1, A5, L ; pre', 'SETF 32, 0, 0 ; pre'] + sum(
                                        (['MOVI 0x%08X, A6, L ; pre' % (src_base + r * 0x1000 + 32 * w),
                                          'MOVE A5, *A6, 0 ; pre'] for r in range(rows) for w in range(2)), []) + [
                                        'SETF 16, 0, 0 ; pre',
                                        'MOVI 0x%08X, B0, L' % sa, 'MOVI 0x00001000, B1, L',
                                        'MOVI 0x%08X, B2, L' % da, 'MOVI 0x00001000, B3, L',
                                        'MOVI 0x%08X, B7, L' % ((rows << 16) | dx)]))
    return out


def pblt_xy_cases():
    """PIXBLT XY forms (Table 13-8 setup: XY,L and L,XY 9, XY,XY 12; corner
    adjust +1 PBH, +2 PBV, +4 both; W=3 preclip for an XY destination: fits
    +3, start +10, dimension +6, both +14) with the Table 13-9 transfer for the
    clipped array, PSIZE 4. Source X 3 (bit 12), destination X 2 (bit 8), so
    the rows are alignment C/D and the first word needs two source words
    (D < S) going forward, one (D >= S) going backward."""
    out = []
    io = [(PSIZE_ADDR, 4), (CONVDP_ADDR, 19), (CONVSP_ADDR, 19)]
    src_lin, dst_lin = DATA_BASE + 0x800, DATA_BASE
    rows, dx = 3, 14
    def addr_setup(form, sx, sy, dxp, dyp):
        sa = ((sy << 16) | sx) if form[0] == 'XY' else src_lin + sy * 0x1000 + sx * 4
        da = ((dyp << 16) | dxp) if form[1] == 'XY' else dst_lin + dyp * 0x1000 + dxp * 4
        return sa, da
    for form in (('XY', 'L'), ('L', 'XY'), ('XY', 'XY')):
        base_setup = 12 if form == ('XY', 'XY') else 9
        for pbh, pbv in ((0, 0), (1, 0), (0, 1), (1, 1)):
            corner = {(0, 0): 0, (1, 0): 1, (0, 1): 2, (1, 1): 4}[(pbh, pbv)]
            for oname, code, g in (('Replace', 0, 2), ('ADDS', 0b10001, 5)):
                d_lo, s_lo, rowbits = 8, 12, dx * 4
                al = 'A' if d_lo % 16 == 0 and (d_lo + rowbits) % 16 == 0 else \
                     'B' if d_lo % 16 == 0 else 'C' if (d_lo + rowbits) % 16 == 0 else 'D'
                n = (d_lo % 16 + rowbits + 15) // 16
                rel = '<' if pblt_two_src(pbh, d_lo, rowbits, s_lo) else '>'
                hit = base_setup + corner + pblt_transfer(pbh, n, rows, rel, al, g, False)
                sa, da = addr_setup(form, 3, 8, 2, 0)      # source rows 8..10: no overlap
                out.append(Case('PIXBLT %s,%s PBH%d PBV%d %s psize4' % (form[0], form[1], pbh, pbv, oname),
                                '13-18 T13-8/13-9', 'PIXBLT %s, %s' % form, hit, -1, hit + 3,
                                note=pblt_note(pbh, n, rel, al, g, False),
                                io=io, ctrl=(code << 10) | (pbh << 8) | (pbv << 9),
                                setup=dest_pattern(dst_lin, rows)
                                + dest_pattern(DATA_BASE + 8 * 0x1000, rows)
                                + dest_pattern(src_lin + 8 * 0x1000, rows) + [
                                    'MOVI 0x%08X, B0, L' % sa, 'MOVI 0x00001000, B1, L',
                                    'MOVI 0x%08X, B2, L' % da, 'MOVI 0x00001000, B3, L',
                                    'MOVI 0x%08X, B4, L' % DATA_BASE,
                                    'MOVI 0x%08X, B7, L' % ((rows << 16) | dx)]))
        if form[1] != 'XY':
            continue
        # W=3 preclipping, PBH = PBV = 0. Destination array X 2..15, Y 4..6.
        for wname, win, extra, cdx, crows, cx0 in (
                ('fits', (0x00000000, 0x00FF00FF), 3, 14, 3, 2),
                ('start adjust', (0x00050006, 0x00FF00FF), 10, 10, 2, 6),
                ('dimension adjust', (0x00000000, 0x0005000B), 6, 10, 2, 2),
                ('adjust both', (0x00050006, 0x0005000B), 14, 6, 1, 6)):
            d_lo, rowbits = cx0 * 4, cdx * 4
            s_lo = (3 + cx0 - 2) * 4
            al = 'A' if d_lo % 16 == 0 and (d_lo + rowbits) % 16 == 0 else \
                 'B' if d_lo % 16 == 0 else 'C' if (d_lo + rowbits) % 16 == 0 else 'D'
            n = (d_lo % 16 + rowbits + 15) // 16
            rel = '<' if pblt_two_src(0, d_lo, rowbits, s_lo) else '>'
            hit = base_setup + extra + pblt_transfer(0, n, crows, rel, al, 2, False)
            sa, da = addr_setup(form, 3, 12, 2, 4)     # source rows 12..14: no overlap
            out.append(Case('PIXBLT %s,%s W=3 %s psize4' % (form[0], form[1], wname),
                            '13-18 T13-8/13-9', 'PIXBLT %s, %s' % form, hit, -1, hit + 3,
                            io=io, ctrl=3 << 6,
                            setup=dest_pattern(dst_lin + 4 * 0x1000, rows)
                            + dest_pattern(DATA_BASE + 12 * 0x1000, rows)
                            + dest_pattern(src_lin + 12 * 0x1000, rows) + [
                                'MOVI 0x%08X, B0, L' % sa, 'MOVI 0x00001000, B1, L',
                                'MOVI 0x%08X, B2, L' % da, 'MOVI 0x00001000, B3, L',
                                'MOVI 0x%08X, B4, L' % DATA_BASE,
                                'MOVI 0x%08X, B5, L' % win[0], 'MOVI 0x%08X, B6, L' % win[1],
                                'MOVI 0x%08X, B7, L' % ((rows << 16) | dx)]))
    return out


def pblt_expand_cases():
    """PIXBLT B,L (13.5, SPVU001A 13-31..13-36): setup 4 (Table 13-11) plus
    Table 13-12 at PSIZE 4 and 8. R = source words of the row (short and
    medium rows); long rows are 32-pixel segments (13.5.2.3)."""
    out = []
    rows = 3
    src_base, dst_base = DATA_BASE + 0x800, DATA_BASE
    ops = [('Replace', 0b00000, 0, [], 2, False), ('AND', 0b00001, 0, [], 4, False),
           ('ADDS', 0b10001, 0, [], 5, False), ('Replace T', 0b00000, CTRL_T, [], 4, True)]
    for psize in (4, 8):
        ppw = 16 // psize
        shapes = [  # name, d_off (pixels), dx
            ('A', 0, ppw), ('B', 0, ppw // 2), ('C', ppw // 2, ppw // 2), ('D', 1, ppw // 2 - 1 or 1),
            ('A', 0, 2 * ppw), ('B', 0, 2 * ppw - 1), ('C', 1, 2 * ppw - 1), ('D', 1, 2 * ppw - 2),
            ('A', 0, 6 * ppw), ('D', 1, 6 * ppw - 2),
            ('A', 0, 48), ('D', 1, 46), ('A', 0, 96), ('D', 1, 94), ('A', 0, 64), ('D', 1, 78)]
        for al, dpx, dx in shapes:
            d_off = dpx * psize
            rowbits = dx * psize
            n = (d_off + rowbits + 15) // 16
            if psize == 8 and al == 'D' and n == 1:
                continue                       # no pixel strictly inside a word at PSIZE 8
            for s_off in (0, 30 - (dx % 16) if dx <= 32 else 13):
                r = (s_off % 16 + dx + 15) // 16 if dx <= 32 else None
                for oname, code, ctrl, io, g, rmw in ops:
                    note = ''
                    note = ''
                    if n == 1:
                        t = (3 + 2 * r + g) * rows + 3
                    elif dx <= 32:
                        t = ((3 if al in 'AC' else 5) + 2 * r + n * g) * rows + 3
                    else:
                        sets = dx // 32
                        s_cnt = sets - 1 if sets % 2 == 0 else sets
                        rr = (s_off % 16 + 32 + 15) // 16
                        rem = dx - 32 * sets
                        v = (s_off % 16 + rem + 15) // 16 if rem else 0
                        y = n - 2 * psize * sets
                        if al == 'A':
                            t = ((3 + 2 * rr + 2 * g * psize) * s_cnt + 2 * v + n * g) * rows + 3
                        else:
                            t = ((8 + 2 * rr + 2 * g * psize) * s_cnt + 2 * v + y * g + 8) * rows + 3
                        note = 'expand-long'
                    if rmw:
                        t -= {'A': 0, 'B': 2, 'C': 2, 'D': 4}[al] * rows
                    if n == 1 and al == 'D' and rmw:
                        note = 'short-d-adjust'
                    hit = 4 + t
                    out.append(Case('PIXBLT B,L %s N%d R%s %s psize%d' % (al, n, r if r else 'x', oname, psize),
                                    '13-31 T13-11/13-12/13-13', 'PIXBLT B, L', hit, -1, hit + 3,
                                    note=note, io=[(PSIZE_ADDR, psize)] + io, ctrl=(code << 10) | ctrl,
                                    setup=dest_pattern(dst_base, rows, longs=4)
                                    + dest_pattern(src_base, rows, longs=3) + [
                                        'MOVI 0x%08X, B0, L' % (src_base + s_off), 'MOVI 0x00001000, B1, L',
                                        'MOVI 0x%08X, B2, L' % (dst_base + d_off), 'MOVI 0x00001000, B3, L',
                                        'MOVI 0x%08X, B7, L' % ((rows << 16) | dx),
                                        'MOVI 0x5A3C96E1, B8, L', 'MOVI 0x1E2D4B87, B9, L']))
    return out


def pblt_more_cases():
    """PIXBLT B,XY setup (Table 13-11: 6, W=3 9/17/12/21) and full-color
    PIXBLT L,L at the other pixel sizes (a long row, PBH 0 and 1)."""
    out = []
    rows = 3
    io = [(PSIZE_ADDR, 8), (CONVDP_ADDR, 19)]
    # B,XY: destination X 2..13 (12 pixels of 8 bits: bits 16..112, N = 6,
    # alignment A), Y 4..6; source 12 bits per row at bit 0 (R = 1).
    for wname, w, win, setup_states, cdx, crows, cx0 in (
            ('W=0', 0, (0, 0), 6, 12, 3, 2),
            ('W=3 fits', 3, (0x00000000, 0x00FF00FF), 9, 12, 3, 2),
            ('W=3 start adjust', 3, (0x00050004, 0x00FF00FF), 17, 10, 2, 4),
            ('W=3 dimension adjust', 3, (0x00000000, 0x0005000B), 12, 10, 2, 2),
            ('W=3 adjust both', 3, (0x00050004, 0x0005000B), 21, 8, 1, 4)):
        d_lo = cx0 * 8
        n = (d_lo % 16 + cdx * 8 + 15) // 16
        al = 'A' if (d_lo % 16 == 0 and (d_lo + cdx * 8) % 16 == 0) else 'D'
        s_lo = cx0 - 2
        r = (s_lo % 16 + cdx + 15) // 16
        t = ((3 if al in 'AC' else 5) + 2 * r + n * 2) * crows + 3 if n > 1 else (3 + 2 * r + 2) * crows + 3
        hit = setup_states + t
        out.append(Case('PIXBLT B,XY %s psize8' % wname, '13-31 T13-11/13-12', 'PIXBLT B, XY', hit, -1,
                        hit + 3, io=io, ctrl=w << 6,
                        setup=dest_pattern(DATA_BASE + 4 * 0x1000, rows, longs=4)
                        + dest_pattern(DATA_BASE + 0x800, rows, longs=1) + [
                            'MOVI 0x%08X, B0, L' % (DATA_BASE + 0x800), 'MOVI 0x00001000, B1, L',
                            'MOVI 0x00040002, B2, L', 'MOVI 0x00001000, B3, L',
                            'MOVI 0x%08X, B4, L' % DATA_BASE,
                            'MOVI 0x%08X, B5, L' % win[0], 'MOVI 0x%08X, B6, L' % win[1],
                            'MOVI 0x%08X, B7, L' % ((rows << 16) | 12),
                            'MOVI 0x5A3C96E1, B8, L', 'MOVI 0x1E2D4B87, B9, L']))
    # Full color at PSIZE 1, 2, 8, 16: a long row, the first destination word
    # partial where the size allows.
    for psize, d_px, s_px, dx in ((1, 3, 9, 58), (2, 1, 5, 29), (8, 1, 0, 7), (16, 0, 0, 4)):
        for pbh in (0, 1):
            d_lo, s_lo, rowbits = d_px * psize, s_px * psize, dx * psize
            n = (d_lo % 16 + rowbits + 15) // 16
            al = ('A' if d_lo % 16 == 0 else 'C') if (d_lo + rowbits) % 16 == 0 else \
                 ('B' if d_lo % 16 == 0 else 'D')
            rel = '<' if pblt_two_src(pbh, d_lo, rowbits, s_lo) else '>'
            for oname, code, g in (('Replace', 0, 2), ('ADDS', 0b10001, 5)):
                hit = 7 + pblt_transfer(pbh, n, rows, rel, al, g, False)
                sa = DATA_BASE + 0x800 + s_lo + (rowbits if pbh else 0)
                da = DATA_BASE + d_lo + (rowbits if pbh else 0)
                out.append(Case('PIXBLT L,L PBH%d D%sS %s N%d %s psize%d' % (
                                    pbh, '>=' if rel == '>' else '<', al, n, oname, psize),
                                '13-18 T13-8/13-9/13-10', 'PIXBLT L, L', hit, -1, hit + 3,
                                note=pblt_note(pbh, n, rel, al, g, False),
                                io=[(PSIZE_ADDR, psize)], ctrl=(code << 10) | (pbh << 8),
                                setup=dest_pattern(DATA_BASE, rows, longs=3)
                                + dest_pattern(DATA_BASE + 0x800, rows, longs=3) + [
                                    'MOVI 0x%08X, B0, L' % sa, 'MOVI 0x00001000, B1, L',
                                    'MOVI 0x%08X, B2, L' % da, 'MOVI 0x00001000, B3, L',
                                    'MOVI 0x%08X, B7, L' % ((rows << 16) | dx)]))
    return out


def trap_cases():
    """TRAP (12-229) and RETI (12-207). The vector for TRAP 5 is written by the
    setup; the handler drains with NOPs and returns."""
    vec = 0xFFFF_FFE0 - 5 * 32
    nops = ['NOP'] * 11
    setup = ['SETF 32, 0, 0', 'MOVI H, A0, L', 'MOVE A0, @0x%08X, 0' % vec, 'SETF 16, 0, 0']
    out = []
    for sp, tag, trap, reti in ((STACK_TOP, 'aligned', 16, 11), (STACK_TOP + 8, 'nonaligned', 30, 15)):
        out.append(Case('TRAP SP %s' % tag, '12-254', ['M: TRAP 5', 'NOP'], trap, 0, trap + 3,
                        sp=sp, setup=setup, sub=['H: NOP'] + nops + ['RETI']))
        out.append(Case('RETI %s' % tag, '12-230', ['TRAP 5', 'MN: NOP'], reti, 0, reti + 3,
                        sp=sp, setup=setup, sub=['H: NOP'] + nops + ['M: RETI']))
    return out


def srt_cases():
    """NARC's high-score scroll (BITCHIN_SCROLL): PIXT with DPYCTL.SRT set
    becomes a memory-to-register / register-to-memory VRAM transfer (9.x),
    one two-state cycle each, so the PIXT figures (12-190, 12-195) apply."""
    io = [(PSIZE_ADDR, 16), (0xC000_0080, 1 << 11)]           # DPYCTL.SRT
    setup = ['MOVI 0x0001E000, A2, L', 'MOVI 0x0001C000, A1, L']
    return [
        Case('PIXT *Rs,Rd SRT (MTR) psize16', '12-218', 'PIXT *A2, A4', 4, 0, 7, io=io, setup=setup),
        Case('PIXT Rs,*Rd SRT (RTM) psize16', '12-214', 'PIXT A4, *A1', 2, 1, 6, io=io, setup=setup),
    ]


def line_cases():
    """LINE, 13.6: 4 + (3 + P)E, P = 2 for Replace (Table 13-15). The
    guide's example (13-35): 23 pixels, 119 states."""
    out = []
    for psize in (16, 8):
        setup = ['MOVI 0xFFFFFFF1, B0, L',              # d
                 'MOVI 0x00340003, B2, L',              # DADDR (X=3, Y=52)
                 'MOVI 0x00000800, B3, L',              # DPTCH
                 'MOVI 0x%08X, B4, L' % DATA_BASE,      # OFFSET
                 'MOVI 0x00030016, B7, L',              # b=3, a=22
                 'MOVI 0x44444444, B9, L',              # COLOR1
                 'MOVI 0x00000017, B10, L',             # COUNT = 23
                 'MOVI 0x00010001, B11, L',             # INC1
                 'MOVI 0x00000001, B12, L',             # INC2
                 'MOVI 0xFFFFFFFF, B13, L']             # PATTRN
        for pname, code, p in (('Replace', 0b00000, 2), ('AND', 0b00001, 4), ('ADDS', 0b10001, 5),
                               ('MAX', 0b10100, 5), ('SUBS', 0b10011, 6)):
            hit = 4 + (3 + p) * 23
            out.append(Case('LINE 0 %s E23 psize%d' % (pname, psize), '12-102 T12-10/12-11', 'LINE 0',
                            hit, -1, -1, ctrl=code << 10,
                            io=[(PSIZE_ADDR, psize), (CONVDP_ADDR, 0x14)], setup=setup))
    return out


def line_window_cases():
    """LINE with window checking, Table 12-10 (12-102): W=1 5q+5; W=2 (3+P)E,
    +5 for a violation; W=3 (3+P)E+5q (E pixels written, q calculated but not
    written; the violating pixel is the +5, docs C10). The line of the guide's
    example: 23 pixels, X 3..25."""
    out = []
    base = ['MOVI 0xFFFFFFF1, B0, L', 'MOVI 0x00340003, B2, L', 'MOVI 0x00000800, B3, L',
            'MOVI 0x%08X, B4, L' % DATA_BASE, 'MOVI 0x00030016, B7, L', 'MOVI 0x44444444, B9, L',
            'MOVI 0x00000017, B10, L', 'MOVI 0x00010001, B11, L', 'MOVI 0x00000001, B12, L',
            'MOVI 0xFFFFFFFF, B13, L']
    first10 = ['MOVI 0x00000003, B5, L', 'MOVI 0x0100000C, B6, L']    # X 3..12: pixels 1-10
    from11 = ['MOVI 0x0000000D, B5, L', 'MOVI 0x01000019, B6, L']     # X 13..25: pixels 11-23
    away = ['MOVI 0x00000100, B5, L', 'MOVI 0x01000200, B6, L']       # no pixel inside
    for pname, code, p in (('Replace', 0b00000, 2), ('AND', 0b00001, 4)):
        for w, win, wname, states in (
                (3, first10, 'first 10 inside', 4 + (3 + p) * 10 + 5 * 13),
                (2, first10, 'first 10 inside', 4 + (3 + p) * 10 + 5),
                (1, from11, 'pixel 11 inside', 4 + 5 * 10 + 5),
                (1, away, 'none inside', 4 + 5 * 23 + 5)):
            out.append(Case('LINE 0 %s W=%d %s psize8' % (pname, w, wname), '12-102 T12-10',
                            'LINE 0', states, -1, states + 3, ctrl=(code << 10) | (w << 6),
                            io=[(PSIZE_ADDR, 8), (CONVDP_ADDR, 0x14)], setup=base + win))
    return out


def extra_cases():
    """More Section 12 pages and Table 13-1 rows."""
    setup = ['MOVI 0x00030004, A1, L', 'MOVI 0x00500060, A0, L']
    out = [
        Case('REV A0', '12-233', 'REV A0', 1, 0, 4),
        Case('EXGPC A0', '12-79', 'EXGPC A0', 2, 0, 5, setup=['MOVI N, A0, L']),
        # 12-58/12-60: DSJEQ/DSJNE decrement and jump only when the Z test
        # passes; otherwise they skip (no jump).
        Case('DSJEQ Z=1 taken', '12-71', ['DSJEQ A2, N', 'NOP'], 3, 0, 9,
             setup=['MOVK 9, A2', 'CLR A3']),
        Case('DSJEQ Z=1 not taken', '12-71', 'DSJEQ A2, N', 2, 0, 8,
             setup=['MOVK 1, A2', 'CLR A3']),
        Case('DSJEQ Z=0 skip', '12-71', 'DSJEQ A2, N', 2, 0, 8,
             setup=['MOVK 9, A2', 'MOVK 1, A3', 'MOVE A3, A3']),
        Case('DSJNE Z=0 taken', '12-73', ['DSJNE A2, N', 'NOP'], 3, 0, 9,
             setup=['MOVK 9, A2', 'MOVK 1, A3', 'MOVE A3, A3']),
        Case('DSJNE Z=1 skip', '12-73', 'DSJNE A2, N', 2, 0, 8,
             setup=['MOVK 9, A2', 'CLR A3']),
        Case('JRV short not taken (V=0)', '12-95', 'JRV E', 1, 0, 4, setup=setup),
    ]
    # An I/O register read (6.1: on-chip registers are read with a local
    # memory cycle), timed as MOVE @Address,Rd alignment A (Table 13-1).
    out.append(Case('MOVE @PSIZE,Rd (I/O register)', '13-5 T13-1', 'MOVE @0x%08X, A0, 0' % PSIZE_ADDR,
                    5, 0, 14, io=[(PSIZE_ADDR, 8)]))
    out.append(Case('MOVE @CONTROL,Rd (I/O register)', '13-5 T13-1', 'MOVE @0x%08X, A0, 0' % CONTROL_ADDR,
                    5, 0, 14))
    # Table 13-1: MOVE @Address,Rd and MOVB loads.
    for al in 'ABCDEFG':
        hit, dis = (5, 14) if al in 'AB' else (9, 18) if al == 'G' else (7, 16)
        fs, off = ALIGNS[al]
        out.append(Case('MOVE @Address,Rd %s fs%d' % (al, fs), '13-5 T13-1',
                        'MOVE @0x%08X, A0, 0' % (DATA_BASE + off), hit, 0, dis,
                        setup=['SETF %d, 0, 0' % (fs & 31)]))
    for al, off, hd, ha in (('B', 0, (5, 11), (5, 14)), ('F', 12, (7, 13), (7, 16))):
        out.append(Case('MOVB *Rs(Disp),Rd %s' % al, '13-5 T13-1', 'MOVB *A1(0), A0', hd[0], 0, hd[1],
                        setup=['MOVI 0x%08X, A1, L' % (DATA_BASE + off)]))
    return out


def review_cases():
    """Forms and data dependences the first review (REVIEW_ee26d33.md) found
    missing from the bench."""
    out = []
    # Table 13-2: MOVE Rs,@Address (13-6).
    t = {'A': (1, 13), 'B': (3, 15), 'C': (3, 15), 'D': (5, 17), 'E': (5, 17), 'F': (7, 19), 'G': (9, 21)}
    for al, (hid, dis) in t.items():
        fs, off = ALIGNS[al]
        out.append(Case('MOVE Rs,@Address %s fs%d' % (al, fs), '13-6 T13-2',
                        'MOVE A0, @0x%08X, 0' % (DATA_BASE + off), 3, hid, dis,
                        setup=['SETF %d, 0, 0' % (fs & 31), 'MOVI 0x12345678, A0, L']))
    # MOVB stores and loads with a displacement or an absolute address
    # (Tables 13-1, 13-2): alignment B (byte in one word) and F (straddling).
    for al, off in (('B', 0), ('F', 12)):
        a = DATA_BASE + off
        st_d, st_a = ((3, 3, 7), (1, 3, 7)) if al == 'B' else ((3, 7, 13), (3, 7, 13))
        out.append(Case('MOVB Rs,*Rd(Disp) %s' % al, '13-6 T13-2', 'MOVB A0, *A1(0)', *st_d,
                        note='movb-store-ext', setup=['MOVI 0x%08X, A1, L' % a, 'MOVI 0x5A, A0']))
        out.append(Case('MOVB Rs,@Address %s' % al, '13-6 T13-2', 'MOVB A0, @0x%08X' % a, *st_a,
                        note='movb-store-ext' + (' movb-abs-b' if al == 'B' else ''),
                        setup=['MOVI 0x5A, A0']))
        ld = (5, 0, 14) if al == 'B' else (7, 0, 16)
        out.append(Case('MOVB @Address,Rd %s' % al, '13-5 T13-1', 'MOVB @0x%08X, A0' % a, *ld))
    # Figure 5-9 (5-29): TI's state-by-state diagram of a graphics inner loop,
    # 12 states per iteration (the Section 12 figures add up to 11).
    out.append(Case('Figure 5-9 loop', '5-26 F5-9',
                    ['MOVE *B1+, B10, 0', 'ADD B10, B8', 'PIXT *B1, *B8', 'ADD B0, B1', 'DSJS B11, N'],
                    12, -1, -1, io=[(PSIZE_ADDR, 16)], note='fig-5-9',
                    setup=['MOVI 0x%08X, B1, L' % DATA_BASE, 'MOVI 0x%08X, B8, L' % (DATA_BASE + 0x1000),
                           'MOVI 16, B0, L', 'MOVK 9, B11']))
    # MMTM / MMFM with the pointer not aligned (12-95, 12-97).
    sp = STACK_TOP + 8
    for n, regs in ((1, 'A0'), (4, 'A0, A1, A2, A3')):
        out.append(Case('MMTM %d regs nonaligned' % n, '12-112',
                        ['M: MMTM SP, %s' % regs, 'MN: NOP'] + ['NOP'] * 16 + ['MMFM SP, %s' % regs],
                        2 + 10 * n, 8, 10 * (n + 1), sp=sp, note='mmtm-nonaligned'))
        out.append(Case('MMFM %d regs nonaligned' % n, '12-110',
                        ['MMTM SP, %s' % regs] + ['NOP'] * 16 + ['M: MMFM SP, %s' % regs, 'MN: NOP'],
                        3 + 6 * n, 4, 13 + 6 * n, sp=sp, note='mmfm-hidden'))
    # Divide special cases (12-50, 12-52, 12-98, 12-99).
    out += [
        Case('DIVS result 80000000', '12-63', 'DIVS A2, A0', 41, 0, 44,
             setup=['MOVI 0, A0', 'MOVI 0x80000000, A1, L', 'MOVI -1, A2']),
        Case('DIVS overflow', '12-63', 'DIVS A2, A0', 7, 0, 10,
             setup=['MOVI 0x10, A0', 'MOVI 0, A1', 'MOVI 1, A2']),
        Case('DIVU overflow', '12-65', 'DIVU A2, A0', 5, 0, 8,
             setup=['MOVI 0x10, A0', 'MOVI 0, A1', 'MOVI 1, A2']),
        Case('MODS result 80000000', '12-113', 'MODS A2, A1', 41, 0, 44,
             setup=['MOVI 0x80000000, A1, L', 'MOVI -1, A2']),
        Case('MODS Rs=0', '12-113', 'MODS A2, A1', 3, 0, 6, setup=['MOVI 1000, A1', 'MOVI 0, A2']),
        Case('MODU Rs=0', '12-114', 'MODU A2, A1', 3, 0, 6, setup=['MOVI 1000, A1', 'MOVI 0, A2']),
    ]
    return out


def window_cases():
    """Window checking (CONTROL.W, 7.10) on PIXT XY stores and transfers and
    DRAV, Replace, PSIZE 16. "Window Violation" columns of 12-194, 12-203
    and 12-56 when the pixel is not drawn; the Replace figure when it is."""
    out = []
    io = [(PSIZE_ADDR, 16), (CONVDP_ADDR, 19), (CONVSP_ADDR, 19)]
    base = ['MOVI 0x00001000, B1, L', 'MOVI 0x00001000, B3, L',
            'MOVI 0x%08X, B4, L' % DATA_BASE, 'MOVI 0x12345678, B9, L',
            'MOVI 0x0000ABCD, A0, L', 'MOVI 0x00020003, A2, L',
            'MOVI 0x00040005, A4, L', 'MOVI 0x00010001, A5, L']
    win = {'in': ['MOVI 0, B5, L', 'MOVI 0x00100010, B6, L'],
           'out': ['MOVI 0x00080008, B5, L', 'MOVI 0x00100010, B6, L']}
    forms = [  # name, page, test, drawn (hit, hidden, off), not drawn {W: (hit, off)}
        ('PIXT Rs,*Rd.XY', '12-216', 'PIXT A0, *A2.XY', (4, 1, 8), {1: (6, 9), 2: (6, 9), 3: (4, 7)}),
        ('PIXT *Rs.XY,*Rd.XY', '12-225', 'PIXT *A2.XY, *A4.XY', (7, 1, 11), {2: (8, 11), 3: (6, 9)}),
        ('DRAV', '12-68', 'DRAV A5, A2', (4, 1, 8), {1: (5, 8), 2: (3, 6), 3: (5, 8)}),
    ]
    for name, page, test, drawn, nodraw in forms:
        for w in (1, 2, 3):
            for where in ('in', 'out'):
                if w == 1 or where == 'out':
                    if w not in nodraw:
                        continue                  # not printed (PIXT XY,XY W=1)
                    hit, dis = nodraw[w]
                    hid = 0
                else:
                    hit, hid, dis = drawn
                out.append(Case('%s W=%d pixel %s' % (name, w, where), page, test, hit, hid, dis,
                                io=io, ctrl=w << 6, setup=base + win[where]))
    return out


PMASK_ADDR = 0xC000_0160
CTRL_T = 1 << 5


def graphics_op_cases():
    """Transparency and plane masking on PIXT, DRAV and LINE. The memory
    controller applies them inside the write, a read-modify-write of each
    word (13.3.2.5, Table 13-7; 12-102: "already included" for LINE). At
    PSIZE < 16 the write is a read-modify-write anyway, so the printed
    figures hold. At PSIZE 16 the guide prints no figure with T or PMASK;
    the expectation is the Replace figure with the write's one cycle
    replaced by a read-modify-write: (1) becomes (3), the same as at
    PSIZE < 16 (page names "13.3.2.5" mark these)."""
    out = []
    pix = ['MOVI 0x0000ABCD, A0, L', 'MOVI 0x%08X, A1, L' % DATA_BASE,
           'MOVI 0x%08X, A3, L' % (DATA_BASE + 0x100)]
    drav = ['MOVI 0x00001000, B3, L', 'MOVI 0x%08X, B4, L' % DATA_BASE,
            'MOVI 0x12345678, B9, L', 'MOVI 0x00020003, A2, L', 'MOVI 0x00010001, A5, L']
    for psize in (8, 16):
        page = '12-214' if psize < 16 else '12-214 13.3.2.5'
        dpage = '12-68' if psize < 16 else '12-68 13.3.2.5'
        for opt, ctrl, io in (('T', CTRL_T, []), ('PMASK', 0, [(PMASK_ADDR, 0x0F0F)])):
            io = [(PSIZE_ADDR, psize), (CONVDP_ADDR, 19)] + io
            out.append(Case('PIXT Rs,*Rd Replace %s psize%d' % (opt, psize), page, 'PIXT A0, *A1',
                            2, 3, 8, io=io, ctrl=ctrl, setup=pix))
            out.append(Case('PIXT *Rs,*Rd Replace %s psize%d' % (opt, psize), page.replace('214', '221'),
                            'PIXT *A1, *A3', 4, 3, 10, io=io, ctrl=ctrl, setup=pix))
            out.append(Case('PIXT *Rs,*Rd AND %s psize%d' % (opt, psize), page.replace('214', '221'),
                            'PIXT *A1, *A3', 6, 3, 12, io=io, ctrl=ctrl | (0b00001 << 10), setup=pix))
            out.append(Case('DRAV Replace %s psize%d' % (opt, psize), dpage, 'DRAV A5, A2',
                            4, 3, 10, io=io, ctrl=ctrl, setup=drav))
    return out


def cache_miss_cases():
    """5.4.7: a cache miss takes 8 states to load the 4-word subsegment, plus
    1 to start the instruction: 9 states for four single-word instructions
    (2.25 each). The loop flushes the cache (HSTCTL CF, 5.4.5) before its
    drain NOPs; four NOPs are measured from the last word of one subsegment,
    so the second one's fetch misses: 4 + 9 = 13 (the +1 lies after the miss,
    in the span). Cache disabled: 4 x 4."""
    flush = ['MOVI 0xC0000100, A9, L', 'MOVI 0x4000, A8', 'MOVE A8, *A9, 0',
             'CLR A8', 'MOVE A8, *A9, 0']
    for pad in range(4):
        c = Case('4 NOPs across a cache miss (5.4.7)', '5-24 5.4.7', ['NOP'] * 4, 13, 0, 16,
                 setup=flush + ['NOP'] * pad)
        _, labels = c.program(0)
        if (labels['T'] // 16) % 4 == 3:          # (cache off: no miss to place)
            return [c]
    raise AssertionError('no padding puts the NOP at the end of a subsegment')


def all_cases():
    return (general_cases() + move_cases() + pixel_cases() + m2m_cases()
            + stack_nonaligned_cases() + fill_cases() + trap_cases() + srt_cases()
            + line_cases() + extra_cases() + review_cases() + window_cases()
            + graphics_op_cases() + line_window_cases() + pblt_cases() + pblt_xy_cases()
            + pblt_expand_cases() + pblt_more_cases() + cache_miss_cases())


def interrupt_variant(case):
    """The case with INT1 enabled and a handler that runs some NOPs and
    returns (tb_accuracy +INTAT pulls LINT1 during the measured pass)."""
    vec = 0xFFFF_FFC0                                   # INT1 (trap 1)
    c = Case(case.name + ' INT', case.page, case.test, -1, -1, -1, setup=case.setup,
             sub=case.sub + ['IH: ADDK 1, A3'] + ['NOP'] * 7 + ['RETI'], sp=case.sp,
             io=case.io, ctrl=case.ctrl, note=case.note)
    c.setup = ['SETF 32, 0, 0', 'MOVI IH, A0, L', 'MOVE A0, @0x%08X, 0' % vec,
               'MOVI 0x%08X, A0, L' % 0xC0000110, 'MOVI 2, A1', 'MOVE A1, *A0, 0',
               'SETF 16, 0, 0', 'EINT'] + c.setup
    return c


def main():
    global CTRL_RR
    cases = all_cases()
    if len(sys.argv) > 2 and sys.argv[2] == 'screen':
        # Every case with internal video timing running and automatic screen
        # refresh on (DPYCTL SRE, every line): a 256-clock line (32 states at
        # 8 clocks per state with VCLK = the core clock, as tb_accuracy has
        # it), 32 lines a frame. Screen-refresh cycles then fall among the
        # CPU's at every phase. I/O registers: 9.2, Figure 6-1.
        global SCREEN_IO
        io = lambda idx: 0xC000_0000 + (idx << 4)
        SCREEN_IO = [(io(0x00), 2), (io(0x01), 8), (io(0x02), 248), (io(0x03), 255),
                     (io(0x04), 1), (io(0x05), 2), (io(0x06), 30), (io(0x07), 31),
                     (io(0x09), 0x0120 << 2), (io(0x1B), 0),
                     (io(0x08), (1 << 14) | (1 << 13) | (1 << 12) | (1 << 2))]
    if len(sys.argv) > 2 and sys.argv[2] == 'refresh':
        # Every case with DRAM refresh at the fastest rate (RR=00, page 6-14),
        # for comparing two versions with refresh cycles among the CPU's.
        CTRL_RR = 0
    if len(sys.argv) > 2 and sys.argv[2] == 'int':
        # Optional third argument: comma-separated name prefixes
        # (default FILL,PIXBLT; e.g. LINE,PIXT,DRAV for the single-pixel path).
        kinds = tuple(sys.argv[3].split(',')) if len(sys.argv) > 3 else ('FILL', 'PIXBLT')
        cases = [interrupt_variant(c) for c in cases if c.name.startswith(kinds)]
    out = []
    n = 0
    for case in cases:
        for cd in (0, 1):
            words, labels = case.program(cd)
            # The measured pass must run from the 128-word instruction cache
            # (4 segments of 32 words, 5.4.1).
            loop_words = (labels['DONE'] - labels['LOOP']) // 16
            assert loop_words <= 128, ('loop larger than the cache', case.name, loop_words)
            # For two-instruction cases the measured instruction is the
            # second one when the name says so (RETS, POPST, MMFM).
            t, nx = labels['T'], labels['N']
            if 'M' in labels:
                t = labels['M']
                nx = labels['MN'] if 'MN' in labels else labels['S'] if 'S' in labels else labels['H']
            exp = case.dis if cd else case.hit
            hid = 0 if cd else case.hidden
            out.append('case %d %s %s %d %d %d %08X %08X %08X %08X %d %08X' % (
                n, case.name.replace(' ', '_').replace(',', '_'), case.page.replace(' ', '_'),
                cd, exp, hid, t, nx, labels['DONE'], case.sp, len(words), CODE_BASE))
            out += ['%04X' % w for w in words]
            n += 1
    with open(sys.argv[1], 'w') as f:
        f.write('\n'.join(out) + '\nend\n')
    print('%d runs written to %s' % (n, sys.argv[1]))


if __name__ == '__main__':
    main()
