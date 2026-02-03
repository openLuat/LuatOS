/**
 * OpenVPN netdrv 适配层
 * 将 OpenVPN 客户端集成到 netdrv 框架中
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_openvpn.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_crypto.h"
#include "lwip/netif.h"
#include "lwip/tcpip.h"
#include "net_lwip2.h"

/* OpenVPN 客户端头文件 */
#include "luat_netdrv_openvpn_client.h"

#define LUAT_LOG_TAG "openvpn_netdrv"
#include "luat_log.h"

/**
 * OpenVPN netdrv 私有数据结构
 */
typedef struct {
    ovpn_client_t *client;
    luat_netdrv_conf_t *conf;
} luat_netdrv_openvpn_ctx_t;

/**
 * OpenVPN 事件回调转发给 netdrv 框架
 */
static void ovpn_netdrv_event_callback(ovpn_event_t event, void *user_data) {
    luat_netdrv_t *drv = (luat_netdrv_t *)user_data;
    
    if (drv == NULL) {
        return;
    }
    
    const char *event_name = NULL;
    
    switch (event) {
        case OVPN_EVENT_CONNECTED:
            event_name = "OPENVPN_CONNECTED";
            LLOGI("[%d] OpenVPN connected", drv->id);
            break;
        case OVPN_EVENT_TLS_HANDSHAKE_OK:
            event_name = "OPENVPN_TLS_HANDSHAKE_OK";
            LLOGI("[%d] OpenVPN TLS handshake successful", drv->id);
            break;
        case OVPN_EVENT_TLS_HANDSHAKE_FAIL:
            event_name = "OPENVPN_TLS_HANDSHAKE_FAIL";
            LLOGE("[%d] OpenVPN TLS handshake failed", drv->id);
            break;
        case OVPN_EVENT_KEEPALIVE_TIMEOUT:
            event_name = "OPENVPN_KEEPALIVE_TIMEOUT";
            LLOGW("[%d] OpenVPN keepalive timeout", drv->id);
            break;
        case OVPN_EVENT_AUTH_FAILED:
            event_name = "OPENVPN_AUTH_FAILED";
            LLOGE("[%d] OpenVPN authentication failed", drv->id);
            break;
        case OVPN_EVENT_DISCONNECTED:
            event_name = "OPENVPN_DISCONNECTED";
            LLOGI("[%d] OpenVPN disconnected", drv->id);
            break;
        case OVPN_EVENT_DATA_RX:
            // 数据接收事件，通常不需要日志
            return;
        case OVPN_EVENT_DATA_TX:
            // 数据发送事件，通常不需要日志
            return;
        default:
            LLOGW("[%d] Unknown OpenVPN event: %d", drv->id, event);
            return;
    }
    
    // 可以在这里添加进一步的处理，比如事件分发到上层
    // luat_netdrv_notify_event(drv->id, event_name);
    if (event_name) {
        #if 0
        rtos_msg_t msg = {0};
        msg.handler = l_netdrv_openvpn_handler;
        msg.arg1 = drv->id;
        msg.arg2 = event;
        msg.ptr = (void *)event_name;
        luat_msgbus_put(&msg, 0);
        #endif
    }
}

/**
 * OpenVPN netdrv boot 函数（启动网络设备）
 */
static int openvpn_boot(luat_netdrv_t *drv, void *userdata) {
    if (drv == NULL || drv->userdata == NULL) {
        LLOGE("Invalid OpenVPN netdrv");
        return -1;
    }
    
    luat_netdrv_openvpn_ctx_t *ctx = (luat_netdrv_openvpn_ctx_t *)drv->userdata;
    ovpn_client_t *client = ctx->client;
    
    if (client == NULL) {
        LLOGE("[%d] OpenVPN client not initialized", drv->id);
        return -1;
    }
    
    int ret = ovpn_client_start(client);
    if (ret != 0) {
        LLOGE("[%d] OpenVPN client start failed: %d", drv->id, ret);
        return ret;
    }
    
    LLOGI("[%d] OpenVPN client started successfully", drv->id);
    return 0;
}

