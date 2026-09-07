/*
 * luat_voip_core.c - VoIP 核心引擎实现
 *
 * 此文件实现：
 * 1. UDP socket 创建/收发
 * 2. G.711 编解码
 * 3. 后台 RTOS task 事件循环
 * 4. 统计定时器
 * 5. 麦克风 I2S 采集回调 (真机)
 * 6. 通过 luat_msgbus 桥接回调到 Lua 主线程
 */

#include "luat_voip_core.h"

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_network_adapter.h"
#include "luat_audio.h"

#ifdef LUAT_USE_AUDIO_V2
#include "luat_audio_driver.h"
#include "luat_audio_core.h"
#endif

#include "luat_rtp.h"
#include "luat_conf_bsp.h"
#include "g711_codec/g711_codec.h"
#include "luat_crypto.h"

#ifdef LUAT_USE_VOIP_AUDIO_DAC
#include "luat_dac.h"
#endif

#ifdef LUAT_USE_VOIP_AUDIO_I2S
#include "luat_i2s.h"
#endif

#include <string.h>
#include <stdlib.h>

#define LUAT_LOG_TAG "voip"
#include "luat_log.h"

/* ======================== 全局单实例 ======================== */

static voip_ctx_t g_voip_ctx;

voip_ctx_t *voip_get_ctx(void)
{
    return &g_voip_ctx;
}

/* ======================== 前向声明 ======================== */

static void voip_task_entry(void *param);
static int  voip_lua_cb_handler(lua_State *L, void *ptr);
static void voip_do_rx(voip_ctx_t *ctx);
static void voip_fill_play_slot(voip_ctx_t *ctx, uint8_t slot_idx);
int voip_audio_backend_start(voip_ctx_t *ctx, uint32_t sample_rate);
void voip_audio_backend_stop(voip_ctx_t *ctx);
static void voip_cleanup(voip_ctx_t *ctx);
static void voip_reset_session_state(voip_ctx_t *ctx);
static int  voip_session_start(voip_ctx_t *ctx);
static void voip_session_stop(voip_ctx_t *ctx, int notify_idle);
static int  voip_runtime_init(voip_ctx_t *ctx);
static void voip_rtp_tx_state_init(voip_rtp_tx_state_t *state, uint8_t payload_type, uint32_t clock_rate, uint16_t ptime);
static int  voip_pack_rtp_packet(voip_rtp_tx_state_t *state, const uint8_t *payload, uint16_t payload_len, uint8_t *out_buf, uint16_t out_max_len, uint16_t *out_len);
static int  voip_parse_rtp_packet(const uint8_t *data, uint16_t len, voip_rtp_parsed_t *out);
static const int16_t *voip_prepare_tx_pcm(voip_ctx_t *ctx, const int16_t *mic_pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t capture_tick_ms);

/* ======================== Lua 回调桥接 ======================== */

/*
 * 通过 luat_msgbus_put 将事件抛给 Lua 主线程。
 * arg1 = 回调类型 (VOIP_CB_STATE / VOIP_CB_STATS / VOIP_CB_ERROR)
 * arg2 = 附加参数
 */
static void voip_notify_lua(int cb_type, int arg2)
{
    rtos_msg_t msg = {0};
    msg.handler = voip_lua_cb_handler;
    msg.arg1 = cb_type;
    msg.arg2 = arg2;
    luat_msgbus_put(&msg, 0);
}

#ifdef LUAT_USE_VOIP_RECORD
static void voip_record_notify(voip_record_event_t event)
{
    voip_notify_lua(VOIP_CB_RECORD, event);
}
#endif

/* ======================== 定时器回调 ======================== */

static LUAT_RT_RET_TYPE voip_stats_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    voip_ctx_t *ctx = &g_voip_ctx;
    if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_STATS_TICK, 0, 0, 0, 0);
    }
}

#ifdef LUAT_USE_VOIP_BRIDGE
static LUAT_RT_RET_TYPE voip_bridge_tone_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    voip_ctx_t *ctx = &g_voip_ctx;
    if (ctx->state == VOIP_STATE_RUNNING && ctx->bridge_tone_on && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_BRIDGE_TONE, 0, 0, 0, 0);
    }
}
#endif

/* ======================== 网络回调 ======================== */

/*
 * UDP socket 事件回调。在网络适配层的上下文中被调用，不能做阻塞操作。
 * 收到数据时发送事件给 voip task 处理。
 */
static int32_t voip_net_cb(void *pdata, void *pparam)
{
    voip_ctx_t *ctx = (voip_ctx_t *)pparam;
    OS_EVENT *event = (OS_EVENT *)pdata;
    uint32_t ev_id = event->ID;

    if (ev_id == EV_NW_RESULT_EVENT) {
        if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
            luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_RX_DATA, 0, 0, 0, 0);
        }
    } else if (ev_id == EV_NW_RESULT_CLOSE || ev_id == EV_NW_SOCKET_ERROR) {
        LLOGW("voip net event 0x%x", (unsigned)ev_id);
    }
    return 0;
}

#if 0 /* moved to luat_voip_audio_backend.c */
#if defined(LUAT_USE_VOIP_AUDIO_I2S) || defined(LUAT_USE_VOIP_AUDIO_DAC)
static int voip_i2s_cb(uint8_t id, luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    (void)id;
    (void)param;

    if (event == LUAT_I2S_EVENT_RX_DONE && ctx->state == VOIP_STATE_RUNNING) {
        if (ctx->task_handle) {
            uint8_t mic_idx = ctx->mic_write_idx;
            uint32_t generation;

            if (ctx->mic_buf[mic_idx]) {
                uint32_t copy_len = rx_len > ctx->frame_bytes ? ctx->frame_bytes : rx_len;
                memcpy(ctx->mic_buf[mic_idx], rx_data, copy_len);
                if (copy_len < ctx->frame_bytes) {
                    memset(((uint8_t *)ctx->mic_buf[mic_idx]) + copy_len, 0, ctx->frame_bytes - copy_len);
                }
            }

            generation = ++ctx->mic_generation[mic_idx];
            if(ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
                ctx->last_completed_slot = (ctx->last_completed_slot + 1) % ctx->play_slot_count;
            }
            luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_MIC_DATA, mic_idx, ctx->last_completed_slot, generation, 0);
            ctx->mic_write_idx = (ctx->mic_write_idx + 1) % VOIP_MIC_SLOT_COUNT;
        }
    } else if (event == LUAT_I2S_EVENT_RX_DONE) {
        LLOGI("voip_i2s_cb: RX_DONE but state=%d (expected RUNNING=%d), dropping", ctx->state, VOIP_STATE_RUNNING);
    }

    return 0;
}
#endif

#if defined(LUAT_USE_VOIP_AUDIO_DAC)
static int voip_dac_play_cb(uint8_t id, luat_dac_event_t event, uint32_t tx_len, void *param)
{
    if (event == LUAT_DAC_EVENT_TX_ONE_BLOCK_DONE) {
        voip_ctx_t *ctx = (voip_ctx_t *)param;
        if (ctx->state != VOIP_STATE_RUNNING) {
            return 0;
        }
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
    }
    return 0;
}
#endif

#ifdef LUAT_USE_AUDIO_V2
/* audio_v2 全双工模式下 DAC 完成一帧的 weak 回调实现 */
void luat_audio_voip_dac_done_cb(void)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
    }
}
#endif
#endif /* moved callbacks */

static int voip_pop_play_frame(voip_ctx_t *ctx, int16_t *out)
{
    int got = voip_jb_pop(ctx->jb, out);

    if (got) {
        ctx->stats.jb_played++;
    } else {
        ctx->stats.jb_silence++;
    }
    return got;
}

