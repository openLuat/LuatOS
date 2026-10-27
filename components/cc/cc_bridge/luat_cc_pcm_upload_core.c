#include "luat_base.h"
#include "luat_cc_pcm_upload_core.h"

#ifdef LUAT_USE_CC_PCM_BRIDGE

#include <string.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

/* 适配器锁保护状态转换和槽位内容。计数器还须
 * 使用仓库要求的跨线程原子操作。
 */
static uint32_t luat_cc_pcm_upload_counter_inc(uint32_t *counter)
{
#if defined(_MSC_VER)
    return (uint32_t)_InterlockedIncrement((volatile long *)counter);
#else
    return __sync_add_and_fetch(counter, 1U);
#endif
}

static uint32_t luat_cc_pcm_upload_counter_dec(uint32_t *counter)
{
#if defined(_MSC_VER)
    return (uint32_t)_InterlockedDecrement((volatile long *)counter);
#else
    return __sync_sub_and_fetch(counter, 1U);
#endif
}

static void luat_cc_pcm_upload_release(luat_cc_pcm_upload_core_t *core, uint32_t index)
{
    core->slots[index].state = LUAT_CC_PCM_UPLOAD_SLOT_FREE;
    luat_cc_pcm_upload_counter_dec(&core->stats.pending);
    if (!core->stats.pending) {
        core->stats.stop_waiting = 0;
    }
}

void luat_cc_pcm_upload_core_init(luat_cc_pcm_upload_core_t *core)
{
    memset(core, 0, sizeof(*core));
}

static void luat_cc_pcm_upload_activate(luat_cc_pcm_upload_core_t *core, uint8_t codec)
{
    if (!luat_cc_pcm_upload_counter_inc(&core->stats.epoch)) {
        luat_cc_pcm_upload_counter_inc(&core->stats.epoch);
    }
    core->stats.codec = codec;
    core->stats.active = 1;
    core->stats.stop_waiting = 0;
    core->stats.start_waiting = 0;
}

int luat_cc_pcm_upload_core_start(luat_cc_pcm_upload_core_t *core, uint8_t codec, uint32_t now_ms)
{
    luat_cc_pcm_upload_core_poll(core, now_ms);
    if (codec > LUAT_CC_PCM_UPLOAD_CODEC_WB) {
        luat_cc_pcm_upload_core_stop(core, now_ms);
        if (!core->stats.fault) {
            core->stats.fault = LUAT_CC_PCM_UPLOAD_FAULT_BAD_CODEC;
        }
        return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    }
    if (core->stats.fault) {
        return LUAT_CC_PCM_UPLOAD_FAULT;
    }
    if (core->stats.active && core->stats.codec == codec) {
        return LUAT_CC_PCM_UPLOAD_OK;
    }
    if (core->stats.active) {
        luat_cc_pcm_upload_core_stop(core, now_ms);
    }
    if (core->stats.pending) {
        /* 保留原停止截止时间。后续录音启动通知
         * 可以替换请求的 codec，但不能推迟已阻塞的排空期限。 */
        core->stats.next_codec = codec;
        core->stats.start_waiting = 1;
        return LUAT_CC_PCM_UPLOAD_DEFERRED;
    }
    luat_cc_pcm_upload_activate(core, codec);
    return LUAT_CC_PCM_UPLOAD_OK;
}

void luat_cc_pcm_upload_core_stop(luat_cc_pcm_upload_core_t *core, uint32_t now_ms)
{
    core->stats.start_waiting = 0;
    if (!core->stats.active) {
        return;
    }
    core->stats.active = 0;
    core->stats.stop_started_ms = now_ms;
    core->stats.stop_waiting = core->stats.pending != 0;
}

