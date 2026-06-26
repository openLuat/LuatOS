/*
 * tfs_tags.c — Packed-tags2 encode / decode for TFS
 *
 * Ported from yaffs_packedtags2.c (YAFFS2).
 *
 * On-NAND representation (all little-endian):
 *
 *   Byte  0.. 3  seq_number
 *   Byte  4.. 7  obj_id  (lower 30 bits obj_id; upper 2 bits: extra flags)
 *   Byte  8..11  chunk_id
 *     Normal data chunk:  [29:0]=chunk_id,  [31:30]=0
 *     Header chunk with extra info carried:
 *       bit31 = TFS_EXTRA_HEADER_INFO_FLAG
 *       [30:28] = object_type
 *       [27:0]  = parent_obj_id (or file_size_hi for files)
 *   Byte 12..13  n_bytes (0xffff for a full chunk)
 *   Byte 14..16  ECC (3 bytes, column+line parity over bytes 0..11)
 *
 * TFS_MAX_OBJ_ID and chunk_id are guaranteed < 2^30 by design.
 */

#include "tfs_tags.h"
#include "../inc/tfs_config.h"

#include <string.h>

/*-------------------------------------------------------------------
 * Helpers
 *-------------------------------------------------------------------*/

static void calc_tags_ecc(tfs_packed_tags2_t *pt)
{
    tfs_ecc_calc_other((const uint8_t *)&pt->t,
                       sizeof(pt->t),
                       &pt->ecc);
}

/*-------------------------------------------------------------------
 * tfs_tags_pack
 *-------------------------------------------------------------------*/

void tfs_tags_pack(const tfs_dev_t *dev,
                   const tfs_ext_tags_t *ext,
                   tfs_packed_tags2_t   *pt)
{
    (void)dev;

    /* Start clean */
    memset(pt, 0xff, sizeof(*pt));

    if (!ext->chunk_used) {
        /* Erased / unused chunk — leave all 0xff */
        return;
    }

    /* seq_number */
    pt->t.seq_number = ext->seq_number;

    /* obj_id: lower 30 bits */
    pt->t.obj_id = ext->obj_id & 0x3fffffffu;

    /* n_bytes: 0xffff = full chunk */
    pt->t.n_bytes = (uint16_t)ext->n_bytes;

    /* chunk_id: normal data or header with extra */
    if (ext->chunk_id == 0 && ext->extra_available) {
        /* Carry extra object-header info inside chunk_id word */
        uint32_t x = TFS_EXTRA_HEADER_INFO_FLAG;

        x |= (uint32_t)(ext->extra_obj_type & TFS_EXTRA_OBJECT_TYPE_MASK)
             << TFS_EXTRA_OBJECT_TYPE_SHIFT;

        if (ext->extra_obj_type == TFS_OBJ_TYPE_FILE) {
            /* Store the high 28 bits of file_size in [27:0] */
            x |= (uint32_t)(ext->extra_file_size >> 2) & 0x0fffffffu;
            /* Store low 2 bits in obj_id bits 30..31 */
            pt->t.obj_id |= (uint32_t)(ext->extra_file_size & 3u) << 30;
        } else {
            x |= ext->extra_parent_id & 0x0fffffffu;
            if (ext->extra_is_shrink)
                pt->t.obj_id |= TFS_EXTRA_SHRINK_FLAG << 30;
            if (ext->extra_shadows)
                pt->t.obj_id |= TFS_EXTRA_SHADOWS_FLAG << 30;
        }

        pt->t.chunk_id = x;
    } else {
        pt->t.chunk_id = ext->chunk_id & 0x3fffffffu;
    }

    if (!dev->param.no_tags_ecc)
        calc_tags_ecc(pt);
}

/*-------------------------------------------------------------------
 * tfs_tags_unpack
 *-------------------------------------------------------------------*/

void tfs_tags_unpack(const tfs_dev_t      *dev,
                     const tfs_packed_tags2_t *pt,
                     tfs_ext_tags_t       *ext)
{
    (void)dev;

    memset(ext, 0, sizeof(*ext));

    if (tfs_tags_is_erased(pt)) {
        return;  /* chunk_used stays 0 */
    }

    ext->chunk_used = 1;
    ext->seq_number = pt->t.seq_number;
    ext->n_bytes    = pt->t.n_bytes;

    /* Decode chunk_id / extra info */
    if (pt->t.chunk_id & TFS_EXTRA_HEADER_INFO_FLAG) {
        /* Extra object-header info is embedded */
        uint32_t x = pt->t.chunk_id;

        ext->chunk_id        = 0;
        ext->extra_available = 1;
        ext->extra_obj_type  = (tfs_obj_type_t)
                               ((x >> TFS_EXTRA_OBJECT_TYPE_SHIFT)
                                & TFS_EXTRA_OBJECT_TYPE_MASK);
        ext->extra_is_shrink = (pt->t.obj_id >> 30) & TFS_EXTRA_SHRINK_FLAG;
        ext->extra_shadows   = (pt->t.obj_id >> 30) & TFS_EXTRA_SHADOWS_FLAG;

        if (ext->extra_obj_type == TFS_OBJ_TYPE_FILE) {
            uint32_t fsize_hi = x & 0x0fffffffu;
            uint32_t fsize_lo = (pt->t.obj_id >> 30) & 3u;
            ext->extra_file_size = ((tfs_off_t)fsize_hi << 2) | fsize_lo;
        } else {
            ext->extra_parent_id = x & 0x0fffffffu;
        }

        ext->obj_id = pt->t.obj_id & 0x3fffffffu;
    } else {
        ext->chunk_id = pt->t.chunk_id & 0x3fffffffu;
        ext->obj_id   = pt->t.obj_id   & 0x3fffffffu;
    }
}

/*-------------------------------------------------------------------
 * tfs_tags_verify_ecc
 *-------------------------------------------------------------------*/

tfs_ecc_result_t tfs_tags_verify_ecc(tfs_packed_tags2_t *pt, int no_ecc)
{
    tfs_ecc_other_t  calc;
    int              result;

    if (no_ecc)
        return TFS_ECC_RESULT_NOT_CHECKED;

    tfs_ecc_calc_other((const uint8_t *)&pt->t, sizeof(pt->t), &calc);

    result = tfs_ecc_correct_other((uint8_t *)&pt->t,
                                   sizeof(pt->t),
                                   &pt->ecc,
                                   &calc);
    if (result == 0)  return TFS_ECC_RESULT_NO_ERROR;
    if (result == 1)  return TFS_ECC_RESULT_FIXED;
    return TFS_ECC_RESULT_UNFIXED;
}

/*-------------------------------------------------------------------
 * tfs_tags_is_erased
 *-------------------------------------------------------------------*/

int tfs_tags_is_erased(const tfs_packed_tags2_t *pt)
{
    const uint32_t *p = (const uint32_t *)&pt->t;
    int i;

    for (i = 0; i < (int)(sizeof(pt->t) / 4); i++) {
        if (p[i] != 0xffffffffu)
            return 0;
    }
    return 1;
}
