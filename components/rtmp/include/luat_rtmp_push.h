/**
 * @file luat_rtmp_push.h
 * @brief RTMP推流组件 - 基于lwip raw API实现
 * @author LuatOS Team
 * 
 * 该组件实现了RTMP(Real Time Messaging Protocol)推流功能,
 * 支持将H.264视频流推送到RTMP服务器。
 * 
 * 主要特性:
 * - 基于lwip raw socket API,适应嵌入式环境
 * - 支持自定义H.264帧来源,灵活的NALU帧注入
 * - 完整的RTMP握手和连接管理
 * - 支持FLV格式视频打包和发送
 * - C99语法,内存使用优化
 * 
 * 调试说明:
 * - 在 luat_rtmp_push.c 中修改 RTMP_DEBUG_VERBOSE 宏来控制详细日志输出
 * - 设置为 1 开启详细调试信息，设置为 0 关闭（仅保留关键日志）
 */

#ifndef __LUAT_RTMP_PUSH_H__
#define __LUAT_RTMP_PUSH_H__

#include "luat_base.h"
#include "lwip/tcp.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ======================== RTMP常量定义 ======================== */

/** RTMP默认块大小(字节) - RTMP规范规定的默认值为128 */
#define RTMP_DEFAULT_CHUNK_SIZE 128

/** RTMP缓冲区大小(字节) - 需要足够大以容纳I帧 */
#define RTMP_BUFFER_SIZE (512 * 1024)

/** 发送帧队列最大字节数上限，超出将丢弃未发送帧（优先丢弃非关键帧） */
#define RTMP_MAX_QUEUE_BYTES (1024 * 1024)

/** RTMP握手数据大小(字节) */
#define RTMP_HANDSHAKE_SIZE 1536

/** RTMP命令超时时间(毫秒) */
#define RTMP_CMD_TIMEOUT 5000

/* ======================== 返回值定义 ======================== */

/** 操作成功 */
#define RTMP_OK 0

/** 通用错误 */
#define RTMP_ERR_FAILED (-1)

/** 参数无效 */
#define RTMP_ERR_INVALID_PARAM (-2)

/** 内存不足 */
#define RTMP_ERR_NO_MEMORY (-3)

/** 连接错误 */
#define RTMP_ERR_CONNECT_FAILED (-4)

/** 握手失败 */
#define RTMP_ERR_HANDSHAKE_FAILED (-5)

/** 网络错误 */
#define RTMP_ERR_NETWORK (-6)

/** 超时 */
#define RTMP_ERR_TIMEOUT (-7)

/** 缓冲区溢出 */
#define RTMP_ERR_BUFFER_OVERFLOW (-8)

/* ======================== 数据类型定义 ======================== */

/**
 * RTMP连接状态枚举
 */
typedef enum {
    RTMP_STATE_IDLE = 0,           /**< 空闲状态 */
    RTMP_STATE_CONNECTING = 1,     /**< 正在连接 */
    RTMP_STATE_HANDSHAKING = 2,    /**< 握手中 */
    RTMP_STATE_CONNECTED = 3,      /**< 已连接 */
    RTMP_STATE_PUBLISHING = 4,     /**< 正在推流 */
    RTMP_STATE_DISCONNECTING = 5,  /**< 正在断开连接 */
    RTMP_STATE_ERROR = 6            /**< 错误状态 */
} rtmp_state_t;

/**
 * RTMP消息类型枚举
 */
typedef enum {
    RTMP_MSG_SET_CHUNK_SIZE = 1,    /**< 设置块大小 */
    RTMP_MSG_ABORT = 2,             /**< 中止消息 */
    RTMP_MSG_BYTES_READ = 3,        /**< 字节已读 */
    RTMP_MSG_CONTROL = 4,           /**< 用户控制消息 */
    RTMP_MSG_SERVER_BW = 5,         /**< 服务器带宽 */
    RTMP_MSG_CLIENT_BW = 6,         /**< 客户端带宽 */
    RTMP_MSG_AUDIO = 8,             /**< 音频数据 */
    RTMP_MSG_VIDEO = 9,             /**< 视频数据 */
    RTMP_MSG_AMFDATAFILE = 15,      /**< AMF数据 */
    RTMP_MSG_COMMAND = 20,          /**< 命令(AMF0) */
    RTMP_MSG_EXTENDED_COMMAND = 17  /**< 扩展命令 */
} rtmp_msg_type_t;