static void voip_fill_play_slot(voip_ctx_t *ctx, uint8_t slot_idx)
{
    if (!ctx->duplex_play_buf || slot_idx >= ctx->play_slot_count) return;
    int16_t *play_frame = ctx->duplex_play_buf + slot_idx * ctx->frame_samples;
    voip_pop_play_frame(ctx, play_frame);
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_tap_rx(play_frame, ctx->frame_samples);
#endif
#ifndef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    /* Preserve legacy Speex playback/capture reference timing on other BSPs. */
    voip_aec_render_push(ctx, play_frame, 0, 0);
#endif
    if (ctx->trace_on) {
        LLOGE("fill play slot %u", slot_idx);
    }
}

static const int16_t *voip_prepare_tx_pcm(voip_ctx_t *ctx, const int16_t *mic_pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t capture_tick_ms)
{
    return voip_aec_process_frame(ctx, mic_pcm, render_seq, capture_seq, capture_tick_ms);
}

static void voip_rtp_tx_state_init(voip_rtp_tx_state_t *state, uint8_t payload_type, uint32_t clock_rate, uint16_t ptime)
{
    if (!state) return;

    memset(state, 0, sizeof(*state));
    state->payload_type = payload_type;
    state->clock_rate = clock_rate ? clock_rate : VOIP_SAMPLE_RATE_DEFAULT;
    state->ptime = ptime ? ptime : VOIP_FRAME_MS_DEFAULT;
    state->samples_per_packet = (uint16_t)(state->clock_rate * state->ptime / 1000);
    PV_Union uPV;
	luat_crypto_trng((char *)uPV.u8, 4);
    state->seq = (uint16_t)(uPV.u32 & 0xFFFF);
	luat_crypto_trng((char *)uPV.u8, 4);
    state->timestamp = (uint32_t)(uPV.u32 & 0x7FFFFFFF);
	luat_crypto_trng((char *)uPV.u8, 4);
    state->ssrc = (uint32_t)(uPV.u32 & 0x7FFFFFFF);
    if (state->ssrc == 0) {
        state->ssrc = 1;
    }
}

static int voip_pack_rtp_packet(voip_rtp_tx_state_t *state, const uint8_t *payload, uint16_t payload_len, uint8_t *out_buf, uint16_t out_max_len, uint16_t *out_len)
{
    rtp_base_head_t base_head = {0};
    int packed_len;

    if (!state || !out_buf || !out_len) return -1;
    if (!payload && payload_len > 0) return -1;

    base_head.version = 2;
    base_head.payload_type = state->payload_type & 0x7F;
    base_head.sn = state->seq;
    base_head.time_tamp = state->timestamp;
    base_head.ssrc = state->ssrc;

    packed_len = luat_pack_rtp(&base_head, NULL, payload, payload_len, out_buf, out_max_len);
    if (packed_len <= 0) {
        return -1;
    }

    state->seq = (state->seq + 1U) & 0xFFFF;
    state->timestamp += state->samples_per_packet;
    *out_len = (uint16_t)packed_len;
    return 0;
}

static int voip_parse_rtp_packet(const uint8_t *data, uint16_t len, voip_rtp_parsed_t *out)
{
    rtp_base_head_t base_head = {0};
    rtp_extern_head_t extern_head = {0};
    uint32_t *csrc = NULL;
    uint32_t *extern_data = NULL;
    uint16_t header_len;
    uint16_t payload_end;
    int parsed_len;

    if (!data || !out || len < VOIP_RTP_HEADER_LEN) return -1;

    memset(out, 0, sizeof(*out));
    parsed_len = luat_unpack_rtp_head((const uint32_t *)data, len, &base_head, &csrc);
    if (parsed_len <= 0) {
        return -2;
    }

    header_len = (uint16_t)parsed_len;
    if (base_head.extension) {
        if (len < (uint16_t)(header_len + 4)) {
            return -3;
        }
        parsed_len = luat_unpack_rtp_extern_head((const uint32_t *)(data + header_len), len - header_len, &extern_head, &extern_data);
        if (parsed_len <= 0) {
            return -4;
        }
        header_len = (uint16_t)(header_len + parsed_len);
    }

    payload_end = len;
    if (base_head.padding) {
        uint8_t pad_len = data[len - 1];
        if (pad_len == 0 || pad_len > (uint8_t)(len - header_len)) {
            return -5;
        }
        payload_end = (uint16_t)(len - pad_len);
    }
    if (payload_end < header_len) {
        return -6;
    }

    out->version = base_head.version;
    out->padding = base_head.padding;
    out->extension = base_head.extension;
    out->marker = base_head.maker;
    out->payload_type = base_head.payload_type;
    out->sequence = base_head.sn;
    out->timestamp = base_head.time_tamp;
    out->ssrc = base_head.ssrc;
    out->header_len = header_len;
    out->payload = data + header_len;
    out->payload_len = (uint16_t)(payload_end - header_len);
    return 0;
}

/* ======================== 核心处理函数 ======================== */

/* TX: 获取一帧 PCM → G.711 编码 → RTP 打包 → UDP 发送 */
static void voip_do_tx(voip_ctx_t *ctx, const int16_t *mic_pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t capture_tick_ms)
{
    if (!ctx->netc) return;
    int16_t *pcm = ctx->tx_pcm_buf;
    const int16_t *tx_pcm;

    if (!mic_pcm) {
        LLOGE("voip_do_tx: mic_pcm is NULL, aborting");
        return;
    }

    tx_pcm = voip_prepare_tx_pcm(ctx, mic_pcm, render_seq, capture_seq,
            capture_tick_ms);
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_tap_tx(tx_pcm, ctx->frame_samples);
#endif
    memcpy(pcm, tx_pcm, ctx->frame_bytes);

    /* Compare raw microphone and post-AEC levels to expose pumping. */
    int32_t mic_energy = 0;
    int32_t out_energy = 0;
    for (uint32_t i = 0; i < ctx->frame_samples; i++) {
        mic_energy += abs(mic_pcm[i]);
        out_energy += abs(pcm[i]);
    }
    mic_energy /= ctx->frame_samples;
    out_energy /= ctx->frame_samples;

    /* 编码 */
    uint32_t out_len = 0;
    uint32_t used = 0;
    int ret = LUAT_ERROR_NONE;
    ret = ctx->codec_encoder.opts->encode(&ctx->codec_encoder,  (const uint8_t *)pcm,  ctx->frame_bytes, ctx->tx_g711_buf, &used, &out_len);
    if (ret != LUAT_ERROR_NONE || out_len == 0) {
        LLOGW("encode failed ret=%d used=%u out_len=%u", ret, used, out_len);
        return;
    }
    /* RTP 打包 */
    uint16_t rtp_len = 0;
    ret = voip_pack_rtp_packet(&ctx->rtp_tx, ctx->tx_g711_buf, (uint16_t)out_len, ctx->rtp_packet_buf, (uint16_t)(VOIP_RTP_HEADER_LEN + ctx->frame_samples), &rtp_len);
    if (ret < 0) return;

    /* UDP 发送 */
    network_ctrl_t *netc = (network_ctrl_t *)ctx->netc;
    /* 已在 connect 时设置好 remote，直接发 */
    uint32_t tx_len = 0;
    network_tx(netc, ctx->rtp_packet_buf, rtp_len, 0, NULL, 0, &tx_len, 0);
    ctx->stats.tx_packets++;
    ctx->stats.tx_bytes += rtp_len;

    /* 调试日志：每100帧输出一次能量信息 */
    if (ctx->stats.tx_packets % 100 == 1) {
        LLOGI("voip_do_tx: tx_packets=%u mic=%ld out=%ld",
                ctx->stats.tx_packets, mic_energy, out_energy);
    }
}

