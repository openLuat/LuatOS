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
#include "luat_i2s.h"
#include "luat_rtp.h"

#include "g711_codec/g711_codec.h"

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
static int  voip_start_audio(voip_ctx_t *ctx, uint32_t sample_rate);
static void voip_stop_audio(voip_ctx_t *ctx);
static void voip_cleanup(voip_ctx_t *ctx);
static void voip_reset_session_state(voip_ctx_t *ctx);
static int  voip_session_start(voip_ctx_t *ctx);
static void voip_session_stop(voip_ctx_t *ctx, int notify_idle);
static int  voip_runtime_init(voip_ctx_t *ctx);
static void voip_rtp_tx_state_init(voip_rtp_tx_state_t *state, uint8_t payload_type, uint32_t clock_rate, uint16_t ptime);
static int  voip_pack_rtp_packet(voip_rtp_tx_state_t *state, const uint8_t *payload, uint16_t payload_len, uint8_t *out_buf, uint16_t out_max_len, uint16_t *out_len);
static int  voip_parse_rtp_packet(const uint8_t *data, uint16_t len, voip_rtp_parsed_t *out);

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

/* ======================== 定时器回调 ======================== */

static LUAT_RT_RET_TYPE voip_stats_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    voip_ctx_t *ctx = &g_voip_ctx;
    if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_STATS_TICK, 0, 0, 0, 0);
    }
}

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

/* ======================== I2S 麦克风回调 (真机) ======================== */
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
            ctx->last_completed_slot = (ctx->last_completed_slot + 1) % ctx->play_slot_count;
            luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_MIC_DATA, mic_idx, ctx->last_completed_slot, generation, 0);
            ctx->mic_write_idx = (ctx->mic_write_idx + 1) % VOIP_MIC_SLOT_COUNT;
        }
    }

    return 0;
}
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
    voip_pop_play_frame(ctx, ctx->duplex_play_buf + slot_idx * ctx->frame_samples);
    if (ctx->trace_on) {
        LLOGD("fill play slot %u", slot_idx);
    }
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
static void voip_do_tx(voip_ctx_t *ctx, const int16_t *mic_pcm)
{
    if (!ctx->netc) return;
    int16_t *pcm = ctx->tx_pcm_buf;

    if (!mic_pcm) {
        return;
    }

    memcpy(pcm, mic_pcm, ctx->frame_bytes);

    /* G.711 编码 */
    uint32_t out_len = 0;
    int ret = g711_encoder_get_data(ctx->encoder, pcm, ctx->frame_samples,
                                    ctx->tx_g711_buf, &out_len);
    if (ret != 1 || out_len == 0) {
        LLOGW("g711 encode failed");
        return;
    }
    /* RTP 打包 */
    uint16_t rtp_len = 0;
    ret = voip_pack_rtp_packet(&ctx->rtp_tx, ctx->tx_g711_buf, (uint16_t)out_len,
                               ctx->rtp_packet_buf, (uint16_t)(VOIP_RTP_HEADER_LEN + ctx->frame_samples), &rtp_len);
    if (ret < 0) return;

    /* UDP 发送 */
    network_ctrl_t *netc = (network_ctrl_t *)ctx->netc;
    /* 已在 connect 时设置好 remote，直接发 */
    uint8_t tx_len = 0;
    network_tx(netc, ctx->rtp_packet_buf, rtp_len, 0, NULL, 0, &tx_len, 0);
    ctx->stats.tx_packets++;
    ctx->stats.tx_bytes += rtp_len;
}

