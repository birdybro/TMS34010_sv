#!/usr/bin/env python3
"""Turn tb_accuracy RUN lines into a markdown table.

Every expectation is the figure printed in the guide. A case whose printed
figure the model is known not to give carries a note naming the entry in
docs/cycle_accuracy.md ("Where the guide disagrees with itself"); it is
counted as explained, not as a match.

Usage: report.py <accuracy.log> [clks_per_state]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cases as case_defs                                         # noqa: E402

CPS = int(sys.argv[2]) if len(sys.argv) > 2 else 8
notes = {c.name.replace(' ', '_').replace(',', '_'): c.note for c in case_defs.all_cases()}

rows = {}
for line in open(sys.argv[1]):
    p = line.split()
    if not p or p[0] != 'RUN':
        continue
    _, rid, name, page, cd, exp, hid = p[:7]
    r = rows.setdefault(name, {'page': page})
    key = 'dis' if cd == '1' else 'hit'
    r[key + '_exp'] = int(exp)
    r[key + '_hid'] = int(hid)
    r[key + '_got'] = p[7] if p[7] == 'TIMEOUT' else int(p[7])
    r[key + '_gothid'] = None if p[7] == 'TIMEOUT' else int(p[8])


def st(clocks):
    return '%g' % round(clocks / CPS, 2)


def verdict(ok, note):
    if ok:
        return 'ok'
    return ('guide: ' + note) if note else '**DIFFERS**'


count = {'hit': [0, 0, 0], 'hid': [0, 0, 0], 'dis': [0, 0, 0]}   # ok, explained, unexplained
na_dis = 0
print('| Instruction | Guide page | Guide hit+(hidden) | Core | Hit | Hidden | Guide cache-off | Core | Off |')
print('|---|---|---|---|---|---|---|---|---|')
for name, r in rows.items():
    note = notes.get(name, '')
    out = {}
    for key in ('hit', 'dis'):
        got, exp = r.get(key + '_got'), r.get(key + '_exp')
        if got is None:
            out[key] = ('-', None)
        elif got == 'TIMEOUT':
            out[key] = ('TIMEOUT', False)
        elif exp is not None and exp < 0:
            out[key] = (st(got), None)
        else:
            out[key] = (st(got), got == exp * CPS)
    gh = r.get('hit_gothid')
    hid_ok = None if (gh is None or r.get('hit_hid', 0) < 0) else (gh == r['hit_hid'] * CPS)
    cells = []
    for key, ok in (('hit', out['hit'][1]), ('hid', hid_ok), ('dis', out['dis'][1])):
        if ok is None:
            cells.append('-')
            if key == 'dis':
                na_dis += 1
            continue
        count[key][0 if ok else 1 if note else 2] += 1
        cells.append(verdict(ok, note))
    eh = r.get('hit_hid', 0)
    exp_h = '%d' % r.get('hit_exp', 0) + ('+(%d)' % eh if eh > 0 else '+(not given)' if eh < 0 else '')
    core_h = out['hit'][0] + ('+(%s)' % st(gh) if gh else '')
    de = r.get('dis_exp', 0)
    print('| %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
        name.replace('_', ' '), r['page'].replace('_', ' '), exp_h, core_h, cells[0], cells[1],
        'not given' if de < 0 else str(de), out['dis'][0], cells[2]))
print()
for key, label in (('hit', 'cache-hit states'), ('hid', 'hidden states'), ('dis', 'cache-off states')):
    ok, ex, un = count[key]
    print('%s: %d match the printed figure, %d differ where the guide disagrees with itself '
          '(noted), %d differ unexplained, of %d.' % (label, ok, ex, un, ok + ex + un))
print('cache-off: %d cases have no printed figure.' % na_dis)
