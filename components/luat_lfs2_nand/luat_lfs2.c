/*
 * The little filesystem
 *
 * Copyright (c) 2022, The littlefs authors.
 * Copyright (c) 2017, Arm Limited. All rights reserved.
 * SPDX-License-Identifier: BSD-3-Clause
 */
#include "luat_lfs2.h"
#include "luat_lfs2_util.h"


// some constants used throughout the code
#define LFS_BLOCK_NULL ((luat_lfs2_block_t)-1)
#define LFS_BLOCK_INLINE ((luat_lfs2_block_t)-2)

enum {
    LFS_OK_RELOCATED = 1,
    LFS_OK_DROPPED   = 2,
    LFS_OK_ORPHANED  = 3,
};

enum {
    LFS_CMP_EQ = 0,
    LFS_CMP_LT = 1,
    LFS_CMP_GT = 2,
};


/// Caching block device operations ///

static inline void luat_lfs2_cache_drop(luat_lfs2_t *lfs, luat_lfs2_cache_t *rcache) {
    // do not zero, cheaper if cache is readonly or only going to be
    // written with identical data (during relocates)
    (void)lfs;
    rcache->block = LFS_BLOCK_NULL;
}

static inline void luat_lfs2_cache_zero(luat_lfs2_t *lfs, luat_lfs2_cache_t *pcache) {
    // zero to avoid information leak
    memset(pcache->buffer, 0xff, lfs->cfg->cache_size);
    pcache->block = LFS_BLOCK_NULL;
}

static int luat_lfs2_bd_read(luat_lfs2_t *lfs,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, luat_lfs2_size_t hint,
        luat_lfs2_block_t block, luat_lfs2_off_t off,
        void *buffer, luat_lfs2_size_t size) {
    uint8_t *data = buffer;
    if (off+size > lfs->cfg->block_size
            || (lfs->block_count && block >= lfs->block_count)) {
        return LFS_ERR_CORRUPT;
    }

    while (size > 0) {
        luat_lfs2_size_t diff = size;

        if (pcache && block == pcache->block &&
                off < pcache->off + pcache->size) {
            if (off >= pcache->off) {
                // is already in pcache?
                diff = luat_lfs2_min(diff, pcache->size - (off-pcache->off));
                memcpy(data, &pcache->buffer[off-pcache->off], diff);

                data += diff;
                off += diff;
                size -= diff;
                continue;
            }

            // pcache takes priority
            diff = luat_lfs2_min(diff, pcache->off-off);
        }

        if (block == rcache->block &&
                off < rcache->off + rcache->size) {
            if (off >= rcache->off) {
                // is already in rcache?
                diff = luat_lfs2_min(diff, rcache->size - (off-rcache->off));
                memcpy(data, &rcache->buffer[off-rcache->off], diff);

                data += diff;
                off += diff;
                size -= diff;
                continue;
            }

            // rcache takes priority
            diff = luat_lfs2_min(diff, rcache->off-off);
        }

        if (size >= hint && off % lfs->cfg->read_size == 0 &&
                size >= lfs->cfg->read_size) {
            // bypass cache?
            diff = luat_lfs2_aligndown(diff, lfs->cfg->read_size);
            int err = lfs->cfg->read(lfs->cfg, block, off, data, diff);
            if (err) {
                return err;
            }

            data += diff;
            off += diff;
            size -= diff;
            continue;
        }

        // load to cache, first condition can no longer fail
        LFS_ASSERT(!lfs->block_count || block < lfs->block_count);
        rcache->block = block;
        rcache->off = luat_lfs2_aligndown(off, lfs->cfg->read_size);
        rcache->size = luat_lfs2_min(
                luat_lfs2_min(
                    luat_lfs2_alignup(off+hint, lfs->cfg->read_size),
                    lfs->cfg->block_size)
                - rcache->off,
                lfs->cfg->cache_size);
        int err = lfs->cfg->read(lfs->cfg, rcache->block,
                rcache->off, rcache->buffer, rcache->size);
        LFS_ASSERT(err <= 0);
        if (err) {
            return err;
        }
    }

    return 0;
}

static int luat_lfs2_bd_cmp(luat_lfs2_t *lfs,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, luat_lfs2_size_t hint,
        luat_lfs2_block_t block, luat_lfs2_off_t off,
        const void *buffer, luat_lfs2_size_t size) {
    const uint8_t *data = buffer;
    luat_lfs2_size_t diff = 0;

    for (luat_lfs2_off_t i = 0; i < size; i += diff) {
        uint8_t dat[8];

        diff = luat_lfs2_min(size-i, sizeof(dat));
        int err = luat_lfs2_bd_read(lfs,
                pcache, rcache, hint-i,
                block, off+i, &dat, diff);
        if (err) {
            return err;
        }

        int res = memcmp(dat, data + i, diff);
        if (res) {
            return res < 0 ? LFS_CMP_LT : LFS_CMP_GT;
        }
    }

    return LFS_CMP_EQ;
}

static int luat_lfs2_bd_crc(luat_lfs2_t *lfs,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, luat_lfs2_size_t hint,
        luat_lfs2_block_t block, luat_lfs2_off_t off, luat_lfs2_size_t size, uint32_t *crc) {
    luat_lfs2_size_t diff = 0;

    for (luat_lfs2_off_t i = 0; i < size; i += diff) {
        uint8_t dat[8];
        diff = luat_lfs2_min(size-i, sizeof(dat));
        int err = luat_lfs2_bd_read(lfs,
                pcache, rcache, hint-i,
                block, off+i, &dat, diff);
        if (err) {
            return err;
        }

        *crc = luat_lfs2_crc(*crc, &dat, diff);
    }

    return 0;
}

