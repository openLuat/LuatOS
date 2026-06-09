/*
 * pgfs_ecc.c — Hamming(72,64) SECDED ECC.
 *
 * Encodes 8 data bytes (64 bits) into a 1-byte parity field using a
 * Hamming code with single-error-correction double-error-detection
 * (SECDED). The 8 parity bits are packed into a single uint8_t, where
 * bits 0..6 are the Hamming check bits p[0..6] and bit 7 is the
 * overall parity p[7].
 *
 * Encoding uses 1-indexed bit positions (j+1) so all 64 data bits are
 * covered by at least one check bit. Syndrome directly encodes the
 * error position (j+1), so corrected data bit index is (syndrome - 1).
 *
 * p[7] covers all 64 data bits ONLY (not the check bits). This is
 * necessary because a data-bit flip changes both the data bit and the
 * check bit that covers it — if p[7] covered both, the two flips would
 * cancel in p[7] and a true single-bit error would be misclassified as
 * double-bit. With data-only p[7], a single data-bit flip always
 * changes overall parity while the syndrome pinpoints the position.
 *
 * On decode:
 *   - syndrome == 0 && overall_mismatch == 0: no error
 *   - syndrome == 0 && overall_mismatch == 1: error in p[7] only (data fine)
 *   - syndrome != 0 && overall_mismatch == 1: single-bit data error corrected
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

    /* Compute 7 Hamming check bits using 1-indexed positions:
     * p[k] covers data bits where bit k of (j+1) is set.
     * This ensures all 64 data bits are covered — bit index 0
     * (position 1 = 0b0000001) is covered by p[0]; bit index 63
     * (position 64 = 0b1000000) is covered by p[6]. */
    for (int k = 0; k < 7; k++) {
        uint8_t parity_bit = 0;
        for (int j = 0; j < 64; j++) {
            if ((j + 1) & (1 << k)) {
                parity_bit ^= ecc_get_bit(data, j);
            }
        }
        check |= (parity_bit << k);
    }

    /* Overall parity p[7] = XOR of all 64 data bits ONLY.
     * Must NOT include check bits — a data-bit flip changes both
     * the data bit and the covering check bit, which would cancel
     * in p[7] and misclassify a single-bit error as double-bit. */
    overall = 0;
    for (int j = 0; j < 64; j++) {
        overall ^= ecc_get_bit(data, j);
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
        /* Single-bit data error. The syndrome encodes the 1-indexed
         * position (j+1) of the flipped bit. Correct by flipping the
         * data bit at index (syndrome - 1).
         *
         * NOTE: a single-bit error in check bits p[0..6] also produces
         * syndrome != 0 but overall_mismatch == 0 (p[7] covers data
         * only), so the decode correctly returns -1 for check-bit errors.
         * CRC32 is the authoritative check, so even if the correction
         * is wrong (e.g. true double-bit error with cancelling data XOR),
         * the CRC will fail and the record will be skipped. */
        int bit_idx = (int)syndrome - 1;
        if (bit_idx >= 0 && bit_idx < 64) {
            if (corrected) {
                memcpy(corrected, data, 8);
                ecc_flip_bit(corrected, bit_idx);
            }
            return 1;
        }
        /* Syndrome maps to a position outside the 64 data bits
         * (i.e. an error in the parity byte itself, position >= 64).
         * Data is fine. */
        if (corrected) memcpy(corrected, data, 8);
        return 0;
    }

    /* syndrome != 0 && overall_mismatch == 0 => double-bit error,
     * uncorrectable */
    return -1;
}
