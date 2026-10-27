#ifndef LUAT_CC_PCM_UPLOAD_CORE_H
#define LUAT_CC_PCM_UPLOAD_CORE_H

/* 由 SoC 管理的上传状态和缓冲区。仅启用 LUAT_USE_CC_PCM_BRIDGE 时
 * 才编译实现；本头文件不负责选择后端。 */

#include <stdint.h>

#define LUAT_CC_PCM_UPLOAD_SLOT_COUNT 4U
#define LUAT_CC_PCM_UPLOAD_MAX_BYTES 640U
#define LUAT_CC_PCM_UPLOAD_STOP_TIMEOUT_MS 1000U
#define LUAT_CC_PCM_UPLOAD_CODEC_NB 0U
#define LUAT_CC_PCM_UPLOAD_CODEC_WB 1U

enum {
    LUAT_CC_PCM_UPLOAD_OK = 0,
    LUAT_CC_PCM_UPLOAD_DEFERRED = 1, /* 已接受启动；必须先等待 HAL 持有的旧槽位归还。 */
    LUAT_CC_PCM_UPLOAD_BAD_ARGUMENT = -1,
    LUAT_CC_PCM_UPLOAD_INACTIVE = -2,
    LUAT_CC_PCM_UPLOAD_FAULT = -3,
    LUAT_CC_PCM_UPLOAD_BAD_LENGTH = -5,
    LUAT_CC_PCM_UPLOAD_STALE_EPOCH = -6,
    LUAT_CC_PCM_UPLOAD_NO_SLOT = -7,
    LUAT_CC_PCM_UPLOAD_BAD_STATE = -8
};

enum {
    LUAT_CC_PCM_UPLOAD_FAULT_NONE = 0,
    LUAT_CC_PCM_UPLOAD_FAULT_STOP_TIMEOUT = 2,
    LUAT_CC_PCM_UPLOAD_FAULT_BAD_CODEC = 3
};

enum {
    LUAT_CC_PCM_UPLOAD_SLOT_FREE = 0,
    LUAT_CC_PCM_UPLOAD_SLOT_RESERVED = 1,
    LUAT_CC_PCM_UPLOAD_SLOT_SUBMITTED = 2
};

typedef struct {
    uint32_t active;
    uint32_t fault;
    uint32_t codec;
    uint32_t epoch;
    uint32_t submitted; /* 已开始的 HAL 请求数，不表示已确认网络送达。 */
    uint32_t completed; /* 仅统计实际编码完成回调。 */
    uint32_t alloc_failed; /* AMR 分配失败后，在调用 HAL 前取消的槽位预留次数。 */
    uint32_t pending; /* 内存仍被持有的预留槽位与已提交槽位总数。 */
    uint32_t high_water;
    uint32_t late; /* 停止接收新提交后收到的实际完成次数。 */
    uint32_t stop_timeout;
    uint32_t bad_length;
    uint32_t no_slot;
    uint32_t stale_epoch;
    uint32_t bad_state;
    uint32_t stop_started_ms;
    uint32_t stop_waiting;
    uint32_t start_waiting; /* 已接受启动，正在等待上一 epoch 排空。 */
    uint32_t next_codec; /* 仅在 start_waiting 置位期间有效。 */
} luat_cc_pcm_upload_stats_t;

typedef struct {
    uint32_t pcm_words[LUAT_CC_PCM_UPLOAD_MAX_BYTES / sizeof(uint32_t)];
    uint32_t state;
} luat_cc_pcm_upload_slot_t;

typedef struct {
    luat_cc_pcm_upload_stats_t stats;
    luat_cc_pcm_upload_slot_t slots[LUAT_CC_PCM_UPLOAD_SLOT_COUNT];
} luat_cc_pcm_upload_core_t;

/* 调用方必须串行化所有调用以及对统计和槽位的访问。
 * init 仅在上电初始化时使用：只要媒体引擎仍可能持有槽位，
 * 就不得用它清空活动中或故障中的池。存储必须覆盖所有回调的生命周期。
 * 只有取消 RESERVED 槽位，或收到 SUBMITTED 槽位的真实
 * 完成回调后，才能复用该槽位。任何超时都不会释放内存。
 * start 可能返回 DEFERRED：立即停止接受旧 epoch 的新提交，再由 poll
 * 等待所有旧槽位真实归还后启动新 epoch。stop
 * 会取消延后的启动。重复启动不会延长排空期限。
 * 适配器必须在完成处理前后都使用当前时间调用 poll，
 * 避免最后一个逾期完成回调掩盖停止超时。
 */
void luat_cc_pcm_upload_core_init(luat_cc_pcm_upload_core_t *core);
int luat_cc_pcm_upload_core_start(luat_cc_pcm_upload_core_t *core, uint8_t codec, uint32_t now_ms);
void luat_cc_pcm_upload_core_stop(luat_cc_pcm_upload_core_t *core, uint32_t now_ms);
int luat_cc_pcm_upload_core_reserve(luat_cc_pcm_upload_core_t *core, const void *data,
                               uint32_t length, uint32_t epoch, uint32_t *out_index);
/* 在所有可能失败的准备步骤完成后、调用 halamrRecordIpc 前立即调用。
 * HAL 返回 void；submitted 仅记录正在发起该请求，
 * 不表示 CP 已接受或 RTP 已到达网络。必须在调用前标记，
 * 让快速完成回调看到 SUBMITTED 槽位。调用后不得再取消该槽位。
 */
int luat_cc_pcm_upload_core_submitted(luat_cc_pcm_upload_core_t *core, uint32_t index);
int luat_cc_pcm_upload_core_cancel(luat_cc_pcm_upload_core_t *core, uint32_t index);
int luat_cc_pcm_upload_core_complete(luat_cc_pcm_upload_core_t *core, uint32_t index);
void luat_cc_pcm_upload_core_poll(luat_cc_pcm_upload_core_t *core, uint32_t now_ms);

#endif