/**
 * H.264 NALU类型枚举
 */
typedef enum {
    NALU_TYPE_NON_IDR = 1,          /**< 非IDR帧 */
    NALU_TYPE_IDR = 5,              /**< IDR帧(关键帧) */
    NALU_TYPE_SEI = 6,              /**< SEI(补充增强信息) */
    NALU_TYPE_SPS = 7,              /**< SPS(序列参数集) */
    NALU_TYPE_PPS = 8,              /**< PPS(图像参数集) */
    NALU_TYPE_AUD = 9               /**< AUD(访问单元分隔符) */
} nalu_type_t;

/**
 * RTMP推流统计信息结构体
 * 用于查询RTMP连接的实时统计数据
 */
typedef struct {
    uint64_t bytes_sent;            /**< 已发送的字节数 */
    uint32_t video_frames_sent;     /**< 已发送的视频帧数 */
    uint32_t audio_frames_sent;     /**< 已发送的音频帧数 */
    uint32_t connection_time;       /**< 连接持续时间(毫秒) */
    uint32_t packets_sent;          /**< 已发送的包数 */
    uint32_t last_video_timestamp;  /**< 最后视频时间戳(毫秒) */
    uint32_t last_audio_timestamp;  /**< 最后音频时间戳(毫秒) */

    /* 细分统计 */
    uint32_t i_frames;              /**< 发送的I帧数量 */
    uint32_t p_frames;              /**< 发送的P帧数量 */
    uint64_t i_bytes;               /**< 发送的I帧字节数（NAL数据长度累加） */
    uint64_t p_bytes;               /**< 发送的P帧字节数（NAL数据长度累加） */
    uint64_t audio_bytes;           /**< 发送的音频字节数 */

    uint32_t dropped_frames;        /**< 被丢弃的帧数量 */
    uint64_t dropped_bytes;         /**< 被丢弃的帧字节数 */
} rtmp_stats_t;

/**
 * RTMP推流上下文结构体
 * 管理单个RTMP连接的所有状态和缓冲区
 */