#ifndef LFS_READONLY
static int luat_lfs2_bd_flush(luat_lfs2_t *lfs,
        luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, bool validate) {
    if (pcache->block != LFS_BLOCK_NULL && pcache->block != LFS_BLOCK_INLINE) {
        LFS_ASSERT(pcache->block < lfs->block_count);
        luat_lfs2_size_t diff = luat_lfs2_alignup(pcache->size, lfs->cfg->prog_size);
        int err = lfs->cfg->prog(lfs->cfg, pcache->block,
                pcache->off, pcache->buffer, diff);
        LFS_ASSERT(err <= 0);
        if (err) {
            return err;
        }

        if (validate) {
            // check data on disk
            luat_lfs2_cache_drop(lfs, rcache);
            int res = luat_lfs2_bd_cmp(lfs,
                    NULL, rcache, diff,
                    pcache->block, pcache->off, pcache->buffer, diff);
            if (res < 0) {
                return res;
            }

            if (res != LFS_CMP_EQ) {
                return LFS_ERR_CORRUPT;
            }
        }

        luat_lfs2_cache_zero(lfs, pcache);
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_bd_sync(luat_lfs2_t *lfs,
        luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, bool validate) {
    luat_lfs2_cache_drop(lfs, rcache);

    int err = luat_lfs2_bd_flush(lfs, pcache, rcache, validate);
    if (err) {
        return err;
    }

    err = lfs->cfg->sync(lfs->cfg);
    LFS_ASSERT(err <= 0);
    return err;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_bd_prog(luat_lfs2_t *lfs,
        luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, bool validate,
        luat_lfs2_block_t block, luat_lfs2_off_t off,
        const void *buffer, luat_lfs2_size_t size) {
    const uint8_t *data = buffer;
    LFS_ASSERT(block == LFS_BLOCK_INLINE || block < lfs->block_count);
    LFS_ASSERT(off + size <= lfs->cfg->block_size);

    while (size > 0) {
        if (block == pcache->block &&
                off >= pcache->off &&
                off < pcache->off + lfs->cfg->cache_size) {
            // already fits in pcache?
            luat_lfs2_size_t diff = luat_lfs2_min(size,
                    lfs->cfg->cache_size - (off-pcache->off));
            memcpy(&pcache->buffer[off-pcache->off], data, diff);

            data += diff;
            off += diff;
            size -= diff;

            pcache->size = luat_lfs2_max(pcache->size, off - pcache->off);
            if (pcache->size == lfs->cfg->cache_size) {
                // eagerly flush out pcache if we fill up
                int err = luat_lfs2_bd_flush(lfs, pcache, rcache, validate);
                if (err) {
                    return err;
                }
            }

            continue;
        }

        // pcache must have been flushed, either by programming and
        // entire block or manually flushing the pcache
        LFS_ASSERT(pcache->block == LFS_BLOCK_NULL);

        // prepare pcache, first condition can no longer fail
        pcache->block = block;
        pcache->off = luat_lfs2_aligndown(off, lfs->cfg->prog_size);
        pcache->size = 0;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_alloc(luat_lfs2_t *lfs, luat_lfs2_block_t *block);

static int luat_lfs2_bd_erase_raw(luat_lfs2_t *lfs, luat_lfs2_block_t block) {
    LFS_ASSERT(block < lfs->block_count);
    int err = lfs->cfg->erase(lfs->cfg, block);
    LFS_ASSERT(err <= 0);
    return err;
}

static void luat_lfs2_preerase_reset(luat_lfs2_t *lfs) {
    if (!lfs) {
        return;
    }
    lfs->preerase_reserve_count = 0;
    lfs->preerase_reserve_head = 0;
    lfs->preerase_reserve_tail = 0;
    lfs->preerase_reserve_peak = 0;
    memset(lfs->preerase_reserve, 0, sizeof(lfs->preerase_reserve));
    memset(&lfs->preerase_stats, 0, sizeof(lfs->preerase_stats));
}

static int luat_lfs2_preerase_reserve_push(luat_lfs2_t *lfs, luat_lfs2_block_t block) {
    if (!lfs || lfs->preerase_reserve_count >= (uint8_t)(sizeof(lfs->preerase_reserve) / sizeof(lfs->preerase_reserve[0]))) {
        return -1;
    }
    lfs->preerase_reserve[lfs->preerase_reserve_tail] = block;
    lfs->preerase_reserve_tail = (uint8_t)((lfs->preerase_reserve_tail + 1u) % (sizeof(lfs->preerase_reserve) / sizeof(lfs->preerase_reserve[0])));
    lfs->preerase_reserve_count++;
    if (lfs->preerase_reserve_count > lfs->preerase_reserve_peak) {
        lfs->preerase_reserve_peak = lfs->preerase_reserve_count;
    }
    return 0;
}

static int luat_lfs2_preerase_reserve_pop(luat_lfs2_t *lfs, luat_lfs2_block_t *block) {
    if (!lfs || !block || lfs->preerase_reserve_count == 0) {
        return -1;
    }
    *block = lfs->preerase_reserve[lfs->preerase_reserve_head];
    lfs->preerase_reserve_head = (uint8_t)((lfs->preerase_reserve_head + 1u) % (sizeof(lfs->preerase_reserve) / sizeof(lfs->preerase_reserve[0])));
    lfs->preerase_reserve_count--;
    return 0;
}

int luat_lfs2_preerase_refill(luat_lfs2_t *lfs, uint8_t budget) {
    if (!lfs || !lfs->preerase_enabled || budget == 0) {
        return 0;
    }
    while (budget-- > 0) {
        luat_lfs2_block_t block = 0;
        int err = 0;
        if (lfs->preerase_reserve_count >= lfs->preerase_reserve_high) {
            break;
        }
        err = luat_lfs2_alloc(lfs, &block);
        if (err) {
            lfs->preerase_stats.refill_fail_count++;
            return err;
        }
        err = luat_lfs2_bd_erase_raw(lfs, block);
        if (err) {
            lfs->preerase_stats.refill_fail_count++;
            if (err == LFS_ERR_CORRUPT) {
                continue;
            }
            return err;
        }
        if (luat_lfs2_preerase_reserve_push(lfs, block) != 0) {
            lfs->preerase_stats.refill_fail_count++;
            return 0;
        }
        lfs->preerase_stats.refill_erase_count++;
    }
    return 0;
}

static int luat_lfs2_alloc_erased(luat_lfs2_t *lfs, luat_lfs2_block_t *block) {
    int err = 0;
    if (lfs && lfs->preerase_enabled && luat_lfs2_preerase_reserve_pop(lfs, block) == 0) {
        lfs->preerase_stats.reserve_hit_count++;
        return 0;
    }
    err = luat_lfs2_alloc(lfs, block);
    if (err) {
        return err;
    }
    err = luat_lfs2_bd_erase_raw(lfs, *block);
    if (err) {
        return err;
    }
    if (lfs && lfs->preerase_enabled) {
        lfs->preerase_stats.foreground_erase_count++;
        lfs->preerase_stats.emergency_fallback_count++;
    }
    return 0;
}

static int luat_lfs2_bd_erase(luat_lfs2_t *lfs, luat_lfs2_block_t block) {
    int err = luat_lfs2_bd_erase_raw(lfs, block);
    if (!err && lfs && lfs->preerase_enabled) {
        lfs->preerase_stats.foreground_erase_count++;
    }
    return err;
}
#endif


/// Small type-level utilities ///
// operations on block pairs
static inline void luat_lfs2_pair_swap(luat_lfs2_block_t pair[2]) {
    luat_lfs2_block_t t = pair[0];
    pair[0] = pair[1];
    pair[1] = t;
}

static inline bool luat_lfs2_pair_isnull(const luat_lfs2_block_t pair[2]) {
    return pair[0] == LFS_BLOCK_NULL || pair[1] == LFS_BLOCK_NULL;
}

static inline int luat_lfs2_pair_cmp(
        const luat_lfs2_block_t paira[2],
        const luat_lfs2_block_t pairb[2]) {
    return !(paira[0] == pairb[0] || paira[1] == pairb[1] ||
             paira[0] == pairb[1] || paira[1] == pairb[0]);
}

static inline bool luat_lfs2_pair_issync(
        const luat_lfs2_block_t paira[2],
        const luat_lfs2_block_t pairb[2]) {
    return (paira[0] == pairb[0] && paira[1] == pairb[1]) ||
           (paira[0] == pairb[1] && paira[1] == pairb[0]);
}

static inline void luat_lfs2_pair_fromle32(luat_lfs2_block_t pair[2]) {
    pair[0] = luat_lfs2_fromle32(pair[0]);
    pair[1] = luat_lfs2_fromle32(pair[1]);
}

#ifndef LFS_READONLY
static inline void luat_lfs2_pair_tole32(luat_lfs2_block_t pair[2]) {
    pair[0] = luat_lfs2_tole32(pair[0]);
    pair[1] = luat_lfs2_tole32(pair[1]);
}
#endif

// operations on 32-bit entry tags
typedef uint32_t luat_lfs2_tag_t;
typedef int32_t luat_lfs2_stag_t;

#define LFS_MKTAG(type, id, size) \
    (((luat_lfs2_tag_t)(type) << 20) | ((luat_lfs2_tag_t)(id) << 10) | (luat_lfs2_tag_t)(size))

#define LFS_MKTAG_IF(cond, type, id, size) \
    ((cond) ? LFS_MKTAG(type, id, size) : LFS_MKTAG(LFS_FROM_NOOP, 0, 0))

#define LFS_MKTAG_IF_ELSE(cond, type1, id1, size1, type2, id2, size2) \
    ((cond) ? LFS_MKTAG(type1, id1, size1) : LFS_MKTAG(type2, id2, size2))

static inline bool luat_lfs2_tag_isvalid(luat_lfs2_tag_t tag) {
    return !(tag & 0x80000000);
}

static inline bool luat_lfs2_tag_isdelete(luat_lfs2_tag_t tag) {
    return ((int32_t)(tag << 22) >> 22) == -1;
}

static inline uint16_t luat_lfs2_tag_type1(luat_lfs2_tag_t tag) {
    return (tag & 0x70000000) >> 20;
}

static inline uint16_t luat_lfs2_tag_type2(luat_lfs2_tag_t tag) {
    return (tag & 0x78000000) >> 20;
}

static inline uint16_t luat_lfs2_tag_type3(luat_lfs2_tag_t tag) {
    return (tag & 0x7ff00000) >> 20;
}

static inline uint8_t luat_lfs2_tag_chunk(luat_lfs2_tag_t tag) {
    return (tag & 0x0ff00000) >> 20;
}

static inline int8_t luat_lfs2_tag_splice(luat_lfs2_tag_t tag) {
    return (int8_t)luat_lfs2_tag_chunk(tag);
}

static inline uint16_t luat_lfs2_tag_id(luat_lfs2_tag_t tag) {
    return (tag & 0x000ffc00) >> 10;
}

static inline luat_lfs2_size_t luat_lfs2_tag_size(luat_lfs2_tag_t tag) {
    return tag & 0x000003ff;
}

static inline luat_lfs2_size_t luat_lfs2_tag_dsize(luat_lfs2_tag_t tag) {
    return sizeof(tag) + luat_lfs2_tag_size(tag + luat_lfs2_tag_isdelete(tag));
}

// operations on attributes in attribute lists
struct luat_lfs2_mattr {
    luat_lfs2_tag_t tag;
    const void *buffer;
};

struct luat_lfs2_diskoff {
    luat_lfs2_block_t block;
    luat_lfs2_off_t off;
};

#define LFS_MKATTRS(...) \
    (struct luat_lfs2_mattr[]){__VA_ARGS__}, \
    sizeof((struct luat_lfs2_mattr[]){__VA_ARGS__}) / sizeof(struct luat_lfs2_mattr)

// operations on global state
static inline void luat_lfs2_gstate_xor(luat_lfs2_gstate_t *a, const luat_lfs2_gstate_t *b) {
    for (int i = 0; i < 3; i++) {
        ((uint32_t*)a)[i] ^= ((const uint32_t*)b)[i];
    }
}

static inline bool luat_lfs2_gstate_iszero(const luat_lfs2_gstate_t *a) {
    for (int i = 0; i < 3; i++) {
        if (((uint32_t*)a)[i] != 0) {
            return false;
        }
    }
    return true;
}

#ifndef LFS_READONLY
static inline bool luat_lfs2_gstate_hasorphans(const luat_lfs2_gstate_t *a) {
    return luat_lfs2_tag_size(a->tag);
}

static inline uint8_t luat_lfs2_gstate_getorphans(const luat_lfs2_gstate_t *a) {
    return luat_lfs2_tag_size(a->tag) & 0x1ff;
}

static inline bool luat_lfs2_gstate_hasmove(const luat_lfs2_gstate_t *a) {
    return luat_lfs2_tag_type1(a->tag);
}
#endif

static inline bool luat_lfs2_gstate_needssuperblock(const luat_lfs2_gstate_t *a) {
    return luat_lfs2_tag_size(a->tag) >> 9;
}

static inline bool luat_lfs2_gstate_hasmovehere(const luat_lfs2_gstate_t *a,
        const luat_lfs2_block_t *pair) {
    return luat_lfs2_tag_type1(a->tag) && luat_lfs2_pair_cmp(a->pair, pair) == 0;
}

static inline void luat_lfs2_gstate_fromle32(luat_lfs2_gstate_t *a) {
    a->tag     = luat_lfs2_fromle32(a->tag);
    a->pair[0] = luat_lfs2_fromle32(a->pair[0]);
    a->pair[1] = luat_lfs2_fromle32(a->pair[1]);
}

#ifndef LFS_READONLY
static inline void luat_lfs2_gstate_tole32(luat_lfs2_gstate_t *a) {
    a->tag     = luat_lfs2_tole32(a->tag);
    a->pair[0] = luat_lfs2_tole32(a->pair[0]);
    a->pair[1] = luat_lfs2_tole32(a->pair[1]);
}
#endif

// operations on forward-CRCs used to track erased state
struct luat_lfs2_fcrc {
    luat_lfs2_size_t size;
    uint32_t crc;
};

static void luat_lfs2_fcrc_fromle32(struct luat_lfs2_fcrc *fcrc) {
    fcrc->size = luat_lfs2_fromle32(fcrc->size);
    fcrc->crc = luat_lfs2_fromle32(fcrc->crc);
}

#ifndef LFS_READONLY
static void luat_lfs2_fcrc_tole32(struct luat_lfs2_fcrc *fcrc) {
    fcrc->size = luat_lfs2_tole32(fcrc->size);
    fcrc->crc = luat_lfs2_tole32(fcrc->crc);
}
#endif

// other endianness operations
static void luat_lfs2_ctz_fromle32(struct luat_lfs2_ctz *ctz) {
    ctz->head = luat_lfs2_fromle32(ctz->head);
    ctz->size = luat_lfs2_fromle32(ctz->size);
}

#ifndef LFS_READONLY
static void luat_lfs2_ctz_tole32(struct luat_lfs2_ctz *ctz) {
    ctz->head = luat_lfs2_tole32(ctz->head);
    ctz->size = luat_lfs2_tole32(ctz->size);
}
#endif

static inline void luat_lfs2_superblock_fromle32(luat_lfs2_superblock_t *superblock) {
    superblock->version     = luat_lfs2_fromle32(superblock->version);
    superblock->block_size  = luat_lfs2_fromle32(superblock->block_size);
    superblock->block_count = luat_lfs2_fromle32(superblock->block_count);
    superblock->name_max    = luat_lfs2_fromle32(superblock->name_max);
    superblock->file_max    = luat_lfs2_fromle32(superblock->file_max);
    superblock->attr_max    = luat_lfs2_fromle32(superblock->attr_max);
}

#ifndef LFS_READONLY
static inline void luat_lfs2_superblock_tole32(luat_lfs2_superblock_t *superblock) {
    superblock->version     = luat_lfs2_tole32(superblock->version);
    superblock->block_size  = luat_lfs2_tole32(superblock->block_size);
    superblock->block_count = luat_lfs2_tole32(superblock->block_count);
    superblock->name_max    = luat_lfs2_tole32(superblock->name_max);
    superblock->file_max    = luat_lfs2_tole32(superblock->file_max);
    superblock->attr_max    = luat_lfs2_tole32(superblock->attr_max);
}
#endif

#ifndef LFS_NO_ASSERT
static bool luat_lfs2_mlist_isopen(struct luat_lfs2_mlist *head,
        struct luat_lfs2_mlist *node) {
    for (struct luat_lfs2_mlist **p = &head; *p; p = &(*p)->next) {
        if (*p == (struct luat_lfs2_mlist*)node) {
            return true;
        }
    }

    return false;
}
#endif

static void luat_lfs2_mlist_remove(luat_lfs2_t *lfs, struct luat_lfs2_mlist *mlist) {
    for (struct luat_lfs2_mlist **p = &lfs->mlist; *p; p = &(*p)->next) {
        if (*p == mlist) {
            *p = (*p)->next;
            break;
        }
    }
}

static void luat_lfs2_mlist_append(luat_lfs2_t *lfs, struct luat_lfs2_mlist *mlist) {
    mlist->next = lfs->mlist;
    lfs->mlist = mlist;
}

// some other filesystem operations
static uint32_t luat_lfs2_fs_disk_version(luat_lfs2_t *lfs) {
    (void)lfs;
#ifdef LFS_MULTIVERSION
    if (lfs->cfg->disk_version) {
        return lfs->cfg->disk_version;
    } else
#endif
    {
        return LFS_DISK_VERSION;
    }
}

static uint16_t luat_lfs2_fs_disk_version_major(luat_lfs2_t *lfs) {
    return 0xffff & (luat_lfs2_fs_disk_version(lfs) >> 16);

}

static uint16_t luat_lfs2_fs_disk_version_minor(luat_lfs2_t *lfs) {
    return 0xffff & (luat_lfs2_fs_disk_version(lfs) >> 0);
}


/// Internal operations predeclared here ///
#ifndef LFS_READONLY
static int luat_lfs2_dir_commit(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const struct luat_lfs2_mattr *attrs, int attrcount);
static int luat_lfs2_dir_compact(luat_lfs2_t *lfs,
        luat_lfs2_mdir_t *dir, const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_mdir_t *source, uint16_t begin, uint16_t end);
static luat_lfs2_ssize_t luat_lfs2_file_flushedwrite(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size);
static luat_lfs2_ssize_t luat_lfs2_file_write_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size);
static int luat_lfs2_file_sync_(luat_lfs2_t *lfs, luat_lfs2_file_t *file);
static int luat_lfs2_file_outline(luat_lfs2_t *lfs, luat_lfs2_file_t *file);
static int luat_lfs2_file_flush(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

static int luat_lfs2_fs_deorphan(luat_lfs2_t *lfs, bool powerloss);
static int luat_lfs2_fs_preporphans(luat_lfs2_t *lfs, int8_t orphans);
static void luat_lfs2_fs_prepmove(luat_lfs2_t *lfs,
        uint16_t id, const luat_lfs2_block_t pair[2]);
static int luat_lfs2_fs_pred(luat_lfs2_t *lfs, const luat_lfs2_block_t dir[2],
        luat_lfs2_mdir_t *pdir);
static luat_lfs2_stag_t luat_lfs2_fs_parent(luat_lfs2_t *lfs, const luat_lfs2_block_t dir[2],
        luat_lfs2_mdir_t *parent);
static int luat_lfs2_fs_forceconsistency(luat_lfs2_t *lfs);
#endif

static void luat_lfs2_fs_prepsuperblock(luat_lfs2_t *lfs, bool needssuperblock);

#ifdef LFS_MIGRATE
static int lfs1_traverse(luat_lfs2_t *lfs,
        int (*cb)(void*, luat_lfs2_block_t), void *data);
#endif

static int luat_lfs2_dir_rewind_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir);

static luat_lfs2_ssize_t luat_lfs2_file_flushedread(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size);
static luat_lfs2_ssize_t luat_lfs2_file_read_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size);
static int luat_lfs2_file_close_(luat_lfs2_t *lfs, luat_lfs2_file_t *file);
static luat_lfs2_soff_t luat_lfs2_file_size_(luat_lfs2_t *lfs, luat_lfs2_file_t *file);

static luat_lfs2_ssize_t luat_lfs2_fs_size_(luat_lfs2_t *lfs);
static int luat_lfs2_fs_traverse_(luat_lfs2_t *lfs,
        int (*cb)(void *data, luat_lfs2_block_t block), void *data,
        bool includeorphans);

static int luat_lfs2_deinit(luat_lfs2_t *lfs);
static int luat_lfs2_unmount_(luat_lfs2_t *lfs);


/// Block allocator ///

// allocations should call this when all allocated blocks are committed to
// the filesystem
//
// after a checkpoint, the block allocator may realloc any untracked blocks
static void luat_lfs2_alloc_ckpoint(luat_lfs2_t *lfs) {
    lfs->lookahead.ckpoint = lfs->block_count;
}

// drop the lookahead buffer, this is done during mounting and failed
// traversals in order to avoid invalid lookahead state
static void luat_lfs2_alloc_drop(luat_lfs2_t *lfs) {
    lfs->lookahead.size = 0;
    lfs->lookahead.next = 0;
    luat_lfs2_alloc_ckpoint(lfs);
}

#ifndef LFS_READONLY
static int luat_lfs2_alloc_lookahead(void *p, luat_lfs2_block_t block) {
    luat_lfs2_t *lfs = (luat_lfs2_t*)p;
    luat_lfs2_block_t off = ((block - lfs->lookahead.start)
            + lfs->block_count) % lfs->block_count;

    if (off < lfs->lookahead.size) {
        lfs->lookahead.buffer[off / 8] |= 1U << (off % 8);
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_alloc_scan(luat_lfs2_t *lfs) {
    // move lookahead buffer to the first unused block
    //
    // note we limit the lookahead buffer to at most the amount of blocks
    // checkpointed, this prevents the math in luat_lfs2_alloc from underflowing
    lfs->lookahead.start = (lfs->lookahead.start + lfs->lookahead.next) 
            % lfs->block_count;
    lfs->lookahead.next = 0;
    lfs->lookahead.size = luat_lfs2_min(
            8*lfs->cfg->lookahead_size,
            lfs->lookahead.ckpoint);

    // find mask of free blocks from tree
    memset(lfs->lookahead.buffer, 0, lfs->cfg->lookahead_size);
    int err = luat_lfs2_fs_traverse_(lfs, luat_lfs2_alloc_lookahead, lfs, true);
    if (err) {
        luat_lfs2_alloc_drop(lfs);
        return err;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_alloc(luat_lfs2_t *lfs, luat_lfs2_block_t *block) {
    while (true) {
        // scan our lookahead buffer for free blocks
        while (lfs->lookahead.next < lfs->lookahead.size) {
            if (!(lfs->lookahead.buffer[lfs->lookahead.next / 8]
                    & (1U << (lfs->lookahead.next % 8)))) {
                // found a free block
                *block = (lfs->lookahead.start + lfs->lookahead.next)
                        % lfs->block_count;

                // eagerly find next free block to maximize how many blocks
                // luat_lfs2_alloc_ckpoint makes available for scanning
                while (true) {
                    lfs->lookahead.next += 1;
                    lfs->lookahead.ckpoint -= 1;

                    if (lfs->lookahead.next >= lfs->lookahead.size
                            || !(lfs->lookahead.buffer[lfs->lookahead.next / 8]
                                & (1U << (lfs->lookahead.next % 8)))) {
                        return 0;
                    }
                }
            }

            lfs->lookahead.next += 1;
            lfs->lookahead.ckpoint -= 1;
        }

        // In order to keep our block allocator from spinning forever when our
        // filesystem is full, we mark points where there are no in-flight
        // allocations with a checkpoint before starting a set of allocations.
        //
        // If we've looked at all blocks since the last checkpoint, we report
        // the filesystem as out of storage.
        //
        if (lfs->lookahead.ckpoint <= 0) {
            LFS_ERROR("No more free space 0x%"PRIx32,
                    (lfs->lookahead.start + lfs->lookahead.next)
                        % lfs->block_count);
            return LFS_ERR_NOSPC;
        }

        // No blocks in our lookahead buffer, we need to scan the filesystem for
        // unused blocks in the next lookahead window.
        int err = luat_lfs2_alloc_scan(lfs);
        if(err) {
            return err;
        }
    }
}
#endif

/// Metadata pair and directory operations ///
static luat_lfs2_stag_t luat_lfs2_dir_getslice(luat_lfs2_t *lfs, const luat_lfs2_mdir_t *dir,
        luat_lfs2_tag_t gmask, luat_lfs2_tag_t gtag,
        luat_lfs2_off_t goff, void *gbuffer, luat_lfs2_size_t gsize) {
    luat_lfs2_off_t off = dir->off;
    luat_lfs2_tag_t ntag = dir->etag;
    luat_lfs2_stag_t gdiff = 0;

    // synthetic moves
    if (luat_lfs2_gstate_hasmovehere(&lfs->gdisk, dir->pair) &&
            luat_lfs2_tag_id(gmask) != 0) {
        if (luat_lfs2_tag_id(lfs->gdisk.tag) == luat_lfs2_tag_id(gtag)) {
            return LFS_ERR_NOENT;
        } else if (luat_lfs2_tag_id(lfs->gdisk.tag) < luat_lfs2_tag_id(gtag)) {
            gdiff -= LFS_MKTAG(0, 1, 0);
        }
    }

    // iterate over dir block backwards (for faster lookups)
    while (off >= sizeof(luat_lfs2_tag_t) + luat_lfs2_tag_dsize(ntag)) {
        off -= luat_lfs2_tag_dsize(ntag);
        luat_lfs2_tag_t tag = ntag;
        int err = luat_lfs2_bd_read(lfs,
                NULL, &lfs->rcache, sizeof(ntag),
                dir->pair[0], off, &ntag, sizeof(ntag));
        if (err) {
            return err;
        }

        ntag = (luat_lfs2_frombe32(ntag) ^ tag) & 0x7fffffff;

        if (luat_lfs2_tag_id(gmask) != 0 &&
                luat_lfs2_tag_type1(tag) == LFS_TYPE_SPLICE &&
                luat_lfs2_tag_id(tag) <= luat_lfs2_tag_id(gtag - gdiff)) {
            if (tag == (LFS_MKTAG(LFS_TYPE_CREATE, 0, 0) |
                    (LFS_MKTAG(0, 0x3ff, 0) & (gtag - gdiff)))) {
                // found where we were created
                return LFS_ERR_NOENT;
            }

            // move around splices
            gdiff += LFS_MKTAG(0, luat_lfs2_tag_splice(tag), 0);
        }

        if ((gmask & tag) == (gmask & (gtag - gdiff))) {
            if (luat_lfs2_tag_isdelete(tag)) {
                return LFS_ERR_NOENT;
            }

            luat_lfs2_size_t diff = luat_lfs2_min(luat_lfs2_tag_size(tag), gsize);
            err = luat_lfs2_bd_read(lfs,
                    NULL, &lfs->rcache, diff,
                    dir->pair[0], off+sizeof(tag)+goff, gbuffer, diff);
            if (err) {
                return err;
            }

            memset((uint8_t*)gbuffer + diff, 0, gsize - diff);

            return tag + gdiff;
        }
    }

    return LFS_ERR_NOENT;
}

static luat_lfs2_stag_t luat_lfs2_dir_get(luat_lfs2_t *lfs, const luat_lfs2_mdir_t *dir,
        luat_lfs2_tag_t gmask, luat_lfs2_tag_t gtag, void *buffer) {
    return luat_lfs2_dir_getslice(lfs, dir,
            gmask, gtag,
            0, buffer, luat_lfs2_tag_size(gtag));
}

static int luat_lfs2_dir_getread(luat_lfs2_t *lfs, const luat_lfs2_mdir_t *dir,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache, luat_lfs2_size_t hint,
        luat_lfs2_tag_t gmask, luat_lfs2_tag_t gtag,
        luat_lfs2_off_t off, void *buffer, luat_lfs2_size_t size) {
    uint8_t *data = buffer;
    if (off+size > lfs->cfg->block_size) {
        return LFS_ERR_CORRUPT;
    }

    while (size > 0) {
        luat_lfs2_size_t diff = size;

        if (pcache && pcache->block == LFS_BLOCK_INLINE &&
                off < pcache->off + pcache->size) {
            if (off >= pcache->off) {
                // is already in pcache?
                diff = luat_lfs2_min(diff, pcache->size - (off-pcache->off));
                memcpy(data, &pcache->buffer[off-pcache->off], diff);

                data += diff;
                off += diff;
                size -= diff;
                continue;
            }

            // pcache takes priority
            diff = luat_lfs2_min(diff, pcache->off-off);
        }

        if (rcache->block == LFS_BLOCK_INLINE &&
                off < rcache->off + rcache->size) {
            if (off >= rcache->off) {
                // is already in rcache?
                diff = luat_lfs2_min(diff, rcache->size - (off-rcache->off));
                memcpy(data, &rcache->buffer[off-rcache->off], diff);

                data += diff;
                off += diff;
                size -= diff;
                continue;
            }

            // rcache takes priority
            diff = luat_lfs2_min(diff, rcache->off-off);
        }

        // load to cache, first condition can no longer fail
        rcache->block = LFS_BLOCK_INLINE;
        rcache->off = luat_lfs2_aligndown(off, lfs->cfg->read_size);
        rcache->size = luat_lfs2_min(luat_lfs2_alignup(off+hint, lfs->cfg->read_size),
                lfs->cfg->cache_size);
        int err = luat_lfs2_dir_getslice(lfs, dir, gmask, gtag,
                rcache->off, rcache->buffer, rcache->size);
        if (err < 0) {
            return err;
        }
    }

    return 0;
}

#ifndef LFS_READONLY
static int luat_lfs2_dir_traverse_filter(void *p,
        luat_lfs2_tag_t tag, const void *buffer) {
    luat_lfs2_tag_t *filtertag = p;
    (void)buffer;

    // which mask depends on unique bit in tag structure
    uint32_t mask = (tag & LFS_MKTAG(0x100, 0, 0))
            ? LFS_MKTAG(0x7ff, 0x3ff, 0)
            : LFS_MKTAG(0x700, 0x3ff, 0);

    // check for redundancy
    if ((mask & tag) == (mask & *filtertag) ||
            luat_lfs2_tag_isdelete(*filtertag) ||
            (LFS_MKTAG(0x7ff, 0x3ff, 0) & tag) == (
                LFS_MKTAG(LFS_TYPE_DELETE, 0, 0) |
                    (LFS_MKTAG(0, 0x3ff, 0) & *filtertag))) {
        *filtertag = LFS_MKTAG(LFS_FROM_NOOP, 0, 0);
        return true;
    }

    // check if we need to adjust for created/deleted tags
    if (luat_lfs2_tag_type1(tag) == LFS_TYPE_SPLICE &&
            luat_lfs2_tag_id(tag) <= luat_lfs2_tag_id(*filtertag)) {
        *filtertag += LFS_MKTAG(0, luat_lfs2_tag_splice(tag), 0);
    }

    return false;
}
#endif

#ifndef LFS_READONLY
// maximum recursive depth of luat_lfs2_dir_traverse, the deepest call:
//
// traverse with commit
// '-> traverse with move
//     '-> traverse with filter
//
#define LFS_DIR_TRAVERSE_DEPTH 3

struct luat_lfs2_dir_traverse {
    const luat_lfs2_mdir_t *dir;
    luat_lfs2_off_t off;
    luat_lfs2_tag_t ptag;
    const struct luat_lfs2_mattr *attrs;
    int attrcount;

    luat_lfs2_tag_t tmask;
    luat_lfs2_tag_t ttag;
    uint16_t begin;
    uint16_t end;
    int16_t diff;

    int (*cb)(void *data, luat_lfs2_tag_t tag, const void *buffer);
    void *data;

    luat_lfs2_tag_t tag;
    const void *buffer;
    struct luat_lfs2_diskoff disk;
};

static int luat_lfs2_dir_traverse(luat_lfs2_t *lfs,
        const luat_lfs2_mdir_t *dir, luat_lfs2_off_t off, luat_lfs2_tag_t ptag,
        const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_tag_t tmask, luat_lfs2_tag_t ttag,
        uint16_t begin, uint16_t end, int16_t diff,
        int (*cb)(void *data, luat_lfs2_tag_t tag, const void *buffer), void *data) {
    // This function in inherently recursive, but bounded. To allow tool-based
    // analysis without unnecessary code-cost we use an explicit stack
    struct luat_lfs2_dir_traverse stack[LFS_DIR_TRAVERSE_DEPTH-1];
    unsigned sp = 0;
    int res;

    // iterate over directory and attrs
    luat_lfs2_tag_t tag;
    const void *buffer;
    struct luat_lfs2_diskoff disk = {0};
    while (true) {
        {
            if (off+luat_lfs2_tag_dsize(ptag) < dir->off) {
                off += luat_lfs2_tag_dsize(ptag);
                int err = luat_lfs2_bd_read(lfs,
                        NULL, &lfs->rcache, sizeof(tag),
                        dir->pair[0], off, &tag, sizeof(tag));
                if (err) {
                    return err;
                }

                tag = (luat_lfs2_frombe32(tag) ^ ptag) | 0x80000000;
                disk.block = dir->pair[0];
                disk.off = off+sizeof(luat_lfs2_tag_t);
                buffer = &disk;
                ptag = tag;
            } else if (attrcount > 0) {
                tag = attrs[0].tag;
                buffer = attrs[0].buffer;
                attrs += 1;
                attrcount -= 1;
            } else {
                // finished traversal, pop from stack?
                res = 0;
                break;
            }

            // do we need to filter?
            luat_lfs2_tag_t mask = LFS_MKTAG(0x7ff, 0, 0);
            if ((mask & tmask & tag) != (mask & tmask & ttag)) {
                continue;
            }

            if (luat_lfs2_tag_id(tmask) != 0) {
                LFS_ASSERT(sp < LFS_DIR_TRAVERSE_DEPTH);
                // recurse, scan for duplicates, and update tag based on
                // creates/deletes
                stack[sp] = (struct luat_lfs2_dir_traverse){
                    .dir        = dir,
                    .off        = off,
                    .ptag       = ptag,
                    .attrs      = attrs,
                    .attrcount  = attrcount,
                    .tmask      = tmask,
                    .ttag       = ttag,
                    .begin      = begin,
                    .end        = end,
                    .diff       = diff,
                    .cb         = cb,
                    .data       = data,
                    .tag        = tag,
                    .buffer     = buffer,
                    .disk       = disk,
                };
                sp += 1;

                tmask = 0;
                ttag = 0;
                begin = 0;
                end = 0;
                diff = 0;
                cb = luat_lfs2_dir_traverse_filter;
                data = &stack[sp-1].tag;
                continue;
            }
        }

popped:
        // in filter range?
        if (luat_lfs2_tag_id(tmask) != 0 &&
                !(luat_lfs2_tag_id(tag) >= begin && luat_lfs2_tag_id(tag) < end)) {
            continue;
        }

        // handle special cases for mcu-side operations
        if (luat_lfs2_tag_type3(tag) == LFS_FROM_NOOP) {
            // do nothing
        } else if (luat_lfs2_tag_type3(tag) == LFS_FROM_MOVE) {
            // Without this condition, luat_lfs2_dir_traverse can exhibit an
            // extremely expensive O(n^3) of nested loops when renaming.
            // This happens because luat_lfs2_dir_traverse tries to filter tags by
            // the tags in the source directory, triggering a second
            // luat_lfs2_dir_traverse with its own filter operation.
            //
            // traverse with commit
            // '-> traverse with filter
            //     '-> traverse with move
            //         '-> traverse with filter
            //
            // However we don't actually care about filtering the second set of
            // tags, since duplicate tags have no effect when filtering.
            //
            // This check skips this unnecessary recursive filtering explicitly,
            // reducing this runtime from O(n^3) to O(n^2).
            if (cb == luat_lfs2_dir_traverse_filter) {
                continue;
            }

            // recurse into move
            stack[sp] = (struct luat_lfs2_dir_traverse){
                .dir        = dir,
                .off        = off,
                .ptag       = ptag,
                .attrs      = attrs,
                .attrcount  = attrcount,
                .tmask      = tmask,
                .ttag       = ttag,
                .begin      = begin,
                .end        = end,
                .diff       = diff,
                .cb         = cb,
                .data       = data,
                .tag        = LFS_MKTAG(LFS_FROM_NOOP, 0, 0),
            };
            sp += 1;

            uint16_t fromid = luat_lfs2_tag_size(tag);
            uint16_t toid = luat_lfs2_tag_id(tag);
            dir = buffer;
            off = 0;
            ptag = 0xffffffff;
            attrs = NULL;
            attrcount = 0;
            tmask = LFS_MKTAG(0x600, 0x3ff, 0);
            ttag = LFS_MKTAG(LFS_TYPE_STRUCT, 0, 0);
            begin = fromid;
            end = fromid+1;
            diff = toid-fromid+diff;
        } else if (luat_lfs2_tag_type3(tag) == LFS_FROM_USERATTRS) {
            for (unsigned i = 0; i < luat_lfs2_tag_size(tag); i++) {
                const struct luat_lfs2_attr *a = buffer;
                res = cb(data, LFS_MKTAG(LFS_TYPE_USERATTR + a[i].type,
                        luat_lfs2_tag_id(tag) + diff, a[i].size), a[i].buffer);
                if (res < 0) {
                    return res;
                }

                if (res) {
                    break;
                }
            }
        } else {
            res = cb(data, tag + LFS_MKTAG(0, diff, 0), buffer);
            if (res < 0) {
                return res;
            }

            if (res) {
                break;
            }
        }
    }

    if (sp > 0) {
        // pop from the stack and return, fortunately all pops share
        // a destination
        dir         = stack[sp-1].dir;
        off         = stack[sp-1].off;
        ptag        = stack[sp-1].ptag;
        attrs       = stack[sp-1].attrs;
        attrcount   = stack[sp-1].attrcount;
        tmask       = stack[sp-1].tmask;
        ttag        = stack[sp-1].ttag;
        begin       = stack[sp-1].begin;
        end         = stack[sp-1].end;
        diff        = stack[sp-1].diff;
        cb          = stack[sp-1].cb;
        data        = stack[sp-1].data;
        tag         = stack[sp-1].tag;
        buffer      = stack[sp-1].buffer;
        disk        = stack[sp-1].disk;
        sp -= 1;
        goto popped;
    } else {
        return res;
    }
}
#endif

static luat_lfs2_stag_t luat_lfs2_dir_fetchmatch(luat_lfs2_t *lfs,
        luat_lfs2_mdir_t *dir, const luat_lfs2_block_t pair[2],
        luat_lfs2_tag_t fmask, luat_lfs2_tag_t ftag, uint16_t *id,
        int (*cb)(void *data, luat_lfs2_tag_t tag, const void *buffer), void *data) {
    // we can find tag very efficiently during a fetch, since we're already
    // scanning the entire directory
    luat_lfs2_stag_t besttag = -1;

    // if either block address is invalid we return LFS_ERR_CORRUPT here,
    // otherwise later writes to the pair could fail
    if (lfs->block_count 
            && (pair[0] >= lfs->block_count || pair[1] >= lfs->block_count)) {
        return LFS_ERR_CORRUPT;
    }

    // find the block with the most recent revision
    uint32_t revs[2] = {0, 0};
    int r = 0;
    for (int i = 0; i < 2; i++) {
        int err = luat_lfs2_bd_read(lfs,
                NULL, &lfs->rcache, sizeof(revs[i]),
                pair[i], 0, &revs[i], sizeof(revs[i]));
        revs[i] = luat_lfs2_fromle32(revs[i]);
        if (err && err != LFS_ERR_CORRUPT) {
            return err;
        }

        if (err != LFS_ERR_CORRUPT &&
                luat_lfs2_scmp(revs[i], revs[(i+1)%2]) > 0) {
            r = i;
        }
    }

    dir->pair[0] = pair[(r+0)%2];
    dir->pair[1] = pair[(r+1)%2];
    dir->rev = revs[(r+0)%2];
    dir->off = 0; // nonzero = found some commits

    // now scan tags to fetch the actual dir and find possible match
    for (int i = 0; i < 2; i++) {
        luat_lfs2_off_t off = 0;
        luat_lfs2_tag_t ptag = 0xffffffff;

        uint16_t tempcount = 0;
        luat_lfs2_block_t temptail[2] = {LFS_BLOCK_NULL, LFS_BLOCK_NULL};
        bool tempsplit = false;
        luat_lfs2_stag_t tempbesttag = besttag;

        // assume not erased until proven otherwise
        bool maybeerased = false;
        bool hasfcrc = false;
        struct luat_lfs2_fcrc fcrc;

        dir->rev = luat_lfs2_tole32(dir->rev);
        uint32_t crc = luat_lfs2_crc(0xffffffff, &dir->rev, sizeof(dir->rev));
        dir->rev = luat_lfs2_fromle32(dir->rev);

        while (true) {
            // extract next tag
            luat_lfs2_tag_t tag;
            off += luat_lfs2_tag_dsize(ptag);
            int err = luat_lfs2_bd_read(lfs,
                    NULL, &lfs->rcache, lfs->cfg->block_size,
                    dir->pair[0], off, &tag, sizeof(tag));
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    // can't continue?
                    break;
                }
                return err;
            }

            crc = luat_lfs2_crc(crc, &tag, sizeof(tag));
            tag = luat_lfs2_frombe32(tag) ^ ptag;

            // next commit not yet programmed?
            if (!luat_lfs2_tag_isvalid(tag)) {
                // we only might be erased if the last tag was a crc
                maybeerased = (luat_lfs2_tag_type2(ptag) == LFS_TYPE_CCRC);
                break;
            // out of range?
            } else if (off + luat_lfs2_tag_dsize(tag) > lfs->cfg->block_size) {
                break;
            }

            ptag = tag;

            if (luat_lfs2_tag_type2(tag) == LFS_TYPE_CCRC) {
                // check the crc attr
                uint32_t dcrc;
                err = luat_lfs2_bd_read(lfs,
                        NULL, &lfs->rcache, lfs->cfg->block_size,
                        dir->pair[0], off+sizeof(tag), &dcrc, sizeof(dcrc));
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        break;
                    }
                    return err;
                }
                dcrc = luat_lfs2_fromle32(dcrc);

                if (crc != dcrc) {
                    break;
                }

                // reset the next bit if we need to
                ptag ^= (luat_lfs2_tag_t)(luat_lfs2_tag_chunk(tag) & 1U) << 31;

                // toss our crc into the filesystem seed for
                // pseudorandom numbers, note we use another crc here
                // as a collection function because it is sufficiently
                // random and convenient
                lfs->seed = luat_lfs2_crc(lfs->seed, &crc, sizeof(crc));

                // update with what's found so far
                besttag = tempbesttag;
                dir->off = off + luat_lfs2_tag_dsize(tag);
                dir->etag = ptag;
                dir->count = tempcount;
                dir->tail[0] = temptail[0];
                dir->tail[1] = temptail[1];
                dir->split = tempsplit;

                // reset crc, hasfcrc
                crc = 0xffffffff;
                continue;
            }

            // crc the entry first, hopefully leaving it in the cache
            err = luat_lfs2_bd_crc(lfs,
                    NULL, &lfs->rcache, lfs->cfg->block_size,
                    dir->pair[0], off+sizeof(tag),
                    luat_lfs2_tag_dsize(tag)-sizeof(tag), &crc);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    break;
                }
                return err;
            }

            // directory modification tags?
            if (luat_lfs2_tag_type1(tag) == LFS_TYPE_NAME) {
                // increase count of files if necessary
                if (luat_lfs2_tag_id(tag) >= tempcount) {
                    tempcount = luat_lfs2_tag_id(tag) + 1;
                }
            } else if (luat_lfs2_tag_type1(tag) == LFS_TYPE_SPLICE) {
                tempcount += luat_lfs2_tag_splice(tag);

                if (tag == (LFS_MKTAG(LFS_TYPE_DELETE, 0, 0) |
                        (LFS_MKTAG(0, 0x3ff, 0) & tempbesttag))) {
                    tempbesttag |= 0x80000000;
                } else if (tempbesttag != -1 &&
                        luat_lfs2_tag_id(tag) <= luat_lfs2_tag_id(tempbesttag)) {
                    tempbesttag += LFS_MKTAG(0, luat_lfs2_tag_splice(tag), 0);
                }
            } else if (luat_lfs2_tag_type1(tag) == LFS_TYPE_TAIL) {
                tempsplit = (luat_lfs2_tag_chunk(tag) & 1);

                err = luat_lfs2_bd_read(lfs,
                        NULL, &lfs->rcache, lfs->cfg->block_size,
                        dir->pair[0], off+sizeof(tag), &temptail, 8);
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        break;
                    }
                    return err;
                }
                luat_lfs2_pair_fromle32(temptail);
            } else if (luat_lfs2_tag_type3(tag) == LFS_TYPE_FCRC) {
                err = luat_lfs2_bd_read(lfs,
                        NULL, &lfs->rcache, lfs->cfg->block_size,
                        dir->pair[0], off+sizeof(tag),
                        &fcrc, sizeof(fcrc));
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        break;
                    }
                }

                luat_lfs2_fcrc_fromle32(&fcrc);
                hasfcrc = true;
            }

            // found a match for our fetcher?
            if ((fmask & tag) == (fmask & ftag)) {
                int res = cb(data, tag, &(struct luat_lfs2_diskoff){
                        dir->pair[0], off+sizeof(tag)});
                if (res < 0) {
                    if (res == LFS_ERR_CORRUPT) {
                        break;
                    }
                    return res;
                }

                if (res == LFS_CMP_EQ) {
                    // found a match
                    tempbesttag = tag;
                } else if ((LFS_MKTAG(0x7ff, 0x3ff, 0) & tag) ==
                        (LFS_MKTAG(0x7ff, 0x3ff, 0) & tempbesttag)) {
                    // found an identical tag, but contents didn't match
                    // this must mean that our besttag has been overwritten
                    tempbesttag = -1;
                } else if (res == LFS_CMP_GT &&
                        luat_lfs2_tag_id(tag) <= luat_lfs2_tag_id(tempbesttag)) {
                    // found a greater match, keep track to keep things sorted
                    tempbesttag = tag | 0x80000000;
                }
            }
        }

        // found no valid commits?
        if (dir->off == 0) {
            // try the other block?
            luat_lfs2_pair_swap(dir->pair);
            dir->rev = revs[(r+1)%2];
            continue;
        }

        // did we end on a valid commit? we may have an erased block
        dir->erased = false;
        if (maybeerased && dir->off % lfs->cfg->prog_size == 0) {
        #ifdef LFS_MULTIVERSION
            // note versions < lfs2.1 did not have fcrc tags, if
            // we're < lfs2.1 treat missing fcrc as erased data
            //
            // we don't strictly need to do this, but otherwise writing
            // to lfs2.0 disks becomes very inefficient
            if (luat_lfs2_fs_disk_version(lfs) < 0x00020001) {
                dir->erased = true;

            } else
        #endif
            if (hasfcrc) {
                // check for an fcrc matching the next prog's erased state, if
                // this failed most likely a previous prog was interrupted, we
                // need a new erase
                uint32_t fcrc_ = 0xffffffff;
                int err = luat_lfs2_bd_crc(lfs,
                        NULL, &lfs->rcache, lfs->cfg->block_size,
                        dir->pair[0], dir->off, fcrc.size, &fcrc_);
                if (err && err != LFS_ERR_CORRUPT) {
                    return err;
                }

                // found beginning of erased part?
                dir->erased = (fcrc_ == fcrc.crc);
            }
        }

        // synthetic move
        if (luat_lfs2_gstate_hasmovehere(&lfs->gdisk, dir->pair)) {
            if (luat_lfs2_tag_id(lfs->gdisk.tag) == luat_lfs2_tag_id(besttag)) {
                besttag |= 0x80000000;
            } else if (besttag != -1 &&
                    luat_lfs2_tag_id(lfs->gdisk.tag) < luat_lfs2_tag_id(besttag)) {
                besttag -= LFS_MKTAG(0, 1, 0);
            }
        }

        // found tag? or found best id?
        if (id) {
            *id = luat_lfs2_min(luat_lfs2_tag_id(besttag), dir->count);
        }

        if (luat_lfs2_tag_isvalid(besttag)) {
            return besttag;
        } else if (luat_lfs2_tag_id(besttag) < dir->count) {
            return LFS_ERR_NOENT;
        } else {
            return 0;
        }
    }

    LFS_ERROR("Corrupted dir pair at {0x%"PRIx32", 0x%"PRIx32"}",
            dir->pair[0], dir->pair[1]);
    return LFS_ERR_CORRUPT;
}

static int luat_lfs2_dir_fetch(luat_lfs2_t *lfs,
        luat_lfs2_mdir_t *dir, const luat_lfs2_block_t pair[2]) {
    // note, mask=-1, tag=-1 can never match a tag since this
    // pattern has the invalid bit set
    return (int)luat_lfs2_dir_fetchmatch(lfs, dir, pair,
            (luat_lfs2_tag_t)-1, (luat_lfs2_tag_t)-1, NULL, NULL, NULL);
}

