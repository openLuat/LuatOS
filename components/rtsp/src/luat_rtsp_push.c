/**
 * @file luat_rtsp_push.c
 * @brief RTSP推流组件实现 - 基于lwip raw API
 * @author LuatOS Team
 * 
 * 实现了RTSP协议的核心功能,包括:
 * - TCP连接管理(RTSP控制通道)
 * - UDP连接管理(RTP媒体通道)
 * - RTSP握手流程(OPTIONS, DESCRIBE, SETUP, PLAY)
 * - RTP打包和发送
 * - H.264视频数据处理
 * - 网络数据收发
 */

#include "luat_rtsp_push.h"
#include "luat_debug.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_sntp.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/tcpip.h"
#include "lwip/timeouts.h"
#include "lwip/ip_addr.h"
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <stdio.h>

/* 外部函数声明 */
extern uint64_t luat_sntp_time64_ms();

#define LUAT_LOG_TAG "rtsp_push"
#include "luat_log.h"

/* ======================== 调试开关 ======================== */

/** 启用详细调试日志 (0=关闭, 1=开启) */
#define RTSP_DEBUG_VERBOSE 0

#if RTSP_DEBUG_VERBOSE
    #define RTSP_LOGV(...) LLOGD(__VA_ARGS__)
#else
    #define RTSP_LOGV(...)
#endif

/* ======================== 内部常量定义 ======================== */

/** 内部帧队列节点结构体 */
struct rtsp_frame_node {
    uint8_t *data;
    uint32_t len;
    uint32_t timestamp;
    struct rtsp_frame_node *next;
};

/** RTP固定头大小 */
#define RTP_HEADER_SIZE 12

/** RTP H.264 Payload Type */
#define RTP_PAYLOAD_TYPE_H264 96

/** RTP时间戳基数(90000 Hz for video) */
#define RTP_TIMESTAMP_BASE 90000

/** H.264 NALU类型定义 */
#define NALU_TYPE_SLICE    1
#define NALU_TYPE_DPA      2
#define NALU_TYPE_DPB      3
#define NALU_TYPE_DPC      4
#define NALU_TYPE_IDR      5
#define NALU_TYPE_SEI      6
#define NALU_TYPE_SPS      7
#define NALU_TYPE_PPS      8
#define NALU_TYPE_AUD      9

/** FU-A分片标识 */
#define FU_A_TYPE          28

rtsp_ctx_t *g_rtsp_ctx;

/* ======================== 内部函数声明 ======================== */

/**
 * 解析URL并提取主机名、端口、流名
 */
static int rtsp_parse_url(rtsp_ctx_t *ctx, const char *url);

/**
 * 详细解析SPS数据
 */
static void rtsp_parse_sps_detail(const uint8_t *sps_data, uint32_t sps_len);

/**
 * 详细解析PPS数据
 */
static void rtsp_parse_pps_detail(const uint8_t *pps_data, uint32_t pps_len);

/**
 * 详细解析SPS数据
 */
static void rtsp_parse_sps_detail(const uint8_t *sps_data, uint32_t sps_len);

/**
 * 详细解析PPS数据
 */
static void rtsp_parse_pps_detail(const uint8_t *pps_data, uint32_t pps_len);

/**
 * TCP连接回调函数
 */
static err_t rtsp_tcp_connect_callback(void *arg, struct tcp_pcb *pcb, err_t err);

/**
 * TCP接收回调函数
 */
static err_t rtsp_tcp_recv_callback(void *arg, struct tcp_pcb *pcb, 
                                   struct pbuf *p, err_t err);

/**
 * TCP错误回调函数
 */
static void rtsp_tcp_error_callback(void *arg, err_t err);

/**
 * 状态转移函数
 */
static void rtsp_set_state(rtsp_ctx_t *ctx, rtsp_state_t new_state, int error_code);

/**
 * 发送RTSP命令
 */
static int rtsp_send_command(rtsp_ctx_t *ctx, const char *method, 
                             const char *resource, const char *extra_headers,
                             const char *data, uint32_t data_len);

/**
 * 处理RTSP响应
 */
static int rtsp_handle_response(rtsp_ctx_t *ctx);

/**
 * 发送RTP包
 */
static int rtsp_send_rtp_packet(rtsp_ctx_t *ctx, const uint8_t *data, 
                                uint32_t len, uint32_t timestamp, uint8_t marker);

/**
 * 解析H.264帧并构建RTP包
 */
static int rtsp_build_rtp_payload(rtsp_ctx_t *ctx, const uint8_t *frame_data, 
                                  uint32_t frame_len, uint32_t timestamp);

/**
 * 从队列中提取并发送帧
 */
static int rtsp_send_queued_frames(rtsp_ctx_t *ctx);

/**
 * 清空帧队列
 */
static void rtsp_clear_frame_queue(rtsp_ctx_t *ctx);

/** 简单的大小写不敏感比较 */
static int rtsp_strncasecmp(const char *a, const char *b, size_t n);

/**
 * Base64编码函数
 */
static int rtsp_base64_encode(const uint8_t *src, uint32_t src_len, char *dst, uint32_t dst_len);

/**
 * 查找下一个NALU起始码位置
 */
static const uint8_t* rtsp_find_next_nalu(const uint8_t *data, uint32_t len, uint32_t *start_code_len);

/**
 * 发送单个NALU(支持FU-A分片)
 */
static int rtsp_send_nalu(rtsp_ctx_t *ctx, const uint8_t *nalu_data, 
                          uint32_t nalu_len, uint32_t timestamp, uint8_t is_last_nalu);

/**
 * 转换系统时间到NTP时间戳
 */
static void rtsp_get_ntp_timestamp(uint32_t *ntp_sec, uint32_t *ntp_frac);

/**
 * 发送RTCP Sender Report
 */
static int rtsp_send_rtcp_sr(rtsp_ctx_t *ctx);

/* ======================== 传输层实现 ======================== */

/**
 * UDP传输层私有数据
 */
typedef struct {
    struct udp_pcb *rtp_pcb;        /**< RTP UDP控制块 */
    struct udp_pcb *rtcp_pcb;       /**< RTCP UDP控制块 */
    ip_addr_t remote_ip;            /**< 远端IP地址 */
    uint16_t remote_rtp_port;       /**< 远端RTP端口 */
    uint16_t remote_rtcp_port;      /**< 远端RTCP端口 */
} rtsp_udp_transport_t;

/**
 * TCP发送队列节点
 */
typedef struct tcp_send_queue_node {
    uint8_t *data;                  /**< 待发送数据指针 */
    uint32_t len;                   /**< 数据长度 */
    struct tcp_send_queue_node *next; /**< 下一个节点 */
} tcp_send_queue_node_t;

/**
 * TCP传输层私有数据
 */
typedef struct {
    struct tcp_pcb *rtp_pcb;        /**< RTP TCP控制块 */
    ip_addr_t remote_ip;            /**< 远端IP地址 */
    uint16_t remote_rtp_port;       /**< 远端RTP端口 */
    uint8_t *send_buf;              /**< 发送缓冲区 */
    uint32_t send_buf_size;         /**< 发送缓冲区大小 */
    uint32_t send_pos;              /**< 发送缓冲区写位置 */

    /* 发送队列 */
    tcp_send_queue_node_t *send_queue_head; /**< 发送队列头 */
    tcp_send_queue_node_t *send_queue_tail; /**< 发送队列尾 */
    uint32_t send_queue_bytes;      /**< 队列总字节数 */
    uint32_t send_queue_count;      /**< 队列包数 */

    /* 发送队列定时器 */
    luat_rtos_timer_t send_timer;   /**< 发送队列定时器 */
} rtsp_tcp_transport_t;

/**
 * UDP传输层发送函数
 */
static int rtsp_udp_transport_send(rtsp_transport_t *transport, const uint8_t *data, uint32_t len);

/**
 * UDP传输层初始化函数
 */
static int rtsp_udp_transport_init(rtsp_transport_t *transport, rtsp_ctx_t *ctx);

/**
 * UDP传输层清理函数
 */
static void rtsp_udp_transport_cleanup(rtsp_transport_t *transport);

/**
 * UDP传输层发送RTCP函数
 */
static int rtsp_udp_transport_send_rtcp(rtsp_transport_t *transport, const uint8_t *data, uint32_t len);

/**
 * TCP传输层发送函数
 */
static int rtsp_tcp_transport_send(rtsp_transport_t *transport, const uint8_t *data, uint32_t len);

/**
 * TCP传输层初始化函数
 */
static int rtsp_tcp_transport_init(rtsp_transport_t *transport, rtsp_ctx_t *ctx);

/**
 * TCP传输层清理函数
 */
static void rtsp_tcp_transport_cleanup(rtsp_transport_t *transport);

/**
 * TCP传输层发送RTCP函数（TCP模式不支持RTCP）
 */
static int rtsp_tcp_transport_send_rtcp(rtsp_transport_t *transport, const uint8_t *data, uint32_t len);

/* ======================== TCP发送队列管理 ======================== */

/**
 * 清空TCP发送队列
 */
static void rtsp_tcp_send_queue_clear(rtsp_tcp_transport_t *tcp_transport);

/**
 * 数据入队到TCP发送队列
 */
static int rtsp_tcp_send_queue_enqueue(rtsp_tcp_transport_t *tcp_transport, const uint8_t *data, uint32_t len);

/**
 * 尝试发送队列中的数据
 */
static int rtsp_tcp_send_queue_flush(rtsp_tcp_transport_t *tcp_transport);

/**
 * TCP发送队列tcpip线程回调函数
 */
static void rtsp_tcp_send_tcpip_callback(void *arg);

/**
 * TCP发送队列定时器回调函数
 */
static LUAT_RT_RET_TYPE rtsp_tcp_send_timer_callback(LUAT_RT_CB_PARAM);

/* ======================== RTCP处理 ======================== */

/**
 * RTCP UDP接收回调函数
 */
static void rtcp_udp_recv_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                                   const ip_addr_t *addr, uint16_t port);

/**
 * 处理RTCP包
 */
static int rtsp_handle_rtcp_packet(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len);

/**
 * 处理RTCP NACK消息
 */
static int rtsp_handle_rtcp_nack(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len);

/**
 * 处理RTCP RR消息
 */
static int rtsp_handle_rtcp_rr(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len);

/* ======================== 核心实现 ======================== */

/**
 * 创建RTSP推流上下文
 */
rtsp_ctx_t* rtsp_create(void) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)luat_heap_malloc(sizeof(rtsp_ctx_t));
    if (!ctx) {
        LLOGE("内存分配失败");
        return NULL;
    }
    
    memset(ctx, 0, sizeof(rtsp_ctx_t));
    
    // 初始化缓冲区
    ctx->recv_buf = (uint8_t *)luat_heap_malloc(RTSP_BUFFER_SIZE);
    if (!ctx->recv_buf) {
        LLOGE("接收缓冲区分配失败");
        luat_heap_free(ctx);
        return NULL;
    }
    ctx->recv_buf_size = RTSP_BUFFER_SIZE;
    ctx->recv_pos = 0;
    
    ctx->send_buf = (uint8_t *)luat_heap_malloc(RTSP_BUFFER_SIZE);
    if (!ctx->send_buf) {
        LLOGE("发送缓冲区分配失败");
        luat_heap_free(ctx->recv_buf);
        luat_heap_free(ctx);
        return NULL;
    }
    ctx->send_buf_size = RTSP_BUFFER_SIZE;
    
    ctx->rtp_buf = (uint8_t *)luat_heap_malloc(RTP_BUFFER_SIZE);
    if (!ctx->rtp_buf) {
        LLOGE("RTP缓冲区分配失败");
        luat_heap_free(ctx->send_buf);
        luat_heap_free(ctx->recv_buf);
        luat_heap_free(ctx);
        return NULL;
    }
    ctx->rtp_buf_size = RTP_BUFFER_SIZE;
    
    // 初始化RTSP状态
    ctx->state = RTSP_STATE_IDLE;
    ctx->cseq = 1;
    ctx->rtp_sequence = (uint32_t)luat_mcu_ticks();
    ctx->rtp_ssrc = (uint32_t)luat_mcu_ticks();
    ctx->start_tick = luat_mcu_ticks();
    ctx->last_rtcp_time = luat_mcu_ticks();

    // 初始化传输模式（默认UDP）
    ctx->transport_mode = RTSP_TRANSPORT_TCP;
    ctx->transport = NULL;

    // 初始化网络统计
    memset(&ctx->network_stats, 0, sizeof(rtsp_network_stats_t));
    ctx->network_stats_callback = NULL;
    ctx->last_stats_time = luat_mcu_ticks();

    // 初始化帧队列
    ctx->frame_head = NULL;
    ctx->frame_tail = NULL;
    ctx->frame_queue_bytes = 0;
    
    g_rtsp_ctx = ctx;
    LLOGD("RTSP上下文创建成功");
    return ctx;
}

