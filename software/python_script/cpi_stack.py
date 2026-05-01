#!/usr/bin/env python3
"""CPI stack breakdown from CV32E40P pipeline_trace.csv.

Categories (priority-ordered, first match wins):
  mem_stall              - data_req asserted but data_gnt not yet returned
  load_use_stall         - id_stage load_stall_o (load-use RAW hazard)
  jr_stall               - id_stage jr_stall_o (jump-register hazard on rs1)
  misaligned_stall       - id_stage misaligned_stall_o (split LSU access)
  branch_penalty         - pc_set due to taken conditional branch (flush)
  jump_redirect          - pc_set due to JAL/JALR/exception (non-branch)
  useful_execution       - is_decoding && id_ready (instruction advanced)
  pipeline_backpressure  - is_decoding but id_ready=0 (downstream not ready)
  ifetch_miss            - IF idle, ID empty, no instruction available
                           (instr_valid_id=0 && (if_busy || perf_imiss))
  fetch_drain            - post-flush refill: instr_valid_id=0 && !if_busy
  other_bubble           - everything else

Usage:
  python3 cpi_stack.py [pipeline_trace.csv]
                       [--annotated OUT.csv]   # default: <input>_classified.csv
                       [--no-annotated]        # skip annotated CSV output
                       [--plot OUT.png]
"""

import argparse
import csv
import os
import sys
from collections import Counter


CATEGORIES = [
    'mem_stall',
    'load_use_stall',
    'jr_stall',
    'misaligned_stall',
    'branch_penalty',
    'jump_redirect',
    'useful_execution',
    'pipeline_backpressure',
    'ifetch_miss',
    'fetch_drain',
    'other_bubble',
]

INT_COLS = (
    'is_decoding', 'id_ready', 'ex_ready',
    'load_stall', 'jr_stall', 'misaligned_stall',
    'branch_dec', 'pc_set',
    'data_req', 'data_gnt', 'data_rvalid',
    'if_busy', 'perf_imiss', 'instr_valid_id',
)


def classify(r):
    if r['data_req'] and not r['data_gnt']:
        return 'mem_stall'
    if r['load_stall']:
        return 'load_use_stall'
    if r['jr_stall']:
        return 'jr_stall'
    if r['misaligned_stall']:
        return 'misaligned_stall'
    if r['pc_set'] and r['branch_dec']:
        return 'branch_penalty'
    if r['pc_set'] and not r['branch_dec']:
        return 'jump_redirect'
    if r['is_decoding'] and r['id_ready']:
        return 'useful_execution'
    if r['is_decoding'] and not r['id_ready']:
        return 'pipeline_backpressure'
    # No instruction in ID this cycle. Split the ex-"other_bubble" further.
    if not r['instr_valid_id']:
        if r['if_busy'] or r['perf_imiss']:
            return 'ifetch_miss'
        return 'fetch_drain'
    return 'other_bubble'


_SIM_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'hardware', 'src', 'simulation')
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv', nargs='?',
                    default=os.path.join(_SIM_DIR, 'pipeline_trace.csv'))
    ap.add_argument('--annotated', default=None,
                    help='Path for annotated CSV (default: <input>_classified.csv)')
    ap.add_argument('--no-annotated', action='store_true',
                    help='Skip writing annotated CSV')
    ap.add_argument('--plot', default=None)
    args = ap.parse_args()

    if args.annotated is None and not args.no_annotated:
        base, ext = os.path.splitext(args.csv)
        args.annotated = f"{base}_classified{ext or '.csv'}"

    counts = Counter()
    total = 0

    out_f = None
    writer = None
    try:
        with open(args.csv, newline='') as f:
            reader = csv.DictReader(f)
            fieldnames = reader.fieldnames + ['category']

            if args.annotated:
                out_f = open(args.annotated, 'w', newline='')
                writer = csv.DictWriter(out_f, fieldnames=fieldnames)
                writer.writeheader()

            for raw in reader:
                if any(raw.get(k) is None or raw.get(k) == '' for k in INT_COLS):
                    continue
                row = {k: int(raw[k]) for k in INT_COLS}
                cat = classify(row)
                counts[cat] += 1
                total += 1
                if writer is not None:
                    raw['category'] = cat
                    writer.writerow(raw)
    finally:
        if out_f is not None:
            out_f.close()

    print(f"Total traced cycles: {total}")
    print(f"{'category':<24} {'cycles':>10} {'%':>8}")
    print('-' * 46)
    for cat in CATEGORIES:
        n = counts.get(cat, 0)
        if n == 0:
            continue
        print(f"{cat:<24} {n:>10} {n / total * 100:>7.2f}%")

    useful = counts.get('useful_execution', 0)
    if useful:
        print(f"\nCPI = {total / useful:.3f}  (assuming 1 retire per useful cycle)")

    if args.annotated:
        print(f"\nAnnotated trace: {args.annotated}")

    if args.plot:
        try:
            import matplotlib.pyplot as plt
        except ImportError:
            print("matplotlib not available; skipping plot", file=sys.stderr)
            return
        fig, ax = plt.subplots(figsize=(4, 6))
        bottom = 0
        for cat in CATEGORIES:
            n = counts.get(cat, 0)
            if not n:
                continue
            ax.bar(['trace'], [n], bottom=bottom, label=cat)
            bottom += n
        ax.set_ylabel('cycles')
        ax.set_title('CPI stack')
        ax.legend(loc='center left', bbox_to_anchor=(1.0, 0.5))
        fig.tight_layout()
        fig.savefig(args.plot, dpi=150)
        print(f"Wrote {args.plot}")


if __name__ == '__main__':
    main()