static int luat_lfs2_dir_getgstate(luat_lfs2_t *lfs, const luat_lfs2_mdir_t *dir,
        luat_lfs2_gstate_t *gstate) {
    luat_lfs2_gstate_t temp;
    luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, dir, LFS_MKTAG(0x7ff, 0, 0),
            LFS_MKTAG(LFS_TYPE_MOVESTATE, 0, sizeof(temp)), &temp);
    if (res < 0 && res != LFS_ERR_NOENT) {
        return res;
    }

    if (res != LFS_ERR_NOENT) {
        // xor together to find resulting gstate
        luat_lfs2_gstate_fromle32(&temp);
        luat_lfs2_gstate_xor(gstate, &temp);
    }

    return 0;
}

static int luat_lfs2_dir_getinfo(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        uint16_t id, struct luat_lfs2_info *info) {
    if (id == 0x3ff) {
        // special case for root
        strcpy(info->name, "/");
        info->type = LFS_TYPE_DIR;
        return 0;
    }

    luat_lfs2_stag_t tag = luat_lfs2_dir_get(lfs, dir, LFS_MKTAG(0x780, 0x3ff, 0),
            LFS_MKTAG(LFS_TYPE_NAME, id, lfs->name_max+1), info->name);
    if (tag < 0) {
        return (int)tag;
    }

    info->type = luat_lfs2_tag_type3(tag);

    struct luat_lfs2_ctz ctz;
    tag = luat_lfs2_dir_get(lfs, dir, LFS_MKTAG(0x700, 0x3ff, 0),
            LFS_MKTAG(LFS_TYPE_STRUCT, id, sizeof(ctz)), &ctz);
    if (tag < 0) {
        return (int)tag;
    }
    luat_lfs2_ctz_fromle32(&ctz);

    if (luat_lfs2_tag_type3(tag) == LFS_TYPE_CTZSTRUCT) {
        info->size = ctz.size;
    } else if (luat_lfs2_tag_type3(tag) == LFS_TYPE_INLINESTRUCT) {
        info->size = luat_lfs2_tag_size(tag);
    }

    return 0;
}

struct luat_lfs2_dir_find_match {
    luat_lfs2_t *lfs;
    const void *name;
    luat_lfs2_size_t size;
};

static int luat_lfs2_dir_find_match(void *data,
        luat_lfs2_tag_t tag, const void *buffer) {
    struct luat_lfs2_dir_find_match *name = data;
    luat_lfs2_t *lfs = name->lfs;
    const struct luat_lfs2_diskoff *disk = buffer;

    // compare with disk
    luat_lfs2_size_t diff = luat_lfs2_min(name->size, luat_lfs2_tag_size(tag));
    int res = luat_lfs2_bd_cmp(lfs,
            NULL, &lfs->rcache, diff,
            disk->block, disk->off, name->name, diff);
    if (res != LFS_CMP_EQ) {
        return res;
    }

    // only equal if our size is still the same
    if (name->size != luat_lfs2_tag_size(tag)) {
        return (name->size < luat_lfs2_tag_size(tag)) ? LFS_CMP_LT : LFS_CMP_GT;
    }

    // found a match!
    return LFS_CMP_EQ;
}

static luat_lfs2_stag_t luat_lfs2_dir_find(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const char **path, uint16_t *id) {
    // we reduce path to a single name if we can find it
    const char *name = *path;
    if (id) {
        *id = 0x3ff;
    }

    // default to root dir
    luat_lfs2_stag_t tag = LFS_MKTAG(LFS_TYPE_DIR, 0x3ff, 0);
    dir->tail[0] = lfs->root[0];
    dir->tail[1] = lfs->root[1];

    while (true) {
nextname:
        // skip slashes
        name += strspn(name, "/");
        luat_lfs2_size_t namelen = strcspn(name, "/");

        // skip '.' and root '..'
        if ((namelen == 1 && memcmp(name, ".", 1) == 0) ||
            (namelen == 2 && memcmp(name, "..", 2) == 0)) {
            name += namelen;
            goto nextname;
        }

        // skip if matched by '..' in name
        const char *suffix = name + namelen;
        luat_lfs2_size_t sufflen;
        int depth = 1;
        while (true) {
            suffix += strspn(suffix, "/");
            sufflen = strcspn(suffix, "/");
            if (sufflen == 0) {
                break;
            }

            if (sufflen == 2 && memcmp(suffix, "..", 2) == 0) {
                depth -= 1;
                if (depth == 0) {
                    name = suffix + sufflen;
                    goto nextname;
                }
            } else {
                depth += 1;
            }

            suffix += sufflen;
        }

        // found path
        if (name[0] == '\0') {
            return tag;
        }

        // update what we've found so far
        *path = name;

        // only continue if we hit a directory
        if (luat_lfs2_tag_type3(tag) != LFS_TYPE_DIR) {
            return LFS_ERR_NOTDIR;
        }

        // grab the entry data
        if (luat_lfs2_tag_id(tag) != 0x3ff) {
            luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, dir, LFS_MKTAG(0x700, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_STRUCT, luat_lfs2_tag_id(tag), 8), dir->tail);
            if (res < 0) {
                return res;
            }
            luat_lfs2_pair_fromle32(dir->tail);
        }

        // find entry matching name
        while (true) {
            tag = luat_lfs2_dir_fetchmatch(lfs, dir, dir->tail,
                    LFS_MKTAG(0x780, 0, 0),
                    LFS_MKTAG(LFS_TYPE_NAME, 0, namelen),
                     // are we last name?
                    (strchr(name, '/') == NULL) ? id : NULL,
                    luat_lfs2_dir_find_match, &(struct luat_lfs2_dir_find_match){
                        lfs, name, namelen});
            if (tag < 0) {
                return tag;
            }

            if (tag) {
                break;
            }

            if (!dir->split) {
                return LFS_ERR_NOENT;
            }
        }

        // to next name
        name += namelen;
    }
}

// commit logic
struct luat_lfs2_commit {
    luat_lfs2_block_t block;
    luat_lfs2_off_t off;
    luat_lfs2_tag_t ptag;
    uint32_t crc;

    luat_lfs2_off_t begin;
    luat_lfs2_off_t end;
};

#ifndef LFS_READONLY
static int luat_lfs2_dir_commitprog(luat_lfs2_t *lfs, struct luat_lfs2_commit *commit,
        const void *buffer, luat_lfs2_size_t size) {
    int err = luat_lfs2_bd_prog(lfs,
            &lfs->pcache, &lfs->rcache, false,
            commit->block, commit->off ,
            (const uint8_t*)buffer, size);
    if (err) {
        return err;
    }

    commit->crc = luat_lfs2_crc(commit->crc, buffer, size);
    commit->off += size;
    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_commitattr(luat_lfs2_t *lfs, struct luat_lfs2_commit *commit,
        luat_lfs2_tag_t tag, const void *buffer) {
    // check if we fit
    luat_lfs2_size_t dsize = luat_lfs2_tag_dsize(tag);
    if (commit->off + dsize > commit->end) {
        return LFS_ERR_NOSPC;
    }

    // write out tag
    luat_lfs2_tag_t ntag = luat_lfs2_tobe32((tag & 0x7fffffff) ^ commit->ptag);
    int err = luat_lfs2_dir_commitprog(lfs, commit, &ntag, sizeof(ntag));
    if (err) {
        return err;
    }

    if (!(tag & 0x80000000)) {
        // from memory
        err = luat_lfs2_dir_commitprog(lfs, commit, buffer, dsize-sizeof(tag));
        if (err) {
            return err;
        }
    } else {
        // from disk
        const struct luat_lfs2_diskoff *disk = buffer;
        for (luat_lfs2_off_t i = 0; i < dsize-sizeof(tag); i++) {
            // rely on caching to make this efficient
            uint8_t dat;
            err = luat_lfs2_bd_read(lfs,
                    NULL, &lfs->rcache, dsize-sizeof(tag)-i,
                    disk->block, disk->off+i, &dat, 1);
            if (err) {
                return err;
            }

            err = luat_lfs2_dir_commitprog(lfs, commit, &dat, 1);
            if (err) {
                return err;
            }
        }
    }

    commit->ptag = tag & 0x7fffffff;
    return 0;
}
#endif

#ifndef LFS_READONLY

static int luat_lfs2_dir_commitcrc(luat_lfs2_t *lfs, struct luat_lfs2_commit *commit) {
    // align to program units
    //
    // this gets a bit complex as we have two types of crcs:
    // - 5-word crc with fcrc to check following prog (middle of block)
    // - 2-word crc with no following prog (end of block)
    const luat_lfs2_off_t end = luat_lfs2_alignup(
            luat_lfs2_min(commit->off + 5*sizeof(uint32_t), lfs->cfg->block_size),
            lfs->cfg->prog_size);

    luat_lfs2_off_t off1 = 0;
    uint32_t crc1 = 0;

    // create crc tags to fill up remainder of commit, note that
    // padding is not crced, which lets fetches skip padding but
    // makes committing a bit more complicated
    while (commit->off < end) {
        luat_lfs2_off_t noff = (
                luat_lfs2_min(end - (commit->off+sizeof(luat_lfs2_tag_t)), 0x3fe)
                + (commit->off+sizeof(luat_lfs2_tag_t)));
        // too large for crc tag? need padding commits
        if (noff < end) {
            noff = luat_lfs2_min(noff, end - 5*sizeof(uint32_t));
        }

        // space for fcrc?
        uint8_t eperturb = (uint8_t)-1;
        if (noff >= end && noff <= lfs->cfg->block_size - lfs->cfg->prog_size) {
            // first read the leading byte, this always contains a bit
            // we can perturb to avoid writes that don't change the fcrc
            int err = luat_lfs2_bd_read(lfs,
                    NULL, &lfs->rcache, lfs->cfg->prog_size,
                    commit->block, noff, &eperturb, 1);
            if (err && err != LFS_ERR_CORRUPT) {
                return err;
            }

        #ifdef LFS_MULTIVERSION
            // unfortunately fcrcs break mdir fetching < lfs2.1, so only write
            // these if we're a >= lfs2.1 filesystem
            if (luat_lfs2_fs_disk_version(lfs) <= 0x00020000) {
                // don't write fcrc
            } else
        #endif
            {
                // find the expected fcrc, don't bother avoiding a reread
                // of the eperturb, it should still be in our cache
                struct luat_lfs2_fcrc fcrc = {
                    .size = lfs->cfg->prog_size,
                    .crc = 0xffffffff
                };
                err = luat_lfs2_bd_crc(lfs,
                        NULL, &lfs->rcache, lfs->cfg->prog_size,
                        commit->block, noff, fcrc.size, &fcrc.crc);
                if (err && err != LFS_ERR_CORRUPT) {
                    return err;
                }

                luat_lfs2_fcrc_tole32(&fcrc);
                err = luat_lfs2_dir_commitattr(lfs, commit,
                        LFS_MKTAG(LFS_TYPE_FCRC, 0x3ff, sizeof(struct luat_lfs2_fcrc)),
                        &fcrc);
                if (err) {
                    return err;
                }
            }
        }

        // build commit crc
        struct {
            luat_lfs2_tag_t tag;
            uint32_t crc;
        } ccrc;
        luat_lfs2_tag_t ntag = LFS_MKTAG(
                LFS_TYPE_CCRC + (((uint8_t)~eperturb) >> 7), 0x3ff,
                noff - (commit->off+sizeof(luat_lfs2_tag_t)));
        ccrc.tag = luat_lfs2_tobe32(ntag ^ commit->ptag);
        commit->crc = luat_lfs2_crc(commit->crc, &ccrc.tag, sizeof(luat_lfs2_tag_t));
        ccrc.crc = luat_lfs2_tole32(commit->crc);

        int err = luat_lfs2_bd_prog(lfs,
                &lfs->pcache, &lfs->rcache, false,
                commit->block, commit->off, &ccrc, sizeof(ccrc));
        if (err) {
            return err;
        }

        // keep track of non-padding checksum to verify
        if (off1 == 0) {
            off1 = commit->off + sizeof(luat_lfs2_tag_t);
            crc1 = commit->crc;
        }

        commit->off = noff;
        // perturb valid bit?
        commit->ptag = ntag ^ ((0x80UL & ~eperturb) << 24);
        // reset crc for next commit
        commit->crc = 0xffffffff;

        // manually flush here since we don't prog the padding, this confuses
        // the caching layer
        if (noff >= end || noff >= lfs->pcache.off + lfs->cfg->cache_size) {
            // flush buffers
            int err = luat_lfs2_bd_sync(lfs, &lfs->pcache, &lfs->rcache, false);
            if (err) {
                return err;
            }
        }
    }

    // successful commit, check checksums to make sure
    //
    // note that we don't need to check padding commits, worst
    // case if they are corrupted we would have had to compact anyways
    luat_lfs2_off_t off = commit->begin;
    uint32_t crc = 0xffffffff;
    int err = luat_lfs2_bd_crc(lfs,
            NULL, &lfs->rcache, off1+sizeof(uint32_t),
            commit->block, off, off1-off, &crc);
    if (err) {
        return err;
    }

    // check non-padding commits against known crc
    if (crc != crc1) {
        return LFS_ERR_CORRUPT;
    }

    // make sure to check crc in case we happen to pick
    // up an unrelated crc (frozen block?)
    err = luat_lfs2_bd_crc(lfs,
            NULL, &lfs->rcache, sizeof(uint32_t),
            commit->block, off1, sizeof(uint32_t), &crc);
    if (err) {
        return err;
    }

    if (crc != 0) {
        return LFS_ERR_CORRUPT;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_alloc(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir) {
    // allocate pair of dir blocks (backwards, so we write block 1 first)
    for (int i = 0; i < 2; i++) {
        int err = luat_lfs2_alloc(lfs, &dir->pair[(i+1)%2]);
        if (err) {
            return err;
        }
    }

    // zero for reproducibility in case initial block is unreadable
    dir->rev = 0;

    // rather than clobbering one of the blocks we just pretend
    // the revision may be valid
    int err = luat_lfs2_bd_read(lfs,
            NULL, &lfs->rcache, sizeof(dir->rev),
            dir->pair[0], 0, &dir->rev, sizeof(dir->rev));
    dir->rev = luat_lfs2_fromle32(dir->rev);
    if (err && err != LFS_ERR_CORRUPT) {
        return err;
    }

    // to make sure we don't immediately evict, align the new revision count
    // to our block_cycles modulus, see luat_lfs2_dir_compact for why our modulus
    // is tweaked this way
    if (lfs->cfg->block_cycles > 0) {
        dir->rev = luat_lfs2_alignup(dir->rev, ((lfs->cfg->block_cycles+1)|1));
    }

    // set defaults
    dir->off = sizeof(dir->rev);
    dir->etag = 0xffffffff;
    dir->count = 0;
    dir->tail[0] = LFS_BLOCK_NULL;
    dir->tail[1] = LFS_BLOCK_NULL;
    dir->erased = false;
    dir->split = false;

    // don't write out yet, let caller take care of that
    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_drop(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir, luat_lfs2_mdir_t *tail) {
    // steal state
    int err = luat_lfs2_dir_getgstate(lfs, tail, &lfs->gdelta);
    if (err) {
        return err;
    }

    // steal tail
    luat_lfs2_pair_tole32(tail->tail);
    err = luat_lfs2_dir_commit(lfs, dir, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_TAIL + tail->split, 0x3ff, 8), tail->tail}));
    luat_lfs2_pair_fromle32(tail->tail);
    if (err) {
        return err;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_split(luat_lfs2_t *lfs,
        luat_lfs2_mdir_t *dir, const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_mdir_t *source, uint16_t split, uint16_t end) {
    // create tail metadata pair
    luat_lfs2_mdir_t tail;
    int err = luat_lfs2_dir_alloc(lfs, &tail);
    if (err) {
        return err;
    }

    tail.split = dir->split;
    tail.tail[0] = dir->tail[0];
    tail.tail[1] = dir->tail[1];

    // note we don't care about LFS_OK_RELOCATED
    int res = luat_lfs2_dir_compact(lfs, &tail, attrs, attrcount, source, split, end);
    if (res < 0) {
        return res;
    }

    dir->tail[0] = tail.pair[0];
    dir->tail[1] = tail.pair[1];
    dir->split = true;

    // update root if needed
    if (luat_lfs2_pair_cmp(dir->pair, lfs->root) == 0 && split == 0) {
        lfs->root[0] = tail.pair[0];
        lfs->root[1] = tail.pair[1];
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_commit_size(void *p, luat_lfs2_tag_t tag, const void *buffer) {
    luat_lfs2_size_t *size = p;
    (void)buffer;

    *size += luat_lfs2_tag_dsize(tag);
    return 0;
}
#endif

#ifndef LFS_READONLY
struct luat_lfs2_dir_commit_commit {
    luat_lfs2_t *lfs;
    struct luat_lfs2_commit *commit;
};
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_commit_commit(void *p, luat_lfs2_tag_t tag, const void *buffer) {
    struct luat_lfs2_dir_commit_commit *commit = p;
    return luat_lfs2_dir_commitattr(commit->lfs, commit->commit, tag, buffer);
}
#endif

#ifndef LFS_READONLY
static bool luat_lfs2_dir_needsrelocation(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir) {
    // If our revision count == n * block_cycles, we should force a relocation,
    // this is how littlefs wear-levels at the metadata-pair level. Note that we
    // actually use (block_cycles+1)|1, this is to avoid two corner cases:
    // 1. block_cycles = 1, which would prevent relocations from terminating
    // 2. block_cycles = 2n, which, due to aliasing, would only ever relocate
    //    one metadata block in the pair, effectively making this useless
    return (lfs->cfg->block_cycles > 0
            && ((dir->rev + 1) % ((lfs->cfg->block_cycles+1)|1) == 0));
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_compact(luat_lfs2_t *lfs,
        luat_lfs2_mdir_t *dir, const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_mdir_t *source, uint16_t begin, uint16_t end) {
    // save some state in case block is bad
    bool relocated = false;
    bool tired = luat_lfs2_dir_needsrelocation(lfs, dir);

    // increment revision count
    dir->rev += 1;

    // do not proactively relocate blocks during migrations, this
    // can cause a number of failure states such: clobbering the
    // v1 superblock if we relocate root, and invalidating directory
    // pointers if we relocate the head of a directory. On top of
    // this, relocations increase the overall complexity of
    // luat_lfs2_migration, which is already a delicate operation.
#ifdef LFS_MIGRATE
    if (lfs->lfs1) {
        tired = false;
    }
#endif

    if (tired && luat_lfs2_pair_cmp(dir->pair, (const luat_lfs2_block_t[2]){0, 1}) != 0) {
        // we're writing too much, time to relocate
        goto relocate;
    }

    // begin loop to commit compaction to blocks until a compact sticks
    while (true) {
        {
            // setup commit state
            struct luat_lfs2_commit commit = {
                .block = dir->pair[1],
                .off = 0,
                .ptag = 0xffffffff,
                .crc = 0xffffffff,

                .begin = 0,
                .end = (lfs->cfg->metadata_max ?
                    lfs->cfg->metadata_max : lfs->cfg->block_size) - 8,
            };

            // erase block to write to
            int err = luat_lfs2_bd_erase(lfs, dir->pair[1]);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }

            // write out header
            dir->rev = luat_lfs2_tole32(dir->rev);
            err = luat_lfs2_dir_commitprog(lfs, &commit,
                    &dir->rev, sizeof(dir->rev));
            dir->rev = luat_lfs2_fromle32(dir->rev);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }

            // traverse the directory, this time writing out all unique tags
            err = luat_lfs2_dir_traverse(lfs,
                    source, 0, 0xffffffff, attrs, attrcount,
                    LFS_MKTAG(0x400, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_NAME, 0, 0),
                    begin, end, -begin,
                    luat_lfs2_dir_commit_commit, &(struct luat_lfs2_dir_commit_commit){
                        lfs, &commit});
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }

            // commit tail, which may be new after last size check
            if (!luat_lfs2_pair_isnull(dir->tail)) {
                luat_lfs2_pair_tole32(dir->tail);
                err = luat_lfs2_dir_commitattr(lfs, &commit,
                        LFS_MKTAG(LFS_TYPE_TAIL + dir->split, 0x3ff, 8),
                        dir->tail);
                luat_lfs2_pair_fromle32(dir->tail);
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        goto relocate;
                    }
                    return err;
                }
            }

            // bring over gstate?
            luat_lfs2_gstate_t delta = {0};
            if (!relocated) {
                luat_lfs2_gstate_xor(&delta, &lfs->gdisk);
                luat_lfs2_gstate_xor(&delta, &lfs->gstate);
            }
            luat_lfs2_gstate_xor(&delta, &lfs->gdelta);
            delta.tag &= ~LFS_MKTAG(0, 0, 0x3ff);

            err = luat_lfs2_dir_getgstate(lfs, dir, &delta);
            if (err) {
                return err;
            }

            if (!luat_lfs2_gstate_iszero(&delta)) {
                luat_lfs2_gstate_tole32(&delta);
                err = luat_lfs2_dir_commitattr(lfs, &commit,
                        LFS_MKTAG(LFS_TYPE_MOVESTATE, 0x3ff,
                            sizeof(delta)), &delta);
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        goto relocate;
                    }
                    return err;
                }
            }

            // complete commit with crc
            err = luat_lfs2_dir_commitcrc(lfs, &commit);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }

            // successful compaction, swap dir pair to indicate most recent
            LFS_ASSERT(commit.off % lfs->cfg->prog_size == 0);
            luat_lfs2_pair_swap(dir->pair);
            dir->count = end - begin;
            dir->off = commit.off;
            dir->etag = commit.ptag;
            // update gstate
            lfs->gdelta = (luat_lfs2_gstate_t){0};
            if (!relocated) {
                lfs->gdisk = lfs->gstate;
            }
        }
        break;

