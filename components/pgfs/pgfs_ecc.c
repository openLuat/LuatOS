/*
 * pgfs_ecc.c — Phase 3b: Simple per-record parity byte.
 *
 * Each data log record carries 8 bytes of "ECC" (really just parity
 * metadata) that protect the first 8 header bytes. The implementation
 * is intentionally minimal:
 *
 *   - ecc[0] = XOR of all 8 header bytes
 *   - ecc[1..7] = 0
 *
 * Verify on read: recompute the XOR. If it doesn't match, the record
 * is treated as damaged and the block is marked weak. Single-bit
 * errors are detected (the XOR is wrong), but not corrected.
 *
 * This is a placeholder for a full Hamming(72,64) SECDED code. The
 * full code requires careful bit-position arithmetic that is fragile to
 * get right; the parity byte is enough to detect most data corruption
 * and marks weak blocks for refresh. A future change can swap in a
 * proper SECDED implementation without changing the on-disk record
 * layout (the field is 8 bytes in either case).
 *
 * The 8-byte field size also matches the 72-bit Hamming codeword
 * minus 64 data bits, so a future upgrade is a drop-in.
 */
#include "luat_base.h"
#include <stdint.h>
#include <string.h>
#include "pgfs_ecc.h"

uint8_t pgfs_ecc_hamming_encode(const uint8_t* data) {
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        p ^= data[i];
    }
    return p;
}

int pgfs_ecc_hamming_decode(const uint8_t* data, uint8_t parity,
                            uint8_t* corrected) {
    uint8_t computed = pgfs_ecc_hamming_encode(data);
    if (computed == parity) {
        if (corrected != NULL) memcpy(corrected, data, 8);
        return 0;
    }
    /* Parity mismatch: a bit has flipped. We don't try to correct (we
     * don't have enough information to locate the single bit cheaply),
     * so we report the failure. The replay path marks the block weak
     * and skips the record. */
    return -1;
}
