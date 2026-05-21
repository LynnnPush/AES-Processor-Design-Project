#!/usr/bin/env python3
"""CV32E40P pipeline profiling: CPI stack + dynamic instruction profile.

One-shot post-processor for the per-cycle trace produced by
hardware/src/simulation/zynq_tb.sv together with the linker map at
software/aes.map. Writes everything to hardware/src/simulation/:

  pipeline_trace_classified.csv  - input trace plus a `category` column
  profile_opcodes.csv            - dynamic opcode mix
  profile_attribution.csv        - per-function cycle breakdown + CPI
  cpi_stack.png                  - stacked-bar CPI breakdown
  function_cycles.png            - donut of cycle attribution by function

No flags. Paths and constants live at the top of this file.
"""

import csv
import os
import re
import sys
from collections import Counter, defaultdict

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    _HAVE_MPL = True
except ImportError as e:
    print(f'warning: matplotlib unavailable ({e}); '
          f'CSVs will be produced but figures will be skipped',
          file=sys.stderr)
    _HAVE_MPL = False


# --------------------------------------------------------------------------- #
# Paths / constants
# --------------------------------------------------------------------------- #

_HERE = os.path.dirname(os.path.abspath(__file__))
_SIM_DIR = os.path.normpath(
    os.path.join(_HERE, '..', '..', 'hardware', 'src', 'simulation'))
_MAP_PATH = os.path.normpath(os.path.join(_HERE, '..', 'aes.map'))

TRACE_CSV       = os.path.join(_SIM_DIR, 'pipeline_trace.csv')
CLASSIFIED_CSV  = os.path.join(_SIM_DIR, 'pipeline_trace_classified.csv')
OPCODES_CSV     = os.path.join(_SIM_DIR, 'profile_opcodes.csv')
ATTRIBUTION_CSV = os.path.join(_SIM_DIR, 'profile_attribution.csv')
CPI_STACK_PNG   = os.path.join(_SIM_DIR, 'cpi_stack.png')
FUNC_CYCLES_PNG = os.path.join(_SIM_DIR, 'function_cycles.png')

# Instr-RAM BRAM is mapped low-byte aligned while the linker places .vectors at
# 0x8000, so subtract this from map addresses before comparing to trace PCs.
PC_OFFSET = 0x8000
TOP_N = 20


# --------------------------------------------------------------------------- #
# CPI-stack classification
# --------------------------------------------------------------------------- #

CATEGORIES = [
    'mem_stall',
    'load_use_stall',
    'jr_stall',
    'misaligned_stall',
    'branch_penalty',
    'jump_redirect',
    'useful_aes',
    'useful_other',
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
    if not r['instr_valid_id']:
        if r['if_busy'] or r['perf_imiss']:
            return 'ifetch_miss'
        return 'fetch_drain'
    return 'other_bubble'


# --------------------------------------------------------------------------- #
# Map-file parsing
# --------------------------------------------------------------------------- #

RE_TEXT_SECTION = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+\d+\s+\.text\.(\S+)\s*$'
)
RE_BARE_SYMBOL = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+0\s+\d+\s+([A-Za-z_][A-Za-z0-9_]*)\s*$'
)
RE_SECTION_HEADER = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+\d+\s+(\.\S+)\s*$'
)


def parse_map(path, pc_offset):
    explicit = []
    bare = []
    text_end = None
    vectors_end = None

    with open(path) as f:
        for line in f:
            m = RE_TEXT_SECTION.match(line)
            if m:
                start = int(m.group(1), 16)
                size = int(m.group(2), 16)
                if size > 0:
                    explicit.append((start, size, m.group(3)))
                continue
            m = RE_SECTION_HEADER.match(line)
            if m:
                start = int(m.group(1), 16)
                size = int(m.group(2), 16)
                sect = m.group(3)
                if sect == '.text' and size > 0:
                    text_end = start + size
                elif sect == '.vectors' and size > 0:
                    vectors_end = start + size
                continue
            m = RE_BARE_SYMBOL.match(line)
            if m:
                bare.append((int(m.group(1), 16), m.group(2)))

    bare.sort()
    bare_ranges = []
    for i, (addr, name) in enumerate(bare):
        next_addr = bare[i + 1][0] if i + 1 < len(bare) else None
        candidates = []
        if next_addr is not None:
            candidates.append(next_addr)
        if text_end is not None and addr < text_end:
            candidates.append(text_end)
        if vectors_end is not None and addr < vectors_end:
            candidates.append(vectors_end)
        if not candidates:
            candidates.append(addr + 4)
        end = min(c for c in candidates if c > addr)
        bare_ranges.append((addr, end, name))

    ranges = [(s, s + sz, n) for s, sz, n in explicit]
    for s, e, n in bare_ranges:
        if not any(es <= s < ee for es, ee, _ in ranges):
            ranges.append((s, e, n))

    ranges = [(s - pc_offset, e - pc_offset, n)
              for s, e, n in ranges if s >= pc_offset]
    ranges.sort()
    return ranges


