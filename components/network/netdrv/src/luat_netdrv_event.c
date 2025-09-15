#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mem.h"
#include "luat_mcu.h"

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
    uint8_t adapter_id = ctrl->adapter_index;
    //LLOGD("fire tcp event %08X for adapter %d", event_id, adapter_id);
    if (event_id < EV_NW_RESET || event_id == EV_NW_SOCKET_TX_OK || event_id == EV_NW_SOCKET_RX_NEW) {
        return; // 其他事件无视
    }
    if (s_tcpevt_regs[adapter_id].cb == NULL) {
        //LLOGD("TCP事件网络适配器ID无效 %d", adapter_id);
        return;
    }
    if (ctrl == NULL || adapter_id >= NW_ADAPTER_QTY || adapter_id <= 0) {
        LLOGW("TCP事件网络适配器ID无效 %d", adapter_id);
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