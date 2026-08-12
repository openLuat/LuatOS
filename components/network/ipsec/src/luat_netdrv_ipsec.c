/**
 * IKEv2/IPsec (tunnel mode) netdrv 适配层
 *
 * 将 components/network/ipsec 下的 IKEv2 客户端集成到 netdrv
 * 框架：setup/ctrl(UPDOWN)/dhcp(-1)/debug + 链路状态回调。
 * 数据面（虚拟 netif -> ESP -> adapter UDP 4500）由 ipsec_client 内部实现，
 * 这里只负责生命周期与 Lua 事件。
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_ipsec.h"
#include "ipsec/ipsec_ike.h"
#include "luat_netdrv_event.h"
#include "luat_mem.h"
#include "lwip/netif.h"
#include "lwip/tcpip.h"
#include "lwip/inet.h"
#include "net_lwip2.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "ipsec_netdrv"
#include "luat_log.h"

/**
 * IPsec netdrv 私有数据结构
 */
typedef struct {
    ipsec_client_t *client;
} luat_netdrv_ipsec_ctx_t;

/**
 * 隧道状态回调 (在 tcpip 线程执行)
 * err_code == 0 -> 隧道就绪 (虚拟 IP 已下发), 发布 IP_READY
 * 其他          -> 链路断开, 发布 IP_LOSE (自动重连由客户端内部处理)
 */
static void ipsec_netdrv_link_status_cb(ipsec_client_t *cli, int err_code, void *user_data) {
    luat_netdrv_t *drv = (luat_netdrv_t *)user_data;
    (void)cli;
    if (!drv) return;

    if (err_code == 0 && ipsec_client_is_ready(cli)) {
        LLOGI("[%d] IPsec connected", drv->id);
        net_lwip2_set_link_state(drv->id, 1);
        luat_netdrv_send_ip_event(drv, 1);
    } else {
        LLOGE("[%d] IPsec link down, err_code=%d", drv->id, err_code);
        net_lwip2_set_link_state(drv->id, 0);
        luat_netdrv_send_ip_event(drv, 0);
    }
}

/**
 * IPsec netdrv boot 函数（无操作，启动在 setup 中完成）
 */
static int ipsec_boot(luat_netdrv_t *drv, void *userdata) {
    (void)drv; (void)userdata;
    return 0;
}

/**
 * IPsec netdrv DHCP 函数（虚拟 IP 由 IKEv2 CP 下发，不支持 DHCP）
 */
static int ipsec_dhcp(luat_netdrv_t *drv, void *userdata, int enable) {
    (void)userdata; (void)enable;
    LLOGW("[%d] IPsec does not support DHCP", drv->id);
    return -1;
}

/**
 * IPsec netdrv debug 函数（调试输出）
 */
static int ipsec_debug(luat_netdrv_t *drv, void *userdata, int enable) {
    if (drv == NULL || drv->userdata == NULL) {
        return -1;
    }
    luat_netdrv_ipsec_ctx_t *ctx = (luat_netdrv_ipsec_ctx_t *)drv->userdata;
    if (ctx->client != NULL) {
        ipsec_client_set_debug(ctx->client, enable);
        LLOGD("[%d] IPsec debug %s", drv->id, enable ? "enabled" : "disabled");
    }
    return 0;
}

/**
 * IPsec netdrv 控制命令
 * @param cmd LUAT_NETDRV_CTRL_UPDOWN — param!=0 启动, param==0 停止
 */
static int ipsec_ctrl(luat_netdrv_t *drv, void *userdata, int cmd, void *param) {
    luat_netdrv_ipsec_ctx_t *ctx = (luat_netdrv_ipsec_ctx_t *)userdata;
    if (!ctx || !ctx->client) return -1;

    switch (cmd) {
        case LUAT_NETDRV_CTRL_UPDOWN: {
            int up = (int)(intptr_t)param;
            if (up) {
                LLOGI("[%d] IPsec ctrl: up", drv->id);
                ipsec_client_start(ctx->client);
            } else {
                LLOGI("[%d] IPsec ctrl: down", drv->id);
                ipsec_client_stop(ctx->client);
            }
            return 0;
        }

        default:
            LLOGW("[%d] IPsec ctrl: unknown cmd %d", drv->id, cmd);
            return -1;
    }
}

/**
 * IPsec netdrv 初始化设置
 * @param conf netdrv 配置结构体指针
 * @return 成功返回 luat_netdrv_t 指针，失败返回 NULL
 */
