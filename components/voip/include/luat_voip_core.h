/*
 * luat_voip_core.h - VoIP 核心引擎
 *
 * 职责：
 * 1. 管理 UDP RTP socket 收发
 * 2. G.711 编解码
 * 3. Jitter Buffer 管理
 * 4. 音频 I/O（上行采集 + 下行播放）
 * 5. 后台 RTOS task + 定时器驱动
 * 6. 通过 msgbus 桥接回调到 Lua 层
 *
 * 首版：全局单实例，单路通话
 */

#ifndef LUAT_VOIP_CORE_H
#define LUAT_VOIP_CORE_H

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_voip_jitterbuf.h"

/* ======================== 配置 ======================== */

#define VOIP_MAX_IP_LEN         48
#define VOIP_FRAME_MS_DEFAULT   20
#define VOIP_SAMPLE_RATE_DEFAULT 8000
#define VOIP_JB_DEPTH_DEFAULT   3
#define VOIP_STATS_INTERVAL_DEFAULT 5000    /* ms */
#define VOIP_DUPLEX_SLOT_COUNT  4
#define VOIP_MIC_SLOT_COUNT     4
#define VOIP_RTP_HEADER_LEN     12
#define VOIP_RTP_PT_PCMU        0
#define VOIP_RTP_PT_PCMA        8

/* Codec 类型 */
typedef enum {
    VOIP_CODEC_PCMU = 0,
    VOIP_CODEC_PCMA = 1,
} voip_codec_type_t;

/* 用户传入的配置 */
typedef struct {
    voip_codec_type_t codec;
    uint32_t stats_interval_ms;
    uint32_t sample_rate;       /* default 8000 */
    int      adapter;
    char     remote_ip[VOIP_MAX_IP_LEN];
    uint16_t remote_port;
    uint16_t local_port;
    uint16_t jitter_depth;
    uint16_t ptime;             /* ms, default 20 */
    uint8_t  multimedia_id;     /* audio device id */
    uint8_t  aec_enable;
    uint8_t  aec_denoise;
    uint16_t aec_tail_ms;
} voip_config_t;

/* ======================== 状态 ======================== */

typedef enum {
    VOIP_STATE_IDLE = 0,
    VOIP_STATE_STARTING,
    VOIP_STATE_RUNNING,
    VOIP_STATE_STOPPING,
    VOIP_STATE_ERROR,
} voip_state_t;

/* 统计信息 */
typedef struct {
    uint32_t tx_packets;
    uint32_t tx_bytes;
    uint32_t rx_packets;
    uint32_t rx_bytes;
    uint32_t rx_parse_fail;
    uint32_t rx_bad_payload;
    uint32_t rx_lost;
    uint32_t rx_out_of_order;
    uint32_t jb_played;
    uint32_t jb_silence;
    uint16_t last_rx_seq;
    uint8_t  last_rx_seq_valid;
} voip_stats_t;

/* ======================== 事件 ======================== */

enum {
    VOIP_EVENT_START = 1,
    VOIP_EVENT_STOP,
    VOIP_EVENT_RX_DATA,     /* UDP 收到数据 */
    VOIP_EVENT_MIC_DATA,    /* I2S 采集到数据 */
    VOIP_EVENT_SPK_DONE,    /* DAC 播放完成一帧 */
    VOIP_EVENT_STATS_TICK,  /* 统计输出定时器 */
};

typedef enum {
    VOIP_AUDIO_BACKEND_NONE = 0,
    VOIP_AUDIO_BACKEND_DUPLEX,
} voip_audio_backend_t;

typedef struct {
    uint8_t  payload_type;
    uint32_t clock_rate;
    uint16_t ptime;
    uint16_t samples_per_packet;
    uint16_t seq;
    uint32_t timestamp;
    uint32_t ssrc;
} voip_rtp_tx_state_t;

