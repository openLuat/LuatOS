#include "luat_base.h"
#include "pgfs_internal.h"

#ifdef LUAT_USE_PGFS_COMPONENT

int pgfs_alloc_segment(pgfs_mount_ctx_t* ctx, uint32_t* seg_id) {
    if (ctx == NULL || seg_id == NULL) {
        return -1;
    }
    if (ctx->gc_next_seg_id == 0) {
        ctx->gc_next_seg_id = 1;
    }
    *seg_id = ctx->gc_next_seg_id++;
    return 0;
}

int pgfs_gc_step(pgfs_mount_ctx_t* ctx, uint32_t byte_budget, uint32_t time_budget_us) {
    uint32_t reclaimed = 0;
    (void)time_budget_us;
    if (ctx == NULL || byte_budget == 0) {
        return 0;
    }
    reclaimed = ctx->checkpoint.gc_dead_bytes > byte_budget ? byte_budget : ctx->checkpoint.gc_dead_bytes;
    ctx->checkpoint.gc_dead_bytes -= reclaimed;
    return (int)reclaimed;
}

int pgfs_mark_block_retired(pgfs_mount_ctx_t* ctx, uint32_t block_id) {
    (void)block_id;
    if (ctx == NULL) {
        return -1;
    }
    ctx->checkpoint.flags |= 0x01u;
    return 0;
}

#endif
