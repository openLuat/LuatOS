#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "dfs.h"
#include "dfs_fs.h"

#define DBG_TAG           "w60x.fs"
#define DBG_LVL           DBG_LOG
#include <rtdbg.h>

#ifdef BSP_USING_WM_LIBRARIES
#include "drv_flash.h"
#include "lfs.h"
rt_err_t wm_spi_bus_attach_device(const char *bus_name, const char *device_name, rt_uint32_t pin);

int luat_fs_init(void) {
    int re;
    re = dfs_mount("onflash", "/", "lfs2", 0, 0);
    if (re) {
      LOG_W("w600 onchiip filesystem damage");
      re = dfs_mkfs("lfs2", "onflash");
      if (re) {
        LOG_E("mkfs FAIL!!!! re=%d", re);
      }
      else {
        LOG_I("mkfs complete");
        re = dfs_mount("onflash", "/", "lfs2", 0, 0);
        if (re) {
          LOG_E("mount FAIL!!!! re=%d", re);
        }
        else {
          LOG_I("w600 onchip lfs mount complete");
        }
      }
    }
    else {
      LOG_I("w600 onchip lfs mount complete");
    }
    return 0;
}


static int rt_hw_spi_flash_init(void)
{
  wm_spi_bus_attach_device(WM_SPI_BUS_NAME, "onflash", 20); -- 占用PB_15了,怎么解决呢
  return RT_EOK;
}
INIT_COMPONENT_EXPORT(rt_hw_spi_flash_init);

#include "wm_flash_map.h"
static uint8_t first_reinit = 1;
static void reinit(void* params) {
  rt_tick_t t_start;
  rt_tick_t t_end;
  if (first_reinit) {
    first_reinit = 0;
    t_start = rt_tick_get();
    // 卸载之
    dfs_unmount("/");
    // 抹除整个分区
    //wm_flash_erase(USER_ADDR_START, USER_ADDR_END - USER_ADDR_START);
    // 重新格式化
    dfs_mkfs("lfs2", "onflash");
    // 挂载
    dfs_mount("onflash", "/", "lfs2", 0, 0);
    t_end = rt_tick_get();
    LOG_I("time use %dms", t_end - t_start);
  }
  LOG_I("reinit DONE!");
}
MSH_CMD_EXPORT(reinit, clean all user data);
#endif