#ifdef LUAT_USE_VOIP_BRIDGE
static void voip_do_bridge_tone(voip_ctx_t *ctx)
{
    static const int16_t tone400_table[20] = {
        0, 2472, 4702, 6472, 7608, 8000, 7608, 6472, 4702, 2472,
        0, -2472, -4702, -6472, -7608, -8000, -7608, -6472, -4702, -2472
    };
    uint32_t cadence_frame;

    if (!ctx || ctx->state != VOIP_STATE_RUNNING || ctx->audio_mode != VOIP_AUDIO_MODE_BRIDGE ||
        !ctx->bridge_tone_on || !ctx->rx_pcm_buf) {
        return;
    }

    cadence_frame = (ctx->bridge_tone_pos / ctx->frame_samples) % 150;
    for (uint16_t i = 0; i < ctx->frame_samples; i++) {
        if (cadence_frame < 50) {
            ctx->rx_pcm_buf[i] = tone400_table[ctx->bridge_tone_pos % 20];
        } else {
            ctx->rx_pcm_buf[i] = 0;
        }
        ctx->bridge_tone_pos++;
    }
    voip_do_tx(ctx, ctx->rx_pcm_buf, 0, 0, 0);
}
#endif
/* callbacks moved to luat_voip_audio_backend.c */

/* RX: 从 UDP socket 读取所有待处理数据 → RTP 解析 → 解码 → JB push */
static void voip_do_rx(voip_ctx_t *ctx)
{
    if (!ctx->netc) return;

    network_ctrl_t *netc = (network_ctrl_t *)ctx->netc;
    luat_ip_addr_t remote_ip = {0};
    uint16_t remote_port = 0;

    while (1) {

        int rd = network_socket_receive(netc, ctx->udp_rx_buf, ctx->udp_rx_buf_size, 0, &remote_ip, &remote_port);
        if (rd <= 0) 
        {
            break;
        }
        ctx->stats.rx_packets++;
        ctx->stats.rx_bytes += rd;

        /* RTP 解析 */
        voip_rtp_parsed_t parsed;
        int ret = voip_parse_rtp_packet(ctx->udp_rx_buf, (uint16_t)rd, &parsed);
        if (ret < 0) {
            ctx->stats.rx_parse_fail++;
            LLOGE("rtp parse failed: %d", ret);
            continue;
        }

        if (parsed.payload_type != ctx->rtp_payload_type) {
            ctx->stats.rx_bad_payload++;
            LLOGE("unexpected RTP payload type: %u", parsed.payload_type);
            continue;
        }

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        /* Air8101's fixed 20 ms G.711 frame buffer accepts one frame per RTP packet. */
        if (parsed.payload_len != ctx->frame_samples) {
            ctx->stats.rx_bad_payload++;
            if ((ctx->stats.rx_bad_payload & 0x3FU) == 1U) {
                LLOGW("drop RTP payload len=%u expected=%u seq=%u",
                      parsed.payload_len, ctx->frame_samples, parsed.sequence);
            }
            continue;
        }
#endif

        /* 丢包/乱序估算 */
        if (ctx->stats.last_rx_seq_valid) {
            uint16_t diff = (parsed.sequence - ctx->stats.last_rx_seq) & 0xFFFF;
            if (diff == 0) {
                ctx->stats.rx_out_of_order++;
            } else if (diff > 1 && diff < 0x8000) {
                ctx->stats.rx_lost += (diff - 1);
            } else if (diff >= 0x8000) {
                ctx->stats.rx_out_of_order++;
            }
        }
        ctx->stats.last_rx_seq = parsed.sequence;
        ctx->stats.last_rx_seq_valid = 1;

        uint32_t pcm_len = 0;
        uint32_t used = 0;

        ret = ctx->codec_decoder.opts->decode(&ctx->codec_decoder, NULL, parsed.payload, parsed.payload_len, (uint8_t *)ctx->rx_pcm_buf, &pcm_len, &used);

        if (ret == LUAT_ERROR_NONE &&
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            pcm_len == ctx->frame_bytes && used == parsed.payload_len
#else
            pcm_len > 0
#endif
            ) {
#ifdef LUAT_USE_VOIP_BRIDGE
            if (ctx->audio_mode == VOIP_AUDIO_MODE_BRIDGE) {
                uint16_t samples = (uint16_t)(pcm_len / sizeof(int16_t));
                if (ctx->bridge_mutex) luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
                for (uint16_t i = 0; i < samples; i++) {
                    if (ctx->bridge_rx_count >= VOIP_BRIDGE_BUF_SAMPLES) {
                        ctx->bridge_rx_read_idx = (ctx->bridge_rx_read_idx + 1) % VOIP_BRIDGE_BUF_SAMPLES;
                        ctx->bridge_rx_count--;
                    }
                    ctx->bridge_rx_buf[ctx->bridge_rx_write_idx] = ctx->rx_pcm_buf[i];
                    ctx->bridge_rx_write_idx = (ctx->bridge_rx_write_idx + 1) % VOIP_BRIDGE_BUF_SAMPLES;
                    ctx->bridge_rx_count++;
                }
                if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
            } else {
                voip_jb_push(ctx->jb, parsed.sequence, ctx->rx_pcm_buf);
            }
#else
            voip_jb_push(ctx->jb, parsed.sequence, ctx->rx_pcm_buf);
#endif
        } else {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            ctx->stats.rx_bad_payload++;
            if ((ctx->stats.rx_bad_payload & 0x3FU) == 1U) {
                LLOGW("drop decoded RTP ret=%d pcm=%u/%u used=%u/%u seq=%u",
                      ret, pcm_len, ctx->frame_bytes, used,
                      parsed.payload_len, parsed.sequence);
            }
#else
            LLOGE("decode failed, ret=%d pcm_len=%u used=%u", ret, pcm_len, used);
#endif
        }
    }
}

/* ======================== 资源分配/释放 ======================== */

static int voip_alloc_buffers(voip_ctx_t *ctx)
{
    uint16_t fs = ctx->frame_samples;
    uint16_t fb = ctx->frame_bytes;

    ctx->tx_pcm_buf     = (int16_t *)luat_heap_calloc(1, fb);
    ctx->tx_g711_buf    = (uint8_t *)luat_heap_calloc(1, fs); /* G.711: 1 byte/sample */
    ctx->rtp_packet_buf = (uint8_t *)luat_heap_calloc(1, VOIP_RTP_HEADER_LEN + fs);
    ctx->rx_pcm_buf     = (int16_t *)luat_heap_calloc(1, fb);
    ctx->duplex_play_buf = (int16_t *)luat_heap_calloc(1, fb * ctx->play_slot_count);
    if (ctx->config.aec_enable) {
        ctx->aec_out_buf = (int16_t *)luat_heap_calloc(1, fb);
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        ctx->aec_ref_buf = (int16_t *)luat_heap_calloc(1, fb);
        ctx->aec_ref_history = (int16_t *)luat_heap_calloc(VOIP_AEC_REF_HISTORY_FRAMES, fb);
#endif
    }
    ctx->udp_rx_buf_size = VOIP_RTP_HEADER_LEN + fs + 64; /* 余量 */
    ctx->udp_rx_buf     = (uint8_t *)luat_heap_calloc(1, ctx->udp_rx_buf_size);

    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        ctx->mic_buf[index] = (int16_t *)luat_heap_calloc(1, fb);
    }

    if (!ctx->tx_pcm_buf || !ctx->tx_g711_buf || !ctx->rtp_packet_buf ||
        !ctx->rx_pcm_buf || !ctx->duplex_play_buf ||
        (ctx->config.aec_enable && !ctx->aec_out_buf) ||
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        (ctx->config.aec_enable && (!ctx->aec_ref_buf || !ctx->aec_ref_history)) ||
#endif
        !ctx->udp_rx_buf) {
        return -1;
    }

    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        if (!ctx->mic_buf[index]) {
            return -1;
        }
    }