/**
 * 销毁RTSP推流上下文
 */
int rtsp_destroy(rtsp_ctx_t *ctx) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // 断开连接
    if (ctx->state != RTSP_STATE_IDLE) {
        rtsp_disconnect(ctx);
    }

    // 清空队列
    rtsp_clear_frame_queue(ctx);

    // 释放TCP连接
    if (ctx->control_pcb) {
        tcp_abort(ctx->control_pcb);
        ctx->control_pcb = NULL;
    }

    // 释放传输层接口（传输层负责释放其管理的UDP/TCP连接）
    if (ctx->transport) {
        if (ctx->transport->cleanup) {
            ctx->transport->cleanup(ctx->transport);
        }
        luat_heap_free(ctx->transport);
        ctx->transport = NULL;
    }

    // 释放缓冲区
    if (ctx->recv_buf) {
        luat_heap_free(ctx->recv_buf);
        ctx->recv_buf = NULL;
    }
    if (ctx->send_buf) {
        luat_heap_free(ctx->send_buf);
        ctx->send_buf = NULL;
    }
    if (ctx->rtp_buf) {
        luat_heap_free(ctx->rtp_buf);
        ctx->rtp_buf = NULL;
    }
    
    // 释放字符串
    if (ctx->url) {
        luat_heap_free(ctx->url);
        ctx->url = NULL;
    }
    if (ctx->host) {
        luat_heap_free(ctx->host);
        ctx->host = NULL;
    }
    if (ctx->stream) {
        luat_heap_free(ctx->stream);
        ctx->stream = NULL;
    }
    if (ctx->session_id) {
        luat_heap_free(ctx->session_id);
        ctx->session_id = NULL;
    }
    if (ctx->sps_data) {
        luat_heap_free(ctx->sps_data);
        ctx->sps_data = NULL;
    }
    if (ctx->pps_data) {
        luat_heap_free(ctx->pps_data);
        ctx->pps_data = NULL;
    }
    if (ctx->sprop_parameter_sets) {
        luat_heap_free(ctx->sprop_parameter_sets);
        ctx->sprop_parameter_sets = NULL;
    }
    
    luat_heap_free(ctx);
    LLOGD("RTSP上下文已销毁");
    return RTSP_OK;
}

/**
 * 设置RTSP服务器URL
 */
int rtsp_set_url(rtsp_ctx_t *ctx, const char *url) {
    if (!ctx || !url) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    if (ctx->url) {
        luat_heap_free(ctx->url);
    }
    
    ctx->url = (char *)luat_heap_malloc(strlen(url) + 1);
    if (!ctx->url) {
        LLOGE("URL内存分配失败");
        return RTSP_ERR_NO_MEMORY;
    }
    
    strcpy(ctx->url, url);
    
    if (rtsp_parse_url(ctx, url) != RTSP_OK) {
        LLOGE("URL解析失败: %s", url);
        return RTSP_ERR_INVALID_PARAM;
    }
    
    LLOGD("RTSP URL设置: %s", url);
    return RTSP_OK;
}

/**
 * 设置状态变化回调函数
 */
int rtsp_set_state_callback(rtsp_ctx_t *ctx, rtsp_state_callback_t callback) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    ctx->user_data = (void *)callback;
    return RTSP_OK;
}

/**
 * 设置H.264 SPS数据
 */
int rtsp_set_sps(rtsp_ctx_t *ctx, const uint8_t *sps_data, uint32_t sps_len) {
    if (!ctx || !sps_data || sps_len == 0 || sps_len > 1024) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    if (ctx->sps_data) {
        luat_heap_free(ctx->sps_data);
    }
    
    ctx->sps_data = (uint8_t *)luat_heap_malloc(sps_len);
    if (!ctx->sps_data) {
        LLOGE("SPS数据内存分配失败");
        return RTSP_ERR_NO_MEMORY;
    }
    
    memcpy(ctx->sps_data, sps_data, sps_len);
    ctx->sps_len = sps_len;
    
    LLOGD("SPS设置完毕: %u字节", sps_len);
    return RTSP_OK;
}

/**
 * 设置H.264 PPS数据
 */
int rtsp_set_pps(rtsp_ctx_t *ctx, const uint8_t *pps_data, uint32_t pps_len) {
    if (!ctx || !pps_data || pps_len == 0 || pps_len > 1024) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    if (ctx->pps_data) {
        luat_heap_free(ctx->pps_data);
    }
    
    ctx->pps_data = (uint8_t *)luat_heap_malloc(pps_len);
    if (!ctx->pps_data) {
        LLOGE("PPS数据内存分配失败");
        return RTSP_ERR_NO_MEMORY;
    }
    
    memcpy(ctx->pps_data, pps_data, pps_len);
    ctx->pps_len = pps_len;
    
    LLOGD("PPS设置完毕: %u字节", pps_len);
    return RTSP_OK;
}

/**
 * 推送H.264视频帧
 */
int rtsp_push_h264_frame(rtsp_ctx_t *ctx, const uint8_t *frame_data, 
                         uint32_t frame_len, uint32_t timestamp) {
    if (!ctx || !frame_data || frame_len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    // 如果在PLAYING状态,直接处理；否则进入队列
    if (ctx->state == RTSP_STATE_PLAYING) {
        // 直接构建RTP包并发送
        return rtsp_build_rtp_payload(ctx, frame_data, frame_len, timestamp);
    } else if (1) {
        return 0; // 丢弃非PLAYING状态下的帧
    } else {
        LLOGI("当前状态非PLAYING,帧加入发送队列 %d %d", frame_len, ctx->state);
        // 加入队列
        struct rtsp_frame_node *node = (struct rtsp_frame_node *)
            luat_heap_malloc(sizeof(struct rtsp_frame_node));
        if (!node) {
            LLOGE("帧队列节点内存分配失败");
            return RTSP_ERR_NO_MEMORY;
        }
        
        node->data = (uint8_t *)luat_heap_malloc(frame_len);
        if (!node->data) {
            LLOGE("帧数据内存分配失败");
            luat_heap_free(node);
            return RTSP_ERR_NO_MEMORY;
        }
        
        memcpy(node->data, frame_data, frame_len);
        node->len = frame_len;
        node->timestamp = timestamp;
        node->next = NULL;

        // 检查队列大小
        if (ctx->frame_queue_bytes + frame_len > RTSP_MAX_QUEUE_BYTES) {
            // 丢弃最早的非关键帧
            if (ctx->frame_head && ctx->frame_head != ctx->frame_tail) {
                struct rtsp_frame_node *temp = ctx->frame_head;
                ctx->frame_head = ctx->frame_head->next;
                ctx->frame_queue_bytes -= temp->len;

                luat_heap_free(temp->data);
                luat_heap_free(temp);
                LLOGD("队列溢出,丢弃一帧");
            }
        }

        if (!ctx->frame_head) {
            ctx->frame_head = node;
        } else {
            ctx->frame_tail->next = node;
        }
        ctx->frame_tail = node;
        ctx->frame_queue_bytes += frame_len;
        
        //RTSP_LOGV("帧已加入队列: %u字节, 队列总大小: %u字节", frame_len, ctx->frame_queue_bytes);
        return (int)frame_len;
    }
}

/**
 * 获取当前连接状态
 */
rtsp_state_t rtsp_get_state(rtsp_ctx_t *ctx) {
    if (!ctx) {
        return RTSP_STATE_IDLE;
    }
    return ctx->state;
}

/**
 * 处理RTSP事件轮询
 */
int rtsp_poll(rtsp_ctx_t *ctx) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    uint32_t now = luat_mcu_ticks();
    
    // 检查连接超时
    if (ctx->state != RTSP_STATE_IDLE && ctx->state != RTSP_STATE_ERROR && ctx->state != RTSP_STATE_PLAYING) {
        if (now - ctx->last_activity_time > RTSP_CMD_TIMEOUT) {
            LLOGE("RTSP连接超时");
            rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_TIMEOUT);
            return RTSP_ERR_TIMEOUT;
        }
    }
    
    // 发送队列中的帧
    if (ctx->state == RTSP_STATE_PLAYING) {
        rtsp_send_queued_frames(ctx);

        // 定期发送RTCP Sender Report (每5秒一次)
        if (now - ctx->last_rtcp_time >= 5000) {
            LLOGD("触发RTCP SR发送: 距上次%u毫秒", now - ctx->last_rtcp_time);
            int ret = rtsp_send_rtcp_sr(ctx);
            if (ret == RTSP_OK) {
                ctx->last_rtcp_time = now;
            } else {
                LLOGE("RTCP SR发送失败: %d", ret);
            }
        }
    }
    
    return RTSP_OK;
}

/**
 * 获取推流统计信息
 */
int rtsp_get_stats(rtsp_ctx_t *ctx, rtsp_stats_t *stats) {
    if (!ctx || !stats) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    stats->bytes_sent = ctx->bytes_sent;
    stats->video_frames_sent = ctx->video_frames_sent;
    stats->rtp_packets_sent = ctx->rtp_packets_sent;
    stats->connection_time = luat_mcu_ticks() - ctx->start_tick;
    stats->last_video_timestamp = ctx->video_timestamp;
    
    return RTSP_OK;
}

/* ======================== 内部函数实现 ======================== */

/**
 * 解析RTSP URL
 */
static int rtsp_parse_url(rtsp_ctx_t *ctx, const char *url) {
    if (strncmp(url, "rtsp://", 7) != 0) {
        LLOGE("非法的RTSP URL格式");
        return RTSP_ERR_INVALID_PARAM;
    }
    
    const char *ptr = url + 7;
    const char *host_end = strchr(ptr, ':');
    const char *stream_start;
    
    // 解析主机名
    if (!host_end) {
        host_end = strchr(ptr, '/');
        if (!host_end) {
            host_end = ptr + strlen(ptr);
        }
    }
    
    int host_len = host_end - ptr;
    ctx->host = (char *)luat_heap_malloc(host_len + 1);
    if (!ctx->host) {
        return RTSP_ERR_NO_MEMORY;
    }
    strncpy(ctx->host, ptr, host_len);
    ctx->host[host_len] = '\0';
    
    // 解析端口
    if (*host_end == ':') {
        ctx->port = (uint16_t)atoi(host_end + 1);
        stream_start = strchr(host_end + 1, '/');
    } else {
        ctx->port = RTSP_DEFAULT_PORT;
        stream_start = host_end;
    }
    
    // 解析流名
    if (stream_start && *stream_start == '/') {
        stream_start++;
        int stream_len = strlen(stream_start);
        ctx->stream = (char *)luat_heap_malloc(stream_len + 1);
        if (!ctx->stream) {
            return RTSP_ERR_NO_MEMORY;
        }
        strcpy(ctx->stream, stream_start);
    } else {
        ctx->stream = (char *)luat_heap_malloc(1);
        if (!ctx->stream) {
            return RTSP_ERR_NO_MEMORY;
        }
        ctx->stream[0] = '\0';
    }
    
    LLOGD("RTSP URL解析: host=%s, port=%u, stream=%s", 
          ctx->host, ctx->port, ctx->stream);
    
    return RTSP_OK;
}

/**
 * 状态转移
 */
static void rtsp_set_state(rtsp_ctx_t *ctx, rtsp_state_t new_state, int error_code) {
    if (ctx->state == new_state) {
        return;
    }
    
    rtsp_state_t old_state = ctx->state;
    ctx->state = new_state;
    ctx->last_activity_time = luat_mcu_ticks();
    
    LLOGD("RTSP状态转移: %d -> %d", (int)old_state, (int)new_state);
    
    // 调用回调函数
    rtsp_state_callback_t callback = (rtsp_state_callback_t)ctx->user_data;
    if (callback) {
        callback(ctx, old_state, new_state, error_code);
    }
}

/**
 * 发送RTSP命令
 */
