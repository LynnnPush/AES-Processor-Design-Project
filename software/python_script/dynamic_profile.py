#!/usr/bin/env python3
"""Dynamic instruction & function profiling from CV32E40P pipeline_trace.csv.

Section 1C of the CPI-stack analysis. Reuses the per-cycle trace produced by
the testbench in `hardware/src/simulation/zynq_tb.sv` and the symbol layout
already encoded in the linker map `software/aes.map`.

For every cycle where an instruction actually retires (is_decoding && id_ready),
we attribute that retire to:
  - a function (via map-derived symbol ranges, looking up `pc_id`)
  - an opcode mnemonic (decoded from the raw `instr` bits, RV32IMC + Zicsr)

When the classified CSV from cpi_stack.py is also provided, every traced cycle
(retiring or stalling) is attributed to its containing function so we can show
per-function cycle attribution alongside dynamic instruction count.

Usage:
  python3 dynamic_profile.py [pipeline_trace.csv]
                             [--map ../aes.map]
                             [--classified pipeline_trace_classified.csv]
                             [--pc-offset 0x8000]
                             [--top 20]
                             [--out-functions functions.csv]
                             [--out-opcodes opcodes.csv]
                             [--out-attribution per_function_cycles.csv]

`--pc-offset` is subtracted from map addresses before comparing to trace PCs;
the testbench reports PCs from the core that are 0x8000 below the linker-map
addresses for this design (instr-RAM BRAM is mapped low-byte aligned while the
linker places .vectors at 0x8000).
"""

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict


# --------------------------------------------------------------------------- #
# Map-file parsing
# --------------------------------------------------------------------------- #

# `.text.<funcname>` split-out sections: VMA LMA SIZE ALIGN .text.<name>
RE_TEXT_SECTION = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+\d+\s+\.text\.(\S+)\s*$'
)

# Bare symbol lines inside the monolithic .text/.vectors: VMA LMA 0 ALIGN <name>
RE_BARE_SYMBOL = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+0\s+\d+\s+([A-Za-z_][A-Za-z0-9_]*)\s*$'
)

# Section header lines we want to bound things by.
RE_SECTION_HEADER = re.compile(
    r'^\s+([0-9a-f]+)\s+[0-9a-f]+\s+([0-9a-f]+)\s+\d+\s+(\.\S+)\s*$'
)


def parse_map(path, pc_offset):
    """Return sorted list of (start_pc, end_pc, name) function ranges."""
    explicit = []  # (start, size, name) from .text.<name> sections
    bare = []      # (start, name) from bare-symbol lines
    text_end = None
    vectors_end = None

    with open(path) as f:
        for line in f:
            m = RE_TEXT_SECTION.match(line)
            if m:
                start = int(m.group(1), 16)
                size = int(m.group(2), 16)
                name = m.group(3)
                if size > 0:
                    explicit.append((start, size, name))
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
                addr = int(m.group(1), 16)
                name = m.group(2)
                bare.append((addr, name))

    # Build ranges from bare symbols by pairing with next symbol or section end.
    bare.sort()
    bare_ranges = []
    for i, (addr, name) in enumerate(bare):
        next_addr = bare[i + 1][0] if i + 1 < len(bare) else None
        end_candidates = []
        if next_addr is not None:
            end_candidates.append(next_addr)
        if text_end is not None and addr < text_end:
            end_candidates.append(text_end)
        if vectors_end is not None and addr < vectors_end:
            end_candidates.append(vectors_end)
        if not end_candidates:
            end_candidates.append(addr + 4)
        end = min(c for c in end_candidates if c > addr)
        bare_ranges.append((addr, end, name))

    # Merge: explicit takes precedence over bare for overlapping ranges.
    ranges = [(s, s + sz, n) for s, sz, n in explicit]
    for s, e, n in bare_ranges:
        if not any(es <= s < ee for es, ee, _ in ranges):
            ranges.append((s, e, n))

    # Apply offset and sort.
    ranges = [(s - pc_offset, e - pc_offset, n) for s, e, n in ranges
              if s >= pc_offset]
    ranges.sort()
    return ranges


def lookup_function(pc, ranges):
    """Binary-search PC into the sorted ranges. Returns name or '<unknown>'."""
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
LOAD_FUNCT3 = {0b000: 'lb', 0b001: 'lh', 0b010: 'lw',
               0b100: 'lbu', 0b101: 'lhu'}
STORE_FUNCT3 = {0b000: 'sb', 0b001: 'sh', 0b010: 'sw'}
BRANCH_FUNCT3 = {0b000: 'beq', 0b001: 'bne', 0b100: 'blt',
                 0b101: 'bge', 0b110: 'bltu', 0b111: 'bgeu'}
