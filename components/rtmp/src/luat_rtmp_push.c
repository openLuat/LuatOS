/**
 * @file luat_rtmp_push.c
 * @brief RTMP推流组件实现 - 基于lwip raw API
 * @author LuatOS Team
 * 
 * 实现了RTMP协议的核心功能,包括:
 * - TCP连接管理
 * - RTMP握手流程
 * - AMF数据序列化
 * - FLV视频数据打包
 * - 网络数据收发
 */

#include "luat_rtmp_push.h"
#include "luat_debug.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "lwip/tcp.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>

#define LUAT_LOG_TAG "rtmp_push"
#include "luat_log.h"

/* ======================== 内部常量定义 ======================== */

/** RTMP握手客户端数据大小 */
#define RTMP_HANDSHAKE_CLIENT_SIZE 1536

/** RTMP命令端口 */
#define RTMP_DEFAULT_PORT 1935

/** AMF数据类型 */
#define AMF_TYPE_NUMBER 0x00
#define AMF_TYPE_BOOLEAN 0x01
#define AMF_TYPE_STRING 0x02
#define AMF_TYPE_OBJECT 0x03
#define AMF_TYPE_NULL 0x05
#define AMF_TYPE_OBJECT_END 0x09

/* ======================== 内部函数声明 ======================== */

/**
 * 解析URL并提取主机名、端口、应用名和流名
 */
static int rtmp_parse_url(rtmp_ctx_t *ctx, const char *url);

/**
 * TCP连接回调函数
 */
static err_t rtmp_tcp_connect_callback(void *arg, struct tcp_pcb *pcb, err_t err);

/**
 * TCP接收回调函数
 */
static err_t rtmp_tcp_recv_callback(void *arg, struct tcp_pcb *pcb, 
                                   struct pbuf *p, err_t err);

/**
 * TCP错误回调函数
 */
static void rtmp_tcp_error_callback(void *arg, err_t err);

/**
 * TCP发送回调函数
 */
static err_t rtmp_tcp_sent_callback(void *arg, struct tcp_pcb *pcb, u16_t len);

/**
 * 执行RTMP握手
 */
static int rtmp_do_handshake(rtmp_ctx_t *ctx);

/**
 * 处理握手响应
 */
static int rtmp_process_handshake_response(rtmp_ctx_t *ctx);

/**
 * 发送RTMP命令
 */
static int rtmp_send_command(rtmp_ctx_t *ctx, const char *command, 
                            uint32_t transaction_id, const char *args);

/**
 * 处理收到的RTMP数据
 */
static int rtmp_process_data(rtmp_ctx_t *ctx);

/**
 * 获取NALU类型
 */
static nalu_type_t rtmp_get_nalu_type(const uint8_t *nalu_data, uint32_t nalu_len);

/**
 * 检查是否为关键帧(IDR)
 */
static bool rtmp_is_key_frame(const uint8_t *nalu_data, uint32_t nalu_len);

/**
 * 打包FLV消息头
 */
static uint32_t rtmp_pack_flv_header(uint8_t *buffer, uint32_t buffer_len,
                                     uint8_t msg_type, uint32_t msg_len,
                                     uint32_t timestamp, uint32_t stream_id);

/**
 * 打包RTMP消息(包含FLV头和块打包)
 */
static int rtmp_pack_message(rtmp_ctx_t *ctx, uint8_t msg_type,
                            const uint8_t *payload, uint32_t payload_len,
                            uint32_t timestamp, uint32_t stream_id);

/**
 * 打包FLV视频标签
 */
static int rtmp_pack_video_tag(uint8_t *buffer, uint32_t buffer_len,
                              const uint8_t *video_data, uint32_t video_len,
                              bool is_key_frame);

/**
 * 帧发送队列节点
 */
typedef struct rtmp_frame_node {
    uint8_t *data;              /* 完整RTMP消息（包含chunk头） */
    uint32_t len;               /* 消息总长度 */
    uint32_t sent;              /* 已发送字节数 */
    bool is_key;                /* 是否关键帧 */
    struct rtmp_frame_node *next;
} rtmp_frame_node_t;

/**
 * 发送发出的缓冲数据
 */
static int rtmp_flush_send_buffer(rtmp_ctx_t *ctx);

/**
 * 更新状态
 */
static void rtmp_set_state(rtmp_ctx_t *ctx, rtmp_state_t new_state, int error_code);

/**
 * 发送单个NALU单元(内部函数)
 * 支持大数据帧(最大300KB+)
 */
static int rtmp_send_single_nalu(rtmp_ctx_t *ctx, const uint8_t *nalu_data,
                                uint32_t nalu_len, uint32_t timestamp);

/**
 * 发送AVC Sequence Header (SPS+PPS配置数据)
 */
static int rtmp_send_avc_sequence_header(rtmp_ctx_t *ctx, const uint8_t *seq_header,
                                        uint32_t seq_len, uint32_t timestamp);
static int rtmp_build_rtmp_message(rtmp_ctx_t *ctx, uint8_t msg_type,
                                  const uint8_t *payload, uint32_t payload_len,
                                  uint32_t timestamp, uint32_t stream_id,
                                  uint8_t **out_buf, uint32_t *out_len);
static void rtmp_free_frame_node(rtmp_frame_node_t *node);
static int rtmp_queue_frame(rtmp_ctx_t *ctx, rtmp_frame_node_t *node);
static void rtmp_try_send_queue(rtmp_ctx_t *ctx);

/**
 * 生成随机时间戳
 */
static uint32_t rtmp_gen_timestamp(void);

/* ======================== 全局状态回调 ======================== */

static rtmp_state_callback g_state_callback = NULL;

/* ======================== 工具函数 ======================== */

/**
 * 大端字节序写入
 */
static inline void write_be32(uint8_t *buf, uint32_t val) {
    buf[0] = (val >> 24) & 0xFF;
    buf[1] = (val >> 16) & 0xFF;
    buf[2] = (val >> 8) & 0xFF;
    buf[3] = val & 0xFF;
}

/**
 * 大端字节序写入16位
 */
static inline void write_be16(uint8_t *buf, uint16_t val) {
    buf[0] = (val >> 8) & 0xFF;
    buf[1] = val & 0xFF;
}

/**
 * 大端字节序读取
 */
static inline uint32_t read_be32(const uint8_t *buf) {
    return ((uint32_t)buf[0] << 24) | ((uint32_t)buf[1] << 16) | 
           ((uint32_t)buf[2] << 8) | (uint32_t)buf[3];
}

/**
 * 大端字节序读取16位
 */
static inline uint16_t read_be16(const uint8_t *buf) {
    return ((uint16_t)buf[0] << 8) | (uint16_t)buf[1];
}

/**
 * 写入AMF字符串
 */
static uint32_t rtmp_write_amf_string(uint8_t *buf, uint32_t buf_len, 
                                     const char *str) {
    uint32_t str_len = strlen(str);
    if (buf_len < str_len + 2) {
        return 0;
    }
    
    write_be16(buf, (uint16_t)str_len);
    if (str_len > 0) {
        memcpy(buf + 2, str, str_len);
    }
    return str_len + 2;
}

/**
 * 写入AMF数字
 */
static uint32_t rtmp_write_amf_number(uint8_t *buf, uint32_t buf_len, 
                                     double num) {
    if (buf_len < 9) {
        return 0;
    }
    
    buf[0] = AMF_TYPE_NUMBER;
    uint64_t bits = *(uint64_t *)&num;
    for (int i = 0; i < 8; i++) {
        buf[8 - i] = (uint8_t)(bits >> (i * 8));
    }
    return 9;
}

/**
 * 写入AMF对象
 */
static uint32_t rtmp_write_amf_object_end(uint8_t *buf, uint32_t buf_len) {
    if (buf_len < 3) {
        return 0;
    }
    
    buf[0] = 0x00;
    buf[1] = 0x00;
    buf[2] = AMF_TYPE_OBJECT_END;
    return 3;
}

/**
 * 打包FLV消息头
 * 
 * FLV消息头格式(11字节):
 * - 消息类型 (1字节): 8=音频, 9=视频, 18=数据
 * - 消息长度 (3字节大端): 负载长度
 * - 时间戳 (3字节大端): 毫秒
 * - 时间戳扩展 (1字节): 时间戳的最高字节
 * - 流ID (3字节大端): 通常为1
 */
static uint32_t rtmp_pack_flv_header(uint8_t *buffer, uint32_t buffer_len,
                                     uint8_t msg_type, uint32_t msg_len,
                                     uint32_t timestamp, uint32_t stream_id) {
    if (buffer_len < 11) {
        return 0;
    }
    
    uint32_t offset = 0;
    
    /* 消息类型 */
    buffer[offset++] = msg_type;
    
    /* 消息长度 (3字节大端) */
    buffer[offset++] = (msg_len >> 16) & 0xFF;
    buffer[offset++] = (msg_len >> 8) & 0xFF;
    buffer[offset++] = msg_len & 0xFF;
    
    /* 时间戳 (3字节大端) */
    buffer[offset++] = (timestamp >> 16) & 0xFF;
    buffer[offset++] = (timestamp >> 8) & 0xFF;
    buffer[offset++] = timestamp & 0xFF;
    
    /* 时间戳扩展 (1字节，用于时间戳超过24bit的情况) */
    buffer[offset++] = (timestamp >> 24) & 0xFF;
    
    /* 流ID (3字节大端) */
    buffer[offset++] = (stream_id >> 16) & 0xFF;
    buffer[offset++] = (stream_id >> 8) & 0xFF;
    buffer[offset++] = stream_id & 0xFF;
    
    return offset;
}

/**
 * 打包RTMP块和消息头
 * 
 * RTMP块格式:
 * - 块头 (1-3字节):
 *   - 格式 (2bit): 0/1/2/3
 *   - 块流ID (6bit) 或 (8bit) 或 (16bit)
 * - 消息头 (0/3/7/11字节): 取决于块格式
 * - 块数据: 最多out_chunk_size字节
 */
