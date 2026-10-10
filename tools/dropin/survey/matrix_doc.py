#!/usr/bin/env python3
"""Write the survey matrix as a Markdown page (docs/game_survey_matrix.md in the drop-in tree)."""
import json, os, sys
from collections import OrderedDict
HERE = os.path.dirname(os.path.abspath(__file__))
m = json.load(open(os.path.join(HERE, 'matrix.json')))
import matrix as M
fams = [f for f in M.FAMILY if f in m['cpus'].values()]
n = {f: sum(1 for v in m['cpus'].values() if v == f) for f in fams}
def table(rows, title):
    out = [f'### {title}', '', '| | ' + ' | '.join(f'{f} ({n[f]})' for f in fams) + ' | all |',
           '|---|' + '---|' * (len(fams) + 1)]
    for r in rows:
        cells = [str(len(m['rows'][r].get(f, []))) if m['rows'][r].get(f) else '' for f in fams]
        out.append(f'| {r} | ' + ' | '.join(cells) + f' | {sum(len(v) for v in m["rows"][r].values())} |')
    return out + ['']
rows = sorted(m['rows'], key=lambda r: (-sum(len(v) for v in m['rows'][r].values()), r))
instr = [r for r in rows if r.startswith('instr: ')]
gfx = [r for r in rows if r.startswith(('graphics:', 'pixel op', 'transparency', 'window', 'pixel size', 'PIXBLT/FILL'))]
ints = [r for r in rows if r.startswith('interrupt')]
host = [r for r in rows if 'host' in r.lower() or r.startswith('HSTCTLH')]
video = [r for r in rows if r.startswith(('SRT', 'external', 'interlaced', 'HSD', 'screen origin', 'DUDATE', 'refresh', 'CAS', 'instruction cache'))]
reads = [r for r in rows if r.startswith('34010 reads')]
out = ['# Game survey matrix', '',
       'Generated from the counting-MAME runs (`game_survey.md`, 0.2). Each cell: how many of that family\'s surveyed',
       '34010s use the item at least once in 5 minutes of attract mode and random play. Families with a host CPU list',
       'only the 34010s.', '']
out += table(gfx, 'Graphics instructions and pixel processing (pixel-writing instructions only)')
out += table(ints, 'Interrupts')
out += table(host, 'Host interface (from the host side, and HSTCTL bits the 34010 writes)')
out += table(video, 'Video, VRAM, refresh, cache')
out += table(reads, 'I/O registers the 34010 reads')
out += table([r.replace('instr: ', '') and r for r in instr], 'Instruction forms executed')
out += ['Instruction forms no surveyed game executed: ' + ', '.join(m['unused_forms']), '']
open(sys.argv[1], 'w').write('\n'.join(out).replace('| instr: ', '| '))
print('written', sys.argv[1])
