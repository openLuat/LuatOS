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
#include "luat_audio_data_codec.h"
#ifdef LUAT_USE_VOIP_RECORD
#include "luat_voip_record.h"
#endif
/* ======================== 配置 ======================== */

#define VOIP_MAX_IP_LEN         48
#define VOIP_FRAME_MS_DEFAULT   20
#define VOIP_SAMPLE_RATE_DEFAULT 8000
#define VOIP_JB_DEPTH_DEFAULT   3
#define VOIP_STATS_INTERVAL_DEFAULT 5000    /* ms */
#define VOIP_DUPLEX_SLOT_COUNT  4
#define VOIP_MIC_SLOT_COUNT     4
#define VOIP_AEC_REF_HISTORY_FRAMES 8
#define VOIP_RTP_HEADER_LEN     12
#define VOIP_RTP_PT_PCMU        0
#define VOIP_RTP_PT_PCMA        8

/* Codec 类型 */
typedef enum {
    VOIP_CODEC_PCMU = 0,
    VOIP_CODEC_PCMA = 1,
} voip_codec_type_t;

typedef enum {
    VOIP_AEC_MODE_SPEEX = 0,
    VOIP_AEC_MODE_BK = 1,
} voip_aec_mode_t;

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
    uint8_t  aec_mode;
    uint8_t  aec_agc;
    uint16_t aec_tail_ms;
    uint16_t aec_delay_samples;
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
    uint32_t event_send_failures; /* Cumulative notification failures across sessions. */
    uint32_t rx_lost;
    uint32_t rx_out_of_order;
    uint32_t jb_played;
    uint32_t jb_silence;
    uint32_t aec_ref_underflow;
    uint32_t aec_ref_overflow;
    uint32_t aec_sync_resets;
    uint32_t aec_mic_clipped;
    uint32_t aec_out_clipped;
    uint32_t aec_max_process_us;
#ifdef LUAT_USE_VOIP_AUDIO_PORT
    uint32_t audio_tx_commit_fail;
    uint32_t audio_tx_underrun;
    uint32_t audio_rx_dropped;
    uint32_t audio_rx_samples; /* Native per-channel sample frames, including queue drops. */
    uint32_t audio_normalized_samples;
    uint32_t audio_render_samples;
#endif
    int32_t  aec_seq_skew;
    uint8_t  aec_mode;
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
#ifdef LUAT_USE_VOIP_AUDIO_PORT
    VOIP_EVENT_RAW_MIC_DATA, /* Optional Audio V2 raw PCM queue */
#endif
#ifdef LUAT_USE_VOIP_BRIDGE
    VOIP_EVENT_BRIDGE_TX,   /* 桥接模式：外部PCM数据需要编码发送 */
    VOIP_EVENT_BRIDGE_TONE, /* 桥接模式：内部早期媒体提示音 */
#endif
};

typedef enum {
    VOIP_AUDIO_BACKEND_NONE = 0,
    VOIP_AUDIO_BACKEND_DUPLEX,
} voip_audio_backend_t;

/* 音频工作模式：I2S直接硬件；桥接固件额外支持PCM缓冲区交换。 */
typedef enum {
    VOIP_AUDIO_MODE_I2S = 0,      /* 传统I2S模式：直接控制音频硬件 */
#ifdef LUAT_USE_VOIP_BRIDGE
    VOIP_AUDIO_MODE_BRIDGE = 1,   /* 桥接模式：通过PCM缓冲区与外部交换数据 */
#endif
} voip_audio_mode_t;

#ifdef LUAT_USE_VOIP_BRIDGE
/* 桥接缓冲区大小：20ms@8kHz=160samples, 预留10帧 = 1600samples */
#define VOIP_BRIDGE_BUF_SAMPLES  1600
#define VOIP_BRIDGE_BUF_BYTES    (VOIP_BRIDGE_BUF_SAMPLES * sizeof(int16_t))
#endif

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
#ifdef LUAT_USE_VOIP_RECORD
    VOIP_CB_RECORD = 3,     /* 本地通话录音 */
