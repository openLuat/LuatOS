/* CC <-> SIP 的纯 PCM 队列。不依赖 RTOS 或音频设备。 */
#ifndef LUAT_CC_PCM_CORE_H
#define LUAT_CC_PCM_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_CC_PCM_CORE_QUEUE_FRAMES 6U
#define LUAT_CC_PCM_CORE_PREBUFFER_FRAMES 3U
#define LUAT_CC_PCM_CORE_8K_SAMPLES 160U
#define LUAT_CC_PCM_CORE_16K_SAMPLES 320U

#define LUAT_CC_PCM_CORE_BAD_ARG (-1)
#define LUAT_CC_PCM_CORE_STALE (-2)
#define LUAT_CC_PCM_CORE_STOPPED (-3)

typedef struct {
    uint32_t dl_pushed;
    uint32_t dl_popped;
    uint32_t dl_dropped;       /* 队列溢出时丢弃最旧帧。 */
    uint32_t dl_flushed;       /* 停止或切换采样率时丢弃的帧数。 */
    uint32_t dl_underflows;    /* 运行期间从空 DL 队列取帧的次数。 */
    uint32_t dl_high_water;
    uint32_t ul_pushed;
    uint32_t ul_popped;        /* 实际帧数，不含生成的静音帧。 */
    uint32_t ul_dropped;
    uint32_t ul_flushed;
    uint32_t ul_underflows;    /* 播放期间队列耗尽，开始重新预缓存。 */
    uint32_t ul_prebuffer_silence;
    uint32_t ul_high_water;
    uint32_t ul_lost;          /* 播放或窗口推进时确认放弃的缺失序号数。 */
    uint32_t ul_duplicate;     /* 槽位中仍存在相同序号的帧。 */
    uint32_t ul_late;          /* 序号早于已确定的接收窗口。 */
    uint32_t rejected_session;
    uint32_t rejected_stopped;
    uint32_t rejected_format;
    uint32_t rate_changes;
    uint32_t session;
    uint32_t cc_rate;
    uint8_t running;
    uint8_t dl_queued;
    uint8_t ul_queued;
    uint8_t ul_ready;
} luat_cc_pcm_core_stats_t;

/** 存储由调用方持有；字段属于内部实现，不可直接作为实时统计读取。
 *
 * 所有操作，包括 init/start/stop/get_stats，都必须由调用方使用
 * 同一把锁串行化。平台可以使用短临界区实现。
 * 不得在锁外并发读取任何字段：get_stats 在持锁期间复制
 * 一致快照，调用方之后可以记录该副本。
 * 计数器更新还须按仓库约定使用编译器原子操作。
 * 原子操作不能替代队列、生命周期和快照的串行化；
 * 不支持无锁访问单独字段。
 *
 * 核心不会保留调用方的 PCM 指针、分配内存、调用其他
 * 子系统或等待。其存储必须覆盖所有使用它的回调的生命周期。
 */
typedef struct {
    int16_t dl[LUAT_CC_PCM_CORE_QUEUE_FRAMES][LUAT_CC_PCM_CORE_16K_SAMPLES];
    int16_t ul[LUAT_CC_PCM_CORE_QUEUE_FRAMES][LUAT_CC_PCM_CORE_8K_SAMPLES];
    luat_cc_pcm_core_stats_t counters;
    uint32_t session;
    uint32_t cc_rate;
    uint8_t running;
    uint8_t dl_read;
    uint8_t dl_count;
    uint8_t ul_count;
    uint8_t ul_ready;
    uint8_t ul_valid[LUAT_CC_PCM_CORE_QUEUE_FRAMES];
    uint16_t ul_seq[LUAT_CC_PCM_CORE_QUEUE_FRAMES];
    uint16_t ul_expected;
    uint32_t ul_stream;
} luat_cc_pcm_core_t;

/** 在任何回调访问核心之前完成初始化。 */
void luat_cc_pcm_core_init(luat_cc_pcm_core_t *core);

/** 以 8000 或 16000 Hz 启动由所有者指定的非零 session。
 * 切换 session 或启动已停止的 session 时，清空队列并重置
 * 计数器。运行中以相同 session/采样率启动时不做任何操作。运行中
 * 切换采样率会清空两个队列，并重新开始 UL 预缓存。
 * 只有生命周期所有者可以调用 start；session 是不透明的标记，
 * 不是有序序号。每通独立通话都应使用新的标记。
 * 成功返回 0；参数无效时返回 BAD_ARG，不改变状态。
 */
int luat_cc_pcm_core_start(luat_cc_pcm_core_t *core, uint32_t session,
                           uint32_t cc_rate);

/** 关闭匹配的 session 并清空 PCM 队列；允许对匹配的 session 重复停止。
 * 过期的停止请求不能关闭新 session。保留计数器供检查。
 */
int luat_cc_pcm_core_stop(luat_cc_pcm_core_t *core, uint32_t session);

/** 清空两个队列并重新预缓存，不关闭 session，
 * 不重置计数器或采样率。要求 session 匹配且正在运行；成功返回 0。
 */
int luat_cc_pcm_core_flush(luat_cc_pcm_core_t *core, uint32_t session);

/** 复制完整的一帧 20 ms CC DL 数据（当前采样率下为 160 或 320 个采样点）。
 * DL 溢出时丢弃最旧帧。返回 1 或错误码。
 */
int luat_cc_pcm_core_push_dl(luat_cc_pcm_core_t *core, uint32_t session,
                             const int16_t *pcm, uint16_t samples);

/** 取出一帧 DL 数据，并转换为 8 kHz 的 160 个采样点。
 * 返回 160；队列为空返回 0，失败返回错误码。空队列或出错时不修改 out。
 * out 必须能容纳 160 个采样点，且不得与核心存储重叠。
 */
int luat_cc_pcm_core_pop_dl(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out);

/** 复制一帧带序号的 SIP 数据，共 160 个采样点。stream 是非零媒体 epoch。
 * 新 stream 仅清空 UL，并重新进行三帧预缓存。首帧
 * 确定序号窗口起点；更早的帧均视为迟到，启动阶段也不例外。
 * 六个序号位置采用模 65536 的半区间排序规则。
 * 复制成功返回 1；重复或迟到返回 0；失败返回错误码。 */
int luat_cc_pcm_core_push_ul(luat_cc_pcm_core_t *core, uint32_t session,
                             uint32_t stream, uint16_t sequence,
                             const int16_t *pcm, uint16_t samples);

/** 按当前 CC 采样率生成一帧 20 ms 数据：返回 160 或 320。
 * 队列积累三帧后开始输出。启动前或实际欠载后，
 * 在重新积累三帧期间输出静音。核心不管理定时器，
 * 调用方必须按已建立的 CC 上传节拍调用本接口。
 * 未运行、session 过期或容量不足时返回错误码，不修改 out。
 * out 不得与核心存储重叠；capacity_samples 的单位为 int16_t 采样点。
 */
int luat_cc_pcm_core_pop_ul(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out, uint16_t capacity_samples);

/** 在同一把串行化锁内复制当前 session 的一致快照。 */
void luat_cc_pcm_core_get_stats(const luat_cc_pcm_core_t *core,
                               luat_cc_pcm_core_stats_t *out);

#ifdef __cplusplus
}
#endif
#endif
