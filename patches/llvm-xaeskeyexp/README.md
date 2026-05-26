# XAesKeyExp LLVM patches

Adds the custom RISC-V extension `xaeskeyexp` to LLVM/clang so that the
AES-128 key schedule can be generated on-the-fly, between encryption
rounds, using a hidden 128-bit round-key register in the PDP project-10
riscy core. Three builtins lower to three custom instructions:

- `__builtin_riscv_xaesksld(w, widx)` -> `xaesksld rs1, widx`
  (seed cipher-key word `widx`)
- `__builtin_riscv_xaeskse()` -> `xaeskse`
  (advance the key register to the next round key in one cycle)
- `__builtin_riscv_xaesksrd(widx)` -> `xaesksrd rd, widx`
  (read round-key word `widx`)

All three share OPC_OP / funct3=0 with a unique funct5 in Inst[29:25]
(`0b10010` ld, `0b10000` kse, `0b10100` rd); the 2-bit word index sits
in Inst[31:30], matching the riscy decoder. The custom feature flag lets
the instructions be enabled independently of any standard extension.

## Hidden state and why the intrinsics are not pure

Unlike `xaes32esi` / `xaes32esmi` (pure functions), these operate on a
hidden 128-bit key register inside the core. The intrinsics are therefore
declared `IntrInaccessibleMemOnly` + `IntrHasSideEffects` so the optimizer
keeps load/expand/read ordered relative to one another and does not delete
the void-returning load/expand as dead. The instruction defs carry
`mayLoad = 1, mayStore = 1, hasSideEffects = 1` to match the memory effects
TableGen infers from those intrinsics.

## Files

- `RISCVFeatures.td.patch` - adds `FeatureVendorXAesKeyExp` and the
  `HasVendorXAesKeyExp` predicate.
- `IntrinsicsRISCV.td.patch` - declares `int_riscv_xaesksld`,
  `int_riscv_xaeskse`, `int_riscv_xaesksrd` with the side-effect attributes
  and `ClangBuiltin` names.
- `BuiltinsRISCV.td.patch` - declares the three clang builtins under the
  `xaeskeyexp,32bit` feature gate.
- `RISCVInstrInfoXAesKeyExp.td.patch` - new file diff: the three
  instruction definitions and their selection patterns.
- `RISCVInstrInfo.td.patch` - `include "RISCVInstrInfoXAesKeyExp.td"`.

The four shared-file patches add their blocks *after* the existing
`xaes32esmi` / `xaes32esi` blocks, so apply the `llvm-xaes32esmi` and
`llvm-xaes32esi` patch sets first.

## Applying to a fresh LLVM checkout

```sh
cd /path/to/llvm-project
git checkout f351172d4a840dfbf533319b62925747a10b762f   # or any nearby rev
git apply /path/to/pdp-project/patches/llvm-xaes32esmi/*.patch
git apply /path/to/pdp-project/patches/llvm-xaes32esi/*.patch
git apply /path/to/pdp-project/patches/llvm-xaeskeyexp/*.patch
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

The C wrappers `aesksld` / `aeskse` / `aesksrd` in
`software/include/aes_intrinsics.h` call the new builtins;
`software/config/rv32-standard.conf` sets
`-march=rv32imac_zicsr_xaes32esmi_xaes32esi_xaeskeyexp`. The on-the-fly key
expansion lives in `aes128_encrypt_block()` in `software/main.c` (the old
byte-serial `expand_key()` is retained behind `-DREFERENCE_KEYEXP`).
```