def lookup_function(pc, ranges):
    lo, hi = 0, len(ranges)
    while lo < hi:
        mid = (lo + hi) // 2
        s, e, _ = ranges[mid]
        if pc < s:
            hi = mid
        elif pc >= e:
            lo = mid + 1
        else:
            return ranges[mid][2]
    return '<unknown>'


# --------------------------------------------------------------------------- #
# RV32IMC + Zicsr opcode decoder
# --------------------------------------------------------------------------- #

R_FUNCT3 = {
    0b000: 'add/sub', 0b001: 'sll', 0b010: 'slt', 0b011: 'sltu',
    0b100: 'xor', 0b101: 'srl/sra', 0b110: 'or', 0b111: 'and',
}
M_FUNCT3 = {
    0b000: 'mul', 0b001: 'mulh', 0b010: 'mulhsu', 0b011: 'mulhu',
    0b100: 'div', 0b101: 'divu', 0b110: 'rem', 0b111: 'remu',
}
I_FUNCT3 = {
    0b000: 'addi', 0b010: 'slti', 0b011: 'sltiu', 0b100: 'xori',
    0b110: 'ori', 0b111: 'andi', 0b001: 'slli', 0b101: 'srli/srai',
}
LOAD_FUNCT3   = {0b000: 'lb', 0b001: 'lh', 0b010: 'lw',
                 0b100: 'lbu', 0b101: 'lhu'}
STORE_FUNCT3  = {0b000: 'sb', 0b001: 'sh', 0b010: 'sw'}
BRANCH_FUNCT3 = {0b000: 'beq', 0b001: 'bne', 0b100: 'blt',
                 0b101: 'bge', 0b110: 'bltu', 0b111: 'bgeu'}
SYSTEM_FUNCT3 = {0b001: 'csrrw', 0b010: 'csrrs', 0b011: 'csrrc',
                 0b101: 'csrrwi', 0b110: 'csrrsi', 0b111: 'csrrci'}


def decode_rv32(instr):
    op = instr & 0x7f
    f3 = (instr >> 12) & 0x7
    f7 = (instr >> 25) & 0x7f
    if op == 0x33:
        if f3 == 0b000 and (f7 & 0x1f) == 0b10011: return 'aes32esmi'
        if f3 == 0b000 and (f7 & 0x1f) == 0b10001: return 'aes32esi'
        if f7 == 0x01: return M_FUNCT3.get(f3, 'mext')
        if f3 == 0b000: return 'sub' if f7 == 0x20 else 'add'
        if f3 == 0b101: return 'sra' if f7 == 0x20 else 'srl'
        return R_FUNCT3.get(f3, 'op')
    if op == 0x13:
        if f3 == 0b101:
            return 'srai' if (instr >> 30) & 1 else 'srli'
        return I_FUNCT3.get(f3, 'opimm')
    if op == 0x03: return LOAD_FUNCT3.get(f3, 'load')
    if op == 0x23: return STORE_FUNCT3.get(f3, 'store')
    if op == 0x63: return BRANCH_FUNCT3.get(f3, 'branch')
    if op == 0x67: return 'jalr'
    if op == 0x6f: return 'jal'
    if op == 0x37: return 'lui'
    if op == 0x17: return 'auipc'
    if op == 0x0f: return 'fence'
    if op == 0x73:
        if f3 == 0:
            return 'ebreak' if (instr >> 20) & 1 else 'ecall'
        return SYSTEM_FUNCT3.get(f3, 'system')
    return f'<op-0x{op:02x}>'