#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->audio_mode == VOIP_AUDIO_MODE_BRIDGE) {
        ctx->bridge_tx_buf = (int16_t *)luat_heap_calloc(1, VOIP_BRIDGE_BUF_BYTES);
        ctx->bridge_rx_buf = (int16_t *)luat_heap_calloc(1, VOIP_BRIDGE_BUF_BYTES);
        if (!ctx->bridge_tx_buf || !ctx->bridge_rx_buf) {
            return -1;
        }
    }
#endif

    return 0;
}

#if 0 /* moved to luat_voip_audio_backend.c */
static int voip_start_audio(voip_ctx_t *ctx, uint32_t sample_rate)
{
    luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
    if (!audio_conf) {
        LLOGE("audio config not found for multimedia_id=%u", ctx->config.multimedia_id);
        return -1;
    }
    LLOGI("voip_start_audio: multimedia_id=%u bus_type=%s i2s_id=%u", 
          ctx->config.multimedia_id, 
          audio_conf->bus_type == LUAT_AUDIO_BUS_I2S ? "I2S" : (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC ? "DAC" : "OTHER"),
          audio_conf->codec_conf.i2s_id);
    memset(ctx->duplex_play_buf, 0, ctx->frame_bytes * ctx->play_slot_count);
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
#if defined(LUAT_USE_VOIP_AUDIO_I2S)
        luat_i2s_conf_t *i2s = luat_i2s_get_config((uint8_t)audio_conf->codec_conf.i2s_id);
        if (!i2s) {
            LLOGE("i2s config not found for id=%u", audio_conf->codec_conf.i2s_id);
            return -1;
        }

        if (luat_i2s_save_old_config(audio_conf->codec_conf.i2s_id) == 0) {
            ctx->i2s_config_saved = 1;
        }

        i2s->is_full_duplex = 1;
        i2s->cb_rx_len = ctx->frame_bytes;
        i2s->luat_i2s_event_callback = voip_i2s_cb;
        LLOGI("voip_start_audio: I2S callback set, frame_bytes=%u", ctx->frame_bytes);

        /* 预填充静音，不从 JB pop，避免在 JB 未就绪时推进 expected_seq */
        ctx->audio_backend = VOIP_AUDIO_BACKEND_DUPLEX;
        if (luat_audio_record_and_play(ctx->config.multimedia_id, sample_rate, (const uint8_t *)ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count) != 0) {
            LLOGE("start duplex audio failed");
            if (ctx->i2s_config_saved) {
                luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
                ctx->i2s_config_saved = 0;
            }
            return -1;
        }
#else
        return -1;
#endif
    } else if (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC) {
#if defined(LUAT_USE_VOIP_AUDIO_DAC)
        ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
        luat_audio_record_set_callback(voip_i2s_cb);
#if defined(LUAT_USE_AUDIO_V2)
        {
            luat_audio_driver_ctrl_t *ctrl = luat_audio_driver_probe(NULL);
            if (!ctrl) {
                LLOGE("no audio_v2 driver found");
                return -1;
            }

            if (LUAT_AUDIO_DRIVER_STATE_INITED == ctrl->state) {
                int ret = ctrl->opts->activate(ctrl);
                if (ret) {
                    LLOGE("audio_v2 activate failed %d", ret);
                    return -1;
                }
                ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
            }

            if (ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 0) != LUAT_ERROR_NONE) {
                LLOGE("audio_v2 modify tx param failed");
                return -1;
            }
            if (ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 1) != LUAT_ERROR_NONE) {
                LLOGE("audio_v2 modify rx param failed");
                return -1;
            }

            ctrl->request_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER;
            if (luat_audio_driver_start(ctrl, &ctrl->tx_param, &ctrl->rx_param,
                                        (uint32_t *)ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count) != 0) {
                LLOGE("audio_v2 speech with buffer start failed");
                return -1;
            }
            ctx->audio_v2_ctrl = ctrl;
        }
#else
        if (luat_audio_record_and_play(ctx->config.multimedia_id, sample_rate, (const uint8_t *)ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count) != 0) {
            LLOGE("start duplex audio failed");
            return -1;
        }
        luat_dac_config_t config = {
            .dac_chl = LUAT_DAC_CHL_L,
            .bits = LUAT_DAC_BITS_16,
            .samp_rate = sample_rate,
            .luat_dac_event_callback = voip_dac_play_cb,
            .userdata = ctx
        };
        luat_dac_setup(0, &config);
        luat_dac_buffer_loop(ctx->config.multimedia_id, ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count);
#endif
#else
        LLOGE("DAC bus type not supported in this build");
        return -1;
#endif
    } else {
        return -1;
    }


    ctx->audio_started = 1;
    ctx->last_completed_slot = ctx->play_slot_count - 1;
    if (ctx->trace_on) {
        LLOGI("duplex backend start slots=%u frame_bytes=%u", ctx->play_slot_count, ctx->frame_bytes);
    }
    return 0;
}

static void voip_stop_audio(voip_ctx_t *ctx)
{
    if (!ctx->audio_started) return;

    luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
    if(!audio_conf) {
        return;
    }

    /* 先清空播放缓冲区，避免挂断后播放残留数据产生噪音 */
    if (ctx->duplex_play_buf) {
        memset(ctx->duplex_play_buf, 0, ctx->frame_bytes * ctx->play_slot_count);
    }

#if defined(LUAT_USE_AUDIO_V2)
    if (ctx->audio_v2_ctrl) {
        luat_audio_driver_deactivate((luat_audio_driver_ctrl_t *)ctx->audio_v2_ctrl);
        ctx->audio_v2_ctrl = NULL;
    } else
#endif
    {
        luat_audio_record_stop(ctx->config.multimedia_id);

        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
#if defined(LUAT_USE_VOIP_AUDIO_I2S)
            luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
            ctx->i2s_config_saved = 0;
#endif
        } else {
#if defined(LUAT_USE_VOIP_AUDIO_DAC)
            luat_dac_close(0);
#endif
        }
    }
    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    ctx->audio_started = 0;
}

#endif /* moved audio backend */

static void voip_free_buffers(voip_ctx_t *ctx)
{
    if (ctx->tx_pcm_buf)      { luat_heap_free(ctx->tx_pcm_buf);      ctx->tx_pcm_buf = NULL; }
    if (ctx->tx_g711_buf)     { luat_heap_free(ctx->tx_g711_buf);     ctx->tx_g711_buf = NULL; }
    if (ctx->rtp_packet_buf)  { luat_heap_free(ctx->rtp_packet_buf);  ctx->rtp_packet_buf = NULL; }
    if (ctx->rx_pcm_buf)      { luat_heap_free(ctx->rx_pcm_buf);      ctx->rx_pcm_buf = NULL; }
    if (ctx->duplex_play_buf) { luat_heap_free(ctx->duplex_play_buf); ctx->duplex_play_buf = NULL; }
    if (ctx->aec_out_buf)     { luat_heap_free(ctx->aec_out_buf);     ctx->aec_out_buf = NULL; }
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    if (ctx->aec_ref_buf)     { luat_heap_free(ctx->aec_ref_buf);     ctx->aec_ref_buf = NULL; }
    if (ctx->aec_ref_history) { luat_heap_free(ctx->aec_ref_history); ctx->aec_ref_history = NULL; }
#endif
    if (ctx->udp_rx_buf)      { luat_heap_free(ctx->udp_rx_buf);      ctx->udp_rx_buf = NULL; }
    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        if (ctx->mic_buf[index]) {
            luat_heap_free(ctx->mic_buf[index]);
            ctx->mic_buf[index] = NULL;
        }
    }