static int rtmp_pack_message(rtmp_ctx_t *ctx, uint8_t msg_type,
                            const uint8_t *payload, uint32_t payload_len,
                            uint32_t timestamp, uint32_t stream_id) {
    if (!ctx || !payload || payload_len == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    if (!ctx->pcb) {
        return RTMP_ERR_FAILED;
    }
    
    /* RTMP 块格式构建
     * 
     * RTMP 消息格式：
     * [块头 (1-3字节)] + [消息头 (0/3/7/11字节)] + [消息体]
     * 
     * 块头格式：
     * - 格式 (2bit): 使用0（完整消息头，包含所有信息）
     * - 块流ID (6bit): 使用0-63之间的值，这里用3表示命令流，4表示视频流
     * 
     * 消息头格式（格式0，11字节）：
     * - 时间戳 (3字节大端)
     * - 消息长度 (3字节大端)
     * - 消息类型 (1字节)
     * - 流ID (4字节小端)
     */
    
    uint8_t chunk_header[12];  /* 1字节块头 + 11字节消息头 */
    uint32_t chunk_header_len = 0;
    
    /* 块头：格式0 + 块流ID
     * 格式0表示完整消息头（11字节）
     * 块流ID：3用于命令，4用于视频流
     */
    uint8_t chunk_stream_id = (msg_type == 20 || msg_type == 17) ? 3 : 4;
    uint8_t fmt = 0;  /* 格式0：完整消息头 */
    
    chunk_header[chunk_header_len++] = (fmt << 6) | (chunk_stream_id & 0x3F);
    
    /* 消息头（11字节，格式0）
     * 注意：这里应该是完整的消息头，不是FLV头！
     */
    
    /* 时间戳 (3字节大端) */
    chunk_header[chunk_header_len++] = (timestamp >> 16) & 0xFF;
    chunk_header[chunk_header_len++] = (timestamp >> 8) & 0xFF;
    chunk_header[chunk_header_len++] = timestamp & 0xFF;
    
    /* 消息长度 (3字节大端) */
    chunk_header[chunk_header_len++] = (payload_len >> 16) & 0xFF;
    chunk_header[chunk_header_len++] = (payload_len >> 8) & 0xFF;
    chunk_header[chunk_header_len++] = payload_len & 0xFF;
    
    /* 消息类型 (1字节) */
    chunk_header[chunk_header_len++] = msg_type;
    
    /* 流ID (4字节小端) */
    chunk_header[chunk_header_len++] = stream_id & 0xFF;
    chunk_header[chunk_header_len++] = (stream_id >> 8) & 0xFF;
    chunk_header[chunk_header_len++] = (stream_id >> 16) & 0xFF;
    chunk_header[chunk_header_len++] = (stream_id >> 24) & 0xFF;
    
    if (chunk_header_len != 12) {
        LLOGE("RTMP: Invalid chunk header length: %d", chunk_header_len);
        return RTMP_ERR_FAILED;
    }
    
    /* RTMP分块发送支持
     * 对于大消息，需要按照chunk_size分块发送
     * 每个块的格式：
     * - 第一个块：完整的块头(1字节) + 消息头(11字节) + 数据
     * - 后续块：简化块头(1字节，格式3) + 数据
     */
    
    uint32_t chunk_size = ctx->chunk_size;
    uint32_t bytes_sent = 0;
    
    /* 发送第一个块（带完整消息头）*/
    uint32_t first_chunk_data = (payload_len < chunk_size) ? payload_len : chunk_size;
    uint32_t first_chunk_total = chunk_header_len + first_chunk_data;
    
    /* 检查缓冲区空间 */
    if (ctx->send_pos + first_chunk_total > ctx->send_buf_size) {
        int ret = rtmp_flush_send_buffer(ctx);
        if (ret != RTMP_OK) {
            return ret;
        }
        
        /* 如果单个块都放不下，使用临时缓冲区 */
        if (first_chunk_total > ctx->send_buf_size) {
            /* 将块头和数据临时放入缓冲区 */
            memcpy(&ctx->send_buf[0], chunk_header, chunk_header_len);
            uint32_t copy_size = (first_chunk_data < ctx->send_buf_size - chunk_header_len) ? 
                                 first_chunk_data : (ctx->send_buf_size - chunk_header_len);
            memcpy(&ctx->send_buf[chunk_header_len], payload, copy_size);
            ctx->send_pos = chunk_header_len + copy_size;
            
            /* 发送缓冲区数据 */
            int ret = rtmp_flush_send_buffer(ctx);
            if (ret != RTMP_OK) {
                return ret;
            }
            
            bytes_sent = copy_size;
        } else {
            /* 放入缓冲区 */
            memcpy(&ctx->send_buf[ctx->send_pos], chunk_header, chunk_header_len);
            ctx->send_pos += chunk_header_len;
            memcpy(&ctx->send_buf[ctx->send_pos], payload, first_chunk_data);
            ctx->send_pos += first_chunk_data;
            bytes_sent = first_chunk_data;
        }
    } else {
        /* 正常情况：放入缓冲区 */
        memcpy(&ctx->send_buf[ctx->send_pos], chunk_header, chunk_header_len);
        ctx->send_pos += chunk_header_len;
        memcpy(&ctx->send_buf[ctx->send_pos], payload, first_chunk_data);
        ctx->send_pos += first_chunk_data;
        bytes_sent = first_chunk_data;
    }
    
    /* 发送后续块（如果有）*/
    while (bytes_sent < payload_len) {
        uint32_t remaining = payload_len - bytes_sent;
        uint32_t chunk_data_size = (remaining < chunk_size) ? remaining : chunk_size;
        
        /* 格式3的块头：只有1字节，表示延续前一个消息 */
        uint8_t continuation_header = (3 << 6) | (chunk_stream_id & 0x3F);
        
        uint32_t chunk_total = 1 + chunk_data_size;
        
        /* 检查缓冲区空间 */
        if (ctx->send_pos + chunk_total > ctx->send_buf_size) {
            int ret = rtmp_flush_send_buffer(ctx);
            if (ret != RTMP_OK) {
                return ret;
            }
            
            /* 如果缓冲区还是放不下，使用临时缓冲区 */
            if (chunk_total > ctx->send_buf_size) {
                ctx->send_buf[0] = continuation_header;
                uint32_t copy_size = (chunk_data_size < ctx->send_buf_size - 1) ? 
                                     chunk_data_size : (ctx->send_buf_size - 1);
                memcpy(&ctx->send_buf[1], &payload[bytes_sent], copy_size);
                ctx->send_pos = 1 + copy_size;
                
                int ret = rtmp_flush_send_buffer(ctx);
                if (ret != RTMP_OK) {
                    return ret;
                }
            } else {
                /* 放入缓冲区 */
                ctx->send_buf[ctx->send_pos++] = continuation_header;
                memcpy(&ctx->send_buf[ctx->send_pos], &payload[bytes_sent], chunk_data_size);
                ctx->send_pos += chunk_data_size;
            }
        } else {
            /* 正常情况：放入缓冲区 */
            ctx->send_buf[ctx->send_pos++] = continuation_header;
            memcpy(&ctx->send_buf[ctx->send_pos], &payload[bytes_sent], chunk_data_size);
            ctx->send_pos += chunk_data_size;
        }
        
        bytes_sent += chunk_data_size;
    }
    
    // LLOGI("RTMP: Packed RTMP message - type=%d, payload_len=%d, chunks=%d",
    //       msg_type, payload_len, (payload_len + chunk_size - 1) / chunk_size);
    
    return RTMP_OK;
}

/* ======================== 核心实现函数 ======================== */

/**
 * 创建RTMP推流上下文
 */
rtmp_ctx_t *g_rtmp_ctx;

rtmp_ctx_t* rtmp_create(void) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)luat_heap_malloc(sizeof(rtmp_ctx_t));
    if (!ctx) {
        LLOGE("RTMP: Failed to allocate context");
        return NULL;
    }
    
    memset(ctx, 0, sizeof(rtmp_ctx_t));
    
    /* 初始化chunk大小 */
    ctx->chunk_size = RTMP_DEFAULT_CHUNK_SIZE;
    
    /* 初始化缓冲区 */
    ctx->recv_buf = (uint8_t *)luat_heap_malloc(RTMP_BUFFER_SIZE);
    ctx->send_buf = (uint8_t *)luat_heap_malloc(RTMP_BUFFER_SIZE);
    
    if (!ctx->recv_buf || !ctx->send_buf) {
        LLOGE("RTMP: Failed to allocate buffers");
        if (ctx->recv_buf) luat_heap_free(ctx->recv_buf);
        if (ctx->send_buf) luat_heap_free(ctx->send_buf);
        luat_heap_free(ctx);
        return NULL;
    }
    
    ctx->recv_buf_size = RTMP_BUFFER_SIZE;
    ctx->send_buf_size = RTMP_BUFFER_SIZE;
    ctx->recv_pos = 0;
    ctx->send_pos = 0;
    
    /* 初始化默认块大小 */
    ctx->in_chunk_size = RTMP_DEFAULT_CHUNK_SIZE;
    ctx->out_chunk_size = RTMP_DEFAULT_CHUNK_SIZE;
    
    /* 初始化流ID */
    ctx->video_stream_id = 1;
    ctx->audio_stream_id = 1;
    
    /* 初始化端口 */
    ctx->port = RTMP_DEFAULT_PORT;
    
    /* 初始化状态 */
    ctx->state = RTMP_STATE_IDLE;
    
    LLOGD("RTMP: Context created successfully");
    g_rtmp_ctx = ctx;
    return ctx;
}

/**
 * 销毁RTMP推流上下文
 */
int rtmp_destroy(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    g_rtmp_ctx = NULL;
    
    /* 断开TCP连接 */
    if (ctx->pcb) {
        tcp_arg(ctx->pcb, NULL);
        tcp_recv(ctx->pcb, NULL);
        tcp_err(ctx->pcb, NULL);
        tcp_sent(ctx->pcb, NULL);
        tcp_close(ctx->pcb);
        ctx->pcb = NULL;
    }
    
    /* 释放内存 */
    if (ctx->url) luat_heap_free(ctx->url);
    if (ctx->host) luat_heap_free(ctx->host);
    if (ctx->app) luat_heap_free(ctx->app);
    if (ctx->stream) luat_heap_free(ctx->stream);
    if (ctx->auth) luat_heap_free(ctx->auth);
    if (ctx->recv_buf) luat_heap_free(ctx->recv_buf);
    if (ctx->send_buf) luat_heap_free(ctx->send_buf);

    /* 释放未发送的帧队列 */
    rtmp_frame_node_t *cur = ctx->frame_head;
    while (cur) {
        rtmp_frame_node_t *next = cur->next;
        rtmp_free_frame_node(cur);
        cur = next;
    }
    
    luat_heap_free(ctx);
    
    LLOGD("RTMP: Context destroyed");
    return RTMP_OK;
}

/**
 * 设置RTMP服务器URL
 */
int rtmp_set_url(rtmp_ctx_t *ctx, const char *url) {
    if (!ctx || !url) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    if (ctx->state != RTMP_STATE_IDLE && ctx->state != RTMP_STATE_ERROR) {
        LLOGE("RTMP: Cannot set URL while connected");
        return RTMP_ERR_FAILED;
    }
    
    return rtmp_parse_url(ctx, url);
}

/**
 * 连接到RTMP服务器
 */