relocate:
        // commit was corrupted, drop caches and prepare to relocate block
        relocated = true;
        luat_lfs2_cache_drop(lfs, &lfs->pcache);
        if (!tired) {
            LFS_DEBUG("Bad block at 0x%"PRIx32, dir->pair[1]);
        }

        // can't relocate superblock, filesystem is now frozen
        if (luat_lfs2_pair_cmp(dir->pair, (const luat_lfs2_block_t[2]){0, 1}) == 0) {
            LFS_WARN("Superblock 0x%"PRIx32" has become unwritable",
                    dir->pair[1]);
            return LFS_ERR_NOSPC;
        }

        // relocate half of pair
        int err = luat_lfs2_alloc(lfs, &dir->pair[1]);
        if (err && (err != LFS_ERR_NOSPC || !tired)) {
            return err;
        }

        tired = false;
        continue;
    }

    return relocated ? LFS_OK_RELOCATED : 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_splittingcompact(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_mdir_t *source, uint16_t begin, uint16_t end) {
    while (true) {
        // find size of first split, we do this by halving the split until
        // the metadata is guaranteed to fit
        //
        // Note that this isn't a true binary search, we never increase the
        // split size. This may result in poorly distributed metadata but isn't
        // worth the extra code size or performance hit to fix.
        luat_lfs2_size_t split = begin;
        while (end - split > 1) {
            luat_lfs2_size_t size = 0;
            int err = luat_lfs2_dir_traverse(lfs,
                    source, 0, 0xffffffff, attrs, attrcount,
                    LFS_MKTAG(0x400, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_NAME, 0, 0),
                    split, end, -split,
                    luat_lfs2_dir_commit_size, &size);
            if (err) {
                return err;
            }

            // space is complicated, we need room for:
            //
            // - tail:         4+2*4 = 12 bytes
            // - gstate:       4+3*4 = 16 bytes
            // - move delete:  4     = 4 bytes
            // - crc:          4+4   = 8 bytes
            //                 total = 40 bytes
            //
            // And we cap at half a block to avoid degenerate cases with
            // nearly-full metadata blocks.
            //
            if (end - split < 0xff
                    && size <= luat_lfs2_min(
                        lfs->cfg->block_size - 40,
                        luat_lfs2_alignup(
                            (lfs->cfg->metadata_max
                                ? lfs->cfg->metadata_max
                                : lfs->cfg->block_size)/2,
                            lfs->cfg->prog_size))) {
                break;
            }

            split = split + ((end - split) / 2);
        }

        if (split == begin) {
            // no split needed
            break;
        }

        // split into two metadata pairs and continue
        int err = luat_lfs2_dir_split(lfs, dir, attrs, attrcount,
                source, split, end);
        if (err && err != LFS_ERR_NOSPC) {
            return err;
        }

        if (err) {
            // we can't allocate a new block, try to compact with degraded
            // performance
            LFS_WARN("Unable to split {0x%"PRIx32", 0x%"PRIx32"}",
                    dir->pair[0], dir->pair[1]);
            break;
        } else {
            end = split;
        }
    }

    if (luat_lfs2_dir_needsrelocation(lfs, dir)
            && luat_lfs2_pair_cmp(dir->pair, (const luat_lfs2_block_t[2]){0, 1}) == 0) {
        // oh no! we're writing too much to the superblock,
        // should we expand?
        luat_lfs2_ssize_t size = luat_lfs2_fs_size_(lfs);
        if (size < 0) {
            return size;
        }

        // littlefs cannot reclaim expanded superblocks, so expand cautiously
        //
        // if our filesystem is more than ~88% full, don't expand, this is
        // somewhat arbitrary
        if (lfs->block_count - size > lfs->block_count/8) {
            LFS_DEBUG("Expanding superblock at rev %"PRIu32, dir->rev);
            int err = luat_lfs2_dir_split(lfs, dir, attrs, attrcount,
                    source, begin, end);
            if (err && err != LFS_ERR_NOSPC) {
                return err;
            }

            if (err) {
                // welp, we tried, if we ran out of space there's not much
                // we can do, we'll error later if we've become frozen
                LFS_WARN("Unable to expand superblock");
            } else {
                // duplicate the superblock entry into the new superblock
                end = 1;
            }
        }
    }

    return luat_lfs2_dir_compact(lfs, dir, attrs, attrcount, source, begin, end);
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_relocatingcommit(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const luat_lfs2_block_t pair[2],
        const struct luat_lfs2_mattr *attrs, int attrcount,
        luat_lfs2_mdir_t *pdir) {
    int state = 0;

    // calculate changes to the directory
    bool hasdelete = false;
    for (int i = 0; i < attrcount; i++) {
        if (luat_lfs2_tag_type3(attrs[i].tag) == LFS_TYPE_CREATE) {
            dir->count += 1;
        } else if (luat_lfs2_tag_type3(attrs[i].tag) == LFS_TYPE_DELETE) {
            LFS_ASSERT(dir->count > 0);
            dir->count -= 1;
            hasdelete = true;
        } else if (luat_lfs2_tag_type1(attrs[i].tag) == LFS_TYPE_TAIL) {
            dir->tail[0] = ((luat_lfs2_block_t*)attrs[i].buffer)[0];
            dir->tail[1] = ((luat_lfs2_block_t*)attrs[i].buffer)[1];
            dir->split = (luat_lfs2_tag_chunk(attrs[i].tag) & 1);
            luat_lfs2_pair_fromle32(dir->tail);
        }
    }

    // should we actually drop the directory block?
    if (hasdelete && dir->count == 0) {
        LFS_ASSERT(pdir);
        int err = luat_lfs2_fs_pred(lfs, dir->pair, pdir);
        if (err && err != LFS_ERR_NOENT) {
            return err;
        }

        if (err != LFS_ERR_NOENT && pdir->split) {
            state = LFS_OK_DROPPED;
            goto fixmlist;
        }
    }

    if (dir->erased) {
        // try to commit
        struct luat_lfs2_commit commit = {
            .block = dir->pair[0],
            .off = dir->off,
            .ptag = dir->etag,
            .crc = 0xffffffff,

            .begin = dir->off,
            .end = (lfs->cfg->metadata_max ?
                lfs->cfg->metadata_max : lfs->cfg->block_size) - 8,
        };

        // traverse attrs that need to be written out
        luat_lfs2_pair_tole32(dir->tail);
        int err = luat_lfs2_dir_traverse(lfs,
                dir, dir->off, dir->etag, attrs, attrcount,
                0, 0, 0, 0, 0,
                luat_lfs2_dir_commit_commit, &(struct luat_lfs2_dir_commit_commit){
                    lfs, &commit});
        luat_lfs2_pair_fromle32(dir->tail);
        if (err) {
            if (err == LFS_ERR_NOSPC || err == LFS_ERR_CORRUPT) {
                goto compact;
            }
            return err;
        }

        // commit any global diffs if we have any
        luat_lfs2_gstate_t delta = {0};
        luat_lfs2_gstate_xor(&delta, &lfs->gstate);
        luat_lfs2_gstate_xor(&delta, &lfs->gdisk);
        luat_lfs2_gstate_xor(&delta, &lfs->gdelta);
        delta.tag &= ~LFS_MKTAG(0, 0, 0x3ff);
        if (!luat_lfs2_gstate_iszero(&delta)) {
            err = luat_lfs2_dir_getgstate(lfs, dir, &delta);
            if (err) {
                return err;
            }

            luat_lfs2_gstate_tole32(&delta);
            err = luat_lfs2_dir_commitattr(lfs, &commit,
                    LFS_MKTAG(LFS_TYPE_MOVESTATE, 0x3ff,
                        sizeof(delta)), &delta);
            if (err) {
                if (err == LFS_ERR_NOSPC || err == LFS_ERR_CORRUPT) {
                    goto compact;
                }
                return err;
            }
        }

        // finalize commit with the crc
        err = luat_lfs2_dir_commitcrc(lfs, &commit);
        if (err) {
            if (err == LFS_ERR_NOSPC || err == LFS_ERR_CORRUPT) {
                goto compact;
            }
            return err;
        }

        // successful commit, update dir
        LFS_ASSERT(commit.off % lfs->cfg->prog_size == 0);
        dir->off = commit.off;
        dir->etag = commit.ptag;
        // and update gstate
        lfs->gdisk = lfs->gstate;
        lfs->gdelta = (luat_lfs2_gstate_t){0};

        goto fixmlist;
    }

compact:
    // fall back to compaction
    luat_lfs2_cache_drop(lfs, &lfs->pcache);

    state = luat_lfs2_dir_splittingcompact(lfs, dir, attrs, attrcount,
            dir, 0, dir->count);
    if (state < 0) {
        return state;
    }

    goto fixmlist;

fixmlist:;
    // this complicated bit of logic is for fixing up any active
    // metadata-pairs that we may have affected
    //
    // note we have to make two passes since the mdir passed to
    // luat_lfs2_dir_commit could also be in this list, and even then
    // we need to copy the pair so they don't get clobbered if we refetch
    // our mdir.
    luat_lfs2_block_t oldpair[2] = {pair[0], pair[1]};
    for (struct luat_lfs2_mlist *d = lfs->mlist; d; d = d->next) {
        if (luat_lfs2_pair_cmp(d->m.pair, oldpair) == 0) {
            d->m = *dir;
            if (d->m.pair != pair) {
                for (int i = 0; i < attrcount; i++) {
                    if (luat_lfs2_tag_type3(attrs[i].tag) == LFS_TYPE_DELETE &&
                            d->id == luat_lfs2_tag_id(attrs[i].tag)) {
                        d->m.pair[0] = LFS_BLOCK_NULL;
                        d->m.pair[1] = LFS_BLOCK_NULL;
                    } else if (luat_lfs2_tag_type3(attrs[i].tag) == LFS_TYPE_DELETE &&
                            d->id > luat_lfs2_tag_id(attrs[i].tag)) {
                        d->id -= 1;
                        if (d->type == LFS_TYPE_DIR) {
                            ((luat_lfs2_dir_t*)d)->pos -= 1;
                        }
                    } else if (luat_lfs2_tag_type3(attrs[i].tag) == LFS_TYPE_CREATE &&
                            d->id >= luat_lfs2_tag_id(attrs[i].tag)) {
                        d->id += 1;
                        if (d->type == LFS_TYPE_DIR) {
                            ((luat_lfs2_dir_t*)d)->pos += 1;
                        }
                    }
                }
            }

            while (d->id >= d->m.count && d->m.split) {
                // we split and id is on tail now
                if (luat_lfs2_pair_cmp(d->m.tail, lfs->root) != 0) {
                    d->id -= d->m.count;
                }
                int err = luat_lfs2_dir_fetch(lfs, &d->m, d->m.tail);
                if (err) {
                    return err;
                }
            }
        }
    }

    return state;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_orphaningcommit(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const struct luat_lfs2_mattr *attrs, int attrcount) {
    // check for any inline files that aren't RAM backed and
    // forcefully evict them, needed for filesystem consistency
    for (luat_lfs2_file_t *f = (luat_lfs2_file_t*)lfs->mlist; f; f = f->next) {
        if (dir != &f->m && luat_lfs2_pair_cmp(f->m.pair, dir->pair) == 0 &&
                f->type == LFS_TYPE_REG && (f->flags & LFS_F_INLINE) &&
                f->ctz.size > lfs->cfg->cache_size) {
            int err = luat_lfs2_file_outline(lfs, f);
            if (err) {
                return err;
            }

            err = luat_lfs2_file_flush(lfs, f);
            if (err) {
                return err;
            }
        }
    }

    luat_lfs2_block_t lpair[2] = {dir->pair[0], dir->pair[1]};
    luat_lfs2_mdir_t ldir = *dir;
    luat_lfs2_mdir_t pdir;
    int state = luat_lfs2_dir_relocatingcommit(lfs, &ldir, dir->pair,
            attrs, attrcount, &pdir);
    if (state < 0) {
        return state;
    }

    // update if we're not in mlist, note we may have already been
    // updated if we are in mlist
    if (luat_lfs2_pair_cmp(dir->pair, lpair) == 0) {
        *dir = ldir;
    }

    // commit was successful, but may require other changes in the
    // filesystem, these would normally be tail recursive, but we have
    // flattened them here avoid unbounded stack usage

    // need to drop?
    if (state == LFS_OK_DROPPED) {
        // steal state
        int err = luat_lfs2_dir_getgstate(lfs, dir, &lfs->gdelta);
        if (err) {
            return err;
        }

        // steal tail, note that this can't create a recursive drop
        lpair[0] = pdir.pair[0];
        lpair[1] = pdir.pair[1];
        luat_lfs2_pair_tole32(dir->tail);
        state = luat_lfs2_dir_relocatingcommit(lfs, &pdir, lpair, LFS_MKATTRS(
                    {LFS_MKTAG(LFS_TYPE_TAIL + dir->split, 0x3ff, 8),
                        dir->tail}),
                NULL);
        luat_lfs2_pair_fromle32(dir->tail);
        if (state < 0) {
            return state;
        }

        ldir = pdir;
    }

    // need to relocate?
    bool orphans = false;
    while (state == LFS_OK_RELOCATED) {
        LFS_DEBUG("Relocating {0x%"PRIx32", 0x%"PRIx32"} "
                    "-> {0x%"PRIx32", 0x%"PRIx32"}",
                lpair[0], lpair[1], ldir.pair[0], ldir.pair[1]);
        state = 0;

        // update internal root
        if (luat_lfs2_pair_cmp(lpair, lfs->root) == 0) {
            lfs->root[0] = ldir.pair[0];
            lfs->root[1] = ldir.pair[1];
        }

        // update internally tracked dirs
        for (struct luat_lfs2_mlist *d = lfs->mlist; d; d = d->next) {
            if (luat_lfs2_pair_cmp(lpair, d->m.pair) == 0) {
                d->m.pair[0] = ldir.pair[0];
                d->m.pair[1] = ldir.pair[1];
            }

            if (d->type == LFS_TYPE_DIR &&
                    luat_lfs2_pair_cmp(lpair, ((luat_lfs2_dir_t*)d)->head) == 0) {
                ((luat_lfs2_dir_t*)d)->head[0] = ldir.pair[0];
                ((luat_lfs2_dir_t*)d)->head[1] = ldir.pair[1];
            }
        }

        // find parent
        luat_lfs2_stag_t tag = luat_lfs2_fs_parent(lfs, lpair, &pdir);
        if (tag < 0 && tag != LFS_ERR_NOENT) {
            return tag;
        }

        bool hasparent = (tag != LFS_ERR_NOENT);
        if (tag != LFS_ERR_NOENT) {
            // note that if we have a parent, we must have a pred, so this will
            // always create an orphan
            int err = luat_lfs2_fs_preporphans(lfs, +1);
            if (err) {
                return err;
            }

            // fix pending move in this pair? this looks like an optimization but
            // is in fact _required_ since relocating may outdate the move.
            uint16_t moveid = 0x3ff;
            if (luat_lfs2_gstate_hasmovehere(&lfs->gstate, pdir.pair)) {
                moveid = luat_lfs2_tag_id(lfs->gstate.tag);
                LFS_DEBUG("Fixing move while relocating "
                        "{0x%"PRIx32", 0x%"PRIx32"} 0x%"PRIx16"\n",
                        pdir.pair[0], pdir.pair[1], moveid);
                luat_lfs2_fs_prepmove(lfs, 0x3ff, NULL);
                if (moveid < luat_lfs2_tag_id(tag)) {
                    tag -= LFS_MKTAG(0, 1, 0);
                }
            }

            luat_lfs2_block_t ppair[2] = {pdir.pair[0], pdir.pair[1]};
            luat_lfs2_pair_tole32(ldir.pair);
            state = luat_lfs2_dir_relocatingcommit(lfs, &pdir, ppair, LFS_MKATTRS(
                        {LFS_MKTAG_IF(moveid != 0x3ff,
                            LFS_TYPE_DELETE, moveid, 0), NULL},
                        {tag, ldir.pair}),
                    NULL);
            luat_lfs2_pair_fromle32(ldir.pair);
            if (state < 0) {
                return state;
            }

            if (state == LFS_OK_RELOCATED) {
                lpair[0] = ppair[0];
                lpair[1] = ppair[1];
                ldir = pdir;
                orphans = true;
                continue;
            }
        }

        // find pred
        int err = luat_lfs2_fs_pred(lfs, lpair, &pdir);
        if (err && err != LFS_ERR_NOENT) {
            return err;
        }
        LFS_ASSERT(!(hasparent && err == LFS_ERR_NOENT));

        // if we can't find dir, it must be new
        if (err != LFS_ERR_NOENT) {
            if (luat_lfs2_gstate_hasorphans(&lfs->gstate)) {
                // next step, clean up orphans
                err = luat_lfs2_fs_preporphans(lfs, -hasparent);
                if (err) {
                    return err;
                }
            }

            // fix pending move in this pair? this looks like an optimization
            // but is in fact _required_ since relocating may outdate the move.
            uint16_t moveid = 0x3ff;
            if (luat_lfs2_gstate_hasmovehere(&lfs->gstate, pdir.pair)) {
                moveid = luat_lfs2_tag_id(lfs->gstate.tag);
                LFS_DEBUG("Fixing move while relocating "
                        "{0x%"PRIx32", 0x%"PRIx32"} 0x%"PRIx16"\n",
                        pdir.pair[0], pdir.pair[1], moveid);
                luat_lfs2_fs_prepmove(lfs, 0x3ff, NULL);
            }

            // replace bad pair, either we clean up desync, or no desync occured
            lpair[0] = pdir.pair[0];
            lpair[1] = pdir.pair[1];
            luat_lfs2_pair_tole32(ldir.pair);
            state = luat_lfs2_dir_relocatingcommit(lfs, &pdir, lpair, LFS_MKATTRS(
                        {LFS_MKTAG_IF(moveid != 0x3ff,
                            LFS_TYPE_DELETE, moveid, 0), NULL},
                        {LFS_MKTAG(LFS_TYPE_TAIL + pdir.split, 0x3ff, 8),
                            ldir.pair}),
                    NULL);
            luat_lfs2_pair_fromle32(ldir.pair);
            if (state < 0) {
                return state;
            }

            ldir = pdir;
        }
    }

    return orphans ? LFS_OK_ORPHANED : 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_dir_commit(luat_lfs2_t *lfs, luat_lfs2_mdir_t *dir,
        const struct luat_lfs2_mattr *attrs, int attrcount) {
    int orphans = luat_lfs2_dir_orphaningcommit(lfs, dir, attrs, attrcount);
    if (orphans < 0) {
        return orphans;
    }

    if (orphans) {
        // make sure we've removed all orphans, this is a noop if there
        // are none, but if we had nested blocks failures we may have
        // created some
        int err = luat_lfs2_fs_deorphan(lfs, false);
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif


/// Top level directory operations ///
#ifndef LFS_READONLY
static int luat_lfs2_mkdir_(luat_lfs2_t *lfs, const char *path) {
    // deorphan if we haven't yet, needed at most once after poweron
    int err = luat_lfs2_fs_forceconsistency(lfs);
    if (err) {
        return err;
    }

    struct luat_lfs2_mlist cwd;
    cwd.next = lfs->mlist;
    uint16_t id;
    err = luat_lfs2_dir_find(lfs, &cwd.m, &path, &id);
    if (!(err == LFS_ERR_NOENT && id != 0x3ff)) {
        return (err < 0) ? err : LFS_ERR_EXIST;
    }

    // check that name fits
    luat_lfs2_size_t nlen = strlen(path);
    if (nlen > lfs->name_max) {
        return LFS_ERR_NAMETOOLONG;
    }

    // build up new directory
    luat_lfs2_alloc_ckpoint(lfs);
    luat_lfs2_mdir_t dir;
    err = luat_lfs2_dir_alloc(lfs, &dir);
    if (err) {
        return err;
    }

    // find end of list
    luat_lfs2_mdir_t pred = cwd.m;
    while (pred.split) {
        err = luat_lfs2_dir_fetch(lfs, &pred, pred.tail);
        if (err) {
            return err;
        }
    }

    // setup dir
    luat_lfs2_pair_tole32(pred.tail);
    err = luat_lfs2_dir_commit(lfs, &dir, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_SOFTTAIL, 0x3ff, 8), pred.tail}));
    luat_lfs2_pair_fromle32(pred.tail);
    if (err) {
        return err;
    }

    // current block not end of list?
    if (cwd.m.split) {
        // update tails, this creates a desync
        err = luat_lfs2_fs_preporphans(lfs, +1);
        if (err) {
            return err;
        }

        // it's possible our predecessor has to be relocated, and if
        // our parent is our predecessor's predecessor, this could have
        // caused our parent to go out of date, fortunately we can hook
        // ourselves into littlefs to catch this
        cwd.type = 0;
        cwd.id = 0;
        lfs->mlist = &cwd;

        luat_lfs2_pair_tole32(dir.pair);
        err = luat_lfs2_dir_commit(lfs, &pred, LFS_MKATTRS(
                {LFS_MKTAG(LFS_TYPE_SOFTTAIL, 0x3ff, 8), dir.pair}));
        luat_lfs2_pair_fromle32(dir.pair);
        if (err) {
            lfs->mlist = cwd.next;
            return err;
        }

        lfs->mlist = cwd.next;
        err = luat_lfs2_fs_preporphans(lfs, -1);
        if (err) {
            return err;
        }
    }

    // now insert into our parent block
    luat_lfs2_pair_tole32(dir.pair);
    err = luat_lfs2_dir_commit(lfs, &cwd.m, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_CREATE, id, 0), NULL},
            {LFS_MKTAG(LFS_TYPE_DIR, id, nlen), path},
            {LFS_MKTAG(LFS_TYPE_DIRSTRUCT, id, 8), dir.pair},
            {LFS_MKTAG_IF(!cwd.m.split,
                LFS_TYPE_SOFTTAIL, 0x3ff, 8), dir.pair}));
    luat_lfs2_pair_fromle32(dir.pair);
    if (err) {
        return err;
    }

    return 0;
}
#endif

static int luat_lfs2_dir_open_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, const char *path) {
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &dir->m, &path, NULL);
    if (tag < 0) {
        return tag;
    }

    if (luat_lfs2_tag_type3(tag) != LFS_TYPE_DIR) {
        return LFS_ERR_NOTDIR;
    }

    luat_lfs2_block_t pair[2];
    if (luat_lfs2_tag_id(tag) == 0x3ff) {
        // handle root dir separately
        pair[0] = lfs->root[0];
        pair[1] = lfs->root[1];
    } else {
        // get dir pair from parent
        luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, &dir->m, LFS_MKTAG(0x700, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_STRUCT, luat_lfs2_tag_id(tag), 8), pair);
        if (res < 0) {
            return res;
        }
        luat_lfs2_pair_fromle32(pair);
    }

    // fetch first pair
    int err = luat_lfs2_dir_fetch(lfs, &dir->m, pair);
    if (err) {
        return err;
    }

    // setup entry
    dir->head[0] = dir->m.pair[0];
    dir->head[1] = dir->m.pair[1];
    dir->id = 0;
    dir->pos = 0;

    // add to list of mdirs
    dir->type = LFS_TYPE_DIR;
    luat_lfs2_mlist_append(lfs, (struct luat_lfs2_mlist *)dir);

    return 0;
}

static int luat_lfs2_dir_close_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    // remove from list of mdirs
    luat_lfs2_mlist_remove(lfs, (struct luat_lfs2_mlist *)dir);

    return 0;
}

static int luat_lfs2_dir_read_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, struct luat_lfs2_info *info) {
    memset(info, 0, sizeof(*info));

    // special offset for '.' and '..'
    if (dir->pos == 0) {
        info->type = LFS_TYPE_DIR;
        strcpy(info->name, ".");
        dir->pos += 1;
        return true;
    } else if (dir->pos == 1) {
        info->type = LFS_TYPE_DIR;
        strcpy(info->name, "..");
        dir->pos += 1;
        return true;
    }

    while (true) {
        if (dir->id == dir->m.count) {
            if (!dir->m.split) {
                return false;
            }

            int err = luat_lfs2_dir_fetch(lfs, &dir->m, dir->m.tail);
            if (err) {
                return err;
            }

            dir->id = 0;
        }

        int err = luat_lfs2_dir_getinfo(lfs, &dir->m, dir->id, info);
        if (err && err != LFS_ERR_NOENT) {
            return err;
        }

        dir->id += 1;
        if (err != LFS_ERR_NOENT) {
            break;
        }
    }

    dir->pos += 1;
    return true;
}

static int luat_lfs2_dir_seek_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, luat_lfs2_off_t off) {
    // simply walk from head dir
    int err = luat_lfs2_dir_rewind_(lfs, dir);
    if (err) {
        return err;
    }

    // first two for ./..
    dir->pos = luat_lfs2_min(2, off);
    off -= dir->pos;

    // skip superblock entry
    dir->id = (off > 0 && luat_lfs2_pair_cmp(dir->head, lfs->root) == 0);

    while (off > 0) {
        if (dir->id == dir->m.count) {
            if (!dir->m.split) {
                return LFS_ERR_INVAL;
            }

            err = luat_lfs2_dir_fetch(lfs, &dir->m, dir->m.tail);
            if (err) {
                return err;
            }

            dir->id = 0;
        }

        int diff = luat_lfs2_min(dir->m.count - dir->id, off);
        dir->id += diff;
        dir->pos += diff;
        off -= diff;
    }

    return 0;
}

static luat_lfs2_soff_t luat_lfs2_dir_tell_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    (void)lfs;
    return dir->pos;
}

static int luat_lfs2_dir_rewind_(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    // reload the head dir
    int err = luat_lfs2_dir_fetch(lfs, &dir->m, dir->head);
    if (err) {
        return err;
    }

    dir->id = 0;
    dir->pos = 0;
    return 0;
}


/// File index list operations ///
static int luat_lfs2_ctz_index(luat_lfs2_t *lfs, luat_lfs2_off_t *off) {
    luat_lfs2_off_t size = *off;
    luat_lfs2_off_t b = lfs->cfg->block_size - 2*4;
    luat_lfs2_off_t i = size / b;
    if (i == 0) {
        return 0;
    }

    i = (size - 4*(luat_lfs2_popc(i-1)+2)) / b;
    *off = size - b*i - 4*luat_lfs2_popc(i);
    return i;
}

static int luat_lfs2_ctz_find(luat_lfs2_t *lfs,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache,
        luat_lfs2_block_t head, luat_lfs2_size_t size,
        luat_lfs2_size_t pos, luat_lfs2_block_t *block, luat_lfs2_off_t *off) {
    if (size == 0) {
        *block = LFS_BLOCK_NULL;
        *off = 0;
        return 0;
    }

    luat_lfs2_off_t current = luat_lfs2_ctz_index(lfs, &(luat_lfs2_off_t){size-1});
    luat_lfs2_off_t target = luat_lfs2_ctz_index(lfs, &pos);

    while (current > target) {
        luat_lfs2_size_t skip = luat_lfs2_min(
                luat_lfs2_npw2(current-target+1) - 1,
                luat_lfs2_ctz(current));

        int err = luat_lfs2_bd_read(lfs,
                pcache, rcache, sizeof(head),
                head, 4*skip, &head, sizeof(head));
        head = luat_lfs2_fromle32(head);
        if (err) {
            return err;
        }

        current -= 1 << skip;
    }

    *block = head;
    *off = pos;
    return 0;
}

#ifndef LFS_READONLY
static int luat_lfs2_ctz_extend(luat_lfs2_t *lfs,
        luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache,
        luat_lfs2_block_t head, luat_lfs2_size_t size,
        luat_lfs2_block_t *block, luat_lfs2_off_t *off) {
    while (true) {
        luat_lfs2_block_t nblock;
        int err = luat_lfs2_alloc_erased(lfs, &nblock);

        {
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }

            if (size == 0) {
                *block = nblock;
                *off = 0;
                return 0;
            }

            luat_lfs2_size_t noff = size - 1;
            luat_lfs2_off_t index = luat_lfs2_ctz_index(lfs, &noff);
            noff = noff + 1;

            // just copy out the last block if it is incomplete
            if (noff != lfs->cfg->block_size) {
                for (luat_lfs2_off_t i = 0; i < noff; i++) {
                    uint8_t data;
                    err = luat_lfs2_bd_read(lfs,
                            NULL, rcache, noff-i,
                            head, i, &data, 1);
                    if (err) {
                        return err;
                    }

                    err = luat_lfs2_bd_prog(lfs,
                            pcache, rcache, true,
                            nblock, i, &data, 1);
                    if (err) {
                        if (err == LFS_ERR_CORRUPT) {
                            goto relocate;
                        }
                        return err;
                    }
                }

                *block = nblock;
                *off = noff;
                return 0;
            }

            // append block
            index += 1;
            luat_lfs2_size_t skips = luat_lfs2_ctz(index) + 1;
            luat_lfs2_block_t nhead = head;
            for (luat_lfs2_off_t i = 0; i < skips; i++) {
                nhead = luat_lfs2_tole32(nhead);
                err = luat_lfs2_bd_prog(lfs, pcache, rcache, true,
                        nblock, 4*i, &nhead, 4);
                nhead = luat_lfs2_fromle32(nhead);
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        goto relocate;
                    }
                    return err;
                }

                if (i != skips-1) {
                    err = luat_lfs2_bd_read(lfs,
                            NULL, rcache, sizeof(nhead),
                            nhead, 4*i, &nhead, sizeof(nhead));
                    nhead = luat_lfs2_fromle32(nhead);
                    if (err) {
                        return err;
                    }
                }
            }

            *block = nblock;
            *off = 4*skips;
            return 0;
        }

relocate:
        LFS_DEBUG("Bad block at 0x%"PRIx32, nblock);

        // just clear cache and try a new block
        luat_lfs2_cache_drop(lfs, pcache);
    }
}
#endif

static int luat_lfs2_ctz_traverse(luat_lfs2_t *lfs,
        const luat_lfs2_cache_t *pcache, luat_lfs2_cache_t *rcache,
        luat_lfs2_block_t head, luat_lfs2_size_t size,
        int (*cb)(void*, luat_lfs2_block_t), void *data) {
    if (size == 0) {
        return 0;
    }

    luat_lfs2_off_t index = luat_lfs2_ctz_index(lfs, &(luat_lfs2_off_t){size-1});

    while (true) {
        int err = cb(data, head);
        if (err) {
            return err;
        }

        if (index == 0) {
            return 0;
        }

        luat_lfs2_block_t heads[2];
        int count = 2 - (index & 1);
        err = luat_lfs2_bd_read(lfs,
                pcache, rcache, count*sizeof(head),
                head, 0, &heads, count*sizeof(head));
        heads[0] = luat_lfs2_fromle32(heads[0]);
        heads[1] = luat_lfs2_fromle32(heads[1]);
        if (err) {
            return err;
        }

        for (int i = 0; i < count-1; i++) {
            err = cb(data, heads[i]);
            if (err) {
                return err;
            }
        }

        head = heads[count-1];
        index -= count;
    }
}


/// Top level file operations ///
static int luat_lfs2_file_opencfg_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const char *path, int flags,
        const struct luat_lfs2_file_config *cfg) {
#ifndef LFS_READONLY
    // deorphan if we haven't yet, needed at most once after poweron
    if ((flags & LFS_O_WRONLY) == LFS_O_WRONLY) {
        int err = luat_lfs2_fs_forceconsistency(lfs);
        if (err) {
            return err;
        }
    }
#else
    LFS_ASSERT((flags & LFS_O_RDONLY) == LFS_O_RDONLY);
#endif

    // setup simple file details
    int err;
    file->cfg = cfg;
    file->flags = flags;
    file->pos = 0;
    file->off = 0;
    file->cache.buffer = NULL;

    // allocate entry for file if it doesn't exist
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &file->m, &path, &file->id);
    if (tag < 0 && !(tag == LFS_ERR_NOENT && file->id != 0x3ff)) {
        err = tag;
        goto cleanup;
    }

    // get id, add to list of mdirs to catch update changes
    file->type = LFS_TYPE_REG;
    luat_lfs2_mlist_append(lfs, (struct luat_lfs2_mlist *)file);