typedef struct {
    uint8_t  version;
    uint8_t  padding;
    uint8_t  extension;
    uint8_t  marker;
    uint8_t  payload_type;
    uint16_t sequence;
    uint32_t timestamp;
    uint32_t ssrc;
    const uint8_t *payload;
    uint16_t payload_len;
    uint16_t header_len;
} voip_rtp_parsed_t;

/* ======================== Lua 回调事件类型 ======================== */

enum {
    VOIP_CB_STATE = 0,      /* 状态变化 */
    VOIP_CB_STATS = 1,      /* 统计数据 */
    VOIP_CB_ERROR = 2,      /* 错误 */
};

typedef struct {
    /* 配置 */
    voip_config_t config;

    /* 状态 */
    volatile voip_state_t state;
    voip_stats_t stats;

    /* RTOS */
    luat_rtos_task_handle task_handle;
    luat_rtos_timer_t stats_timer;

    /* 网络 */
    void *netc;                 /* network_ctrl_t* */

    /* RTP */
    voip_rtp_tx_state_t rtp_tx;

    /* Codec */
    void *encoder;              /* g711 encoder handle */
    void *decoder;              /* g711 decoder handle */
    uint8_t g711_type;          /* G711_TYPE_ULAW / G711_TYPE_ALAW */
    uint8_t rtp_payload_type;   /* 0=PCMU, 8=PCMA */

    /* Jitter Buffer */
    voip_jb_t *jb;

    /* 音频缓冲区 */
    uint16_t frame_samples;     /* e.g. 160 for 20ms@8kHz */
    uint16_t frame_bytes;       /* frame_samples * 2 (PCM16) */
    int16_t *tx_pcm_buf;        /* TX: PCM 编码前缓冲 */
    uint8_t *tx_g711_buf;       /* TX: G.711 编码后缓冲 */
    uint8_t *rtp_packet_buf;    /* TX: RTP 打包输出缓冲 */
    int16_t *rx_pcm_buf;        /* RX: G.711 解码后缓冲 */
    int16_t *duplex_play_buf;   /* 全双工环形播放缓冲 */
    int16_t *mic_buf[VOIP_MIC_SLOT_COUNT];
    uint8_t *udp_rx_buf;        /* UDP 收包缓冲 */
    uint16_t udp_rx_buf_size;
    uint8_t play_slot_count;
    uint8_t mic_write_idx;
    uint8_t last_completed_slot;
    uint8_t i2s_config_saved;
    uint8_t audio_started;
    uint8_t trace_on;
    voip_audio_backend_t audio_backend;
    uint32_t mic_generation[VOIP_MIC_SLOT_COUNT];
    uint32_t dropped_mic_events;

    /* AEC */
    void *aec_echo;
    void *aec_preprocess;
    int16_t *aec_out_buf;
    uint8_t aec_ready;

    /* Lua 回调引用 */
    int cb_state_ref;   /* LUA_REGISTRYINDEX ref for state callback */
    int cb_stats_ref;   /* LUA_REGISTRYINDEX ref for stats callback */
    int cb_error_ref;   /* LUA_REGISTRYINDEX ref for error callback */
} voip_ctx_t;

/* ======================== API ======================== */

/**
 * 获取全局单例上下文
 */
voip_ctx_t *voip_get_ctx(void);

/**
 * 启动 VoIP 媒体引擎
 * @param config 配置（会被拷贝，调用方可立即释放）
 * @return 0 成功, <0 失败
 */
int voip_start(const voip_config_t *config);

/**
 * 停止 VoIP 媒体引擎
 * @return 0 成功
 */
int voip_stop(void);

/**
 * 获取当前状态
 */
voip_state_t voip_get_state(void);

/**
 * 获取统计信息快照
 */
void voip_get_stats(voip_stats_t *out);

/**
 * 是否正在运行
 */
int voip_is_running(void);

#endif /* LUAT_VOIP_CORE_H */