/**
 * OpenVPN netdrv shutdown 函数（关闭网络设备）
 */
static int openvpn_shutdown(luat_netdrv_t *drv, void *userdata) {
    if (drv == NULL || drv->userdata == NULL) {
        return -1;
    }
    
    luat_netdrv_openvpn_ctx_t *ctx = (luat_netdrv_openvpn_ctx_t *)drv->userdata;
    ovpn_client_t *client = ctx->client;
    
    if (client != NULL) {
        ovpn_client_stop(client);
        LLOGI("[%d] OpenVPN client stopped", drv->id);
    }
    
    return 0;
}

/**
 * OpenVPN netdrv ready 函数（检查是否准备就绪）
 */
static int openvpn_ready(luat_netdrv_t *drv, void *userdata) {
    if (drv == NULL || drv->netif == NULL) {
        return 0;
    }
    
    // 检查网络接口是否已启用且有有效 IP
    return netif_is_link_up(drv->netif) && !ip_addr_isany(&drv->netif->ip_addr);
}

/**
 * OpenVPN netdrv DHCP 函数（不适用于 OpenVPN）
 */
static int openvpn_dhcp(luat_netdrv_t *drv, void *userdata, int enable) {
    LLOGW("[%d] OpenVPN does not support DHCP", drv->id);
    return -1;
}

/**
 * OpenVPN netdrv debug 函数（调试输出）
 */
static int openvpn_debug(luat_netdrv_t *drv, void *userdata, int enable) {
    if (drv == NULL || drv->userdata == NULL) {
        return -1;
    }
    
    luat_netdrv_openvpn_ctx_t *ctx = (luat_netdrv_openvpn_ctx_t *)drv->userdata;
    ovpn_client_t *client = ctx->client;
    
    if (client != NULL) {
        ovpn_client_set_debug(client, enable);
        LLOGD("[%d] OpenVPN debug %s", drv->id, enable ? "enabled" : "disabled");
    }
    
    return 0;
}

/**
 * OpenVPN netdrv 初始化设置
 * @param conf netdrv 配置结构体指针
 * @return 成功返回 luat_netdrv_t 指针，失败返回 NULL
 */