#ifdef LUAT_USE_VOIP_BRIDGE
    /* PCM callers can still be finishing a CC timer callback. Detach under
     * their lock, then free without holding the lock across heap operations. */
    if (ctx->bridge_mutex) luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
    int16_t *bridge_tx = ctx->bridge_tx_buf;
    int16_t *bridge_rx = ctx->bridge_rx_buf;
    ctx->bridge_tx_buf = NULL;
    ctx->bridge_rx_buf = NULL;
    ctx->bridge_tx_count = 0;
    ctx->bridge_rx_count = 0;
    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
    if (bridge_tx) luat_heap_free(bridge_tx);
    if (bridge_rx) luat_heap_free(bridge_rx);
#endif
}
static void voip_cleanup(voip_ctx_t *ctx)
{
    /* 停止定时器 */
    if (ctx->stats_timer) { luat_rtos_timer_stop(ctx->stats_timer); }
#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->bridge_tone_timer) { luat_rtos_timer_stop(ctx->bridge_tone_timer); }
    ctx->bridge_tone_on = 0;
#endif
    
    /* 停止音频 */
    voip_audio_backend_stop(ctx);

    /* 关闭网络 */
    if (ctx->netc) {
        network_socket_force_close((network_ctrl_t *)ctx->netc);
        network_release_ctrl((network_ctrl_t *)ctx->netc);
        ctx->netc = NULL;
    }


    /* 释放 codec */
    // if (ctx->encoder) { g711_encoder_destroy(ctx->encoder); ctx->encoder = NULL; }
    // if (ctx->decoder) { g711_decoder_destroy(ctx->decoder); ctx->decoder = NULL; }

        /* 释放 codec */
    luat_audio_data_codec_unbind(&ctx->codec_encoder);
    luat_audio_data_codec_unbind(&ctx->codec_decoder);

    /* 释放 AEC */
    voip_aec_cleanup(ctx);

    /* 释放 JB */
    if (ctx->jb) { voip_jb_destroy(ctx->jb); ctx->jb = NULL; }

    /* 释放缓冲区 */
    voip_free_buffers(ctx);
}

static void voip_reset_session_state(voip_ctx_t *ctx)
{
    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    ctx->audio_started = 0;
    ctx->i2s_config_saved = 0;
#ifdef LUAT_USE_AUDIO_V2
    ctx->audio_v2_ctrl = NULL;
#endif
    ctx->play_slot_count = VOIP_DUPLEX_SLOT_COUNT;
    ctx->mic_write_idx = 0;
    ctx->last_completed_slot = ctx->play_slot_count - 1;
    ctx->trace_on = 0;
    ctx->dropped_mic_events = 0;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    ctx->render_done_seq = 0;
    ctx->render_refill_seq = 0;
    ctx->capture_seq = 0;
    ctx->aec_last_capture_seq = 0;
    ctx->aec_last_render_seq = 0;
    ctx->aec_ops = NULL;
    ctx->aec_state = NULL;
    ctx->aec_sync_fault = 0;
#endif
    ctx->aec_ready = 0;
#ifdef LUAT_USE_VOIP_BRIDGE
    ctx->bridge_tx_write_idx = 0;
    ctx->bridge_tx_read_idx = 0;
    ctx->bridge_rx_write_idx = 0;
    ctx->bridge_rx_read_idx = 0;
    ctx->bridge_tx_count = 0;
    ctx->bridge_rx_count = 0;
    ctx->bridge_tone_on = 0;
    ctx->bridge_tone_pos = 0;
#endif
    memset(ctx->mic_generation, 0, sizeof(ctx->mic_generation));
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    memset(ctx->mic_capture_seq, 0, sizeof(ctx->mic_capture_seq));
    memset(ctx->mic_render_seq, 0, sizeof(ctx->mic_render_seq));
    memset(ctx->mic_capture_tick_ms, 0, sizeof(ctx->mic_capture_tick_ms));
#endif
    memset(&ctx->stats, 0, sizeof(ctx->stats));
}

static int voip_session_start(voip_ctx_t *ctx)
{
    uint16_t ptime = ctx->config.ptime ? ctx->config.ptime : VOIP_FRAME_MS_DEFAULT;
    uint32_t sample_rate = ctx->config.sample_rate ? ctx->config.sample_rate : VOIP_SAMPLE_RATE_DEFAULT;
    ctx->config.sample_rate = sample_rate;

    voip_reset_session_state(ctx);
#ifdef __WIN32__
    ctx->trace_on = 1;  /* PC 模拟器调试：开启 RTP 数据包跟踪 */
#endif
    ctx->frame_samples = (uint16_t)(sample_rate * ptime / 1000);
    ctx->frame_bytes = ctx->frame_samples * 2;
    LLOGE("voip config: remote=%s:%d codec=%d ptime=%d",
          ctx->config.remote_ip, ctx->config.remote_port, ctx->config.codec,
          ptime);
    LLOGE("voio origin: samples=%d", ctx->config.sample_rate);
    LLOGE("voio frame: samples=%d bytes=%d", ctx->frame_samples, ctx->frame_bytes);
    // const luat_audio_data_codec_opts_t *codec_opts = NULL;

    uint8_t codec_type = VOIP_CODEC_PCMA;
    if (ctx->config.codec == VOIP_CODEC_PCMA) {
        ctx->rtp_payload_type = VOIP_RTP_PT_PCMA;
        codec_type = LUAT_AUDIO_DATA_CODEC_TYPE_G711_ALAW;
    } else {
        ctx->rtp_payload_type = VOIP_RTP_PT_PCMU;
        codec_type = LUAT_AUDIO_DATA_CODEC_TYPE_G711_ULAW;
    }

    int ret = luat_audio_data_codec_bind(&ctx->codec_encoder, luat_audio_data_codec_find(codec_type), NULL);
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("codec encoder bind failed type=%u ret=%d", codec_type, ret);
        goto start_failed;
    }
    LLOGE("codec encoder bind success type=%u", codec_type);
    ret = luat_audio_data_codec_bind(&ctx->codec_decoder, luat_audio_data_codec_find(codec_type), NULL);
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("codec decoder bind failed type=%u ret=%d", codec_type, ret);
        luat_audio_data_codec_unbind(&ctx->codec_encoder);
        goto start_failed;
    }

    ret = ctx->codec_encoder.opts->init(&ctx->codec_encoder, 1);
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("codec encoder init failed type=%u ret=%d", codec_type, ret);
        luat_audio_data_codec_unbind(&ctx->codec_encoder);
        luat_audio_data_codec_unbind(&ctx->codec_decoder);
        goto start_failed;
    }

    ret = ctx->codec_decoder.opts->init(&ctx->codec_decoder, 0);
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("codec decoder init failed type=%u ret=%d", codec_type, ret);
        luat_audio_data_codec_unbind(&ctx->codec_encoder);
        luat_audio_data_codec_unbind(&ctx->codec_decoder);
        goto start_failed;
    }


    if (voip_alloc_buffers(ctx) < 0) {
        LLOGE("voip buffer alloc failed");
        goto start_failed;
    }


    uint16_t jb_depth = ctx->config.jitter_depth ? ctx->config.jitter_depth : VOIP_JB_DEPTH_DEFAULT;
    ctx->jb = voip_jb_create(jb_depth, VOIP_JB_DEFAULT_MAX_PENDING, ctx->frame_samples);
    if (!ctx->jb) {
        LLOGE("jitter buffer create failed");
        goto start_failed;
    }

    /* Disable AEC in bridge mode - pure digital relay needs no echo cancellation */
