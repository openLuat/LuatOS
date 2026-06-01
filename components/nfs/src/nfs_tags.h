/*
 * nfs_tags.h — Packed-tags2 encode/decode for NFS
 *
 * Each NAND page spare area stores:
 *   - 4-byte packed tags (seq, obj_id, chunk_id, n_bytes) packed
 *     into a nfs_packed_tags2_t struct
 *   - optional 3-byte ECC covering the packed tags
 *
 * Object-header chunks (chunk_id == 0) may carry extra fields
 * packed into the chunk_id word (upper bits).
 */

#ifndef NFS_TAGS_H
#define NFS_TAGS_H

#include "../inc/nfs_types.h"
#include "nfs_dev.h"
#include "nfs_ecc.h"

/*-------------------------------------------------------------------
 *  On-NAND packed-tags2 layout (16 bytes total)
 *-------------------------------------------------------------------*/

typedef struct {
    nfs_u32 seq_number;     /* block sequence number             */
    nfs_u32 obj_id;         /* object ID  (30 bits + flags)      */
    nfs_u32 chunk_id;       /* chunk ID   (30 bits + extra flags)*/
    nfs_u16 n_bytes;        /* data bytes in this chunk          */
} nfs_packed_tags2_tags_only_t;

typedef struct {
    nfs_packed_tags2_tags_only_t t;
    nfs_ecc_other_t              ecc;
} nfs_packed_tags2_t;

/* Flags packed into obj_id upper bits */
#define NFS_EXTRA_HEADER_INFO_FLAG  0x80000000u
#define NFS_EXTRA_SHRINK_FLAG       0x00000001u
#define NFS_EXTRA_SHADOWS_FLAG      0x00000002u
#define NFS_EXTRA_SPARE_1           0x00000004u
#define NFS_ALL_EXTRA_FLAGS         0x00000007u

/* Field widths/shifts within packed chunk_id word when extra info present */
#define NFS_EXTRA_OBJECT_TYPE_SHIFT 28
#define NFS_EXTRA_OBJECT_TYPE_MASK  0x0fu

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * nfs_tags_pack — encode extended tags to packed tags + ECC
 * @dev:  device (needed for config flags)
 * @ext:  source extended tags
 * @pt:   destination packed-tags2 struct
 */
void nfs_tags_pack(const nfs_dev_t *dev,
                   const nfs_ext_tags_t *ext,
                   nfs_packed_tags2_t   *pt);

/**
 * nfs_tags_unpack — decode packed tags to extended tags
 * @dev:  device (needed for config flags)
 * @pt:   source packed-tags2 struct
 * @ext:  destination extended tags (always fully populated)
 */
void nfs_tags_unpack(const nfs_dev_t      *dev,
                     const nfs_packed_tags2_t *pt,
                     nfs_ext_tags_t       *ext);

/**
 * nfs_tags_verify_ecc — verify ECC on a packed tags struct
 * @pt:      packed tags as read from NAND
 * @no_ecc:  1 if the device is configured without tags ECC
 * Return: NFS_ECC_RESULT_NO_ERROR / _FIXED / _UNFIXED / _NOT_CHECKED
 */
nfs_ecc_result_t nfs_tags_verify_ecc(nfs_packed_tags2_t *pt, int no_ecc);

/**
 * nfs_tags_is_erased — return 1 if the tags represent an erased page
 */
int nfs_tags_is_erased(const nfs_packed_tags2_t *pt);

#endif /* NFS_TAGS_H */
