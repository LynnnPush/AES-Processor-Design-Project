#ifndef AES_INTRINSICS_H
#define AES_INTRINSICS_H

#include <stdint.h>

/*
 * RISC-V scalar-crypto-style aes32esmi / aes32esi instructions implemented
 * on the project-10 riscy core, exposed as clang builtins via the custom
 * XAes32esmi / XAes32esi extensions added to our local LLVM tree.
 *
 *   xaes32esmi rd, rs1, rs2, bs   (middle rounds: SBox + MixCol)
 *   xaes32esi  rd, rs1, rs2, bs   (final  round:  SBox only,  no MixCol)
 *
 * Semantics (match the Zkne spec):
 *   esmi: rd = rs1 ^ rot_left(MixCol_fwd(SBox((rs2 >> (bs*8)) & 0xFF)), bs*8)
 *   esi : rd = rs1 ^ rot_left(zext32   (SBox((rs2 >> (bs*8)) & 0xFF)), bs*8)
 *
 * Encodings match the standard Zkne ones (OPC_OP, funct3=0, bs in
 * Inst[31:30]; funct5 = 0b10011 for esmi, 0b10001 for esi). Requires
 * -march=rv32imac_zicsr_xaes32esmi_xaes32esi (set in config/rv32-standard.conf).
 *
 * `bs` must be a compile-time constant in {0,1,2,3}. The 4-way switch
 * below dispatches a runtime `bs` to a literal call so the builtin's
 * constant-argument check is satisfied at every call site; with a
 * compile-time-constant `bs` the optimizer collapses it to one call.
 */

static inline uint32_t aes32esmi(uint32_t rs1, uint32_t rs2, int bs) {
    switch (bs & 0x3) {
    case 0:  return __builtin_riscv_xaes32esmi(rs1, rs2, 0);
    case 1:  return __builtin_riscv_xaes32esmi(rs1, rs2, 1);
    case 2:  return __builtin_riscv_xaes32esmi(rs1, rs2, 2);
    default: return __builtin_riscv_xaes32esmi(rs1, rs2, 3);
    }
}

// Final-round variant: identical dispatch pattern; lowers to xaes32esi.
static inline uint32_t aes32esi(uint32_t rs1, uint32_t rs2, int bs) {
    switch (bs & 0x3) {
    case 0:  return __builtin_riscv_xaes32esi(rs1, rs2, 0);
    case 1:  return __builtin_riscv_xaes32esi(rs1, rs2, 1);
    case 2:  return __builtin_riscv_xaes32esi(rs1, rs2, 2);
    default: return __builtin_riscv_xaes32esi(rs1, rs2, 3);
    }
}

/*
 * XAesKeyExp: AES-128 key schedule on a hidden 128-bit key register.
 *
 *   aesksld(w, widx) : key_reg[widx] = w     (seed a cipher-key word)
 *   aeskse()         : key_reg = KeyExpand(key_reg) (advance one round key)
 *   aesksrd(widx)    : returns key_reg[widx] (read a round-key word)
 *
 * A seed load resets the internal round counter; each aeskse() consumes the
 * next Rcon and advances, so round keys must be generated strictly in order
 * (round 1..10). `widx` must be a compile-time constant in {0,1,2,3}; the
 * switch dispatches a runtime widx to a literal call to satisfy the builtin's
 * constant-argument check, and collapses to one call for a constant widx.
 * Requires -march=...xaeskeyexp (set in config/rv32-standard.conf).
 */
static inline void aesksld(uint32_t w, int widx) {
    switch (widx & 0x3) {
    case 0:  __builtin_riscv_xaesksld(w, 0); break;
    case 1:  __builtin_riscv_xaesksld(w, 1); break;
    case 2:  __builtin_riscv_xaesksld(w, 2); break;
    default: __builtin_riscv_xaesksld(w, 3); break;
    }
}

static inline void aeskse(void) {
    __builtin_riscv_xaeskse();
}

static inline uint32_t aesksrd(int widx) {
    switch (widx & 0x3) {
    case 0:  return __builtin_riscv_xaesksrd(0);
    case 1:  return __builtin_riscv_xaesksrd(1);
    case 2:  return __builtin_riscv_xaesksrd(2);
    default: return __builtin_riscv_xaesksrd(3);
    }
}

#endif
