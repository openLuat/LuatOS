#include "luat_base.h"
#include "pgfs_internal.h"
#include "luat_mem.h"

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
    uint8_t* ptr = NULL;
    if (cache == NULL) {
        return -1;
    }
    if (need <= cache->cap) {
        return 0;
    }
    target = cache->cap == 0 ? 256 : cache->cap;
    while (target < need) {
        size_t next = target << 1;
        if (next <= target) {
            return -1;
        }
        target = next;
    }
    ptr = (uint8_t*)luat_heap_realloc(cache->data, target);
    if (ptr == NULL) {
        return -1;
    }
    cache->data = ptr;
    cache->cap = target;
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
