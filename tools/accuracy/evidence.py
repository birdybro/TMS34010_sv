#!/usr/bin/env python3
"""Numbers for docs/accuracy_evidence.md, from tb_accuracy logs.

Usage: evidence.py <accurate.log> <upstream.log> [<upstream.log> ...] [--json out.json]

<accurate.log>  scripts/accuracy.sh 1 1   (CYCLE_ACCURATE=1, CLKS_PER_STATE=8)
<upstream.log>  scripts/accuracy.sh N 0   (CYCLE_ACCURATE=0: upstream behaviour), one
                per memory speed N; the first one is the one tabulated.

Prints, for both cores, how many measured figures equal the figure printed in
the guide; whether registers and memory agree between the two runs; and, for
the upstream core, the best match count over every clocks-per-state ratio
1..32 at each memory speed (upstream has no defined ratio, so no single
ratio is assumed)."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cases as case_defs                                         # noqa: E402

CPS = 8


def parse(path):
    runs = {}
    for line in open(path):
        p = line.split()
        if not p or p[0] != 'RUN':
            continue
        name, cd, exp, hid = p[2], int(p[4]), int(p[5]), int(p[6])
        clk = None if p[7] == 'TIMEOUT' else int(p[7])
        regs = None if clk is None else ' '.join(p[9:])
        runs[(name, cd)] = dict(page=p[3].replace('_', ' '), exp=exp, hid=hid, clk=clk, regs=regs)
    return runs


def main():
    args = sys.argv[1:]
    out_json = None
    if '--json' in args:
        i = args.index('--json')
        out_json = args[i + 1]
        del args[i:i + 2]
    acc, ups = parse(args[0]), [parse(a) for a in args[1:]]
    up = ups[0]
    names = {c.name.replace(' ', '_').replace(',', '_'): c for c in case_defs.all_cases()}

    rows, same, differ = [], 0, 0
    for (name, cd), a in acc.items():
        u = up.get((name, cd), {})
        if a['regs'] is not None and u.get('regs') is not None:
            if a['regs'] == u['regs']:
                same += 1
            else:
                differ += 1
        c = names.get(name)
        rows.append(dict(name=c.name if c else name, page=a['page'], cache='off' if cd else 'hit',
                         guide=a['exp'], hidden=a['hid'],
                         ours=None if a['clk'] is None else a['clk'] / CPS,
                         upstream=None if u.get('clk') is None else u['clk'] / CPS,
                         note=c.note if c else ''))

    def tally(key, cache):
        t = dict(match=0, noted=0, other=0)
        for r in rows:
            if r['cache'] != cache or r['guide'] < 0 or r[key] is None:
                continue
            if r[key] == r['guide']:
                t['match'] += 1
            elif r['note']:
                t['noted'] += 1
            else:
                t['other'] += 1
        return t

    sweep = []
    for path, runs in zip(args[1:], ups):
        hit = [(r['exp'], r['clk']) for (n, cd), r in runs.items()
               if cd == 0 and r['exp'] >= 0 and r['clk'] is not None]
        per_k = [sum(1 for e, c in hit if c == e * k) for k in range(1, 33)]
        best = max(range(32), key=lambda i: per_k[i])
        sweep.append(dict(log=os.path.basename(path), cases=len(hit), per_k=per_k,
                          best_k=best + 1, best=per_k[best]))

    summary = dict(ours_hit=tally('ours', 'hit'), ours_off=tally('ours', 'off'),
                   upstream_hit=tally('upstream', 'hit'), upstream_off=tally('upstream', 'off'),
                   regs_same=same, regs_differ=differ, sweep=sweep)
    for k in ('ours_hit', 'ours_off', 'upstream_hit', 'upstream_off'):
        print('%-13s %s' % (k, summary[k]))
    print('registers+memory identical in %d of %d runs' % (same, same + differ))
    for s in sweep:
        print('upstream %s: best %d of %d cache-hit figures, at %d clocks per state'
              % (s['log'], s['best'], s['cases'], s['best_k']))
    if out_json:
        json.dump(dict(summary=summary, rows=rows), open(out_json, 'w'))


if __name__ == '__main__':
    main()