typedef struct {
    /** ============ 连接信息 ============ */
    char *url;                      /**< RTMP服务器URL */
    char *host;                     /**< RTMP服务器主机名/IP地址 */
    char *app;                      /**< RTMP应用名 */
    char *stream;                   /**< 推流名 */
    char *auth;                     /**< 认证信息 */
    uint16_t port;                  /**< 连接端口 */
    
    /** ============ TCP连接状态 ============ */
    struct tcp_pcb *pcb;            /**< lwip TCP控制块 */
    rtmp_state_t state;             /**< 当前连接状态 */
    uint32_t last_activity_time;    /**< 最后活动时间戳 */
    int handshake_state;            /**< 握手状态: 0=发送C0C1, 1=等待S0S1, 2=发送C2, 3=完成 */
    
    /** ============ RTMP协议状态 ============ */
    uint32_t in_chunk_size;         /**< 输入块大小 */
    uint32_t out_chunk_size;        /**< 输出块大小 */
    uint32_t chunk_size;            /**< 当前chunk大小（用于分块发送）*/
    uint32_t video_stream_id;       /**< 视频流ID */
    uint32_t audio_stream_id;       /**< 音频流ID */
    
    /** ============ 缓冲区管理 ============ */
    uint8_t *recv_buf;              /**< 接收缓冲区 */
    uint32_t recv_buf_size;         /**< 接收缓冲区大小 */
    uint32_t recv_pos;              /**< 接收缓冲区写位置 */
    
    uint8_t *send_buf;              /**< 发送缓冲区 */
    uint32_t send_buf_size;         /**< 发送缓冲区大小 */
    uint32_t send_pos;              /**< 发送缓冲区写位置 */

    /** ============ 帧发送队列 ============ */
    struct rtmp_frame_node *frame_head; /**< 待发送帧队列头 */
    struct rtmp_frame_node *frame_tail; /**< 待发送帧队列尾 */
    uint32_t frame_queue_bytes;          /**< 队列占用的总字节数 */
    
    /** ============ 时间戳管理 ============ */
    uint32_t video_timestamp;       /**< 当前视频时间戳(ms) */
    uint32_t audio_timestamp;       /**< 当前音频时间戳(ms) */
    uint32_t base_timestamp;        /**< 基准时间戳 */
    
    /** ============ 统计信息 ============ */
    uint32_t packets_sent;          /**< 已发送的包数 */
    uint64_t bytes_sent;            /**< 已发送的字节数 */
    uint32_t command_id;            /**< 当前命令ID */

    /* 帧统计 */
    uint32_t i_frames;              /**< 发送的I帧数量 */
    uint32_t p_frames;              /**< 发送的P帧数量 */
    uint64_t i_bytes;               /**< 发送的I帧字节数 */
    uint64_t p_bytes;               /**< 发送的P帧字节数 */
    uint32_t audio_frames_sent;     /**< 发送的音频帧数量 */
    uint64_t audio_bytes;           /**< 发送的音频字节数 */
    uint32_t dropped_frames;        /**< 被丢弃的帧数量 */
    uint64_t dropped_bytes;         /**< 被丢弃的帧字节数 */
    uint32_t last_stats_log_ms;     /**< 上次统计日志输出时间 */
    uint64_t last_stats_bytes;      /**< 上次统计日志输出时的总字节数 */
    uint32_t stats_interval_ms;     /**< 统计输出间隔(毫秒)，默认10000 */
    uint32_t stats_window_ms;       /**< 统计窗口长度(毫秒)，默认与间隔相同 */
    uint32_t last_window_ms;        /**< 上次窗口采样时间戳(ms) */
    uint64_t last_window_bytes;     /**< 上次窗口采样时的总字节数 */
    
    /** ============ 用户数据 ============ */
    void *user_data;                /**< 用户自定义数据指针 */
} rtmp_ctx_t;

/* ======================== 核心接口函数 ======================== */

/**
 * 创建RTMP推流上下文
 * 
 * 分配并初始化RTMP上下文结构体,为后续的RTMP连接做准备。
 * 
 * @return 返回RTMP上下文指针,失败返回NULL
 */
rtmp_ctx_t* rtmp_create(void);

/**
 * 销毁RTMP推流上下文
 * 
 * 释放所有由RTMP上下文占用的资源,包括内存缓冲区和TCP连接。
 * 
 * @param ctx RTMP上下文指针
 * @return 返回RTMP_OK表示成功
 */
int rtmp_destroy(rtmp_ctx_t *ctx);

/**
 * 设置RTMP服务器URL
 * 
 * 解析并设置RTMP服务器地址,支持的格式为:
 * - rtmp://hostname:port/app/stream
 * - rtmp://hostname/app/stream (使用默认端口1935)
 * 
 * 如果设置过URL,新的设置会覆盖旧的设置。
 * 
 * @param ctx RTMP上下文指针
 * @param url RTMP服务器URL字符串
 * @return RTMP_OK表示成功,其他值表示失败
 */
int rtmp_set_url(rtmp_ctx_t *ctx, const char *url);

/**
 * 连接到RTMP服务器
 * 
 * 建立与RTMP服务器的TCP连接,然后执行RTMP握手流程。
 * 该函数是非阻塞的,实际的连接过程通过回调函数进行。
 * 
 * @param ctx RTMP上下文指针
 * @return RTMP_OK表示连接已启动,其他值表示参数错误或资源不足
 */
int rtmp_connect(rtmp_ctx_t *ctx);

