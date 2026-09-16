/*
 * luat_cc_bridge.h - CC(VoLTE) <-> VoIP(SIP) 桥接功能
 *
 * 从 luat_lib_cc_v2.c 拆出的桥接代码，便于单独维护，来源提交：
 *   144285f86 add: voip,cc, 支持sip和cc通话语音流传输
 *   a4a5db00b add: voip,cc, 添加支持在4g->sip桥接通话的早期媒体功能
 *   ae88b9075 fix: cc,voip, 误把 rate=1 当成 16 kHz,导致移动卡实际 8 kHz 语音被错误按 16 kHz 处理
 *
 * 功能概述：
 *   1. 下行：CP DSP 语音从 play_save_fifo 读出，必要时 16k->8k 降采样，送 VoIP RTP 发送
 *   2. 上行：SIP 侧语音经 voip_bridge_pcm_out 取出，必要时 8k->16k 升采样，供 CP DSP 编码发送
 *   3. 早期媒体：通话未接通时向 SIP 侧送彩铃/静音(cc.bridgeTone)
 *   4. 上行 jitter 缓冲：目标水位预缓冲 + 高水位丢弃 + PLC(丢包隐藏)
 */

#ifndef LUAT_CC_BRIDGE_H
#define LUAT_CC_BRIDGE_H

#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_audio_request.h"

#if defined(LUAT_USE_CC_VOIP_BRIDGE) && !defined(LUAT_USE_VOIP_BRIDGE)
#error "LUAT_USE_CC_VOIP_BRIDGE requires LUAT_USE_VOIP_BRIDGE"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* This feature is intentionally limited to EC718HM firmware type 13/113.
 * Keep no-op inlines for other audio_v2 products so their regular CC path has
 * neither bridge symbols nor a runtime dependency on VoIP. */
#ifdef LUAT_USE_CC_VOIP_BRIDGE

/* ================= 由 luat_cc_bridge.c 提供 ================= */

/** Open gates for a new CC media session, before starting the audio request.
 * Call from the serialized media task. Stop APIs join PCM access and close
 * the gates; never call them while holding the VoIP bridge or CC driver lock. */
int luat_cc_bridge_session_start(void);

/** Select CC/SIP routing before either media path starts. Same-value calls are
 * idempotent. Enabling also selects generic PCM bridge mode; disabling leaves
 * that audio mode unchanged. Returns 0 on success and <0 while media is busy. */
int luat_cc_bridge_set_enabled(uint8_t enabled);

/** CC audio/ring/source setup, activity or teardown is still in progress. */
uint8_t luat_cc_bridge_is_busy(void);

/** Explicit CC selection and generic PCM bridge mode; RTP need not be running. */
uint8_t luat_cc_bridge_mode_on(void);

/** 早期彩铃：开始/停止/查询，仅向 VoIP RTP 侧送音 */
void    luat_cc_bridge_tone_start(void);
void    luat_cc_bridge_tone_stop(void);
uint8_t luat_cc_bridge_tone_is_on(void);

/** 下行抽取定时器：开始/停止，以及手动抽一次下行数据送 VoIP */
void    luat_cc_bridge_drain_start(void);
void    luat_cc_bridge_drain_stop(void);
void    luat_cc_bridge_drain_downlink(void);

/** 清空 SIP 上行缓冲并复位 PLC/预缓冲状态(通话接通时调用) */
void    luat_cc_bridge_flush_sip_uplink(void);

/** 录音回调中拿到真实下行数据时调用(停止早期彩铃并记日志) */
void    luat_cc_bridge_real_downlink_seen(uint32_t bytes);

/** Route SIP RTP PCM into CC through the audio extern-record source. */
int     luat_cc_bridge_uplink_source_start(luat_audio_extern_source_t *source, const luat_audio_common_param_t *cc_param, uint32_t request_id);
void    luat_cc_bridge_uplink_source_stop(void);

#else

static inline int luat_cc_bridge_session_start(void) { return 0; }
static inline int luat_cc_bridge_set_enabled(uint8_t enabled) { return enabled ? -1 : 0; }
static inline uint8_t luat_cc_bridge_is_busy(void) { return 0; }
static inline uint8_t luat_cc_bridge_mode_on(void) { return 0; }
static inline void luat_cc_bridge_tone_start(void) {}
static inline void luat_cc_bridge_tone_stop(void) {}
static inline uint8_t luat_cc_bridge_tone_is_on(void) { return 0; }
static inline void luat_cc_bridge_drain_start(void) {}
static inline void luat_cc_bridge_drain_stop(void) {}
static inline void luat_cc_bridge_drain_downlink(void) {}
static inline void luat_cc_bridge_flush_sip_uplink(void) {}
static inline void luat_cc_bridge_real_downlink_seen(uint32_t bytes) { (void)bytes; }
static inline int luat_cc_bridge_uplink_source_start(luat_audio_extern_source_t *source, const luat_audio_common_param_t *param, uint32_t request_id) {
    (void)source; (void)param; (void)request_id; return -1;
}
static inline void luat_cc_bridge_uplink_source_stop(void) {}

#endif /* LUAT_USE_CC_VOIP_BRIDGE */

/* ================= 由 luat_lib_cc_v2.c 提供 ================= */

/** 通话是否真正在进行(upload_enable && is_true_start) */
uint8_t       luat_cc_call_running(void);

/** 当前 CC 通话采样率(cc_param.sample_rate) */
uint16_t      luat_cc_get_sample_rate(void);

/** 下行播放数据 FIFO(play_save_fifo) */
luat_fifo_t  *luat_cc_get_play_fifo(void);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_CC_BRIDGE_H */
