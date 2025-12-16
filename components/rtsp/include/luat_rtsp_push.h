/**
 * @file luat_rtsp_push.h
 * @brief RTSP推流组件 - 基于lwip raw API实现
 * @author LuatOS Team
 * 
 * 该组件实现了RTSP(Real Time Streaming Protocol)推流功能,
 * 支持将H.264视频流推送到RTSP服务器。
 * 
 * 主要特性:
 * - 基于lwip raw socket API,适应嵌入式环境
 * - 支持自定义H.264帧来源,灵活的NALU帧注入
 * - 完整的RTSP握手和连接管理
 * - 支持RTP/RTCP协议实现
 * - 支持H.264基础配置文件
 * - C99语法,内存使用优化
 * 
 * 调试说明:
 * - 在 luat_rtsp_push.c 中修改 RTSP_DEBUG_VERBOSE 宏来控制详细日志输出
 * - 设置为 1 开启详细调试信息，设置为 0 关闭（仅保留关键日志）
 */

#ifndef __LUAT_RTSP_PUSH_H__
#define __LUAT_RTSP_PUSH_H__

#include "luat_base.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ======================== RTSP常量定义 ======================== */

/** RTSP默认端口 */
#define RTSP_DEFAULT_PORT 554

/** RTSP缓冲区大小(字节) - 需要足够大以容纳RTSP信令 */
#define RTSP_BUFFER_SIZE (64 * 1024)

/** RTP缓冲区大小(字节) */
#define RTP_BUFFER_SIZE (256 * 1024)

/** RTP UDP缓冲区最大包大小 */
#define RTP_MAX_PACKET_SIZE 1400

/** 发送帧队列最大字节数上限，超出将丢弃未发送帧 */
#define RTSP_MAX_QUEUE_BYTES (1024 * 1024)

/** RTSP命令超时时间(毫秒) */
#define RTSP_CMD_TIMEOUT 5000

/* ======================== 返回值定义 ======================== */

/** 操作成功 */
#define RTSP_OK 0

/** 通用错误 */
#define RTSP_ERR_FAILED (-1)

/** 参数无效 */
#define RTSP_ERR_INVALID_PARAM (-2)

/** 内存不足 */
#define RTSP_ERR_NO_MEMORY (-3)

/** 连接错误 */
#define RTSP_ERR_CONNECT_FAILED (-4)

/** 握手失败 */
#define RTSP_ERR_HANDSHAKE_FAILED (-5)

/** 网络错误 */
#define RTSP_ERR_NETWORK (-6)

/** 超时 */
#define RTSP_ERR_TIMEOUT (-7)

/** 缓冲区溢出 */
#define RTSP_ERR_BUFFER_OVERFLOW (-8)

/* ======================== 数据类型定义 ======================== */

/**
 * RTSP连接状态枚举
 */
typedef enum {
    RTSP_STATE_IDLE = 0,            /**< 空闲状态 */
    RTSP_STATE_CONNECTING = 1,      /**< 正在连接 */
    RTSP_STATE_OPTIONS = 2,         /**< 发送OPTIONS请求 */
    RTSP_STATE_DESCRIBE = 3,        /**< 发送DESCRIBE请求 */
    RTSP_STATE_SETUP = 4,           /**< 发送SETUP请求 */
    RTSP_STATE_PLAY = 5,            /**< 发送PLAY请求，准备推流 */
    RTSP_STATE_PLAYING = 6,         /**< 正在推流 */
    RTSP_STATE_DISCONNECTING = 7,   /**< 正在断开连接 */
    RTSP_STATE_ERROR = 8            /**< 错误状态 */
} rtsp_state_t;

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
 * H.264视频帧信息结构体
 */
typedef struct {
    uint8_t *data;                  /**< 视频数据指针 */
    uint32_t len;                   /**< 视频数据长度 */
    uint32_t timestamp;             /**< 时间戳(ms) */
    uint8_t nalu_type;              /**< NALU类型 */
    uint8_t is_keyframe;            /**< 是否为关键帧 */
} h264_frame_t;

/**
 * RTSP推流统计信息结构体
 */
typedef struct {
    uint32_t bytes_sent;            /**< 已发送的字节数 */
    uint32_t video_frames_sent;     /**< 已发送的视频帧数 */
    uint32_t rtp_packets_sent;      /**< 已发送的RTP包数 */
    uint32_t connection_time;       /**< 连接持续时间(毫秒) */
    uint32_t last_video_timestamp;  /**< 最后视频时间戳(毫秒) */
} rtsp_stats_t;

/**
 * RTSP推流上下文结构体
 * 管理单个RTSP连接的所有状态和缓冲区
 */