static int rtsp_send_command(rtsp_ctx_t *ctx, const char *method, 
                             const char *resource, const char *extra_headers,
                             const char *data, uint32_t data_len) {
    if (!ctx->control_pcb) {
        LLOGE("RTSP TCP连接未建立");
        return RTSP_ERR_CONNECT_FAILED;
    }
    
    // 构建RTSP请求行
    int len = snprintf((char *)ctx->send_buf, ctx->send_buf_size,
        "%s %s RTSP/1.0\r\n"
        "CSeq: %u\r\n"
        "User-Agent: LuatOS-RTSP/1.0\r\n",
        method, resource, ctx->cseq++);
    
    if (len < 0 || len >= (int)ctx->send_buf_size) {
        LLOGE("发送缓冲区溢出");
        return RTSP_ERR_BUFFER_OVERFLOW;
    }
    
    // 添加Session头(如果已建立会话)
    if (ctx->session_id) {
        int n = snprintf((char *)ctx->send_buf + len, ctx->send_buf_size - len,
            "Session: %s\r\n", ctx->session_id);
        if (n < 0 || len + n >= (int)ctx->send_buf_size) {
            LLOGE("发送缓冲区溢出");
            return RTSP_ERR_BUFFER_OVERFLOW;
        }
        len += n;
    }
    
    // 添加额外头部
    if (extra_headers) {
        int n = strlen(extra_headers);
        if (len + n >= (int)ctx->send_buf_size) {
            LLOGE("发送缓冲区溢出");
            return RTSP_ERR_BUFFER_OVERFLOW;
        }
        memcpy(ctx->send_buf + len, extra_headers, n);
        len += n;
    }
    
    // 添加空行分隔头部和body(仅当没有data时自动添加)
    if (data_len == 0) {
        if (len + 2 >= (int)ctx->send_buf_size) {
            LLOGE("发送缓冲区溢出");
            return RTSP_ERR_BUFFER_OVERFLOW;
        }
        memcpy(ctx->send_buf + len, "\r\n", 2);
        len += 2;
    }
    
    RTSP_LOGV("RTSP命令:\n%.*s", len, (char *)ctx->send_buf);
    
    // 发送TCP头部数据
    err_t err = tcp_write(ctx->control_pcb, ctx->send_buf, len, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK) {
        LLOGE("TCP头部发送失败: %d", err);
        return RTSP_ERR_NETWORK;
    }
    
    // 发送body数据(如果有)
    if (data && data_len > 0) {
        // 需要发送空行 + body
        err = tcp_write(ctx->control_pcb, (const void *)"\r\n", 2, TCP_WRITE_FLAG_COPY);
        if (err != ERR_OK) {
            LLOGE("TCP空行发送失败: %d", err);
            return RTSP_ERR_NETWORK;
        }
        
        err = tcp_write(ctx->control_pcb, (const void *)data, data_len, TCP_WRITE_FLAG_COPY);
        if (err != ERR_OK) {
            LLOGE("TCP数据体发送失败: %d", err);
            return RTSP_ERR_NETWORK;
        }
    }
    
    tcp_output(ctx->control_pcb);
    return RTSP_OK;
}

/**
 * TCP连接回调
 */
static err_t rtsp_tcp_connect_callback(void *arg, struct tcp_pcb *pcb, err_t err) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)arg;
    
    if (err != ERR_OK) {
        LLOGE("TCP连接失败: %d", err);
        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_CONNECT_FAILED);
        return ERR_ABRT;
    }
    
    LLOGD("TCP连接成功");
    rtsp_set_state(ctx, RTSP_STATE_OPTIONS, 0);
    
    // 设置TCP回调函数
    tcp_recv(pcb, rtsp_tcp_recv_callback);
    tcp_err(pcb, rtsp_tcp_error_callback);
    tcp_arg(pcb, ctx);
    
    // 发送OPTIONS请求(使用具体的stream URI)
    if (rtsp_send_command(ctx, "OPTIONS", ctx->url, NULL, NULL, 0) == RTSP_OK) {
        rtsp_set_state(ctx, RTSP_STATE_OPTIONS, 0);
    }
    
    return ERR_OK;
}

/**
 * TCP接收回调
 */
static err_t rtsp_tcp_recv_callback(void *arg, struct tcp_pcb *pcb, 
                                   struct pbuf *p, err_t err) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)arg;
    
    if (err != ERR_OK) {
        LLOGE("TCP接收错误: %d", err);
        if (p) pbuf_free(p);
        return ERR_ABRT;
    }
    
    if (!p) {
        LLOGD("TCP连接已关闭");
        rtsp_set_state(ctx, RTSP_STATE_IDLE, 0);
        return ERR_OK;
    }
    
    // 复制数据到接收缓冲区
    if (ctx->recv_pos + p->tot_len > ctx->recv_buf_size) {
        LLOGE("接收缓冲区溢出");
        pbuf_free(p);
        return ERR_ABRT;
    }
    
    pbuf_copy_partial(p, ctx->recv_buf + ctx->recv_pos, p->tot_len, 0);
    ctx->recv_pos += p->tot_len;
    
    // 更新活动时间
    ctx->last_activity_time = luat_mcu_ticks();
    
    RTSP_LOGV("接收RTSP数据: %u字节", p->tot_len);
    pbuf_free(p);
    
    // 处理RTSP响应
    rtsp_handle_response(ctx);
    tcp_recved(pcb, p->tot_len);
    
    return ERR_OK;
}

/**
 * TCP错误回调
 */
static void rtsp_tcp_error_callback(void *arg, err_t err) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)arg;
    LLOGE("TCP错误: %d", err);
    rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_NETWORK);
}

/**
 * 处理RTSP响应
 */
static int rtsp_handle_response(rtsp_ctx_t *ctx) {
    // 检查是否已收到完整的响应
    char *resp_end = strstr((char *)ctx->recv_buf, "\r\n\r\n");
    if (!resp_end) {
        // 尚未接收完整响应
        return RTSP_OK;
    }
    
    // 打印完整的RTSP响应以便调试
    int resp_len = (resp_end - (char *)ctx->recv_buf) + 4;
    LLOGD("RTSP响应内容:\n%.*s", resp_len, (char *)ctx->recv_buf);
    
    // 解析响应行: RTSP/1.0 <status> <reason>
    char *line_start = (char *)ctx->recv_buf;
    char *line_end = strstr(line_start, "\r\n");
    if (!line_end) {
        LLOGE("无效的RTSP响应");
        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_HANDSHAKE_FAILED);
        return RTSP_ERR_HANDSHAKE_FAILED;
    }
    
    *line_end = '\0';
    int status_code = 0;
    if (sscanf(line_start, "RTSP/1.0 %d", &status_code) != 1) {
        LLOGE("RTSP响应行解析失败");
        *line_end = '\r';
        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_HANDSHAKE_FAILED);
        return RTSP_ERR_HANDSHAKE_FAILED;
    }
    *line_end = '\r';
    
    LLOGD("RTSP响应: 状态码=%d", status_code);
    
    if (status_code != 200) {
        LLOGE("RTSP服务器错误: %d", status_code);
        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_HANDSHAKE_FAILED);
        return RTSP_ERR_HANDSHAKE_FAILED;
    }
    
    // 解析响应头
    char *header_start = line_end + 2;
    char *session_id = NULL;
    
    while (header_start < resp_end) {
        line_end = strstr(header_start, "\r\n");
        if (!line_end) break;
        
        *line_end = '\0';
        
        // 提取Session头
        if (rtsp_strncasecmp(header_start, "Session:", 8) == 0) {
            char *value = header_start + 8;
            while (*value == ' ' || *value == '\t') value++;
            
            // Session ID可能包含超时参数 (e.g. "12345678;timeout=60")
            char *semicolon = strchr(value, ';');
            int len = semicolon ? (semicolon - value) : strlen(value);
            
            if (len > 0) {
                session_id = (char *)luat_heap_malloc(len + 1);
                if (session_id) {
                    strncpy(session_id, value, len);
                    session_id[len] = '\0';
                    LLOGD("提取Session ID: %s", session_id);
                }
            }
        }
        
        // 提取Transport头
        if (rtsp_strncasecmp(header_start, "Transport:", 10) == 0) {
            char *value = header_start + 10;
            while (*value == ' ' || *value == '\t') value++;
            
            // 解析server_port参数
            char *server_port = strstr(value, "server_port=");
            if (server_port) {
                server_port += 12;  // strlen("server_port=")
                int rtp_port = 0, rtcp_port = 0;
                if (sscanf(server_port, "%d-%d", &rtp_port, &rtcp_port) == 2) {
                    ctx->remote_rtp_port = (uint16_t)rtp_port;
                    ctx->remote_rtcp_port = (uint16_t)rtcp_port;
                    LLOGD("服务器端口: RTP=%u, RTCP=%u", 
                          ctx->remote_rtp_port, ctx->remote_rtcp_port);
                }
            }
            
            // 解析client_port参数(如果服务器返回)
            char *client_port = strstr(value, "client_port=");
            if (client_port) {
                client_port += 12;  // strlen("client_port=")
                int rtp_port = 0, rtcp_port = 0;
                if (sscanf(client_port, "%d-%d", &rtp_port, &rtcp_port) == 2) {
                    ctx->local_rtp_port = (uint16_t)rtp_port;
                    ctx->local_rtcp_port = (uint16_t)rtcp_port;
                    LLOGD("本地端口: RTP=%u, RTCP=%u", 
                          ctx->local_rtp_port, ctx->local_rtcp_port);
                }
            }
        }
        
        *line_end = '\r';
        header_start = line_end + 2;
    }
    
    // 保存Session ID
    if (session_id && !ctx->session_id) {
        ctx->session_id = session_id;
    } else if (session_id) {
        luat_heap_free(session_id);
    }
    
    // 根据当前状态处理下一步
    switch (ctx->state) {
        case RTSP_STATE_OPTIONS:
            // OPTIONS成功,发送ANNOUNCE
            {
                char sdp[2048];
                int sdp_len = 0;
                
                // 如果有SPS/PPS，构建完整的SDP；否则使用基础SDP
                if (ctx->sps_data && ctx->sps_len > 0 && ctx->pps_data && ctx->pps_len > 0) {
                    // 计算profile-level-id (从SPS中提取)
                    char profile_level_id[16] = {0};
                    if (ctx->sps_len >= 4) {
                        snprintf(profile_level_id, sizeof(profile_level_id), "%02X%02X%02X",
                                ctx->sps_data[1], ctx->sps_data[2], ctx->sps_data[3]);
                    } else {
                        strcpy(profile_level_id, "42C01E");  // 默认Baseline Profile Level 3.0
                    }
                    
                    // Base64编码SPS
                    char sps_b64[512] = {0};
                    int sps_b64_len = rtsp_base64_encode(ctx->sps_data, ctx->sps_len, 
                                                         sps_b64, sizeof(sps_b64));
                    
                    // Base64编码PPS
                    char pps_b64[512] = {0};
                    int pps_b64_len = rtsp_base64_encode(ctx->pps_data, ctx->pps_len,
                                                         pps_b64, sizeof(pps_b64));
                    
                    if (sps_b64_len > 0 && pps_b64_len > 0) {
                        // 构建完整的SDP
                        sdp_len = snprintf(sdp, sizeof(sdp),
                            "v=0\r\n"
                            "o=- 0 0 IN IP4 127.0.0.1\r\n"
                            "s=LuatOS RTSP Stream\r\n"
                            "c=IN IP4 0.0.0.0\r\n"
                            "t=0 0\r\n"
                            "m=video 0 RTP/AVP 96\r\n"
                            "a=rtpmap:96 H264/90000\r\n"
                            "a=fmtp:96 packetization-mode=1;profile-level-id=%s;sprop-parameter-sets=%s\r\n"
                            "a=control:streamid=0\r\n",
                            profile_level_id, (ctx->sprop_parameter_sets ? ctx->sprop_parameter_sets : "") );
                        
                        LLOGD("完整SDP生成: profile-level-id=%s", profile_level_id);
                    }
                }
                
                // 如果没有生成完整SDP，使用基础SDP
                if (sdp_len <= 0) {
                    sdp_len = snprintf(sdp, sizeof(sdp),
                        "v=0\r\n"
                        "o=- 0 0 IN IP4 127.0.0.1\r\n"
                        "s=LuatOS RTSP Stream\r\n"
                        "c=IN IP4 %s\r\n"
                        "t=0 0\r\n"
                        "m=video 0 RTP/AVP 96\r\n"
                        "a=rtpmap:96 H264/90000\r\n"
                        "a=fmtp:96 profile-level-id=1; sprop-parameter-sets=Z0IAKeNQCgC2QgAAB9AAAOpg0YAAmJgAL/L3gAE=,aM48gA==\r\n"
                        "a=control:streamid=0\r\n", ctx->host);
                    
                    LLOGD("使用基础SDP(无SPS/PPS)");
                }
                
                if (sdp_len > 0 && sdp_len < (int)sizeof(sdp)) {
                    char headers[512] = {0};
                    snprintf(headers, sizeof(headers),
                        "Content-Type: application/sdp\r\n"
                        "Content-Length: %d\r\n", sdp_len);
                    
                    if (rtsp_send_command(ctx, "ANNOUNCE", ctx->url, headers, sdp, sdp_len) == RTSP_OK) {
                        rtsp_set_state(ctx, RTSP_STATE_DESCRIBE, 0);
                    }
                }
            }
            break;
            
        case RTSP_STATE_DESCRIBE:
            // ANNOUNCE/DESCRIBE成功,发送SETUP
            {
                char setup_headers[512] = {0};

                // 根据传输模式设置不同的 Transport 头
                if (ctx->transport_mode == RTSP_TRANSPORT_TCP) {
                    // TCP传输模式
                    snprintf(setup_headers, sizeof(setup_headers),
                        "Transport: RTP/AVP/TCP;unicast;interleaved=0-1;mode=record\r\n");
                } else {
                    // UDP 或 UDP+FEC 传输模式
                    snprintf(setup_headers, sizeof(setup_headers),
                        "Transport: RTP/AVP/UDP;unicast;client_port=%u-%u;mode=record\r\n",
                        ctx->local_rtp_port ? ctx->local_rtp_port : 19030,
                        ctx->local_rtcp_port ? ctx->local_rtcp_port : 19031);
                }

                char resource[512] = {0};
                snprintf(resource, sizeof(resource), "%s/streamid=0", ctx->url);

                if (rtsp_send_command(ctx, "SETUP", resource, setup_headers, NULL, 0) == RTSP_OK) {
                    rtsp_set_state(ctx, RTSP_STATE_SETUP, 0);
                }
            }
            break;
            
        case RTSP_STATE_SETUP:
            // SETUP成功,初始化传输层并发送PLAY
            {
                // 分配传输层接口
                ctx->transport = (rtsp_transport_t *)luat_heap_malloc(sizeof(rtsp_transport_t));
                if (!ctx->transport) {
                    LLOGE("传输层内存分配失败");
                    rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_NO_MEMORY);
                    break;
                }
                memset(ctx->transport, 0, sizeof(rtsp_transport_t));

                // 根据传输模式初始化传输层
                if (ctx->transport_mode == RTSP_TRANSPORT_TCP) {
                    // TCP传输模式
                    LLOGD("初始化TCP传输层");
                    if (rtsp_tcp_transport_init(ctx->transport, ctx) != RTSP_OK) {
                        LLOGE("TCP传输层初始化失败");
                        luat_heap_free(ctx->transport);
                        ctx->transport = NULL;
                        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_CONNECT_FAILED);
                        break;
                    }
                } else {
                    // UDP 或 UDP+FEC 传输模式
                    LLOGD("初始化UDP传输层");
                    if (rtsp_udp_transport_init(ctx->transport, ctx) != RTSP_OK) {
                        LLOGE("UDP传输层初始化失败");
                        luat_heap_free(ctx->transport);
                        ctx->transport = NULL;
                        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_CONNECT_FAILED);
                        break;
                    }
                }

                LLOGD("传输层初始化成功: mode=%d", ctx->transport_mode);

                // 发送PLAY请求
                if (rtsp_send_command(ctx, "RECORD", ctx->url, NULL, NULL, 0) == RTSP_OK) {
                    rtsp_set_state(ctx, RTSP_STATE_PLAY, 0);
                }
            }
            break;
            
        case RTSP_STATE_PLAY:
            // RECORD/PLAY成功,进入推流状态
            rtsp_set_state(ctx, RTSP_STATE_PLAYING, 0);
            LLOGD("RTSP握手完成,开始推流");
            
            // 立即发送一次RTCP Sender Report
            LLOGD("RTSP就绪,发送初始RTCP SR");
            rtsp_send_rtcp_sr(ctx);
            ctx->last_rtcp_time = luat_mcu_ticks();
            
            // 通知摄像头开始采集
            extern int luat_camera_capture(int id, uint8_t quality, const char *path);
            luat_camera_capture(0, 80, "rtsp");
            break;
            
        default:
            break;
    }
    
    // 清空接收缓冲区
    resp_len = (resp_end - (char *)ctx->recv_buf) + 4;
    if (ctx->recv_pos > (uint32_t)resp_len) {
        memmove(ctx->recv_buf, ctx->recv_buf + resp_len, ctx->recv_pos - resp_len);
        ctx->recv_pos -= resp_len;
    } else {
        ctx->recv_pos = 0;
    }
    
    return RTSP_OK;
}