def decode_rvc(instr):
    instr &= 0xffff
    op = instr & 0x3
    f3 = (instr >> 13) & 0x7
    if op == 0b00:
        return {0: 'c.addi4spn', 2: 'c.lw', 6: 'c.sw'}.get(f3, 'c.q0')
    if op == 0b01:
        if f3 == 0:
            return 'c.nop' if (instr >> 7) & 0x1f == 0 else 'c.addi'
        if f3 == 1: return 'c.jal'
        if f3 == 2: return 'c.li'
        if f3 == 3:
            return 'c.addi16sp' if ((instr >> 7) & 0x1f) == 2 else 'c.lui'
        if f3 == 4:
            sub = (instr >> 10) & 0x3
            if sub == 0: return 'c.srli'
            if sub == 1: return 'c.srai'
            if sub == 2: return 'c.andi'
            f6 = (instr >> 10) & 0x3f
            f2 = (instr >> 5) & 0x3
            if f6 == 0b100011:
                return {0: 'c.sub', 1: 'c.xor', 2: 'c.or',
                        3: 'c.and'}.get(f2, 'c.rop')
            return 'c.rop'
        if f3 == 5: return 'c.j'
        if f3 == 6: return 'c.beqz'
        if f3 == 7: return 'c.bnez'
    if op == 0b10:
        if f3 == 0: return 'c.slli'
        if f3 == 2: return 'c.lwsp'
        if f3 == 4:
            funct4 = (instr >> 12) & 0xf
            rs2 = (instr >> 2) & 0x1f
            rd  = (instr >> 7) & 0x1f
            if funct4 == 0b1000:
                return 'c.jr' if rs2 == 0 else 'c.mv'
            if funct4 == 0b1001:
                if rd == 0 and rs2 == 0: return 'c.ebreak'
                return 'c.jalr' if rs2 == 0 else 'c.add'
            return 'c.q2'
        if f3 == 6: return 'c.swsp'
    return f'<c-0x{instr:04x}>'


def decode_instr(instr):
    if (instr & 0x3) == 0x3:
        return decode_rv32(instr)
    return decode_rvc(instr)


def parse_pc(s):
    return int(s, 16) if s.startswith('0x') else int(s)


# --------------------------------------------------------------------------- #
# Main pipeline
# --------------------------------------------------------------------------- #

def main():
    if not os.path.exists(TRACE_CSV):
        sys.exit(f'error: trace not found: {TRACE_CSV}')
    if not os.path.exists(_MAP_PATH):
        sys.exit(f'error: map not found: {_MAP_PATH}')

    ranges = parse_map(_MAP_PATH, PC_OFFSET)
    print(f'Loaded {len(ranges)} symbol ranges from {_MAP_PATH}')

    counts = Counter()
    func_cycle_counts = defaultdict(Counter)
    func_insn_count = Counter()
    func_mnem_count = defaultdict(Counter)
    opcode_count = Counter()
    total_cycles = 0
    total_retired = 0

    instr_cache = {}

    def decode_cached(i):
        m = instr_cache.get(i)
        if m is None:
            m = decode_instr(i)
            instr_cache[i] = m
        return m

    with open(TRACE_CSV, newline='') as f_in, \
         open(CLASSIFIED_CSV, 'w', newline='') as f_out:
        reader = csv.DictReader(f_in)
        writer = csv.DictWriter(
            f_out, fieldnames=reader.fieldnames + ['mnemonic', 'category'])
        writer.writeheader()

        for raw in reader:
            if any(raw.get(k) in (None, '') for k in INT_COLS):
                continue
            row = {k: int(raw[k]) for k in INT_COLS}

            # Decode the in-flight instruction once per row; reused for the
            # trace mnemonic column, useful_aes/useful_other split, and the
            # per-function opcode counters at retire.
            try:
                instr = parse_pc(raw['instr'])
                mnem = decode_cached(instr)
            except (KeyError, ValueError):
                instr = None
                mnem = ''

            cat = classify(row)
            if cat == 'useful_execution':
                cat = ('useful_aes' if mnem in ('aes32esmi', 'aes32esi')
                       else 'useful_other')
            counts[cat] += 1
            total_cycles += 1
            raw['mnemonic'] = mnem
            raw['category'] = cat
            writer.writerow(raw)

            pc_str = raw['pc_id'] if row['is_decoding'] else raw['pc_if']
            try:
                pc = parse_pc(pc_str)
            except (KeyError, ValueError):
                continue
            func = lookup_function(pc, ranges)
            func_cycle_counts[func][cat] += 1

            if row['is_decoding'] and row['id_ready'] and instr is not None:
                func_insn_count[func] += 1
                opcode_count[mnem] += 1
                if mnem in ('aes32esmi', 'aes32esi'):
                    func_mnem_count[func][mnem] += 1
                total_retired += 1

    if total_cycles == 0:
        sys.exit('error: no traced cycles found')

    _print_summaries(counts, func_cycle_counts, func_insn_count,
                     opcode_count, total_cycles, total_retired)
    ordered = sorted(func_cycle_counts.items(),
                     key=lambda kv: -sum(kv[1].values()))
    _write_opcodes_csv(opcode_count, total_retired)
    _write_attribution_csv(ordered, func_insn_count, func_mnem_count,
                           func_cycle_counts, total_retired)
    written = [CLASSIFIED_CSV, OPCODES_CSV, ATTRIBUTION_CSV]
    if _HAVE_MPL:
        _plot_cpi_stack(counts, total_cycles)
        _plot_function_cycles(ordered, total_cycles)
        written += [CPI_STACK_PNG, FUNC_CYCLES_PNG]

    print('\nWrote:')
    for p in written:
        print(f'  {p}')


