/*
 * pgfs_ecc.h — Phase 3b: Hamming(72,64) SECDED ECC API.
 *
 * Encodes 8 data bytes into 1 parity byte (Hamming code), and decodes
 * back. The 72-bit codeword is laid out as 64 data bits (LSB-first,
 * bytes 0..7 of `data`) plus 8 parity bits packed in a uint8_t.
 */
#ifndef PGFS_ECC_H
#define PGFS_ECC_H

#include <stdint.h>

/* Compute the 8-bit parity for an 8-byte data block. */
uint8_t pgfs_ecc_hamming_encode(const uint8_t* data);

/* Verify and (if possible) correct a data block. The parity byte is
 * the one written alongside the data. Writes the corrected data to
 * `corrected` (8 bytes) if non-NULL. Return value:
 *    0 : no error (or single-bit error in p7 itself, ignored)
 *    1 : single-bit data error corrected
 *   -1 : double-bit error (uncorrectable) */
int pgfs_ecc_hamming_decode(const uint8_t* data, uint8_t parity,
                            uint8_t* corrected);

#endif /* PGFS_ECC_H */
