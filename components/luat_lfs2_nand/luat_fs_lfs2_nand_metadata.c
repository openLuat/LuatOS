#include "luat_fs_lfs2_nand_metadata.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include "luat_mcu.h"

#define LUAT_LFS2_NAND_SPACE_META_MAGIC 0x4C324E44u
#define LUAT_LFS2_NAND_SPACE_META_VERSION 1u
#define LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY 4u
#define LUAT_LFS2_NAND_SPACE_META_SLOW_US 5000u

static void luat_lfs2_nand_space_meta_log(const luat_lfs2_nand_space_meta_ops_t* ops, const char* message);

static uint64_t luat_lfs2_nand_space_meta_now_us(void) {
    uint64_t tick = luat_mcu_tick64();
    uint32_t tick_per_us = luat_mcu_us_period();
    if (tick_per_us == 0) {
        tick_per_us = 1;
    }
    return tick / tick_per_us;
}

static void luat_lfs2_nand_space_meta_log_timing(const luat_lfs2_nand_space_meta_ops_t* ops, const char* stage, uint32_t attempt, uint64_t cost_us) {
    char msg[128];
    if (cost_us < LUAT_LFS2_NAND_SPACE_META_SLOW_US) {
        return;
    }
    snprintf(msg, sizeof(msg), "space metadata %s attempt=%u cost=%llu us", stage, (unsigned int)attempt, (unsigned long long)cost_us);
    luat_lfs2_nand_space_meta_log(ops, msg);
}

static uint32_t luat_lfs2_nand_space_meta_crc32(const void* data, size_t len) {
    uint32_t crc = 0xFFFFFFFFu;
    const unsigned char* ptr = (const unsigned char*)data;
    size_t i = 0;
    while (i < len) {
        uint32_t byte = ptr[i++];
        uint32_t bit = 0;
        crc ^= byte;
        while (bit++ < 8u) {
            uint32_t mask = 0u - (crc & 1u);
            crc = (crc >> 1) ^ (0xEDB88320u & mask);
        }
    }
    return ~crc;
}

static uint32_t luat_lfs2_nand_space_meta_crc(const luat_lfs2_nand_space_meta_t* meta) {
    luat_lfs2_nand_space_meta_t copy = *meta;
    copy.crc = 0;
    return luat_lfs2_nand_space_meta_crc32(&copy, sizeof(copy));
}

static int luat_lfs2_nand_space_meta_seq_is_newer(uint32_t lhs, uint32_t rhs) {
    return ((int32_t)(lhs - rhs)) > 0;
}

void luat_lfs2_nand_space_meta_init(luat_lfs2_nand_space_meta_t* meta, uint32_t seq, uint32_t used, uint32_t total) {
    if (!meta) {
        return;
    }
    memset(meta, 0, sizeof(*meta));
    meta->magic = LUAT_LFS2_NAND_SPACE_META_MAGIC;
    meta->version = LUAT_LFS2_NAND_SPACE_META_VERSION;
    meta->seq = seq;
    meta->used = used;
    meta->total = total;
    meta->free = (used <= total) ? (total - used) : 0;
    meta->crc = luat_lfs2_nand_space_meta_crc(meta);
}

int luat_lfs2_nand_space_meta_validate(const luat_lfs2_nand_space_meta_t* meta) {
    if (!meta) {
        return -1;
    }
    if (meta->magic != LUAT_LFS2_NAND_SPACE_META_MAGIC || meta->version != LUAT_LFS2_NAND_SPACE_META_VERSION) {
        return -1;
    }
    if (meta->total == 0 || meta->used > meta->total || meta->free > meta->total) {
        return -1;
    }
    if ((meta->used + meta->free) != meta->total) {
        return -1;
    }
    return (luat_lfs2_nand_space_meta_crc(meta) == meta->crc) ? 0 : -1;
}

int luat_lfs2_nand_space_meta_select_latest(const luat_lfs2_nand_space_meta_t* slots, uint32_t slot_count, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    uint32_t i = 0;
    uint32_t best_slot = 0;
    int found = 0;
    luat_lfs2_nand_space_meta_t best = {0};

    if (!slots || slot_count == 0 || !out) {
        return -1;
    }
    while (i < slot_count) {
        if (luat_lfs2_nand_space_meta_validate(&slots[i]) == 0) {
            if (!found || luat_lfs2_nand_space_meta_seq_is_newer(slots[i].seq, best.seq)) {
                best = slots[i];
                best_slot = i;
                found = 1;
            }
        }
        i++;
    }
    if (!found) {
        return -1;
    }
    *out = best;
    if (out_slot) {
        *out_slot = best_slot;
    }
    return 0;
}

static void luat_lfs2_nand_space_meta_log(const luat_lfs2_nand_space_meta_ops_t* ops, const char* message) {
    if (ops && ops->log) {
        ops->log(ops->ctx, message);
    }
}