/* RX: 从 UDP socket 读取所有待处理数据 → RTP 解析 → G.711 解码 → JB push */
static void voip_do_rx(voip_ctx_t *ctx)
{
    if (!ctx->netc) return;

    network_ctrl_t *netc = (network_ctrl_t *)ctx->netc;
    luat_ip_addr_t remote_ip = {0};
    uint16_t remote_port = 0;

    while (1) {

        int rd = network_socket_receive(netc, ctx->udp_rx_buf, ctx->udp_rx_buf_size,
                                        0, &remote_ip, &remote_port);
        // LLOGE("voip_do_rx: got udp packet, len=%d", rd);
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

        /* G.711 解码 */
        uint32_t pcm_len = 0;
        uint32_t used = 0;
        ret = g711_decoder_get_data(ctx->decoder, parsed.payload, parsed.payload_len,
                                    ctx->rx_pcm_buf, &pcm_len, &used);
        if (ret == 1 && pcm_len > 0) {
            voip_jb_push(ctx->jb, parsed.sequence, ctx->rx_pcm_buf);
        }
        else {
            // ctx->stats.rx_bad_payload++;
            LLOGE("g711 decode failed, ret=%d pcm_len=%u used=%u", ret, pcm_len, used);
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
    ctx->udp_rx_buf_size = VOIP_RTP_HEADER_LEN + fs + 64; /* 余量 */
    ctx->udp_rx_buf     = (uint8_t *)luat_heap_calloc(1, ctx->udp_rx_buf_size);

    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        ctx->mic_buf[index] = (int16_t *)luat_heap_calloc(1, fb);
    }

    if (!ctx->tx_pcm_buf || !ctx->tx_g711_buf || !ctx->rtp_packet_buf ||
        !ctx->rx_pcm_buf || !ctx->duplex_play_buf || !ctx->udp_rx_buf) {
        return -1;
    }

    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        if (!ctx->mic_buf[index]) {
            return -1;
        }
    }

    return 0;
}

static int voip_start_audio(voip_ctx_t *ctx, uint32_t sample_rate)
{
    luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
    if (!audio_conf) {
        LLOGE("audio config not found");
        return -1;
    }

    luat_i2s_conf_t *i2s = luat_i2s_get_config((uint8_t)audio_conf->codec_conf.i2s_id);
    if (!i2s) {
        LLOGE("i2s config not found");
        return -1;
    }

    if (luat_i2s_save_old_config(audio_conf->codec_conf.i2s_id) == 0) {
        ctx->i2s_config_saved = 1;
    }

    i2s->is_full_duplex = 1;
    i2s->cb_rx_len = ctx->frame_bytes;
    i2s->luat_i2s_event_callback = voip_i2s_cb;

    /* 预填充静音，不从 JB pop，避免在 JB 未就绪时推进 expected_seq */
    memset(ctx->duplex_play_buf, 0, ctx->frame_bytes * ctx->play_slot_count);

    if (luat_audio_record_and_play(ctx->config.multimedia_id,
                                   sample_rate,
                                   (const uint8_t *)ctx->duplex_play_buf,
                                   ctx->frame_bytes,
                                   ctx->play_slot_count) != 0) {
        LLOGE("start duplex audio failed");
        if (ctx->i2s_config_saved) {
            luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
            ctx->i2s_config_saved = 0;
        }
        return -1;
    }

    ctx->audio_backend = VOIP_AUDIO_BACKEND_DUPLEX;
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

    if (ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
        luat_audio_record_stop(ctx->config.multimedia_id);
        if (ctx->i2s_config_saved) {
            luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
            if (audio_conf) {
                luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
            }
            ctx->i2s_config_saved = 0;
        }
    }

    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    ctx->audio_started = 0;
}