luat_netdrv_t* luat_netdrv_ipsec_setup(luat_netdrv_conf_t *conf) {
    if (conf == NULL) {
        LLOGE("Invalid configuration");
        return NULL;
    }
    if (conf->ipsec_conf == NULL) {
        LLOGE("IPsec configuration missing");
        return NULL;
    }

    LLOGI("Setting up IPsec netdrv for adapter %d", conf->id);

    /* 分配 netdrv 结构体内存 */
    luat_netdrv_t *drv = (luat_netdrv_t *)luat_heap_malloc(sizeof(luat_netdrv_t));
    if (drv == NULL) {
        LLOGE("Failed to allocate memory for netdrv");
        return NULL;
    }
    memset(drv, 0, sizeof(luat_netdrv_t));

    /* 分配 IPsec 上下文内存 */
    luat_netdrv_ipsec_ctx_t *ctx = (luat_netdrv_ipsec_ctx_t *)luat_heap_malloc(sizeof(luat_netdrv_ipsec_ctx_t));
    if (ctx == NULL) {
        LLOGE("Failed to allocate memory for IPsec context");
        luat_heap_free(drv);
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_netdrv_ipsec_ctx_t));

    /* 分配 IPsec 客户端内存 */
    ipsec_client_t *client = (ipsec_client_t *)luat_heap_malloc(sizeof(ipsec_client_t));
    if (client == NULL) {
        LLOGE("Failed to allocate memory for IPsec client");
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    ipsec_client_cfg_t cfg = {0};

    /* 远程网关地址 (仅 IP 字面量, 同 OpenVPN/L2TP) */
    if (conf->ipsec_conf->ipsec_remote_ip != NULL && conf->ipsec_conf->ipsec_remote_ip[0] != '\0') {
        if (!ipaddr_aton(conf->ipsec_conf->ipsec_remote_ip, &cfg.remote_ip)) {
            LLOGE("IPsec remote host must be an IP address: %s", conf->ipsec_conf->ipsec_remote_ip);
            luat_heap_free(client);
            luat_heap_free(ctx);
            luat_heap_free(drv);
            return NULL;
        }
    } else {
        LLOGE("IPsec remote host missing");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    /* 远程 IKE 端口, 默认 500 */
    cfg.remote_port = conf->ipsec_conf->ipsec_remote_port ? conf->ipsec_conf->ipsec_remote_port : IPSEC_IKE_PORT;

    /* MTU, 默认 1400 */
    if (conf->ipsec_conf->ipsec_mtu > 0) {
        cfg.mtu = conf->ipsec_conf->ipsec_mtu;
    } else if (conf->mtu > 0) {
        cfg.mtu = conf->mtu;
    } else {
        cfg.mtu = IPSEC_DEFAULT_MTU;
    }

    /* 虚拟网卡编号 + 底层传输网卡编号 */
    cfg.adapter_index = (uint8_t)conf->id;
    cfg.transport_index = (uint8_t)network_register_get_default();

    /* EAP-MSCHAPv2 认证 */
    if (conf->ipsec_conf->ipsec_username != NULL && conf->ipsec_conf->ipsec_username_len > 0) {
        cfg.username = (char *)conf->ipsec_conf->ipsec_username;
        cfg.username_len = conf->ipsec_conf->ipsec_username_len;
    }
    if (conf->ipsec_conf->ipsec_password != NULL && conf->ipsec_conf->ipsec_password_len > 0) {
        cfg.password = (char *)conf->ipsec_conf->ipsec_password;
        cfg.password_len = conf->ipsec_conf->ipsec_password_len;
    }
    if (conf->ipsec_conf->ipsec_username == NULL || conf->ipsec_conf->ipsec_password == NULL) {
        LLOGE("IPsec EAP-MSCHAPv2 username/password required");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    /* 服务器证书信任锚 + SAN (可选; 不提供时无条件接受服务器证书) */
    if (conf->ipsec_conf->ipsec_ca_cert_pem != NULL && conf->ipsec_conf->ipsec_ca_cert_pem_len > 0) {
        cfg.ca_cert_pem = (char *)conf->ipsec_conf->ipsec_ca_cert_pem;
        cfg.ca_cert_pem_len = conf->ipsec_conf->ipsec_ca_cert_pem_len;
    }
    cfg.san = (char *)(conf->ipsec_conf->ipsec_san ? conf->ipsec_conf->ipsec_san
                                                   : conf->ipsec_conf->ipsec_remote_ip);

    /* 重试参数 */
    if (conf->ipsec_conf->ipsec_retry_enable) {
        cfg.retry_enable = 1;
        cfg.retry_base_ms = conf->ipsec_conf->ipsec_retry_base_ms ? conf->ipsec_conf->ipsec_retry_base_ms : 1000;
        cfg.retry_max_ms = conf->ipsec_conf->ipsec_retry_max_ms ? conf->ipsec_conf->ipsec_retry_max_ms : 60000;
        if (cfg.retry_max_ms < cfg.retry_base_ms) {
            cfg.retry_max_ms = cfg.retry_base_ms;
        }
    }

    /* 回调 */
    cfg.status_cb = ipsec_netdrv_link_status_cb;
    cfg.user_data = (void *)drv;

    int ret = ipsec_client_init(client, &cfg);
    if (ret != 0) {
        LLOGE("Failed to initialize IPsec client: %d", ret);
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
    drv->boot = ipsec_boot;
    drv->dhcp = ipsec_dhcp;
    drv->debug = ipsec_debug;
    drv->ctrl = ipsec_ctrl;

    /* 注册到 netdrv 系统 */
    int reg_ret = luat_netdrv_register(conf->id, drv);
    if (reg_ret != 0) {
        LLOGE("Failed to register IPsec netdrv");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }

    LLOGI("IPsec netdrv setup completed successfully");

    ipsec_client_start(client);

    return drv;
}