luat_netdrv_t* luat_netdrv_openvpn_setup(luat_netdrv_conf_t *conf) {
    if (conf == NULL) {
        LLOGE("Invalid configuration");
        return NULL;
    }
    
    LLOGI("Setting up OpenVPN netdrv for adapter %d", conf->id);
    
    // 分配 netdrv 结构体内存
    luat_netdrv_t *drv = (luat_netdrv_t *)luat_heap_malloc(sizeof(luat_netdrv_t));
    if (drv == NULL) {
        LLOGE("Failed to allocate memory for netdrv");
        return NULL;
    }
    memset(drv, 0, sizeof(luat_netdrv_t));
    
    // 分配 OpenVPN 上下文内存
    luat_netdrv_openvpn_ctx_t *ctx = (luat_netdrv_openvpn_ctx_t *)luat_heap_malloc(sizeof(luat_netdrv_openvpn_ctx_t));
    if (ctx == NULL) {
        LLOGE("Failed to allocate memory for OpenVPN context");
        luat_heap_free(drv);
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_netdrv_openvpn_ctx_t));
    
    // 分配 OpenVPN 客户端内存
    ovpn_client_t *client = (ovpn_client_t *)luat_heap_malloc(sizeof(ovpn_client_t));
    if (client == NULL) {
        LLOGE("Failed to allocate memory for OpenVPN client");
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }
    memset(client, 0, sizeof(ovpn_client_t));
    
    // 初始化 OpenVPN 配置
    ovpn_client_cfg_t ovpn_cfg = {0};
    
    // 从 netdrv 配置提取 OpenVPN 相关参数并拷贝
    // 注意：Lua 脚本调用完成后，参数内存会被释放，所以需要拷贝到 ovpn_client 内部
    
    // 拷贝 CA 证书
    if (conf->ovpn_conf->ovpn_ca_cert != NULL && conf->ovpn_conf->ovpn_ca_cert_len > 0) {
        ovpn_cfg.ca_cert_pem = conf->ovpn_conf->ovpn_ca_cert;
        ovpn_cfg.ca_cert_len = conf->ovpn_conf->ovpn_ca_cert_len;
    }
    
    // 拷贝客户端证书
    if (conf->ovpn_conf->ovpn_client_cert != NULL && conf->ovpn_conf->ovpn_client_cert_len > 0) {
        ovpn_cfg.client_cert_pem = conf->ovpn_conf->ovpn_client_cert;
        ovpn_cfg.client_cert_len = conf->ovpn_conf->ovpn_client_cert_len;
    }
    
    // 拷贝客户端私钥
    if (conf->ovpn_conf->ovpn_client_key != NULL && conf->ovpn_conf->ovpn_client_key_len > 0) {
        ovpn_cfg.client_key_pem = conf->ovpn_conf->ovpn_client_key;
        ovpn_cfg.client_key_len = conf->ovpn_conf->ovpn_client_key_len;
    }
    
    // 拷贝静态密钥（可选）
    if (conf->ovpn_conf->ovpn_static_key != NULL && conf->ovpn_conf->ovpn_static_key_len > 0) {
        ovpn_cfg.static_key = conf->ovpn_conf->ovpn_static_key;
        ovpn_cfg.static_key_len = conf->ovpn_conf->ovpn_static_key_len;
    }
    
    // 设置远程服务器 IP 地址
    if (conf->ovpn_conf->ovpn_remote_ip != NULL) {
        // 从字符串 IP 地址转换为 ip_addr_t
        // 这里需要在 ovpn_client_init 中处理
        ovpn_cfg.remote_host = conf->ovpn_conf->ovpn_remote_ip;
    }
    
    // 设置远程服务器端口
    if (conf->ovpn_conf->ovpn_remote_port > 0) {
        ovpn_cfg.remote_port = conf->ovpn_conf->ovpn_remote_port;
    } else {
        ovpn_cfg.remote_port = 1194;  // OpenVPN 默认端口
    }
    
    // 设置默认适配器索引
    ovpn_cfg.adapter_index = conf->id;
    
    // 设置 MTU（可从 conf 中读取，默认 1500）
    if (conf->mtu > 0) {
        ovpn_cfg.tun_mtu = conf->mtu;
    } else {
        ovpn_cfg.tun_mtu = 1500;
    }
    
    // 设置事件回调
    ovpn_cfg.event_cb = ovpn_netdrv_event_callback;
    ovpn_cfg.user_data = (void *)drv;
    
    // 初始化 OpenVPN 客户端
    int ret = ovpn_client_init(client, &ovpn_cfg);
    if (ret != 0) {
        LLOGE("Failed to initialize OpenVPN client: %d", ret);
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }
    
    // 保存客户端指针到上下文
    ctx->client = client;
    ctx->conf = conf;
    
    // 初始化 netdrv 结构体
    drv->id = conf->id;
    drv->userdata = (void *)ctx;
    drv->netif = &client->netif;
    drv->boot = openvpn_boot;
    // drv->shutdown = openvpn_shutdown;
    drv->ready = openvpn_ready;
    drv->dhcp = openvpn_dhcp;
    drv->debug = openvpn_debug;
    
    // 注册到 netdrv 系统
    int reg_ret = luat_netdrv_register(conf->id, drv);
    if (reg_ret != 0) {
        LLOGE("Failed to register OpenVPN netdrv");
        luat_heap_free(client);
        luat_heap_free(ctx);
        luat_heap_free(drv);
        return NULL;
    }
    
    LLOGI("OpenVPN netdrv setup completed successfully");
    return drv;
}