/**
 * 断开RTMP连接
 * 
 * 主动关闭与RTMP服务器的连接,释放TCP资源。
 * 
 * @param ctx RTMP上下文指针
 * @return RTMP_OK表示断开已启动
 */
int rtmp_disconnect(rtmp_ctx_t *ctx);

/**
 * 发送H.264 NALU帧
 * 
 * 将一个H.264 NALU帧打包为FLV视频标签并发送。
 * 支持自动检测关键帧(IDR)和普通帧。
 * 
 * 使用示例:
 * @code
 * uint8_t nalu_data[1024];
 * uint32_t nalu_len = 1024;
 * rtmp_send_nalu(ctx, nalu_data, nalu_len, 0); // 时间戳0ms
 * @endcode
 * 
 * @param ctx RTMP上下文指针
 * @param nalu_data NALU数据指针,包含完整的NALU单元
 * @param nalu_len NALU数据长度
 * @param timestamp 视频时间戳(毫秒),从0开始递增
 * @return RTMP_OK表示发送成功,其他值表示错误
 *         - RTMP_ERR_INVALID_PARAM: 参数无效
 *         - RTMP_ERR_BUFFER_OVERFLOW: 缓冲区不足
 *         - RTMP_ERR_FAILED: 发送失败
 */
int rtmp_send_nalu(rtmp_ctx_t *ctx, const uint8_t *nalu_data, 
                   uint32_t nalu_len, uint32_t timestamp);

/**
 * 发送多个NALU帧(聚合发送)
 * 
 * 将多个NALU帧聚合打包为单个FLV视频数据包发送,
 * 可以提高网络传输效率。
 * 
 * @param ctx RTMP上下文指针
 * @param nalus NALU数据指针数组
 * @param lengths 对应NALU的长度数组
 * @param count NALU帧的个数
 * @param timestamp 视频时间戳(毫秒)
 * @return RTMP_OK表示发送成功
 */
int rtmp_send_nalu_multi(rtmp_ctx_t *ctx, const uint8_t **nalus,
                         const uint32_t *lengths, uint32_t count, 
                         uint32_t timestamp);

/**
 * 发送音频数据帧
 * 
 * 将音频数据打包为RTMP音频消息并发送。
 * 支持AAC等多种音频格式。
 * 
 * 使用示例(AAC):
 * @code
 * // 发送AAC Sequence Header
 * uint8_t aac_header[] = {0xAF, 0x00, 0x12, 0x10}; // AAC-LC, 44.1kHz, Stereo
 * rtmp_send_audio(ctx, aac_header, sizeof(aac_header), 0);
 * 
 * // 发送AAC音频帧
 * uint8_t audio_frame[256];
 * audio_frame[0] = 0xAF; // AAC, 44.1kHz, 16bit, Stereo
 * audio_frame[1] = 0x01; // AAC raw data
 * memcpy(&audio_frame[2], aac_raw_data, aac_raw_len);
 * rtmp_send_audio(ctx, audio_frame, 2 + aac_raw_len, timestamp);
 * @endcode
 * 
 * 音频标签头格式(第1字节):
 * - Bit[7:4]: SoundFormat (10=AAC, 2=MP3, 3=PCM等)
 * - Bit[3:2]: SoundRate (0=5.5kHz, 1=11kHz, 2=22kHz, 3=44kHz)
 * - Bit[1]: SoundSize (0=8bit, 1=16bit)
 * - Bit[0]: SoundType (0=Mono, 1=Stereo)
 * 
 * AAC格式需要第2字节指定AACPacketType:
 * - 0 = AAC sequence header (AudioSpecificConfig)
 * - 1 = AAC raw data
 * 
 * @param ctx RTMP上下文指针
 * @param audio_data 音频数据指针,应包含完整的音频标签(标签头+数据)
 * @param audio_len 音频数据总长度
 * @param timestamp 音频时间戳(毫秒),从0开始递增
 * @return RTMP_OK表示发送成功,其他值表示错误
 *         - RTMP_ERR_INVALID_PARAM: 参数无效
 *         - RTMP_ERR_NO_MEMORY: 内存不足
 *         - RTMP_ERR_FAILED: 发送失败
 */