#endif
};

typedef struct {
    /* 配置 */
    voip_config_t config;

    /* 状态 */
    volatile voip_state_t state;
    volatile uint32_t stop_requested;
    uint32_t audio_session;
    volatile uint32_t rx_event_state;
    volatile uint32_t event_send_failures;
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

    luat_audio_data_codec_t codec_encoder;  /* RTP encoder codec state */
    luat_audio_data_codec_t codec_decoder;  /* RTP decoder codec state */
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
#ifdef LUAT_USE_AUDIO_V2
    void *audio_v2_ctrl;        /* audio_v2 driver control, audio_v2 builds only */
#ifdef LUAT_USE_VOIP_AUDIO_PORT
    void *audio_port_state;     /* Optional raw PCM/explicit commit port */
#endif
#endif
    uint8_t trace_on;
    voip_audio_backend_t audio_backend;
    voip_audio_mode_t audio_mode;

#ifdef LUAT_USE_VOIP_BRIDGE
    volatile uint32_t tx_event_state;
    /* 桥接模式缓冲区（仅当 audio_mode == VOIP_AUDIO_MODE_BRIDGE 时有效） */
    int16_t *bridge_tx_buf;             /* 上行：外部PCM -> voip编码 -> RTP */
    int16_t *bridge_rx_buf;             /* 下行：RTP -> voip解码 -> 外部PCM */
    uint16_t bridge_tx_write_idx;     /* bridge_tx_buf 写索引 */
    uint16_t bridge_tx_read_idx;      /* bridge_tx_buf 读索引 */
    uint16_t bridge_rx_write_idx;     /* bridge_rx_buf 写索引 */
    uint16_t bridge_rx_read_idx;      /* bridge_rx_buf 读索引 */
    uint16_t bridge_tx_count;         /* bridge_tx_buf 有效样本数 */
    uint16_t bridge_rx_count;         /* bridge_rx_buf 有效样本数 */
    luat_rtos_mutex_t bridge_mutex;     /* 桥接缓冲区互斥锁 */
    luat_rtos_timer_t bridge_tone_timer; /* 桥接模式早期提示音定时器 */
    uint32_t bridge_tone_pos;
    uint8_t bridge_tone_on;
#endif

    uint32_t mic_generation[VOIP_MIC_SLOT_COUNT];
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    uint32_t mic_capture_seq[VOIP_MIC_SLOT_COUNT];
    uint32_t mic_render_seq[VOIP_MIC_SLOT_COUNT];
    uint64_t mic_capture_tick_ms[VOIP_MIC_SLOT_COUNT];
#endif
    uint32_t dropped_mic_events;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    volatile uint32_t render_done_seq;
    uint32_t render_refill_seq;
    uint32_t capture_seq;
#endif

    /* AEC */
    const void *aec_ops;
    void *aec_state;
    void *aec_preprocess;
    int16_t *aec_out_buf;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    int16_t *aec_ref_buf;
    int16_t *aec_ref_history;
    volatile uint32_t aec_ref_seq[VOIP_AEC_REF_HISTORY_FRAMES];
    uint64_t aec_ref_tick_ms[VOIP_AEC_REF_HISTORY_FRAMES];
    uint32_t aec_last_capture_seq;
    uint32_t aec_last_render_seq;
    volatile uint32_t aec_sync_fault;
#endif
    uint8_t aec_ready;

    /* Lua 回调引用 */
    int cb_state_ref;   /* LUA_REGISTRYINDEX ref for state callback */
    int cb_stats_ref;   /* LUA_REGISTRYINDEX ref for stats callback */
    int cb_error_ref;   /* LUA_REGISTRYINDEX ref for error callback */
#ifdef LUAT_USE_VOIP_RECORD
    int cb_record_ref;  /* LUA_REGISTRYINDEX ref for record callback */
#endif
} voip_ctx_t;

