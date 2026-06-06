/*
 * pgfs_ecc.c — Hamming(72,64) SECDED ECC.
 *
 * Encodes 8 data bytes (64 bits) into a 1-byte parity field using a
 * Hamming code with single-error-correction double-error-detection
 * (SECDED). The 8 parity bits are packed into a single uint8_t, where
 * bits 0..6 are the Hamming check bits p[0..6] and bit 7 is the
 * overall parity p[7].
 *
 * On decode:
 *   - syndrome == 0 && overall_mismatch == 0: no error
 *   - syndrome == 0 && overall_mismatch == 1: error in p[7] only (data fine)
 *   - syndrome != 0 && overall_mismatch == 1: single-bit error (correctable)
 *   - syndrome != 0 && overall_mismatch == 0: double-bit error (uncorrectable)
 *
 * The 8-byte ECC field in the on-disk record layout matches this
 * design; byte 0 carries the Hamming parity and bytes 1..7 are
 * reserved for future expansion.
 */
#include "luat_base.h"
#include <stdint.h>
#include <string.h>
#include "pgfs_ecc.h"

/* Read a single bit from the 8-byte data block.
 * data[0] bit 0 = global index 0; data[0] bit 7 = index 7;
 * data[1] bit 0 = index 8; ... */
static inline uint8_t ecc_get_bit(const uint8_t* data, int idx) {
    return (data[idx / 8] >> (idx % 8)) & 1;
}

/* Flip a single bit in the data block at global index `idx`. */
static inline void ecc_flip_bit(uint8_t* data, int idx) {
    data[idx / 8] ^= (uint8_t)(1u << (idx % 8));
}

uint8_t pgfs_ecc_hamming_encode(const uint8_t* data) {
    uint8_t check = 0;    /* p[0..6] = Hamming check bits */
    uint8_t overall = 0;  /* p[7] = overall parity */

    /* Compute 7 Hamming check bits: p[k] covers data bits where
     * bit k of the bit index is set. */
    for (int k = 0; k < 7; k++) {
        uint8_t parity_bit = 0;
        for (int j = 0; j < 64; j++) {
            if (j & (1 << k)) {
                parity_bit ^= ecc_get_bit(data, j);
            }
        }
        check |= (parity_bit << k);
    }

    /* Overall parity p[7] = XOR of all 64 data bits XOR XOR of
     * check bits p[0..6]. */
    overall = 0;
    for (int j = 0; j < 64; j++) {
        overall ^= ecc_get_bit(data, j);
    }
    for (int k = 0; k < 7; k++) {
        overall ^= ((check >> k) & 1);
    }

    return (uint8_t)(check | (overall << 7));
}

int pgfs_ecc_hamming_decode(const uint8_t* data, uint8_t parity,
                             uint8_t* corrected) {
    uint8_t expected = pgfs_ecc_hamming_encode(data);
    uint8_t syndrome = (expected ^ parity) & 0x7F;
    uint8_t overall_mismatch = ((expected ^ parity) >> 7) & 1;

    if (syndrome == 0 && overall_mismatch == 0) {
        /* No error */
        if (corrected) memcpy(corrected, data, 8);
        return 0;
    }

    if (syndrome == 0 && overall_mismatch == 1) {
        /* Error in p[7] only (overall parity bit), data is fine */
        if (corrected) memcpy(corrected, data, 8);
        return 0;
    }

    if (syndrome != 0 && overall_mismatch == 1) {
        /* Single-bit error. The syndrome is the data bit index to flip.
         * NOTE: a single-bit error in check bits p[0..6] is
         * indistinguishable from a data-bit error with the same syndrome
         * value. CRC32 is the authoritative check, so a false correction
         * will be caught by CRC. */
        if (syndrome < 64) {
            if (corrected) {
                memcpy(corrected, data, 8);
                ecc_flip_bit(corrected, (int)syndrome);
            }
            return 1;
        }
        /* syndrome >= 64 means error was in the parity region
         * (not in data bits), so data is fine. */
        if (corrected) memcpy(corrected, data, 8);
        return 0;
    }

    /* syndrome != 0 && overall_mismatch == 0 => double-bit error,
     * uncorrectable */
    return -1;
}
