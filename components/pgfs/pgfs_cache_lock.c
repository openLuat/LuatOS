#include "luat_base.h"
#include "pgfs_internal.h"
#include "luat_mem.h"
#define LUAT_LOG_TAG "pgfs"
#include "luat_log.h"

static void pgfs_cache_free_buffer(pgfs_file_cache_t* cache) {
    if (cache == NULL || cache->data == NULL) {
        return;
    }
    if (cache->heap_type == (uint8_t)LUAT_HEAP_PSRAM) {
        luat_heap_opt_free(LUAT_HEAP_PSRAM, cache->data);
    }
    else {
        luat_heap_free(cache->data);
    }
    cache->data = NULL;
    cache->cap = 0;
    cache->len = 0;
    cache->heap_type = (uint8_t)LUAT_HEAP_SRAM;
}

int pgfs_lock(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    if (ctx->lock_mode == PGFS_LOCK_MODE_ON) {
        ctx->stats.lock_acquire_count++;
    }
    else {
        ctx->stats.lock_passthrough_count++;
    }
    return 0;
}

int pgfs_unlock(pgfs_mount_ctx_t* ctx) {
    if (ctx == NULL) {
        return -1;
    }
    return 0;
}

static int pgfs_cache_expand(pgfs_file_cache_t* cache, size_t need) {
    size_t target = 0;
    size_t min_target = 0;
    size_t candidates[3] = {0};
    size_t i = 0;
    size_t candidate_count = 0;
    uint8_t* ptr = NULL;
    uint8_t heap_type = (uint8_t)LUAT_HEAP_SRAM;
    if (cache == NULL) {
        return -1;
    }
    if (need <= cache->cap) {
        return 0;
    }
    target = cache->cap == 0 ? 256 : cache->cap;
    while (target < need) {
        size_t step = target < (64 * 1024) ? target : (64 * 1024);
        size_t next = 0;
        if (step < 4096) {
            step = 4096;
        }
        if (target > ((size_t)-1) - step) {
            return -1;
        }
        next = target + step;
        if (next <= target) {
            return -1;
        }
        target = next;
    }
    min_target = (need + 4095) & ~(size_t)4095;
    target = (target + 4095) & ~(size_t)4095;

    candidates[candidate_count++] = target;
    if (min_target != target) {
        candidates[candidate_count++] = min_target;
    }
    if (need != min_target && need != target) {
        candidates[candidate_count++] = need;
    }

    for (i = 0; i < candidate_count; i++) {
        ptr = (uint8_t*)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, candidates[i]);
        if (ptr != NULL) {
            heap_type = (uint8_t)LUAT_HEAP_PSRAM;
            target = candidates[i];
            break;
        }
        ptr = (uint8_t*)luat_heap_malloc(candidates[i]);
        if (ptr != NULL) {
            heap_type = (uint8_t)LUAT_HEAP_SRAM;
            target = candidates[i];
            break;
        }
    }
    if (ptr == NULL) {
        LLOGE("cache_expand malloc failed need=%u target=%u min_target=%u old_cap=%u", (unsigned int)need, (unsigned int)target, (unsigned int)min_target, (unsigned int)cache->cap);
        return -1;
    }
    if (cache->data != NULL && cache->len > 0) {
        memcpy(ptr, cache->data, cache->len);
    }
    pgfs_cache_free_buffer(cache);
    cache->data = ptr;
    cache->cap = target;
    cache->heap_type = heap_type;
    return 0;
}

int pgfs_cache_append(pgfs_file_t* f, const uint8_t* data, size_t len) {
    if (f == NULL || data == NULL || len == 0) {
        return -1;
    }
    if (pgfs_cache_expand(&f->cache, f->cache.len + len) != 0) {
        f->err = 1;
        return -1;
    }
    memcpy(f->cache.data + f->cache.len, data, len);
    f->cache.len += len;
    return 0;
}

int pgfs_cache_flush_to_log(pgfs_mount_ctx_t* ctx, pgfs_file_t* f) {
    (void)ctx;
    if (f == NULL) {
        return -1;
    }
    if (f->cache.len == 0) {
        return 0;
    }
    return 0;
}