/**
 * 发送RTP包
 */
static int rtsp_send_rtp_packet(rtsp_ctx_t *ctx, const uint8_t *data,
                                uint32_t len, uint32_t timestamp, uint8_t marker) {
    // 构建RTP头
    uint8_t rtp_header[RTP_HEADER_SIZE];
    uint32_t rtp_ts = (timestamp * RTP_TIMESTAMP_BASE) / 1000;

    // V=2, P=0, X=0, CC=0
    rtp_header[0] = (2 << 6) | 0;
    // M=marker, PT=96(H.264)
    rtp_header[1] = (marker << 7) | RTP_PAYLOAD_TYPE_H264;
    // Sequence number (big-endian)
    rtp_header[2] = (ctx->rtp_sequence >> 8) & 0xFF;
    rtp_header[3] = ctx->rtp_sequence & 0xFF;
    // Timestamp (big-endian)
    rtp_header[4] = (rtp_ts >> 24) & 0xFF;
    rtp_header[5] = (rtp_ts >> 16) & 0xFF;
    rtp_header[6] = (rtp_ts >> 8) & 0xFF;
    rtp_header[7] = rtp_ts & 0xFF;
    // SSRC (big-endian)
    rtp_header[8] = (ctx->rtp_ssrc >> 24) & 0xFF;
    rtp_header[9] = (ctx->rtp_ssrc >> 16) & 0xFF;
    rtp_header[10] = (ctx->rtp_ssrc >> 8) & 0xFF;
    rtp_header[11] = ctx->rtp_ssrc & 0xFF;

    ctx->rtp_sequence++;

    // 构建完整RTP包
    if (RTP_HEADER_SIZE + len > ctx->rtp_buf_size) {
        LLOGE("RTP缓冲区溢出");
        return RTSP_ERR_BUFFER_OVERFLOW;
    }

    memcpy(ctx->rtp_buf, rtp_header, RTP_HEADER_SIZE);
    memcpy(ctx->rtp_buf + RTP_HEADER_SIZE, data, len);

    // 使用传输层接口发送
    if (ctx->transport && ctx->transport->send) {
        int ret = ctx->transport->send(ctx->transport, ctx->rtp_buf, RTP_HEADER_SIZE + len);
        if (ret == RTSP_OK) {
            ctx->bytes_sent += RTP_HEADER_SIZE + len;
            ctx->rtp_packets_sent++;
        }
        return ret;
    }

    // 传输层未初始化
    LLOGE("传输层未初始化");
    return RTSP_ERR_CONNECT_FAILED;
}

/**
 * 构建RTP载荷 - 支持多NALU解析和FU-A分片
 */
static int rtsp_build_rtp_payload(rtsp_ctx_t *ctx, const uint8_t *frame_data, 
                                  uint32_t frame_len, uint32_t timestamp) {
    if (!frame_data || frame_len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    // 如果传入的 timestamp 为 0，使用上下文中的时间戳
    if (timestamp == 0) {
        timestamp = ctx->video_timestamp;
    }
    
    const uint8_t *ptr = frame_data;
    uint32_t remaining = frame_len;
    int nalu_count = 0;
    int total_sent = 0;
    
    RTSP_LOGV("处理帧数据: %u字节", frame_len);
    
    // 解析并发送所有NALU
    while (remaining > 0) {
        // 查找当前NALU的起始码
        uint32_t start_code_len = 0;
        const uint8_t *nalu_start = rtsp_find_next_nalu(ptr, remaining, &start_code_len);
        
        if (!nalu_start) {
            // 没有找到起始码，可能整个数据就是一个NALU
            if (nalu_count == 0 && remaining > 0) {
                nalu_start = ptr;
                start_code_len = 0;
            } else {
                break;
            }
        }
        
        // 跳过起始码
        const uint8_t *nalu_data = nalu_start + start_code_len;
        uint32_t nalu_available = remaining - (nalu_start - ptr) - start_code_len;
        
        if (nalu_available == 0) {
            break;
        }
        
        // 查找下一个NALU起始码，确定当前NALU长度
        uint32_t next_start_code_len = 0;
        const uint8_t *next_nalu = rtsp_find_next_nalu(nalu_data + 1, nalu_available - 1, &next_start_code_len);
        
        uint32_t nalu_len;
        if (next_nalu) {
            nalu_len = next_nalu - nalu_data;
        } else {
            nalu_len = nalu_available;
        }
        
        if (nalu_len > 0) {
            uint8_t nalu_type = nalu_data[0] & 0x1F;
            RTSP_LOGV("发现NALU: 类型=%u, 长度=%u", nalu_type, nalu_len);
            
            // 自动保存SPS/PPS
            if (nalu_type == NALU_TYPE_SPS && (!ctx->sps_data || ctx->sps_len != nalu_len)) {
                if (ctx->sps_data) {
                    luat_heap_free(ctx->sps_data);
                }
                ctx->sps_data = (uint8_t *)luat_heap_malloc(nalu_len);
                if (ctx->sps_data) {
                    memcpy(ctx->sps_data, nalu_data, nalu_len);
                    ctx->sps_len = nalu_len;
                    LLOGD("自动提取SPS: %u字节", nalu_len);
                    // 详细解析SPS
                    rtsp_parse_sps_detail(nalu_data, nalu_len);
                    // 打印sprop-sps(Base64)
                    char b64_sps[256];
                    if (rtsp_base64_encode(nalu_data, nalu_len, b64_sps, sizeof(b64_sps)) >= 0) {
                        LLOGD("sprop-sps=%s", b64_sps);
                        // 如果已有PPS，合成sprop-parameter-sets
                        if (ctx->pps_data && ctx->pps_len > 0) {
                            char b64_pps[256];
                            if (rtsp_base64_encode(ctx->pps_data, ctx->pps_len, b64_pps, sizeof(b64_pps)) >= 0) {
                                size_t total_len = strlen(b64_sps) + 1 + strlen(b64_pps) + 1;
                                if (ctx->sprop_parameter_sets) {
                                    luat_heap_free(ctx->sprop_parameter_sets);
                                    ctx->sprop_parameter_sets = NULL;
                                }
                                ctx->sprop_parameter_sets = (char*)luat_heap_malloc(total_len);
                                if (ctx->sprop_parameter_sets) {
                                    snprintf(ctx->sprop_parameter_sets, total_len, "%s,%s", b64_sps, b64_pps);
                                    LLOGD("sprop-parameter-sets=%s", ctx->sprop_parameter_sets);
                                } else {
                                    LLOGW("分配sprop-parameter-sets失败");
                                }
                            }
                        }
                    } else {
                        LLOGW("sprop-sps Base64编码失败");
                    }
                }
            } else if (nalu_type == NALU_TYPE_PPS && (!ctx->pps_data || ctx->pps_len != nalu_len)) {
                if (ctx->pps_data) {
                    luat_heap_free(ctx->pps_data);
                }
                ctx->pps_data = (uint8_t *)luat_heap_malloc(nalu_len);
                if (ctx->pps_data) {
                    memcpy(ctx->pps_data, nalu_data, nalu_len);
                    ctx->pps_len = nalu_len;
                    LLOGD("自动提取PPS: %u字节", nalu_len);
                    // 详细解析PPS
                    rtsp_parse_pps_detail(nalu_data, nalu_len);
                    // 打印sprop-pps(Base64)
                    char b64_pps[256];
                    if (rtsp_base64_encode(nalu_data, nalu_len, b64_pps, sizeof(b64_pps)) >= 0) {
                        LLOGD("sprop-pps=%s", b64_pps);
                        // 如果已有SPS，合成sprop-parameter-sets
                        if (ctx->sps_data && ctx->sps_len > 0) {
                            char b64_sps[256];
                            if (rtsp_base64_encode(ctx->sps_data, ctx->sps_len, b64_sps, sizeof(b64_sps)) >= 0) {
                                size_t total_len = strlen(b64_sps) + 1 + strlen(b64_pps) + 1;
                                if (ctx->sprop_parameter_sets) {
                                    luat_heap_free(ctx->sprop_parameter_sets);
                                    ctx->sprop_parameter_sets = NULL;
                                }
                                ctx->sprop_parameter_sets = (char*)luat_heap_malloc(total_len);
                                if (ctx->sprop_parameter_sets) {
                                    snprintf(ctx->sprop_parameter_sets, total_len, "%s,%s", b64_sps, b64_pps);
                                    LLOGD("sprop-parameter-sets=%s", ctx->sprop_parameter_sets);
                                } else {
                                    LLOGW("分配sprop-parameter-sets失败");
                                }
                            }
                        }
                    } else {
                        LLOGW("sprop-pps Base64编码失败");
                    }
                }
            }
            
            // 发送NALU（非SPS/PPS或在推流状态下也发送SPS/PPS）
            if (nalu_type != NALU_TYPE_AUD) {  // 跳过AUD
                // 判断是否为最后一个NALU
                uint8_t is_last = (next_nalu == NULL) ? 1 : 0;
                
                int ret = rtsp_send_nalu(ctx, nalu_data, nalu_len, timestamp, is_last);
                if (ret >= 0) {
                    total_sent += ret;
                    nalu_count++;
                } else {
                    LLOGE("NALU发送失败: %d", ret);
                    return ret;
                }
            }
        }
        
        // 移动到下一个NALU
        if (next_nalu) {
            uint32_t consumed = next_nalu - ptr;
            ptr = next_nalu;
            remaining -= consumed;
        } else {
            break;
        }
    }
    
    if (nalu_count > 0) {
        ctx->video_frames_sent++;
        ctx->video_timestamp = timestamp;
        RTSP_LOGV("帧发送完成: %d个NALU, 总计%d字节", nalu_count, total_sent);
    }
    
    return total_sent > 0 ? total_sent : RTSP_ERR_FAILED;
}

/**
 * 发送队列中的帧
 */
static int rtsp_send_queued_frames(rtsp_ctx_t *ctx) {
    int sent_count = 0;

    while (ctx->frame_head && sent_count < 5) {  // 每次轮询最多发送5帧
        struct rtsp_frame_node *node = ctx->frame_head;

        if (rtsp_build_rtp_payload(ctx, node->data, node->len, node->timestamp) == RTSP_OK) {
            ctx->frame_head = node->next;
            ctx->frame_queue_bytes -= node->len;

            luat_heap_free(node->data);
            luat_heap_free(node);

            sent_count++;
        } else {
            break;  // 发送失败,暂停发送
        }
    }

    if (!ctx->frame_head) {
        ctx->frame_tail = NULL;
    }

    //RTSP_LOGV("队列帧发送: %d帧, 剩余队列: %u字节", sent_count, ctx->frame_queue_bytes);

    return RTSP_OK;
    }

/**
 * 清空帧队列
 */
static void rtsp_clear_frame_queue(rtsp_ctx_t *ctx) {
    struct rtsp_frame_node *node = ctx->frame_head;

    while (node) {
        struct rtsp_frame_node *next = node->next;
        if (node->data) {
            luat_heap_free(node->data);
        }
        luat_heap_free(node);
        node = next;
    }

    ctx->frame_head = NULL;
    ctx->frame_tail = NULL;
    ctx->frame_queue_bytes = 0;
}

/**
 * 大小写不敏感字符串比较(用于HTTP头解析)
 */
static int rtsp_strncasecmp(const char *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        int ca = tolower((unsigned char)a[i]);
        int cb = tolower((unsigned char)b[i]);
        if (ca != cb || ca == 0) {
            return ca - cb;
        }
    }
    return 0;
}