int rtmp_send_audio(rtmp_ctx_t *ctx, const uint8_t *audio_data,
                    uint32_t audio_len, uint32_t timestamp);

/**
 * 获取当前连接状态
 * 
 * @param ctx RTMP上下文指针
 * @return 返回当前的rtmp_state_t状态值
 */
rtmp_state_t rtmp_get_state(rtmp_ctx_t *ctx);

/**
 * 处理RTMP事件(需要定期调用)
 * 
 * 处理TCP连接事件、接收数据、超时检测等。
 * 该函数应该在主循环或定时器中定期调用,建议间隔为10-50毫秒。
 * 
 * @param ctx RTMP上下文指针
 * @return RTMP_OK表示正常,其他值表示发生错误
 */
int rtmp_poll(rtmp_ctx_t *ctx);

/**
 * 设置用户自定义数据
 * 
 * 可用于关联用户的上下文信息,在回调函数中可以通过
 * rtmp_get_user_data获取。
 * 
 * @param ctx RTMP上下文指针
 * @param user_data 用户数据指针
 * @return RTMP_OK表示成功
 */
int rtmp_set_user_data(rtmp_ctx_t *ctx, void *user_data);

/**
 * 获取用户自定义数据
 * 
 * @param ctx RTMP上下文指针
 * @return 返回用户设置的数据指针,未设置则返回NULL
 */
void* rtmp_get_user_data(rtmp_ctx_t *ctx);

/**
 * 获取统计信息
 * 
 * 获取RTMP连接的实时统计数据，包括字节数、帧数、连接时长等。
 * 该函数可以在任何时刻调用以查询当前的推流统计信息。
 * 
 * @param ctx RTMP上下文指针
 * @param stats 指向rtmp_stats_t结构体的指针，用于返回统计信息
 * @return RTMP_OK表示成功，其他值表示失败
 *         - RTMP_ERR_INVALID_PARAM: ctx或stats参数为NULL
 * 
 * 使用示例:
 * @code
 * rtmp_stats_t stats;
 * if (rtmp_get_stats(ctx, &stats) == RTMP_OK) {
 *     printf("已发送: %u 字节, %u 视频帧\n", 
 *            stats.bytes_sent, stats.video_frames_sent);
 * }
 * @endcode
 */
int rtmp_get_stats(rtmp_ctx_t *ctx, rtmp_stats_t *stats);

/**
 * 设置统计输出间隔
 * 
 * @param ctx RTMP上下文指针
 * @param interval_ms 间隔毫秒数（例如10000表示10秒）
 * @return RTMP_OK表示成功
 */
int rtmp_set_stats_interval(rtmp_ctx_t *ctx, uint32_t interval_ms);

/**
 * 设置统计窗口长度
 * 
 * @param ctx RTMP上下文指针
 * @param window_ms 窗口毫秒数（例如10000表示10秒）
 * @return RTMP_OK表示成功
 */
int rtmp_set_stats_window(rtmp_ctx_t *ctx, uint32_t window_ms);

/* ======================== 回调函数定义 ======================== */

/**
 * RTMP连接状态变化回调函数类型
 * 
 * @param ctx RTMP上下文指针
 * @param old_state 旧状态
 * @param new_state 新状态
 * @param error_code 如果是ERROR状态,此参数表示错误码
 */
typedef void (*rtmp_state_callback)(rtmp_ctx_t *ctx, rtmp_state_t old_state, 
                                    rtmp_state_t new_state, int error_code);

/**
 * 设置状态变化回调函数
 * 
 * 当RTMP连接状态发生变化时会调用此回调函数。
 * 
 * @param ctx RTMP上下文指针
 * @param callback 回调函数指针,传NULL则禁用回调
 * @return RTMP_OK表示成功
 */
int rtmp_set_state_callback(rtmp_ctx_t *ctx, rtmp_state_callback callback);

#ifdef __cplusplus
}
#endif

#endif /* __LUAT_RTMP_PUSH_H__ */
