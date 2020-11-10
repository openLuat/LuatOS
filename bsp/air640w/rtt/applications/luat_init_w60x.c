#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef RT_USING_WIFI
#include "wlan_mgnt.h"
#endif

#define DBG_TAG           "w60x.init"
#define DBG_LVL           DBG_LOG
#include <rtdbg.h>

#ifdef BSP_USING_WM_LIBRARIES
static rt_err_t w600_bt(void *context) {
  rt_kprintf("\r\nFUCK!!\r\n");
  return 0;
} 
static int rtt_w60x_init() {
  #ifdef RT_USING_WIFI
  rt_wlan_set_mode("wlan0", RT_WLAN_STATION);
  #endif
  rt_hw_exception_install(w600_bt);
  return RT_EOK;
}
INIT_COMPONENT_EXPORT(rtt_w60x_init);
#endif
