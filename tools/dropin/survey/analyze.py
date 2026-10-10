#!/usr/bin/env python3
"""Game survey analysis: turns the counting-MAME dumps (runs/<set>/tmscov_*.txt) into
per-game facts and a games x chip-features matrix. Instruction names follow the 1988 guide's
summary (12.3); MAME's handler names are only used to group opcodes."""
import glob, json, os, re, sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = open(os.path.join(HERE, 'mame_op_names.txt')).read().split()

IOREG = ["HESYNC", "HEBLNK", "HSBLNK", "HTOTAL", "VESYNC", "VEBLNK", "VSBLNK", "VTOTAL",
         "DPYCTL", "DPYSTRT", "DPYINT", "CONTROL", "HSTDATA", "HSTADRL", "HSTADRH", "HSTCTLL",
         "HSTCTLH", "INTENB", "INTPEND", "CONVSP", "CONVDP", "PSIZE", "PMASK", "RES23",
         "RES24", "RES25", "RES26", "DPYTAP", "HCOUNT", "VCOUNT", "DPYADR", "REFCNT"]
PPOP = {0: "replace", 1: "AND", 2: "AND NOT S", 3: "zero", 4: "OR NOT S", 5: "XNOR", 6: "NOT D",
        7: "NOR", 8: "OR", 9: "D", 10: "XOR", 11: "NOT S AND D", 12: "ones", 13: "NOT S OR D",
        14: "NAND", 15: "NOT S", 16: "ADD", 17: "ADDS", 18: "SUB", 19: "SUBS", 20: "MAX", 21: "MIN"}
INTV = {"INT_fffffec0": "HI (host)", "INT_fffffea0": "DI (display)", "INT_fffffe80": "WV (window)",
        "INT_ffffffc0": "INT1", "INT_ffffffa0": "INT2", "NMI": "NMI", "NMI_nosave": "NMI (NMIM=1)"}

MOVE_FORM = {
    'rr': 'Rs,Rd', 'rn': 'Rs,*Rd', 'nr': '*Rs,Rd', 'nn': '*Rs,*Rd', 'r_ni': 'Rs,*Rd+', 'ni_r': '*Rs+,Rd',
    'ni_ni': '*Rs+,*Rd+', 'r_dn': 'Rs,-*Rd', 'dn_r': '-*Rs,Rd', 'dn_dn': '-*Rs,-*Rd', 'r_no': 'Rs,*Rd(n)',
    'no_r': '*Rs(n),Rd', 'no_no': '*Rs(n),*Rd(n)', 'no_ni': '*Rs(n),*Rd+', 'ra': 'Rs,@L', 'ar': '@L,Rd',
    'aa': '@L,@L', 'a_ni': '@L,*Rd+'}


def form(op):
    """Guide-style instruction form for one opcode word."""
    n = NAMES[op >> 4]
    m = re.match(r'(move|movb)([01]?)_(.*?)(_a|_b)?$', n)
    if m and m.group(1) in ('move', 'movb') and n not in ('move_rr_a', 'move_rr_b', 'move_rr_ax', 'move_rr_bx'):
        mn = 'MOVE' if m.group(1) == 'move' else 'MOVB'
        f = ',F' if mn == 'MOVE' else ''
        return f"{mn} {MOVE_FORM.get(m.group(3), m.group(3))}{f}"
    if n.startswith('move_rr'):
        return 'MOVE Rs,Rd' + (' (other file)' if n.endswith('x') else '')
    m = re.match(r'j_([A-Z]+)_(0|8|x)$', n)
    if m:
        cc = m.group(1)
        kind = {'x': 'JRcc short', '0': 'JRcc long', '8': 'JAcc'}[m.group(2)]
        return f"{kind}" + ('' if cc != 'UC' else ' (UC)')
    n2 = re.sub(r'_(a|b)$', '', n)
    special = {
        'pixblt_b_l': 'PIXBLT B,L', 'pixblt_b_xy': 'PIXBLT B,XY', 'pixblt_l_l': 'PIXBLT L,L',
        'pixblt_l_xy': 'PIXBLT L,XY', 'pixblt_xy_l': 'PIXBLT XY,L', 'pixblt_xy_xy': 'PIXBLT XY,XY',
        'fill_l': 'FILL L', 'fill_xy': 'FILL XY', 'line': 'LINE',
        'pixt_ii': 'PIXT *Rs,*Rd', 'pixt_ir': 'PIXT *Rs,Rd', 'pixt_ixyixy': 'PIXT *Rs.XY,*Rd.XY',
        'pixt_ixyr': 'PIXT *Rs.XY,Rd', 'pixt_ri': 'PIXT Rs,*Rd', 'pixt_rixy': 'PIXT Rs,*Rd.XY',
        'add_xy': 'ADDXY', 'sub_xy': 'SUBXY', 'cmp_xy': 'CMPXY',
        'addi_w': 'ADDI IW', 'addi_l': 'ADDI IL', 'cmpi_w': 'CMPI IW', 'cmpi_l': 'CMPI IL',
        'subi_w': 'SUBI IW', 'subi_l': 'SUBI IL', 'movi_w': 'MOVI IW', 'movi_l': 'MOVI IL',
        'btst_k': 'BTST K', 'btst_r': 'BTST Rs', 'rl_k': 'RL K', 'rl_r': 'RL Rs', 'sla_k': 'SLA K',
        'sla_r': 'SLA Rs', 'sll_k': 'SLL K', 'sll_r': 'SLL Rs', 'sra_k': 'SRA K', 'sra_r': 'SRA Rs',
        'srl_k': 'SRL K', 'srl_r': 'SRL Rs', 'exgf0': 'EXGF F=0', 'exgf1': 'EXGF F=1',
        'setf0': 'SETF F=0', 'setf1': 'SETF F=1', 'sext0': 'SEXT F=0', 'sext1': 'SEXT F=1',
        'zext0': 'ZEXT F=0', 'zext1': 'ZEXT F=1', 'call': 'CALL Rs', 'jump': 'JUMP Rs',
        'unimpl': 'ILLEGAL (unimplemented code)', 'illop': 'ILLEGAL (illop)', 'callr': 'CALLR', 'calla': 'CALLA',
    }
    if n2 in special:
        return special[n2]
    return n2.upper()


