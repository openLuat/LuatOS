#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_ulwip.h"

#include "lwip/ip_addr.h"
#include "lwip/netif.h"

#include "luat_netdrv_event.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

static netdrv_tcpevt_reg_t s_tcpevt_regs[NW_ADAPTER_QTY] = {0};

void luat_netdrv_register_socket_event_cb(uint8_t id, uint32_t evt_flags, luat_netdrv_tcp_evt_cb cb, void* userdata) {
    if (id >= NW_ADAPTER_QTY) {
        LLOGE("无效的TCP事件注册ID %d", id);
        return;
    }
    if (evt_flags == 0) {
        s_tcpevt_regs[id].cb = NULL;
        s_tcpevt_regs[id].userdata = NULL;
        return;
    }
    s_tcpevt_regs[id].flags = evt_flags;
    s_tcpevt_regs[id].cb = cb;
    s_tcpevt_regs[id].userdata = userdata;
    // LLOGD("socket event cb adapter %d, flags=0x%02X userdata=%p", id, evt_flags, userdata);
}

__NETDRV_CODE_IN_RAM__ void luat_netdrv_fire_socket_event_netctrl(uint32_t event_id, network_ctrl_t* ctrl, uint8_t proto) {
    if (event_id < EV_NW_RESET || event_id == EV_NW_SOCKET_TX_OK || event_id == EV_NW_SOCKET_RX_NEW || event_id == EV_NW_STATE) {
        return; // 其他事件无视
    }
    if (ctrl == NULL) {
        return;
    }
    uint8_t adapter_id = ctrl->adapter_index;
    //LLOGD("fire tcp event %08X for adapter %d", event_id, adapter_id);
    if (adapter_id >= NW_ADAPTER_QTY || adapter_id <= 0) {
        LLOGW("ctrl %p adapter %d is invalid, but socket event id is %08x", ctrl, adapter_id, event_id);
        return;
    }
    if (s_tcpevt_regs[adapter_id].cb == NULL) {
        //LLOGD("TCP事件网络适配器ID无效 %d", adapter_id);
        return;
    }
    event_id -= EV_NW_RESET;
    if ((s_tcpevt_regs[adapter_id].flags & event_id) == 0) {
        //LLOGD("TCP事件网络适配器ID无效 %d", adapter_id);
        return;
    }
    netdrv_tcp_evt_t evt = {0};
    evt.id = adapter_id;
    evt.flags = event_id;
    if (proto == 0 && event_id != (0x81)) {
        evt.proto = ctrl->is_tcp ? 1 : 2;
    }
    else {
        evt.proto = proto;
    }
    if (ctrl->domain_name && ctrl->domain_name_len > 0) {
        strncpy(evt.domain_name, ctrl->domain_name, sizeof(evt.domain_name) - 1);
        evt.domain_name[sizeof(evt.domain_name) - 1] = 0;
    }
    // if (ctrl->online_ip) {
    //     evt.remote_ip = *ctrl->online_ip;
    // }
    // else {
    evt.remote_ip = ctrl->remote_ip;
    evt.online_ip = ctrl->online_ip;
    // }
    evt.local_port = ctrl->local_port;
    evt.remote_port = ctrl->remote_port;
    evt.userdata = ctrl->user_data;
    s_tcpevt_regs[adapter_id].cb(&evt, s_tcpevt_regs[adapter_id].userdata);
}

// IP 事件, 分成 IP_READY 和 IP_LOSE
#ifdef __LUATOS__
static int netif_ip_event_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    char buff[32] = {0};
    luat_netdrv_t* netdrv = luat_netdrv_get(msg->arg1);
    if (netdrv == NULL) {
        return 0;
    }
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        if (msg->arg2 == 0) {
            LLOGD("IP_LOSE %d", netdrv->id);
            lua_pushstring(L, "IP_LOSE");
            lua_pushinteger(L, netdrv->id);
            lua_call(L, 2, 0);
        }
        else {
            ipaddr_ntoa_r(&netdrv->netif->ip_addr, buff,  32);
            LLOGD("IP_READY %d %s", netdrv->id, buff);
            lua_pushstring(L, "IP_READY");
            lua_pushstring(L, buff);
            lua_pushinteger(L, netdrv->id);
            lua_call(L, 3, 0);
        }
    }
    return 0;
}

