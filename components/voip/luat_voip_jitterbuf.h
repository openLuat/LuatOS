/*
 * luat_voip_jitterbuf.h - 最小抖动缓冲
 *
 * 职责：
 * 1. 缓冲网络侧收到的 PCM 帧
 * 2. 按 RTP sequence 尽量有序输出
 * 3. 缺帧时补静音，保持播放节拍稳定
 *
 * 限制：
 * - 不做自适应延迟调整
 * - 不做 PLC（Packet Loss Concealment）
 */

#ifndef LUAT_VOIP_JITTERBUF_H
#define LUAT_VOIP_JITTERBUF_H

#include <stdint.h>
#include <stddef.h>

/* 默认参数 */
#define VOIP_JB_DEFAULT_DEPTH       3
#define VOIP_JB_DEFAULT_MAX_PENDING 64

/* 单帧槽 */
typedef struct {
    int16_t *pcm;       /* PCM 数据（由 jb 分配） */
    uint16_t seq;       /* RTP sequence number */
    uint8_t  valid;     /* 此槽是否有数据 */
} voip_jb_slot_t;

/* Jitter Buffer 上下文 */
typedef struct {
    voip_jb_slot_t *slots;
    uint16_t max_pending;   /* slots 数组大小 */
    uint16_t depth;         /* 启动深度 */
    uint16_t frame_samples; /* 每帧 PCM 采样点数 (e.g. 160 for 20ms@8kHz) */
    uint16_t pending;       /* 当前缓存帧数 */
    uint16_t expected_seq;  /* 下一个期望输出的 seq */
    uint16_t consecutive_miss; /* 连续 pop miss 计数，用于 resync */
    uint8_t  started;       /* 是否已开始输出 */
    uint8_t  seq_valid;     /* expected_seq 是否已初始化 */
} voip_jb_t;

/**
 * 创建 Jitter Buffer
 * @param depth          启动深度（积累多少帧后才开始输出）
 * @param max_pending    最大缓冲帧数
 * @param frame_samples  每帧的采样点数（不是字节数）
 * @return 上下文指针，失败返回 NULL
 */
voip_jb_t *voip_jb_create(uint16_t depth, uint16_t max_pending, uint16_t frame_samples);

/**
 * 销毁 Jitter Buffer
 */
void voip_jb_destroy(voip_jb_t *jb);

/**
 * 重置状态（清空缓冲，保留配置）
 */
void voip_jb_reset(voip_jb_t *jb);

/**
 * 推入一帧 PCM 数据
 * @param jb    上下文
 * @param seq   RTP sequence number
 * @param pcm   PCM 数据（frame_samples 个 int16_t）
 * @return 0 成功, <0 失败
 */
int voip_jb_push(voip_jb_t *jb, uint16_t seq, const int16_t *pcm);

/**
 * 弹出一帧用于播放
 * @param jb    上下文
 * @param out   输出缓冲区（frame_samples 个 int16_t），缺帧时填充静音
 * @return 1=有效帧, 0=静音帧
 */
int voip_jb_pop(voip_jb_t *jb, int16_t *out);

#endif /* LUAT_VOIP_JITTERBUF_H */