#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->audio_mode == VOIP_AUDIO_MODE_BRIDGE) {
        ctx->config.aec_enable = 0;
        ctx->config.aec_denoise = 0;
        LLOGI("Bridge mode: AEC disabled");
    }
#endif

    if (voip_aec_init(ctx) != 0) {
        goto start_failed;
    }
    
    voip_rtp_tx_state_init(&ctx->rtp_tx, ctx->rtp_payload_type, sample_rate, ptime);


    int adapter_index = ctx->config.adapter;
    luat_ip_addr_t remote_ip = {0};
    network_ctrl_t *netc;
    if (adapter_index < 0) adapter_index = NW_ADAPTER_INDEX_LWIP_GPRS;
    netc = network_alloc_ctrl((uint8_t)adapter_index);
    if (!netc) {
        LLOGE("network alloc ctrl failed");
        goto start_failed;
    }
    ctx->netc = netc;
    network_init_ctrl(netc, NULL, voip_net_cb, ctx);
    network_set_base_mode(netc, 0 /* UDP */, 0, 0, 0, 0, 0);
    if (ctx->config.local_port) {
        network_set_local_port(netc, ctx->config.local_port);
    }
    ipaddr_aton(ctx->config.remote_ip, &remote_ip);
    if (!network_ip_is_vaild(&remote_ip)) {
        LLOGE("invalid remote ip: %s", ctx->config.remote_ip);
        goto start_failed;
    }
    ret = network_connect(netc, NULL, 0, &remote_ip, ctx->config.remote_port, 5000);
    if (ret < 0) {
        LLOGE("udp connect failed: %d", ret);
        goto start_failed;
    }
    

    if (
#ifdef LUAT_USE_VOIP_BRIDGE
        ctx->audio_mode != VOIP_AUDIO_MODE_BRIDGE
#else
        1
#endif
    ) {
        if (voip_audio_backend_start(ctx, sample_rate) != 0) {
            goto start_failed;
        }
    }


    uint32_t stats_ms = ctx->config.stats_interval_ms ? ctx->config.stats_interval_ms : VOIP_STATS_INTERVAL_DEFAULT;
    if (stats_ms > 0) {
        luat_rtos_timer_start(ctx->stats_timer, stats_ms, 1, voip_stats_timer_cb, NULL);
    }


#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->bridge_mutex) luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
#endif
    ctx->state = VOIP_STATE_RUNNING;
#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
#endif
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_media_started();
#endif
    voip_notify_lua(VOIP_CB_STATE, VOIP_STATE_RUNNING);
    return 0;

start_failed:
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_stop("voip_stopped");
#endif
    ctx->state = VOIP_STATE_ERROR;
    voip_notify_lua(VOIP_CB_STATE, VOIP_STATE_ERROR);
    voip_cleanup(ctx);
    ctx->state = VOIP_STATE_IDLE;
    voip_notify_lua(VOIP_CB_STATE, VOIP_STATE_IDLE);
    return -1;
}

static void voip_session_stop(voip_ctx_t *ctx, int notify_idle)
{
    if (ctx->state == VOIP_STATE_IDLE) {
        return;
    }

#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->bridge_mutex) luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
#endif
    ctx->state = VOIP_STATE_STOPPING;
#ifdef LUAT_USE_VOIP_BRIDGE
    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
#endif
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_stop("voip_stopped");
#endif
    voip_cleanup(ctx);
    ctx->state = VOIP_STATE_IDLE;
    if (notify_idle) {
        voip_notify_lua(VOIP_CB_STATE, VOIP_STATE_IDLE);
    }
}

static int voip_runtime_init(voip_ctx_t *ctx)
{
    int ret;

    if (ctx->task_handle) {
        return 0;
    }

    ctx->state = VOIP_STATE_IDLE;
    luat_rtos_timer_create(&ctx->stats_timer);
#ifdef LUAT_USE_VOIP_BRIDGE
    luat_rtos_timer_create(&ctx->bridge_tone_timer);
    if (!ctx->bridge_mutex && luat_rtos_mutex_create(&ctx->bridge_mutex) != 0) {
        LLOGE("bridge mutex create failed");
        if (ctx->stats_timer) { luat_rtos_timer_delete(ctx->stats_timer); ctx->stats_timer = NULL; }
        if (ctx->bridge_tone_timer) { luat_rtos_timer_delete(ctx->bridge_tone_timer); ctx->bridge_tone_timer = NULL; }
        return -2;
    }
#endif

    ret = luat_rtos_task_create(&ctx->task_handle, 8 * 1024, 50, "voip", voip_task_entry, ctx, 32);
    if (ret != 0) {
        LLOGE("voip task create failed: %d", ret);
        ctx->state = VOIP_STATE_IDLE;
        if (ctx->stats_timer) { luat_rtos_timer_delete(ctx->stats_timer); ctx->stats_timer = NULL; }
#ifdef LUAT_USE_VOIP_BRIDGE
        if (ctx->bridge_tone_timer) { luat_rtos_timer_delete(ctx->bridge_tone_timer); ctx->bridge_tone_timer = NULL; }
#endif
        return -2;
    }

    return 0;
}

/* ======================== VOIP TASK ======================== */

