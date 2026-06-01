/*
 * nfs_tags.c — Packed-tags2 encode / decode for NFS
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
 *       bit31 = NFS_EXTRA_HEADER_INFO_FLAG
 *       [30:28] = object_type
 *       [27:0]  = parent_obj_id (or file_size_hi for files)
 *   Byte 12..13  n_bytes (0xffff for a full chunk)
 *   Byte 14..16  ECC (3 bytes, column+line parity over bytes 0..11)
 *
 * NFS_MAX_OBJ_ID and chunk_id are guaranteed < 2^30 by design.
 */

#include "nfs_tags.h"
#include "../inc/nfs_config.h"

#include <string.h>

/*-------------------------------------------------------------------
 * Helpers
 *-------------------------------------------------------------------*/

static void calc_tags_ecc(nfs_packed_tags2_t *pt)
{
    nfs_ecc_calc_other((const nfs_u8 *)&pt->t,
                       sizeof(pt->t),
                       &pt->ecc);
}

/*-------------------------------------------------------------------
 * nfs_tags_pack
 *-------------------------------------------------------------------*/

void nfs_tags_pack(const nfs_dev_t *dev,
                   const nfs_ext_tags_t *ext,
                   nfs_packed_tags2_t   *pt)
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
    pt->t.n_bytes = (nfs_u16)ext->n_bytes;

    /* chunk_id: normal data or header with extra */
    if (ext->chunk_id == 0 && ext->extra_available) {
        /* Carry extra object-header info inside chunk_id word */
        nfs_u32 x = NFS_EXTRA_HEADER_INFO_FLAG;

        x |= (nfs_u32)(ext->extra_obj_type & NFS_EXTRA_OBJECT_TYPE_MASK)
             << NFS_EXTRA_OBJECT_TYPE_SHIFT;

        if (ext->extra_obj_type == NFS_OBJ_TYPE_FILE) {
            /* Store the high 28 bits of file_size in [27:0] */
            x |= (nfs_u32)(ext->extra_file_size >> 2) & 0x0fffffffu;
            /* Store low 2 bits in obj_id bits 30..31 */
            pt->t.obj_id |= (nfs_u32)(ext->extra_file_size & 3u) << 30;
        } else {
            x |= ext->extra_parent_id & 0x0fffffffu;
            if (ext->extra_is_shrink)
                pt->t.obj_id |= NFS_EXTRA_SHRINK_FLAG << 30;
            if (ext->extra_shadows)
                pt->t.obj_id |= NFS_EXTRA_SHADOWS_FLAG << 30;
        }

        pt->t.chunk_id = x;
    } else {
        pt->t.chunk_id = ext->chunk_id & 0x3fffffffu;
    }

    if (!dev->param.no_tags_ecc)
        calc_tags_ecc(pt);
}

/*-------------------------------------------------------------------
 * nfs_tags_unpack
 *-------------------------------------------------------------------*/

void nfs_tags_unpack(const nfs_dev_t      *dev,
                     const nfs_packed_tags2_t *pt,
                     nfs_ext_tags_t       *ext)
{
    (void)dev;

    memset(ext, 0, sizeof(*ext));

    if (nfs_tags_is_erased(pt)) {
        return;  /* chunk_used stays 0 */
    }

    ext->chunk_used = 1;
    ext->seq_number = pt->t.seq_number;
    ext->n_bytes    = pt->t.n_bytes;

    /* Decode chunk_id / extra info */
    if (pt->t.chunk_id & NFS_EXTRA_HEADER_INFO_FLAG) {
        /* Extra object-header info is embedded */
        nfs_u32 x = pt->t.chunk_id;

        ext->chunk_id        = 0;
        ext->extra_available = 1;
        ext->extra_obj_type  = (nfs_obj_type_t)
                               ((x >> NFS_EXTRA_OBJECT_TYPE_SHIFT)
                                & NFS_EXTRA_OBJECT_TYPE_MASK);
        ext->extra_is_shrink = (pt->t.obj_id >> 30) & NFS_EXTRA_SHRINK_FLAG;
        ext->extra_shadows   = (pt->t.obj_id >> 30) & NFS_EXTRA_SHADOWS_FLAG;

        if (ext->extra_obj_type == NFS_OBJ_TYPE_FILE) {
            nfs_u32 fsize_hi = x & 0x0fffffffu;
            nfs_u32 fsize_lo = (pt->t.obj_id >> 30) & 3u;
            ext->extra_file_size = ((nfs_off_t)fsize_hi << 2) | fsize_lo;
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
 * nfs_tags_verify_ecc
 *-------------------------------------------------------------------*/

nfs_ecc_result_t nfs_tags_verify_ecc(nfs_packed_tags2_t *pt, int no_ecc)
{
    nfs_ecc_other_t  calc;
    int              result;

    if (no_ecc)
        return NFS_ECC_RESULT_NOT_CHECKED;

    nfs_ecc_calc_other((const nfs_u8 *)&pt->t, sizeof(pt->t), &calc);

    result = nfs_ecc_correct_other((nfs_u8 *)&pt->t,
                                   sizeof(pt->t),
                                   &pt->ecc,
                                   &calc);
    if (result == 0)  return NFS_ECC_RESULT_NO_ERROR;
    if (result == 1)  return NFS_ECC_RESULT_FIXED;
    return NFS_ECC_RESULT_UNFIXED;
}

/*-------------------------------------------------------------------
 * nfs_tags_is_erased
 *-------------------------------------------------------------------*/

int nfs_tags_is_erased(const nfs_packed_tags2_t *pt)
{
    const nfs_u32 *p = (const nfs_u32 *)&pt->t;
    int i;

    for (i = 0; i < (int)(sizeof(pt->t) / 4); i++) {
        if (p[i] != 0xffffffffu)
            return 0;
    }
    return 1;
}