/**
 * Base64编码函数
 */
static int rtsp_base64_encode(const uint8_t *src, uint32_t src_len, char *dst, uint32_t dst_len) {
    static const char base64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    uint32_t i = 0, j = 0;
    
    // 计算所需的输出长度
    uint32_t required_len = ((src_len + 2) / 3) * 4;
    if (required_len >= dst_len) {
        return -1;  // 缓冲区不足
    }
    
    while (i < src_len) {
        uint32_t octet_a = i < src_len ? src[i++] : 0;
        uint32_t octet_b = i < src_len ? src[i++] : 0;
        uint32_t octet_c = i < src_len ? src[i++] : 0;
        
        uint32_t triple = (octet_a << 16) + (octet_b << 8) + octet_c;
        
        dst[j++] = base64_table[(triple >> 18) & 0x3F];
        dst[j++] = base64_table[(triple >> 12) & 0x3F];
        dst[j++] = base64_table[(triple >> 6) & 0x3F];
        dst[j++] = base64_table[triple & 0x3F];
    }
    
    // 添加填充
    uint32_t mod = src_len % 3;
    if (mod == 1) {
        dst[j - 1] = '=';
        dst[j - 2] = '=';
    } else if (mod == 2) {
        dst[j - 1] = '=';
    }
    
    dst[j] = '\0';
    return j;
}

/**
 * 查找下一个NALU起始码
 * @return 起始码的位置，如果未找到返回NULL
 */
static const uint8_t* rtsp_find_next_nalu(const uint8_t *data, uint32_t len, uint32_t *start_code_len) {
    if (len < 3) {
        return NULL;
    }
    
    for (uint32_t i = 0; i < len - 2; i++) {
        // 查找0x000001或0x00000001
        if (data[i] == 0 && data[i+1] == 0) {
            if (data[i+2] == 1) {
                *start_code_len = 3;
                return &data[i];
            } else if (i < len - 3 && data[i+2] == 0 && data[i+3] == 1) {
                *start_code_len = 4;
                return &data[i];
            }
        }
    }
    
    return NULL;
}

/**
 * 发送单个NALU(支持FU-A分片)
 */
static int rtsp_send_nalu(rtsp_ctx_t *ctx, const uint8_t *nalu_data, 
                          uint32_t nalu_len, uint32_t timestamp, uint8_t is_last_nalu) {
    if (!nalu_data || nalu_len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }
    
    uint8_t nalu_header = nalu_data[0];
    uint8_t nalu_type = nalu_header & 0x1F;
    uint8_t nri = nalu_header & 0x60;
    
    // 如果NALU小于最大载荷，直接发送
    if (nalu_len <= RTP_MAX_PACKET_SIZE) {
        int ret = rtsp_send_rtp_packet(ctx, nalu_data, nalu_len, timestamp, is_last_nalu);
        return (ret == RTSP_OK) ? (int)nalu_len : ret;
    }
    
    // 需要FU-A分片
    RTSP_LOGV("NALU过大(%u字节)，使用FU-A分片", nalu_len);
    
    uint32_t nalu_payload_len = nalu_len - 1;  // 去掉NALU头
    const uint8_t *nalu_payload = nalu_data + 1;
    uint32_t fragment_size = RTP_MAX_PACKET_SIZE - 2;  // FU indicator + FU header
    uint32_t offset = 0;
    uint32_t fragment_count = 0;
    int total_sent = 0;
    
    while (offset < nalu_payload_len) {
        uint32_t this_fragment_size = (nalu_payload_len - offset > fragment_size) ? 
                                      fragment_size : (nalu_payload_len - offset);
        
        uint8_t fu_packet[RTP_MAX_PACKET_SIZE];
        
        // FU indicator: F(1bit) + NRI(2bits) + Type(5bits=28)
        fu_packet[0] = nri | FU_A_TYPE;
        
        // FU header: S(1bit) + E(1bit) + R(1bit) + Type(5bits)
        uint8_t fu_header = nalu_type;
        if (offset == 0) {
            fu_header |= 0x80;  // S bit (start)
        }
        if (offset + this_fragment_size >= nalu_payload_len) {
            fu_header |= 0x40;  // E bit (end)
        }
        fu_packet[1] = fu_header;
        
        // 复制分片数据
        memcpy(fu_packet + 2, nalu_payload + offset, this_fragment_size);
        
        // 发送分片，只有最后一个分片且是最后一个NALU时才设置marker
        uint8_t marker = ((fu_header & 0x40) && is_last_nalu) ? 1 : 0;
        
        int ret = rtsp_send_rtp_packet(ctx, fu_packet, 2 + this_fragment_size, timestamp, marker);
        if (ret != RTSP_OK) {
            LLOGE("FU-A分片发送失败: %d", ret);
            return ret;
        }
        
        offset += this_fragment_size;
        fragment_count++;
        total_sent += (2 + this_fragment_size);
    }
    
    RTSP_LOGV("FU-A分片完成: %u个分片", fragment_count);
    return total_sent;
}

/**
 * 转换系统时间到NTP时间戳
 * NTP时间戳: 64位, 高32位是秒数(从1900年1月1日开始), 低32位是小数秒
 */
static void rtsp_get_ntp_timestamp(uint32_t *ntp_sec, uint32_t *ntp_frac) {
    // 使用 SNTP 获取准确的 NTP 时间戳(毫秒单位，从1970年开始)
    uint64_t unix_ms = luat_sntp_time64_ms();

    // NTP时间戳从1900年开始，1970年1月1日对应的秒数为2208988800秒
    const uint64_t NTP_OFFSET_SEC = 2208988800UL;

    // 将UNIX时间(毫秒)转换为NTP时间
    // 1. UNIX秒数 = unix_ms / 1000
    // 2. NTP秒数 = UNIX秒数 + NTP_OFFSET
    uint64_t unix_sec = unix_ms / 1000;
    uint32_t unix_ms_frac = (uint32_t)(unix_ms % 1000);

    // NTP秒数
    *ntp_sec = (uint32_t)(unix_sec + NTP_OFFSET_SEC);

    // NTP小数部分: 将毫秒转换为 NTP 小数格式 (2^32 * ms / 1000)
    *ntp_frac = (unix_ms_frac * 4294967296ULL) / 1000;

    RTSP_LOGV("NTP时间戳: unix_ms=%llu, unix_sec=%llu, ntp_sec=%u, ntp_frac=%u",
              unix_ms, unix_sec, *ntp_sec, *ntp_frac);
}

/**
 * 发送RTCP Sender Report
 * RTCP SR格式 (RFC 3550):
 * 0                   1                   2                   3
 * 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |V=2|P|    RC   |   PT=SR=200   |             length            |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         SSRC of sender                        |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |              NTP timestamp, most significant word             |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |             NTP timestamp, least significant word             |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                         RTP timestamp                         |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                     sender's packet count                     |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 * |                      sender's octet count                     |
 * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 */
