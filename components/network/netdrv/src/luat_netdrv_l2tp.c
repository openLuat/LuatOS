/**
 * L2TPv2 netdrv 适配层
 * 将 L2TPv2 客户端 (LAC) 集成到 netdrv 框架中
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_l2tp.h"
#include "luat_netdrv_l2tp_client.h"
#include "luat_netdrv_event.h"
#include "luat_mem.h"
#include "lwip/netif.h"
#include "lwip/tcpip.h"
#include "lwip/inet.h"
#include "net_lwip2.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "l2tp_netdrv"
#include "luat_log.h"

/**
 * L2TP netdrv 私有数据结构
 */
typedef struct {
    l2tp_client_t *client;
} luat_netdrv_l2tp_ctx_t;

/**
 * PPP 链路状态回调 (在 tcpip 线程执行)
 *
 * err_code 复用 lwip PPP 的错误码:
 *   PPPERR_NONE(0)    -> 链路就绪, 发布 IP_READY
 *   其他 (AUTHFAIL/CONNECT/USER/PEERDEAD/...) -> 链路断开, 发布 IP_LOSE
 * 自动重连由 l2tp_client 内部处理, 这里只负责 net_lwip2 链路状态与 Lua 事件。
 */
static void l2tp_netdrv_link_status_cb(l2tp_client_t *cli, int err_code, void *user_data) {
    luat_netdrv_t *drv = (luat_netdrv_t *)user_data;
    if (!drv) return;

    if (err_code == 0 /* PPPERR_NONE */ && l2tp_client_is_ready(cli)) {
        LLOGI("[%d] L2TP connected", drv->id);
        /* PPP 的 sifup() 已调用 netif_set_link_up; 这里补上 lwip2 适配器
         * 链路状态与 IP_READY 事件 (luat_netdrv_set_link_updown 此时是 no-op) */
        net_lwip2_set_link_state(drv->id, 1);
        luat_netdrv_send_ip_event(drv, 1);
    } else {
        LLOGE("[%d] L2TP link down, err_code=%d", drv->id, err_code);
        net_lwip2_set_link_state(drv->id, 0);
        luat_netdrv_send_ip_event(drv, 0);
    }
}

/**
 * L2TP netdrv boot 函数（无操作，启动在 setup 中完成）
 */
static int l2tp_boot(luat_netdrv_t *drv, void *userdata) {
    return 0;
}

/**
 * L2TP netdrv DHCP 函数（IP 由 IPCP 下发，不支持 DHCP）
 */
static int l2tp_dhcp(luat_netdrv_t *drv, void *userdata, int enable) {
    LLOGW("[%d] L2TP does not support DHCP", drv->id);
    return -1;
}

/**
 * L2TP netdrv debug 函数（调试输出）
 */
static int l2tp_debug(luat_netdrv_t *drv, void *userdata, int enable) {
    if (drv == NULL || drv->userdata == NULL) {
        return -1;
    }
    luat_netdrv_l2tp_ctx_t *ctx = (luat_netdrv_l2tp_ctx_t *)drv->userdata;
    if (ctx->client != NULL) {
        l2tp_client_set_debug(ctx->client, enable);
        LLOGD("[%d] L2TP debug %s", drv->id, enable ? "enabled" : "disabled");
    }
    return 0;
}

/**
 * L2TP netdrv 控制命令
 * @param cmd LUAT_NETDRV_CTRL_UPDOWN — param!=0 启动, param==0 停止
 */
static int l2tp_ctrl(luat_netdrv_t *drv, void *userdata, int cmd, void *param) {
    luat_netdrv_l2tp_ctx_t *ctx = (luat_netdrv_l2tp_ctx_t *)userdata;
    if (!ctx || !ctx->client) return -1;

    switch (cmd) {
        case LUAT_NETDRV_CTRL_UPDOWN: {
            int up = (int)(intptr_t)param;
            if (up) {
                LLOGI("[%d] L2TP ctrl: up", drv->id);
                l2tp_client_start(ctx->client);
            } else {
                LLOGI("[%d] L2TP ctrl: down", drv->id);
                l2tp_client_stop(ctx->client);
            }
            return 0;
        }

        default:
            LLOGW("[%d] L2TP ctrl: unknown cmd %d", drv->id, cmd);
            return -1;
    }
}

/**
 * L2TP netdrv 初始化设置
 * @param conf netdrv 配置结构体指针
 * @return 成功返回 luat_netdrv_t 指针，失败返回 NULL
 */