int rtmp_connect(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    if (!ctx->host || !ctx->app || !ctx->stream) {
        LLOGE("RTMP: URL not set before connect");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 创建TCP控制块 */
    ctx->pcb = tcp_new();
    if (!ctx->pcb) {
        LLOGE("RTMP: Failed to create TCP PCB");
        return RTMP_ERR_NO_MEMORY;
    }
    
    tcp_arg(ctx->pcb, (void *)ctx);
    tcp_recv(ctx->pcb, rtmp_tcp_recv_callback);
    tcp_err(ctx->pcb, rtmp_tcp_error_callback);
    tcp_sent(ctx->pcb, rtmp_tcp_sent_callback);
    
    /* 将IP地址字符串转换为lwip ip_addr结构体 */
    ip_addr_t remote_addr;
    err_t parse_ret = ipaddr_aton(ctx->host, &remote_addr);
    
    if (!parse_ret) {
        LLOGE("RTMP: Invalid IP address: %s", ctx->host);
        tcp_close(ctx->pcb);
        ctx->pcb = NULL;
        return RTMP_ERR_INVALID_PARAM;
    }
    
    rtmp_set_state(ctx, RTMP_STATE_CONNECTING, 0);
    
    /* 发起TCP连接 */
    err_t err = tcp_connect(ctx->pcb, &remote_addr, ctx->port, rtmp_tcp_connect_callback);
    
    if (err != ERR_OK) {
        LLOGE("RTMP: TCP connect failed: %d", err);
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_CONNECT_FAILED);
        tcp_close(ctx->pcb);
        ctx->pcb = NULL;
        return RTMP_ERR_CONNECT_FAILED;
    }
    
    ctx->last_activity_time = rtmp_gen_timestamp();
    LLOGD("RTMP: Connecting to %s:%d (app:%s, stream:%s)", ctx->host, ctx->port, ctx->app, ctx->stream);
    
    return RTMP_OK;
}

/**
 * 断开RTMP连接
 */
int rtmp_disconnect(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    if (ctx->pcb) {
        rtmp_set_state(ctx, RTMP_STATE_DISCONNECTING, 0);
        tcp_close(ctx->pcb);
        ctx->pcb = NULL;
    }
    
    rtmp_set_state(ctx, RTMP_STATE_IDLE, 0);
    
    return RTMP_OK;
}

/**
 * 发送H.264 NALU帧
 */
int rtmp_send_nalu(rtmp_ctx_t *ctx, const uint8_t *nalu_data,
                   uint32_t nalu_len, uint32_t timestamp) {
    if (!ctx || !nalu_data || nalu_len == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    if (ctx->state != RTMP_STATE_CONNECTED && ctx->state != RTMP_STATE_PUBLISHING) {
        return RTMP_ERR_FAILED;
    }
    
    /* 分析输入数据，提取所有NALU单元
     * 格式: [起始码(0x00000001)] [NALU数据] [起始码] [NALU数据] ...
     * 对于I帧: 通常包含 SPS + PPS + IDR
     * 对于P帧: 只包含 P帧数据
     */
    
    typedef struct {
        const uint8_t *data;
        uint32_t len;
        uint8_t type;
    } nalu_info_t;
    
    nalu_info_t nalus[16];  /* 支持最多16个NALU */
    uint32_t nalu_count = 0;
    
    /* 扫描所有NALU单元 */
    uint32_t pos = 0;
    while (pos < nalu_len && nalu_count < 16) {
        /* 查找起始码 0x00000001 */
        if (pos + 4 <= nalu_len && 
            nalu_data[pos] == 0x00 && nalu_data[pos+1] == 0x00 && 
            nalu_data[pos+2] == 0x00 && nalu_data[pos+3] == 0x01) {
            
            uint32_t nalu_start = pos + 4;  /* 跳过起始码 */
            
            /* 查找下一个起始码或数据末尾 */
            uint32_t nalu_end = nalu_len;
            for (uint32_t i = nalu_start + 1; i + 3 < nalu_len; i++) {
                if (nalu_data[i] == 0x00 && nalu_data[i+1] == 0x00 && 
                    nalu_data[i+2] == 0x00 && nalu_data[i+3] == 0x01) {
                    nalu_end = i;
                    break;
                }
            }
            
            uint32_t current_nalu_len = nalu_end - nalu_start;
            
            if (current_nalu_len > 0 && nalu_start < nalu_len) {
                nalus[nalu_count].data = &nalu_data[nalu_start];
                nalus[nalu_count].len = current_nalu_len;
                nalus[nalu_count].type = nalu_data[nalu_start] & 0x1F;
                nalu_count++;
            }
            
            pos = nalu_end;
        } else {
            pos++;
        }
    }
    
    if (nalu_count == 0) {
        LLOGE("RTMP: No valid NALU found in input data");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 查找SPS、PPS和IDR */
    const uint8_t *sps_data = NULL, *pps_data = NULL, *idr_data = NULL;
    uint32_t sps_len = 0, pps_len = 0, idr_len = 0;
    bool has_p_frame = false;
    
    for (uint32_t i = 0; i < nalu_count; i++) {
        switch (nalus[i].type) {
            case NALU_TYPE_SPS:
                sps_data = nalus[i].data;
                sps_len = nalus[i].len;
                // LLOGD("RTMP: Found SPS, len=%u", sps_len);
                break;
            case NALU_TYPE_PPS:
                pps_data = nalus[i].data;
                pps_len = nalus[i].len;
                // LLOGD("RTMP: Found PPS, len=%u", pps_len);
                break;
            case NALU_TYPE_IDR:
                idr_data = nalus[i].data;
                idr_len = nalus[i].len;
                // LLOGD("RTMP: Found IDR, len=%u", idr_len);
                break;
            case NALU_TYPE_NON_IDR:
                has_p_frame = true;
                // LLOGD("RTMP: Found P-frame, len=%u", nalus[i].len);
                break;
        }
    }
    
    /* 如果有SPS和PPS，发送AVC Sequence Header */
    if (sps_data && pps_data) {
        // LLOGI("RTMP: Sending AVC Sequence Header (SPS+PPS)");
        
        /* 构建AVC Sequence Header
         * 格式: [configurationVersion(1)] [AVCProfileIndication(1)] [profile_compatibility(1)] 
         *       [AVCLevelIndication(1)] [lengthSizeMinusOne(1)] [numOfSPS(1)] 
         *       [spsLength(2)] [SPS data] [numOfPPS(1)] [ppsLength(2)] [PPS data]
         */
        uint32_t seq_header_size = 5 + 1 + 2 + sps_len + 1 + 2 + pps_len;
        uint8_t *seq_header = (uint8_t *)luat_heap_malloc(seq_header_size);
        if (!seq_header) {
            LLOGE("RTMP: Failed to allocate AVC sequence header");
            return RTMP_ERR_NO_MEMORY;
        }
        
        uint32_t offset = 0;
        seq_header[offset++] = 0x01;  /* configurationVersion */
        seq_header[offset++] = sps_data[1];  /* AVCProfileIndication */
        seq_header[offset++] = sps_data[2];  /* profile_compatibility */
        seq_header[offset++] = sps_data[3];  /* AVCLevelIndication */
        seq_header[offset++] = 0xFF;  /* lengthSizeMinusOne (4字节长度) */
        
        /* SPS */
        seq_header[offset++] = 0xE1;  /* numOfSPS = 1 (高3位保留为111) */
        write_be16(&seq_header[offset], sps_len);
        offset += 2;
        memcpy(&seq_header[offset], sps_data, sps_len);
        offset += sps_len;
        
        /* PPS */
        seq_header[offset++] = 0x01;  /* numOfPPS = 1 */
        write_be16(&seq_header[offset], pps_len);
        offset += 2;
        memcpy(&seq_header[offset], pps_data, pps_len);
        offset += pps_len;
        
        /* 发送AVC Sequence Header */
        int ret = rtmp_send_avc_sequence_header(ctx, seq_header, seq_header_size, timestamp);
        luat_heap_free(seq_header);
        
        if (ret != RTMP_OK) {
            LLOGE("RTMP: Failed to send AVC sequence header");
            return ret;
        }
    }
    
    /* 发送IDR帧（如果有）*/
    if (idr_data) {
        LLOGI("RTMP: Sending IDR frame, len=%u", idr_len);
        int ret = rtmp_send_single_nalu(ctx, idr_data, idr_len, timestamp);
        if (ret != RTMP_OK) {
            return ret;
        }
    }
    
    /* 发送P帧（如果有）*/
    if (has_p_frame) {
        for (uint32_t i = 0; i < nalu_count; i++) {
            if (nalus[i].type == NALU_TYPE_NON_IDR) {
                // LLOGI("RTMP: Sending P-frame, len=%u", nalus[i].len);
                int ret = rtmp_send_single_nalu(ctx, nalus[i].data, nalus[i].len, timestamp);
                if (ret != RTMP_OK) {
                    return ret;
                }
            }
        }
    }
    
    // LLOGD("RTMP: Video frame sent, timestamp=%u, nalus=%u", timestamp, nalu_count);
    
    return RTMP_OK;
}

/**
 * 发送AVC Sequence Header (SPS+PPS配置数据)
 * 这是H.264流的配置信息，必须在发送视频数据前发送
 */
static int rtmp_send_avc_sequence_header(rtmp_ctx_t *ctx, const uint8_t *seq_header,
                                        uint32_t seq_len, uint32_t timestamp) {
    if (!ctx || !seq_header || seq_len == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 构建RTMP视频消息
     * 格式: [FrameType+CodecID(1)] [AVCPacketType(1)] [CompositionTime(3)] [AVC Sequence Header]
     */
    uint32_t msg_len = 1 + 1 + 3 + seq_len;
    uint8_t *msg_buf = (uint8_t *)luat_heap_malloc(msg_len);
    if (!msg_buf) {
        LLOGE("RTMP: Failed to allocate buffer for AVC sequence header");
        return RTMP_ERR_NO_MEMORY;
    }
    
    uint32_t offset = 0;
    
    /* FrameType(4bit) + CodecID(4bit)
     * FrameType: 1=关键帧 (AVC Sequence Header作为关键帧发送)
     * CodecID: 7=H.264
     */
    msg_buf[offset++] = (1 << 4) | 7;
    
    /* AVCPacketType
     * 0 = AVC Sequence Header
     * 1 = AVC NALU
     * 2 = AVC End of Sequence
     */
    msg_buf[offset++] = 0;  /* AVC Sequence Header */
    
    /* CompositionTime (3字节，大端)
     * 对于Sequence Header总是0
     */
    msg_buf[offset++] = 0;
    msg_buf[offset++] = 0;
    msg_buf[offset++] = 0;
    
    /* AVC Sequence Header数据 */
    memcpy(&msg_buf[offset], seq_header, seq_len);
    offset += seq_len;
    
    /* 发送消息 (消息类型9=视频, 流ID=1)，放入帧队列 */
    uint8_t *rtmp_buf = NULL;
    uint32_t rtmp_len = 0;
    int ret = rtmp_build_rtmp_message(ctx, 9, msg_buf, msg_len, timestamp, 1, &rtmp_buf, &rtmp_len);
    luat_heap_free(msg_buf);
    if (ret != RTMP_OK) {
        LLOGE("RTMP: Failed to build RTMP message for AVC sequence header");
        return ret;
    }
    
    rtmp_frame_node_t *node = (rtmp_frame_node_t *)luat_heap_malloc(sizeof(rtmp_frame_node_t));
    if (!node) {
        luat_heap_free(rtmp_buf);
        return RTMP_ERR_NO_MEMORY;
    }
    node->data = rtmp_buf;
    node->len = rtmp_len;
    node->sent = 0;
    node->is_key = true; /* 配置按关键帧优先处理 */
    node->next = NULL;
    
    ret = rtmp_queue_frame(ctx, node);
    if (ret != RTMP_OK) {
        rtmp_free_frame_node(node);
        return ret;
    }
    
    // LLOGI("RTMP: AVC Sequence Header queued, size=%u", rtmp_len);
    
    return RTMP_OK;
}

/**
 * 发送单个NALU单元(内部函数)
 * 支持大数据帧(最大300KB+)
 */
static int rtmp_send_single_nalu(rtmp_ctx_t *ctx, const uint8_t *nalu_data,
                                uint32_t nalu_len, uint32_t timestamp) {
    if (!ctx || !nalu_data || nalu_len == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 构建视频消息 - 支持大数据 */
    uint32_t header_size = 11;  /* FLV标签头大小 */
    uint8_t header_buf[11];
    uint32_t header_len = 0;
    
    /* 获取NALU类型 */
    uint8_t nal_type = nalu_data[0] & 0x1F;
    
    /* 检查是否为关键帧(IDR) */
    bool is_key_frame = (nal_type == NALU_TYPE_IDR);
    
    /* 构建视频标签 */
    /* 视频标签格式: 帧类型(4bit) + 编码ID(4bit) */
    uint8_t tag_byte = 0;
    tag_byte |= (is_key_frame ? 1 : 2) << 4;  /* 帧类型: 1=关键帧, 2=普通帧 */
    tag_byte |= 7;                             /* 编码ID: 7=H.264 */
    
    header_buf[header_len++] = tag_byte;
    
    /* AVCPacketType: 1 = AVC NALU (视频数据) */
    header_buf[header_len++] = 1;
    
    /* 添加CTS (Composition Time Stamp) - 3字节大端 */
    header_buf[header_len++] = 0;
    header_buf[header_len++] = 0;
    header_buf[header_len++] = 0;
    
    /* 写入NALU长度(4字节大端) */
    write_be32(&header_buf[header_len], nalu_len);
    header_len += 4;
    
    /* 完整视频消息 = 头(11字节) + NALU数据 */
    uint32_t total_msg_len = header_len + nalu_len;

    uint8_t *msg_buf = (uint8_t *)luat_heap_malloc(total_msg_len);
    if (!msg_buf) {
        LLOGE("RTMP: Failed to allocate buffer for video message");
        return RTMP_ERR_NO_MEMORY;
    }

    memcpy(msg_buf, header_buf, header_len);
    memcpy(&msg_buf[header_len], nalu_data, nalu_len);

    /* 构建完整RTMP消息并入队 */
    uint8_t *rtmp_buf = NULL;
    uint32_t rtmp_len = 0;
    int ret = rtmp_build_rtmp_message(ctx, 9, msg_buf, total_msg_len, timestamp, 1, &rtmp_buf, &rtmp_len);
    luat_heap_free(msg_buf);
    if (ret != RTMP_OK) {
        return ret;
    }

    rtmp_frame_node_t *node = (rtmp_frame_node_t *)luat_heap_malloc(sizeof(rtmp_frame_node_t));
    if (!node) {
        luat_heap_free(rtmp_buf);
        return RTMP_ERR_NO_MEMORY;
    }
    node->data = rtmp_buf;
    node->len = rtmp_len;
    node->sent = 0;
    node->is_key = is_key_frame;
    node->next = NULL;

    ret = rtmp_queue_frame(ctx, node);
    if (ret != RTMP_OK) {
        rtmp_free_frame_node(node);
        return ret;
    }

    /* 更新统计 */
    ctx->video_timestamp = timestamp;
    ctx->packets_sent++;
    ctx->bytes_sent += nalu_len;

    return RTMP_OK;
}

/**
 * 发送多个NALU帧
 */
int rtmp_send_nalu_multi(rtmp_ctx_t *ctx, const uint8_t **nalus,
                         const uint32_t *lengths, uint32_t count,
                         uint32_t timestamp) {
    if (!ctx || !nalus || !lengths || count == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    for (uint32_t i = 0; i < count; i++) {
        int ret = rtmp_send_nalu(ctx, nalus[i], lengths[i], timestamp);
        if (ret != RTMP_OK) {
            return ret;
        }
    }
    
    return RTMP_OK;
}

/**
 * 获取当前连接状态
 */
rtmp_state_t rtmp_get_state(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_STATE_ERROR;
    }
    return ctx->state;
}

/**
 * 处理RTMP事件
 */
int rtmp_poll(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }

    /* 优先尝试发送队列中的数据 */
    rtmp_try_send_queue(ctx);
    
    /* 检查超时 */
    uint32_t now = rtmp_gen_timestamp();
    if (ctx->last_activity_time > 0 && 
        (now - ctx->last_activity_time) > RTMP_CMD_TIMEOUT) {
        
        if (ctx->state == RTMP_STATE_CONNECTING || 
            ctx->state == RTMP_STATE_HANDSHAKING) {
            rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_TIMEOUT);
            return RTMP_ERR_TIMEOUT;
        }
    }
    
    /* 处理收到的数据 */
    if (ctx->recv_pos > 0) {
        int ret = rtmp_process_data(ctx);
        if (ret < 0) {
            return ret;
        }
    }
    
    /* 发送缓冲的数据 */
    /* 在CONNECTED和PUBLISHING状态下都可以发送数据 */
    if (ctx->send_pos > 0 && (ctx->state == RTMP_STATE_PUBLISHING || 
                              ctx->state == RTMP_STATE_CONNECTED)) {
        int ret = rtmp_flush_send_buffer(ctx);
        if (ret < 0) {
            return ret;
        }
    }
    
    return RTMP_OK;
}

/**
 * 设置用户自定义数据
 */
int rtmp_set_user_data(rtmp_ctx_t *ctx, void *user_data) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    ctx->user_data = user_data;
    return RTMP_OK;
}

/**
 * 获取用户自定义数据
 */
void* rtmp_get_user_data(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return NULL;
    }
    return ctx->user_data;
}

