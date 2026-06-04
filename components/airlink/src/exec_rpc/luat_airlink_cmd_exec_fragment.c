/*
 * AirLink Fragment Reassembly Handler (cmd 0x32)
 *
 * Wire format (cmd 0x32 data):
 *   [original_cmd : 2B]  original cmd id (e.g. 0x30 for RPC)
 *   [reassembly_id: 2B]  unique reassembly session id
 *   [total_len    : 2B]  total data length of original cmd->data
 *   [frag_index   : 1B]  0-based fragment index
 *   [frag_total   : 1B]  total number of fragments
 *   [chunk        : NB]  payload slice
 *
 * Fragment positions are computed from frag_index, not arrival order:
 *   non-last: offset = frag_index * chunk_max
 *   last:     offset = total_len - chunk_len
 *
 * Dedup via bitmap; complete only when all bits set AND received_bytes == total_len.
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "airlink.frag"
#include "luat_log.h"

#define FRAG_HDR_LEN      8
#define FRAG_POOL_SIZE    4
#define FRAG_TIMEOUT_MS   2000
#define FRAG_MAP_SIZE     32   // 256 bits max, 255 fragments

typedef struct {
    uint16_t  reassembly_id;
    uint16_t  original_cmd;
    uint16_t  total_len;
    uint8_t   frag_total;
    uint8_t   received_count;
    uint16_t  received_bytes;
    uint16_t  chunk_max;         // learned from first non-last fragment
    uint8_t   received_map[FRAG_MAP_SIZE]; // bitmap per frag_index
    uint8_t*  buffer;            // allocated: luat_airlink_cmd_t + total_len
    uint64_t  last_tick;
    uint8_t   active;
} frag_ctx_t;

static frag_ctx_t g_frag_pool[FRAG_POOL_SIZE];
static uint8_t g_frag_pool_hwm = 0;  // 分片池高水位 (最大并发会话数)

static uint8_t frag_pool_active_count(void) {
    uint8_t n = 0;
    for (int i = 0; i < FRAG_POOL_SIZE; i++) {
        if (g_frag_pool[i].active) n++;
    }
    return n;
}

extern void luat_airlink_on_data_recv(uint8_t *data, size_t len);

static int map_test(const uint8_t* map, uint8_t idx) {
    return (map[idx / 8] >> (idx % 8)) & 1;
}

static void map_set(uint8_t* map, uint8_t idx) {
    map[idx / 8] |= (uint8_t)(1 << (idx % 8));
}

int luat_airlink_cmd_exec_fragment(luat_airlink_cmd_t* cmd, void* userdata) {
    (void)userdata;

    if (cmd->len < FRAG_HDR_LEN) {
        LLOGE("frag: cmd too short %d (min %d)", cmd->len, FRAG_HDR_LEN);
        return -1;
    }

    uint16_t original_cmd  = 0;
    uint16_t reassembly_id = 0;
    uint16_t total_len     = 0;
    uint8_t  frag_index    = 0;
    uint8_t  frag_total    = 0;

    memcpy(&original_cmd,  cmd->data,      2);
    memcpy(&reassembly_id, cmd->data + 2,  2);
    memcpy(&total_len,     cmd->data + 4,  2);
    frag_index = cmd->data[6];
    frag_total = cmd->data[7];

    if (frag_index >= frag_total || frag_total == 0
        || frag_total > FRAG_MAP_SIZE * 8) {
        LLOGE("frag: invalid idx=%d total=%d", frag_index, frag_total);
        return -1;
    }

    uint16_t chunk_len = cmd->len - FRAG_HDR_LEN;

    // ---- Lazy timeout cleanup ----
    uint64_t tnow = luat_mcu_tick64_ms();
    for (int i = 0; i < FRAG_POOL_SIZE; i++) {
        if (!g_frag_pool[i].active) continue;
        if (tnow - g_frag_pool[i].last_tick <= FRAG_TIMEOUT_MS) continue;

        LLOGI("frag: timeout cleanup id=0x%04X slot=%d total=%d bytes=%u (frag session expired)",
              g_frag_pool[i].reassembly_id, i, g_frag_pool[i].frag_total, g_frag_pool[i].total_len);
        if (g_frag_pool[i].buffer) {
            luat_heap_opt_free(AIRLINK_MEM_TYPE, g_frag_pool[i].buffer);
        }
        memset(&g_frag_pool[i], 0, sizeof(frag_ctx_t));
    }

    // ---- Find or create reassembly context ----
    frag_ctx_t* ctx = NULL;
    int free_slot   = -1;

    for (int i = 0; i < FRAG_POOL_SIZE; i++) {
        if (g_frag_pool[i].active && g_frag_pool[i].reassembly_id == reassembly_id) {
            ctx = &g_frag_pool[i];
            break;
        }
        if (!g_frag_pool[i].active && free_slot < 0) {
            free_slot = i;
        }
    }

    if (ctx == NULL) {
        if (free_slot < 0) {
            LLOGE("frag: all %d slots busy (hwm=%u), drop id=0x%04X",
                  FRAG_POOL_SIZE, g_frag_pool_hwm, reassembly_id);
            return -2;
        }
        if (total_len == 0 || total_len > 0xFFF0) {
            LLOGE("frag: invalid total_len=%u", total_len);
            return -1;
        }
        if (frag_total > 255) {
            LLOGE("frag: frag_total too large %d", frag_total);
            return -1;
        }

        ctx = &g_frag_pool[free_slot];
        memset(ctx, 0, sizeof(frag_ctx_t));

        size_t alloc_size = sizeof(luat_airlink_cmd_t) + total_len;
        ctx->buffer = (uint8_t*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, alloc_size);
        if (ctx->buffer == NULL) {
            LLOGE("frag: OOM allocating %d bytes", (int)alloc_size);
            return -2;
        }
        memset(ctx->buffer, 0, alloc_size);

        ctx->reassembly_id = reassembly_id;
        ctx->original_cmd  = original_cmd;
        ctx->total_len     = total_len;
        ctx->frag_total    = frag_total;
        ctx->chunk_max     = 0;  // learned from first non-last fragment
        ctx->active        = 1;
        {
            uint8_t active = frag_pool_active_count();
            if (active > g_frag_pool_hwm) {
                g_frag_pool_hwm = active;
                LLOGI("frag: pool hwm updated to %u/%u", active, (unsigned)FRAG_POOL_SIZE);
            }
        }
    }

    ctx->last_tick = tnow;

    // ---- Consistency check ----
    if (ctx->original_cmd != original_cmd || ctx->frag_total != frag_total
        || ctx->total_len != total_len) {
        LLOGE("frag: mismatch id=0x%04X (exp cmd=%04X total=%d/%d, got cmd=%04X total=%d/%d)",
              reassembly_id, ctx->original_cmd, ctx->frag_total, ctx->total_len,
              original_cmd, frag_total, total_len);
        if (ctx->buffer) {
            luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx->buffer);
        }
        memset(ctx, 0, sizeof(frag_ctx_t));
        return -1;
    }

    // ---- Dedup via bitmap ----
    if (map_test(ctx->received_map, frag_index)) {
        LLOGD("frag: duplicate idx=%d id=0x%04X, ignoring", frag_index, reassembly_id);
        return 0;
    }

    // ---- Compute write offset from frag_index ----
    uint32_t offset;
    uint8_t is_last = (frag_index == frag_total - 1);

    if (is_last) {
        // Last fragment: validate chunk_len before subtraction to prevent underflow
        if (chunk_len > total_len) {
            LLOGE("frag: last chunk too large id=0x%04X idx=%d chunk=%d > total=%d",
                  reassembly_id, frag_index, chunk_len, total_len);
            if (ctx->buffer) {
                luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx->buffer);
            }
            memset(ctx, 0, sizeof(frag_ctx_t));
            return -1;
        }
        offset = total_len - chunk_len;
    } else {
        // Non-last: learn chunk_max from first one received.
        // Protocol invariant: all non-last fragments MUST have equal length.
        // Relies on sender using fixed chunk_max = max_data - FRAG_HDR_LEN.
        if (ctx->chunk_max == 0) {
            ctx->chunk_max = chunk_len;
        } else if (chunk_len != ctx->chunk_max) {
            LLOGE("frag: non-last chunk mismatch id=0x%04X idx=%d len=%d (exp %d)",
                  reassembly_id, frag_index, chunk_len, ctx->chunk_max);
            if (ctx->buffer) {
                luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx->buffer);
            }
            memset(ctx, 0, sizeof(frag_ctx_t));
            return -1;
        }
        offset = (uint32_t)frag_index * ctx->chunk_max;
    }

    // ---- Validate offset ----
    if (offset + chunk_len > total_len) {
        LLOGE("frag: overflow id=0x%04X idx=%d offset=%d + chunk=%d > total=%d",
              reassembly_id, frag_index, (int)offset, chunk_len, total_len);
        if (ctx->buffer) {
            luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx->buffer);
        }
        memset(ctx, 0, sizeof(frag_ctx_t));
        return -1;
    }

    // ---- Copy chunk ----
    luat_airlink_cmd_t* assembled = (luat_airlink_cmd_t*)ctx->buffer;
    assembled->cmd = original_cmd;
    assembled->len = total_len;
    memcpy(assembled->data + offset, cmd->data + FRAG_HDR_LEN, chunk_len);
    map_set(ctx->received_map, frag_index);
    ctx->received_count++;
    ctx->received_bytes += chunk_len;

    LLOGD("frag: id=0x%04X idx=%d/%d chunk=%d offset=%d rcvd=%d/%d bytes=%d/%d",
          reassembly_id, frag_index, frag_total, chunk_len, (int)offset,
          ctx->received_count, ctx->frag_total, ctx->received_bytes, ctx->total_len);

    // ---- Dispatch when complete: all bits set AND bytes match ----
    if (ctx->received_count == ctx->frag_total && ctx->received_bytes == total_len) {
        uint8_t* buf = ctx->buffer;
        size_t full_len = sizeof(luat_airlink_cmd_t) + total_len;

        ctx->buffer = NULL;
        ctx->active = 0;

        LLOGD("frag: complete id=0x%04X cmd=0x%04X len=%d",
              reassembly_id, original_cmd, total_len);

        luat_airlink_on_data_recv(buf, full_len);
        luat_heap_opt_free(AIRLINK_MEM_TYPE, buf);
    }

    return 0;
}
