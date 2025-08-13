#ifndef LUAT_AIRLINK_DRV_MOBILE_H
#define LUAT_AIRLINK_DRV_MOBILE_H


#ifndef LUAT_AIRLINK_H
#error "include luat_airlink.h first"
#endif

// mobile 操作
#include "luat_mobile.h"


int luat_airlink_drv_mobile_event_callback(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr);

#endif
