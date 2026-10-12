#ifndef LUAT_RF433_DECODER_H
#define LUAT_RF433_DECODER_H

#include <stdint.h>
#include "luat_rf433.h"

#ifdef __cplusplus
extern "C" {
#endif

/* 内部解码核心：每个接收器独立保存一份状态，由 GPIO 中断逐次喂入边沿。
 * 原始边沿 -> 普通毛刺过滤 -> 24 位帧状态机 -> 重复帧确认 -> 服务层结果 FIFO。
 * 这里不依赖任务、计时器或 Lua；公开配置和应用接口定义在 luat_rf433.h。
 */
#define LUAT_RF433_DECODER_BITS 24u

typedef enum {
    LUAT_RF433_DECODER_WAIT_SYNC = 0, /* 尚未找到有效同步，忽略普通数据脉冲。 */
    LUAT_RF433_DECODER_READ_BITS,     /* 已找到同步，正在接收并检查 24 位数据。 */
    LUAT_RF433_DECODER_WAIT_TAIL      /* 满 24 位，仍须检查帧尾，不能立即输出。 */
} luat_rf433_decoder_state_t;

/* 帧尾阶段：LOW 同步允许两种结束顺序：
 * ① 最后一个数据 HIGH -> 长 LOW 同步；
 * ② 最后一个数据 HIGH -> 数据 LOW -> 短 HIGH 头 -> 长 LOW 同步。
 * HIGH 同步使用 START 阶段，通过 low_us 检查长 HIGH 前的短 LOW 头。
 * 这些检查用于拒绝额外数据位和顺序不正确的帧尾。
 */
typedef enum {
    LUAT_RF433_DECODER_TAIL_START = 0,    /* 刚接满 24 位，开始检查尾部。 */
    LUAT_RF433_DECODER_TAIL_SHORT_HIGH,   /* LOW 同步：已收到尾部数据 LOW，等待短 HIGH。 */
    LUAT_RF433_DECODER_TAIL_SYNC          /* LOW 同步：短 HIGH 已通过，等待长 LOW 同步。 */
} luat_rf433_decoder_tail_phase_t;

/* 内部输出函数：重复帧确认成功后，在 edge() 内立即调用，通常仍在 GPIO 中断中。
 * 服务层只在这里把完整结果复制到 FIFO；不能阻塞、分配内存或直接执行 Lua/业务。
 * 也不能从输出函数再次调用同一实例的解码器，避免重入破坏当前处理过程。
 */
typedef void (*luat_rf433_decoder_emit_t)(void *userdata, uint32_t code,
                                         uint32_t timestamp_us);

/* 每个接收器一份上下文，所有存储固定，不动态申请内存。
 * 同一实例的 init/reset/edge 由调用方保证串行；config 已由服务层校验并复制。
 * 下列三组状态分别用于：当前帧、毛刺过滤、上一完整帧的重复确认。
 */
typedef struct {
    luat_rf433_cfg_t config;          /* 实例自己的配置副本，接收时不再读取应用原对象。 */
    luat_rf433_decoder_emit_t emit;      /* 内部结果输出函数，通常指向服务层 FIFO 入队。 */
    void *emit_userdata;                /* 原样传给 emit 的上下文指针。 */
    luat_rf433_decoder_state_t state;    /* 主状态：等待同步 / 接收数据 / 检查帧尾。 */
    luat_rf433_decoder_tail_phase_t tail_phase; /* WAIT_TAIL 内部的尾部进度。 */
    uint8_t bits;                       /* 当前已接收的数据位数，正常为 0～24。 */
    /* code：逐位左移累积的 24 位码；frame_start_us：同步结束、开始收数据的时刻。 */
    uint32_t code, frame_start_us;
    /* 以下是滤波后、真正交给状态机的边沿历史：
     * have_edge：是否已有计时起点；last_level：上一个已提交边沿后的电平；
     * have_low：low_us 是否有记录，供数据配对和 HIGH 同步的帧尾检查使用。
     */
    uint8_t have_edge, last_level, have_low;
    /* last_edge_us：上一个已提交边沿时刻；low_us：最近一个完整 LOW 段的宽度。 */
    uint32_t last_edge_us, low_us;
    /* 以下是普通毛刺过滤器的状态：
     * filter_have_raw：是否已收到首个原始边沿，用来判断需不需要初始化基准；
     * filter_raw_level：最近一次 GPIO 中断读到的物理电平，包括尚未确认的变化；
     * filter_stable_level：过滤器最后已提交的电平，反向脉冲返回这里才可能被消除。
     */
    uint8_t filter_have_raw, filter_raw_level, filter_stable_level;
    /* filter_pending：是否有一个待确认边沿；filter_pending_level：该边沿之后的电平。
     * 先暂存电平变化，等后一个实际边沿判断它是否只是一次短反向毛刺。
     */
    uint8_t filter_pending, filter_pending_level;
    uint32_t filter_pending_us;          /* 待确认边沿的原始采样时刻，提交时仍使用这个时间。 */
    uint8_t last_valid;                 /* 上一完整帧是否仍可用于重复确认，和当前帧状态独立。 */
    /* last_code：上一完整帧的码；last_frame_us：该帧尾部同步结束的采样时刻。 */
    uint32_t last_code, last_frame_us;
} luat_rf433_decoder_t;

/* 初始化配置、输出函数和所有状态；首次调用时需提供已校验的配置。 */
void luat_rf433_decoder_init(luat_rf433_decoder_t *decoder,
                             const luat_rf433_cfg_t *config,
                             luat_rf433_decoder_emit_t emit, void *userdata);
/* 完整重置：清空当前帧、滤波状态和重复帧历史；保留配置及输出函数。 */
void luat_rf433_decoder_reset(luat_rf433_decoder_t *decoder);
/* 仅重置采集：清空当前帧和滤波状态，保留上一完整帧及其时刻。
 * 用于一段较长静默后的重新捕获；历史是否超时仍由 edge() 检查。
 */
void luat_rf433_decoder_reset_acquisition(luat_rf433_decoder_t *decoder);
/* 输入一次原始边沿：physical_level 是边沿之后的物理 DAT 电平，timestamp_us 是采样时刻。
 * sync_level 只选择同步/帧尾电平；数据一直按物理 HIGH 短=1、长=0 解析。
 * 一个变化先存为 pending，后一个实际边沿才能确认或消除它；没有定时器补交末尾边沿。
 * 同码完整帧在窗口内再次出现才输出；持续重复发送时，每次确认均调用 emit。
 */
void luat_rf433_decoder_edge(luat_rf433_decoder_t *decoder,
                             uint8_t physical_level, uint32_t timestamp_us);

#ifdef __cplusplus
}
#endif
#endif