SYSTEM_FUNCT3 = {0b001: 'csrrw', 0b010: 'csrrs', 0b011: 'csrrc',
                 0b101: 'csrrwi', 0b110: 'csrrsi', 0b111: 'csrrci'}


def decode_rv32(instr):
    op = instr & 0x7f
    f3 = (instr >> 12) & 0x7
    f7 = (instr >> 25) & 0x7f

    if op == 0x33:  # OP
        if f7 == 0x01:
            return M_FUNCT3.get(f3, 'mext')
        if f3 == 0b000:
            return 'sub' if f7 == 0x20 else 'add'
        if f3 == 0b101:
            return 'sra' if f7 == 0x20 else 'srl'
        return R_FUNCT3.get(f3, 'op')
    if op == 0x13:  # OP-IMM
        if f3 == 0b101:
            return 'srai' if (instr >> 30) & 1 else 'srli'
        return I_FUNCT3.get(f3, 'opimm')
    if op == 0x03:
        return LOAD_FUNCT3.get(f3, 'load')
    if op == 0x23:
        return STORE_FUNCT3.get(f3, 'store')
    if op == 0x63:
        return BRANCH_FUNCT3.get(f3, 'branch')
    if op == 0x67:
        return 'jalr'
    if op == 0x6f:
        return 'jal'
    if op == 0x37:
        return 'lui'
    if op == 0x17:
        return 'auipc'
    if op == 0x0f:
        return 'fence'
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
                return {0: 'c.sub', 1: 'c.xor', 2: 'c.or', 3: 'c.and'}.get(f2, 'c.rop')
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
    if instr is None:
        return '<none>'
    if (instr & 0x3) == 0x3:
        return decode_rv32(instr)
    return decode_rvc(instr)


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def parse_int_or_hex(s):
    return int(s, 0)


def parse_pc(s):
    return int(s, 16) if s.startswith('0x') else int(s)