static void voip_free_buffers(voip_ctx_t *ctx)
{
    if (ctx->tx_pcm_buf)      { luat_heap_free(ctx->tx_pcm_buf);      ctx->tx_pcm_buf = NULL; }
    if (ctx->tx_g711_buf)     { luat_heap_free(ctx->tx_g711_buf);     ctx->tx_g711_buf = NULL; }
    if (ctx->rtp_packet_buf)  { luat_heap_free(ctx->rtp_packet_buf);  ctx->rtp_packet_buf = NULL; }
    if (ctx->rx_pcm_buf)      { luat_heap_free(ctx->rx_pcm_buf);      ctx->rx_pcm_buf = NULL; }
    if (ctx->duplex_play_buf) { luat_heap_free(ctx->duplex_play_buf); ctx->duplex_play_buf = NULL; }
    if (ctx->udp_rx_buf)      { luat_heap_free(ctx->udp_rx_buf);      ctx->udp_rx_buf = NULL; }
    for (uint8_t index = 0; index < VOIP_MIC_SLOT_COUNT; index++) {
        if (ctx->mic_buf[index]) {
            luat_heap_free(ctx->mic_buf[index]);
            ctx->mic_buf[index] = NULL;
        }
    }
}

static void voip_cleanup(voip_ctx_t *ctx)
{
    /* 停止定时器 */
    if (ctx->stats_timer) { luat_rtos_timer_stop(ctx->stats_timer); }
    
    /* 停止音频 */
    voip_stop_audio(ctx);

    /* 关闭网络 */
    if (ctx->netc) {
        network_socket_force_close((network_ctrl_t *)ctx->netc);
        network_release_ctrl((network_ctrl_t *)ctx->netc);
        ctx->netc = NULL;
    }


    /* 释放 codec */
    if (ctx->encoder) { g711_encoder_destroy(ctx->encoder); ctx->encoder = NULL; }
    if (ctx->decoder) { g711_decoder_destroy(ctx->decoder); ctx->decoder = NULL; }

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
    ctx->play_slot_count = VOIP_DUPLEX_SLOT_COUNT;
    ctx->mic_write_idx = 0;
    ctx->last_completed_slot = ctx->play_slot_count - 1;
    ctx->trace_on = 0;
    ctx->dropped_mic_events = 0;
    memset(ctx->mic_generation, 0, sizeof(ctx->mic_generation));
    memset(&ctx->stats, 0, sizeof(ctx->stats));
}

