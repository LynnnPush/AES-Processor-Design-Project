#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "aes_intrinsics.h"

// S-box for SubBytes (precomputed substitution table)
static const uint8_t sbox[256] = {
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16
};

// Round constants for key expansion
static const uint8_t rcon[10] = {
    0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

// Key expansion function
void expand_key(uint8_t *key, uint8_t *round_keys) {
    int i;
    for (i = 0; i < 16; i++) {
        round_keys[i] = key[i];
    }
    for (i = 16; i < 176; i += 4) {
        uint8_t temp[4];
        temp[0] = round_keys[i - 4];
        temp[1] = round_keys[i - 3];
        temp[2] = round_keys[i - 2];
        temp[3] = round_keys[i - 1];
        if (i % 16 == 0) {
            uint8_t t = temp[0];
            temp[0] = sbox[temp[1]];
            temp[1] = sbox[temp[2]];
            temp[2] = sbox[temp[3]];
            temp[3] = sbox[t];
            temp[0] ^= rcon[(i / 16) - 1];
        }
        round_keys[i]     = round_keys[i - 16] ^ temp[0];
        round_keys[i + 1] = round_keys[i - 15] ^ temp[1];
        round_keys[i + 2] = round_keys[i - 14] ^ temp[2];
        round_keys[i + 3] = round_keys[i - 13] ^ temp[3];
    }
}

// SubBytes transformation
void sub_bytes(uint8_t *state) {
    for (int i = 0; i < 16; i++) {
        state[i] = sbox[state[i]];
    }
}

// ShiftRows transformation
void shift_rows(uint8_t *state) {
    uint8_t temp;
    temp = state[1]; state[1] = state[5]; state[5] = state[9]; state[9] = state[13]; state[13] = temp;
    temp = state[2]; state[2] = state[10]; state[10] = temp;
    temp = state[6]; state[6] = state[14]; state[14] = temp;
    temp = state[15]; state[15] = state[11]; state[11] = state[7]; state[7] = state[3]; state[3] = temp;
}

// GF(2^8) multiplication
uint8_t gf_mult(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        if (b & 1) p ^= a;
        uint8_t hi_bit = a & 0x80;
        a <<= 1;
        if (hi_bit) a ^= 0x1b; // Reduce modulo 0x11b
        b >>= 1;
    }
    return p;
}

// MixColumns transformation
void mix_columns(uint8_t *state) {
    uint8_t temp[16];
    for (int i = 0; i < 4; i++) {
        int idx = i * 4;
        temp[idx]     = gf_mult(0x02, state[idx]) ^ gf_mult(0x03, state[idx + 1]) ^ state[idx + 2] ^ state[idx + 3];
        temp[idx + 1] = state[idx] ^ gf_mult(0x02, state[idx + 1]) ^ gf_mult(0x03, state[idx + 2]) ^ state[idx + 3];
        temp[idx + 2] = state[idx] ^ state[idx + 1] ^ gf_mult(0x02, state[idx + 2]) ^ gf_mult(0x03, state[idx + 3]);
        temp[idx + 3] = gf_mult(0x03, state[idx]) ^ state[idx + 1] ^ state[idx + 2] ^ gf_mult(0x02, state[idx + 3]);
    }
    for (int i = 0; i < 16; i++) {
        state[i] = temp[i];
    }
}

// AddRoundKey transformation
void add_round_key(uint8_t *state, uint8_t *round_key) {
    for (int i = 0; i < 16; i++) {
        state[i] ^= round_key[i];
    }
}

// Fused SubBytes + ShiftRows + MixColumns + AddRoundKey via aes32esmi.
// For each output column c, acc is seeded with round_key[c] and four chained
// aes32esmi calls XOR in the row-0..row-3 contributions taken from input
// columns (c+0..c+3) mod 4 - the (c+r) mod 4 index pattern is exactly the
// ShiftRows permutation.
void aes_inner_round(uint8_t *state, uint8_t *rk) {
    uint32_t *w  = (uint32_t *)state;
    uint32_t *kw = (uint32_t *)rk;
    uint32_t in0 = w[0], in1 = w[1], in2 = w[2], in3 = w[3];
    uint32_t c0, c1, c2, c3;

    // Column 0: rows from input columns 0,1,2,3
    c0 = kw[0];
    c0 = aes32esmi(c0, in0, 0);
    c0 = aes32esmi(c0, in1, 1);
    c0 = aes32esmi(c0, in2, 2);
    c0 = aes32esmi(c0, in3, 3);

    // Column 1: rows from input columns 1,2,3,0
    c1 = kw[1];
    c1 = aes32esmi(c1, in1, 0);
    c1 = aes32esmi(c1, in2, 1);
    c1 = aes32esmi(c1, in3, 2);
    c1 = aes32esmi(c1, in0, 3);

    // Column 2: rows from input columns 2,3,0,1
    c2 = kw[2];
    c2 = aes32esmi(c2, in2, 0);
    c2 = aes32esmi(c2, in3, 1);
    c2 = aes32esmi(c2, in0, 2);
    c2 = aes32esmi(c2, in1, 3);

    // Column 3: rows from input columns 3,0,1,2
    c3 = kw[3];
    c3 = aes32esmi(c3, in3, 0);
    c3 = aes32esmi(c3, in0, 1);
    c3 = aes32esmi(c3, in1, 2);
    c3 = aes32esmi(c3, in2, 3);

    w[0] = c0; w[1] = c1; w[2] = c2; w[3] = c3;
}

