#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_airlink.h"

#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
#include "luat_mobile.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 
luat_airlink_mobile_evt_cb g_airlink_mobile_evt_cb;

int luat_airlink_mobile_event_callback(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr) {
    LLOGD("airlink mobile event %d, index %d, status %d", event, index, status);
    // 当 mobile netif 状态变化时，控制 GP_GW 的 netif link up/down
    if (event == LUAT_MOBILE_EVENT_NETIF) {
        luat_netdrv_t* gw = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_GP_GW);
        if (gw && gw->netif) {
            if (status == LUAT_MOBILE_NETIF_LINK_ON) {
                LLOGD("mobile NETIF LINK ON -> set GW netif up");
                luat_netdrv_set_link_updown(gw, 1);
            }
            else if (status == LUAT_MOBILE_NETIF_LINK_OFF) {
                LLOGD("mobile NETIF LINK OFF -> set GW netif down");
                luat_netdrv_set_link_updown(gw, 0);
            }
        }
    }

    if (g_airlink_mobile_evt_cb) {
		g_airlink_mobile_evt_cb(event, index, status, ptr);
	}
    return 0;
}
#endif