static void voip_task_entry(void *param)
{
    voip_ctx_t *ctx = (voip_ctx_t *)param;
    luat_event_t event;

    LLOGD("voip task started");
    while (1) {
        int ret = luat_rtos_event_recv(ctx->task_handle, 0, &event, NULL, (uint32_t)LUAT_WAIT_FOREVER);
        if (ret != 0) continue;
        switch (event.id) {
        case VOIP_EVENT_START:
            if (ctx->state == VOIP_STATE_IDLE || ctx->state == VOIP_STATE_STARTING) {
                LLOGD("voip start event");
                voip_session_start(ctx);
            }
            break;

        case VOIP_EVENT_STOP:
            if (ctx->state == VOIP_STATE_RUNNING || ctx->state == VOIP_STATE_STARTING || ctx->state == VOIP_STATE_ERROR) {
                voip_session_stop(ctx, 1);
            }
            break;

        case VOIP_EVENT_MIC_DATA:
            if (ctx->state != VOIP_STATE_RUNNING) {
                break;
            }
            if (event.param1 < VOIP_MIC_SLOT_COUNT && event.param3 == ctx->mic_generation[event.param1]) {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
                voip_do_tx(ctx, ctx->mic_buf[event.param1],
                        ctx->mic_render_seq[event.param1], ctx->mic_capture_seq[event.param1],
                        ctx->mic_capture_tick_ms[event.param1]);
#else
                voip_do_tx(ctx, ctx->mic_buf[event.param1], 0, 0, 0);
#endif
            } else if (event.param1 < VOIP_MIC_SLOT_COUNT) {
                ctx->dropped_mic_events++;
                if (ctx->trace_on) {
                    LLOGW("drop stale mic frame idx=%u gen=%u current=%u", (unsigned)event.param1, (unsigned)event.param3, (unsigned)ctx->mic_generation[event.param1]);
                }
            }
#ifndef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            if (ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
                voip_fill_play_slot(ctx, (uint8_t)event.param2);
            }
#endif
            break;
        case VOIP_EVENT_SPK_DONE:
            if (ctx->state != VOIP_STATE_RUNNING) {
                break;
            }
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            if (event.param1 >= ctx->play_slot_count) break;
            if (ctx->render_refill_seq && event.param2 != ctx->render_refill_seq + 1) {
                ctx->aec_sync_fault = 1;
            }
            ctx->render_refill_seq = event.param2;
            ctx->last_completed_slot = (uint8_t)event.param1;
#else
            ctx->last_completed_slot = (ctx->last_completed_slot + 1) % ctx->play_slot_count;
#endif
            voip_fill_play_slot(ctx, ctx->last_completed_slot);
            break;

        case VOIP_EVENT_RX_DATA:
            if (ctx->state == VOIP_STATE_RUNNING) {
                voip_do_rx(ctx);
            }
            break;

        case VOIP_EVENT_STATS_TICK:
            if (ctx->state == VOIP_STATE_RUNNING) {
                voip_notify_lua(VOIP_CB_STATS, 0);
            }
            break;

#ifdef LUAT_USE_VOIP_BRIDGE
        case VOIP_EVENT_BRIDGE_TX:
            if (ctx->state != VOIP_STATE_RUNNING) {
                break;
            }
            if (ctx->audio_mode == VOIP_AUDIO_MODE_BRIDGE && ctx->bridge_tx_buf) {
                while (1) {
                    if (ctx->bridge_mutex) luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
                    if (ctx->bridge_tx_count < ctx->frame_samples) {
                        if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
                        break;
                    }
                    for (uint16_t i = 0; i < ctx->frame_samples; i++) {
                        ctx->rx_pcm_buf[i] = ctx->bridge_tx_buf[ctx->bridge_tx_read_idx];
                        ctx->bridge_tx_read_idx = (ctx->bridge_tx_read_idx + 1) % VOIP_BRIDGE_BUF_SAMPLES;
                    }
                    ctx->bridge_tx_count -= ctx->frame_samples;
                    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
                    voip_do_tx(ctx, ctx->rx_pcm_buf, 0, 0, 0);
                }
            }
            break;

        case VOIP_EVENT_BRIDGE_TONE:
            voip_do_bridge_tone(ctx);
            break;
#endif

        default:
            break;
        }
    }
}

/* ======================== Lua 回调 handler ======================== */

/*
 * 在 Lua 主线程中执行，由 msgbus 分发。
 * 根据 msg->arg1 (cb_type) 调用对应的 Lua 回调。
 */
static int voip_lua_cb_handler(lua_State *L, void *ptr)
{
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    lua_pop(L, 1);

    voip_ctx_t *ctx = &g_voip_ctx;
    int cb_type = msg->arg1;

    if (cb_type == VOIP_CB_STATE) {
        if (ctx->cb_state_ref == 0) goto done;
        lua_geti(L, LUA_REGISTRYINDEX, ctx->cb_state_ref);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); goto done; }

        /* state string */
        const char *state_str;
        switch (msg->arg2) {
        case VOIP_STATE_RUNNING:  state_str = "started"; break;
        case VOIP_STATE_IDLE:     state_str = "stopped"; break;
        case VOIP_STATE_ERROR:    state_str = "error"; break;
        default:                  state_str = "unknown"; break;
        }
        lua_pushstring(L, state_str);
        lua_call(L, 1, 0);
    }
    else if (cb_type == VOIP_CB_STATS) {
        if (ctx->cb_stats_ref == 0) goto done;
        lua_geti(L, LUA_REGISTRYINDEX, ctx->cb_stats_ref);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); goto done; }

        /* 构建统计 table */
        lua_newtable(L);
        lua_pushinteger(L, ctx->stats.tx_packets);  lua_setfield(L, -2, "tx_packets");
        lua_pushinteger(L, ctx->stats.tx_bytes);     lua_setfield(L, -2, "tx_bytes");
        lua_pushinteger(L, ctx->stats.rx_packets);   lua_setfield(L, -2, "rx_packets");
        lua_pushinteger(L, ctx->stats.rx_bytes);     lua_setfield(L, -2, "rx_bytes");
        lua_pushinteger(L, ctx->stats.rx_parse_fail); lua_setfield(L, -2, "rx_parse_fail");
        lua_pushinteger(L, ctx->stats.rx_bad_payload); lua_setfield(L, -2, "rx_bad_payload");
        lua_pushinteger(L, ctx->stats.rx_lost);      lua_setfield(L, -2, "rx_lost");
        lua_pushinteger(L, ctx->stats.rx_out_of_order); lua_setfield(L, -2, "rx_out_of_order");
        lua_pushinteger(L, ctx->stats.jb_played);    lua_setfield(L, -2, "jb_played");
        lua_pushinteger(L, ctx->stats.jb_silence);   lua_setfield(L, -2, "jb_silence");
        lua_pushstring(L, voip_aec_mode_name(ctx));   lua_setfield(L, -2, "aec_mode");
        lua_pushinteger(L, ctx->stats.aec_ref_underflow); lua_setfield(L, -2, "aec_ref_underflow");
        lua_pushinteger(L, ctx->stats.aec_ref_overflow);  lua_setfield(L, -2, "aec_ref_overflow");
        lua_pushinteger(L, ctx->stats.aec_sync_resets);   lua_setfield(L, -2, "aec_sync_resets");
        lua_pushinteger(L, ctx->stats.aec_mic_clipped);   lua_setfield(L, -2, "aec_mic_clipped");
        lua_pushinteger(L, ctx->stats.aec_out_clipped);   lua_setfield(L, -2, "aec_out_clipped");
        lua_pushinteger(L, ctx->stats.aec_max_process_us); lua_setfield(L, -2, "aec_max_process_us");
        lua_pushinteger(L, ctx->stats.aec_seq_skew);      lua_setfield(L, -2, "aec_seq_skew");
        lua_call(L, 1, 0);
    }
    else if (cb_type == VOIP_CB_ERROR) {
        if (ctx->cb_error_ref == 0) goto done;
        lua_geti(L, LUA_REGISTRYINDEX, ctx->cb_error_ref);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); goto done; }
        lua_pushstring(L, "internal_error");
        lua_call(L, 1, 0);
    }
#ifdef LUAT_USE_VOIP_RECORD
    else if (cb_type == VOIP_CB_RECORD) {
        voip_record_status_t status;
        const char *event_name;
        if (ctx->cb_record_ref == 0) goto done;
        lua_geti(L, LUA_REGISTRYINDEX, ctx->cb_record_ref);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); goto done; }
        switch (msg->arg2) {
        case VOIP_RECORD_EVENT_STARTED: event_name = "started"; break;
        case VOIP_RECORD_EVENT_STOPPED: event_name = "stopped"; break;
        default: event_name = "error"; break;
        }
        luat_voip_record_get_status(&status);
        lua_pushstring(L, event_name);
        lua_newtable(L);
        lua_pushstring(L, status.path); lua_setfield(L, -2, "path");
        if (status.reason[0]) lua_pushstring(L, status.reason); else lua_pushnil(L);
        lua_setfield(L, -2, "reason");
        lua_pushinteger(L, status.bytes); lua_setfield(L, -2, "bytes");
        lua_pushinteger(L, status.duration_ms); lua_setfield(L, -2, "duration_ms");
        lua_pushinteger(L, status.dropped_frames); lua_setfield(L, -2, "dropped_frames");
        lua_call(L, 2, 0);
    }
