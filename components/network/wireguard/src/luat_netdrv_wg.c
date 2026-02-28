// WireGuard network driver, 集成到netdrv框架下

// 导入必要的头文件
#include "luat_base.h"
#include "luat_network_adapter.h"
#include "wireguard/wireguardif.h"
#include "wireguard/crypto.h"
#include "wireguard/wireguard.h"
#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "luat_mem.h"
#include "lwip/ip.h"
#include "lwip/ip_addr.h"

#include "net_lwip2.h"

#define LUAT_LOG_TAG "netdrv.wg"
#include "luat_log.h"

typedef struct wg_ctx
{
    struct netif *netif;
    // struct wireguardif_init_data wg;
    ip_addr_t ipaddr;
    ip_addr_t netmask;
    ip_addr_t gateway;
    struct wireguard_device * dev;
}wg_ctx_t;


static int netdrv_wg_boot(struct luat_netdrv* drv, void* userdata) {
    // 无需特殊操作
    return 0;
}

static void exec_netif_add(wg_ctx_t* ctx) {

    // 初始化WireGuard设备

    netif_add(ctx->netif, ip_2_ip4(&ctx->ipaddr), ip_2_ip4(&ctx->netmask), ip_2_ip4(&ctx->gateway), ctx->dev, wireguardif_init, ip_input);
    luat_heap_free(ctx);
}

luat_netdrv_t* luat_netdrv_wg_setup(luat_netdrv_conf_t *cfg)
{
    LLOGD("Starting WireGuard netdrv setup for cfg id=%d", cfg->id);

    if (cfg->wg_conf == NULL) {
        LLOGE("WireGuard config is NULL");
        return NULL;
    }

    uint8_t wireguard_peer_index = 0;
    wg_ctx_t* ctx = luat_heap_malloc(sizeof(wg_ctx_t));
    struct wireguardif_peer *peer = luat_heap_malloc(sizeof(struct wireguardif_peer));
    struct wireguard_device *device = luat_heap_malloc(sizeof(struct wireguard_device));
    struct netif *wg_netif_struct = luat_heap_malloc(sizeof(struct netif));
    // struct netif *wg_netif = NULL;
    luat_netdrv_t *netdrv = luat_heap_malloc(sizeof(luat_netdrv_t));
    if (ctx == NULL || netdrv == NULL || wg_netif_struct == NULL || peer == NULL || device == NULL) {
        LLOGE("Failed to allocate memory for WireGuard netdrv %p %p %p %p", netdrv, wg_netif_struct, peer, device);
        if (netdrv)
            luat_heap_free(netdrv);
        if (wg_netif_struct)
            luat_heap_free(wg_netif_struct);
        if (peer)
            luat_heap_free(peer);
        if (device)
            luat_heap_free(device);
        if (ctx)
            luat_heap_free(ctx);
        return NULL;
    }
    
	// We need to initialise the wireguard module
	wireguard_init();

    memset(wg_netif_struct, 0, sizeof(struct netif));
    memset(netdrv, 0, sizeof(luat_netdrv_t));
    memset(peer, 0, sizeof(struct wireguardif_peer));
    memset(device, 0, sizeof(struct wireguard_device));

    
    // Setup the WireGuard device structure
    device->adapter_index = cfg->id; // LuatOS的网卡id
    device->gw_adapter_index = network_register_get_default(); // 出口网卡id

    LLOGD("Setting up WireGuard netdrv id=%d, gw=%d", device->adapter_index, device->gw_adapter_index);

    uint8_t private_key[WIREGUARD_PRIVATE_KEY_LEN + 1] = {0};
    uint32_t private_key_len = sizeof(private_key);

    if (cfg->wg_conf->wg_private_key == NULL) {
        LLOGE("WireGuard private key is NULL");
        goto fail;
    }
    wireguard_base64_decode(cfg->wg_conf->wg_private_key, private_key, &private_key_len);

    wireguard_device_init(device, private_key);

    ctx->netif = wg_netif_struct;
    ctx->dev = device;
    
    if (cfg->ip_conf) {
        ip_addr_copy_from_ip4(ctx->ipaddr, cfg->ip_conf->ip);
        ip_addr_copy_from_ip4(ctx->netmask, cfg->ip_conf->netmask);
        ip_addr_copy_from_ip4(ctx->gateway, cfg->ip_conf->gw);
    } else {
        // Fallback or error? defaulting to 0.0.0.0 if not provided which is handled by memset
        // But let's log a warning
        LLOGW("No IP config provided for WireGuard interface");
    }

    // Register the new WireGuard network interface with lwIP
    LLOGD("Adding WireGuard netif %p %p", wg_netif_struct, ctx->dev);
    tcpip_callback_with_block((tcpip_callback_fn)exec_netif_add, ctx, 0);

    // Initialise the first WireGuard peer structure
    LLOGD("Adding WireGuard peer - master");
    wireguardif_peer_init(peer);
    peer->public_key = cfg->wg_conf->wg_endpoint_key;

    // Add buffer for preshared key
    uint8_t preshared_key_buf[WIREGUARD_SESSION_KEY_LEN + 1];
    memset(preshared_key_buf, 0, sizeof(preshared_key_buf));
    
    if (cfg->wg_conf->wg_preshared_key) {
        size_t preshared_key_len = sizeof(preshared_key_buf);
        wireguard_base64_decode(cfg->wg_conf->wg_preshared_key, preshared_key_buf, &preshared_key_len);
        peer->preshared_key = preshared_key_buf;
    } else {
        peer->preshared_key = NULL;
    }

    peer->keep_alive = cfg->wg_conf->wg_keepalive;

    // If we know the endpoint's address can add here
    if (cfg->wg_conf->wg_endpoint_ip) {
        ipaddr_aton(cfg->wg_conf->wg_endpoint_ip, &peer->endpoint_ip);
    }
    if (cfg->wg_conf->wg_endpoint_port) {
        peer->endpoint_port = cfg->wg_conf->wg_endpoint_port;
    } else {
        peer->endpoint_port = 51820; // Default WG port
    }

    // Register the new WireGuard peer with the netwok interface
    LLOGD("Registering WireGuard peer - wireguardif_add_peer");
    wireguardif_add_peer(wg_netif_struct, peer, &wireguard_peer_index);

    // Free peer structure as it is copied by wireguardif_add_peer
    luat_heap_free(peer);

    wireguardif_connect(wg_netif_struct, wireguard_peer_index);

    netdrv->id = cfg->id;
    netdrv->netif = wg_netif_struct;
    netdrv->dataout = NULL; // 目前不支持直接发送数据
    netdrv->boot = netdrv_wg_boot;
    netdrv->userdata = device;
    netdrv->dhcp = NULL; // 不支持DHCP

    LLOGD("WireGuard netdrv setup complete %d %d %p %p", netdrv->id, cfg->id, netdrv, wg_netif_struct);
    net_lwip2_set_netif(netdrv->id, netdrv->netif);
    net_lwip2_register_adapter(netdrv->id);
    return netdrv;

fail:
    if (netdrv)
        luat_heap_free(netdrv);
    if (wg_netif_struct)
        luat_heap_free(wg_netif_struct);
    if (peer)
        luat_heap_free(peer);
    if (device)
        luat_heap_free(device);
    if (ctx)
        luat_heap_free(ctx);
    return NULL;
}

