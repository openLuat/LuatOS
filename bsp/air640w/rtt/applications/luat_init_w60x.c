#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef RT_USING_WIFI
#include "wlan_mgnt.h"

#define DBG_TAG           "w60x.init"
#define DBG_LVL           DBG_LOG
#include <rtdbg.h>

#ifdef BSP_USING_WM_LIBRARIES
static int rtt_w60x_init() {
  rt_wlan_set_mode("wlan0", RT_WLAN_STATION);
  return RT_EOK;
}
INIT_COMPONENT_EXPORT(rtt_w60x_init);
#endif
#endif