#endif

done:
    lua_pushinteger(L, 0);
    return 1;
}

/* ======================== 公共 API ======================== */

int voip_start(const voip_config_t *config)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    int ret;

    if (!config) {
        return -3;
    }

    if (ctx->state != VOIP_STATE_IDLE) {
        LLOGW("voip already running, stop first");
        return -1;
    }

    ret = voip_runtime_init(ctx);
    if (ret != 0) {
        return ret;
    }

    /* 拷贝配置 */
    memcpy(&ctx->config, config, sizeof(voip_config_t));
    ctx->state = VOIP_STATE_STARTING;
    luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_START, 0, 0, 0, 0);

    return 0;
}

int voip_stop(void)
{
    voip_ctx_t *ctx = &g_voip_ctx;

    if (ctx->state != VOIP_STATE_RUNNING && ctx->state != VOIP_STATE_STARTING) {
        return 0;
    }

    if (ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_STOP, 0, 0, 0, 0);
    }
    return 0;
}

voip_state_t voip_get_state(void)
{
    return g_voip_ctx.state;
}

void voip_get_stats(voip_stats_t *out)
{
    if (out) {
        memcpy(out, &g_voip_ctx.stats, sizeof(voip_stats_t));
    }
}

int voip_is_running(void)
{
    return g_voip_ctx.state == VOIP_STATE_RUNNING ? 1 : 0;
}

#ifdef LUAT_USE_VOIP_RECORD
static int voip_record_path_valid(const char *path)
{
    size_t len;
    if (!path || !path[0]) return 0;
    len = strlen(path);
    if (len >= VOIP_RECORD_PATH_MAX || len < 5) return 0;
    return path[len - 4] == '.' &&
           (path[len - 3] == 'w' || path[len - 3] == 'W') &&
           (path[len - 2] == 'a' || path[len - 2] == 'A') &&
           (path[len - 1] == 'v' || path[len - 1] == 'V');
}

int voip_record_start(const char *path, uint32_t max_seconds)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    int media_running;
    int ret;
    if (!voip_record_path_valid(path)) return -1;
    if (ctx->state != VOIP_STATE_STARTING && ctx->state != VOIP_STATE_RUNNING) return -2;
    if ((ctx->config.sample_rate && ctx->config.sample_rate != 8000) ||
        (ctx->config.ptime && ctx->config.ptime != 20)) return -2;
    if (luat_voip_record_init(voip_record_notify) != 0) return -4;
    media_running = (ctx->state == VOIP_STATE_RUNNING);
    ret = luat_voip_record_start(path, max_seconds, media_running);
    if (ret == -2) return -3;
    if (ret != 0) return -4;
    return 0;
}

int voip_record_stop(void)
{
    return luat_voip_record_stop("manual");
}

void voip_record_get_status(voip_record_status_t *status)
{
    luat_voip_record_get_status(status);
}
#endif


#ifdef LUAT_USE_VOIP_BRIDGE
int voip_set_audio_mode(voip_audio_mode_t mode)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    if (ctx->state != VOIP_STATE_IDLE) {
        LLOGW("voip_set_audio_mode: must be called in IDLE state");
        return -1;
    }
    if (mode != VOIP_AUDIO_MODE_I2S && mode != VOIP_AUDIO_MODE_BRIDGE) {
        return -2;
    }
    ctx->audio_mode = mode;
    return 0;
}

int voip_bridge_tone(int on)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    uint32_t interval;

    if (!on) {
        if (ctx->bridge_tone_timer) {
            luat_rtos_timer_stop(ctx->bridge_tone_timer);
        }
        if (ctx->bridge_tone_on) {
            LLOGI("voip bridge tone stopped");
        }
        ctx->bridge_tone_on = 0;
        ctx->bridge_tone_pos = 0;
        return 0;
    }

    if (ctx->state != VOIP_STATE_RUNNING || ctx->audio_mode != VOIP_AUDIO_MODE_BRIDGE) {
        return -1;
    }
    if (!ctx->bridge_tone_timer) {
        if (luat_rtos_timer_create(&ctx->bridge_tone_timer) != 0) {
            return -2;
        }
    }
    interval = ctx->config.ptime ? ctx->config.ptime : VOIP_FRAME_MS_DEFAULT;
    ctx->bridge_tone_pos = 0;
    ctx->bridge_tone_on = 1;
    if (luat_rtos_timer_start(ctx->bridge_tone_timer, interval, 1, voip_bridge_tone_timer_cb, NULL) != 0) {
        ctx->bridge_tone_on = 0;
        return -3;
    }
    LLOGI("voip bridge tone started interval=%u", (unsigned)interval);
    luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_BRIDGE_TONE, 0, 0, 0, 0);
    return 0;
}

int voip_bridge_pcm_in(const int16_t *pcm, uint16_t samples)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    uint16_t consumed = 0;

    if (!pcm || samples == 0) {
        return 0;
    }
    if (!ctx->bridge_mutex) {
        return -1;
    }
    luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
    if (ctx->state != VOIP_STATE_RUNNING || ctx->audio_mode != VOIP_AUDIO_MODE_BRIDGE || !ctx->bridge_tx_buf) {
        luat_rtos_mutex_unlock(ctx->bridge_mutex);
        return -1;
    }
    for (uint16_t i = 0; i < samples; i++) {
        if (ctx->bridge_tx_count >= VOIP_BRIDGE_BUF_SAMPLES) {
            break;
        }
        ctx->bridge_tx_buf[ctx->bridge_tx_write_idx] = pcm[i];
        ctx->bridge_tx_write_idx = (ctx->bridge_tx_write_idx + 1) % VOIP_BRIDGE_BUF_SAMPLES;
        ctx->bridge_tx_count++;
        consumed++;
    }
    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
    if (consumed > 0 && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_BRIDGE_TX, 0, 0, 0, 0);
    }
    return (int)consumed;
}

int voip_bridge_pcm_out(int16_t *pcm, uint16_t max_samples)
{
    voip_ctx_t *ctx = &g_voip_ctx;
    uint16_t to_read = 0;

    if (!pcm || max_samples == 0) {
        return 0;
    }
    if (!ctx->bridge_mutex) {
        return -1;
    }
    luat_rtos_mutex_lock(ctx->bridge_mutex, LUAT_WAIT_FOREVER);
    if (ctx->state != VOIP_STATE_RUNNING || ctx->audio_mode != VOIP_AUDIO_MODE_BRIDGE || !ctx->bridge_rx_buf) {
        luat_rtos_mutex_unlock(ctx->bridge_mutex);
        return -1;
    }
    to_read = (ctx->bridge_rx_count < max_samples) ? ctx->bridge_rx_count : max_samples;
    for (uint16_t i = 0; i < to_read; i++) {
        pcm[i] = ctx->bridge_rx_buf[ctx->bridge_rx_read_idx];
        ctx->bridge_rx_read_idx = (ctx->bridge_rx_read_idx + 1) % VOIP_BRIDGE_BUF_SAMPLES;
        ctx->bridge_rx_count--;
    }
    if (ctx->bridge_mutex) luat_rtos_mutex_unlock(ctx->bridge_mutex);
#ifdef LUAT_USE_VOIP_RECORD
    luat_voip_record_tap_rx(pcm, to_read);
#endif
    return (int)to_read;
}
#endif
