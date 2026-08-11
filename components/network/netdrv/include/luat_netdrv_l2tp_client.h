#pragma once

/*
 * L2TPv2 client core for LuatOS netdrv.
 *
 * Transport: LuatOS network adapter (UDP mode, like the OpenVPN client),
 * never a direct lwIP udp_pcb.  Control plane and PPP session follow
 * RFC 2661 (LAC) with PAP + CHAP(MD5) authentication and optional
 * L2TP tunnel authentication (shared secret).
 *
 * The PPP stack is the vendored lwIP 2.2.1 PPP code under
 * components/network/netdrv/src/ppp/ (ppp.c / lcp.c / ipcp.c / auth.c /
 * fsm.c / upap.c / chap-new.c / chap-md5.c / magic.c / utils.c).
 */

#include <stddef.h>
#include <stdint.h>
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "luat_network_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========== L2TPv2 protocol constants (RFC 2661, from lwip22 pppol2tp.h) ========== */

/* Timeout / retry */
#define L2TP_CONTROL_TIMEOUT         (5 * 1000)  /* base for quick timeout calculation */
#define L2TP_SLOW_RETRY              (60 * 1000) /* persistent retry interval */
#define L2TP_MAXSCCRQ                4           /* retry SCCRQ four times (quickly) */
#define L2TP_MAXICRQ                 4           /* retry ICRQ four times */
#define L2TP_MAXICCN                 4           /* retry ICCN four times */
#define L2TP_TICK_INTERVAL_MS        500         /* periodic transport-error check */

/* L2TP header flags */
#define L2TP_HEADERFLAG_CONTROL      0x8000
#define L2TP_HEADERFLAG_LENGTH       0x4000
#define L2TP_HEADERFLAG_SEQUENCE     0x0800
#define L2TP_HEADERFLAG_OFFSET       0x0200
#define L2TP_HEADERFLAG_PRIORITY     0x0100
#define L2TP_HEADERFLAG_VERSION      0x0002

/* Mandatory bits for control: Control, Length, Sequence, Version 2 */
#define L2TP_HEADERFLAG_CONTROL_MANDATORY \
    (L2TP_HEADERFLAG_CONTROL | L2TP_HEADERFLAG_LENGTH | L2TP_HEADERFLAG_SEQUENCE | L2TP_HEADERFLAG_VERSION)
/* Forbidden bits for control: Offset, Priority */
#define L2TP_HEADERFLAG_CONTROL_FORBIDDEN (L2TP_HEADERFLAG_OFFSET | L2TP_HEADERFLAG_PRIORITY)
/* Mandatory bits for data: Version 2 */
#define L2TP_HEADERFLAG_DATA_MANDATORY    (L2TP_HEADERFLAG_VERSION)

/* AVP header */
#define L2TP_AVPHEADERFLAG_MANDATORY  0x8000
#define L2TP_AVPHEADERFLAG_HIDDEN     0x4000
#define L2TP_AVPHEADERFLAG_LENGTHMASK 0x03ff

/* AVP - Message type */
#define L2TP_AVPTYPE_MESSAGE          0

/* Control connection management */
#define L2TP_MESSAGETYPE_SCCRQ        1
#define L2TP_MESSAGETYPE_SCCRP        2
#define L2TP_MESSAGETYPE_SCCCN        3
#define L2TP_MESSAGETYPE_STOPCCN      4
#define L2TP_MESSAGETYPE_HELLO        6
/* Call management */
#define L2TP_MESSAGETYPE_ICRQ        10
#define L2TP_MESSAGETYPE_ICRP        11
#define L2TP_MESSAGETYPE_ICCN        12

/* AVP attributes */
#define L2TP_AVPTYPE_RESULTCODE       1
#define L2TP_RESULTCODE               1  /* General request to clear control connection */
#define L2TP_AVPTYPE_VERSION          2
#define L2TP_VERSION                  0x0100 /* L2TP protocol version 1, revision 0 */
#define L2TP_AVPTYPE_FRAMINGCAPABILITIES 3
#define L2TP_FRAMINGCAPABILITIES      0x00000003 /* Async + Sync framing */
#define L2TP_AVPTYPE_BEARERCAPABILITIES  4
#define L2TP_BEARERCAPABILITIES       0x00000003 /* Analog + Digital access */
#define L2TP_AVPTYPE_TIEBREAKER       5
#define L2TP_AVPTYPE_HOSTNAME         7
#define L2TP_HOSTNAME                 "LuatOS"
#define L2TP_AVPTYPE_VENDORNAME       8
#define L2TP_VENDORNAME               "LuatOS"
#define L2TP_AVPTYPE_TUNNELID         9
#define L2TP_AVPTYPE_RECEIVEWINDOWSIZE 10
#define L2TP_RECEIVEWINDOWSIZE        8
#define L2TP_AVPTYPE_CHALLENGE        11
#define L2TP_AVPTYPE_CHALLENGERESPONSE 13
#define L2TP_AVPTYPE_CHALLENGERESPONSE_SIZE 16
#define L2TP_AVPTYPE_SESSIONID        14
#define L2TP_AVPTYPE_CALLSERIALNUMBER 15
#define L2TP_AVPTYPE_FRAMINGTYPE      19
#define L2TP_FRAMINGTYPE              0x00000001 /* Sync framing */
#define L2TP_AVPTYPE_TXCONNECTSPEED   24
#define L2TP_TXCONNECTSPEED           100000000  /* Connect speed: 100 Mbits/s */

