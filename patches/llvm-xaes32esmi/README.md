# XAes32esmi LLVM patches

Adds the custom RISC-V extension `xaes32esmi` to LLVM/clang so that
`__builtin_riscv_xaes32esmi(rs1, rs2, bs)` lowers to a single
`xaes32esmi` instruction matching the PDP project-10 hardware
implementation. Encoding is bit-identical to the standard Zkne
`aes32esmi`; the custom feature flag exists so the instruction can be
enabled without pulling in the rest of Zkne.

## Files

- `RISCVFeatures.td.patch` — adds `FeatureVendorXAes32esmi` and the
  `HasVendorXAes32esmi` predicate.
- `RISCVInstrInfoXAes32esmi.td.patch` — new file diff: `XAES32ESMI`
  instruction def + selection pattern.
- `RISCVInstrInfo.td.patch` — `include "RISCVInstrInfoXAes32esmi.td"`.
- `IntrinsicsRISCV.td.patch` — declares `int_riscv_xaes32esmi` with
  `ClangBuiltin<"__builtin_riscv_xaes32esmi">`.
- `BuiltinsRISCV.td.patch` — declares the clang builtin under the
  `xaes32esmi,32bit` feature gate.

Patches were generated with `git diff` against upstream LLVM at git
rev `f351172d4a840dfbf533319b62925747a10b762f`
(`https://github.com/llvm/llvm-project.git`).

## Applying to a fresh LLVM checkout

```sh
cd /path/to/llvm-project
git checkout f351172d4a840dfbf533319b62925747a10b762f   # or any nearby rev
git apply /path/to/pdp-project/patches/llvm-xaes32esmi/*.patch
```

Then rebuild the RISCV backend with the cmake/ninja command in the
top-level `README.md` under "LLVM modifications". On the procdesign
server, **always pass `ninja -j4`** — bare `ninja` OOMs the box.

## Using the toolchain

After rebuilding LLVM:

```sh
cd software
make clean && make soft
```

The C wrapper at `software/include/aes_intrinsics.h` calls the new
builtin; `software/config/rv32-standard.conf` sets
`-march=rv32imac_zicsr_xaes32esmi`.