#ifdef LFS_READONLY
    if (tag == LFS_ERR_NOENT) {
        err = LFS_ERR_NOENT;
        goto cleanup;
#else
    if (tag == LFS_ERR_NOENT) {
        if (!(flags & LFS_O_CREAT)) {
            err = LFS_ERR_NOENT;
            goto cleanup;
        }

        // check that name fits
        luat_lfs2_size_t nlen = strlen(path);
        if (nlen > lfs->name_max) {
            err = LFS_ERR_NAMETOOLONG;
            goto cleanup;
        }

        // get next slot and create entry to remember name
        err = luat_lfs2_dir_commit(lfs, &file->m, LFS_MKATTRS(
                {LFS_MKTAG(LFS_TYPE_CREATE, file->id, 0), NULL},
                {LFS_MKTAG(LFS_TYPE_REG, file->id, nlen), path},
                {LFS_MKTAG(LFS_TYPE_INLINESTRUCT, file->id, 0), NULL}));

        // it may happen that the file name doesn't fit in the metadata blocks, e.g., a 256 byte file name will
        // not fit in a 128 byte block.
        err = (err == LFS_ERR_NOSPC) ? LFS_ERR_NAMETOOLONG : err;
        if (err) {
            goto cleanup;
        }

        tag = LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, 0);
    } else if (flags & LFS_O_EXCL) {
        err = LFS_ERR_EXIST;
        goto cleanup;
#endif
    } else if (luat_lfs2_tag_type3(tag) != LFS_TYPE_REG) {
        err = LFS_ERR_ISDIR;
        goto cleanup;
#ifndef LFS_READONLY
    } else if (flags & LFS_O_TRUNC) {
        // truncate if requested
        tag = LFS_MKTAG(LFS_TYPE_INLINESTRUCT, file->id, 0);
        file->flags |= LFS_F_DIRTY;
#endif
    } else {
        // try to load what's on disk, if it's inlined we'll fix it later
        tag = luat_lfs2_dir_get(lfs, &file->m, LFS_MKTAG(0x700, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_STRUCT, file->id, 8), &file->ctz);
        if (tag < 0) {
            err = tag;
            goto cleanup;
        }
        luat_lfs2_ctz_fromle32(&file->ctz);
    }

    // fetch attrs
    for (unsigned i = 0; i < file->cfg->attr_count; i++) {
        // if opened for read / read-write operations
        if ((file->flags & LFS_O_RDONLY) == LFS_O_RDONLY) {
            luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, &file->m,
                    LFS_MKTAG(0x7ff, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_USERATTR + file->cfg->attrs[i].type,
                        file->id, file->cfg->attrs[i].size),
                        file->cfg->attrs[i].buffer);
            if (res < 0 && res != LFS_ERR_NOENT) {
                err = res;
                goto cleanup;
            }
        }

#ifndef LFS_READONLY
        // if opened for write / read-write operations
        if ((file->flags & LFS_O_WRONLY) == LFS_O_WRONLY) {
            if (file->cfg->attrs[i].size > lfs->attr_max) {
                err = LFS_ERR_NOSPC;
                goto cleanup;
            }

            file->flags |= LFS_F_DIRTY;
        }
#endif
    }

    // allocate buffer if needed
    if (file->cfg->buffer) {
        file->cache.buffer = file->cfg->buffer;
    } else {
        file->cache.buffer = luat_lfs2_malloc(lfs->cfg->cache_size);
        if (!file->cache.buffer) {
            err = LFS_ERR_NOMEM;
            goto cleanup;
        }
    }

    // zero to avoid information leak
    luat_lfs2_cache_zero(lfs, &file->cache);

    if (luat_lfs2_tag_type3(tag) == LFS_TYPE_INLINESTRUCT) {
        // load inline files
        file->ctz.head = LFS_BLOCK_INLINE;
        file->ctz.size = luat_lfs2_tag_size(tag);
        file->flags |= LFS_F_INLINE;
        file->cache.block = file->ctz.head;
        file->cache.off = 0;
        file->cache.size = lfs->cfg->cache_size;

        // don't always read (may be new/trunc file)
        if (file->ctz.size > 0) {
            luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, &file->m,
                    LFS_MKTAG(0x700, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_STRUCT, file->id,
                        luat_lfs2_min(file->cache.size, 0x3fe)),
                    file->cache.buffer);
            if (res < 0) {
                err = res;
                goto cleanup;
            }
        }
    }

    return 0;

cleanup:
    // clean up lingering resources
#ifndef LFS_READONLY
    file->flags |= LFS_F_ERRED;
#endif
    luat_lfs2_file_close_(lfs, file);
    return err;
}

#ifndef LFS_NO_MALLOC
static int luat_lfs2_file_open_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const char *path, int flags) {
    static const struct luat_lfs2_file_config defaults = {0};
    int err = luat_lfs2_file_opencfg_(lfs, file, path, flags, &defaults);
    return err;
}
#endif

static int luat_lfs2_file_close_(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
#ifndef LFS_READONLY
    int err = luat_lfs2_file_sync_(lfs, file);
#else
    int err = 0;
#endif

    // remove from list of mdirs
    luat_lfs2_mlist_remove(lfs, (struct luat_lfs2_mlist*)file);

    // clean up memory
    if (!file->cfg->buffer && file->cache.buffer) {
        luat_lfs2_free(file->cache.buffer);
        file->cache.buffer = NULL;
    }

    return err;
}


#ifndef LFS_READONLY
static int luat_lfs2_file_relocate(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    while (true) {
        // just relocate what exists into new block
        luat_lfs2_block_t nblock;
        int err = luat_lfs2_alloc_erased(lfs, &nblock);
        if (err) {
            if (err == LFS_ERR_CORRUPT) {
                goto relocate;
            }
            return err;
        }

        // either read from dirty cache or disk
        for (luat_lfs2_off_t i = 0; i < file->off; i++) {
            uint8_t data;
            if (file->flags & LFS_F_INLINE) {
                err = luat_lfs2_dir_getread(lfs, &file->m,
                        // note we evict inline files before they can be dirty
                        NULL, &file->cache, file->off-i,
                        LFS_MKTAG(0xfff, 0x1ff, 0),
                        LFS_MKTAG(LFS_TYPE_INLINESTRUCT, file->id, 0),
                        i, &data, 1);
                if (err) {
                    return err;
                }
            } else {
                err = luat_lfs2_bd_read(lfs,
                        &file->cache, &lfs->rcache, file->off-i,
                        file->block, i, &data, 1);
                if (err) {
                    return err;
                }
            }

            err = luat_lfs2_bd_prog(lfs,
                    &lfs->pcache, &lfs->rcache, true,
                    nblock, i, &data, 1);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                return err;
            }
        }

        // copy over new state of file
        memcpy(file->cache.buffer, lfs->pcache.buffer, lfs->cfg->cache_size);
        file->cache.block = lfs->pcache.block;
        file->cache.off = lfs->pcache.off;
        file->cache.size = lfs->pcache.size;
        luat_lfs2_cache_zero(lfs, &lfs->pcache);

        file->block = nblock;
        file->flags |= LFS_F_WRITING;
        return 0;

relocate:
        LFS_DEBUG("Bad block at 0x%"PRIx32, nblock);

        // just clear cache and try a new block
        luat_lfs2_cache_drop(lfs, &lfs->pcache);
    }
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_file_outline(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    file->off = file->pos;
    luat_lfs2_alloc_ckpoint(lfs);
    int err = luat_lfs2_file_relocate(lfs, file);
    if (err) {
        return err;
    }

    file->flags &= ~LFS_F_INLINE;
    return 0;
}
#endif

static int luat_lfs2_file_flush(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    if (file->flags & LFS_F_READING) {
        if (!(file->flags & LFS_F_INLINE)) {
            luat_lfs2_cache_drop(lfs, &file->cache);
        }
        file->flags &= ~LFS_F_READING;
    }

#ifndef LFS_READONLY
    if (file->flags & LFS_F_WRITING) {
        luat_lfs2_off_t pos = file->pos;

        if (!(file->flags & LFS_F_INLINE)) {
            // copy over anything after current branch
            luat_lfs2_file_t orig = {
                .ctz.head = file->ctz.head,
                .ctz.size = file->ctz.size,
                .flags = LFS_O_RDONLY,
                .pos = file->pos,
                .cache = lfs->rcache,
            };
            luat_lfs2_cache_drop(lfs, &lfs->rcache);

            while (file->pos < file->ctz.size) {
                // copy over a byte at a time, leave it up to caching
                // to make this efficient
                uint8_t data;
                luat_lfs2_ssize_t res = luat_lfs2_file_flushedread(lfs, &orig, &data, 1);
                if (res < 0) {
                    return res;
                }

                res = luat_lfs2_file_flushedwrite(lfs, file, &data, 1);
                if (res < 0) {
                    return res;
                }

                // keep our reference to the rcache in sync
                if (lfs->rcache.block != LFS_BLOCK_NULL) {
                    luat_lfs2_cache_drop(lfs, &orig.cache);
                    luat_lfs2_cache_drop(lfs, &lfs->rcache);
                }
            }

            // write out what we have
            while (true) {
                int err = luat_lfs2_bd_flush(lfs, &file->cache, &lfs->rcache, true);
                if (err) {
                    if (err == LFS_ERR_CORRUPT) {
                        goto relocate;
                    }
                    return err;
                }

                break;

relocate:
                LFS_DEBUG("Bad block at 0x%"PRIx32, file->block);
                err = luat_lfs2_file_relocate(lfs, file);
                if (err) {
                    return err;
                }
            }
        } else {
            file->pos = luat_lfs2_max(file->pos, file->ctz.size);
        }

        // actual file updates
        file->ctz.head = file->block;
        file->ctz.size = file->pos;
        file->flags &= ~LFS_F_WRITING;
        file->flags |= LFS_F_DIRTY;

        file->pos = pos;
    }
#endif

    return 0;
}

#ifndef LFS_READONLY
static int luat_lfs2_file_sync_(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    if (file->flags & LFS_F_ERRED) {
        // it's not safe to do anything if our file errored
        return 0;
    }

    int err = luat_lfs2_file_flush(lfs, file);
    if (err) {
        file->flags |= LFS_F_ERRED;
        return err;
    }


    if ((file->flags & LFS_F_DIRTY) &&
            !luat_lfs2_pair_isnull(file->m.pair)) {
        // before we commit metadata, we need sync the disk to make sure
        // data writes don't complete after metadata writes
        if (!(file->flags & LFS_F_INLINE)) {
            err = luat_lfs2_bd_sync(lfs, &lfs->pcache, &lfs->rcache, false);
            if (err) {
                return err;
            }
        }

        // update dir entry
        uint16_t type;
        const void *buffer;
        luat_lfs2_size_t size;
        struct luat_lfs2_ctz ctz;
        if (file->flags & LFS_F_INLINE) {
            // inline the whole file
            type = LFS_TYPE_INLINESTRUCT;
            buffer = file->cache.buffer;
            size = file->ctz.size;
        } else {
            // update the ctz reference
            type = LFS_TYPE_CTZSTRUCT;
            // copy ctz so alloc will work during a relocate
            ctz = file->ctz;
            luat_lfs2_ctz_tole32(&ctz);
            buffer = &ctz;
            size = sizeof(ctz);
        }

        // commit file data and attributes
        err = luat_lfs2_dir_commit(lfs, &file->m, LFS_MKATTRS(
                {LFS_MKTAG(type, file->id, size), buffer},
                {LFS_MKTAG(LFS_FROM_USERATTRS, file->id,
                    file->cfg->attr_count), file->cfg->attrs}));
        if (err) {
            file->flags |= LFS_F_ERRED;
            return err;
        }

        file->flags &= ~LFS_F_DIRTY;
    }

    return 0;
}
#endif

static luat_lfs2_ssize_t luat_lfs2_file_flushedread(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size) {
    uint8_t *data = buffer;
    luat_lfs2_size_t nsize = size;

    if (file->pos >= file->ctz.size) {
        // eof if past end
        return 0;
    }

    size = luat_lfs2_min(size, file->ctz.size - file->pos);
    nsize = size;

    while (nsize > 0) {
        // check if we need a new block
        if (!(file->flags & LFS_F_READING) ||
                file->off == lfs->cfg->block_size) {
            if (!(file->flags & LFS_F_INLINE)) {
                int err = luat_lfs2_ctz_find(lfs, NULL, &file->cache,
                        file->ctz.head, file->ctz.size,
                        file->pos, &file->block, &file->off);
                if (err) {
                    return err;
                }
            } else {
                file->block = LFS_BLOCK_INLINE;
                file->off = file->pos;
            }

            file->flags |= LFS_F_READING;
        }

        // read as much as we can in current block
        luat_lfs2_size_t diff = luat_lfs2_min(nsize, lfs->cfg->block_size - file->off);
        if (file->flags & LFS_F_INLINE) {
            int err = luat_lfs2_dir_getread(lfs, &file->m,
                    NULL, &file->cache, lfs->cfg->block_size,
                    LFS_MKTAG(0xfff, 0x1ff, 0),
                    LFS_MKTAG(LFS_TYPE_INLINESTRUCT, file->id, 0),
                    file->off, data, diff);
            if (err) {
                return err;
            }
        } else {
            int err = luat_lfs2_bd_read(lfs,
                    NULL, &file->cache, lfs->cfg->block_size,
                    file->block, file->off, data, diff);
            if (err) {
                return err;
            }
        }

        file->pos += diff;
        file->off += diff;
        data += diff;
        nsize -= diff;
    }

    return size;
}

static luat_lfs2_ssize_t luat_lfs2_file_read_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size) {
    LFS_ASSERT((file->flags & LFS_O_RDONLY) == LFS_O_RDONLY);

#ifndef LFS_READONLY
    if (file->flags & LFS_F_WRITING) {
        // flush out any writes
        int err = luat_lfs2_file_flush(lfs, file);
        if (err) {
            return err;
        }
    }
#endif

    return luat_lfs2_file_flushedread(lfs, file, buffer, size);
}


#ifndef LFS_READONLY
static luat_lfs2_ssize_t luat_lfs2_file_flushedwrite(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size) {
    const uint8_t *data = buffer;
    luat_lfs2_size_t nsize = size;

    if ((file->flags & LFS_F_INLINE) &&
            luat_lfs2_max(file->pos+nsize, file->ctz.size) > lfs->inline_max) {
        // inline file doesn't fit anymore
        int err = luat_lfs2_file_outline(lfs, file);
        if (err) {
            file->flags |= LFS_F_ERRED;
            return err;
        }
    }

    while (nsize > 0) {
        // check if we need a new block
        if (!(file->flags & LFS_F_WRITING) ||
                file->off == lfs->cfg->block_size) {
            if (!(file->flags & LFS_F_INLINE)) {
                if (!(file->flags & LFS_F_WRITING) && file->pos > 0) {
                    // find out which block we're extending from
                    int err = luat_lfs2_ctz_find(lfs, NULL, &file->cache,
                            file->ctz.head, file->ctz.size,
                            file->pos-1, &file->block, &(luat_lfs2_off_t){0});
                    if (err) {
                        file->flags |= LFS_F_ERRED;
                        return err;
                    }

                    // mark cache as dirty since we may have read data into it
                    luat_lfs2_cache_zero(lfs, &file->cache);
                }

                // extend file with new blocks
                luat_lfs2_alloc_ckpoint(lfs);
                int err = luat_lfs2_ctz_extend(lfs, &file->cache, &lfs->rcache,
                        file->block, file->pos,
                        &file->block, &file->off);
                if (err) {
                    file->flags |= LFS_F_ERRED;
                    return err;
                }
            } else {
                file->block = LFS_BLOCK_INLINE;
                file->off = file->pos;
            }

            file->flags |= LFS_F_WRITING;
        }

        // program as much as we can in current block
        luat_lfs2_size_t diff = luat_lfs2_min(nsize, lfs->cfg->block_size - file->off);
        while (true) {
            int err = luat_lfs2_bd_prog(lfs, &file->cache, &lfs->rcache, true,
                    file->block, file->off, data, diff);
            if (err) {
                if (err == LFS_ERR_CORRUPT) {
                    goto relocate;
                }
                file->flags |= LFS_F_ERRED;
                return err;
            }

            break;
relocate:
            err = luat_lfs2_file_relocate(lfs, file);
            if (err) {
                file->flags |= LFS_F_ERRED;
                return err;
            }
        }

        file->pos += diff;
        file->off += diff;
        data += diff;
        nsize -= diff;

        luat_lfs2_alloc_ckpoint(lfs);
    }

    return size;
}

static luat_lfs2_ssize_t luat_lfs2_file_write_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size) {
    LFS_ASSERT((file->flags & LFS_O_WRONLY) == LFS_O_WRONLY);

    if (file->flags & LFS_F_READING) {
        // drop any reads
        int err = luat_lfs2_file_flush(lfs, file);
        if (err) {
            return err;
        }
    }

    if ((file->flags & LFS_O_APPEND) && file->pos < file->ctz.size) {
        file->pos = file->ctz.size;
    }

    if (file->pos + size > lfs->file_max) {
        // Larger than file limit?
        return LFS_ERR_FBIG;
    }

    if (!(file->flags & LFS_F_WRITING) && file->pos > file->ctz.size) {
        // fill with zeros
        luat_lfs2_off_t pos = file->pos;
        file->pos = file->ctz.size;

        while (file->pos < pos) {
            luat_lfs2_ssize_t res = luat_lfs2_file_flushedwrite(lfs, file, &(uint8_t){0}, 1);
            if (res < 0) {
                return res;
            }
        }
    }

    luat_lfs2_ssize_t nsize = luat_lfs2_file_flushedwrite(lfs, file, buffer, size);
    if (nsize < 0) {
        return nsize;
    }

    file->flags &= ~LFS_F_ERRED;
    return nsize;
}
#endif

static luat_lfs2_soff_t luat_lfs2_file_seek_(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        luat_lfs2_soff_t off, int whence) {
    // find new pos
    luat_lfs2_off_t npos = file->pos;
    if (whence == LFS_SEEK_SET) {
        npos = off;
    } else if (whence == LFS_SEEK_CUR) {
        if ((luat_lfs2_soff_t)file->pos + off < 0) {
            return LFS_ERR_INVAL;
        } else {
            npos = file->pos + off;
        }
    } else if (whence == LFS_SEEK_END) {
        luat_lfs2_soff_t res = luat_lfs2_file_size_(lfs, file) + off;
        if (res < 0) {
            return LFS_ERR_INVAL;
        } else {
            npos = res;
        }
    }

    if (npos > lfs->file_max) {
        // file position out of range
        return LFS_ERR_INVAL;
    }

    if (file->pos == npos) {
        // noop - position has not changed
        return npos;
    }

    // if we're only reading and our new offset is still in the file's cache
    // we can avoid flushing and needing to reread the data
    if (
#ifndef LFS_READONLY
        !(file->flags & LFS_F_WRITING)
#else
        true
#endif
            ) {
        int oindex = luat_lfs2_ctz_index(lfs, &(luat_lfs2_off_t){file->pos});
        luat_lfs2_off_t noff = npos;
        int nindex = luat_lfs2_ctz_index(lfs, &noff);
        if (oindex == nindex
                && noff >= file->cache.off
                && noff < file->cache.off + file->cache.size) {
            file->pos = npos;
            file->off = noff;
            return npos;
        }
    }

    // write out everything beforehand, may be noop if rdonly
    int err = luat_lfs2_file_flush(lfs, file);
    if (err) {
        return err;
    }

    // update pos
    file->pos = npos;
    return npos;
}

#ifndef LFS_READONLY
static int luat_lfs2_file_truncate_(luat_lfs2_t *lfs, luat_lfs2_file_t *file, luat_lfs2_off_t size) {
    LFS_ASSERT((file->flags & LFS_O_WRONLY) == LFS_O_WRONLY);

    if (size > LFS_FILE_MAX) {
        return LFS_ERR_INVAL;
    }

    luat_lfs2_off_t pos = file->pos;
    luat_lfs2_off_t oldsize = luat_lfs2_file_size_(lfs, file);
    if (size < oldsize) {
        // revert to inline file?
        if (size <= lfs->inline_max) {
            // flush+seek to head
            luat_lfs2_soff_t res = luat_lfs2_file_seek_(lfs, file, 0, LFS_SEEK_SET);
            if (res < 0) {
                return (int)res;
            }

            // read our data into rcache temporarily
            luat_lfs2_cache_drop(lfs, &lfs->rcache);
            res = luat_lfs2_file_flushedread(lfs, file,
                    lfs->rcache.buffer, size);
            if (res < 0) {
                return (int)res;
            }

            file->ctz.head = LFS_BLOCK_INLINE;
            file->ctz.size = size;
            file->flags |= LFS_F_DIRTY | LFS_F_READING | LFS_F_INLINE;
            file->cache.block = file->ctz.head;
            file->cache.off = 0;
            file->cache.size = lfs->cfg->cache_size;
            memcpy(file->cache.buffer, lfs->rcache.buffer, size);

        } else {
            // need to flush since directly changing metadata
            int err = luat_lfs2_file_flush(lfs, file);
            if (err) {
                return err;
            }

            // lookup new head in ctz skip list
            err = luat_lfs2_ctz_find(lfs, NULL, &file->cache,
                    file->ctz.head, file->ctz.size,
                    size-1, &file->block, &(luat_lfs2_off_t){0});
            if (err) {
                return err;
            }

            // need to set pos/block/off consistently so seeking back to
            // the old position does not get confused
            file->pos = size;
            file->ctz.head = file->block;
            file->ctz.size = size;
            file->flags |= LFS_F_DIRTY | LFS_F_READING;
        }
    } else if (size > oldsize) {
        // flush+seek if not already at end
        luat_lfs2_soff_t res = luat_lfs2_file_seek_(lfs, file, 0, LFS_SEEK_END);
        if (res < 0) {
            return (int)res;
        }

        // fill with zeros
        while (file->pos < size) {
            res = luat_lfs2_file_write_(lfs, file, &(uint8_t){0}, 1);
            if (res < 0) {
                return (int)res;
            }
        }
    }

    // restore pos
    luat_lfs2_soff_t res = luat_lfs2_file_seek_(lfs, file, pos, LFS_SEEK_SET);
    if (res < 0) {
      return (int)res;
    }

    return 0;
}
#endif

static luat_lfs2_soff_t luat_lfs2_file_tell_(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    (void)lfs;
    return file->pos;
}

static int luat_lfs2_file_rewind_(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    luat_lfs2_soff_t res = luat_lfs2_file_seek_(lfs, file, 0, LFS_SEEK_SET);
    if (res < 0) {
        return (int)res;
    }

    return 0;
}

static luat_lfs2_soff_t luat_lfs2_file_size_(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    (void)lfs;

#ifndef LFS_READONLY
    if (file->flags & LFS_F_WRITING) {
        return luat_lfs2_max(file->pos, file->ctz.size);
    }
#endif

    return file->ctz.size;
}


/// General fs operations ///
static int luat_lfs2_stat_(luat_lfs2_t *lfs, const char *path, struct luat_lfs2_info *info) {
    luat_lfs2_mdir_t cwd;
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &cwd, &path, NULL);
    if (tag < 0) {
        return (int)tag;
    }

    return luat_lfs2_dir_getinfo(lfs, &cwd, luat_lfs2_tag_id(tag), info);
}