_SIM_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), '..', '..', 'hardware', 'src', 'simulation')
)
_MAP_DEFAULT = os.path.normpath(
    os.path.join(os.path.dirname(__file__), '..', 'aes.map')
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv', nargs='?',
                    default=os.path.join(_SIM_DIR, 'pipeline_trace.csv'))
    ap.add_argument('--map', default=None,
                    help='Path to aes.map (default: software/aes.map)')
    ap.add_argument('--classified', default=None,
                    help='Path to pipeline_trace_classified.csv from cpi_stack.py'
                         ' (default: auto-detect <csv>_classified.csv)')
    ap.add_argument('--pc-offset', type=parse_int_or_hex, default=0x8000,
                    help='Subtracted from map addresses before lookup'
                         ' (default 0x8000 — instr-RAM mapping for this design)')
    ap.add_argument('--top', type=int, default=20)
    ap.add_argument('--out-opcodes', default=os.path.join(_SIM_DIR, 'profile_opcodes.csv'))
    ap.add_argument('--out-attribution', default=os.path.join(_SIM_DIR, 'profile_attribution.csv'))
    args = ap.parse_args()

    if args.map is None:
        for cand in (_MAP_DEFAULT,
                     os.path.join(os.path.dirname(args.csv) or '.', 'aes.map'),
                     'aes.map',
                     '../aes.map',
                     '../../software/aes.map'):
            if os.path.exists(cand):
                args.map = cand
                break
        if args.map is None:
            print('error: --map not provided and aes.map not found', file=sys.stderr)
            sys.exit(2)

    ranges = parse_map(args.map, args.pc_offset)
    print(f'Loaded {len(ranges)} symbol ranges from {args.map}'
          f' (pc-offset 0x{args.pc_offset:x})')

    func_insn_count = Counter()       # dynamic retired instructions per function
    opcode_count = Counter()          # dynamic instruction mix
    func_opcode_count = defaultdict(Counter)  # per-function opcode mix
    total_retired = 0

    # Cache PC -> (function, mnemonic) so we don't re-decode every cycle.
    pc_cache = {}

    def attribute(pc, instr):
        key = (pc, instr)
        cached = pc_cache.get(key)
        if cached is None:
            cached = (lookup_function(pc, ranges), decode_instr(instr))
            pc_cache[key] = cached
        return cached

    with open(args.csv, newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                is_dec = int(row['is_decoding'])
                id_rdy = int(row['id_ready'])
            except (KeyError, ValueError):
                continue
            if not (is_dec and id_rdy):
                continue
            pc = parse_pc(row['pc_id'])
            instr = parse_pc(row['instr'])
            func, mnem = attribute(pc, instr)
            func_insn_count[func] += 1
            opcode_count[mnem] += 1
            func_opcode_count[func][mnem] += 1
            total_retired += 1

    if total_retired == 0:
        print('No retired instructions found in trace.', file=sys.stderr)
        sys.exit(1)

    # ------------------------------------------------------------------ #
    # Per-function CPI attribution (uses classified CSV if available).
    # ------------------------------------------------------------------ #
    classified_path = args.classified
    if classified_path is None:
        base, ext = os.path.splitext(args.csv)
        cand = f'{base}_classified{ext or ".csv"}'
        if os.path.exists(cand):
            classified_path = cand

    func_cycle_counts = None
    if classified_path and os.path.exists(classified_path):
        func_cycle_counts = defaultdict(Counter)  # func -> Counter(category)
        total_cycles = 0
        with open(classified_path, newline='') as f:
            reader = csv.DictReader(f)
            for row in reader:
                cat = row.get('category')
                if not cat:
                    continue
                # Attribute by pc_id when an instr is in ID, else by pc_if.
                try:
                    is_dec = int(row['is_decoding'])
                except (KeyError, ValueError):
                    is_dec = 0
                pc_str = row['pc_id'] if is_dec else row['pc_if']
                pc = parse_pc(pc_str)
                func = lookup_function(pc, ranges)
                func_cycle_counts[func][cat] += 1
                total_cycles += 1
        print(f'Loaded {total_cycles} classified cycles from {classified_path}')
    else:
        print('(no classified CSV — skipping per-function cycle attribution)')

    # ------------------------------------------------------------------ #
    # Reports
    # ------------------------------------------------------------------ #
    print(f'\nTotal retired instructions: {total_retired}')

    print(f'\nDynamic instruction count by function (top {args.top}):')
    print(f"{'function':<32} {'insns':>10} {'%':>7}")
    print('-' * 52)
    for func, n in func_insn_count.most_common(args.top):
        print(f'{func:<32} {n:>10} {n / total_retired * 100:>6.2f}%')

    print(f'\nDynamic instruction mix by opcode (top {args.top}):')
    print(f"{'mnemonic':<16} {'insns':>10} {'%':>7}")
    print('-' * 36)
    for mnem, n in opcode_count.most_common(args.top):
        print(f'{mnem:<16} {n:>10} {n / total_retired * 100:>6.2f}%')

    if func_cycle_counts is not None:
        total_cycles = sum(sum(c.values()) for c in func_cycle_counts.values())
        useful_cycles = sum(c.get('useful_execution', 0)
                            for c in func_cycle_counts.values())
        print(f'\nPer-function cycle attribution (top {args.top}, sorted by cycles):')
        print(f"{'function':<28} {'cycles':>9} {'cyc%':>6} "
              f"{'insn%':>6} {'CPI':>6}")
        print('-' * 60)
        ordered = sorted(func_cycle_counts.items(),
                         key=lambda kv: -sum(kv[1].values()))
        for func, cc in ordered[:args.top]:
            cyc = sum(cc.values())
            useful = cc.get('useful_execution', 0)
            insns = func_insn_count.get(func, 0)
            cpi = (cyc / useful) if useful else float('inf')
            print(f'{func:<28} {cyc:>9} {cyc / total_cycles * 100:>5.2f}% '
                  f'{insns / total_retired * 100:>5.2f}% {cpi:>6.2f}')

    # ------------------------------------------------------------------ #
    # CSV outputs
    # ------------------------------------------------------------------ #
    if args.out_opcodes:
        with open(args.out_opcodes, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['mnemonic', 'insns', 'pct'])
            for mnem, n in opcode_count.most_common():
                w.writerow([mnem, n, f'{n / total_retired * 100:.4f}'])
        print(f'Wrote {args.out_opcodes}')

    if args.out_attribution and func_cycle_counts is not None:
        cats = sorted({c for cc in func_cycle_counts.values() for c in cc})
        with open(args.out_attribution, 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(['function', 'insns', 'insns_pct', 'cycles', 'cpi'] + cats)
            for func, cc in sorted(func_cycle_counts.items(),
                                   key=lambda kv: -sum(kv[1].values())):
                cyc = sum(cc.values())
                useful = cc.get('useful_execution', 0)
                insns = func_insn_count.get(func, 0)
                cpi = (cyc / useful) if useful else ''
                w.writerow([func, insns,
                            f'{insns / total_retired * 100:.4f}',
                            cyc,
                            f'{cpi:.4f}' if cpi != '' else '']
                           + [cc.get(c, 0) for c in cats])
        print(f'Wrote {args.out_attribution}')


if __name__ == '__main__':
    main()
