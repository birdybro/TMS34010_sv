#!/usr/bin/env python3
"""0.3: games x chip-features matrix from survey.json -> matrix.md (+ matrix.json)."""
import json, os, re
from collections import defaultdict, OrderedDict

HERE = os.path.dirname(os.path.abspath(__file__))
S = json.load(open(os.path.join(HERE, 'survey.json')))

FAMILY = OrderedDict([
    ('Z/Y-unit', 'narc trog smashtv hiimpact shimpact strkforc term2 mkla4 totcarn'),
    ('T-unit', 'mk mk2 jdreddp nbajam nbajamte'),
    ('W-unit', 'mk3 umk3 wwfmania openice nbahangt rmpgwt'),
    ('Atari GSP', 'harddriv harddrivc racedriv racedrivc stunrun steeltal hdrivair strtdriv'),
    ('Atari MSP', ''),
    ('Exterminator', 'exterm'),
    ('ICE', 'lethalj eggventr ripribit cfarm cclownz'),
    ('Cool Pool', 'amerdart coolpool 9ballsht'),
    ('Tickee', 'tickee ghoshunt tutstomb mouseatk rapidfir maletmad'),
    ('Skimaxx', 'skimaxx'),
    ('X the Ball', 'xtheball'),
    ('Micro3D', 'f15se botss tankbatl'),
    ('JPM Impact', 'cluedo trivialp scrabble'),
    ('Art & Magic', 'ultennis cheesech stonebal'),
    ('Inder', 'megaphx hamboy littlerb'),
])


def family(cpu):
    st = cpu.split()[0]
    if '[' in cpu and 'msp' in cpu:
        return 'Atari MSP'
    for f, sets in FAMILY.items():
        if st in sets.split():
            return f
    return 'other'


def feats(s):
    """Feature -> True for one CPU."""
    f = set()
    for k, n in s['forms'].items():
        if n:
            f.add('instr: ' + k)
    for op, g in s['gfx'].items():
        if not op.startswith(('PIXBLT', 'FILL', 'LINE', 'PIXT', 'DRAV')):
            continue                       # XY arithmetic, CPW, CVXYL, MOVX/MOVY: no pixel write
        f.add(f'graphics: {op}')
        for p in g['ppop']:
            f.add(f'pixel op in {op.split()[0]}: {p}')
        fl = 0
        for x in g.get('flags', []):
            fl |= x
        if op.endswith(('L', 'L,L')) and op.startswith(('FILL L', 'PIXBLT')) and op.split()[-1].endswith('L') and fl & 1:
            f.add('linear destination not pixel-aligned (C17)')
        if op.startswith('PIXBLT B') and fl & 2:
            f.add('expand row wider than 32 pixels (C15)')
        if op.startswith('PIXBLT L') and fl & 4:
            f.add('linear source not pixel-aligned')
        if op.startswith('PIXBLT') and fl & 2:
            f.add(f'PIXBLT row wider than 32 pixels: {op}')
        for p in g['ppop']:
            f.add(f'pixel op: {p}')
        if 1 in g['T']:
            f.add('transparency (T=1) in a graphics instruction')
        for w in g['W']:
            if w:
                f.add(f'window mode W={w}')
        if 1 in g['PBH']:
            f.add('PIXBLT/FILL direction PBH=1')
        if 1 in g['PBV']:
            f.add('PIXBLT/FILL direction PBV=1')
        for p in g['psize']:
            f.add(f'pixel size {p} during graphics instructions')
    d = s['dpyctl']
    if 0 in d.get('NIL', []) and 1 in d.get('ENV', []):
        f.add('interlaced video (NIL=0) written')
    if 0 in d.get('DXV', []):
        f.add('external sync (DXV=0) written')
    if 1 in d.get('HSD', []):
        f.add('HSD=1 written')
    if 1 in d.get('ORG', []):
        f.add('screen origin ORG=1')
    if 1 in d.get('SRT', []):
        f.add('SRT=1 (VRAM shift-register transfers)')
    for v in d.get('DUDATE', []):
        f.add(f'DUDATE={v}')
    c = s['control']
    if 1 in c.get('CD', []):
        f.add('instruction cache disabled (CD=1)')
    for v in c.get('RR', []):
        f.add(f'refresh rate RR={v}')
    if 1 in c.get('RM', []):
        f.add('CAS-before-RAS refresh (RM=1)')
    for k, v in s['intenb'].items():
        if 1 in v:
            f.add(f'interrupt enabled: {k}')
    for k, v in s['ints'].items():
        if v:
            f.add(f'interrupt taken: {k}')
    for k, v in s['hstctlh'].items():
        if 1 in v:
            f.add(f'HSTCTLH {k}=1 written by the 34010')
    if s['pmask_nonzero']:
        f.add('plane mask (PMASK != 0)')
    for k in s['hostw']:
        r, v = k.split(':')
        f.add({'0': 'host writes HSTADRL', '1': 'host writes HSTADRH', '2': 'host writes HSTDATA',
               '3': 'host writes HSTCTL'}.get(r, 'host write ' + r))
        if r == '3':
            v = int(v, 16)
            for bit, nm in ((15, 'HLT'), (8, 'NMI'), (9, 'NMIM'), (11, 'INCW'), (12, 'INCR'), (13, 'LBL'),
                            (14, 'CF'), (7, 'INTOUT'), (3, 'INTIN')):
                if v >> bit & 1:
                    f.add(f'host sets {nm} in HSTCTL')
    for r in s['hostr']:
        f.add({0: 'host reads HSTADRL', 1: 'host reads HSTADRH', 2: 'host reads HSTDATA',
               3: 'host reads HSTCTL'}.get(int(r), 'host read'))
    for r, n in s['ior'].items():
        if r in ('HCOUNT', 'VCOUNT', 'DPYADR', 'REFCNT', 'DPYTAP', 'INTPEND', 'HSTCTLL', 'HSTCTLH', 'HSTDATA',
                 'DPYCTL', 'CONTROL', 'INTENB'):
            f.add(f'34010 reads {r}')
    return f