def load(path):
    d = {'op': {}, 'gfx': [], 'iow': defaultdict(dict), 'ior': {}, 'ev': {}, 'hostw': {}, 'hostr': {}}
    for line in open(path):
        p = line.split()
        if not p or p[0] == '#':
            continue
        if p[0] == 'OP':
            d['op'][int(p[1], 16)] = (int(p[2]), int(p[3], 16))
        elif p[0] == 'GFX':
            d['gfx'].append(tuple(int(x, 16) for x in p[1:5]) + (int(p[5]),))
        elif p[0] == 'IOW':
            d['iow'][int(p[1], 16)][int(p[2], 16)] = int(p[3])
        elif p[0] == 'IOR':
            d['ior'][int(p[1], 16)] = int(p[2])
        elif p[0] == 'EV':
            d['ev'][p[1]] = int(p[2])
        elif p[0] == 'HOSTW':
            d['hostw'][(int(p[1]), int(p[2], 16))] = int(p[3])
        elif p[0] == 'HOSTR':
            d['hostr'][int(p[1])] = int(p[2])
    return d


def summarise(d):
    s = {}
    forms = defaultdict(int)
    for op, (c, pc) in d['op'].items():
        forms[form(op)] += c
    s['forms'] = dict(forms)
    s['instructions'] = sum(c for c, _ in d['op'].values())
    g = defaultdict(lambda: {'n': 0, 'ppop': set(), 'T': set(), 'W': set(), 'PBH': set(), 'PBV': set(),
                             'psize': set(), 'flags': set()})
    for op, ctl, psz, fl, c in d['gfx']:
        e = g[form(op)]
        e['n'] += c
        e['ppop'].add(PPOP.get((ctl >> 10) & 31, f"reserved {(ctl >> 10) & 31}"))
        e['T'].add((ctl >> 5) & 1)
        e['W'].add((ctl >> 6) & 3)
        e['PBH'].add((ctl >> 8) & 1)
        e['PBV'].add((ctl >> 9) & 1)
        e['psize'].add(psz)
        e['flags'].add(fl)                 # 1: DADDR % PSIZE, 2: DX > 32, 4: SADDR % PSIZE
    s['gfx'] = {k: {kk: (sorted(vv) if isinstance(vv, set) else vv) for kk, vv in v.items()} for k, v in g.items()}
    iow = {}
    for r, vals in d['iow'].items():
        iow[IOREG[r]] = {f"{v:04x}": c for v, c in sorted(vals.items())}
    s['iow'] = iow
    s['ior'] = {IOREG[r]: c for r, c in d['ior'].items()}
    s['ints'] = {INTV.get(k, k): v for k, v in d['ev'].items()}
    s['hostw'] = {f"{r}:{v:04x}": c for (r, v), c in d['hostw'].items()}
    s['hostr'] = d['hostr']
    # decoded register bits ever set
    def bits(reg, fields):
        out = {}
        for v in d['iow'].get(IOREG.index(reg), {}):
            for name, (lo, w) in fields.items():
                out.setdefault(name, set()).add((v >> lo) & ((1 << w) - 1))
        return {k: sorted(v) for k, v in out.items()}
    s['dpyctl'] = bits('DPYCTL', {'ENV': (15, 1), 'NIL': (14, 1), 'DXV': (13, 1), 'SRE': (12, 1), 'SRT': (11, 1),
                                  'ORG': (10, 1), 'DUDATE': (2, 8), 'HSD': (0, 1)})
    s['control'] = bits('CONTROL', {'CD': (15, 1), 'PPOP': (10, 5), 'PBV': (9, 1), 'PBH': (8, 1), 'W': (6, 2),
                                    'T': (5, 1), 'RR': (3, 2), 'RM': (2, 1)})
    s['intenb'] = bits('INTENB', {'WVE': (11, 1), 'DIE': (10, 1), 'HIE': (9, 1), 'X2E': (2, 1), 'X1E': (1, 1)})
    s['hstctlh'] = bits('HSTCTLH', {'HLT': (15, 1), 'CF': (14, 1), 'LBL': (13, 1), 'INCR': (12, 1),
                                    'INCW': (11, 1), 'NMIM': (9, 1), 'NMI': (8, 1)})
    s['psize'] = sorted(int(v, 16) for v in iow.get('PSIZE', {}))
    s['pmask_nonzero'] = any(int(v, 16) != 0 for v in iow.get('PMASK', {}))
    return s


def main():
    runs = sorted(glob.glob(os.path.join(HERE, os.environ.get('RUNS', 'runs'), '*', 'tmscov*.txt')))
    out = {}
    for p in runs:
        st = os.path.basename(os.path.dirname(p))
        tag = os.path.basename(p)[len('tmscov'):-4].strip('_').replace('_', ':')
        d = load(p)
        if not d['op']:
            continue
        out[f"{st}{'' if tag == 'maincpu' else ' [' + tag + ']'}"] = summarise(d)
    json.dump(out, open(os.path.join(HERE, 'survey.json'), 'w'), indent=1, default=list)
    print(f"{len(out)} CPUs from {len(runs)} dumps -> survey.json")


if __name__ == '__main__':
    main()