#ifndef LFS_READONLY
static int luat_lfs2_remove_(luat_lfs2_t *lfs, const char *path) {
    // deorphan if we haven't yet, needed at most once after poweron
    int err = luat_lfs2_fs_forceconsistency(lfs);
    if (err) {
        return err;
    }

    luat_lfs2_mdir_t cwd;
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &cwd, &path, NULL);
    if (tag < 0 || luat_lfs2_tag_id(tag) == 0x3ff) {
        return (tag < 0) ? (int)tag : LFS_ERR_INVAL;
    }

    struct luat_lfs2_mlist dir;
    dir.next = lfs->mlist;
    if (luat_lfs2_tag_type3(tag) == LFS_TYPE_DIR) {
        // must be empty before removal
        luat_lfs2_block_t pair[2];
        luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, &cwd, LFS_MKTAG(0x700, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_STRUCT, luat_lfs2_tag_id(tag), 8), pair);
        if (res < 0) {
            return (int)res;
        }
        luat_lfs2_pair_fromle32(pair);

        err = luat_lfs2_dir_fetch(lfs, &dir.m, pair);
        if (err) {
            return err;
        }

        if (dir.m.count > 0 || dir.m.split) {
            return LFS_ERR_NOTEMPTY;
        }

        // mark fs as orphaned
        err = luat_lfs2_fs_preporphans(lfs, +1);
        if (err) {
            return err;
        }

        // I know it's crazy but yes, dir can be changed by our parent's
        // commit (if predecessor is child)
        dir.type = 0;
        dir.id = 0;
        lfs->mlist = &dir;
    }

    // delete the entry
    err = luat_lfs2_dir_commit(lfs, &cwd, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_DELETE, luat_lfs2_tag_id(tag), 0), NULL}));
    if (err) {
        lfs->mlist = dir.next;
        return err;
    }

    lfs->mlist = dir.next;
    if (luat_lfs2_tag_type3(tag) == LFS_TYPE_DIR) {
        // fix orphan
        err = luat_lfs2_fs_preporphans(lfs, -1);
        if (err) {
            return err;
        }

        err = luat_lfs2_fs_pred(lfs, dir.m.pair, &cwd);
        if (err) {
            return err;
        }

        err = luat_lfs2_dir_drop(lfs, &cwd, &dir.m);
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_rename_(luat_lfs2_t *lfs, const char *oldpath, const char *newpath) {
    // deorphan if we haven't yet, needed at most once after poweron
    int err = luat_lfs2_fs_forceconsistency(lfs);
    if (err) {
        return err;
    }

    // find old entry
    luat_lfs2_mdir_t oldcwd;
    luat_lfs2_stag_t oldtag = luat_lfs2_dir_find(lfs, &oldcwd, &oldpath, NULL);
    if (oldtag < 0 || luat_lfs2_tag_id(oldtag) == 0x3ff) {
        return (oldtag < 0) ? (int)oldtag : LFS_ERR_INVAL;
    }

    // find new entry
    luat_lfs2_mdir_t newcwd;
    uint16_t newid;
    luat_lfs2_stag_t prevtag = luat_lfs2_dir_find(lfs, &newcwd, &newpath, &newid);
    if ((prevtag < 0 || luat_lfs2_tag_id(prevtag) == 0x3ff) &&
            !(prevtag == LFS_ERR_NOENT && newid != 0x3ff)) {
        return (prevtag < 0) ? (int)prevtag : LFS_ERR_INVAL;
    }

    // if we're in the same pair there's a few special cases...
    bool samepair = (luat_lfs2_pair_cmp(oldcwd.pair, newcwd.pair) == 0);
    uint16_t newoldid = luat_lfs2_tag_id(oldtag);

    struct luat_lfs2_mlist prevdir;
    prevdir.next = lfs->mlist;
    if (prevtag == LFS_ERR_NOENT) {
        // check that name fits
        luat_lfs2_size_t nlen = strlen(newpath);
        if (nlen > lfs->name_max) {
            return LFS_ERR_NAMETOOLONG;
        }

        // there is a small chance we are being renamed in the same
        // directory/ to an id less than our old id, the global update
        // to handle this is a bit messy
        if (samepair && newid <= newoldid) {
            newoldid += 1;
        }
    } else if (luat_lfs2_tag_type3(prevtag) != luat_lfs2_tag_type3(oldtag)) {
        return (luat_lfs2_tag_type3(prevtag) == LFS_TYPE_DIR)
                ? LFS_ERR_ISDIR
                : LFS_ERR_NOTDIR;
    } else if (samepair && newid == newoldid) {
        // we're renaming to ourselves??
        return 0;
    } else if (luat_lfs2_tag_type3(prevtag) == LFS_TYPE_DIR) {
        // must be empty before removal
        luat_lfs2_block_t prevpair[2];
        luat_lfs2_stag_t res = luat_lfs2_dir_get(lfs, &newcwd, LFS_MKTAG(0x700, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_STRUCT, newid, 8), prevpair);
        if (res < 0) {
            return (int)res;
        }
        luat_lfs2_pair_fromle32(prevpair);

        // must be empty before removal
        err = luat_lfs2_dir_fetch(lfs, &prevdir.m, prevpair);
        if (err) {
            return err;
        }

        if (prevdir.m.count > 0 || prevdir.m.split) {
            return LFS_ERR_NOTEMPTY;
        }

        // mark fs as orphaned
        err = luat_lfs2_fs_preporphans(lfs, +1);
        if (err) {
            return err;
        }

        // I know it's crazy but yes, dir can be changed by our parent's
        // commit (if predecessor is child)
        prevdir.type = 0;
        prevdir.id = 0;
        lfs->mlist = &prevdir;
    }

    if (!samepair) {
        luat_lfs2_fs_prepmove(lfs, newoldid, oldcwd.pair);
    }

    // move over all attributes
    err = luat_lfs2_dir_commit(lfs, &newcwd, LFS_MKATTRS(
            {LFS_MKTAG_IF(prevtag != LFS_ERR_NOENT,
                LFS_TYPE_DELETE, newid, 0), NULL},
            {LFS_MKTAG(LFS_TYPE_CREATE, newid, 0), NULL},
            {LFS_MKTAG(luat_lfs2_tag_type3(oldtag), newid, strlen(newpath)), newpath},
            {LFS_MKTAG(LFS_FROM_MOVE, newid, luat_lfs2_tag_id(oldtag)), &oldcwd},
            {LFS_MKTAG_IF(samepair,
                LFS_TYPE_DELETE, newoldid, 0), NULL}));
    if (err) {
        lfs->mlist = prevdir.next;
        return err;
    }

    // let commit clean up after move (if we're different! otherwise move
    // logic already fixed it for us)
    if (!samepair && luat_lfs2_gstate_hasmove(&lfs->gstate)) {
        // prep gstate and delete move id
        luat_lfs2_fs_prepmove(lfs, 0x3ff, NULL);
        err = luat_lfs2_dir_commit(lfs, &oldcwd, LFS_MKATTRS(
                {LFS_MKTAG(LFS_TYPE_DELETE, luat_lfs2_tag_id(oldtag), 0), NULL}));
        if (err) {
            lfs->mlist = prevdir.next;
            return err;
        }
    }

    lfs->mlist = prevdir.next;
    if (prevtag != LFS_ERR_NOENT
            && luat_lfs2_tag_type3(prevtag) == LFS_TYPE_DIR) {
        // fix orphan
        err = luat_lfs2_fs_preporphans(lfs, -1);
        if (err) {
            return err;
        }

        err = luat_lfs2_fs_pred(lfs, prevdir.m.pair, &newcwd);
        if (err) {
            return err;
        }

        err = luat_lfs2_dir_drop(lfs, &newcwd, &prevdir.m);
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif

static luat_lfs2_ssize_t luat_lfs2_getattr_(luat_lfs2_t *lfs, const char *path,
        uint8_t type, void *buffer, luat_lfs2_size_t size) {
    luat_lfs2_mdir_t cwd;
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &cwd, &path, NULL);
    if (tag < 0) {
        return tag;
    }

    uint16_t id = luat_lfs2_tag_id(tag);
    if (id == 0x3ff) {
        // special case for root
        id = 0;
        int err = luat_lfs2_dir_fetch(lfs, &cwd, lfs->root);
        if (err) {
            return err;
        }
    }

    tag = luat_lfs2_dir_get(lfs, &cwd, LFS_MKTAG(0x7ff, 0x3ff, 0),
            LFS_MKTAG(LFS_TYPE_USERATTR + type,
                id, luat_lfs2_min(size, lfs->attr_max)),
            buffer);
    if (tag < 0) {
        if (tag == LFS_ERR_NOENT) {
            return LFS_ERR_NOATTR;
        }

        return tag;
    }

    return luat_lfs2_tag_size(tag);
}

#ifndef LFS_READONLY
static int luat_lfs2_commitattr(luat_lfs2_t *lfs, const char *path,
        uint8_t type, const void *buffer, luat_lfs2_size_t size) {
    luat_lfs2_mdir_t cwd;
    luat_lfs2_stag_t tag = luat_lfs2_dir_find(lfs, &cwd, &path, NULL);
    if (tag < 0) {
        return tag;
    }

    uint16_t id = luat_lfs2_tag_id(tag);
    if (id == 0x3ff) {
        // special case for root
        id = 0;
        int err = luat_lfs2_dir_fetch(lfs, &cwd, lfs->root);
        if (err) {
            return err;
        }
    }

    return luat_lfs2_dir_commit(lfs, &cwd, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_USERATTR + type, id, size), buffer}));
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_setattr_(luat_lfs2_t *lfs, const char *path,
        uint8_t type, const void *buffer, luat_lfs2_size_t size) {
    if (size > lfs->attr_max) {
        return LFS_ERR_NOSPC;
    }

    return luat_lfs2_commitattr(lfs, path, type, buffer, size);
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_removeattr_(luat_lfs2_t *lfs, const char *path, uint8_t type) {
    return luat_lfs2_commitattr(lfs, path, type, NULL, 0x3ff);
}
#endif


/// Filesystem operations ///

// compile time checks, see lfs.h for why these limits exist
#if LFS_NAME_MAX > 1022
#error "Invalid LFS_NAME_MAX, must be <= 1022"
#endif

#if LFS_FILE_MAX > 2147483647
#error "Invalid LFS_FILE_MAX, must be <= 2147483647"
#endif

#if LFS_ATTR_MAX > 1022
#error "Invalid LFS_ATTR_MAX, must be <= 1022"
#endif

// common filesystem initialization
static int luat_lfs2_init(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    lfs->cfg = cfg;
    lfs->block_count = cfg->block_count;  // May be 0
    int err = 0;

#ifdef LFS_MULTIVERSION
    // this driver only supports minor version < current minor version
    LFS_ASSERT(!lfs->cfg->disk_version || (
            (0xffff & (lfs->cfg->disk_version >> 16))
                    == LFS_DISK_VERSION_MAJOR
                && (0xffff & (lfs->cfg->disk_version >> 0))
                    <= LFS_DISK_VERSION_MINOR));
#endif

    // check that bool is a truthy-preserving type
    //
    // note the most common reason for this failure is a before-c99 compiler,
    // which littlefs currently does not support
    LFS_ASSERT((bool)0x80000000);

    // validate that the lfs-cfg sizes were initiated properly before
    // performing any arithmetic logics with them
    LFS_ASSERT(lfs->cfg->read_size != 0);
    LFS_ASSERT(lfs->cfg->prog_size != 0);
    LFS_ASSERT(lfs->cfg->cache_size != 0);

    // check that block size is a multiple of cache size is a multiple
    // of prog and read sizes
    LFS_ASSERT(lfs->cfg->cache_size % lfs->cfg->read_size == 0);
    LFS_ASSERT(lfs->cfg->cache_size % lfs->cfg->prog_size == 0);
    LFS_ASSERT(lfs->cfg->block_size % lfs->cfg->cache_size == 0);

    // check that the block size is large enough to fit all ctz pointers
    LFS_ASSERT(lfs->cfg->block_size >= 128);
    // this is the exact calculation for all ctz pointers, if this fails
    // and the simpler assert above does not, math must be broken
    LFS_ASSERT(4*luat_lfs2_npw2(0xffffffff / (lfs->cfg->block_size-2*4))
            <= lfs->cfg->block_size);

    // block_cycles = 0 is no longer supported.
    //
    // block_cycles is the number of erase cycles before littlefs evicts
    // metadata logs as a part of wear leveling. Suggested values are in the
    // range of 100-1000, or set block_cycles to -1 to disable block-level
    // wear-leveling.
    LFS_ASSERT(lfs->cfg->block_cycles != 0);

    // check that compact_thresh makes sense
    //
    // metadata can't be compacted below block_size/2, and metadata can't
    // exceed a block_size
    LFS_ASSERT(lfs->cfg->compact_thresh == 0
            || lfs->cfg->compact_thresh >= lfs->cfg->block_size/2);
    LFS_ASSERT(lfs->cfg->compact_thresh == (luat_lfs2_size_t)-1
            || lfs->cfg->compact_thresh <= lfs->cfg->block_size);

    // setup read cache
    if (lfs->cfg->read_buffer) {
        lfs->rcache.buffer = lfs->cfg->read_buffer;
    } else {
        lfs->rcache.buffer = luat_lfs2_malloc(lfs->cfg->cache_size);
        if (!lfs->rcache.buffer) {
            err = LFS_ERR_NOMEM;
            goto cleanup;
        }
    }

    // setup program cache
    if (lfs->cfg->prog_buffer) {
        lfs->pcache.buffer = lfs->cfg->prog_buffer;
    } else {
        lfs->pcache.buffer = luat_lfs2_malloc(lfs->cfg->cache_size);
        if (!lfs->pcache.buffer) {
            err = LFS_ERR_NOMEM;
            goto cleanup;
        }
    }

    // zero to avoid information leaks
    luat_lfs2_cache_zero(lfs, &lfs->rcache);
    luat_lfs2_cache_zero(lfs, &lfs->pcache);

    // setup lookahead buffer, note mount finishes initializing this after
    // we establish a decent pseudo-random seed
    LFS_ASSERT(lfs->cfg->lookahead_size > 0);
    if (lfs->cfg->lookahead_buffer) {
        lfs->lookahead.buffer = lfs->cfg->lookahead_buffer;
    } else {
        lfs->lookahead.buffer = luat_lfs2_malloc(lfs->cfg->lookahead_size);
        if (!lfs->lookahead.buffer) {
            err = LFS_ERR_NOMEM;
            goto cleanup;
        }
    }

    // check that the size limits are sane
    LFS_ASSERT(lfs->cfg->name_max <= LFS_NAME_MAX);
    lfs->name_max = lfs->cfg->name_max;
    if (!lfs->name_max) {
        lfs->name_max = LFS_NAME_MAX;
    }

    LFS_ASSERT(lfs->cfg->file_max <= LFS_FILE_MAX);
    lfs->file_max = lfs->cfg->file_max;
    if (!lfs->file_max) {
        lfs->file_max = LFS_FILE_MAX;
    }

    LFS_ASSERT(lfs->cfg->attr_max <= LFS_ATTR_MAX);
    lfs->attr_max = lfs->cfg->attr_max;
    if (!lfs->attr_max) {
        lfs->attr_max = LFS_ATTR_MAX;
    }

    LFS_ASSERT(lfs->cfg->metadata_max <= lfs->cfg->block_size);

    LFS_ASSERT(lfs->cfg->inline_max == (luat_lfs2_size_t)-1
            || lfs->cfg->inline_max <= lfs->cfg->cache_size);
    LFS_ASSERT(lfs->cfg->inline_max == (luat_lfs2_size_t)-1
            || lfs->cfg->inline_max <= lfs->attr_max);
    LFS_ASSERT(lfs->cfg->inline_max == (luat_lfs2_size_t)-1
            || lfs->cfg->inline_max <= ((lfs->cfg->metadata_max)
                ? lfs->cfg->metadata_max
                : lfs->cfg->block_size)/8);
    lfs->inline_max = lfs->cfg->inline_max;
    if (lfs->inline_max == (luat_lfs2_size_t)-1) {
        lfs->inline_max = 0;
    } else if (lfs->inline_max == 0) {
        lfs->inline_max = luat_lfs2_min(
                lfs->cfg->cache_size,
                luat_lfs2_min(
                    lfs->attr_max,
                    ((lfs->cfg->metadata_max)
                        ? lfs->cfg->metadata_max
                        : lfs->cfg->block_size)/8));
    }

    // setup default state
    lfs->root[0] = LFS_BLOCK_NULL;
    lfs->root[1] = LFS_BLOCK_NULL;
    lfs->mlist = NULL;
    lfs->seed = 0;
    lfs->gdisk = (luat_lfs2_gstate_t){0};
    lfs->gstate = (luat_lfs2_gstate_t){0};
    lfs->gdelta = (luat_lfs2_gstate_t){0};
#ifdef LFS_MIGRATE
    lfs->lfs1 = NULL;
#endif
    lfs->preerase_enabled = 0;
    lfs->preerase_reserve_low = 0;
    lfs->preerase_reserve_high = 0;
    luat_lfs2_preerase_reset(lfs);

    return 0;

cleanup:
    luat_lfs2_deinit(lfs);
    return err;
}

static int luat_lfs2_deinit(luat_lfs2_t *lfs) {
    // free allocated memory
    if (!lfs->cfg->read_buffer) {
        luat_lfs2_free(lfs->rcache.buffer);
    }

    if (!lfs->cfg->prog_buffer) {
        luat_lfs2_free(lfs->pcache.buffer);
    }

    if (!lfs->cfg->lookahead_buffer) {
        luat_lfs2_free(lfs->lookahead.buffer);
    }

    return 0;
}



#ifndef LFS_READONLY
static int luat_lfs2_format_(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    int err = 0;
    {
        err = luat_lfs2_init(lfs, cfg);
        if (err) {
            return err;
        }

        LFS_ASSERT(cfg->block_count != 0);

        // create free lookahead
        memset(lfs->lookahead.buffer, 0, lfs->cfg->lookahead_size);
        lfs->lookahead.start = 0;
        lfs->lookahead.size = luat_lfs2_min(8*lfs->cfg->lookahead_size,
                lfs->block_count);
        lfs->lookahead.next = 0;
        luat_lfs2_alloc_ckpoint(lfs);

        // create root dir
        luat_lfs2_mdir_t root;
        err = luat_lfs2_dir_alloc(lfs, &root);
        if (err) {
            goto cleanup;
        }

        // write one superblock
        luat_lfs2_superblock_t superblock = {
            .version     = luat_lfs2_fs_disk_version(lfs),
            .block_size  = lfs->cfg->block_size,
            .block_count = lfs->block_count,
            .name_max    = lfs->name_max,
            .file_max    = lfs->file_max,
            .attr_max    = lfs->attr_max,
        };

        luat_lfs2_superblock_tole32(&superblock);
        err = luat_lfs2_dir_commit(lfs, &root, LFS_MKATTRS(
                {LFS_MKTAG(LFS_TYPE_CREATE, 0, 0), NULL},
                {LFS_MKTAG(LFS_TYPE_SUPERBLOCK, 0, 8), "littlefs"},
                {LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                    &superblock}));
        if (err) {
            goto cleanup;
        }

        // force compaction to prevent accidentally mounting any
        // older version of littlefs that may live on disk
        root.erased = false;
        err = luat_lfs2_dir_commit(lfs, &root, NULL, 0);
        if (err) {
            goto cleanup;
        }

        // sanity check that fetch works
        err = luat_lfs2_dir_fetch(lfs, &root, (const luat_lfs2_block_t[2]){0, 1});
        if (err) {
            goto cleanup;
        }
    }

cleanup:
    luat_lfs2_deinit(lfs);
    return err;

}
#endif

static int luat_lfs2_mount_(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    int err = luat_lfs2_init(lfs, cfg);
    if (err) {
        return err;
    }

    // scan directory blocks for superblock and any global updates
    luat_lfs2_mdir_t dir = {.tail = {0, 1}};
    luat_lfs2_block_t tortoise[2] = {LFS_BLOCK_NULL, LFS_BLOCK_NULL};
    luat_lfs2_size_t tortoise_i = 1;
    luat_lfs2_size_t tortoise_period = 1;
    while (!luat_lfs2_pair_isnull(dir.tail)) {
        // detect cycles with Brent's algorithm
        if (luat_lfs2_pair_issync(dir.tail, tortoise)) {
            LFS_WARN("Cycle detected in tail list");
            err = LFS_ERR_CORRUPT;
            goto cleanup;
        }
        if (tortoise_i == tortoise_period) {
            tortoise[0] = dir.tail[0];
            tortoise[1] = dir.tail[1];
            tortoise_i = 0;
            tortoise_period *= 2;
        }
        tortoise_i += 1;

        // fetch next block in tail list
        luat_lfs2_stag_t tag = luat_lfs2_dir_fetchmatch(lfs, &dir, dir.tail,
                LFS_MKTAG(0x7ff, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_SUPERBLOCK, 0, 8),
                NULL,
                luat_lfs2_dir_find_match, &(struct luat_lfs2_dir_find_match){
                    lfs, "littlefs", 8});
        if (tag < 0) {
            err = tag;
            goto cleanup;
        }

        // has superblock?
        if (tag && !luat_lfs2_tag_isdelete(tag)) {
            // update root
            lfs->root[0] = dir.pair[0];
            lfs->root[1] = dir.pair[1];

            // grab superblock
            luat_lfs2_superblock_t superblock;
            tag = luat_lfs2_dir_get(lfs, &dir, LFS_MKTAG(0x7ff, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                    &superblock);
            if (tag < 0) {
                err = tag;
                goto cleanup;
            }
            luat_lfs2_superblock_fromle32(&superblock);

            // check version
            uint16_t major_version = (0xffff & (superblock.version >> 16));
            uint16_t minor_version = (0xffff & (superblock.version >>  0));
            if (major_version != luat_lfs2_fs_disk_version_major(lfs)
                    || minor_version > luat_lfs2_fs_disk_version_minor(lfs)) {
                LFS_ERROR("Invalid version "
                        "v%"PRIu16".%"PRIu16" != v%"PRIu16".%"PRIu16,
                        major_version,
                        minor_version,
                        luat_lfs2_fs_disk_version_major(lfs),
                        luat_lfs2_fs_disk_version_minor(lfs));
                err = LFS_ERR_INVAL;
                goto cleanup;
            }

            // found older minor version? set an in-device only bit in the
            // gstate so we know we need to rewrite the superblock before
            // the first write
            bool needssuperblock = false;
            if (minor_version < luat_lfs2_fs_disk_version_minor(lfs)) {
                LFS_DEBUG("Found older minor version "
                        "v%"PRIu16".%"PRIu16" < v%"PRIu16".%"PRIu16,
                        major_version,
                        minor_version,
                        luat_lfs2_fs_disk_version_major(lfs),
                        luat_lfs2_fs_disk_version_minor(lfs));
                needssuperblock = true;
            }
            // note this bit is reserved on disk, so fetching more gstate
            // will not interfere here
            luat_lfs2_fs_prepsuperblock(lfs, needssuperblock);

            // check superblock configuration
            if (superblock.name_max) {
                if (superblock.name_max > lfs->name_max) {
                    LFS_ERROR("Unsupported name_max (%"PRIu32" > %"PRIu32")",
                            superblock.name_max, lfs->name_max);
                    err = LFS_ERR_INVAL;
                    goto cleanup;
                }

                lfs->name_max = superblock.name_max;
            }

            if (superblock.file_max) {
                if (superblock.file_max > lfs->file_max) {
                    LFS_ERROR("Unsupported file_max (%"PRIu32" > %"PRIu32")",
                            superblock.file_max, lfs->file_max);
                    err = LFS_ERR_INVAL;
                    goto cleanup;
                }

                lfs->file_max = superblock.file_max;
            }

            if (superblock.attr_max) {
                if (superblock.attr_max > lfs->attr_max) {
                    LFS_ERROR("Unsupported attr_max (%"PRIu32" > %"PRIu32")",
                            superblock.attr_max, lfs->attr_max);
                    err = LFS_ERR_INVAL;
                    goto cleanup;
                }

                lfs->attr_max = superblock.attr_max;

                // we also need to update inline_max in case attr_max changed
                lfs->inline_max = luat_lfs2_min(lfs->inline_max, lfs->attr_max);
            }

            // this is where we get the block_count from disk if block_count=0
            if (lfs->cfg->block_count
                    && superblock.block_count != lfs->cfg->block_count) {
                LFS_ERROR("Invalid block count (%"PRIu32" != %"PRIu32")",
                        superblock.block_count, lfs->cfg->block_count);
                err = LFS_ERR_INVAL;
                goto cleanup;
            }

            lfs->block_count = superblock.block_count;

            if (superblock.block_size != lfs->cfg->block_size) {
                LFS_ERROR("Invalid block size (%"PRIu32" != %"PRIu32")",
                        superblock.block_size, lfs->cfg->block_size);
                err = LFS_ERR_INVAL;
                goto cleanup;
            }
        }

        // has gstate?
        err = luat_lfs2_dir_getgstate(lfs, &dir, &lfs->gstate);
        if (err) {
            goto cleanup;
        }
    }

    // update littlefs with gstate
    if (!luat_lfs2_gstate_iszero(&lfs->gstate)) {
        LFS_DEBUG("Found pending gstate 0x%08"PRIx32"%08"PRIx32"%08"PRIx32,
                lfs->gstate.tag,
                lfs->gstate.pair[0],
                lfs->gstate.pair[1]);
    }
    lfs->gstate.tag += !luat_lfs2_tag_isvalid(lfs->gstate.tag);
    lfs->gdisk = lfs->gstate;

    // setup free lookahead, to distribute allocations uniformly across
    // boots, we start the allocator at a random location
    lfs->lookahead.start = lfs->seed % lfs->block_count;
    luat_lfs2_alloc_drop(lfs);

    return 0;

cleanup:
    luat_lfs2_unmount_(lfs);
    return err;
}

static int luat_lfs2_unmount_(luat_lfs2_t *lfs) {
    return luat_lfs2_deinit(lfs);
}


/// Filesystem filesystem operations ///
static int luat_lfs2_fs_stat_(luat_lfs2_t *lfs, struct luat_lfs2_fsinfo *fsinfo) {
    // if the superblock is up-to-date, we must be on the most recent
    // minor version of littlefs
    if (!luat_lfs2_gstate_needssuperblock(&lfs->gstate)) {
        fsinfo->disk_version = luat_lfs2_fs_disk_version(lfs);

    // otherwise we need to read the minor version on disk
    } else {
        // fetch the superblock
        luat_lfs2_mdir_t dir;
        int err = luat_lfs2_dir_fetch(lfs, &dir, lfs->root);
        if (err) {
            return err;
        }

        luat_lfs2_superblock_t superblock;
        luat_lfs2_stag_t tag = luat_lfs2_dir_get(lfs, &dir, LFS_MKTAG(0x7ff, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                &superblock);
        if (tag < 0) {
            return tag;
        }
        luat_lfs2_superblock_fromle32(&superblock);

        // read the on-disk version
        fsinfo->disk_version = superblock.version;
    }

    // filesystem geometry
    fsinfo->block_size = lfs->cfg->block_size;
    fsinfo->block_count = lfs->block_count;

    // other on-disk configuration, we cache all of these for internal use
    fsinfo->name_max = lfs->name_max;
    fsinfo->file_max = lfs->file_max;
    fsinfo->attr_max = lfs->attr_max;

    return 0;
}

int luat_lfs2_fs_traverse_(luat_lfs2_t *lfs,
        int (*cb)(void *data, luat_lfs2_block_t block), void *data,
        bool includeorphans) {
    // iterate over metadata pairs
    luat_lfs2_mdir_t dir = {.tail = {0, 1}};

#ifdef LFS_MIGRATE
    // also consider v1 blocks during migration
    if (lfs->lfs1) {
        int err = lfs1_traverse(lfs, cb, data);
        if (err) {
            return err;
        }

        dir.tail[0] = lfs->root[0];
        dir.tail[1] = lfs->root[1];
    }
#endif

    luat_lfs2_block_t tortoise[2] = {LFS_BLOCK_NULL, LFS_BLOCK_NULL};
    luat_lfs2_size_t tortoise_i = 1;
    luat_lfs2_size_t tortoise_period = 1;
    while (!luat_lfs2_pair_isnull(dir.tail)) {
        // detect cycles with Brent's algorithm
        if (luat_lfs2_pair_issync(dir.tail, tortoise)) {
            LFS_WARN("Cycle detected in tail list");
            return LFS_ERR_CORRUPT;
        }
        if (tortoise_i == tortoise_period) {
            tortoise[0] = dir.tail[0];
            tortoise[1] = dir.tail[1];
            tortoise_i = 0;
            tortoise_period *= 2;
        }
        tortoise_i += 1;

        for (int i = 0; i < 2; i++) {
            int err = cb(data, dir.tail[i]);
            if (err) {
                return err;
            }
        }

        // iterate through ids in directory
        int err = luat_lfs2_dir_fetch(lfs, &dir, dir.tail);
        if (err) {
            return err;
        }

        for (uint16_t id = 0; id < dir.count; id++) {
            struct luat_lfs2_ctz ctz;
            luat_lfs2_stag_t tag = luat_lfs2_dir_get(lfs, &dir, LFS_MKTAG(0x700, 0x3ff, 0),
                    LFS_MKTAG(LFS_TYPE_STRUCT, id, sizeof(ctz)), &ctz);
            if (tag < 0) {
                if (tag == LFS_ERR_NOENT) {
                    continue;
                }
                return tag;
            }
            luat_lfs2_ctz_fromle32(&ctz);

            if (luat_lfs2_tag_type3(tag) == LFS_TYPE_CTZSTRUCT) {
                err = luat_lfs2_ctz_traverse(lfs, NULL, &lfs->rcache,
                        ctz.head, ctz.size, cb, data);
                if (err) {
                    return err;
                }
            } else if (includeorphans &&
                    luat_lfs2_tag_type3(tag) == LFS_TYPE_DIRSTRUCT) {
                for (int i = 0; i < 2; i++) {
                    err = cb(data, (&ctz.head)[i]);
                    if (err) {
                        return err;
                    }
                }
            }
        }
    }

#ifndef LFS_READONLY
    // iterate over any open files
    for (luat_lfs2_file_t *f = (luat_lfs2_file_t*)lfs->mlist; f; f = f->next) {
        if (f->type != LFS_TYPE_REG) {
            continue;
        }

        if ((f->flags & LFS_F_DIRTY) && !(f->flags & LFS_F_INLINE)) {
            int err = luat_lfs2_ctz_traverse(lfs, &f->cache, &lfs->rcache,
                    f->ctz.head, f->ctz.size, cb, data);
            if (err) {
                return err;
            }
        }

        if ((f->flags & LFS_F_WRITING) && !(f->flags & LFS_F_INLINE)) {
            int err = luat_lfs2_ctz_traverse(lfs, &f->cache, &lfs->rcache,
                    f->block, f->pos, cb, data);
            if (err) {
                return err;
            }
        }
    }
#endif

    return 0;
}

#ifndef LFS_READONLY
static int luat_lfs2_fs_pred(luat_lfs2_t *lfs,
        const luat_lfs2_block_t pair[2], luat_lfs2_mdir_t *pdir) {
    // iterate over all directory directory entries
    pdir->tail[0] = 0;
    pdir->tail[1] = 1;
    luat_lfs2_block_t tortoise[2] = {LFS_BLOCK_NULL, LFS_BLOCK_NULL};
    luat_lfs2_size_t tortoise_i = 1;
    luat_lfs2_size_t tortoise_period = 1;
    while (!luat_lfs2_pair_isnull(pdir->tail)) {
        // detect cycles with Brent's algorithm
        if (luat_lfs2_pair_issync(pdir->tail, tortoise)) {
            LFS_WARN("Cycle detected in tail list");
            return LFS_ERR_CORRUPT;
        }
        if (tortoise_i == tortoise_period) {
            tortoise[0] = pdir->tail[0];
            tortoise[1] = pdir->tail[1];
            tortoise_i = 0;
            tortoise_period *= 2;
        }
        tortoise_i += 1;

        if (luat_lfs2_pair_cmp(pdir->tail, pair) == 0) {
            return 0;
        }

        int err = luat_lfs2_dir_fetch(lfs, pdir, pdir->tail);
        if (err) {
            return err;
        }
    }

    return LFS_ERR_NOENT;
}
#endif

#ifndef LFS_READONLY
struct luat_lfs2_fs_parent_match {
    luat_lfs2_t *lfs;
    const luat_lfs2_block_t pair[2];
};
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_parent_match(void *data,
        luat_lfs2_tag_t tag, const void *buffer) {
    struct luat_lfs2_fs_parent_match *find = data;
    luat_lfs2_t *lfs = find->lfs;
    const struct luat_lfs2_diskoff *disk = buffer;
    (void)tag;

    luat_lfs2_block_t child[2];
    int err = luat_lfs2_bd_read(lfs,
            &lfs->pcache, &lfs->rcache, lfs->cfg->block_size,
            disk->block, disk->off, &child, sizeof(child));
    if (err) {
        return err;
    }

    luat_lfs2_pair_fromle32(child);
    return (luat_lfs2_pair_cmp(child, find->pair) == 0) ? LFS_CMP_EQ : LFS_CMP_LT;
}
#endif

#ifndef LFS_READONLY
static luat_lfs2_stag_t luat_lfs2_fs_parent(luat_lfs2_t *lfs, const luat_lfs2_block_t pair[2],
        luat_lfs2_mdir_t *parent) {
    // use fetchmatch with callback to find pairs
    parent->tail[0] = 0;
    parent->tail[1] = 1;
    luat_lfs2_block_t tortoise[2] = {LFS_BLOCK_NULL, LFS_BLOCK_NULL};
    luat_lfs2_size_t tortoise_i = 1;
    luat_lfs2_size_t tortoise_period = 1;
    while (!luat_lfs2_pair_isnull(parent->tail)) {
        // detect cycles with Brent's algorithm
        if (luat_lfs2_pair_issync(parent->tail, tortoise)) {
            LFS_WARN("Cycle detected in tail list");
            return LFS_ERR_CORRUPT;
        }
        if (tortoise_i == tortoise_period) {
            tortoise[0] = parent->tail[0];
            tortoise[1] = parent->tail[1];
            tortoise_i = 0;
            tortoise_period *= 2;
        }
        tortoise_i += 1;

        luat_lfs2_stag_t tag = luat_lfs2_dir_fetchmatch(lfs, parent, parent->tail,
                LFS_MKTAG(0x7ff, 0, 0x3ff),
                LFS_MKTAG(LFS_TYPE_DIRSTRUCT, 0, 8),
                NULL,
                luat_lfs2_fs_parent_match, &(struct luat_lfs2_fs_parent_match){
                    lfs, {pair[0], pair[1]}});
        if (tag && tag != LFS_ERR_NOENT) {
            return tag;
        }
    }

    return LFS_ERR_NOENT;
}
#endif

static void luat_lfs2_fs_prepsuperblock(luat_lfs2_t *lfs, bool needssuperblock) {
    lfs->gstate.tag = (lfs->gstate.tag & ~LFS_MKTAG(0, 0, 0x200))
            | (uint32_t)needssuperblock << 9;
}

#ifndef LFS_READONLY
static int luat_lfs2_fs_preporphans(luat_lfs2_t *lfs, int8_t orphans) {
    LFS_ASSERT(luat_lfs2_tag_size(lfs->gstate.tag) > 0x000 || orphans >= 0);
    LFS_ASSERT(luat_lfs2_tag_size(lfs->gstate.tag) < 0x1ff || orphans <= 0);
    lfs->gstate.tag += orphans;
    lfs->gstate.tag = ((lfs->gstate.tag & ~LFS_MKTAG(0x800, 0, 0)) |
            ((uint32_t)luat_lfs2_gstate_hasorphans(&lfs->gstate) << 31));

    return 0;
}
#endif

#ifndef LFS_READONLY
static void luat_lfs2_fs_prepmove(luat_lfs2_t *lfs,
        uint16_t id, const luat_lfs2_block_t pair[2]) {
    lfs->gstate.tag = ((lfs->gstate.tag & ~LFS_MKTAG(0x7ff, 0x3ff, 0)) |
            ((id != 0x3ff) ? LFS_MKTAG(LFS_TYPE_DELETE, id, 0) : 0));
    lfs->gstate.pair[0] = (id != 0x3ff) ? pair[0] : 0;
    lfs->gstate.pair[1] = (id != 0x3ff) ? pair[1] : 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_desuperblock(luat_lfs2_t *lfs) {
    if (!luat_lfs2_gstate_needssuperblock(&lfs->gstate)) {
        return 0;
    }

    LFS_DEBUG("Rewriting superblock {0x%"PRIx32", 0x%"PRIx32"}",
            lfs->root[0],
            lfs->root[1]);

    luat_lfs2_mdir_t root;
    int err = luat_lfs2_dir_fetch(lfs, &root, lfs->root);
    if (err) {
        return err;
    }

    // write a new superblock
    luat_lfs2_superblock_t superblock = {
        .version     = luat_lfs2_fs_disk_version(lfs),
        .block_size  = lfs->cfg->block_size,
        .block_count = lfs->block_count,
        .name_max    = lfs->name_max,
        .file_max    = lfs->file_max,
        .attr_max    = lfs->attr_max,
    };

    luat_lfs2_superblock_tole32(&superblock);
    err = luat_lfs2_dir_commit(lfs, &root, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                &superblock}));
    if (err) {
        return err;
    }

    luat_lfs2_fs_prepsuperblock(lfs, false);
    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_demove(luat_lfs2_t *lfs) {
    if (!luat_lfs2_gstate_hasmove(&lfs->gdisk)) {
        return 0;
    }

    // Fix bad moves
    LFS_DEBUG("Fixing move {0x%"PRIx32", 0x%"PRIx32"} 0x%"PRIx16,
            lfs->gdisk.pair[0],
            lfs->gdisk.pair[1],
            luat_lfs2_tag_id(lfs->gdisk.tag));

    // no other gstate is supported at this time, so if we found something else
    // something most likely went wrong in gstate calculation
    LFS_ASSERT(luat_lfs2_tag_type3(lfs->gdisk.tag) == LFS_TYPE_DELETE);

    // fetch and delete the moved entry
    luat_lfs2_mdir_t movedir;
    int err = luat_lfs2_dir_fetch(lfs, &movedir, lfs->gdisk.pair);
    if (err) {
        return err;
    }

    // prep gstate and delete move id
    uint16_t moveid = luat_lfs2_tag_id(lfs->gdisk.tag);
    luat_lfs2_fs_prepmove(lfs, 0x3ff, NULL);
    err = luat_lfs2_dir_commit(lfs, &movedir, LFS_MKATTRS(
            {LFS_MKTAG(LFS_TYPE_DELETE, moveid, 0), NULL}));
    if (err) {
        return err;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_deorphan(luat_lfs2_t *lfs, bool powerloss) {
    if (!luat_lfs2_gstate_hasorphans(&lfs->gstate)) {
        return 0;
    }

    // Check for orphans in two separate passes:
    // - 1 for half-orphans (relocations)
    // - 2 for full-orphans (removes/renames)
    //
    // Two separate passes are needed as half-orphans can contain outdated
    // references to full-orphans, effectively hiding them from the deorphan
    // search.
    //
    int pass = 0;
    while (pass < 2) {
        // Fix any orphans
        luat_lfs2_mdir_t pdir = {.split = true, .tail = {0, 1}};
        luat_lfs2_mdir_t dir;
        bool moreorphans = false;

        // iterate over all directory directory entries
        while (!luat_lfs2_pair_isnull(pdir.tail)) {
            int err = luat_lfs2_dir_fetch(lfs, &dir, pdir.tail);
            if (err) {
                return err;
            }

            // check head blocks for orphans
            if (!pdir.split) {
                // check if we have a parent
                luat_lfs2_mdir_t parent;
                luat_lfs2_stag_t tag = luat_lfs2_fs_parent(lfs, pdir.tail, &parent);
                if (tag < 0 && tag != LFS_ERR_NOENT) {
                    return tag;
                }

                if (pass == 0 && tag != LFS_ERR_NOENT) {
                    luat_lfs2_block_t pair[2];
                    luat_lfs2_stag_t state = luat_lfs2_dir_get(lfs, &parent,
                            LFS_MKTAG(0x7ff, 0x3ff, 0), tag, pair);
                    if (state < 0) {
                        return state;
                    }
                    luat_lfs2_pair_fromle32(pair);

                    if (!luat_lfs2_pair_issync(pair, pdir.tail)) {
                        // we have desynced
                        LFS_DEBUG("Fixing half-orphan "
                                "{0x%"PRIx32", 0x%"PRIx32"} "
                                "-> {0x%"PRIx32", 0x%"PRIx32"}",
                                pdir.tail[0], pdir.tail[1], pair[0], pair[1]);

                        // fix pending move in this pair? this looks like an
                        // optimization but is in fact _required_ since
                        // relocating may outdate the move.
                        uint16_t moveid = 0x3ff;
                        if (luat_lfs2_gstate_hasmovehere(&lfs->gstate, pdir.pair)) {
                            moveid = luat_lfs2_tag_id(lfs->gstate.tag);
                            LFS_DEBUG("Fixing move while fixing orphans "
                                    "{0x%"PRIx32", 0x%"PRIx32"} 0x%"PRIx16"\n",
                                    pdir.pair[0], pdir.pair[1], moveid);
                            luat_lfs2_fs_prepmove(lfs, 0x3ff, NULL);
                        }

                        luat_lfs2_pair_tole32(pair);
                        state = luat_lfs2_dir_orphaningcommit(lfs, &pdir, LFS_MKATTRS(
                                {LFS_MKTAG_IF(moveid != 0x3ff,
                                    LFS_TYPE_DELETE, moveid, 0), NULL},
                                {LFS_MKTAG(LFS_TYPE_SOFTTAIL, 0x3ff, 8),
                                    pair}));
                        luat_lfs2_pair_fromle32(pair);
                        if (state < 0) {
                            return state;
                        }

                        // did our commit create more orphans?
                        if (state == LFS_OK_ORPHANED) {
                            moreorphans = true;
                        }

                        // refetch tail
                        continue;
                    }
                }

                // note we only check for full orphans if we may have had a
                // power-loss, otherwise orphans are created intentionally
                // during operations such as luat_lfs2_mkdir
                if (pass == 1 && tag == LFS_ERR_NOENT && powerloss) {
                    // we are an orphan
                    LFS_DEBUG("Fixing orphan {0x%"PRIx32", 0x%"PRIx32"}",
                            pdir.tail[0], pdir.tail[1]);

                    // steal state
                    err = luat_lfs2_dir_getgstate(lfs, &dir, &lfs->gdelta);
                    if (err) {
                        return err;
                    }

                    // steal tail
                    luat_lfs2_pair_tole32(dir.tail);
                    int state = luat_lfs2_dir_orphaningcommit(lfs, &pdir, LFS_MKATTRS(
                            {LFS_MKTAG(LFS_TYPE_TAIL + dir.split, 0x3ff, 8),
                                dir.tail}));
                    luat_lfs2_pair_fromle32(dir.tail);
                    if (state < 0) {
                        return state;
                    }

                    // did our commit create more orphans?
                    if (state == LFS_OK_ORPHANED) {
                        moreorphans = true;
                    }

                    // refetch tail
                    continue;
                }
            }

            pdir = dir;
        }

        pass = moreorphans ? 0 : pass+1;
    }

    // mark orphans as fixed
    return luat_lfs2_fs_preporphans(lfs, -luat_lfs2_gstate_getorphans(&lfs->gstate));
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_forceconsistency(luat_lfs2_t *lfs) {
    int err = luat_lfs2_fs_desuperblock(lfs);
    if (err) {
        return err;
    }

    err = luat_lfs2_fs_demove(lfs);
    if (err) {
        return err;
    }

    err = luat_lfs2_fs_deorphan(lfs, true);
    if (err) {
        return err;
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_mkconsistent_(luat_lfs2_t *lfs) {
    // luat_lfs2_fs_forceconsistency does most of the work here
    int err = luat_lfs2_fs_forceconsistency(lfs);
    if (err) {
        return err;
    }

    // do we have any pending gstate?
    luat_lfs2_gstate_t delta = {0};
    luat_lfs2_gstate_xor(&delta, &lfs->gdisk);
    luat_lfs2_gstate_xor(&delta, &lfs->gstate);
    if (!luat_lfs2_gstate_iszero(&delta)) {
        // luat_lfs2_dir_commit will implicitly write out any pending gstate
        luat_lfs2_mdir_t root;
        err = luat_lfs2_dir_fetch(lfs, &root, lfs->root);
        if (err) {
            return err;
        }

        err = luat_lfs2_dir_commit(lfs, &root, NULL, 0);
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif

static int luat_lfs2_fs_size_count(void *p, luat_lfs2_block_t block) {
    (void)block;
    luat_lfs2_size_t *size = p;
    *size += 1;
    return 0;
}

static luat_lfs2_ssize_t luat_lfs2_fs_size_(luat_lfs2_t *lfs) {
    luat_lfs2_size_t size = 0;
    int err = luat_lfs2_fs_traverse_(lfs, luat_lfs2_fs_size_count, &size, false);
    if (err) {
        return err;
    }

    return size;
}

// explicit garbage collection
#ifndef LFS_READONLY
static int luat_lfs2_fs_gc_(luat_lfs2_t *lfs) {
    // force consistency, even if we're not necessarily going to write,
    // because this function is supposed to take care of janitorial work
    // isn't it?
    int err = luat_lfs2_fs_forceconsistency(lfs);
    if (err) {
        return err;
    }

    // try to compact metadata pairs, note we can't really accomplish
    // anything if compact_thresh doesn't at least leave a prog_size
    // available
    if (lfs->cfg->compact_thresh
            < lfs->cfg->block_size - lfs->cfg->prog_size) {
        // iterate over all mdirs
        luat_lfs2_mdir_t mdir = {.tail = {0, 1}};
        while (!luat_lfs2_pair_isnull(mdir.tail)) {
            err = luat_lfs2_dir_fetch(lfs, &mdir, mdir.tail);
            if (err) {
                return err;
            }

            // not erased? exceeds our compaction threshold?
            if (!mdir.erased || ((lfs->cfg->compact_thresh == 0)
                    ? mdir.off > lfs->cfg->block_size - lfs->cfg->block_size/8
                    : mdir.off > lfs->cfg->compact_thresh)) {
                // the easiest way to trigger a compaction is to mark
                // the mdir as unerased and add an empty commit
                mdir.erased = false;
                err = luat_lfs2_dir_commit(lfs, &mdir, NULL, 0);
                if (err) {
                    return err;
                }
            }
        }
    }

    // try to populate the lookahead buffer, unless it's already full
    if (lfs->lookahead.size < 8*lfs->cfg->lookahead_size) {
        err = luat_lfs2_alloc_scan(lfs);
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif

#ifndef LFS_READONLY
static int luat_lfs2_fs_grow_(luat_lfs2_t *lfs, luat_lfs2_size_t block_count) {
    // shrinking is not supported
    LFS_ASSERT(block_count >= lfs->block_count);

    if (block_count > lfs->block_count) {
        lfs->block_count = block_count;

        // fetch the root
        luat_lfs2_mdir_t root;
        int err = luat_lfs2_dir_fetch(lfs, &root, lfs->root);
        if (err) {
            return err;
        }

        // update the superblock
        luat_lfs2_superblock_t superblock;
        luat_lfs2_stag_t tag = luat_lfs2_dir_get(lfs, &root, LFS_MKTAG(0x7ff, 0x3ff, 0),
                LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                &superblock);
        if (tag < 0) {
            return tag;
        }
        luat_lfs2_superblock_fromle32(&superblock);

        superblock.block_count = lfs->block_count;

        luat_lfs2_superblock_tole32(&superblock);
        err = luat_lfs2_dir_commit(lfs, &root, LFS_MKATTRS(
                {tag, &superblock}));
        if (err) {
            return err;
        }
    }

    return 0;
}
#endif

#ifdef LFS_MIGRATE
////// Migration from littelfs v1 below this //////

/// Version info ///

// Software library version
// Major (top-nibble), incremented on backwards incompatible changes
// Minor (bottom-nibble), incremented on feature additions
#define LFS1_VERSION 0x00010007
#define LFS1_VERSION_MAJOR (0xffff & (LFS1_VERSION >> 16))
#define LFS1_VERSION_MINOR (0xffff & (LFS1_VERSION >>  0))

// Version of On-disk data structures
// Major (top-nibble), incremented on backwards incompatible changes
// Minor (bottom-nibble), incremented on feature additions
#define LFS1_DISK_VERSION 0x00010001
#define LFS1_DISK_VERSION_MAJOR (0xffff & (LFS1_DISK_VERSION >> 16))
#define LFS1_DISK_VERSION_MINOR (0xffff & (LFS1_DISK_VERSION >>  0))


/// v1 Definitions ///

// File types
enum lfs1_type {
    LFS1_TYPE_REG        = 0x11,
    LFS1_TYPE_DIR        = 0x22,
    LFS1_TYPE_SUPERBLOCK = 0x2e,
};

typedef struct lfs1 {
    luat_lfs2_block_t root[2];
} lfs1_t;

typedef struct lfs1_entry {
    luat_lfs2_off_t off;

    struct lfs1_disk_entry {
        uint8_t type;
        uint8_t elen;
        uint8_t alen;
        uint8_t nlen;
        union {
            struct {
                luat_lfs2_block_t head;
                luat_lfs2_size_t size;
            } file;
            luat_lfs2_block_t dir[2];
        } u;
    } d;
} lfs1_entry_t;

typedef struct lfs1_dir {
    struct lfs1_dir *next;
    luat_lfs2_block_t pair[2];
    luat_lfs2_off_t off;

    luat_lfs2_block_t head[2];
    luat_lfs2_off_t pos;

    struct lfs1_disk_dir {
        uint32_t rev;
        luat_lfs2_size_t size;
        luat_lfs2_block_t tail[2];
    } d;
} lfs1_dir_t;

typedef struct lfs1_superblock {
    luat_lfs2_off_t off;

    struct lfs1_disk_superblock {
        uint8_t type;
        uint8_t elen;
        uint8_t alen;
        uint8_t nlen;
        luat_lfs2_block_t root[2];
        uint32_t block_size;
        uint32_t block_count;
        uint32_t version;
        char magic[8];
    } d;
} lfs1_superblock_t;


/// Low-level wrappers v1->v2 ///
static void lfs1_crc(uint32_t *crc, const void *buffer, size_t size) {
    *crc = luat_lfs2_crc(*crc, buffer, size);
}

static int lfs1_bd_read(luat_lfs2_t *lfs, luat_lfs2_block_t block,
        luat_lfs2_off_t off, void *buffer, luat_lfs2_size_t size) {
    // if we ever do more than writes to alternating pairs,
    // this may need to consider pcache
    return luat_lfs2_bd_read(lfs, &lfs->pcache, &lfs->rcache, size,
            block, off, buffer, size);
}

static int lfs1_bd_crc(luat_lfs2_t *lfs, luat_lfs2_block_t block,
        luat_lfs2_off_t off, luat_lfs2_size_t size, uint32_t *crc) {
    for (luat_lfs2_off_t i = 0; i < size; i++) {
        uint8_t c;
        int err = lfs1_bd_read(lfs, block, off+i, &c, 1);
        if (err) {
            return err;
        }

        lfs1_crc(crc, &c, 1);
    }

    return 0;
}


/// Endian swapping functions ///
static void lfs1_dir_fromle32(struct lfs1_disk_dir *d) {
    d->rev     = luat_lfs2_fromle32(d->rev);
    d->size    = luat_lfs2_fromle32(d->size);
    d->tail[0] = luat_lfs2_fromle32(d->tail[0]);
    d->tail[1] = luat_lfs2_fromle32(d->tail[1]);
}

static void lfs1_dir_tole32(struct lfs1_disk_dir *d) {
    d->rev     = luat_lfs2_tole32(d->rev);
    d->size    = luat_lfs2_tole32(d->size);
    d->tail[0] = luat_lfs2_tole32(d->tail[0]);
    d->tail[1] = luat_lfs2_tole32(d->tail[1]);
}

static void lfs1_entry_fromle32(struct lfs1_disk_entry *d) {
    d->u.dir[0] = luat_lfs2_fromle32(d->u.dir[0]);
    d->u.dir[1] = luat_lfs2_fromle32(d->u.dir[1]);
}

static void lfs1_entry_tole32(struct lfs1_disk_entry *d) {
    d->u.dir[0] = luat_lfs2_tole32(d->u.dir[0]);
    d->u.dir[1] = luat_lfs2_tole32(d->u.dir[1]);
}

static void lfs1_superblock_fromle32(struct lfs1_disk_superblock *d) {
    d->root[0]     = luat_lfs2_fromle32(d->root[0]);
    d->root[1]     = luat_lfs2_fromle32(d->root[1]);
    d->block_size  = luat_lfs2_fromle32(d->block_size);
    d->block_count = luat_lfs2_fromle32(d->block_count);
    d->version     = luat_lfs2_fromle32(d->version);
}


///// Metadata pair and directory operations ///
static inline luat_lfs2_size_t lfs1_entry_size(const lfs1_entry_t *entry) {
    return 4 + entry->d.elen + entry->d.alen + entry->d.nlen;
}

static int lfs1_dir_fetch(luat_lfs2_t *lfs,
        lfs1_dir_t *dir, const luat_lfs2_block_t pair[2]) {
    // copy out pair, otherwise may be aliasing dir
    const luat_lfs2_block_t tpair[2] = {pair[0], pair[1]};
    bool valid = false;

    // check both blocks for the most recent revision
    for (int i = 0; i < 2; i++) {
        struct lfs1_disk_dir test;
        int err = lfs1_bd_read(lfs, tpair[i], 0, &test, sizeof(test));
        lfs1_dir_fromle32(&test);
        if (err) {
            if (err == LFS_ERR_CORRUPT) {
                continue;
            }
            return err;
        }

        if (valid && luat_lfs2_scmp(test.rev, dir->d.rev) < 0) {
            continue;
        }

        if ((0x7fffffff & test.size) < sizeof(test)+4 ||
            (0x7fffffff & test.size) > lfs->cfg->block_size) {
            continue;
        }

        uint32_t crc = 0xffffffff;
        lfs1_dir_tole32(&test);
        lfs1_crc(&crc, &test, sizeof(test));
        lfs1_dir_fromle32(&test);
        err = lfs1_bd_crc(lfs, tpair[i], sizeof(test),
                (0x7fffffff & test.size) - sizeof(test), &crc);
        if (err) {
            if (err == LFS_ERR_CORRUPT) {
                continue;
            }
            return err;
        }

        if (crc != 0) {
            continue;
        }

        valid = true;

        // setup dir in case it's valid
        dir->pair[0] = tpair[(i+0) % 2];
        dir->pair[1] = tpair[(i+1) % 2];
        dir->off = sizeof(dir->d);
        dir->d = test;
    }

    if (!valid) {
        LFS_ERROR("Corrupted dir pair at {0x%"PRIx32", 0x%"PRIx32"}",
                tpair[0], tpair[1]);
        return LFS_ERR_CORRUPT;
    }

    return 0;
}

static int lfs1_dir_next(luat_lfs2_t *lfs, lfs1_dir_t *dir, lfs1_entry_t *entry) {
    while (dir->off + sizeof(entry->d) > (0x7fffffff & dir->d.size)-4) {
        if (!(0x80000000 & dir->d.size)) {
            entry->off = dir->off;
            return LFS_ERR_NOENT;
        }

        int err = lfs1_dir_fetch(lfs, dir, dir->d.tail);
        if (err) {
            return err;
        }

        dir->off = sizeof(dir->d);
        dir->pos += sizeof(dir->d) + 4;
    }

    int err = lfs1_bd_read(lfs, dir->pair[0], dir->off,
            &entry->d, sizeof(entry->d));
    lfs1_entry_fromle32(&entry->d);
    if (err) {
        return err;
    }

    entry->off = dir->off;
    dir->off += lfs1_entry_size(entry);
    dir->pos += lfs1_entry_size(entry);
    return 0;
}

/// littlefs v1 specific operations ///
int lfs1_traverse(luat_lfs2_t *lfs, int (*cb)(void*, luat_lfs2_block_t), void *data) {
    if (luat_lfs2_pair_isnull(lfs->lfs1->root)) {
        return 0;
    }

    // iterate over metadata pairs
    lfs1_dir_t dir;
    lfs1_entry_t entry;
    luat_lfs2_block_t cwd[2] = {0, 1};

    while (true) {
        for (int i = 0; i < 2; i++) {
            int err = cb(data, cwd[i]);
            if (err) {
                return err;
            }
        }

        int err = lfs1_dir_fetch(lfs, &dir, cwd);
        if (err) {
            return err;
        }

        // iterate over contents
        while (dir.off + sizeof(entry.d) <= (0x7fffffff & dir.d.size)-4) {
            err = lfs1_bd_read(lfs, dir.pair[0], dir.off,
                    &entry.d, sizeof(entry.d));
            lfs1_entry_fromle32(&entry.d);
            if (err) {
                return err;
            }

            dir.off += lfs1_entry_size(&entry);
            if ((0x70 & entry.d.type) == (0x70 & LFS1_TYPE_REG)) {
                err = luat_lfs2_ctz_traverse(lfs, NULL, &lfs->rcache,
                        entry.d.u.file.head, entry.d.u.file.size, cb, data);
                if (err) {
                    return err;
                }
            }
        }

        // we also need to check if we contain a threaded v2 directory
        luat_lfs2_mdir_t dir2 = {.split=true, .tail={cwd[0], cwd[1]}};
        while (dir2.split) {
            err = luat_lfs2_dir_fetch(lfs, &dir2, dir2.tail);
            if (err) {
                break;
            }

            for (int i = 0; i < 2; i++) {
                err = cb(data, dir2.pair[i]);
                if (err) {
                    return err;
                }
            }
        }

        cwd[0] = dir.d.tail[0];
        cwd[1] = dir.d.tail[1];

        if (luat_lfs2_pair_isnull(cwd)) {
            break;
        }
    }

    return 0;
}

static int lfs1_moved(luat_lfs2_t *lfs, const void *e) {
    if (luat_lfs2_pair_isnull(lfs->lfs1->root)) {
        return 0;
    }

    // skip superblock
    lfs1_dir_t cwd;
    int err = lfs1_dir_fetch(lfs, &cwd, (const luat_lfs2_block_t[2]){0, 1});
    if (err) {
        return err;
    }

    // iterate over all directory directory entries
    lfs1_entry_t entry;
    while (!luat_lfs2_pair_isnull(cwd.d.tail)) {
        err = lfs1_dir_fetch(lfs, &cwd, cwd.d.tail);
        if (err) {
            return err;
        }

        while (true) {
            err = lfs1_dir_next(lfs, &cwd, &entry);
            if (err && err != LFS_ERR_NOENT) {
                return err;
            }

            if (err == LFS_ERR_NOENT) {
                break;
            }

            if (!(0x80 & entry.d.type) &&
                 memcmp(&entry.d.u, e, sizeof(entry.d.u)) == 0) {
                return true;
            }
        }
    }

    return false;
}

/// Filesystem operations ///
static int lfs1_mount(luat_lfs2_t *lfs, struct lfs1 *lfs1,
        const struct luat_lfs2_config *cfg) {
    int err = 0;
    {
        err = luat_lfs2_init(lfs, cfg);
        if (err) {
            return err;
        }

        lfs->lfs1 = lfs1;
        lfs->lfs1->root[0] = LFS_BLOCK_NULL;
        lfs->lfs1->root[1] = LFS_BLOCK_NULL;

        // setup free lookahead
        lfs->lookahead.start = 0;
        lfs->lookahead.size = 0;
        lfs->lookahead.next = 0;
        luat_lfs2_alloc_ckpoint(lfs);

        // load superblock
        lfs1_dir_t dir;
        lfs1_superblock_t superblock;
        err = lfs1_dir_fetch(lfs, &dir, (const luat_lfs2_block_t[2]){0, 1});
        if (err && err != LFS_ERR_CORRUPT) {
            goto cleanup;
        }

        if (!err) {
            err = lfs1_bd_read(lfs, dir.pair[0], sizeof(dir.d),
                    &superblock.d, sizeof(superblock.d));
            lfs1_superblock_fromle32(&superblock.d);
            if (err) {
                goto cleanup;
            }

            lfs->lfs1->root[0] = superblock.d.root[0];
            lfs->lfs1->root[1] = superblock.d.root[1];
        }

        if (err || memcmp(superblock.d.magic, "littlefs", 8) != 0) {
            LFS_ERROR("Invalid superblock at {0x%"PRIx32", 0x%"PRIx32"}",
                    0, 1);
            err = LFS_ERR_CORRUPT;
            goto cleanup;
        }

        uint16_t major_version = (0xffff & (superblock.d.version >> 16));
        uint16_t minor_version = (0xffff & (superblock.d.version >>  0));
        if ((major_version != LFS1_DISK_VERSION_MAJOR ||
             minor_version > LFS1_DISK_VERSION_MINOR)) {
            LFS_ERROR("Invalid version v%d.%d", major_version, minor_version);
            err = LFS_ERR_INVAL;
            goto cleanup;
        }

        return 0;
    }

cleanup:
    luat_lfs2_deinit(lfs);
    return err;
}

static int lfs1_unmount(luat_lfs2_t *lfs) {
    return luat_lfs2_deinit(lfs);
}

/// v1 migration ///
static int luat_lfs2_migrate_(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    struct lfs1 lfs1;

    // Indeterminate filesystem size not allowed for migration.
    LFS_ASSERT(cfg->block_count != 0);

    int err = lfs1_mount(lfs, &lfs1, cfg);
    if (err) {
        return err;
    }

    {
        // iterate through each directory, copying over entries
        // into new directory
        lfs1_dir_t dir1;
        luat_lfs2_mdir_t dir2;
        dir1.d.tail[0] = lfs->lfs1->root[0];
        dir1.d.tail[1] = lfs->lfs1->root[1];
        while (!luat_lfs2_pair_isnull(dir1.d.tail)) {
            // iterate old dir
            err = lfs1_dir_fetch(lfs, &dir1, dir1.d.tail);
            if (err) {
                goto cleanup;
            }

            // create new dir and bind as temporary pretend root
            err = luat_lfs2_dir_alloc(lfs, &dir2);
            if (err) {
                goto cleanup;
            }

            dir2.rev = dir1.d.rev;
            dir1.head[0] = dir1.pair[0];
            dir1.head[1] = dir1.pair[1];
            lfs->root[0] = dir2.pair[0];
            lfs->root[1] = dir2.pair[1];

            err = luat_lfs2_dir_commit(lfs, &dir2, NULL, 0);
            if (err) {
                goto cleanup;
            }

            while (true) {
                lfs1_entry_t entry1;
                err = lfs1_dir_next(lfs, &dir1, &entry1);
                if (err && err != LFS_ERR_NOENT) {
                    goto cleanup;
                }

                if (err == LFS_ERR_NOENT) {
                    break;
                }

                // check that entry has not been moved
                if (entry1.d.type & 0x80) {
                    int moved = lfs1_moved(lfs, &entry1.d.u);
                    if (moved < 0) {
                        err = moved;
                        goto cleanup;
                    }

                    if (moved) {
                        continue;
                    }

                    entry1.d.type &= ~0x80;
                }

                // also fetch name
                char name[LFS_NAME_MAX+1];
                memset(name, 0, sizeof(name));
                err = lfs1_bd_read(lfs, dir1.pair[0],
                        entry1.off + 4+entry1.d.elen+entry1.d.alen,
                        name, entry1.d.nlen);
                if (err) {
                    goto cleanup;
                }

                bool isdir = (entry1.d.type == LFS1_TYPE_DIR);

                // create entry in new dir
                err = luat_lfs2_dir_fetch(lfs, &dir2, lfs->root);
                if (err) {
                    goto cleanup;
                }

                uint16_t id;
                err = luat_lfs2_dir_find(lfs, &dir2, &(const char*){name}, &id);
                if (!(err == LFS_ERR_NOENT && id != 0x3ff)) {
                    err = (err < 0) ? err : LFS_ERR_EXIST;
                    goto cleanup;
                }

                lfs1_entry_tole32(&entry1.d);
                err = luat_lfs2_dir_commit(lfs, &dir2, LFS_MKATTRS(
                        {LFS_MKTAG(LFS_TYPE_CREATE, id, 0), NULL},
                        {LFS_MKTAG_IF_ELSE(isdir,
                            LFS_TYPE_DIR, id, entry1.d.nlen,
                            LFS_TYPE_REG, id, entry1.d.nlen),
                                name},
                        {LFS_MKTAG_IF_ELSE(isdir,
                            LFS_TYPE_DIRSTRUCT, id, sizeof(entry1.d.u),
                            LFS_TYPE_CTZSTRUCT, id, sizeof(entry1.d.u)),
                                &entry1.d.u}));
                lfs1_entry_fromle32(&entry1.d);
                if (err) {
                    goto cleanup;
                }
            }

            if (!luat_lfs2_pair_isnull(dir1.d.tail)) {
                // find last block and update tail to thread into fs
                err = luat_lfs2_dir_fetch(lfs, &dir2, lfs->root);
                if (err) {
                    goto cleanup;
                }

                while (dir2.split) {
                    err = luat_lfs2_dir_fetch(lfs, &dir2, dir2.tail);
                    if (err) {
                        goto cleanup;
                    }
                }

                luat_lfs2_pair_tole32(dir2.pair);
                err = luat_lfs2_dir_commit(lfs, &dir2, LFS_MKATTRS(
                        {LFS_MKTAG(LFS_TYPE_SOFTTAIL, 0x3ff, 8), dir1.d.tail}));
                luat_lfs2_pair_fromle32(dir2.pair);
                if (err) {
                    goto cleanup;
                }
            }

            // Copy over first block to thread into fs. Unfortunately
            // if this fails there is not much we can do.
            LFS_DEBUG("Migrating {0x%"PRIx32", 0x%"PRIx32"} "
                        "-> {0x%"PRIx32", 0x%"PRIx32"}",
                    lfs->root[0], lfs->root[1], dir1.head[0], dir1.head[1]);

            err = luat_lfs2_bd_erase(lfs, dir1.head[1]);
            if (err) {
                goto cleanup;
            }

            err = luat_lfs2_dir_fetch(lfs, &dir2, lfs->root);
            if (err) {
                goto cleanup;
            }

            for (luat_lfs2_off_t i = 0; i < dir2.off; i++) {
                uint8_t dat;
                err = luat_lfs2_bd_read(lfs,
                        NULL, &lfs->rcache, dir2.off,
                        dir2.pair[0], i, &dat, 1);
                if (err) {
                    goto cleanup;
                }

                err = luat_lfs2_bd_prog(lfs,
                        &lfs->pcache, &lfs->rcache, true,
                        dir1.head[1], i, &dat, 1);
                if (err) {
                    goto cleanup;
                }
            }

            err = luat_lfs2_bd_flush(lfs, &lfs->pcache, &lfs->rcache, true);
            if (err) {
                goto cleanup;
            }
        }

        // Create new superblock. This marks a successful migration!
        err = lfs1_dir_fetch(lfs, &dir1, (const luat_lfs2_block_t[2]){0, 1});
        if (err) {
            goto cleanup;
        }

        dir2.pair[0] = dir1.pair[0];
        dir2.pair[1] = dir1.pair[1];
        dir2.rev = dir1.d.rev;
        dir2.off = sizeof(dir2.rev);
        dir2.etag = 0xffffffff;
        dir2.count = 0;
        dir2.tail[0] = lfs->lfs1->root[0];
        dir2.tail[1] = lfs->lfs1->root[1];
        dir2.erased = false;
        dir2.split = true;

        luat_lfs2_superblock_t superblock = {
            .version     = LFS_DISK_VERSION,
            .block_size  = lfs->cfg->block_size,
            .block_count = lfs->cfg->block_count,
            .name_max    = lfs->name_max,
            .file_max    = lfs->file_max,
            .attr_max    = lfs->attr_max,
        };

        luat_lfs2_superblock_tole32(&superblock);
        err = luat_lfs2_dir_commit(lfs, &dir2, LFS_MKATTRS(
                {LFS_MKTAG(LFS_TYPE_CREATE, 0, 0), NULL},
                {LFS_MKTAG(LFS_TYPE_SUPERBLOCK, 0, 8), "littlefs"},
                {LFS_MKTAG(LFS_TYPE_INLINESTRUCT, 0, sizeof(superblock)),
                    &superblock}));
        if (err) {
            goto cleanup;
        }

        // sanity check that fetch works
        err = luat_lfs2_dir_fetch(lfs, &dir2, (const luat_lfs2_block_t[2]){0, 1});
        if (err) {
            goto cleanup;
        }

        // force compaction to prevent accidentally mounting v1
        dir2.erased = false;
        err = luat_lfs2_dir_commit(lfs, &dir2, NULL, 0);
        if (err) {
            goto cleanup;
        }
    }

cleanup:
    lfs1_unmount(lfs);
    return err;
}

#endif


/// Public API wrappers ///

// Here we can add tracing/thread safety easily

// Thread-safe wrappers if enabled
#ifdef LFS_THREADSAFE
#define LFS_LOCK(cfg)   cfg->lock(cfg)
#define LFS_UNLOCK(cfg) cfg->unlock(cfg)
#else
#define LFS_LOCK(cfg)   ((void)cfg, 0)
#define LFS_UNLOCK(cfg) ((void)cfg)
#endif

// Public API
#ifndef LFS_READONLY
int luat_lfs2_format(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    int err = LFS_LOCK(cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_format(%p, %p {.context=%p, "
                ".read=%p, .prog=%p, .erase=%p, .sync=%p, "
                ".read_size=%"PRIu32", .prog_size=%"PRIu32", "
                ".block_size=%"PRIu32", .block_count=%"PRIu32", "
                ".block_cycles=%"PRIu32", .cache_size=%"PRIu32", "
                ".lookahead_size=%"PRIu32", .read_buffer=%p, "
                ".prog_buffer=%p, .lookahead_buffer=%p, "
                ".name_max=%"PRIu32", .file_max=%"PRIu32", "
                ".attr_max=%"PRIu32"})",
            (void*)lfs, (void*)cfg, cfg->context,
            (void*)(uintptr_t)cfg->read, (void*)(uintptr_t)cfg->prog,
            (void*)(uintptr_t)cfg->erase, (void*)(uintptr_t)cfg->sync,
            cfg->read_size, cfg->prog_size, cfg->block_size, cfg->block_count,
            cfg->block_cycles, cfg->cache_size, cfg->lookahead_size,
            cfg->read_buffer, cfg->prog_buffer, cfg->lookahead_buffer,
            cfg->name_max, cfg->file_max, cfg->attr_max);

    err = luat_lfs2_format_(lfs, cfg);

    LFS_TRACE("luat_lfs2_format -> %d", err);
    LFS_UNLOCK(cfg);
    return err;
}
#endif

int luat_lfs2_mount(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    int err = LFS_LOCK(cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_mount(%p, %p {.context=%p, "
                ".read=%p, .prog=%p, .erase=%p, .sync=%p, "
                ".read_size=%"PRIu32", .prog_size=%"PRIu32", "
                ".block_size=%"PRIu32", .block_count=%"PRIu32", "
                ".block_cycles=%"PRIu32", .cache_size=%"PRIu32", "
                ".lookahead_size=%"PRIu32", .read_buffer=%p, "
                ".prog_buffer=%p, .lookahead_buffer=%p, "
                ".name_max=%"PRIu32", .file_max=%"PRIu32", "
                ".attr_max=%"PRIu32"})",
            (void*)lfs, (void*)cfg, cfg->context,
            (void*)(uintptr_t)cfg->read, (void*)(uintptr_t)cfg->prog,
            (void*)(uintptr_t)cfg->erase, (void*)(uintptr_t)cfg->sync,
            cfg->read_size, cfg->prog_size, cfg->block_size, cfg->block_count,
            cfg->block_cycles, cfg->cache_size, cfg->lookahead_size,
            cfg->read_buffer, cfg->prog_buffer, cfg->lookahead_buffer,
            cfg->name_max, cfg->file_max, cfg->attr_max);

    err = luat_lfs2_mount_(lfs, cfg);

    LFS_TRACE("luat_lfs2_mount -> %d", err);
    LFS_UNLOCK(cfg);
    return err;
}

int luat_lfs2_unmount(luat_lfs2_t *lfs) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_unmount(%p)", (void*)lfs);

    err = luat_lfs2_unmount_(lfs);

    LFS_TRACE("luat_lfs2_unmount -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

#ifndef LFS_READONLY
void luat_lfs2_preerase_configure(luat_lfs2_t *lfs, uint8_t enabled, uint8_t low_watermark, uint8_t high_watermark) {
    if (!lfs) {
        return;
    }
    if (!enabled) {
        lfs->preerase_enabled = 0;
        lfs->preerase_reserve_low = 0;
        lfs->preerase_reserve_high = 0;
        luat_lfs2_preerase_reset(lfs);
        return;
    }
    if (high_watermark > (uint8_t)(sizeof(lfs->preerase_reserve) / sizeof(lfs->preerase_reserve[0]))) {
        high_watermark = (uint8_t)(sizeof(lfs->preerase_reserve) / sizeof(lfs->preerase_reserve[0]));
    }
    if (high_watermark == 0) {
        high_watermark = 1;
    }
    if (low_watermark >= high_watermark) {
        low_watermark = (uint8_t)(high_watermark > 0 ? high_watermark - 1 : 0);
    }
    lfs->preerase_enabled = 1;
    lfs->preerase_reserve_low = low_watermark;
    lfs->preerase_reserve_high = high_watermark;
    luat_lfs2_preerase_reset(lfs);
}

void luat_lfs2_preerase_get_stats(luat_lfs2_t *lfs, luat_lfs2_preerase_stats_t *out_stats) {
    if (!out_stats) {
        return;
    }
    memset(out_stats, 0, sizeof(*out_stats));
    if (!lfs) {
        return;
    }
    *out_stats = lfs->preerase_stats;
    out_stats->reserve_peak_count = lfs->preerase_reserve_peak;
    out_stats->reserve_current_count = lfs->preerase_reserve_count;
}
#endif

#ifndef LFS_READONLY
int luat_lfs2_remove(luat_lfs2_t *lfs, const char *path) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_remove(%p, \"%s\")", (void*)lfs, path);

    err = luat_lfs2_remove_(lfs, path);

    LFS_TRACE("luat_lfs2_remove -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifndef LFS_READONLY
int luat_lfs2_rename(luat_lfs2_t *lfs, const char *oldpath, const char *newpath) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_rename(%p, \"%s\", \"%s\")", (void*)lfs, oldpath, newpath);

    err = luat_lfs2_rename_(lfs, oldpath, newpath);

    LFS_TRACE("luat_lfs2_rename -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

int luat_lfs2_stat(luat_lfs2_t *lfs, const char *path, struct luat_lfs2_info *info) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_stat(%p, \"%s\", %p)", (void*)lfs, path, (void*)info);

    err = luat_lfs2_stat_(lfs, path, info);

    LFS_TRACE("luat_lfs2_stat -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

luat_lfs2_ssize_t luat_lfs2_getattr(luat_lfs2_t *lfs, const char *path,
        uint8_t type, void *buffer, luat_lfs2_size_t size) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_getattr(%p, \"%s\", %"PRIu8", %p, %"PRIu32")",
            (void*)lfs, path, type, buffer, size);

    luat_lfs2_ssize_t res = luat_lfs2_getattr_(lfs, path, type, buffer, size);

    LFS_TRACE("luat_lfs2_getattr -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

#ifndef LFS_READONLY
int luat_lfs2_setattr(luat_lfs2_t *lfs, const char *path,
        uint8_t type, const void *buffer, luat_lfs2_size_t size) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_setattr(%p, \"%s\", %"PRIu8", %p, %"PRIu32")",
            (void*)lfs, path, type, buffer, size);

    err = luat_lfs2_setattr_(lfs, path, type, buffer, size);

    LFS_TRACE("luat_lfs2_setattr -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifndef LFS_READONLY
int luat_lfs2_removeattr(luat_lfs2_t *lfs, const char *path, uint8_t type) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_removeattr(%p, \"%s\", %"PRIu8")", (void*)lfs, path, type);

    err = luat_lfs2_removeattr_(lfs, path, type);

    LFS_TRACE("luat_lfs2_removeattr -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifndef LFS_NO_MALLOC
int luat_lfs2_file_open(luat_lfs2_t *lfs, luat_lfs2_file_t *file, const char *path, int flags) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_open(%p, %p, \"%s\", %x)",
            (void*)lfs, (void*)file, path, flags);
    LFS_ASSERT(!luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    err = luat_lfs2_file_open_(lfs, file, path, flags);

    LFS_TRACE("luat_lfs2_file_open -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

int luat_lfs2_file_opencfg(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const char *path, int flags,
        const struct luat_lfs2_file_config *cfg) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_opencfg(%p, %p, \"%s\", %x, %p {"
                 ".buffer=%p, .attrs=%p, .attr_count=%"PRIu32"})",
            (void*)lfs, (void*)file, path, flags,
            (void*)cfg, cfg->buffer, (void*)cfg->attrs, cfg->attr_count);
    LFS_ASSERT(!luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    err = luat_lfs2_file_opencfg_(lfs, file, path, flags, cfg);

    LFS_TRACE("luat_lfs2_file_opencfg -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

int luat_lfs2_file_close(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_close(%p, %p)", (void*)lfs, (void*)file);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    err = luat_lfs2_file_close_(lfs, file);

    LFS_TRACE("luat_lfs2_file_close -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

#ifndef LFS_READONLY
int luat_lfs2_file_sync(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_sync(%p, %p)", (void*)lfs, (void*)file);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    err = luat_lfs2_file_sync_(lfs, file);

    LFS_TRACE("luat_lfs2_file_sync -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

luat_lfs2_ssize_t luat_lfs2_file_read(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        void *buffer, luat_lfs2_size_t size) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_read(%p, %p, %p, %"PRIu32")",
            (void*)lfs, (void*)file, buffer, size);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    luat_lfs2_ssize_t res = luat_lfs2_file_read_(lfs, file, buffer, size);

    LFS_TRACE("luat_lfs2_file_read -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

#ifndef LFS_READONLY
luat_lfs2_ssize_t luat_lfs2_file_write(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        const void *buffer, luat_lfs2_size_t size) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_write(%p, %p, %p, %"PRIu32")",
            (void*)lfs, (void*)file, buffer, size);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    luat_lfs2_ssize_t res = luat_lfs2_file_write_(lfs, file, buffer, size);

    LFS_TRACE("luat_lfs2_file_write -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}
#endif

luat_lfs2_soff_t luat_lfs2_file_seek(luat_lfs2_t *lfs, luat_lfs2_file_t *file,
        luat_lfs2_soff_t off, int whence) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_seek(%p, %p, %"PRId32", %d)",
            (void*)lfs, (void*)file, off, whence);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    luat_lfs2_soff_t res = luat_lfs2_file_seek_(lfs, file, off, whence);

    LFS_TRACE("luat_lfs2_file_seek -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

#ifndef LFS_READONLY
int luat_lfs2_file_truncate(luat_lfs2_t *lfs, luat_lfs2_file_t *file, luat_lfs2_off_t size) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_truncate(%p, %p, %"PRIu32")",
            (void*)lfs, (void*)file, size);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    err = luat_lfs2_file_truncate_(lfs, file, size);

    LFS_TRACE("luat_lfs2_file_truncate -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

luat_lfs2_soff_t luat_lfs2_file_tell(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_tell(%p, %p)", (void*)lfs, (void*)file);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    luat_lfs2_soff_t res = luat_lfs2_file_tell_(lfs, file);

    LFS_TRACE("luat_lfs2_file_tell -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

int luat_lfs2_file_rewind(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_rewind(%p, %p)", (void*)lfs, (void*)file);

    err = luat_lfs2_file_rewind_(lfs, file);

    LFS_TRACE("luat_lfs2_file_rewind -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

luat_lfs2_soff_t luat_lfs2_file_size(luat_lfs2_t *lfs, luat_lfs2_file_t *file) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_file_size(%p, %p)", (void*)lfs, (void*)file);
    LFS_ASSERT(luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)file));

    luat_lfs2_soff_t res = luat_lfs2_file_size_(lfs, file);

    LFS_TRACE("luat_lfs2_file_size -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

#ifndef LFS_READONLY
int luat_lfs2_mkdir(luat_lfs2_t *lfs, const char *path) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_mkdir(%p, \"%s\")", (void*)lfs, path);

    err = luat_lfs2_mkdir_(lfs, path);

    LFS_TRACE("luat_lfs2_mkdir -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

int luat_lfs2_dir_open(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, const char *path) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_open(%p, %p, \"%s\")", (void*)lfs, (void*)dir, path);
    LFS_ASSERT(!luat_lfs2_mlist_isopen(lfs->mlist, (struct luat_lfs2_mlist*)dir));

    err = luat_lfs2_dir_open_(lfs, dir, path);

    LFS_TRACE("luat_lfs2_dir_open -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

int luat_lfs2_dir_close(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_close(%p, %p)", (void*)lfs, (void*)dir);

    err = luat_lfs2_dir_close_(lfs, dir);

    LFS_TRACE("luat_lfs2_dir_close -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

int luat_lfs2_dir_read(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, struct luat_lfs2_info *info) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_read(%p, %p, %p)",
            (void*)lfs, (void*)dir, (void*)info);

    err = luat_lfs2_dir_read_(lfs, dir, info);

    LFS_TRACE("luat_lfs2_dir_read -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

int luat_lfs2_dir_seek(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir, luat_lfs2_off_t off) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_seek(%p, %p, %"PRIu32")",
            (void*)lfs, (void*)dir, off);

    err = luat_lfs2_dir_seek_(lfs, dir, off);

    LFS_TRACE("luat_lfs2_dir_seek -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

luat_lfs2_soff_t luat_lfs2_dir_tell(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_tell(%p, %p)", (void*)lfs, (void*)dir);

    luat_lfs2_soff_t res = luat_lfs2_dir_tell_(lfs, dir);

    LFS_TRACE("luat_lfs2_dir_tell -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

int luat_lfs2_dir_rewind(luat_lfs2_t *lfs, luat_lfs2_dir_t *dir) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_dir_rewind(%p, %p)", (void*)lfs, (void*)dir);

    err = luat_lfs2_dir_rewind_(lfs, dir);

    LFS_TRACE("luat_lfs2_dir_rewind -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

int luat_lfs2_fs_stat(luat_lfs2_t *lfs, struct luat_lfs2_fsinfo *fsinfo) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_stat(%p, %p)", (void*)lfs, (void*)fsinfo);

    err = luat_lfs2_fs_stat_(lfs, fsinfo);

    LFS_TRACE("luat_lfs2_fs_stat -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

luat_lfs2_ssize_t luat_lfs2_fs_size(luat_lfs2_t *lfs) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_size(%p)", (void*)lfs);

    luat_lfs2_ssize_t res = luat_lfs2_fs_size_(lfs);

    LFS_TRACE("luat_lfs2_fs_size -> %"PRId32, res);
    LFS_UNLOCK(lfs->cfg);
    return res;
}

int luat_lfs2_fs_traverse(luat_lfs2_t *lfs, int (*cb)(void *, luat_lfs2_block_t), void *data) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_traverse(%p, %p, %p)",
            (void*)lfs, (void*)(uintptr_t)cb, data);

    err = luat_lfs2_fs_traverse_(lfs, cb, data, true);

    LFS_TRACE("luat_lfs2_fs_traverse -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}

#ifndef LFS_READONLY
int luat_lfs2_fs_mkconsistent(luat_lfs2_t *lfs) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_mkconsistent(%p)", (void*)lfs);

    err = luat_lfs2_fs_mkconsistent_(lfs);

    LFS_TRACE("luat_lfs2_fs_mkconsistent -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifndef LFS_READONLY
int luat_lfs2_fs_gc(luat_lfs2_t *lfs) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_gc(%p)", (void*)lfs);

    err = luat_lfs2_fs_gc_(lfs);

    LFS_TRACE("luat_lfs2_fs_gc -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifndef LFS_READONLY
int luat_lfs2_fs_grow(luat_lfs2_t *lfs, luat_lfs2_size_t block_count) {
    int err = LFS_LOCK(lfs->cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_fs_grow(%p, %"PRIu32")", (void*)lfs, block_count);

    err = luat_lfs2_fs_grow_(lfs, block_count);

    LFS_TRACE("luat_lfs2_fs_grow -> %d", err);
    LFS_UNLOCK(lfs->cfg);
    return err;
}
#endif

#ifdef LFS_MIGRATE
int luat_lfs2_migrate(luat_lfs2_t *lfs, const struct luat_lfs2_config *cfg) {
    int err = LFS_LOCK(cfg);
    if (err) {
        return err;
    }
    LFS_TRACE("luat_lfs2_migrate(%p, %p {.context=%p, "
                ".read=%p, .prog=%p, .erase=%p, .sync=%p, "
                ".read_size=%"PRIu32", .prog_size=%"PRIu32", "
                ".block_size=%"PRIu32", .block_count=%"PRIu32", "
                ".block_cycles=%"PRIu32", .cache_size=%"PRIu32", "
                ".lookahead_size=%"PRIu32", .read_buffer=%p, "
                ".prog_buffer=%p, .lookahead_buffer=%p, "
                ".name_max=%"PRIu32", .file_max=%"PRIu32", "
                ".attr_max=%"PRIu32"})",
            (void*)lfs, (void*)cfg, cfg->context,
            (void*)(uintptr_t)cfg->read, (void*)(uintptr_t)cfg->prog,
            (void*)(uintptr_t)cfg->erase, (void*)(uintptr_t)cfg->sync,
            cfg->read_size, cfg->prog_size, cfg->block_size, cfg->block_count,
            cfg->block_cycles, cfg->cache_size, cfg->lookahead_size,
            cfg->read_buffer, cfg->prog_buffer, cfg->lookahead_buffer,
            cfg->name_max, cfg->file_max, cfg->attr_max);

    err = luat_lfs2_migrate_(lfs, cfg);

    LFS_TRACE("luat_lfs2_migrate -> %d", err);
    LFS_UNLOCK(cfg);
    return err;
}
#endif