void luat_netdrv_send_ip_event(luat_netdrv_t* drv, uint8_t ready) {
    rtos_msg_t msg = {0};
    if (drv == NULL || drv->netif == NULL) {
        return;
    }
    msg.arg1 = drv->id;
    msg.arg2 = ready;
    msg.ptr = NULL;
    msg.handler = netif_ip_event_cb;
    luat_msgbus_put(&msg, 0);
}

#else
// TODO 改成weak实现?
void luat_netdrv_send_ip_event(luat_netdrv_t* drv, uint8_t updown) {
    // nop
}
#endif

typedef struct tmpptr {
    luat_netdrv_t* drv;
    uint8_t updown;
}tmpptr_t;

static void delay_dhcp_start(void* args) {
    ulwip_ctx_t *ctx = (ulwip_ctx_t *)args;
    if (ctx && ctx->dhcp_enable) {
        ulwip_dhcp_client_start(ctx);
    }
}

static void link_updown(void* args) {
    tmpptr_t* ptr = (tmpptr_t*)args;
    luat_netdrv_t* drv = ptr->drv;
    uint8_t updown = ptr->updown;
    luat_heap_free(ptr);
    ptr = NULL;
    void* userdata = NULL;
    if (drv == NULL || drv->netif == NULL) {
        return;
    }
    struct netif *netif = drv->netif;
    ulwip_ctx_t *ulwip = drv->ulwip;
    // LLOGI("netif %d link prev %d set %s %p", drv->id, netif_is_link_up(netif), updown ? "UP" : "DOWN", netif);
    if (updown && netif_is_link_up(netif) == 0) {
        LLOGD("网卡(%d)设置为UP", drv->id);
        netif_set_link_up(netif);
        net_lwip2_set_link_state(drv->id, 1);
        if (ulwip) {
            if (ulwip->netif == NULL) {
                ulwip->netif = netif;
            }
            if (ulwip->dhcp_enable) {
                ulwip_dhcp_client_stop(ulwip);
                // 延时50ms, 避免netif_set_up和dhcp冲突
                sys_timeout(50, delay_dhcp_start, ulwip);
            }
            else if (!ip_addr_isany(&netif->ip_addr)) {
                // 静态IP, 那就发布IP_READY事件
                luat_netdrv_send_ip_event(drv, 1);
            }
        }
        else {
            if (!ip_addr_isany(&netif->ip_addr)) {
                // 静态IP, 那就发布IP_READY事件
                luat_netdrv_send_ip_event(drv, 1);
            }
        }
        return;
    }
    if (updown == 0 && netif_is_link_up(netif)) {
        LLOGD("网卡(%d)设置为DOWN", drv->id);
        luat_netdrv_netif_set_link_down(netif);
        if (ulwip && ulwip->dhcp_enable) {
            ulwip_dhcp_client_stop(ulwip);
        }
        net_lwip2_set_link_state(drv->id, 0);
        luat_netdrv_send_ip_event(drv, 0);
    }

    #if 0
    network_adapter_info* info = network_adapter_fetch(drv->id, &userdata);
    if (info == NULL || info->check_ready == NULL) {
        // LLOGI("网络适配器(%d)不存在, 或者没有check_ready函数", adapter_index);
        return;
    }
    int ready = info->check_ready(userdata);
    net_lwip2_set_link_state(drv->id, ready);
    luat_netdrv_send_ip_event(drv, ready);
    #endif
}

void luat_netdrv_set_link_updown(luat_netdrv_t* drv, uint8_t updown) {
    if (drv == NULL || drv->netif == NULL) {
        return;
    }
    // 动态分配内存，避免局部变量在回调执行前被销毁
    tmpptr_t *ptr = (tmpptr_t*)luat_heap_malloc(sizeof(tmpptr_t));
    if (ptr == NULL) {
        LLOGE("luat_netdrv_set_link_updown: malloc failed!");
        return;
    }
    ptr->drv = drv;
    ptr->updown = updown;

    // 使用 tcpip_callback 需要在回调中释放内存
    #if NO_SYS
    link_updown(ptr);
    luat_heap_free(ptr);
    #else
    // 在 link_updown 中释放内存
    tcpip_callback(link_updown, ptr);
    #endif
}
