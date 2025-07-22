#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#include "luat_netdrv_event.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__ 
#endif

netdrv_tcpevt_reg_t g_netdrv_tcpevt_regs[NW_ADAPTER_QTY] = {0};

void luat_netdrv_register_tcp_event_cb(uint8_t id, uint8_t flags, luat_netdrv_tcp_evt_cb cb, void* userdata) {
    if (id >= NW_ADAPTER_QTY) {
        LLOGE("无效的TCP事件注册ID %d", id);
        return;
    }
    if (flags == 0) {
        g_netdrv_tcpevt_regs[id].cb = NULL;
        g_netdrv_tcpevt_regs[id].userdata = NULL;
        return;
    }
    g_netdrv_tcpevt_regs[id].flags = flags;
    g_netdrv_tcpevt_regs[id].cb = cb;
    g_netdrv_tcpevt_regs[id].userdata = userdata;
    LLOGD("注册TCP事件回调 %d, flags=0x%02X", id, flags);
}


__USER_FUNC_IN_RAM__ void luat_netdrv_fire_tcp_event(netdrv_tcp_evt_t* evt) {
    if (evt == NULL || evt->id >= NW_ADAPTER_QTY) {
        LLOGE("TCP事件网络适配器ID无效 %d", evt ? evt->id : -1);
        return;
    }
    if ((g_netdrv_tcpevt_regs[evt->id].flags & evt->flags) && g_netdrv_tcpevt_regs[evt->id].cb) {
        g_netdrv_tcpevt_regs[evt->id].cb(evt, g_netdrv_tcpevt_regs[evt->id].userdata);
    }
}
