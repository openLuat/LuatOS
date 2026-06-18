/*
 * tfs_tags.h — Packed-tags2 encode/decode for TFS
 *
 * Each NAND page spare area stores:
 *   - 4-byte packed tags (seq, obj_id, chunk_id, n_bytes) packed
 *     into a tfs_packed_tags2_t struct
 *   - optional 3-byte ECC covering the packed tags
 *
 * Object-header chunks (chunk_id == 0) may carry extra fields
 * packed into the chunk_id word (upper bits).
 */

#ifndef TFS_TAGS_H
#define TFS_TAGS_H

#include "../inc/tfs_types.h"
#include "tfs_dev.h"
#include "tfs_ecc.h"

/*-------------------------------------------------------------------
 *  On-NAND packed-tags2 layout (16 bytes total)
 *-------------------------------------------------------------------*/

typedef struct {
    uint32_t seq_number;     /* block sequence number             */
    uint32_t obj_id;         /* object ID  (30 bits + flags)      */
    uint32_t chunk_id;       /* chunk ID   (30 bits + extra flags)*/
    uint16_t n_bytes;        /* data bytes in this chunk          */
} tfs_packed_tags2_tags_only_t;

typedef struct {
    tfs_packed_tags2_tags_only_t t;
    tfs_ecc_other_t              ecc;
} tfs_packed_tags2_t;

/* Flags packed into obj_id upper bits */
#define TFS_EXTRA_HEADER_INFO_FLAG  0x80000000u
#define TFS_EXTRA_SHRINK_FLAG       0x00000001u
#define TFS_EXTRA_SHADOWS_FLAG      0x00000002u
#define TFS_EXTRA_SPARE_1           0x00000004u
#define TFS_ALL_EXTRA_FLAGS         0x00000007u

/* Field widths/shifts within packed chunk_id word when extra info present */
#define TFS_EXTRA_OBJECT_TYPE_SHIFT 28
#define TFS_EXTRA_OBJECT_TYPE_MASK  0x07u

/*-------------------------------------------------------------------
 *  API
 *-------------------------------------------------------------------*/

/**
 * tfs_tags_pack — encode extended tags to packed tags + ECC
 * @dev:  device (needed for config flags)
 * @ext:  source extended tags
 * @pt:   destination packed-tags2 struct
 */
void tfs_tags_pack(const tfs_dev_t *dev,
                   const tfs_ext_tags_t *ext,
                   tfs_packed_tags2_t   *pt);

/**
 * tfs_tags_unpack — decode packed tags to extended tags
 * @dev:  device (needed for config flags)
 * @pt:   source packed-tags2 struct
 * @ext:  destination extended tags (always fully populated)
 */
void tfs_tags_unpack(const tfs_dev_t      *dev,
                     const tfs_packed_tags2_t *pt,
                     tfs_ext_tags_t       *ext);

/**
 * tfs_tags_verify_ecc — verify ECC on a packed tags struct
 * @pt:      packed tags as read from NAND
 * @no_ecc:  1 if the device is configured without tags ECC
 * Return: TFS_ECC_RESULT_NO_ERROR / _FIXED / _UNFIXED / _NOT_CHECKED
 */
tfs_ecc_result_t tfs_tags_verify_ecc(tfs_packed_tags2_t *pt, int no_ecc);

/**
 * tfs_tags_is_erased — return 1 if the tags represent an erased page
 */
int tfs_tags_is_erased(const tfs_packed_tags2_t *pt);

#endif /* TFS_TAGS_H */