static int rtsp_send_rtcp_sr(rtsp_ctx_t *ctx) {
    if (!ctx->transport || !ctx->transport->send_rtcp) {
        LLOGD("传输层不支持RTCP发送,跳过SR发送");
        return RTSP_OK;
    }

    if (ctx->remote_rtcp_port == 0) {
        LLOGD("RTCP端口未配置,跳过SR发送: remote_rtcp_port=%u",
              ctx->remote_rtcp_port);
        return RTSP_OK;
    }

    LLOGD("准备发送RTCP SR: packets=%u, bytes=%u, remote_ip=%s, remote_rtcp_port=%u",
          ctx->rtp_packets_sent, ctx->bytes_sent,
          ipaddr_ntoa(&ctx->remote_ip), ctx->remote_rtcp_port);
    
    uint8_t rtcp_packet[28];  // RTCP SR固定头部28字节(不含接收报告块)
    uint32_t ntp_sec, ntp_frac;
    
    // 获取NTP时间戳
    rtsp_get_ntp_timestamp(&ntp_sec, &ntp_frac);
    
    // 计算RTP时间戳
    uint32_t rtp_ts = (ctx->video_timestamp * RTP_TIMESTAMP_BASE) / 1000;
    
    // 构建RTCP SR包
    // V=2, P=0, RC=0 (无接收报告块)
    rtcp_packet[0] = (2 << 6) | 0;
    // PT=200 (SR)
    rtcp_packet[1] = 200;
    // Length = 6 (28字节 / 4 - 1)
    rtcp_packet[2] = 0;
    rtcp_packet[3] = 6;
    
    // SSRC (big-endian)
    rtcp_packet[4] = (ctx->rtp_ssrc >> 24) & 0xFF;
    rtcp_packet[5] = (ctx->rtp_ssrc >> 16) & 0xFF;
    rtcp_packet[6] = (ctx->rtp_ssrc >> 8) & 0xFF;
    rtcp_packet[7] = ctx->rtp_ssrc & 0xFF;
    
    // NTP timestamp - 高32位 (big-endian)
    rtcp_packet[8] = (ntp_sec >> 24) & 0xFF;
    rtcp_packet[9] = (ntp_sec >> 16) & 0xFF;
    rtcp_packet[10] = (ntp_sec >> 8) & 0xFF;
    rtcp_packet[11] = ntp_sec & 0xFF;
    
    // NTP timestamp - 低32位 (big-endian)
    rtcp_packet[12] = (ntp_frac >> 24) & 0xFF;
    rtcp_packet[13] = (ntp_frac >> 16) & 0xFF;
    rtcp_packet[14] = (ntp_frac >> 8) & 0xFF;
    rtcp_packet[15] = ntp_frac & 0xFF;
    
    // RTP timestamp (big-endian)
    rtcp_packet[16] = (rtp_ts >> 24) & 0xFF;
    rtcp_packet[17] = (rtp_ts >> 16) & 0xFF;
    rtcp_packet[18] = (rtp_ts >> 8) & 0xFF;
    rtcp_packet[19] = rtp_ts & 0xFF;
    
    // Sender's packet count (big-endian)
    rtcp_packet[20] = (ctx->rtp_packets_sent >> 24) & 0xFF;
    rtcp_packet[21] = (ctx->rtp_packets_sent >> 16) & 0xFF;
    rtcp_packet[22] = (ctx->rtp_packets_sent >> 8) & 0xFF;
    rtcp_packet[23] = ctx->rtp_packets_sent & 0xFF;
    
    // Sender's octet count (big-endian)
    rtcp_packet[24] = (ctx->bytes_sent >> 24) & 0xFF;
    rtcp_packet[25] = (ctx->bytes_sent >> 16) & 0xFF;
    rtcp_packet[26] = (ctx->bytes_sent >> 8) & 0xFF;
    rtcp_packet[27] = ctx->bytes_sent & 0xFF;
    
    // 发送RTCP SR包
    if (!ctx->transport || !ctx->transport->send_rtcp) {
        LLOGE("传输层不支持RTCP发送");
        return RTSP_ERR_CONNECT_FAILED;
    }

    int ret = ctx->transport->send_rtcp(ctx->transport, rtcp_packet, 28);
    if (ret != RTSP_OK) {
        LLOGE("RTCP SR发送失败: err=%d", ret);
        return ret;
    }

    LLOGD("RTCP SR已成功发送: SSRC=0x%08X, packets=%u, bytes=%u, NTP=%u.%u, RTP_TS=%u",
          ctx->rtp_ssrc, ctx->rtp_packets_sent, ctx->bytes_sent, ntp_sec, ntp_frac, rtp_ts);

    return RTSP_OK;
}

/**
 * 连接到RTSP服务器
 */
int rtsp_connect(rtsp_ctx_t *ctx) {
    if (!ctx || !ctx->host || ctx->port == 0) {
        LLOGE("RTSP上下文无效或URL未设置");
        return RTSP_ERR_INVALID_PARAM;
    }

    if (ctx->state != RTSP_STATE_IDLE) {
        LLOGE("RTSP已处于连接状态");
        return RTSP_ERR_FAILED;
    }

    // 创建TCP控制连接
    ctx->control_pcb = tcp_new();
    if (!ctx->control_pcb) {
        LLOGE("TCP控制块创建失败");
        return RTSP_ERR_NO_MEMORY;
    }

    rtsp_set_state(ctx, RTSP_STATE_CONNECTING, 0);

    // 发起TCP连接
    ip_addr_t remote_ip;
    if (ipaddr_aton(ctx->host, &remote_ip) == 0) {
        // TODO: DNS解析
        LLOGE("IP地址转换失败: %s", ctx->host);
        tcp_abort(ctx->control_pcb);
        ctx->control_pcb = NULL;
        rtsp_set_state(ctx, RTSP_STATE_ERROR, RTSP_ERR_CONNECT_FAILED);
        return RTSP_ERR_CONNECT_FAILED;
    }

    // 保存远端IP地址
    ip_addr_copy(ctx->remote_ip, remote_ip);
    LLOGD("解析服务器地址: %s -> %s", ctx->host, ipaddr_ntoa(&ctx->remote_ip));

    tcp_arg(ctx->control_pcb, (void *)ctx);
    tcp_connect(ctx->control_pcb, &remote_ip, ctx->port, rtsp_tcp_connect_callback);

    LLOGD("RTSP连接请求已发送: %s:%u", ctx->host, ctx->port);
    return RTSP_OK;
}

/**
 * 断开RTSP连接
 */
int rtsp_disconnect(rtsp_ctx_t *ctx) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    rtsp_set_state(ctx, RTSP_STATE_DISCONNECTING, 0);

    // 关闭TCP连接
    if (ctx->control_pcb) {
        tcp_close(ctx->control_pcb);
        ctx->control_pcb = NULL;
    }

    rtsp_clear_frame_queue(ctx);
    rtsp_set_state(ctx, RTSP_STATE_IDLE, 0);

    LLOGD("RTSP连接已断开");
    return RTSP_OK;
}

/**
 * 详细解析SPS数据
 */
static void rtsp_parse_sps_detail(const uint8_t *sps_data, uint32_t sps_len) {
    if (!sps_data || sps_len < 4) {
        LLOGE("SPS数据无效");
        return;
    }
    
    LLOGD("========== SPS详细信息 ==========");
    
    // NALU头 (1字节)
    uint8_t nalu_header = sps_data[0];
    uint8_t forbidden_zero = (nalu_header >> 7) & 0x01;
    uint8_t nal_ref_idc = (nalu_header >> 5) & 0x03;
    uint8_t nal_unit_type = nalu_header & 0x1F;
    
    LLOGD("NALU Header: 0x%02X", nalu_header);
    LLOGD("  forbidden_zero_bit: %u", forbidden_zero);
    LLOGD("  nal_ref_idc: %u", nal_ref_idc);
    LLOGD("  nal_unit_type: %u (SPS)", nal_unit_type);
    
    if (sps_len < 4) {
        LLOGD("SPS数据太短，无法解析详细参数");
        return;
    }
    
    // Profile & Level (3字节)
    uint8_t profile_idc = sps_data[1];
    uint8_t constraint_flags = sps_data[2];
    uint8_t level_idc = sps_data[3];
    
    LLOGD("Profile IDC: %u (0x%02X)", profile_idc, profile_idc);
    const char *profile_name = "Unknown";
    switch (profile_idc) {
        case 66: profile_name = "Baseline"; break;
        case 77: profile_name = "Main"; break;
        case 88: profile_name = "Extended"; break;
        case 100: profile_name = "High"; break;
        case 110: profile_name = "High 10"; break;
        case 122: profile_name = "High 4:2:2"; break;
        case 244: profile_name = "High 4:4:4"; break;
    }
    LLOGD("  Profile: %s", profile_name);
    
    LLOGD("Constraint Flags: 0x%02X", constraint_flags);
    LLOGD("  constraint_set0_flag: %u", (constraint_flags >> 7) & 0x01);
    LLOGD("  constraint_set1_flag: %u", (constraint_flags >> 6) & 0x01);
    LLOGD("  constraint_set2_flag: %u", (constraint_flags >> 5) & 0x01);
    LLOGD("  constraint_set3_flag: %u", (constraint_flags >> 4) & 0x01);
    LLOGD("  constraint_set4_flag: %u", (constraint_flags >> 3) & 0x01);
    LLOGD("  constraint_set5_flag: %u", (constraint_flags >> 2) & 0x01);
    
    LLOGD("Level IDC: %u (Level %.1f)", level_idc, level_idc / 10.0);
    
    // 打印原始数据 (前16字节或全部)
    uint32_t print_len = sps_len > 16 ? 16 : sps_len;
    char hex_str[128];
    int pos = 0;
    for (uint32_t i = 0; i < print_len && pos < 120; i++) {
        pos += snprintf(hex_str + pos, sizeof(hex_str) - pos, "%02X ", sps_data[i]);
    }
    if (sps_len > 16) {
        snprintf(hex_str + pos, sizeof(hex_str) - pos, "...");
    }
    LLOGD("SPS Raw Data (%u bytes): %s", sps_len, hex_str);
    LLOGD("==================================\n");
}

/**
 * 详细解析PPS数据
 */
static void rtsp_parse_pps_detail(const uint8_t *pps_data, uint32_t pps_len) {
    if (!pps_data || pps_len < 1) {
        LLOGE("PPS数据无效");
        return;
    }
    
    LLOGD("========== PPS详细信息 ==========");
    
    // NALU头 (1字节)
    uint8_t nalu_header = pps_data[0];
    uint8_t forbidden_zero = (nalu_header >> 7) & 0x01;
    uint8_t nal_ref_idc = (nalu_header >> 5) & 0x03;
    uint8_t nal_unit_type = nalu_header & 0x1F;
    
    LLOGD("NALU Header: 0x%02X", nalu_header);
    LLOGD("  forbidden_zero_bit: %u", forbidden_zero);
    LLOGD("  nal_ref_idc: %u", nal_ref_idc);
    LLOGD("  nal_unit_type: %u (PPS)", nal_unit_type);
    
    // 打印原始数据 (前16字节或全部)
    uint32_t print_len = pps_len > 16 ? 16 : pps_len;
    char hex_str[128];
    int pos = 0;
    for (uint32_t i = 0; i < print_len && pos < 120; i++) {
        pos += snprintf(hex_str + pos, sizeof(hex_str) - pos, "%02X ", pps_data[i]);
    }
    if (pps_len > 16) {
        snprintf(hex_str + pos, sizeof(hex_str) - pos, "...");
    }
    LLOGD("PPS Raw Data (%u bytes): %s", pps_len, hex_str);
    LLOGD("==================================\n");
}

/* ======================== 传输层实现 ======================== */

/**
 * UDP传输层发送函数
 */
static int rtsp_udp_transport_send(rtsp_transport_t *transport, const uint8_t *data, uint32_t len) {
    if (!transport || !transport->private_data || !data || len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }

    rtsp_udp_transport_t *udp_transport = (rtsp_udp_transport_t *)transport->private_data;

    if (!udp_transport->rtp_pcb) {
        LLOGE("UDP传输层未初始化");
        return RTSP_ERR_CONNECT_FAILED;
    }

    // 分配pbuf
    struct pbuf *pb = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (!pb) {
        LLOGE("UDP数据包分配失败");
        return RTSP_ERR_NO_MEMORY;
    }

    memcpy(pb->payload, data, len);

    // 发送UDP包
    err_t err = udp_sendto(udp_transport->rtp_pcb, pb, &udp_transport->remote_ip, udp_transport->remote_rtp_port);
    pbuf_free(pb);

    if (err != ERR_OK) {
        LLOGE("UDP发送失败: err=%d", err);
        return RTSP_ERR_NETWORK;
    }

    return RTSP_OK;
}

/**
 * UDP传输层初始化函数
 */
