/*
 * tfs_ecc.h — Software Hamming ECC for TFS
 */

#ifndef TFS_ECC_H
#define TFS_ECC_H

#include "../inc/tfs_types.h"

/*-------------------------------------------------------------------
 *  ECC for arbitrary-length data (used for packed tags)
 *-------------------------------------------------------------------*/

typedef struct {
    uint8_t   col_parity;
    uint32_t  line_parity;
    uint32_t  line_parity_prime;
} tfs_ecc_other_t;

/**
 * tfs_ecc_calc_other — calculate parity over n_bytes of data
 */
void tfs_ecc_calc_other(const uint8_t *data, uint32_t n_bytes,
                        tfs_ecc_other_t *ecc);

/**
 * tfs_ecc_correct_other — verify and correct up to 1 bit
 * @data:      data buffer to correct in-place
 * @read_ecc:  ECC as read from storage (will be corrected if needed)
 * @calc_ecc:  freshly calculated ECC
 * Return: 0=no error, 1=corrected, -1=uncorrectable
 */
int tfs_ecc_correct_other(uint8_t *data, uint32_t n_bytes,
                          tfs_ecc_other_t *read_ecc,
                          const tfs_ecc_other_t *calc_ecc);

#endif /* TFS_ECC_H */