static int voip_session_start(voip_ctx_t *ctx)
{
    uint16_t ptime = ctx->config.ptime ? ctx->config.ptime : VOIP_FRAME_MS_DEFAULT;
    uint32_t sample_rate = ctx->config.sample_rate ? ctx->config.sample_rate : VOIP_SAMPLE_RATE_DEFAULT;

    voip_reset_session_state(ctx);
    ctx->frame_samples = (uint16_t)(sample_rate * ptime / 1000);
    ctx->frame_bytes = ctx->frame_samples * 2;
    LLOGE("voip config: remote=%s:%d codec=%d ptime=%d",
          ctx->config.remote_ip, ctx->config.remote_port, ctx->config.codec,
          ptime);
    LLOGE("voio origin: samples=%d", ctx->config.sample_rate);
    LLOGE("voio frame: samples=%d bytes=%d", ctx->frame_samples, ctx->frame_bytes);

    if (ctx->config.codec == VOIP_CODEC_PCMA) {
        ctx->g711_type = LUAT_MULTIMEDIA_DATA_TYPE_ALAW;
        ctx->rtp_payload_type = VOIP_RTP_PT_PCMA;
    } else {
        ctx->g711_type = LUAT_MULTIMEDIA_DATA_TYPE_ULAW;
        ctx->rtp_payload_type = VOIP_RTP_PT_PCMU;
    }

    if (voip_alloc_buffers(ctx) < 0) {
        LLOGE("voip buffer alloc failed");
        goto start_failed;
    }

    ctx->encoder = g711_encoder_create(ctx->g711_type);
    ctx->decoder = g711_decoder_create(ctx->g711_type);
    if (!ctx->encoder || !ctx->decoder) {
        LLOGE("g711 codec create failed");
        goto start_failed;
    }

    {
        uint16_t jb_depth = ctx->config.jitter_depth ? ctx->config.jitter_depth : VOIP_JB_DEPTH_DEFAULT;
        ctx->jb = voip_jb_create(jb_depth, VOIP_JB_DEFAULT_MAX_PENDING, ctx->frame_samples);
        if (!ctx->jb) {
            LLOGE("jitter buffer create failed");
            goto start_failed;
        }
    }

    voip_rtp_tx_state_init(&ctx->rtp_tx, ctx->rtp_payload_type, sample_rate, ptime);

    {
        int adapter_index = network_get_last_register_adapter();
        luat_ip_addr_t remote_ip = {0};
        network_ctrl_t *netc;
        int ret;

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
    }

    LLOGE("udp socket created and connected to %s:%d",
          ctx->config.remote_ip, ctx->config.remote_port);
    if (voip_start_audio(ctx, sample_rate) != 0) {
        goto start_failed;
    }
    LLOGE("audio started: multimedia_id=%d sample_rate=%d backend=%d", ctx->config.multimedia_id, sample_rate, ctx->audio_backend);

    {
        uint32_t stats_ms = ctx->config.stats_interval_ms ? ctx->config.stats_interval_ms : VOIP_STATS_INTERVAL_DEFAULT;
        if (stats_ms > 0) {
            luat_rtos_timer_start(ctx->stats_timer, stats_ms, 1, voip_stats_timer_cb, NULL);
        }
    }

    ctx->state = VOIP_STATE_RUNNING;
    voip_notify_lua(VOIP_CB_STATE, VOIP_STATE_RUNNING);
    LLOGI("voip running: %s:%d codec=%d ptime=%d",
          ctx->config.remote_ip, ctx->config.remote_port,
          ctx->config.codec, ptime);
    return 0;

start_failed:
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

    ctx->state = VOIP_STATE_STOPPING;
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

    ret = luat_rtos_task_create(&ctx->task_handle, 4096, 50, "voip", voip_task_entry, ctx, 32);
    if (ret != 0) {
        LLOGE("voip task create failed: %d", ret);
        ctx->state = VOIP_STATE_IDLE;
        if (ctx->stats_timer) { luat_rtos_timer_delete(ctx->stats_timer); ctx->stats_timer = NULL; }
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
                LLOGD("voip stop event");
                voip_session_stop(ctx, 1);
            }
            break;

        case VOIP_EVENT_MIC_DATA:
            if (ctx->state != VOIP_STATE_RUNNING) {
                break;
            }
            if (event.param1 < VOIP_MIC_SLOT_COUNT && event.param3 == ctx->mic_generation[event.param1]) {
                voip_do_tx(ctx, ctx->mic_buf[event.param1]);
            } else if (event.param1 < VOIP_MIC_SLOT_COUNT) {
                ctx->dropped_mic_events++;
                if (ctx->trace_on) {
                    LLOGW("drop stale mic frame idx=%u gen=%u current=%u", (unsigned)event.param1, (unsigned)event.param3, (unsigned)ctx->mic_generation[event.param1]);
                }
            }
            if (ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
                voip_fill_play_slot(ctx, (uint8_t)event.param2);
            }
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
        lua_pushinteger(L, ctx->stats.rx_lost);      lua_setfield(L, -2, "rx_lost");
        lua_pushinteger(L, ctx->stats.rx_out_of_order); lua_setfield(L, -2, "rx_out_of_order");
        lua_pushinteger(L, ctx->stats.jb_played);    lua_setfield(L, -2, "jb_played");
        lua_pushinteger(L, ctx->stats.jb_silence);   lua_setfield(L, -2, "jb_silence");
        lua_call(L, 1, 0);
    }
    else if (cb_type == VOIP_CB_ERROR) {
        if (ctx->cb_error_ref == 0) goto done;
        lua_geti(L, LUA_REGISTRYINDEX, ctx->cb_error_ref);
        if (!lua_isfunction(L, -1)) { lua_pop(L, 1); goto done; }
        lua_pushstring(L, "internal_error");
        lua_call(L, 1, 0);
    }

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
