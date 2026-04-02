/*
 * luat_voip_jitterbuf.c - 最小抖动缓冲实现
 */

#include "luat_voip_jitterbuf.h"
#include "luat_mem.h"
#include <string.h>
#define LUAT_LOG_TAG "voip_jb"
#include "luat_log.h"

voip_jb_t *voip_jb_create(uint16_t depth, uint16_t max_pending, uint16_t frame_samples)
{
    if (frame_samples == 0) return NULL;
    if (depth == 0) depth = VOIP_JB_DEFAULT_DEPTH;
    if (max_pending == 0) max_pending = VOIP_JB_DEFAULT_MAX_PENDING;
    if (max_pending < depth) max_pending = depth * 2;

    voip_jb_t *jb = (voip_jb_t *)luat_heap_calloc(1, sizeof(voip_jb_t));
    if (!jb) return NULL;

    jb->slots = (voip_jb_slot_t *)luat_heap_calloc(max_pending, sizeof(voip_jb_slot_t));
    if (!jb->slots) {
        luat_heap_free(jb);
        return NULL;
    }

    /* 为每个 slot 预分配 PCM buffer */
    for (uint16_t i = 0; i < max_pending; i++) {
        jb->slots[i].pcm = (int16_t *)luat_heap_malloc(frame_samples * sizeof(int16_t));
        if (!jb->slots[i].pcm) {
            /* 回滚释放 */
            for (uint16_t j = 0; j < i; j++) {
                luat_heap_free(jb->slots[j].pcm);
            }
            luat_heap_free(jb->slots);
            luat_heap_free(jb);
            return NULL;
        }
        jb->slots[i].valid = 0;
    }

    jb->max_pending = max_pending;
    jb->depth = depth;
    jb->frame_samples = frame_samples;
    jb->pending = 0;
    jb->expected_seq = 0;
    jb->started = 0;
    jb->seq_valid = 0;
    jb->consecutive_miss = 0;

    return jb;
}

void voip_jb_destroy(voip_jb_t *jb)
{
    if (!jb) return;
    if (jb->slots) {
        for (uint16_t i = 0; i < jb->max_pending; i++) {
            if (jb->slots[i].pcm) {
                luat_heap_free(jb->slots[i].pcm);
            }
        }
        luat_heap_free(jb->slots);
    }
    luat_heap_free(jb);
}

void voip_jb_reset(voip_jb_t *jb)
{
    if (!jb) return;
    for (uint16_t i = 0; i < jb->max_pending; i++) {
        jb->slots[i].valid = 0;
    }
    jb->pending = 0;
    jb->expected_seq = 0;
    jb->started = 0;
    jb->seq_valid = 0;
    jb->consecutive_miss = 0;
}

/* 内部：按 seq 哈希到 slot index */
static inline uint16_t jb_slot_index(voip_jb_t *jb, uint16_t seq)
{
    return seq % jb->max_pending;
}

/* 内部：扫描 slots 找最小有效 seq，将 expected_seq 对齐过去 */
static void jb_resync(voip_jb_t *jb)
{
    uint16_t min_seq = 0;
    int found = 0;

    for (uint16_t i = 0; i < jb->max_pending; i++) {
        if (!jb->slots[i].valid) continue;
        if (!found) {
            min_seq = jb->slots[i].seq;
            found = 1;
        } else {
            /* 用有符号差值处理 uint16_t 回绕 */
            if ((int16_t)(jb->slots[i].seq - min_seq) < 0) {
                min_seq = jb->slots[i].seq;
            }
        }
    }

    if (found) {
        LLOGW("jb resync: expected_seq %u -> %u (pending %u)",
              jb->expected_seq, min_seq, jb->pending);
        jb->expected_seq = min_seq;
    }
    jb->consecutive_miss = 0;
}

int voip_jb_push(voip_jb_t *jb, uint16_t seq, const int16_t *pcm)
{
    if (!jb || !pcm) return -1;

    uint16_t idx = jb_slot_index(jb, seq);

    if (!jb->slots[idx].valid) {
        memcpy(jb->slots[idx].pcm, pcm, jb->frame_samples * sizeof(int16_t));
        jb->slots[idx].seq = seq;
        jb->slots[idx].valid = 1;
        jb->pending++;
    } else if (jb->slots[idx].seq == seq) {
        /* 重复包，忽略 */
        return 0;
    } else {
        /* 哈希冲突 — 覆盖旧帧 */
        memcpy(jb->slots[idx].pcm, pcm, jb->frame_samples * sizeof(int16_t));
        jb->slots[idx].seq = seq;
        jb->slots[idx].valid = 1;
        /* pending 不变（覆盖） */
    }

    if (!jb->seq_valid) {
        jb->expected_seq = seq;
        jb->seq_valid = 1;
    }

    if (jb->pending >= jb->depth) {
        jb->started = 1;
    }

    return 0;
}

int voip_jb_pop(voip_jb_t *jb, int16_t *out)
{
    if (!jb || !out) {
        LLOGE("voip_jb_pop: invalid arguments");
        return 0;
    }

    /* 尚未开始 => 静音 */
    if (!jb->seq_valid || !jb->started) {
        memset(out, 0, jb->frame_samples * sizeof(int16_t));
        return 0;
    }

    uint16_t idx = jb_slot_index(jb, jb->expected_seq);
    int got_frame = 0;

    if (jb->slots[idx].valid && jb->slots[idx].seq == jb->expected_seq) {
        memcpy(out, jb->slots[idx].pcm, jb->frame_samples * sizeof(int16_t));
        jb->slots[idx].valid = 0;
        if (jb->pending > 0) jb->pending--;
        got_frame = 1;
        jb->consecutive_miss = 0;
    } else {
        /* 缺帧 */
        jb->consecutive_miss++;

        /* 连续 miss 达到 depth 且缓冲区有帧 → resync expected_seq */
        if (jb->consecutive_miss >= jb->depth && jb->pending > 0) {
            jb_resync(jb);
            /* resync 后重试一次 */
            idx = jb_slot_index(jb, jb->expected_seq);
            if (jb->slots[idx].valid && jb->slots[idx].seq == jb->expected_seq) {
                memcpy(out, jb->slots[idx].pcm, jb->frame_samples * sizeof(int16_t));
                jb->slots[idx].valid = 0;
                if (jb->pending > 0) jb->pending--;
                got_frame = 1;
            }
        }

        if (!got_frame) {
            memset(out, 0, jb->frame_samples * sizeof(int16_t));
        }
    }

    jb->expected_seq = (jb->expected_seq + 1) & 0xFFFF;
    return got_frame;
}
