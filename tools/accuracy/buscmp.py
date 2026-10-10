#!/usr/bin/env python3
"""Compare two tb_accuracy logs made with +BUSLOG, run by run.

Usage: buscmp.py NEW.log REF.log
Prints how many runs differ in their RUN line (registers, memory, clocks) and
in their external bus cycles (kind, address, data, start clock). Exit 1 if
anything differs.
"""
import collections
import re
import sys

BUS = re.compile(r'BUS c=(\d+) k=(\d+) a=(\w+) w=(\w+)')


def load(path):
    runs, buf = {}, []
    for line in open(path):
        m = BUS.match(line)
        if m:
            buf.append((int(m[1]), m[2], m[3], m[4]))
        elif line.startswith('RUN'):
            runs[' '.join(line.split()[:3])] = (buf, line.strip())
            buf = []
    return runs


def main():
    new, ref = load(sys.argv[1]), load(sys.argv[2])
    if not new or not ref:
        print(f'no runs: {len(new)} new, {len(ref)} ref')
        return 1
    if new.keys() != ref.keys():
        print(f'run lists differ: {len(new)} vs {len(ref)}')
        return 1
    runline, seq, timing = [], [], collections.Counter()
    for k, (bn, ln) in new.items():
        br, lr = ref[k]
        if ln != lr:
            runline.append((k, ln, lr))
        if [x[1:] for x in bn] != [x[1:] for x in br]:
            seq.append(k)
            continue
        for x, y in zip(bn, br):
            if x[0] != y[0]:
                timing[k] += 1
    print(f'runs {len(new)}: RUN line differs {len(runline)}, bus sequence differs '
          f'{len(seq)}, bus timing differs {len(timing)}')
    for k, ln, lr in runline[:5]:
        print(f'  {k}\n    new: {ln}\n    ref: {lr}')
    return 1 if (runline or seq or timing) else 0


if __name__ == '__main__':
    sys.exit(main())