static int luat_lfs2_nand_space_meta_load(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    luat_lfs2_nand_space_meta_t slots[LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT];
    uint32_t i = 0;

    if (!ops || !ops->read_slot || !out) {
        return -1;
    }
    memset(slots, 0, sizeof(slots));
    while (i < LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT) {
        if (ops->read_slot(ops->ctx, i, &slots[i]) != 0) {
            memset(&slots[i], 0, sizeof(slots[i]));
        }
        i++;
    }
    return luat_lfs2_nand_space_meta_select_latest(slots, LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT, out, out_slot);
}

int luat_lfs2_nand_space_meta_refresh(const luat_lfs2_nand_space_meta_ops_t* ops, const luat_lfs2_nand_space_meta_t* previous, uint32_t previous_slot, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot) {
    luat_lfs2_nand_space_meta_t current = {0};
    uint32_t current_slot = 0;
    uint32_t used = 0;
    uint32_t total = 0;
    uint32_t seq = 0;
    uint32_t target_slot = 0;
    uint32_t attempt = 0;

    if (!ops || !ops->scan || !ops->write_slot || !out) {
        return -1;
    }
    if (!previous || luat_lfs2_nand_space_meta_validate(previous) != 0) {
        if (luat_lfs2_nand_space_meta_load(ops, &current, &current_slot) == 0) {
            previous = &current;
            previous_slot = current_slot;
        }
    }
    if (previous && luat_lfs2_nand_space_meta_validate(previous) == 0) {
        seq = previous->seq + 1u;
        target_slot = (previous_slot + 1u) % LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT;
    }

    while (attempt < LUAT_LFS2_NAND_SPACE_META_REFRESH_RETRY) {
        uint64_t t0 = luat_lfs2_nand_space_meta_now_us();
        if (ops->scan(ops->ctx, &used, &total) != 0) {
            luat_lfs2_nand_space_meta_log(ops, "space metadata scan failed");
            return -1;
        }
        luat_lfs2_nand_space_meta_log_timing(ops, "scan", attempt, luat_lfs2_nand_space_meta_now_us() - t0);
        luat_lfs2_nand_space_meta_init(out, seq, used, total);
        t0 = luat_lfs2_nand_space_meta_now_us();
        if (ops->write_slot(ops->ctx, target_slot, out) != 0) {
            luat_lfs2_nand_space_meta_log(ops, "space metadata write failed");
            return -1;
        }
        luat_lfs2_nand_space_meta_log_timing(ops, "write", attempt, luat_lfs2_nand_space_meta_now_us() - t0);
        t0 = luat_lfs2_nand_space_meta_now_us();
        if (ops->scan(ops->ctx, &used, &total) != 0) {
            luat_lfs2_nand_space_meta_log(ops, "space metadata verify scan failed");
            return -1;
        }
        luat_lfs2_nand_space_meta_log_timing(ops, "verify_scan", attempt, luat_lfs2_nand_space_meta_now_us() - t0);
        if (used == out->used && total == out->total) {
            if (out_slot) {
                *out_slot = target_slot;
            }
            return 0;
        }
        seq++;
        target_slot = (target_slot + 1u) % LUAT_LFS2_NAND_SPACE_META_SLOT_COUNT;
        attempt++;
    }

    luat_lfs2_nand_space_meta_log(ops, "space metadata did not stabilize");
    return -1;
}

int luat_lfs2_nand_space_meta_load_or_rebuild(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint32_t* out_slot, uint8_t* rebuilt) {
    if (luat_lfs2_nand_space_meta_load(ops, out, out_slot) == 0) {
        if (rebuilt) {
            *rebuilt = 0;
        }
        return 0;
    }
    luat_lfs2_nand_space_meta_log(ops, "space metadata invalid, rebuilding");
    if (luat_lfs2_nand_space_meta_refresh(ops, NULL, 0, out, out_slot) != 0) {
        return -1;
    }
    if (rebuilt) {
        *rebuilt = 1;
    }
    return 0;
}

int luat_lfs2_nand_space_meta_load_prefer_fast(const luat_lfs2_nand_space_meta_ops_t* ops, luat_lfs2_nand_space_meta_t* out, uint8_t* rebuilt, uint8_t* persisted) {
    if (persisted) {
        *persisted = 0;
    }
    if (luat_lfs2_nand_space_meta_load_or_rebuild(ops, out, NULL, rebuilt) == 0) {
        if (persisted) {
            *persisted = 1;
        }
        return 0;
    }
    if (!ops || !ops->scan || !out) {
        return -1;
    }
    luat_lfs2_nand_space_meta_log(ops, "space metadata rebuild persistence failed, using scan result");
    if (ops->scan(ops->ctx, &out->used, &out->total) != 0) {
        return -1;
    }
    luat_lfs2_nand_space_meta_init(out, 0, out->used, out->total);
    if (rebuilt) {
        *rebuilt = 1;
    }
    return 0;
}
