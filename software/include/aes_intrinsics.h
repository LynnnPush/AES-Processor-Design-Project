#ifndef AES_INTRINSICS_H
#define AES_INTRINSICS_H

#include <stdint.h>

/*
<<<<<<< HEAD
 * Inline-asm wrapper for the RISC-V scalar-crypto (Zkne) instruction:
 *
 *   aes32esmi rd, rs1, rs2, bs
 *
 * Encoding (R-type under OPCODE_OP):
 *   bs[1:0] | 5'b10011 | rs2 | rs1 | 3'b000 | rd | 7'b0110011
 *
 * Semantics:
 *   rd = rs1 ^ rot_left( MixCol_fwd( SBox( (rs2 >> (bs*8)) & 0xFF ) ),
 *                        bs * 8 )
 *
 * bs must be a compile-time constant in {0,1,2,3}. The instruction is
 * emitted via `.insn r` so no toolchain modification is needed.
 * funct7 = (bs << 5) | 0x13 carries bs in its top two bits and the
 * Zkne funct5 5'b10011 in its low five bits.
 */

#define AES32ESMI(rd, rs1, rs2, bs)                                            \
    __asm__ volatile(                                                          \
        ".insn r 0x33, 0x0, %3, %0, %1, %2"                                    \
        : "=r"(rd)                                                             \
        : "r"(rs1), "r"(rs2), "i"(((bs) << 5) | 0x13))

static inline uint32_t aes32esmi(uint32_t rs1, uint32_t rs2, int bs) {
    uint32_t rd;
    switch (bs & 0x3) {
        case 0: AES32ESMI(rd, rs1, rs2, 0); break;
        case 1: AES32ESMI(rd, rs1, rs2, 1); break;
        case 2: AES32ESMI(rd, rs1, rs2, 2); break;
        default: AES32ESMI(rd, rs1, rs2, 3); break;
    }
    return rd;
=======
 * RISC-V scalar-crypto-style aes32esmi instruction implemented on the
 * project-10 riscy core, exposed as a clang builtin via the custom
 * XAes32esmi extension added to our local LLVM tree.
 *
 *   xaes32esmi rd, rs1, rs2, bs
 *
 * Semantics (matches Zkne aes32esmi spec):
 *   rd = rs1 ^ rot_left(MixCol_fwd(SBox((rs2 >> (bs*8)) & 0xFF)), bs * 8)
 *
 * Encoding matches standard aes32esmi (funct5=0b10011, OPC_OP, funct3=0,
 * bs in Inst[31:30]). Requires building with
 * -march=rv32imac_zicsr_xaes32esmi (set in config/rv32-standard.conf).
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
>>>>>>> c604b1b (Initial commit with Path B xaes32esmi LLVM builtin)
}

#endif