typedef struct {
    /** ============ 连接信息 ============ */
    char *url;                      /**< RTSP服务器URL */
    char *host;                     /**< RTSP服务器主机名/IP地址 */
    char *stream;                   /**< 推流名 */
    char *auth;                     /**< 认证信息(用户名:密码) */
    uint16_t port;                  /**< 连接端口 */
    
    /** ============ TCP连接状态(RTSP控制通道) ============ */
    struct tcp_pcb *control_pcb;    /**< lwip TCP控制块(RTSP信令) */
    rtsp_state_t state;             /**< 当前连接状态 */
    uint32_t last_activity_time;    /**< 最后活动时间戳 */
    
    /** ============ UDP连接状态(RTP媒体通道) ============ */
    struct udp_pcb *rtp_pcb;        /**< RTP UDP控制块 */
    struct udp_pcb *rtcp_pcb;       /**< RTCP UDP控制块 */
    ip_addr_t remote_ip;            /**< 远端IP地址 */
    uint16_t remote_rtp_port;       /**< 远端RTP端口 */
    uint16_t remote_rtcp_port;      /**< 远端RTCP端口 */
    uint16_t local_rtp_port;        /**< 本地RTP端口 */
    uint16_t local_rtcp_port;       /**< 本地RTCP端口 */
    
    /** ============ RTSP协议状态 ============ */
    uint32_t cseq;                  /**< RTSP序列号 */
    char *session_id;               /**< RTSP会话ID */
    uint32_t video_stream_id;       /**< 视频流ID(SSRC) */
    
    /** ============ RTP状态 ============ */
    uint32_t rtp_sequence;          /**< RTP序列号 */
    uint32_t rtp_timestamp;         /**< RTP时间戳 */
    uint32_t rtp_ssrc;              /**< RTP同步源标识符 */
    
    /** ============ 缓冲区管理 ============ */
    uint8_t *recv_buf;              /**< 接收缓冲区 */
    uint32_t recv_buf_size;         /**< 接收缓冲区大小 */
    uint32_t recv_pos;              /**< 接收缓冲区写位置 */
    
    uint8_t *send_buf;              /**< 发送缓冲区 */
    uint32_t send_buf_size;         /**< 发送缓冲区大小 */
    uint32_t send_pos;              /**< 发送缓冲区写位置 */
    
    uint8_t *rtp_buf;               /**< RTP发送缓冲区 */
    uint32_t rtp_buf_size;          /**< RTP缓冲区大小 */

    /** ============ 帧发送队列 ============ */
    struct rtsp_frame_node *frame_head; /**< 待发送帧队列头 */
    struct rtsp_frame_node *frame_tail; /**< 待发送帧队列尾 */
    uint32_t frame_queue_bytes;          /**< 队列占用的总字节数 */
    
    /** ============ 时间戳管理 ============ */
    uint32_t video_timestamp;       /**< 当前视频时间戳(ms) */
    uint32_t base_timestamp;        /**< 基准时间戳 */
    uint32_t start_tick;            /**< 启动时刻的系统tick */
    
    /** ============ H.264编码信息 ============ */
    uint8_t *sps_data;              /**< SPS(序列参数集)数据 */
    uint32_t sps_len;               /**< SPS长度 */
    uint8_t *pps_data;              /**< PPS(图像参数集)数据 */
    uint32_t pps_len;               /**< PPS长度 */
    char *sprop_parameter_sets;     /**< SDP中的sprop-parameter-sets */
    
    /** ============ 统计信息 ============ */
    uint32_t packets_sent;          /**< 已发送的包数 */
    uint32_t bytes_sent;            /**< 已发送的字节数 */
    uint32_t video_frames_sent;     /**< 已发送的视频帧数 */
    uint32_t rtp_packets_sent;      /**< 已发送的RTP包数 */
    uint32_t last_rtcp_time;        /**< 上次发送RTCP SR的时间(tick) */
    
    /** ============ 用户数据 ============ */
    void *user_data;                /**< 用户自定义数据指针 */
} rtsp_ctx_t;

/**
 * RTSP状态变化回调函数类型
 * 
 * @param ctx RTSP上下文指针
 * @param old_state 旧状态
 * @param new_state 新状态
 * @param error_code 错误代码(仅在STATE_ERROR时有效)
 */
typedef void (*rtsp_state_callback_t)(rtsp_ctx_t *ctx, rtsp_state_t old_state, 
                                      rtsp_state_t new_state, int error_code);

/* ======================== 核心接口函数 ======================== */

/**
 * 创建RTSP推流上下文
 * 
 * @return RTSP上下文指针,失败返回NULL
 * @note 返回的指针需要使用rtsp_destroy()释放
 */
