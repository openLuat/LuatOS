#include "luat_base.h"
#ifdef LUAT_USE_CC_PCM_BRIDGE
#include "luat_cc_pcm_upload.h"
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "common_api.h"
#include "system_ec7xx.h"
#include "pspdu.h"
#include "hal_voice_eng.h"
#include "hal_voice_eng_mem.h"

/* 由 SoC 管理的纯 PCM 上传后端。
 * 提交/启动/停止使用任务互斥锁；完成处理只使用 IRQ 临界区保护。
 * GNU ld 包装函数为普通 CC 操作保留原 SDK 回调。
 */
static __USER_BSS_IN_OPT_RAM__ luat_cc_pcm_upload_core_t s_pcm_core;
static __USER_BSS_IN_OPT_RAM__ UlPduBlock s_pcm_tokens[LUAT_CC_PCM_UPLOAD_SLOT_COUNT];
static SemaphoreHandle_t s_pcm_submit_mutex;
static uint8_t s_pcm_enabled;

static uint32_t pcm_now_ms(void)
{
    return (uint32_t)xTaskGetTickCount() * portTICK_PERIOD_MS;
}

int luat_cc_pcm_upload_enable(void)
{
    uint32_t mask;
    SemaphoreHandle_t gate;
    /* CC 初始化的所有者负责串行化这次仅在上电时进行的选择。
     * 后续调用始终使用同一个池、互斥锁和 epoch 状态。 */
    if (s_pcm_enabled) return LUAT_CC_PCM_UPLOAD_OK;
    gate = xSemaphoreCreateMutex();
    if (!gate) return LUAT_CC_PCM_UPLOAD_BAD_STATE;
    mask = SaveAndSetIRQMask();
    luat_cc_pcm_upload_core_init(&s_pcm_core);
    s_pcm_submit_mutex = gate;
    s_pcm_enabled = 1;
    RestoreIRQMask(mask);
    return LUAT_CC_PCM_UPLOAD_OK;
}

static void pcm_record_start(uint8_t codec)
{
    uint32_t mask;
    xSemaphoreTake(s_pcm_submit_mutex, portMAX_DELAY);
    mask = SaveAndSetIRQMask();
    luat_cc_pcm_upload_core_start(&s_pcm_core, codec, pcm_now_ms());
    RestoreIRQMask(mask);
    xSemaphoreGive(s_pcm_submit_mutex);
}

void luat_cc_pcm_upload_stop(void)
{
    uint32_t mask;
    if (!s_pcm_enabled) return;
    /* stop 返回后，新的 IPC 提交不能再通过此处。不要在这里等待媒体
     * 完成：stop 本身也可能在媒体任务中执行。 */
    xSemaphoreTake(s_pcm_submit_mutex, portMAX_DELAY);
    mask = SaveAndSetIRQMask();
    luat_cc_pcm_upload_core_stop(&s_pcm_core, pcm_now_ms());
    RestoreIRQMask(mask);
    xSemaphoreGive(s_pcm_submit_mutex);
}

static int pcm_record_complete(void *token)
{
    uint32_t i, mask;
    if (!s_pcm_submit_mutex) return 0;
    for (i = 0; i < LUAT_CC_PCM_UPLOAD_SLOT_COUNT; i++) {
        if (token == &s_pcm_tokens[i]) {
            mask = SaveAndSetIRQMask();
            /* 释放最后一个槽位前先检查截止时间，避免逾期完成
             * 掩盖超时并启动新的 epoch。 */
            luat_cc_pcm_upload_core_poll(&s_pcm_core, pcm_now_ms());
            /* 不得在 PLAY_STOP 时清空或复用这些 token。 */
            s_pcm_tokens[i].ptr = NULL;
            luat_cc_pcm_upload_core_complete(&s_pcm_core, i);
            luat_cc_pcm_upload_core_poll(&s_pcm_core, pcm_now_ms());
            RestoreIRQMask(mask);
            return 1;
        }
    }
    return 0;
}

int luat_cc_pcm_upload_get_stats(luat_cc_pcm_upload_stats_t *stats)
{
    uint32_t mask;
    if (!stats) return LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT;
    mask = SaveAndSetIRQMask();
    if (!s_pcm_enabled) {
        RestoreIRQMask(mask);
        return LUAT_CC_PCM_UPLOAD_INACTIVE;
    }
    luat_cc_pcm_upload_core_poll(&s_pcm_core, pcm_now_ms());
    *stats = s_pcm_core.stats;
    RestoreIRQMask(mask);
    return 0;
}