def _print_summaries(counts, func_cycle_counts, func_insn_count,
                     opcode_count, total_cycles, total_retired):
    print(f'\nTotal traced cycles: {total_cycles}')
    print(f"{'category':<24} {'cycles':>10} {'%':>8}")
    print('-' * 46)
    for cat in CATEGORIES:
        n = counts.get(cat, 0)
        if n == 0:
            continue
        print(f'{cat:<24} {n:>10} {n / total_cycles * 100:>7.2f}%')

    useful = counts.get('useful_aes', 0) + counts.get('useful_other', 0)
    if useful:
        print(f'\nCPI = {total_cycles / useful:.3f} '
              f'(assuming 1 retire per useful cycle)')

    print(f'\nTotal retired instructions: {total_retired}')

    print(f'\nDynamic instruction count by function (top {TOP_N}):')
    print(f"{'function':<32} {'insns':>10} {'%':>7}")
    print('-' * 52)
    for func, n in func_insn_count.most_common(TOP_N):
        print(f'{func:<32} {n:>10} {n / total_retired * 100:>6.2f}%')

    print(f'\nDynamic instruction mix by opcode (top {TOP_N}):')
    print(f"{'mnemonic':<16} {'insns':>10} {'%':>7}")
    print('-' * 36)
    for mnem, n in opcode_count.most_common(TOP_N):
        print(f'{mnem:<16} {n:>10} {n / total_retired * 100:>6.2f}%')

    print(f'\nPer-function cycle attribution (top {TOP_N}):')
    print(f"{'function':<28} {'cycles':>9} {'cyc%':>6} "
          f"{'insn%':>6} {'CPI':>6}")
    print('-' * 60)
    ordered = sorted(func_cycle_counts.items(),
                     key=lambda kv: -sum(kv[1].values()))
    for func, cc in ordered[:TOP_N]:
        cyc = sum(cc.values())
        u = cc.get('useful_aes', 0) + cc.get('useful_other', 0)
        insns = func_insn_count.get(func, 0)
        cpi = (cyc / u) if u else float('inf')
        print(f'{func:<28} {cyc:>9} {cyc / total_cycles * 100:>5.2f}% '
              f'{insns / total_retired * 100:>5.2f}% {cpi:>6.2f}')


def _write_opcodes_csv(opcode_count, total_retired):
    with open(OPCODES_CSV, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['mnemonic', 'insns', 'pct'])
        for mnem, n in opcode_count.most_common():
            w.writerow([mnem, n, f'{n / total_retired * 100:.4f}'])


def _write_attribution_csv(ordered, func_insn_count, func_mnem_count,
                           func_cycle_counts, total_retired):
    cats = sorted({c for cc in func_cycle_counts.values() for c in cc})
    with open(ATTRIBUTION_CSV, 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['function', 'insns', 'insns_pct',
                    'aes32esmi_insns', 'aes32esi_insns',
                    'cycles', 'cpi'] + cats)
        for func, cc in ordered:
            cyc = sum(cc.values())
            u = cc.get('useful_aes', 0) + cc.get('useful_other', 0)
            insns = func_insn_count.get(func, 0)
            mc = func_mnem_count.get(func, {})
            aes_esmi = mc.get('aes32esmi', 0)
            aes_esi  = mc.get('aes32esi', 0)
            cpi = f'{cyc / u:.4f}' if u else ''
            w.writerow([func, insns,
                        f'{insns / total_retired * 100:.4f}',
                        aes_esmi, aes_esi,
                        cyc, cpi]
                       + [cc.get(c, 0) for c in cats])