/**
 * 获取统计信息
 */
int rtmp_get_stats(rtmp_ctx_t *ctx, rtmp_stats_t *stats) {
    if (!ctx || !stats) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    // 获取当前时间戳(毫秒)，用于计算连接持续时间
    uint32_t current_time = (uint32_t)(luat_mcu_tick64_ms());
    
    // 填充统计结构体
    stats->bytes_sent = ctx->bytes_sent;
    stats->packets_sent = ctx->packets_sent;
    stats->video_frames_sent = (ctx->video_timestamp > 0) ? (ctx->video_timestamp / 33 + 1) : 0;  // 估计帧数(30fps约33ms)
    stats->audio_frames_sent = 0;  // 当前仅支持视频
    stats->last_video_timestamp = ctx->video_timestamp;
    stats->last_audio_timestamp = ctx->audio_timestamp;
    
    // 计算连接持续时间
    if (ctx->base_timestamp > 0 && current_time >= ctx->base_timestamp) {
        stats->connection_time = current_time - ctx->base_timestamp;
    } else {
        stats->connection_time = 0;
    }
    
    return RTMP_OK;
}

/**
 * 设置状态变化回调函数
 */
int rtmp_set_state_callback(rtmp_ctx_t *ctx, rtmp_state_callback callback) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    g_state_callback = callback;
    return RTMP_OK;
}

/* ======================== 内部函数实现 ======================== */

/**
 * 解析URL并提取主机名、端口、应用名和流名
 */