int luat_cc_pcm_upload_submit(const void *pcm, uint32_t len, uint32_t epoch)
{
    uint32_t mask, slot;
    uint8_t *amr = NULL;
    uint16_t amr_size = 0;
    int ret;
    if (!s_pcm_submit_mutex) return LUAT_CC_PCM_UPLOAD_INACTIVE;
    xSemaphoreTake(s_pcm_submit_mutex, portMAX_DELAY);
    mask = SaveAndSetIRQMask();
    if (!s_pcm_enabled) {
        RestoreIRQMask(mask);
        ret = LUAT_CC_PCM_UPLOAD_INACTIVE;
        goto out;
    }
    luat_cc_pcm_upload_core_poll(&s_pcm_core, pcm_now_ms());
    ret = luat_cc_pcm_upload_core_reserve(&s_pcm_core, pcm, len, epoch, &slot);
    RestoreIRQMask(mask);
    if (ret) goto out;
    halVEAllocAmrEnFrameBuf(3, (void **)&amr, &amr_size);
    if (!amr) {
        mask = SaveAndSetIRQMask();
        luat_cc_pcm_upload_core_cancel(&s_pcm_core, slot);
        RestoreIRQMask(mask);
        ret = -9;
        goto out;
    }
    mask = SaveAndSetIRQMask();
    s_pcm_tokens[slot].ptr = (uint8_t *)s_pcm_core.slots[slot].pcm_words;
    s_pcm_tokens[slot].memType = UL_RBUF_MEM;
    s_pcm_tokens[slot].refCnt = 1;
    s_pcm_tokens[slot].chanNo = 12;
    /* 在 IPC 前标记，因为快速确认可能抢占调用方。
     * halamrRecordIpc 返回 void；submitted 统计请求数，而非 RTP 包数。 */
    ret = luat_cc_pcm_upload_core_submitted(&s_pcm_core, slot);
    RestoreIRQMask(mask);
    if (ret) {
        halVEFreeAmrEnFrameBuf((void **)&amr);
        mask = SaveAndSetIRQMask();
        luat_cc_pcm_upload_core_cancel(&s_pcm_core, slot);
        RestoreIRQMask(mask);
        goto out;
    }
    /* 唤醒 CP 和输出日志必须在开中断状态下执行。调用期间仅持有
     * 任务互斥锁；完成处理不需要这把锁。 */
    halamrRecordIpc(s_pcm_core.stats.codec, s_pcm_tokens[slot].ptr, amr,
                   (uint8_t *)&s_pcm_tokens[slot], NULL, NULL);
out:
    xSemaphoreGive(s_pcm_submit_mutex);
    return ret;
}

extern void __real_audioStartRecordVoice(uint8_t codec);
extern void __real_audioStopRecordVoice(uint8_t codec);
extern void __real_audioFreeRecordBuf(void *token);
extern int __real_soc_mobile_speech_upload(uint8_t *data, uint32_t len);

void __wrap_audioStartRecordVoice(uint8_t codec)
{
    if (s_pcm_enabled) pcm_record_start(codec);
    /* 原回调会同步进入平台的 CC 事件路径，
     * 必须在释放提交互斥锁后执行。 */
    __real_audioStartRecordVoice(codec);
}

void __wrap_audioStopRecordVoice(uint8_t codec)
{
    if (s_pcm_enabled) luat_cc_pcm_upload_stop();
    /* SDK 可以清空自己的旧槽位；我们的在途副本仍保持被持有状态。 */
    __real_audioStopRecordVoice(codec);
}

void __wrap_audioFreeRecordBuf(void *token)
{
    /* 停止后仍须识别我们的 token，不得将其交给旧清理路径。 */
    if (pcm_record_complete(token)) return;
    __real_audioFreeRecordBuf(token);
}

int __wrap_soc_mobile_speech_upload(uint8_t *data, uint32_t len)
{
    return s_pcm_enabled ? -1 : __real_soc_mobile_speech_upload(data, len);
}
#endif /* LUAT_USE_CC_PCM_BRIDGE */