luat_netdrv_t* luat_netdrv_l2tp_setup(luat_netdrv_conf_t *conf) {
    if (conf == NULL) {
        LLOGE("Invalid configuration");
        return NULL;
    }
    if (conf->l2tp_conf == NULL) {
        LLOGE("L2TP configuration missing");
        return NULL;
    }

    LLOGI("Setting up L2TP netdrv for adapter %d", conf->id);

    /* 分配 netdrv 结构体内存 */
    luat_netdrv_t *drv = (luat_netdrv_t *)luat_heap_malloc(sizeof(luat_netdrv_t));
    if (drv == NULL) {
        LLOGE("Failed to allocate memory for netdrv");
        return NULL;
    }
    memset(drv, 0, sizeof(luat_netdrv_t));

    /* 分配 L2TP 上下文内存 */
    luat_netdrv_l2tp_ctx_t *ctx = (luat_netdrv_l2tp_ctx_t *)luat_heap_malloc(sizeof(luat_netdrv_l2tp_ctx_t));
    if (ctx == NULL) {
        LLOGE("Failed to allocate memory for L2TP context");
        luat_heap_free(drv);
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_netdrv_l2tp_ctx_t));

    /* 分配 L2TP 客户端内存 */
    l2tp_client_t *client = (l2tp_client_t *)luat_heap_malloc(sizeof(l2tp_client_t));
    if (client == NULL) {
        LLOGE("Failed to allocate memory for L2TP client");
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    l2tp_client_cfg_t cfg = {0};

    /* 远程 LNS 地址 (仅 IP 字面量, 同 OpenVPN) */
    if (conf->l2tp_conf->l2tp_remote_ip != NULL && conf->l2tp_conf->l2tp_remote_ip[0] != '\0') {
        if (!ipaddr_aton(conf->l2tp_conf->l2tp_remote_ip, &cfg.remote_ip)) {
            LLOGE("L2TP remote host must be an IP address: %s", conf->l2tp_conf->l2tp_remote_ip);
            luat_heap_free(client);
            luat_heap_free(ctx);
            luat_heap_free(drv);
            return NULL;
        }
    } else {
        LLOGE("L2TP remote host missing");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    /* 远程端口, 默认 1701 */
    cfg.remote_port = conf->l2tp_conf->l2tp_remote_port ? conf->l2tp_conf->l2tp_remote_port : L2TP_DEFAULT_PORT;

    /* MTU, 默认 1450 */
    if (conf->l2tp_conf->l2tp_mtu > 0) {
        cfg.mtu = conf->l2tp_conf->l2tp_mtu;
    } else if (conf->mtu > 0) {
        cfg.mtu = conf->mtu;
    } else {
        cfg.mtu = L2TP_DEFAULT_MTU;
    }

    /* 虚拟网卡编号 + 底层传输网卡编号 */
    cfg.adapter_index = (uint8_t)conf->id;
    cfg.transport_index = (uint8_t)network_register_get_default();

    /* PPP 认证 (可选) */
    if (conf->l2tp_conf->l2tp_username != NULL && conf->l2tp_conf->l2tp_username_len > 0) {
        cfg.username = conf->l2tp_conf->l2tp_username;
        cfg.username_len = conf->l2tp_conf->l2tp_username_len;
    }
    if (conf->l2tp_conf->l2tp_password != NULL && conf->l2tp_conf->l2tp_password_len > 0) {
        cfg.password = conf->l2tp_conf->l2tp_password;
        cfg.password_len = conf->l2tp_conf->l2tp_password_len;
    }

    /* L2TP 隧道认证 (可选) */
    if (conf->l2tp_conf->l2tp_secret != NULL && conf->l2tp_conf->l2tp_secret_len > 0) {
        cfg.secret = conf->l2tp_conf->l2tp_secret;
        cfg.secret_len = conf->l2tp_conf->l2tp_secret_len;
    }

    /* 重试参数 */
    if (conf->l2tp_conf->l2tp_retry_enable) {
        cfg.retry_enable = 1;
        cfg.retry_base_ms = conf->l2tp_conf->l2tp_retry_base_ms ? conf->l2tp_conf->l2tp_retry_base_ms : 1000;
        cfg.retry_max_ms = conf->l2tp_conf->l2tp_retry_max_ms ? conf->l2tp_conf->l2tp_retry_max_ms : 60000;
        if (cfg.retry_max_ms < cfg.retry_base_ms) {
            cfg.retry_max_ms = cfg.retry_base_ms;
        }
    }

    /* 回调 */
    cfg.status_cb = l2tp_netdrv_link_status_cb;
    cfg.user_data = (void *)drv;

    int ret = l2tp_client_init(client, &cfg);
    if (ret != 0) {
        LLOGE("Failed to initialize L2TP client: %d", ret);
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    /* 保存客户端指针到上下文 */
    ctx->client = client;

    /* 初始化 netdrv 结构体 */
    drv->id = conf->id;
    drv->userdata = (void *)ctx;
    drv->netif = &client->netif;
    drv->boot = l2tp_boot;
    drv->dhcp = l2tp_dhcp;
    drv->debug = l2tp_debug;
    drv->ctrl = l2tp_ctrl;

    /* 注册到 netdrv 系统 */
    int reg_ret = luat_netdrv_register(conf->id, drv);
    if (reg_ret != 0) {
        LLOGE("Failed to register L2TP netdrv");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    LLOGI("L2TP netdrv setup completed successfully");

    l2tp_client_start(client);

    return drv;
}