/* ======================== API ======================== */

/**
 * 获取全局单例上下文
 */
voip_ctx_t *voip_get_ctx(void);

/** Register the audio_v2 PCM codec used by the VoIP Lua adapter. */
void luat_voip_audio_codec_register(void);

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
/* Push the same statistics table for stats() and the periodic Lua callback. */
void voip_push_stats(lua_State *L);

/* Internal AEC/audio-backend interface. */
#ifdef LUAT_USE_VOIP_AUDIO_PORT
int voip_audio_port_prepare(voip_ctx_t *ctx);
void voip_audio_port_cleanup(voip_ctx_t *ctx);
int voip_audio_port_process_raw(voip_ctx_t *ctx, uint32_t index,
        uint32_t sequence, uint32_t session);
int voip_audio_port_commit(voip_ctx_t *ctx, uint8_t slot);
void voip_audio_process_pcm(voip_ctx_t *ctx, const int16_t *pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t end_tick_ms);
#endif
int voip_aec_init(voip_ctx_t *ctx);
void voip_aec_cleanup(voip_ctx_t *ctx);
void voip_aec_render_push(voip_ctx_t *ctx, const int16_t *render_pcm,
        uint32_t render_seq, uint64_t tick_ms);
const int16_t *voip_aec_process_frame(voip_ctx_t *ctx, const int16_t *mic_pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t capture_tick_ms);
const char *voip_aec_mode_name(const voip_ctx_t *ctx);

/**
 * 是否正在运行
 */
/**
 * 是否正在运行
 */
int voip_is_running(void);

#ifdef LUAT_USE_VOIP_RECORD
/** Start/arm a local stereo WAV recording. */
int voip_record_start(const char *path, uint32_t max_seconds);

/** Asynchronously drain and close the current recording. */
int voip_record_stop(void);

/** Get a point-in-time recording status snapshot. */
void voip_record_get_status(voip_record_status_t *status);
#endif

/* ======================== 桥接模式 API ======================== */

#ifdef LUAT_USE_VOIP_BRIDGE

/**
 * 设置音频工作模式（必须在 voip_start 之前调用，或 voip_stop 后调用）
 * @param mode VOIP_AUDIO_MODE_I2S 或 VOIP_AUDIO_MODE_BRIDGE
 * @return 0 成功, <0 失败
 */
int voip_set_audio_mode(voip_audio_mode_t mode);

/**
 * 向 voip 注入上行 PCM 数据（桥接模式）
 * 调用方将外部采集的 PCM 数据（如来自 CC 模块的mic数据）送入 voip，
 * voip 编码后通过 RTP 发送给 SIP 服务器。
 *
 * @param pcm   16bit 单声道 PCM 数据指针
 * @param samples 样本数（每个样本2字节）
 * @return 实际消耗的样本数（可能小于请求数，如果缓冲区满）
 */
int voip_bridge_pcm_in(const int16_t *pcm, uint16_t samples);

/**
 * 从 voip 取出下行 PCM 数据（桥接模式）
 * 调用方从 voip 获取 SIP 服务器发送过来的解码后 PCM 数据，
 * 用于播放（如通过 CC 模块的扬声器播放）。
 *
 * @param pcm     16bit 单声道 PCM 数据接收缓冲区
 * @param max_samples 缓冲区可容纳的最大样本数
 * @return 实际取出的样本数
 */
int voip_bridge_pcm_out(int16_t *pcm, uint16_t max_samples);

/**
 * 控制桥接模式内部早期提示音。
 * 该提示音由VoIP task按ptime发送RTP，不经过Lua 20ms定时器，避免早期媒体卡顿。
 *
 * @param on 1启动，0停止
 * @return 0 成功, <0 失败
 */
int voip_bridge_tone(int on);
#endif

#endif /* LUAT_VOIP_CORE_H */
