# XAesState LLVM patches

Adds the custom RISC-V extension `xaesstate` to LLVM/clang so the round-wise
AES-128 accelerator added in `cv32e40p_aes_state.sv` can be driven from C.
The hardware holds the 128-bit cipher state in a hidden register and
advances it by one full FIPS-197 forward round per cycle; AddRoundKey reads
the live round key from the adjacent XAesKeyExp register (no GPR shuttling).

Three builtins lower to three custom instructions:

- `__builtin_riscv_xaesstld(w, sidx)` -> `xaesstld rs1, sidx`
  (load one state word: `st[sidx] <- rs1`)
- `__builtin_riscv_xaesrnd(mode)` -> `xaesrnd mode`
  (one full round: `st <- round(st, krk)`; mode 0 = middle, 1 = final,
  2 = AddRoundKey-only)
- `__builtin_riscv_xaesstrd(sidx)` -> `xaesstrd rd, sidx`
  (read one state word: `rd <- st[sidx]`)

All three share OPC_OP / funct3=0 with a unique funct5 in Inst[29:25]
(`0b10101` ld, `0b10110` rnd, `0b10111` rd); the 2-bit sidx / mode sits in
Inst[31:30], matching the riscy decoder. The custom feature flag lets the
extension be enabled independently of the rest of the AES family.

## Hidden state and why the intrinsics are not pure

Like `xaeskeyexp`, these intrinsics operate on a hidden register inside
the core. They are declared `IntrInaccessibleMemOnly` + `IntrHasSideEffects`
so the optimizer keeps load / round / read ordered relative to one
another and to the surrounding `xaeskse` calls, and does not delete the
void-returning load / round as dead. The instruction defs carry
`mayLoad = 1, mayStore = 1, hasSideEffects = 1` to match.

## Files

- `RISCVFeatures.td.patch` - adds `FeatureVendorXAesState` and the
  `HasVendorXAesState` predicate.
- `IntrinsicsRISCV.td.patch` - declares `int_riscv_xaesstld`,
  `int_riscv_xaesrnd`, `int_riscv_xaesstrd` with the side-effect
  attributes and `ClangBuiltin` names.
- `BuiltinsRISCV.td.patch` - declares the three clang builtins under the
  `xaesstate,32bit` feature gate.
- `RISCVInstrInfoXAesState.td.patch` - new file diff: the three
  instruction definitions and their selection patterns.
- `RISCVInstrInfo.td.patch` - `include "RISCVInstrInfoXAesState.td"`.

The four shared-file patches add their blocks *after* the existing
`xaeskeyexp` blocks, so apply the `llvm-xaes32esmi`, `llvm-xaes32esi`,
and `llvm-xaeskeyexp` patch sets first.

## Applying to a fresh LLVM checkout

```sh
cd /path/to/llvm-project
git checkout f351172d4a840dfbf533319b62925747a10b762f   # or any nearby rev
git apply /path/to/pdp-project/patches/llvm-xaes32esmi/*.patch
git apply /path/to/pdp-project/patches/llvm-xaes32esi/*.patch
git apply /path/to/pdp-project/patches/llvm-xaeskeyexp/*.patch
git apply /path/to/pdp-project/patches/llvm-xaesstate/*.patch
```

Then rebuild with the cmake/ninja command in the top-level `README.md`
under "LLVM modifications". On the procdesign server, **always pass
`ninja -j4`** - bare `ninja` OOMs the box.

## Using the toolchain

After rebuilding LLVM:

```sh
cd software
make clean && make soft
```

The C wrappers `aesstld` / `aesrnd` / `aesstrd` in
`software/include/aes_intrinsics.h` call the new builtins;
`software/config/rv32-standard.conf` sets
`-march=rv32imac_zicsr_xaes32esmi_xaes32esi_xaeskeyexp_xaesstate`.
The round-wise encryption loop lives in `aes128_encrypt_block()` in
`software/main.c` (33 AES-extension instructions per block vs. 218 with the
byte-wise path).
