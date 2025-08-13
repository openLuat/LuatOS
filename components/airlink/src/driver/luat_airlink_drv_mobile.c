#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_airlink.h"

#if defined(LUAT_USE_DRV_MOBILE)
#include "luat_mobile.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 
luat_airlink_mobile_evt_cb g_airlink_mobile_evt_cb;

extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

int luat_airlink_mobile_event_callback(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr) {
	if (g_airlink_mobile_evt_cb) {
		g_airlink_mobile_evt_cb(event, index, status, ptr);
	}
    return 0;
}
#endif