err_t wireguardif_peer_output(struct netif *netif, struct pbuf *q, struct wireguard_peer *peer) {
	struct wireguard_device *device = netif->state;
	// Send to last know port, not the connect port
	//TODO: Support DSCP and ECN - lwip requires this set on PCB globally, not per packet
	// return udp_sendto(device->udp_pcb, q, &peer->ip, peer->port);
    luat_netdrv_t* drv = luat_netdrv_get(device->gw_adapter_index);
    if (drv == NULL) {
        LLOGE("gw(%d) netdrv is NULL, can't send pbuf %d", device->gw_adapter_index, q->tot_len);
        return -1;
    }
	int ret = udp_sendto_if(device->udp_pcb, q, &peer->ip, peer->port, drv->netif);
    if (ret) {
        LLOGE("udp_sendto_if error %d", ret);
    }
	return ret;
}

err_t wireguardif_device_output(struct wireguard_device *device, struct pbuf *q, const ip4_addr_t *ipaddr, u16_t port) {
	// return udp_sendto(device->udp_pcb, q, ipaddr, port);
	// LLOGD("device output to %s:%d\r\n", ipaddr_ntoa(ipaddr), port);

    luat_netdrv_t* drv = luat_netdrv_get(device->gw_adapter_index);
    if (drv == NULL) {
        LLOGE("netdrv is NULL");
        return -1;
    }
	int ret = udp_sendto_if(device->udp_pcb, q, ipaddr, port, drv->netif);
    if (ret) {
        LLOGE("udp_sendto_if error %d", ret);
    }
	return ret;
}