int luat_cc_pcm_upload_core_reserve(luat_cc_pcm_upload_core_t *core, const void *data,
                               uint32_t length, uint32_t epoch, uint32_t *out_index)
{
    uint32_t index;
    uint32_t frame_bytes;
    luat_cc_pcm_upload_slot_t *slot;

    if (!data || !out_index) {
        return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    }
    if (core->stats.fault) {
        return LUAT_CC_PCM_UPLOAD_FAULT;
    }
    if (!core->stats.active) {
        return LUAT_CC_PCM_UPLOAD_INACTIVE;
    }
    if (epoch != core->stats.epoch) {
        luat_cc_pcm_upload_counter_inc(&core->stats.stale_epoch);
        return LUAT_CC_PCM_UPLOAD_STALE_EPOCH;
    }
    frame_bytes = core->stats.codec == LUAT_CC_PCM_UPLOAD_CODEC_WB ? 640U : 320U;
    if (length != frame_bytes) {
        luat_cc_pcm_upload_counter_inc(&core->stats.bad_length);
        return LUAT_CC_PCM_UPLOAD_BAD_LENGTH;
    }
    for (index = 0; index < LUAT_CC_PCM_UPLOAD_SLOT_COUNT; index++) {
        slot = &core->slots[index];
        if (slot->state == LUAT_CC_PCM_UPLOAD_SLOT_FREE) {
            memcpy(slot->pcm_words, data, length);
            slot->state = LUAT_CC_PCM_UPLOAD_SLOT_RESERVED;
            luat_cc_pcm_upload_counter_inc(&core->stats.pending);
            if (core->stats.pending > core->stats.high_water) {
                core->stats.high_water = core->stats.pending;
            }
            *out_index = index;
            return LUAT_CC_PCM_UPLOAD_OK;
        }
    }
    luat_cc_pcm_upload_counter_inc(&core->stats.no_slot);
    return LUAT_CC_PCM_UPLOAD_NO_SLOT;
}

int luat_cc_pcm_upload_core_submitted(luat_cc_pcm_upload_core_t *core, uint32_t index)
{
    if (index >= LUAT_CC_PCM_UPLOAD_SLOT_COUNT) {
        return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    }
    if (core->slots[index].state != LUAT_CC_PCM_UPLOAD_SLOT_RESERVED) {
        luat_cc_pcm_upload_counter_inc(&core->stats.bad_state);
        return LUAT_CC_PCM_UPLOAD_BAD_STATE;
    }
    /* 适配器将完整的预留/准备/提交流程与 stop 串行化。 */
    if (core->stats.fault) {
        return LUAT_CC_PCM_UPLOAD_FAULT;
    }
    if (!core->stats.active) {
        return LUAT_CC_PCM_UPLOAD_INACTIVE;
    }
    core->slots[index].state = LUAT_CC_PCM_UPLOAD_SLOT_SUBMITTED;
    luat_cc_pcm_upload_counter_inc(&core->stats.submitted);
    return LUAT_CC_PCM_UPLOAD_OK;
}

int luat_cc_pcm_upload_core_cancel(luat_cc_pcm_upload_core_t *core, uint32_t index)
{
    if (index >= LUAT_CC_PCM_UPLOAD_SLOT_COUNT) {
        return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    }
    if (core->slots[index].state != LUAT_CC_PCM_UPLOAD_SLOT_RESERVED) {
        luat_cc_pcm_upload_counter_inc(&core->stats.bad_state);
        return LUAT_CC_PCM_UPLOAD_BAD_STATE;
    }
    luat_cc_pcm_upload_counter_inc(&core->stats.alloc_failed);
    luat_cc_pcm_upload_release(core, index);
    return LUAT_CC_PCM_UPLOAD_OK;
}

int luat_cc_pcm_upload_core_complete(luat_cc_pcm_upload_core_t *core, uint32_t index)
{
    if (index >= LUAT_CC_PCM_UPLOAD_SLOT_COUNT) {
        return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    }
    if (core->slots[index].state != LUAT_CC_PCM_UPLOAD_SLOT_SUBMITTED) {
        luat_cc_pcm_upload_counter_inc(&core->stats.bad_state);
        return LUAT_CC_PCM_UPLOAD_BAD_STATE;
    }
    luat_cc_pcm_upload_counter_inc(&core->stats.completed);
    if (!core->stats.active) {
        luat_cc_pcm_upload_counter_inc(&core->stats.late);
    }
    luat_cc_pcm_upload_release(core, index);
    return LUAT_CC_PCM_UPLOAD_OK;
}

void luat_cc_pcm_upload_core_poll(luat_cc_pcm_upload_core_t *core, uint32_t now_ms)
{
    if (core->stats.stop_waiting && core->stats.pending &&
        (uint32_t)(now_ms - core->stats.stop_started_ms) >= LUAT_CC_PCM_UPLOAD_STOP_TIMEOUT_MS) {
        if (!core->stats.stop_timeout) {
            luat_cc_pcm_upload_counter_inc(&core->stats.stop_timeout);
        }
        if (!core->stats.fault) {
            core->stats.fault = LUAT_CC_PCM_UPLOAD_FAULT_STOP_TIMEOUT;
        }
        core->stats.start_waiting = 0;
    }
    if (!core->stats.fault && core->stats.start_waiting && !core->stats.pending) {
        luat_cc_pcm_upload_activate(core, (uint8_t)core->stats.next_codec);
    }
}

#endif /* LUAT_USE_CC_PCM_BRIDGE */