def _plot_cpi_stack(counts, total_cycles):
    fig, ax = plt.subplots(figsize=(4, 6))
    bottom = 0
    for cat in CATEGORIES:
        n = counts.get(cat, 0)
        if not n:
            continue
        ax.bar(['trace'], [n], bottom=bottom,
               label=f'{cat} ({n / total_cycles * 100:.1f}%)')
        bottom += n
    ax.set_ylabel('cycles')
    ax.set_title('CPI stack')
    ax.legend(loc='center left', bbox_to_anchor=(1.02, 0.5), fontsize=8)
    fig.savefig(CPI_STACK_PNG, dpi=150, bbox_inches='tight')
    plt.close(fig)


def _plot_function_cycles(ordered, total_cycles):
    keep = TOP_N - 1
    top = ordered[:keep]
    rest = ordered[keep:]
    labels = [f for f, _ in top]
    sizes = [sum(cc.values()) for _, cc in top]
    aes_sizes = [cc.get('useful_aes', 0) for _, cc in top]

    rest_total = sum(sum(cc.values()) for _, cc in rest)
    rest_aes = sum(cc.get('useful_aes', 0) for _, cc in rest)
    if rest_total > 0:
        labels.append(f'other ({len(rest)} funcs)')
        sizes.append(rest_total)
        aes_sizes.append(rest_aes)

    non_aes_sizes = [s - a for s, a in zip(sizes, aes_sizes)]

    # Wider figure leaves room for the (now long) two-legend stack; we also
    # pass both legends to bbox_extra_artists so savefig's tight crop sees
    # them as content rather than clipping at the figure edge.
    fig, ax = plt.subplots(figsize=(15, 7))

    # Outer ring: per function.
    outer_wedges, _ = ax.pie(
        sizes, radius=1.0, startangle=90,
        wedgeprops={'width': 0.3, 'edgecolor': 'white'})

    # Inner ring: each outer slice split into [AES useful, non-AES] cycles.
    # Pick a colour that isn't already used by the tab10 outer-ring palette.
    # tab10's C3 is #d62728 (assigned to memcpy here), so use a strong magenta
    # instead to keep the AES sub-wedge visually distinct.
    aes_color = '#e7298a'
    non_aes_color = '#cccccc'
    inner_sizes = []
    inner_colors = []
    for a, na in zip(aes_sizes, non_aes_sizes):
        inner_sizes.extend([a, na])
        inner_colors.extend([aes_color, non_aes_color])
    ax.pie(inner_sizes, radius=0.7, startangle=90,
           colors=inner_colors,
           wedgeprops={'width': 0.25, 'edgecolor': 'white'})

    def _fmt(label, total, aes):
        if not total:
            return f'{label} — 0'
        pct = total / total_cycles * 100
        base = f'{label} — {total} ({pct:.1f}%)'
        if aes:
            return f'{base} · AES {aes} ({aes / total * 100:.1f}%)'
        return base

    legend_labels = [_fmt(l, s, a)
                     for l, s, a in zip(labels, sizes, aes_sizes)]
    outer_legend = ax.legend(
        outer_wedges, legend_labels,
        loc='center left', bbox_to_anchor=(1.02, 0.5),
        fontsize=9, frameon=False, title='function (outer ring)')
    ax.add_artist(outer_legend)

    from matplotlib.patches import Patch
    inner_handles = [
        Patch(facecolor=aes_color, label='aes32esmi/esi (useful)'),
        Patch(facecolor=non_aes_color, label='non-AES cycles'),
    ]
    inner_legend = ax.legend(
        handles=inner_handles,
        loc='lower left', bbox_to_anchor=(1.02, -0.02),
        fontsize=9, frameon=False, title='inner ring')

    ax.set_title('Cycle attribution by function '
                 '(inner ring: AES vs non-AES)')
    fig.savefig(FUNC_CYCLES_PNG, dpi=150, bbox_inches='tight',
                bbox_extra_artists=(outer_legend, inner_legend))
    plt.close(fig)


if __name__ == '__main__':
    main()