static int rtmp_parse_url(rtmp_ctx_t *ctx, const char *url) {
    if (!url || strncmp(url, "rtmp://", 7) != 0) {
        LLOGE("RTMP: Invalid URL format %s", url ? url : "NULL");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    const char *ptr = url + 7;
    
    /* 提取主机名和端口 */
    char host[256] = {0};
    uint32_t host_len = 0;
    
    while (*ptr && *ptr != '/' && *ptr != ':' && host_len < sizeof(host) - 1) {
        host[host_len++] = *ptr++;
    }
    host[host_len] = '\0';
    
    /* 检查端口 */
    ctx->port = RTMP_DEFAULT_PORT;
    if (*ptr == ':') {
        ptr++;
        char port_str[10] = {0};
        uint32_t port_len = 0;
        
        while (*ptr && isdigit((unsigned char)*ptr) && port_len < sizeof(port_str) - 1) {
            port_str[port_len++] = *ptr++;
        }
        
        if (port_len > 0) {
            ctx->port = (uint16_t)atoi(port_str);
        }
    }
    
    /* 提取应用名和流名 */
    if (*ptr != '/') {
        LLOGE("RTMP: Invalid URL format, missing path");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    ptr++;  /* 跳过 '/' */
    
    char app[256] = {0};
    uint32_t app_len = 0;
    
    while (*ptr && *ptr != '/' && app_len < sizeof(app) - 1) {
        app[app_len++] = *ptr++;
    }
    app[app_len] = '\0';
    
    if (app_len == 0) {
        LLOGE("RTMP: Invalid URL format, missing app");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 提取流名 */
    char stream[256] = {0};
    uint32_t stream_len = 0;
    
    if (*ptr == '/') {
        ptr++;
        
        while (*ptr && stream_len < sizeof(stream) - 1) {
            stream[stream_len++] = *ptr++;
        }
    }
    stream[stream_len] = '\0';
    
    if (stream_len == 0) {
        LLOGE("RTMP: Invalid URL format, missing stream");
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 保存URL组件 */
    if (ctx->url) luat_heap_free(ctx->url);
    ctx->url = (char *)luat_heap_malloc(strlen(url) + 1);
    strcpy(ctx->url, url);
    
    if (ctx->host) luat_heap_free(ctx->host);
    ctx->host = (char *)luat_heap_malloc(strlen(host) + 1);
    strcpy(ctx->host, host);
    
    if (ctx->app) luat_heap_free(ctx->app);
    ctx->app = (char *)luat_heap_malloc(strlen(app) + 1);
    strcpy(ctx->app, app);
    
    if (ctx->stream) luat_heap_free(ctx->stream);
    ctx->stream = (char *)luat_heap_malloc(strlen(stream) + 1);
    strcpy(ctx->stream, stream);
    
    LLOGD("RTMP: URL parsed - host:%s, port:%d, app:%s, stream:%s",
                     host, ctx->port, ctx->app, ctx->stream);
    
    return RTMP_OK;
}

/**
 * TCP连接回调函数
 */
static err_t rtmp_tcp_connect_callback(void *arg, struct tcp_pcb *pcb, err_t err) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    
    if (err != ERR_OK) {
        LLOGE("RTMP: TCP connect failed: %d", err);
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_CONNECT_FAILED);
        return err;
    }
    
    LLOGD("RTMP: TCP connected %s:%d", ctx->host, ctx->port);
    
    /* 执行握手 */
    int ret = rtmp_do_handshake(ctx);
    if (ret != RTMP_OK) {
        rtmp_set_state(ctx, RTMP_STATE_ERROR, ret);
        return ERR_ABRT;
    }
    
    rtmp_set_state(ctx, RTMP_STATE_HANDSHAKING, 0);
    
    return ERR_OK;
}

static void rtmp_send_connect(void *arg) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    LLOGI("RTMP: Received %u bytes after C2, handshake confirmed", ctx->recv_pos);
    ctx->handshake_state = 3;
    rtmp_set_state(ctx, RTMP_STATE_HANDSHAKING, 0);
            
    /* 发送RTMP connect命令 */
    LLOGD("RTMP: Sending connect command...");
    LLOGD("before send buff offset=%d", ctx->send_pos);
    int ret = rtmp_send_command(ctx, "connect", 1, ctx->app);
    if (ret == 0) {
        rtmp_set_state(ctx, RTMP_STATE_CONNECTED, 0);
        LLOGI("RTMP: Connect command sent successfully");
        /* 握手状态机已完成，后续接收的数据是RTMP消息，需要处理 */
        ctx->recv_pos = 0;
    } else {
        LLOGE("RTMP: Failed to send connect command");
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_FAILED);
    }
}

/**
 * TCP接收回调函数
 */
static err_t rtmp_tcp_recv_callback(void *arg, struct tcp_pcb *pcb, struct pbuf *p, err_t err) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    if (arg == NULL) {
        LLOGE("RTMP: TCP recv callback with NULL arg");
        return ERR_ARG;
    }
    LLOGD("RTMP: TCP recv callback, err=%d, pbuf=%p len=%d", err, p, p ? p->tot_len : 0);
    if (err != ERR_OK) {
        LLOGE("RTMP: TCP recv error: %d", err);
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_NETWORK);
        return ERR_OK;
    }
    
    if (!p) {
        LLOGW("RTMP: TCP connection closed");
        rtmp_set_state(ctx, RTMP_STATE_IDLE, 0);
        return ERR_OK;
    }
    
    /* 将数据复制到接收缓冲区 */
    uint32_t copy_len = (p->tot_len < (ctx->recv_buf_size - ctx->recv_pos)) ?
                        p->tot_len : (ctx->recv_buf_size - ctx->recv_pos);
    LLOGI("RTMP: Copying %d bytes to recv buffer", copy_len);
    if (copy_len > 0) {
        LLOGD("ctx->recv_buf %p", ctx->recv_buf);
        LLOGD("ctx->recv_pos %d", ctx->recv_pos);
        LLOGD("p %p", p);
        pbuf_copy_partial(p, &ctx->recv_buf[ctx->recv_pos], copy_len, 0);
        
        ctx->recv_pos += copy_len;
    }
    
    LLOGI("RTMP: Received %d bytes, p->tot_len=%d", copy_len, p->tot_len);
    tcp_recved(pcb, p->tot_len);
    pbuf_free(p);
    
    ctx->last_activity_time = rtmp_gen_timestamp();
    
    /* 处理握手 */
    if (ctx->handshake_state == 1) {
        /* 等待接收完整的 S0+S1 (1+1536 = 1537 字节) */
        uint32_t required_len = 1 + RTMP_HANDSHAKE_CLIENT_SIZE;
        
        if (ctx->recv_pos >= required_len) {
            /* 验证S0版本号 */
            if (ctx->recv_buf[0] != 0x03) {
                LLOGE("RTMP: Invalid RTMP version from server: %d", ctx->recv_buf[0]);
                rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_HANDSHAKE_FAILED);
                return ERR_ABRT;
            }
            
            /* 已收到完整的S0+S1,现在发送C2 */
            /* C2 是 S1 的完整 1536 字节回显 */
            LLOGI("RTMP: Received complete S0+S1 (%u bytes), sending C2...", required_len);
            
            err_t err = tcp_write(ctx->pcb, &ctx->recv_buf[1], RTMP_HANDSHAKE_CLIENT_SIZE, TCP_WRITE_FLAG_COPY);
            
            if (err != ERR_OK) {
                LLOGE("RTMP: Failed to send C2: %d", err);
                rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_NETWORK);
                return ERR_ABRT;
            }
            
            tcp_output(ctx->pcb);
            
            LLOGI("RTMP: C2 sent successfully (exactly %u bytes, S1 echo)", RTMP_HANDSHAKE_CLIENT_SIZE);
            
            /* 握手状态转为2，等待握手完全完成或后续RTMP数据 */
            ctx->handshake_state = 2;
            
            /* 移除已处理的握手数据，保留剩余数据用于后续RTMP消息处理 */
            if (ctx->recv_pos > required_len) {
                /* 还有剩余数据（可能是服务器握手确认或RTMP消息），需要左移 */
                LLOGI("RTMP: Extra data after S0+S1: %u bytes", ctx->recv_pos - required_len);
                memmove(ctx->recv_buf, &ctx->recv_buf[required_len], ctx->recv_pos - required_len);
                ctx->recv_pos -= required_len;
                LLOGD("RTMP: Buffer adjusted, remaining: %u bytes", ctx->recv_pos);
            } else {
                /* 恰好接收到S0+S1，没有剩余数据 */
                ctx->recv_pos = 0;
                LLOGD("RTMP: No extra data after S0+S1, buffer cleared");
            }
        } else {
            /* 数据不足，继续等待 */
            LLOGD("RTMP: Waiting for complete S0+S1... received %u/%u bytes", ctx->recv_pos, required_len);
        }
    } 
    else if (ctx->handshake_state == 2) {
        /* 握手已发送C2
           根据RTMP规范，握手完成后，可以直接开始发送RTMP消息
           或等待服务器响应。这里我们检查是否有新数据到达
           如果有新数据，说明服务器已确认握手，可以继续 */
        
        if (ctx->recv_pos >= RTMP_HANDSHAKE_SIZE) {
            sys_timeout(100, rtmp_send_connect, (void *)ctx);
        }
    }
    
    return ERR_OK;
}

/**
 * TCP错误回调函数
 */
static void rtmp_tcp_error_callback(void *arg, err_t err) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    
    LLOGE("RTMP: TCP error: %d", err);
    
    if (ctx) {
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_NETWORK);
        ctx->pcb = NULL;
    }
}

/**
 * TCP发送回调函数
 */
static err_t rtmp_tcp_sent_callback(void *arg, struct tcp_pcb *pcb, u16_t len) {
    rtmp_ctx_t *ctx = (rtmp_ctx_t *)arg;
    static uint64_t total_sent = 0;
    total_sent += len;
    //LLOGD("RTMP: TCP sent callback, len=%d, total_sent=%llu", len, total_sent);
    if (ctx) {
        ctx->bytes_sent += len;
        /* 继续发送队列中的数据 */
        rtmp_try_send_queue(ctx);
    }
    
    return ERR_OK;
}

/**
 * 执行RTMP握手
 */
static int rtmp_do_handshake(rtmp_ctx_t *ctx) {
    /* 生成C0和C1数据 */
    uint8_t handshake[1 + RTMP_HANDSHAKE_CLIENT_SIZE];
    
    /* C0: 版本号 */
    handshake[0] = 0x03;  /* RTMP版本3 */
    
    /* C1: 握手数据 */
    uint32_t timestamp = rtmp_gen_timestamp();
    write_be32(&handshake[1], timestamp);
    
    /* Zero字段 */
    memset(&handshake[5], 0, 4);
    
    /* 随机数据 */
    for (uint32_t i = 9; i < 1 + RTMP_HANDSHAKE_CLIENT_SIZE; i++) {
        handshake[i] = (uint8_t)(rand() & 0xFF);
    }
    
    /* 发送握手数据 */
    LLOGI("RTMP: Sending handshake (C0+C1)...");
    err_t err = tcp_write(ctx->pcb, handshake, sizeof(handshake), TCP_WRITE_FLAG_COPY);
    
    if (err != ERR_OK) {
        LLOGE("RTMP: Failed to send handshake: %d", err);
        return RTMP_ERR_NETWORK;
    }
    
    tcp_output(ctx->pcb);
    
    LLOGD("RTMP: C0+C1 sent (%d bytes), waiting for S0+S1...", sizeof(handshake));
    
    /* 设置握手状态为等待S0+S1 */
    ctx->handshake_state = 1;
    
    return RTMP_OK;
}

/**
 * 处理握手响应
 */
static int rtmp_process_handshake_response(rtmp_ctx_t *ctx) {
    /* 检查收到的数据是否足够 */
    if (ctx->recv_pos < 1 + 2 * RTMP_HANDSHAKE_CLIENT_SIZE) {
        return RTMP_OK;  /* 数据不足,继续等待 */
    }
    
    /* S0: 版本号 */
    if (ctx->recv_buf[0] != 0x03) {
        LLOGE("RTMP: Invalid RTMP version from server %d", ctx->recv_buf[0]);
        return RTMP_ERR_HANDSHAKE_FAILED;
    }
    
    /* 握手完成,发送connect命令 */
    rtmp_set_state(ctx, RTMP_STATE_CONNECTED, 0);
    
    /* 发送connect命令 */
    int ret = rtmp_send_command(ctx, "connect", 1, ctx->app);
    if (ret != RTMP_OK) {
        return ret;
    }
    
    /* 清空接收缓冲区 */
    ctx->recv_pos = 0;
    
    return RTMP_OK;
}

/**
 * 发送 @setDataFrame 元数据
 * 用于设置视频流的元信息
 */
