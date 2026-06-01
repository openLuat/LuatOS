/*
 * nfs_ecc.h — Software Hamming ECC for NFS
 */

#ifndef NFS_ECC_H
#define NFS_ECC_H

#include "../inc/nfs_types.h"

/*-------------------------------------------------------------------
 *  ECC for arbitrary-length data (used for packed tags)
 *-------------------------------------------------------------------*/

typedef struct {
    nfs_u8   col_parity;
    nfs_u32  line_parity;
    nfs_u32  line_parity_prime;
} nfs_ecc_other_t;

/**
 * nfs_ecc_calc_other — calculate parity over n_bytes of data
 */
void nfs_ecc_calc_other(const nfs_u8 *data, nfs_u32 n_bytes,
                        nfs_ecc_other_t *ecc);

/**
 * nfs_ecc_correct_other — verify and correct up to 1 bit
 * @data:      data buffer to correct in-place
 * @read_ecc:  ECC as read from storage (will be corrected if needed)
 * @calc_ecc:  freshly calculated ECC
 * Return: 0=no error, 1=corrected, -1=uncorrectable
 */
int nfs_ecc_correct_other(nfs_u8 *data, nfs_u32 n_bytes,
                          nfs_ecc_other_t *read_ecc,
                          const nfs_ecc_other_t *calc_ecc);

#endif /* NFS_ECC_H */