// Fused SubBytes + ShiftRows + AddRoundKey via aes32esi (final round, no MixCol).
// Same (c+r) mod 4 ShiftRows pattern as aes_inner_round; differs only in that
// aes32esi places the sbox byte directly (no MixColumns mix) at byte position bs.
void aes_final_round(uint8_t *state, uint8_t *rk) {
    uint32_t *w  = (uint32_t *)state;
    uint32_t *kw = (uint32_t *)rk;
    uint32_t in0 = w[0], in1 = w[1], in2 = w[2], in3 = w[3];
    uint32_t c0, c1, c2, c3;

    c0 = kw[0];
    c0 = aes32esi(c0, in0, 0);
    c0 = aes32esi(c0, in1, 1);
    c0 = aes32esi(c0, in2, 2);
    c0 = aes32esi(c0, in3, 3);

    c1 = kw[1];
    c1 = aes32esi(c1, in1, 0);
    c1 = aes32esi(c1, in2, 1);
    c1 = aes32esi(c1, in3, 2);
    c1 = aes32esi(c1, in0, 3);

    c2 = kw[2];
    c2 = aes32esi(c2, in2, 0);
    c2 = aes32esi(c2, in3, 1);
    c2 = aes32esi(c2, in0, 2);
    c2 = aes32esi(c2, in1, 3);

    c3 = kw[3];
    c3 = aes32esi(c3, in3, 0);
    c3 = aes32esi(c3, in0, 1);
    c3 = aes32esi(c3, in1, 2);
    c3 = aes32esi(c3, in2, 3);

    w[0] = c0; w[1] = c1; w[2] = c2; w[3] = c3;
}

// Single block AES-128 encryption
void aes128_encrypt_block(uint8_t *plaintext, uint8_t *round_keys, uint8_t *ciphertext) {
    uint8_t state[16];
    memcpy(state, plaintext, 16);

    // Initial round
    add_round_key(state, round_keys);

    // Main rounds (1 to 9) - fused via aes32esmi:
    //   SubBytes + ShiftRows + MixColumns + AddRoundKey  ->  one chained step
    // Fully unrolled by the LLVM loop-unrolling pass: the trip count is a
    // compile-time constant (9), so unroll(full) flattens the loop and
    // removes the round-counter increment and back-edge branch entirely.
    #pragma clang loop unroll(full)
    for (int round = 1; round < 10; round++) {
        aes_inner_round(state, &round_keys[round * 16]);
    }

    // Final round (10) - fused via aes32esi:
    //   SubBytes + ShiftRows + AddRoundKey  ->  one chained step (no MixCol)
    aes_final_round(state, &round_keys[10 * 16]);

    memcpy(ciphertext, state, 16);
}

// AES-128 ECB encryption (no padding)
void aes128_ecb_encrypt(uint8_t *plaintext, size_t len, uint8_t *key, uint8_t *ciphertext) {
    if (len % 16 != 0) {
        //printf("Error: Input length must be a multiple of 16 bytes (no padding).\n");
        return;
    }

    uint8_t round_keys[176];
    expand_key(key, round_keys);

    for (size_t i = 0; i < len; i += 16) {
        aes128_encrypt_block(&plaintext[i], round_keys, &ciphertext[i]);
    }
}

void write_to_address(uintptr_t addr, uint32_t value) {
    *(volatile uint32_t *)addr = value;
}

void write_v_to_address(uintptr_t addr, uint8_t vector[16]) {
    uint32_t *vector_word = (uint32_t *)vector;
	for(int i = 0; i < 4; i++) {
        write_to_address(addr + i*0x4, vector_word[i]);
    }
}

int main()
{
	// Plaintext: "Hello, World!000" (16 bytes, 1 block)
    uint8_t plaintext[16] = {
        'H', 'e', 'l', 'l', 'o', ',', ' ', 'W',
        'o', 'r', 'l', 'd', '!', '0', '0', '0'
    };
    // Key: "cese4040password" (16 bytes)
    uint8_t key[16] = {
        'c', 'e', 's', 'e', '4', '0', '4', '0',
        'p', 'a', 's', 's', 'w', 'o', 'r', 'd'
    };
    uint8_t expected_output[16] = {0x14, 0x09, 0xA5, 0xFB, 0x1F, 0xF4, 0x4B, 0x71, 0xBE, 0xAA, 0x25, 0x2E, 0x0F, 0x08, 0xF9, 0xAA};
    uint8_t ciphertext[16];
    size_t len = 16; // Single block

    uintptr_t addr;
    uint32_t value;

    aes128_ecb_encrypt(plaintext, len, key, ciphertext);

    addr = 0x0100000 + 0x2000 + 0x30;
    write_v_to_address(addr, expected_output);
    
    addr = 0x0100000 + 0x2000 + 0x40;
    write_v_to_address(addr, ciphertext);

    // Check if calculated and expected match:
    addr = 0x0100000 + 0x2000 + 0x04;  // Some memory-mapped register or memory location
    value = 0xCAFEBABE; //Assume arrays match initially
    for (int i = 0; i < 16; i++) {
        if (ciphertext[i] != expected_output[i]) {
            value = 0xBAAAAAAD; // Set to false value if there's a mismatch
            break;
        }
    }
    write_to_address(addr, value);

    //END OF TEST WRITE (used to identify when the execution of the C code finished): DO NOT REMOVE!
    addr = 0x0100000 + 0x2000; // SRAM base address is 0x0100000.
    value = 0xDEADBEEF;
    write_to_address(addr, value);

    return 0;
}