static int rtmp_send_metadata(rtmp_ctx_t *ctx) {
    if (!ctx) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    uint8_t amf_buf[512] = {0};
    uint32_t offset = 0;
    
    /* 1. 写入命令名称 "@setDataFrame" */
    const char *cmd = "@setDataFrame";
    amf_buf[offset++] = AMF_TYPE_STRING;
    write_be16(&amf_buf[offset], strlen(cmd));
    offset += 2;
    memcpy(&amf_buf[offset], cmd, strlen(cmd));
    offset += strlen(cmd);
    
    /* 2. 写入元数据类型 "onMetaData" */
    const char *meta_type = "onMetaData";
    amf_buf[offset++] = AMF_TYPE_STRING;
    write_be16(&amf_buf[offset], strlen(meta_type));
    offset += 2;
    memcpy(&amf_buf[offset], meta_type, strlen(meta_type));
    offset += strlen(meta_type);
    
    /* 3. 写入元数据对象 */
    amf_buf[offset++] = AMF_TYPE_OBJECT;
    
    /* duration */
    {
        const char *key = "duration";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 0.0;
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* width */
    {
        const char *key = "width";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 1280.0;  /* 默认1280 */
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* height */
    {
        const char *key = "height";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 720.0;  /* 默认720 */
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* videodatarate */
    {
        const char *key = "videodatarate";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 2500.0;  /* 2.5 Mbps */
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* framerate */
    {
        const char *key = "framerate";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 30.0;  /* 30 fps */
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* videocodecid */
    {
        const char *key = "videocodecid";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        amf_buf[offset++] = AMF_TYPE_NUMBER;
        double val = 7.0;  /* 7 = H.264 */
        uint64_t bits = *(uint64_t *)&val;
        for (int i = 0; i < 8; i++) {
            amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
        }
    }
    
    /* encoder */
    {
        const char *key = "encoder";
        write_be16(&amf_buf[offset], strlen(key));
        offset += 2;
        memcpy(&amf_buf[offset], key, strlen(key));
        offset += strlen(key);
        
        const char *val = "LuatOS RTMP";
        amf_buf[offset++] = AMF_TYPE_STRING;
        write_be16(&amf_buf[offset], strlen(val));
        offset += 2;
        memcpy(&amf_buf[offset], val, strlen(val));
        offset += strlen(val);
    }
    
    /* 对象结束 */
    amf_buf[offset++] = 0x00;
    amf_buf[offset++] = 0x00;
    amf_buf[offset++] = AMF_TYPE_OBJECT_END;
    
    /* 检查缓冲区大小 */
    if (offset > sizeof(amf_buf)) {
        LLOGE("RTMP: Metadata buffer overflow");
        return RTMP_ERR_BUFFER_OVERFLOW;
    }
    
    LLOGI("RTMP: Metadata payload size: %u bytes", offset);
    
    /* 发送元数据作为数据消息 (类型18) */
    int ret = rtmp_pack_message(ctx, 18, amf_buf, offset, 0, 1);
    
    if (ret != RTMP_OK) {
        LLOGE("RTMP: Failed to pack metadata message: %d", ret);
        return ret;
    }
    
    /* 立即发送 */
    ret = rtmp_flush_send_buffer(ctx);
    
    LLOGI("RTMP: Metadata @setDataFrame sent successfully");
    
    return ret;
}

/* ========== 帧队列与发送 ========== */

static void rtmp_free_frame_node(rtmp_frame_node_t *node) {
    if (!node) return;
    if (node->data) {
        luat_heap_free(node->data);
    }
    luat_heap_free(node);
}

/* 构建完整的RTMP消息（包含chunk分片），返回新分配的缓冲区 */
static int rtmp_build_rtmp_message(rtmp_ctx_t *ctx, uint8_t msg_type,
                                  const uint8_t *payload, uint32_t payload_len,
                                  uint32_t timestamp, uint32_t stream_id,
                                  uint8_t **out_buf, uint32_t *out_len) {
    if (!ctx || !payload || payload_len == 0 || !out_buf || !out_len) {
        return RTMP_ERR_INVALID_PARAM;
    }

    uint32_t chunk_size = ctx->chunk_size ? ctx->chunk_size : RTMP_DEFAULT_CHUNK_SIZE;
    uint8_t chunk_stream_id = (msg_type == 20 || msg_type == 17) ? 3 : 4;

    uint32_t num_chunks = (payload_len + chunk_size - 1) / chunk_size;
    uint32_t total_len = 12 + payload_len;           /* 首块含完整头 */
    if (num_chunks > 1) {
        total_len += (num_chunks - 1);               /* 每个后续块1字节继续头 */
    }

    uint8_t *buf = (uint8_t *)luat_heap_malloc(total_len);
    if (!buf) {
        return RTMP_ERR_NO_MEMORY;
    }

    uint32_t offset = 0;

    /* 首块头：fmt0 */
    buf[offset++] = (0 << 6) | (chunk_stream_id & 0x3F);
    buf[offset++] = (timestamp >> 16) & 0xFF;
    buf[offset++] = (timestamp >> 8) & 0xFF;
    buf[offset++] = timestamp & 0xFF;
    buf[offset++] = (payload_len >> 16) & 0xFF;
    buf[offset++] = (payload_len >> 8) & 0xFF;
    buf[offset++] = payload_len & 0xFF;
    buf[offset++] = msg_type;
    buf[offset++] = stream_id & 0xFF;
    buf[offset++] = (stream_id >> 8) & 0xFF;
    buf[offset++] = (stream_id >> 16) & 0xFF;
    buf[offset++] = (stream_id >> 24) & 0xFF;

    /* 数据拷贝，带继续块头 */
    uint32_t sent = 0;
    uint32_t first_copy = (payload_len < chunk_size) ? payload_len : chunk_size;
    memcpy(&buf[offset], payload, first_copy);
    offset += first_copy;
    sent += first_copy;

    while (sent < payload_len) {
        uint32_t remain = payload_len - sent;
        uint32_t copy_len = (remain < chunk_size) ? remain : chunk_size;
        buf[offset++] = (3 << 6) | (chunk_stream_id & 0x3F); /* continuation header */
        memcpy(&buf[offset], &payload[sent], copy_len);
        offset += copy_len;
        sent += copy_len;
    }

    *out_buf = buf;
    *out_len = offset;
    return RTMP_OK;
}

/* 入队帧，必要时丢弃未开始发送的旧帧 */
static int rtmp_queue_frame(rtmp_ctx_t *ctx, rtmp_frame_node_t *node) {
    if (!ctx || !node) return RTMP_ERR_INVALID_PARAM;

    /* 拥堵且来了关键帧，丢弃所有未开始发送的帧（sent==0） */
    if (node->is_key && ctx->frame_head) {
        rtmp_frame_node_t *cur = ctx->frame_head;
        rtmp_frame_node_t *prev = NULL;
        while (cur) {
            if (cur->sent == 0) {
                rtmp_frame_node_t *to_free = cur;
                cur = cur->next;
                if (prev) prev->next = cur; else ctx->frame_head = cur;
                if (to_free == ctx->frame_tail) ctx->frame_tail = prev;
                ctx->frame_queue_bytes -= to_free->len;
                rtmp_free_frame_node(to_free);
                continue;
            }
            prev = cur;
            cur = cur->next;
        }
    }

    /* 水位控制：超限则优先丢弃未发送的非关键帧，再丢未发送的旧帧 */
    uint32_t need_bytes = node->len;
    rtmp_frame_node_t *cur = ctx->frame_head;
    rtmp_frame_node_t *prev = NULL;
    while (ctx->frame_queue_bytes + need_bytes > RTMP_MAX_QUEUE_BYTES && cur) {
        if (cur->sent == 0 && !cur->is_key) {
            rtmp_frame_node_t *to_free = cur;
            cur = cur->next;
            if (prev) prev->next = cur; else ctx->frame_head = cur;
            if (to_free == ctx->frame_tail) ctx->frame_tail = prev;
            ctx->frame_queue_bytes -= to_free->len;
            rtmp_free_frame_node(to_free);
            continue;
        }
        prev = cur;
        cur = cur->next;
    }

    cur = ctx->frame_head;
    prev = NULL;
    while (ctx->frame_queue_bytes + need_bytes > RTMP_MAX_QUEUE_BYTES && cur) {
        if (cur->sent == 0) {
            rtmp_frame_node_t *to_free = cur;
            cur = cur->next;
            if (prev) prev->next = cur; else ctx->frame_head = cur;
            if (to_free == ctx->frame_tail) ctx->frame_tail = prev;
            ctx->frame_queue_bytes -= to_free->len;
            rtmp_free_frame_node(to_free);
            continue;
        }
        prev = cur;
        cur = cur->next;
    }

    /* 仍然超限，则放弃当前帧 */
    if (ctx->frame_queue_bytes + need_bytes > RTMP_MAX_QUEUE_BYTES) {
        LLOGE("RTMP: Drop frame, queue bytes %u exceed max %u", ctx->frame_queue_bytes + need_bytes, RTMP_MAX_QUEUE_BYTES);
        return RTMP_ERR_BUFFER_OVERFLOW;
    }

    /* 追加到队尾 */
    node->next = NULL;
    if (ctx->frame_tail) {
        ctx->frame_tail->next = node;
    } else {
        ctx->frame_head = node;
    }
    ctx->frame_tail = node;
    ctx->frame_queue_bytes += node->len;

    /* 尝试立即发送 */
    rtmp_try_send_queue(ctx);

    return RTMP_OK;
}

/* 发送队列中的数据，逐chunk写入lwip */
static void rtmp_try_send_queue(rtmp_ctx_t *ctx) {
    if (!ctx || !ctx->pcb) return;

    while (ctx->frame_head) {
        rtmp_frame_node_t *node = ctx->frame_head;
        uint32_t remaining = node->len - node->sent;
        if (remaining == 0) {
            ctx->frame_head = node->next;
            if (ctx->frame_head == NULL) ctx->frame_tail = NULL;
            if (ctx->frame_queue_bytes >= node->len) ctx->frame_queue_bytes -= node->len; else ctx->frame_queue_bytes = 0;
            rtmp_free_frame_node(node);
            continue;
        }

        u16_t snd_avail = tcp_sndbuf(ctx->pcb);
        if (snd_avail == 0) {
            tcp_output(ctx->pcb);
            break;
        }

        uint32_t to_send = remaining < snd_avail ? remaining : snd_avail;
        /* 在空闲时多发，拥堵时受snd_avail限制；上限设为8KB */
        if (to_send > 8192) to_send = 8192;

        err_t err = tcp_write(ctx->pcb, node->data + node->sent, to_send, TCP_WRITE_FLAG_COPY);
        if (err != ERR_OK) {
            LLOGE("RTMP: tcp_write queue failed %d", err);
            break;
        }
        node->sent += to_send;

        tcp_output(ctx->pcb);

        if (node->sent >= node->len) {
            ctx->frame_head = node->next;
            if (ctx->frame_head == NULL) ctx->frame_tail = NULL;
            if (ctx->frame_queue_bytes >= node->len) ctx->frame_queue_bytes -= node->len; else ctx->frame_queue_bytes = 0;
            rtmp_free_frame_node(node);
        } else {
            /* 发送缓冲区不足，等待sent回调继续 */
            break;
        }
    }
}

/**
 * 发送RTMP命令
 */
static int rtmp_send_command(rtmp_ctx_t *ctx, const char *command,
                            uint32_t transaction_id, const char *args) {
    if (!ctx || !command) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    uint8_t amf_buf[512] = {0};
    uint32_t offset = 0;
    
    /* AMF消息格式:
     * 1. 命令名称 (String) - "connect"
     * 2. 事务ID (Number)
     * 3. 命令对象 (Object) - connect参数
     * 4. (可选) 附加参数
     */
    
    /* 1. 写入命令名称 */
    amf_buf[offset++] = AMF_TYPE_STRING;
    uint32_t cmd_len = strlen(command);
    write_be16(&amf_buf[offset], (uint16_t)cmd_len);
    offset += 2;
    memcpy(&amf_buf[offset], command, cmd_len);
    offset += cmd_len;
    
    LLOGD("RTMP: Command name: %s (len=%u)", command, cmd_len);
    
    /* 2. 写入事务ID */
    amf_buf[offset++] = AMF_TYPE_NUMBER;
    /* 转换double */
    double trans_id = (double)transaction_id;
    uint64_t bits = *(uint64_t *)&trans_id;
    for (int i = 0; i < 8; i++) {
        amf_buf[offset++] = (uint8_t)(bits >> (56 - i * 8));
    }
    
    LLOGD("RTMP: Transaction ID: %u", transaction_id);
    
    /* 3. 写入命令对象或参数 */
    if (strcmp(command, "connect") == 0) {
        /* connect 命令：带详细参数对象 */
        amf_buf[offset++] = AMF_TYPE_OBJECT;
        
        /* 3.1 app 参数 */
        if (ctx->app) {
            const char *key = "app";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_STRING;
            write_be16(&amf_buf[offset], strlen(ctx->app));
            offset += 2;
            memcpy(&amf_buf[offset], ctx->app, strlen(ctx->app));
            offset += strlen(ctx->app);
            
            LLOGD("RTMP: Parameter - app: %s", ctx->app);
        }
        
        /* 3.2 flashVer 参数 */
        {
            const char *key = "flashVer";
            const char *val = "LNX 9,0,124,2";
            
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_STRING;
            write_be16(&amf_buf[offset], strlen(val));
            offset += 2;
            memcpy(&amf_buf[offset], val, strlen(val));
            offset += strlen(val);
            
            LLOGD("RTMP: Parameter - flashVer: %s", val);
        }
        
        /* 3.3 tcUrl 参数 */
        if (ctx->url) {
            const char *key = "tcUrl";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_STRING;
            write_be16(&amf_buf[offset], strlen(ctx->url));
            offset += 2;
            memcpy(&amf_buf[offset], ctx->url, strlen(ctx->url));
            offset += strlen(ctx->url);
            
            LLOGD("RTMP: Parameter - tcUrl: %s", ctx->url);
        }
        
        /* 3.4 fpad 参数 */
        {
            const char *key = "fpad";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_BOOLEAN;
            amf_buf[offset++] = 0;  /* false */
            
            LLOGD("RTMP: Parameter - fpad: false");
        }
        
        /* 3.5 audioCodecs 参数 */
        if (0) {
            const char *key = "audioCodecs";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_NUMBER;
            double codec_val = 3575.0;  /* 支持的音频编码 */
            uint64_t codec_bits = *(uint64_t *)&codec_val;
            for (int i = 0; i < 8; i++) {
                amf_buf[offset++] = (uint8_t)(codec_bits >> (56 - i * 8));
            }
            
            LLOGD("RTMP: Parameter - audioCodecs: 3575.0");
        }
        
        /* 3.6 videoCodecs 参数 */
        if (0) {
            const char *key = "videoCodecs";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_NUMBER;
            double codec_val = 252.0;  /* 支持的视频编码 */
            uint64_t codec_bits = *(uint64_t *)&codec_val;
            for (int i = 0; i < 8; i++) {
                amf_buf[offset++] = (uint8_t)(codec_bits >> (56 - i * 8));
            }
            
            LLOGD("RTMP: Parameter - videoCodecs: 252.0");
        }
        
        /* 3.7 objectEncoding 参数 */
        if (0) {
            const char *key = "objectEncoding";
            write_be16(&amf_buf[offset], strlen(key));
            offset += 2;
            memcpy(&amf_buf[offset], key, strlen(key));
            offset += strlen(key);
            
            amf_buf[offset++] = AMF_TYPE_NUMBER;
            double enc_val = 0.0;
            uint64_t enc_bits = *(uint64_t *)&enc_val;
            for (int i = 0; i < 8; i++) {
                amf_buf[offset++] = (uint8_t)(enc_bits >> (56 - i * 8));
            }
            
            LLOGD("RTMP: Parameter - objectEncoding: 0.0");
        }
        
        /* 对象结束 */
        amf_buf[offset++] = 0x00;
        amf_buf[offset++] = 0x00;
        amf_buf[offset++] = AMF_TYPE_OBJECT_END;
        
    } else if (strcmp(command, "releaseStream") == 0 || 
               strcmp(command, "FCPublish") == 0 ||
               strcmp(command, "FCUnpublish") == 0) {
        /* releaseStream / FCPublish / FCUnpublish 命令：NULL对象 + 流名称 */
        amf_buf[offset++] = AMF_TYPE_NULL;  /* 命令对象为null */
        
        /* 流名称参数 */
        if (ctx->stream) {
            amf_buf[offset++] = AMF_TYPE_STRING;
            write_be16(&amf_buf[offset], strlen(ctx->stream));
            offset += 2;
            memcpy(&amf_buf[offset], ctx->stream, strlen(ctx->stream));
            offset += strlen(ctx->stream);
            
            LLOGD("RTMP: Parameter - stream: %s", ctx->stream);
        }
        
    } else if (strcmp(command, "createStream") == 0) {
        /* createStream 命令：NULL对象 */
        amf_buf[offset++] = AMF_TYPE_NULL;
        LLOGD("RTMP: createStream with NULL object");
        
    } else if (strcmp(command, "publish") == 0) {
        /* publish 命令：NULL对象 + 流名称 + 发布类型 */
        amf_buf[offset++] = AMF_TYPE_NULL;
        
        /* 流名称 */
        if (ctx->stream) {
            amf_buf[offset++] = AMF_TYPE_STRING;
            write_be16(&amf_buf[offset], strlen(ctx->stream));
            offset += 2;
            memcpy(&amf_buf[offset], ctx->stream, strlen(ctx->stream));
            offset += strlen(ctx->stream);
        }
        
        /* 发布类型："live" */
        const char *pub_type = "live";
        amf_buf[offset++] = AMF_TYPE_STRING;
        write_be16(&amf_buf[offset], strlen(pub_type));
        offset += 2;
        memcpy(&amf_buf[offset], pub_type, strlen(pub_type));
        offset += strlen(pub_type);
        
        LLOGD("RTMP: publish - stream: %s, type: %s", ctx->stream ? ctx->stream : "NULL", pub_type);
    }
    
    /* 检查缓冲区大小 */
    if (offset > sizeof(amf_buf)) {
        LLOGE("RTMP: AMF buffer overflow");
        return RTMP_ERR_BUFFER_OVERFLOW;
    }
    
    LLOGI("RTMP: AMF payload size: %u bytes", offset);
    
    /* 打印前64字节的hex数据用于调试 */
    {
        uint32_t print_len = (offset > 64) ? 64 : offset;
        LLOGI("RTMP: AMF payload (first %u bytes):", print_len);
        
        char hex_buf[256] = {0};
        uint32_t hex_pos = 0;
        
        for (uint32_t i = 0; i < print_len; i++) {
            hex_pos += snprintf(&hex_buf[hex_pos], sizeof(hex_buf) - hex_pos, "%02X ", amf_buf[i]);
            if ((i + 1) % 16 == 0 && i + 1 < print_len) {
                LLOGD("RTMP:   %s", hex_buf);
                hex_pos = 0;
                memset(hex_buf, 0, sizeof(hex_buf));
            }
        }
        
        if (hex_pos > 0) {
            LLOGD("RTMP:   %s", hex_buf);
        }
    }
    
    /* 发送connect命令作为RTMP消息 */
    /* 消息类型 20 = 命令消息 (AMF0) */
    int ret = rtmp_pack_message(ctx, 20, amf_buf, offset, 0, 0);
    
    if (ret != RTMP_OK) {
        LLOGE("RTMP: Failed to pack connect message: %d", ret);
        return ret;
    }
    
    /* 立即发送connect命令 */
    ret = rtmp_flush_send_buffer(ctx);
    
    LLOGI("RTMP: Connect command sent successfully: %s (tx_id=%u, payload_size=%u bytes)", 
          command, transaction_id, offset);
    
    return ret;
}

/**
 * 处理收到的RTMP数据
 */
static int rtmp_process_data(rtmp_ctx_t *ctx) {
    /* RTMP消息解析和处理
     * 
     * RTMP消息格式:
     * - 块头 (1-3字节)
     * - 消息头 (0/3/7/11字节)
     * - 块数据 (可变长)
     * 
     * 消息头格式(最多11字节):
     * - 消息类型 (1字节): 8=音频, 9=视频, 18=数据, 20=命令(AMF0)
     * - 消息长度 (3字节大端)
     * - 时间戳 (3字节大端)
     * - 扩展时间戳 (1字节)
     * - 流ID (3字节大端)
     */
    
    if (!ctx || ctx->recv_pos == 0) {
        return RTMP_OK;
    }
    
    /* 简化实现: 寻找响应中的onStatus/NetConnection.Connect.Success */
    /* 完整实现应该解析块头和消息头 */
    
    uint32_t pos = 0;
    
    /* 搜索响应字符串 */
    const char *success_str = "NetConnection.Connect.Success";
    const char *on_status_str = "onStatus";
    const char *failed_str = "NetConnection.Connect.Failed";
    const char *result_str = "_result";
    const char *publish_start_str = "NetStream.Publish.Start";
    
    bool found_success = false;
    bool found_failed = false;
    bool found_on_status = false;
    bool found_result = false;
    bool found_publish_start = false;
    
    /* 在接收缓冲区中搜索这些字符串 */
    while (pos < ctx->recv_pos) {
        /* 检查 connect success */
        if (!found_success && pos + strlen(success_str) <= ctx->recv_pos) {
            if (memcmp(&ctx->recv_buf[pos], success_str, strlen(success_str)) == 0) {
                found_success = true;
                LLOGD("RTMP: Found NetConnection.Connect.Success");
                break;
            }
        }
        
        /* 检查 connect failed */
        if (!found_failed && pos + strlen(failed_str) <= ctx->recv_pos) {
            if (memcmp(&ctx->recv_buf[pos], failed_str, strlen(failed_str)) == 0) {
                found_failed = true;
                LLOGD("RTMP: Found NetConnection.Connect.Failed");
                break;
            }
        }
        
        /* 检查 _result (createStream响应) */
        if (!found_result && pos + strlen(result_str) <= ctx->recv_pos) {
            if (memcmp(&ctx->recv_buf[pos], result_str, strlen(result_str)) == 0) {
                found_result = true;
                LLOGD("RTMP: Found _result response");
            }
        }
        
        /* 检查 publish start */
        if (!found_publish_start && pos + strlen(publish_start_str) <= ctx->recv_pos) {
            if (memcmp(&ctx->recv_buf[pos], publish_start_str, strlen(publish_start_str)) == 0) {
                found_publish_start = true;
                LLOGD("RTMP: Found NetStream.Publish.Start");
            }
        }
        
        /* 检查 onStatus */
        if (!found_on_status && pos + strlen(on_status_str) <= ctx->recv_pos) {
            if (memcmp(&ctx->recv_buf[pos], on_status_str, strlen(on_status_str)) == 0) {
                found_on_status = true;
                LLOGD("RTMP: Found onStatus command");
            }
        }
        
        pos++;
    }
    
    /* 根据查找结果更新状态 */
    if (found_success) {
        /* 连接成功,开始发送发布流的控制命令 */
        LLOGI("RTMP: Connection successful, sending publish commands...");
        
        /* 1. 发送 setChunkSize */
        uint8_t chunk_size_msg[4];
        uint32_t new_chunk_size = 4096;  /* 设置为4KB */
        write_be32(chunk_size_msg, new_chunk_size);
        
        int ret = rtmp_pack_message(ctx, 1, chunk_size_msg, sizeof(chunk_size_msg), 0, 0);
        if (ret == RTMP_OK) {
            ctx->out_chunk_size = new_chunk_size;
            ctx->chunk_size = new_chunk_size;  /* 更新实际使用的chunk大小 */
            LLOGI("RTMP: Sent setChunkSize: %u", new_chunk_size);
        }
        
        /* 2. 发送 releaseStream */
        ret = rtmp_send_command(ctx, "releaseStream", 2, NULL);
        if (ret == RTMP_OK) {
            LLOGI("RTMP: Sent releaseStream");
        }
        
        /* 3. 发送 FCPublish */
        ret = rtmp_send_command(ctx, "FCPublish", 3, NULL);
        if (ret == RTMP_OK) {
            LLOGI("RTMP: Sent FCPublish");
        }
        
        /* 4. 发送 createStream */
        ret = rtmp_send_command(ctx, "createStream", 4, NULL);
        if (ret == RTMP_OK) {
            LLOGI("RTMP: Sent createStream");
        }
        
        /* 立即发送缓冲数据 */
        rtmp_flush_send_buffer(ctx);
        
        LLOGI("RTMP: Sent publish control commands, waiting for createStream response");
        
    } else if (found_result && ctx->state == RTMP_STATE_CONNECTED) {
        /* 收到 _result 响应（createStream的响应）
         * 现在可以发送 publish 命令了 */
        LLOGI("RTMP: Received createStream _result, sending publish command...");
        
        /* 发送 publish 命令 */
        int ret = rtmp_send_command(ctx, "publish", 5, NULL);
        if (ret == RTMP_OK) {
            LLOGI("RTMP: Sent publish command");
            rtmp_flush_send_buffer(ctx);
        } else {
            LLOGE("RTMP: Failed to send publish command");
        }
        
    } else if (found_publish_start) {
        /* 收到 NetStream.Publish.Start 响应
         * 表示推流已成功开始，发送元数据后即可发送视频数据 */
        LLOGI("RTMP: Publish started successfully, sending metadata");
        
        /* 发送 @setDataFrame 元数据 */
        if (rtmp_send_metadata(ctx) == RTMP_OK) {
            LLOGI("RTMP: Metadata sent, ready to send video data");
            rtmp_set_state(ctx, RTMP_STATE_PUBLISHING, 0);
        } else {
            LLOGE("RTMP: Failed to send metadata");
            rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_FAILED);
        }
        
    } else if (found_failed) {
        /* 连接失败 */
        rtmp_set_state(ctx, RTMP_STATE_ERROR, RTMP_ERR_CONNECT_FAILED);
        LLOGE("RTMP: Connection failed");
        
    } else if (ctx->state == RTMP_STATE_CONNECTED && found_on_status) {
        /* 收到onStatus,继续等待 */
        LLOGD("RTMP: Received onStatus response");
    }
    
    /* 清空接收缓冲区 */
    ctx->recv_pos = 0;
    
    return RTMP_OK;
}

/**
 * 获取NALU类型
 */
static nalu_type_t rtmp_get_nalu_type(const uint8_t *nalu_data, 
                                     uint32_t nalu_len) {
    if (nalu_len < 4) {
        return NALU_TYPE_NON_IDR;
    }
    
    /* 检查起始码 */
    uint32_t start_code = read_be32(nalu_data);
    if (start_code == 0x00000001) {
        if (nalu_len < 5) {
            return NALU_TYPE_NON_IDR;
        }
        uint8_t nalu_header = nalu_data[4];
        return (nalu_type_t)(nalu_header & 0x1F);
    }
    
    return NALU_TYPE_NON_IDR;
}

/**
 * 检查是否为关键帧
 */
static bool rtmp_is_key_frame(const uint8_t *nalu_data, uint32_t nalu_len) {
    nalu_type_t type = rtmp_get_nalu_type(nalu_data, nalu_len);
    return (type == NALU_TYPE_IDR);
}

/**
 * 打包FLV视频标签
 */
static int rtmp_pack_video_tag(uint8_t *buffer, uint32_t buffer_len,
                              const uint8_t *video_data, uint32_t video_len,
                              bool is_key_frame) {
    if (!buffer || buffer_len < 5 || !video_data || video_len == 0) {
        return RTMP_ERR_INVALID_PARAM;
    }
    
    /* 视频标签格式:
     * byte 0: 帧类型(4bit) + 编码ID(4bit)
     * byte 1-3: 包类型和时间戳偏移
     * byte 4+: NAL单元数据
     */
    
    uint32_t offset = 0;
    
    /* 帧类型和编码ID */
    uint8_t tag = 0;
    tag |= (is_key_frame ? 1 : 2) << 4;
    tag |= 7;  /* H.264 */
    
    buffer[offset++] = tag;
    
    if (offset + video_len > buffer_len) {
        return RTMP_ERR_BUFFER_OVERFLOW;
    }
    
    memcpy(&buffer[offset], video_data, video_len);
    offset += video_len;
    
    return (int)offset;
}

/**
 * 发送缓冲的数据
 */
static int rtmp_flush_send_buffer(rtmp_ctx_t *ctx) {
    if (!ctx || ctx->send_pos == 0) {
        return RTMP_OK;
    }
    
    if (!ctx->pcb) {
        return RTMP_ERR_FAILED;
    }
    
    //LLOGI("RTMP: Flushing %u bytes from send buffer", ctx->send_pos);
    
    uint32_t bytes_sent = 0;
    uint32_t total_bytes = ctx->send_pos;
    
    /* 分批发送数据，避免lwip缓冲区溢出 */
    while (bytes_sent < total_bytes) {
        /* 检查TCP发送缓冲区可用空间 */
        u16_t available = tcp_sndbuf(ctx->pcb);
        if (available == 0) {
            /* 缓冲区已满，先输出已有数据，等待sent回调继续 */
            tcp_output(ctx->pcb);
            return RTMP_ERR_NETWORK;
        }
        
        /* 计算本次可以发送的字节数 */
        uint32_t remaining = total_bytes - bytes_sent;
        uint32_t to_send = (remaining < available) ? remaining : available;
        
        /* 限制单次发送大小，避免过大 */
        if (to_send > 4096) {
            to_send = 4096;
        }
        
        /* 发送数据 */
        err_t err = tcp_write(ctx->pcb, &ctx->send_buf[bytes_sent], to_send, TCP_WRITE_FLAG_COPY);
        if (err != ERR_OK) {
            LLOGE("RTMP: tcp_write failed: %d, sent %u/%u bytes", err, bytes_sent, total_bytes);
            return RTMP_ERR_NETWORK;
        }
        
        bytes_sent += to_send;
        
        /* 每发送一批数据后触发输出 */
        if (bytes_sent % 8192 == 0 || bytes_sent >= total_bytes) {
            tcp_output(ctx->pcb);
        }
    }
    
    //LLOGI("RTMP: Successfully sent %u bytes", bytes_sent);
    ctx->send_pos = 0;
    
    return RTMP_OK;
}

/**
 * 更新状态
 */
static void rtmp_set_state(rtmp_ctx_t *ctx, rtmp_state_t new_state, int error_code) {
    rtmp_state_t old_state = ctx->state;
    
    if (old_state == new_state) {
        return;
    }
    
    ctx->state = new_state;
    
    // 在连接成功时初始化 base_timestamp
    if (new_state == RTMP_STATE_CONNECTED && old_state != RTMP_STATE_CONNECTED) {
        if (ctx->base_timestamp == 0) {
            ctx->base_timestamp = (uint32_t)(luat_mcu_tick64_ms());
        }
    }
    
    // 在断开连接时重置 base_timestamp
    if (new_state == RTMP_STATE_IDLE) {
        ctx->base_timestamp = 0;
    }
    
    LLOGD("RTMP: State changed from %d to %d", old_state, new_state);
    
    if (g_state_callback) {
        g_state_callback(ctx, old_state, new_state, error_code);
    }
}

/**
 * 生成随机时间戳
 */
static uint32_t rtmp_gen_timestamp(void) {
    static uint32_t start_time = 0;
    
    if (start_time == 0) {
        /* 首次调用,初始化基准时间 */
        start_time = (uint32_t)(uint32_t)(luat_mcu_tick64_ms());
    }
    
    return (uint32_t)(uint32_t)(luat_mcu_tick64_ms()) - start_time;
}