def main():
    rows = defaultdict(lambda: defaultdict(list))
    cpus = {}
    for cpu, s in S.items():
        fam = family(cpu)
        cpus[cpu] = fam
        for x in feats(s):
            rows[x][fam].append(cpu.split()[0] + (' ' + cpu.split()[1] if len(cpu.split()) > 1 else ''))
    fams = [f for f in FAMILY if any(v == f for v in cpus.values())] + (['other'] if 'other' in cpus.values() else [])
    nfam = {f: sum(1 for v in cpus.values() if v == f) for f in fams}
    out = ['| Feature | ' + ' | '.join(f'{f} ({nfam[f]})' for f in fams) + ' | CPUs |',
           '|---|' + '---|' * len(fams) + '---|']
    def key(r):
        grp = r.split(':')[0]
        return (grp, -sum(len(v) for v in rows[r].values()), r)
    for r in sorted(rows, key=key):
        tot = sum(len(v) for v in rows[r].values())
        out.append(f'| {r} | ' + ' | '.join(str(len(rows[r][f])) if rows[r][f] else '' for f in fams) + f' | {tot} |')
    # instruction forms nobody used
    names = open(os.path.join(HERE, 'mame_op_names.txt')).read().split()
    import analyze
    allforms = sorted({analyze.form(i << 4) for i in range(4096)} | {analyze.form((i << 4) | 0xf) for i in range(4096)})
    unused = [x for x in allforms if 'instr: ' + x not in rows]
    open(os.path.join(HERE, 'matrix.md'), 'w').write('\n'.join(out) + '\n\nInstruction forms no surveyed game executed: '
                                                    + ', '.join(unused) + '\n')
    json.dump({'rows': {r: dict(v) for r, v in rows.items()}, 'cpus': cpus, 'unused_forms': unused},
              open(os.path.join(HERE, 'matrix.json'), 'w'), indent=1)
    print(len(cpus), 'CPUs', len(rows), 'features;', len(unused), 'unused forms')


if __name__ == '__main__':
    main()