static int rtsp_udp_transport_init(rtsp_transport_t *transport, rtsp_ctx_t *ctx) {
    if (!transport || !ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // 分配私有数据
    rtsp_udp_transport_t *udp_transport = (rtsp_udp_transport_t *)luat_heap_malloc(sizeof(rtsp_udp_transport_t));
    if (!udp_transport) {
        LLOGE("UDP传输层内存分配失败");
        return RTSP_ERR_NO_MEMORY;
    }

    memset(udp_transport, 0, sizeof(rtsp_udp_transport_t));

    // 创建RTP UDP连接
    udp_transport->rtp_pcb = udp_new();
    if (!udp_transport->rtp_pcb) {
        LLOGE("RTP UDP块创建失败");
        luat_heap_free(udp_transport);
        return RTSP_ERR_NO_MEMORY;
    }

    // 创建RTCP UDP连接
    udp_transport->rtcp_pcb = udp_new();
    if (!udp_transport->rtcp_pcb) {
        LLOGE("RTCP UDP块创建失败");
        udp_remove(udp_transport->rtp_pcb);
        luat_heap_free(udp_transport);
        return RTSP_ERR_NO_MEMORY;
    }

    // 设置RTCP接收回调
    udp_recv(udp_transport->rtcp_pcb, rtcp_udp_recv_callback, ctx);

    // 从ctx复制UDP连接信息
    ip_addr_copy(udp_transport->remote_ip, ctx->remote_ip);
    udp_transport->remote_rtp_port = ctx->remote_rtp_port;
    udp_transport->remote_rtcp_port = ctx->remote_rtcp_port;

    // 设置传输层接口
    transport->send = rtsp_udp_transport_send;
    transport->send_rtcp = rtsp_udp_transport_send_rtcp;
    transport->init = rtsp_udp_transport_init;
    transport->cleanup = rtsp_udp_transport_cleanup;
    transport->ctx = ctx;
    transport->private_data = udp_transport;

    LLOGD("UDP传输层初始化成功");
    return RTSP_OK;
}

/**
 * UDP传输层清理函数
 */
static void rtsp_udp_transport_cleanup(rtsp_transport_t *transport) {
    if (!transport || !transport->private_data) {
        return;
    }

    rtsp_udp_transport_t *udp_transport = (rtsp_udp_transport_t *)transport->private_data;

    // 释放RTP UDP连接
    if (udp_transport->rtp_pcb) {
        udp_remove(udp_transport->rtp_pcb);
        udp_transport->rtp_pcb = NULL;
    }

    // 释放RTCP UDP连接
    if (udp_transport->rtcp_pcb) {
        udp_remove(udp_transport->rtcp_pcb);
        udp_transport->rtcp_pcb = NULL;
    }

    luat_heap_free(udp_transport);
    transport->private_data = NULL;

    LLOGD("UDP传输层已清理");
}

/**
 * UDP传输层发送RTCP函数
 */
static int rtsp_udp_transport_send_rtcp(rtsp_transport_t *transport, const uint8_t *data, uint32_t len) {
    if (!transport || !transport->private_data || !data || len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }

    rtsp_udp_transport_t *udp_transport = (rtsp_udp_transport_t *)transport->private_data;

    if (!udp_transport->rtcp_pcb) {
        LLOGE("RTCP UDP传输层未初始化");
        return RTSP_ERR_CONNECT_FAILED;
    }

    // 分配pbuf
    struct pbuf *pb = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (!pb) {
        LLOGE("RTCP UDP数据包分配失败");
        return RTSP_ERR_NO_MEMORY;
    }

    memcpy(pb->payload, data, len);

    // 发送UDP包
    err_t err = udp_sendto(udp_transport->rtcp_pcb, pb, &udp_transport->remote_ip, udp_transport->remote_rtcp_port);
    pbuf_free(pb);

    if (err != ERR_OK) {
        LLOGE("RTCP UDP发送失败: err=%d", err);
        return RTSP_ERR_NETWORK;
    }

    return RTSP_OK;
}

/* ======================== TCP发送队列管理 ======================== */

/**
 * 清空TCP发送队列
 */
static void rtsp_tcp_send_queue_clear(rtsp_tcp_transport_t *tcp_transport) {
    if (!tcp_transport) {
        return;
    }

    tcp_send_queue_node_t *node = tcp_transport->send_queue_head;
    while (node) {
        tcp_send_queue_node_t *next = node->next;
        if (node->data) {
            luat_heap_free(node->data);
        }
        luat_heap_free(node);
        node = next;
    }

    tcp_transport->send_queue_head = NULL;
    tcp_transport->send_queue_tail = NULL;
    tcp_transport->send_queue_bytes = 0;
    tcp_transport->send_queue_count = 0;
}

/**
 * 尝试发送队列中的数据
 */
static int rtsp_tcp_send_queue_flush(rtsp_tcp_transport_t *tcp_transport) {
    if (!tcp_transport || !tcp_transport->rtp_pcb) {
        return RTSP_ERR_INVALID_PARAM;
    }

    uint32_t sent_count = 0;
    uint32_t sent_bytes = 0;
    uint32_t reserved = TCP_WND / 5;  // 预留20%窗口给RTSP控制信令

    while (tcp_transport->send_queue_head) {
        tcp_send_queue_node_t *node = tcp_transport->send_queue_head;

        // 检查TCP发送窗口（考虑预留）
        uint32_t sndbuf = tcp_sndbuf(tcp_transport->rtp_pcb);
        if (sndbuf < (node->len + reserved)) {
            RTSP_LOGV("TCP窗口不足(预留%u字节)，停止发送队列: 需要%u字节, 可用%u字节", reserved, node->len, sndbuf);
            break;
        }

        // 发送数据
        err_t err = tcp_write(tcp_transport->rtp_pcb, node->data, node->len, TCP_WRITE_FLAG_COPY);
        if (err != ERR_OK) {
            LLOGE("TCP队列发送失败: err=%d", err);
            break;
        }

        // 出队
        tcp_transport->send_queue_head = node->next;
        if (!tcp_transport->send_queue_head) {
            tcp_transport->send_queue_tail = NULL;
        }

        tcp_transport->send_queue_bytes -= node->len;
        tcp_transport->send_queue_count--;
        sent_bytes += node->len;
        sent_count++;

        // 释放节点
        luat_heap_free(node->data);
        luat_heap_free(node);
    }

    if (sent_count > 0) {
        tcp_output(tcp_transport->rtp_pcb);
        RTSP_LOGV("队列发送完成: %u包, %u字节, 剩余%u包", sent_count, sent_bytes, tcp_transport->send_queue_count);
    }

    return sent_count > 0 ? RTSP_OK : RTSP_ERR_NETWORK;
}

/**
 * TCP发送队列tcpip线程回调函数
 * 在tcpip线程中执行，确保线程安全
 */
static void rtsp_tcp_send_tcpip_callback(void *arg) {
    rtsp_tcp_transport_t *tcp_transport = (rtsp_tcp_transport_t *)arg;

    if (tcp_transport && tcp_transport->send_queue_head) {
        rtsp_tcp_send_queue_flush(tcp_transport);
    }
}

/**
 * TCP发送队列定时器回调函数
 * 定期尝试发送队列中的数据
 */
static LUAT_RT_RET_TYPE rtsp_tcp_send_timer_callback(LUAT_RT_CB_PARAM) {
    // 使用全局变量获取tcp_transport指针
    extern rtsp_ctx_t *g_rtsp_ctx;
    if (g_rtsp_ctx && g_rtsp_ctx->transport && g_rtsp_ctx->transport->private_data) {
        rtsp_tcp_transport_t *tcp_transport = (rtsp_tcp_transport_t *)g_rtsp_ctx->transport->private_data;
        if (tcp_transport && tcp_transport->send_queue_head) {
            // 使用tcpip_callback确保在tcpip线程中执行TCP操作
            tcpip_callback_with_block(rtsp_tcp_send_tcpip_callback, tcp_transport, 0);
        }
    }
}

/**
 * 数据入队到TCP发送队列
 */
static int rtsp_tcp_send_queue_enqueue(rtsp_tcp_transport_t *tcp_transport, const uint8_t *data, uint32_t len) {
    if (!tcp_transport || !data || len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // 检查队列大小限制（最大2MB）
    if (tcp_transport->send_queue_bytes + len > 2 * 1024 * 1024) {
        LLOGW("TCP发送队列已满: 当前%u字节, 新增%u字节", tcp_transport->send_queue_bytes, len);
        return RTSP_ERR_BUFFER_OVERFLOW;
    }

    // 分配节点
    tcp_send_queue_node_t *node = (tcp_send_queue_node_t *)luat_heap_malloc(sizeof(tcp_send_queue_node_t));
    if (!node) {
        LLOGE("发送队列节点分配失败");
        return RTSP_ERR_NO_MEMORY;
    }

    // 分配数据缓冲区
    node->data = (uint8_t *)luat_heap_malloc(len);
    if (!node->data) {
        LLOGE("发送队列数据分配失败");
        luat_heap_free(node);
        return RTSP_ERR_NO_MEMORY;
    }

    // 复制数据
    memcpy(node->data, data, len);
    node->len = len;
    node->next = NULL;

    // 入队
    if (!tcp_transport->send_queue_tail) {
        tcp_transport->send_queue_head = node;
        tcp_transport->send_queue_tail = node;
    } else {
        tcp_transport->send_queue_tail->next = node;
        tcp_transport->send_queue_tail = node;
    }

    tcp_transport->send_queue_bytes += len;
    tcp_transport->send_queue_count++;

    RTSP_LOGV("数据入队: %u字节, 队列包数=%u, 总字节数=%u", len, tcp_transport->send_queue_count, tcp_transport->send_queue_bytes);

    return RTSP_OK;
}

/**
 * TCP传输层发送函数
 * 实现RTP over TCP (RFC 2326)
 */
static int rtsp_tcp_transport_send(rtsp_transport_t *transport, const uint8_t *data, uint32_t len) {
    if (!transport || !transport->private_data || !data || len == 0) {
        return RTSP_ERR_INVALID_PARAM;
    }

    rtsp_tcp_transport_t *tcp_transport = (rtsp_tcp_transport_t *)transport->private_data;

    if (!tcp_transport->rtp_pcb) {
        LLOGE("TCP传输层未初始化");
        return RTSP_ERR_CONNECT_FAILED;
    }

    // 优先发送队列中的数据
    if (tcp_transport->send_queue_head) {
        rtsp_tcp_send_queue_flush(tcp_transport);
    }

    // RFC 2326: RTP over TCP格式
    // 前缀: '$' (1字节) + 通道ID (1字节) + 数据长度 (2字节，大端)
    // 数据: RTP包

    uint16_t total_len = 4 + len;  // 前缀4字节 + RTP数据

    // 检查缓冲区大小
    if (total_len > tcp_transport->send_buf_size) {
        LLOGE("TCP发送缓冲区溢出");
        return RTSP_ERR_BUFFER_OVERFLOW;
    }

    // 构建RTP over TCP前缀
    tcp_transport->send_buf[0] = '$';  // 起始符
    tcp_transport->send_buf[1] = 0;    // 通道ID (RTP通道)
    tcp_transport->send_buf[2] = (len >> 8) & 0xFF;  // 长度高字节
    tcp_transport->send_buf[3] = len & 0xFF;         // 长度低字节

    // 复制RTP数据
    memcpy(tcp_transport->send_buf + 4, data, len);

    // 检查TCP发送窗口
    uint32_t sndbuf = tcp_sndbuf(tcp_transport->rtp_pcb);
    uint32_t reserved = TCP_WND / 5;  // 预留20%窗口给RTSP控制信令

    // 如果队列还有数据或窗口不足（考虑预留），则入队
    if (tcp_transport->send_queue_head || sndbuf < (total_len + reserved)) {
        if (tcp_transport->send_queue_head) {
            RTSP_LOGV("队列未清空，新数据入队: %u字节", total_len);
        } else {
            RTSP_LOGV("TCP窗口不足(预留%u字节): 需要%u字节, 可用%u字节, 数据入队", reserved, total_len, sndbuf);
        }
        return rtsp_tcp_send_queue_enqueue(tcp_transport, tcp_transport->send_buf, total_len);
    }

    // 发送TCP数据
    err_t err = tcp_write(tcp_transport->rtp_pcb, tcp_transport->send_buf, total_len, TCP_WRITE_FLAG_COPY);
    if (err != ERR_OK) {
        LLOGE("TCP发送失败: err=%d, 尝试入队", err);
        // 发送失败时也尝试入队
        return rtsp_tcp_send_queue_enqueue(tcp_transport, tcp_transport->send_buf, total_len);
    }

    tcp_output(tcp_transport->rtp_pcb);

    return RTSP_OK;
}

/**
 * TCP传输层初始化函数
 */
static int rtsp_tcp_transport_init(rtsp_transport_t *transport, rtsp_ctx_t *ctx) {
    if (!transport || !ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // 分配私有数据
    rtsp_tcp_transport_t *tcp_transport = (rtsp_tcp_transport_t *)luat_heap_malloc(sizeof(rtsp_tcp_transport_t));
    if (!tcp_transport) {
        LLOGE("TCP传输层内存分配失败");
        return RTSP_ERR_NO_MEMORY;
    }

    memset(tcp_transport, 0, sizeof(rtsp_tcp_transport_t));

    // 分配发送缓冲区
    tcp_transport->send_buf_size = RTP_BUFFER_SIZE + 4;  // RTP缓冲区 + 4字节前缀
    tcp_transport->send_buf = (uint8_t *)luat_heap_malloc(tcp_transport->send_buf_size);
    if (!tcp_transport->send_buf) {
        LLOGE("TCP发送缓冲区分配失败");
        luat_heap_free(tcp_transport);
        return RTSP_ERR_NO_MEMORY;
    }

    // 使用RTSP控制连接（TCP interleaved模式）
    tcp_transport->rtp_pcb = ctx->control_pcb;
    ip_addr_copy(tcp_transport->remote_ip, ctx->remote_ip);
    tcp_transport->remote_rtp_port = ctx->remote_rtp_port;

    // 创建并启动发送队列定时器（每10ms触发一次）
    if (luat_rtos_timer_create(&tcp_transport->send_timer) != 0) {
        LLOGE("TCP发送定时器创建失败");
        luat_heap_free(tcp_transport->send_buf);
        luat_heap_free(tcp_transport);
        return RTSP_ERR_NO_MEMORY;
    }

    if (luat_rtos_timer_start(tcp_transport->send_timer, 10, 1, rtsp_tcp_send_timer_callback, NULL) != 0) {
        LLOGE("TCP发送定时器启动失败");
        luat_rtos_timer_delete(tcp_transport->send_timer);
        luat_heap_free(tcp_transport->send_buf);
        luat_heap_free(tcp_transport);
        return RTSP_ERR_FAILED;
    }

    LLOGD("TCP发送定时器已启动");

    // 设置传输层接口
    transport->send = rtsp_tcp_transport_send;
    transport->send_rtcp = rtsp_tcp_transport_send_rtcp;
    transport->init = rtsp_tcp_transport_init;
    transport->cleanup = rtsp_tcp_transport_cleanup;
    transport->ctx = ctx;
    transport->private_data = tcp_transport;

    LLOGD("TCP传输层初始化成功");
    return RTSP_OK;
}

/**
 * TCP传输层清理函数
 */
static void rtsp_tcp_transport_cleanup(rtsp_transport_t *transport) {
    if (!transport || !transport->private_data) {
        return;
    }

    rtsp_tcp_transport_t *tcp_transport = (rtsp_tcp_transport_t *)transport->private_data;

    // 停止并删除发送定时器
    if (tcp_transport->send_timer) {
        luat_rtos_timer_stop(tcp_transport->send_timer);
        luat_rtos_timer_delete(tcp_transport->send_timer);
        tcp_transport->send_timer = NULL;
        LLOGD("TCP发送定时器已删除");
    }

    // 清空发送队列
    rtsp_tcp_send_queue_clear(tcp_transport);

    // 释放发送缓冲区
    if (tcp_transport->send_buf) {
        luat_heap_free(tcp_transport->send_buf);
        tcp_transport->send_buf = NULL;
    }

    // 注意：不释放TCP PCB，因为使用的是RTSP控制连接，由RTSP上下文管理
    luat_heap_free(tcp_transport);
    transport->private_data = NULL;

    LLOGD("TCP传输层已清理");
}

/**
 * TCP传输层发送RTCP函数（TCP模式不支持RTCP）
 */
static int rtsp_tcp_transport_send_rtcp(rtsp_transport_t *transport, const uint8_t *data, uint32_t len) {
    // TCP 模式下，RTCP 和 RTP 都通过同一个 TCP 连接发送
    // 使用相同的发送函数
    return rtsp_tcp_transport_send(transport, data, len);
}

/**
 * 设置传输模式
 */
int rtsp_set_transport_mode(rtsp_ctx_t *ctx, rtsp_transport_mode_t mode) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    if (ctx->state != RTSP_STATE_IDLE) {
        LLOGE("只能在空闲状态下设置传输模式");
        return RTSP_ERR_FAILED;
    }

    ctx->transport_mode = mode;
    LLOGD("传输模式已设置为: %d", mode);

    return RTSP_OK;
}

/**
 * 获取网络统计信息
 */
int rtsp_get_network_stats(rtsp_ctx_t *ctx, rtsp_network_stats_t *stats) {
    if (!ctx || !stats) {
        return RTSP_ERR_INVALID_PARAM;
    }

    memcpy(stats, &ctx->network_stats, sizeof(rtsp_network_stats_t));

    return RTSP_OK;
}

/**
 * 设置网络统计回调
 */
int rtsp_set_network_stats_callback(rtsp_ctx_t *ctx, rtsp_network_stats_callback_t callback) {
    if (!ctx) {
        return RTSP_ERR_INVALID_PARAM;
    }

    ctx->network_stats_callback = callback;

    return RTSP_OK;
}

/* ======================== RTCP处理实现 ======================== */

/**
 * RTCP UDP接收回调函数
 */
static void rtcp_udp_recv_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                                   const ip_addr_t *addr, uint16_t port) {
    rtsp_ctx_t *ctx = (rtsp_ctx_t *)arg;

    if (!ctx || !p) {
        if (p) pbuf_free(p);
        return;
    }

    // 复制数据到接收缓冲区
    if (p->tot_len > RTSP_BUFFER_SIZE) {
        LLOGW("RTCP包过大: %u字节", p->tot_len);
        pbuf_free(p);
        return;
    }

    uint8_t *rtcp_data = (uint8_t *)luat_heap_malloc(p->tot_len);
    if (!rtcp_data) {
        LLOGE("RTCP数据内存分配失败");
        pbuf_free(p);
        return;
    }

    pbuf_copy_partial(p, rtcp_data, p->tot_len, 0);

    LLOGD("收到RTCP包: %u字节, 来自 %s:%u", p->tot_len, ipaddr_ntoa(addr), port);

    // 处理RTCP包
    rtsp_handle_rtcp_packet(ctx, rtcp_data, p->tot_len);

    luat_heap_free(rtcp_data);
    pbuf_free(p);
}

/**
 * 处理RTCP包
 */
static int rtsp_handle_rtcp_packet(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len) {
    if (!ctx || !data || len < 4) {
        return RTSP_ERR_INVALID_PARAM;
    }

    uint32_t offset = 0;

    // RTCP可能包含多个包，循环处理
    while (offset + 4 <= len) {
        // 解析RTCP头部
        // Byte 0: V(2) + P(1) + RC(5)
        // Byte 1: PT (Packet Type)
        // Bytes 2-3: Length (in words, excluding header)

        uint8_t v = (data[offset] >> 6) & 0x03;
        uint8_t p = (data[offset] >> 5) & 0x01;
        uint8_t rc = data[offset] & 0x1F;
        uint8_t pt = data[offset + 1];
        uint16_t length = ((data[offset + 2] << 8) | data[offset + 3]) + 1;  // +1 for header
        uint32_t packet_len = length * 4;

        // 验证RTSP版本
        if (v != 2) {
            LLOGE("不支持的RTCP版本: %u", v);
            return RTSP_ERR_FAILED;
        }

        // 检查包长度
        if (offset + packet_len > len) {
            LLOGE("RTCP包长度错误");
            return RTSP_ERR_FAILED;
        }

        LLOGD("RTCP包: PT=%u, RC=%u, 长度=%u字节", pt, rc, packet_len);

        // 根据包类型处理
        switch (pt) {
            case RTCP_SR:
                // Sender Report (我们发送的，忽略)
                LLOGD("收到RTCP SR (忽略)");
                break;

            case RTCP_RR:
                // Receiver Report (处理丢包率、延迟等)
                rtsp_handle_rtcp_rr(ctx, data + offset, packet_len);
                break;

            case RTCP_RTPFB:
                // RTP Feedback (NACK)
                rtsp_handle_rtcp_nack(ctx, data + offset, packet_len);
                break;

            case RTCP_SDES:
                // Source Description (忽略)
                LLOGD("收到RTCP SDES (忽略)");
                break;

            case RTCP_BYE:
                // Goodbye (忽略)
                LLOGD("收到RTCP BYE (忽略)");
                break;

            default:
                LLOGW("未知的RTCP包类型: %u", pt);
                break;
        }

        offset += packet_len;
    }

    return RTSP_OK;
}

/**
 * 处理RTCP NACK消息
 */
static int rtsp_handle_rtcp_nack(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len) {
    if (!ctx || !data || len < 16) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // RTCP NACK格式 (RFC 4585):
    // Bytes 0-3: Header (V=2, P=0, FMT=1, PT=205)
    // Bytes 4-7: SSRC of packet sender
    // Bytes 8-11: SSRC of media source
    // Bytes 12-15: NACK PID (Packet ID)
    // Bytes 16-19: NACK BLP (Bitmask of Following Lost Packets)

    // 提取丢失的包序列号
    uint16_t pid = ((data[12] << 8) | data[13]);
    uint16_t blp = ((data[14] << 8) | data[15]);

    LLOGD("RTCP NACK: PID=%u, BLP=0x%04X", pid, blp);

    // 更新NACK统计
    ctx->network_stats.rtp_nack_received++;

    // 重传PID指定的包
    // rtsp_retransmit_buffer_retransmit(ctx, pid);

    // 重传BLP中指定的包（最多16个）
    for (int i = 0; i < 16; i++) {
        if (blp & (1 << i)) {
            uint16_t seq = pid + i + 1;
            LLOGD("重传NACK包: seq=%u", seq);
            // rtsp_retransmit_buffer_retransmit(ctx, seq);
        }
    }

    return RTSP_OK;
}

/**
 * 处理RTCP RR消息
 */
static int rtsp_handle_rtcp_rr(rtsp_ctx_t *ctx, const uint8_t *data, uint32_t len) {
    if (!ctx || !data || len < 8) {
        return RTSP_ERR_INVALID_PARAM;
    }

    // RTCP RR格式 (RFC 3550):
    // Bytes 0-3: Header (V=2, P=0, RC=report count, PT=201)
    // Bytes 4-7: SSRC of packet sender
    // 每个report block (24 bytes):
    //   Bytes 0-3: SSRC of source
    //   Bytes 4-7: Fraction lost (8 bits) + Cumulative packets lost (24 bits)
    //   Bytes 8-11: Extended highest sequence number received
    //   Bytes 12-15: Interarrival jitter
    //   Bytes 16-19: Last SR timestamp (LSR)
    //   Bytes 20-23: Delay since last SR (DLSR)

    uint8_t rc = data[0] & 0x1F;  // Report count

    LLOGD("RTCP RR: Report count=%u", rc);

    if (len < 8 + rc * 24) {
        LLOGE("RTCP RR包长度错误");
        return RTSP_ERR_FAILED;
    }

    // 处理每个report block
    for (uint8_t i = 0; i < rc; i++) {
        uint32_t offset = 8 + i * 24;

        // 提取丢包率
        uint8_t fraction_lost = data[offset + 4];
        int32_t cumulative_lost = ((data[offset + 5] << 16) | (data[offset + 6] << 8) | data[offset + 7]);
        if (data[offset + 5] & 0x80) {
            cumulative_lost |= 0xFF000000;  // 符号扩展
        }

        // 提取抖动
        uint32_t jitter = ((data[offset + 12] << 24) | (data[offset + 13] << 16) |
                          (data[offset + 14] << 8) | data[offset + 15]);

        // 提取LSR和DLSR
        uint32_t lsr = ((data[offset + 16] << 24) | (data[offset + 17] << 16) |
                       (data[offset + 18] << 8) | data[offset + 19]);
        uint32_t dlsr = ((data[offset + 20] << 24) | (data[offset + 21] << 16) |
                        (data[offset + 22] << 8) | data[offset + 23]);

        // 计算往返延迟 (RTT)
        // LSR: NTP 时间戳中间 32 位（秒数，从1900年开始）
        // DLSR: 延迟（单位：1/65536 秒）
        // RTT = 当前时间 - LSR - DLSR
        uint32_t rtt_ms = 0;
        if (lsr > 0 && dlsr > 0) {
            // 获取当前 NTP 时间（秒）
            uint64_t now_ms = luat_sntp_time64_ms();
            uint64_t now_ntp_sec = (now_ms / 1000) + 2208988800ULL;  // 转换为 NTP 时间（从1900年开始）
            
            // 计算 RTT（单位：1/65536 秒）
            uint64_t rtt_units = (now_ntp_sec - lsr) * 65536 - dlsr;
            
            // 转换为毫秒（1/65536 秒 = 15.2587890625 微秒）
            rtt_ms = (uint32_t)(rtt_units / 65.536);
        }

        LLOGD("RTCP RR Block %u: 丢包率=%u/256, 累计丢失=%d, 抖动=%u, RTT=%ums",
              i, fraction_lost, cumulative_lost, jitter, rtt_ms);

        // 更新网络统计
        ctx->network_stats.packet_loss_rate = fraction_lost / 256.0f;
        ctx->network_stats.rtt_ms = rtt_ms;
        ctx->network_stats.jitter_ms = jitter / 90;  // 转换为毫秒 (90kHz时钟)
        ctx->network_stats.rtp_packets_lost = cumulative_lost;
    }

    return RTSP_OK;
}

