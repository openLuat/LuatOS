#ifndef LUAT_AIRLINK_DRV_MOBILE_H
#define LUAT_AIRLINK_DRV_MOBILE_H

#include "luat_airlink.h"

// mobile 操作
#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
#include "luat_mobile.h"
typedef void (*luat_airlink_mobile_evt_cb)(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr);
int luat_airlink_mobile_event_callback(LUAT_MOBILE_EVENT_E event, uint8_t index, uint8_t status, void* ptr);
#endif

#endif
