# XAes32esi LLVM patches

Adds the custom RISC-V extension `xaes32esi` (AES final round, no
MixColumns) to LLVM/clang so that `__builtin_riscv_xaes32esi(rs1, rs2, bs)`
lowers to a single `xaes32esi` instruction matching the PDP project-10
hardware implementation. Encoding is bit-identical to the standard Zkne
`aes32esi` (funct5=0b10001); the custom feature flag exists so the
instruction can be enabled without pulling in the rest of Zkne.

## Files

- `RISCVFeatures.td.patch` — adds `FeatureVendorXAes32esi` and the
  `HasVendorXAes32esi` predicate.
- `RISCVInstrInfoXAes32esi.td.patch` — new file diff: `XAES32ESI`
  instruction def + selection pattern.
- `RISCVInstrInfo.td.patch` — `include "RISCVInstrInfoXAes32esi.td"`.
- `IntrinsicsRISCV.td.patch` — declares `int_riscv_xaes32esi` with
  `ClangBuiltin<"__builtin_riscv_xaes32esi">`.
- `BuiltinsRISCV.td.patch` — declares the clang builtin under the
  `xaes32esi,32bit` feature gate.

These patches assume the `llvm-xaes32esmi` patches are applied first
(some hunks anchor on lines those patches add). Apply alphabetically:

```sh
cd /path/to/llvm-project
git checkout f351172d4a840dfbf533319b62925747a10b762f   # or any nearby rev
git apply /path/to/pdp-project/patches/llvm-xaes32esmi/*.patch
git apply /path/to/pdp-project/patches/llvm-xaes32esi/*.patch
```

Rebuild the RISCV backend with the cmake/ninja command in the top-level
`README.md` under "LLVM modifications". On the procdesign server,
**always pass `ninja -j4`** — bare `ninja` OOMs the box.

## Using the toolchain

After rebuilding LLVM:

```sh
cd software
make clean && make soft
```

The C wrapper at `software/include/aes_intrinsics.h` calls the new
builtin; `software/config/rv32-standard.conf` sets
`-march=rv32imac_zicsr_xaes32esmi_xaes32esi`.