/* L2TP session state */
#define L2TP_STATE_INITIAL            0
#define L2TP_STATE_SCCRQ_SENT         1
#define L2TP_STATE_ICRQ_SENT          2
#define L2TP_STATE_ICCN_SENT          3
#define L2TP_STATE_DATA               4

#define L2TP_OUTPUT_DATA_HEADER_LEN   6
#define L2TP_DEFAULT_MTU              1450
#define L2TP_DEFAULT_PORT             1701

/* Event types delivered through the status callback (PPPERR_* codes from ppp.h) */
typedef struct l2tp_client l2tp_client_t;

typedef struct l2tp_client_cfg {
    ip_addr_t  remote_ip;         /* LNS IP */
    uint16_t   remote_port;       /* LNS port, default 1701 */
    uint16_t   mtu;               /* PPP MRU, default 1450 */
    uint8_t    adapter_index;     /* 虚拟网卡编号（netdrv id，用于 net_lwip2 注册） */
    uint8_t    transport_index;   /* 底层传输网卡编号（用于 network_alloc_ctrl） */
    const char *username;         /* PPP 用户名 (可选) */
    size_t     username_len;
    const char *password;         /* PPP 密码 (可选) */
    size_t     password_len;
    const char *secret;           /* L2TP 隧道共享密钥 (可选) */
    size_t     secret_len;
    uint8_t    retry_enable;      /* 失败后自动重连 */
    uint32_t   retry_base_ms;
    uint32_t   retry_max_ms;
    /* PPP 链路状态回调: err_code == PPPERR_NONE 表示已就绪, 其他为断开/失败 */
    void (*status_cb)(l2tp_client_t *cli, int err_code, void *user_data);
    void *user_data;
} l2tp_client_cfg_t;

struct l2tp_client {
    /* 配置 (字符串已复制到客户端自有堆内存) */
    ip_addr_t  remote_ip;
    uint16_t   remote_port;
    uint16_t   mtu;
    uint8_t    adapter_index;
    uint8_t    transport_index;
    uint8_t    retry_enable;
    uint32_t   retry_base_ms;
    uint32_t   retry_max_ms;
    char      *username;
    size_t     username_len;
    char      *password;
    size_t     password_len;
    char      *secret;
    size_t     secret_len;

    /* 传输层 (network adapter UDP) */
    network_ctrl_t *netc;
    volatile uint8_t transport_err; /* 非0: 传输 socket 异常, 由周期定时器处理 */
    uint8_t started;
    uint8_t debug;
    uint8_t user_close;      /* 用户主动关闭, 不自动重连 */
    uint8_t tearing_down;    /* 正在拆卸, 防止递归 */
    uint8_t ppp_inited;      /* ppp_init() 已调用 */

    /* L2TPv2 控制面状态 */
    uint8_t  phase;          /* L2TP_STATE_* */
    uint16_t tunnel_port;
    uint16_t our_ns;
    uint16_t peer_nr;
    uint16_t peer_ns;
    uint16_t source_tunnel_id;   /* 对端分配的 tunnel id */
    uint16_t remote_tunnel_id;   /* 本端分配的 tunnel id */
    uint16_t source_session_id;  /* 对端分配的 session id */
    uint16_t remote_session_id;  /* 本端分配的 session id */
    uint8_t  sccrq_retried;
    uint8_t  icrq_retried;
    uint8_t  iccn_retried;
    uint8_t  secret_rv[16];      /* 隧道认证随机向量 */
    uint8_t  challenge_hash[16]; /* 隧道认证挑战响应 */
    uint8_t  send_challenge;     /* SCCCN 是否携带 challenge response */

    /* 重连退避 */
    uint8_t  retry_timer_active;
    uint32_t retry_attempt;

    /* PPP (vendored lwip ppp, opaque here) */
    struct netif netif;
    void *ppp;                    /* ppp_pcb* */

    /* 回调 */
    void (*status_cb)(l2tp_client_t *cli, int err_code, void *user_data);
    void *user_data;
};

/* API */
int  l2tp_client_init(l2tp_client_t *cli, const l2tp_client_cfg_t *cfg);
int  l2tp_client_start(l2tp_client_t *cli);
void l2tp_client_stop(l2tp_client_t *cli);
void l2tp_client_set_debug(l2tp_client_t *cli, int enable);
int  l2tp_client_is_ready(l2tp_client_t *cli);

#ifdef __cplusplus
}
#endif