rtsp_ctx_t* rtsp_create(void);

/**
 * 销毁RTSP推流上下文,释放所有资源
 * 
 * @param ctx RTSP上下文指针
 * @return 0=成功, 负数=失败
 */
int rtsp_destroy(rtsp_ctx_t *ctx);

/**
 * 设置RTSP服务器URL
 * 
 * @param ctx RTSP上下文指针
 * @param url RTSP服务器地址,格式: rtsp://host:port/stream
 * @return 0=成功, 负数=失败
 */
int rtsp_set_url(rtsp_ctx_t *ctx, const char *url);

/**
 * 设置状态变化回调函数
 * 
 * @param ctx RTSP上下文指针
 * @param callback 回调函数指针
 * @return 0=成功, 负数=失败
 */
int rtsp_set_state_callback(rtsp_ctx_t *ctx, rtsp_state_callback_t callback);

/**
 * 连接到RTSP服务器
 * 
 * @param ctx RTSP上下文指针
 * @return 0=成功, 负数=失败
 * @note 此函数应在lwip tcpip线程中调用
 */
int rtsp_connect(rtsp_ctx_t *ctx);

/**
 * 断开RTSP连接
 * 
 * @param ctx RTSP上下文指针
 * @return 0=成功, 负数=失败
 */
int rtsp_disconnect(rtsp_ctx_t *ctx);

/**
 * 获取当前连接状态
 * 
 * @param ctx RTSP上下文指针
 * @return 当前状态值
 */
rtsp_state_t rtsp_get_state(rtsp_ctx_t *ctx);

/**
 * 设置H.264 SPS数据(序列参数集)
 * 
 * @param ctx RTSP上下文指针
 * @param sps_data SPS数据指针
 * @param sps_len SPS数据长度
 * @return 0=成功, 负数=失败
 * @note 数据会被复制,调用者可以释放原数据
 */
int rtsp_set_sps(rtsp_ctx_t *ctx, const uint8_t *sps_data, uint32_t sps_len);

/**
 * 设置H.264 PPS数据(图像参数集)
 * 
 * @param ctx RTSP上下文指针
 * @param pps_data PPS数据指针
 * @param pps_len PPS数据长度
 * @return 0=成功, 负数=失败
 * @note 数据会被复制,调用者可以释放原数据
 */
int rtsp_set_pps(rtsp_ctx_t *ctx, const uint8_t *pps_data, uint32_t pps_len);

/**
 * 推送H.264视频帧数据
 * 
 * 该函数接收H.264编码的视频帧数据(可以是完整的访问单元或单个NALU)
 * 内部会自动进行RTP打包并通过UDP发送到服务器。
 * 
 * @param ctx RTSP上下文指针
 * @param frame_data 视频帧数据指针(包含起始码或不包含均可)
 * @param frame_len 视频帧数据长度(字节数)
 * @param timestamp 时间戳(毫秒),如果为0则使用内部时间戳
 * @return 0=成功,正数=已入队,负数=失败
 * 
 * @note 
 * - frame_data 可以包含H.264起始码(0x00000001或0x000001)或不包含
 * - 支持单个NALU或多个NALU的访问单元
 * - 如果在PLAYING状态下调用,数据会立即发送;否则进入队列
 * - 返回值为正数时表示字节数已加入队列
 * 
 * @example
 * // 推送一帧H.264视频
 * uint8_t *frame_data = ...;  // H.264编码帧数据
 * uint32_t frame_len = ...;   // 帧长度
 * uint32_t timestamp = 0;     // 使用内部时间戳
 * 
 * int ret = rtsp_push_h264_frame(ctx, frame_data, frame_len, timestamp);
 * if (ret >= 0) {
 *     printf("成功推送%d字节\n", ret);
 * } else {
 *     printf("推送失败: %d\n", ret);
 * }
 */
int rtsp_push_h264_frame(rtsp_ctx_t *ctx, const uint8_t *frame_data, 
                         uint32_t frame_len, uint32_t timestamp);

/**
 * 处理RTSP连接事件,应定期调用此函数
 * 
 * @param ctx RTSP上下文指针
 * @return 0=成功, 负数=失败
 * @note 建议每10-20ms调用一次此函数
 */
int rtsp_poll(rtsp_ctx_t *ctx);

/**
 * 获取推流统计信息
 * 
 * @param ctx RTSP上下文指针
 * @param stats 统计信息指针
 * @return 0=成功, 负数=失败
 */
int rtsp_get_stats(rtsp_ctx_t *ctx, rtsp_stats_t *stats);

#ifdef __cplusplus
}
#endif

#endif /* __LUAT_RTSP_PUSH_H__ */
