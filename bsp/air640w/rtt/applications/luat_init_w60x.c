#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"
#include "luat_fs.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef RT_USING_WIFI
#include "wlan_mgnt.h"
#endif

#define DBG_TAG           "w60x.init"
#define DBG_LVL           DBG_LOG
#include <rtdbg.h>

#ifdef BSP_USING_WM_LIBRARIES

static int w60x_read_cfg(void *buff, int len) {
  int fd = luat_fs_fopen("/wlan.cfg", "rb");
  if (fd) {
    luat_fs_fread(buff, 1, len, fd);
    luat_fs_fclose(fd);
    return len;
  }
  return 0;
};
static int w60x_get_len(void) {
  return luat_fs_fsize("/wlan.cfg");
};
static int w60x_write_cfg(void *buff, int len) {
  int fd = luat_fs_fopen("/wlan.cfg", "w");
  if (fd) {
    luat_fs_fwrite(buff, 1, len, fd);
    luat_fs_fclose(fd);
    return len;
  }
  return 0;
};
#ifdef RT_USING_WIFI
static struct rt_wlan_cfg_ops cfg_ops = {
  w60x_read_cfg,
  w60x_get_len,
  w60x_write_cfg
};
#endif

static rt_err_t w600_bt(void *context) {
  rt_kprintf("\r\nwatchdog irq!!!!\r\n");
  extern void tls_sys_reset(void);
  tls_sys_reset();
  return 0;
} 
static int rtt_w60x_init() {
  #ifdef RT_USING_WIFI
  rt_wlan_set_mode("wlan0", RT_WLAN_STATION);
  rt_wlan_cfg_set_ops(&cfg_ops);
  rt_wlan_cfg_cache_refresh();
  #endif
  rt_hw_exception_install(w600_bt);
  return RT_EOK;
}
INIT_APP_EXPORT(rtt_w60x_init);
#endif
