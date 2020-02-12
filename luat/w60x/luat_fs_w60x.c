#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "dfs.h"
#include "dfs_fs.h"

#ifdef BSP_USING_WM_LIBRARIES
#include "drv_flash.h"
#include "lfs.h"

int luat_fs_init() {
    //luat_lfs_init();
    //#ifdef RT_USING_SFUD
    //dfs_mount("W25QXX", "/", "elm", 0, 0);
    //#endif
    int re;
    re = dfs_mount("spi01", "/", "lfs2", 0, 0);
    if (re) {
      rt_kprintf("w600 onchiip filesystem damage!!! do mkfs...\n");
      re = dfs_mkfs("lfs2", "spi01");
      if (re) {
        rt_kprintf("mkfs FAIL!!!! re=%d\n", re);
      }
      else {
        rt_kprintf("mkfs complete\n");
        re = dfs_mount("spi01", "/", "lfs2", 0, 0);
        if (re) {
          rt_kprintf("mount FAIL!!!! re=%d\n", re);
        }
        else {
          rt_kprintf("w600 onchip lfs mount complete\n");
        }
      }
    }
    else {
      rt_kprintf("w600 onchip lfs mount complete\n");
    }
}

rt_err_t wm_spi_bus_attach_device(const char *bus_name, const char *device_name, rt_uint32_t pin);
static int rt_hw_spi_flash_init(void)
{
  wm_spi_bus_attach_device(WM_SPI_BUS_NAME, "spi01", 20);

#ifdef RT_USING_SFUD
  if (RT_NULL == rt_sfud_flash_probe("W25QXX", "spi01"))
  {
    //return -RT_ERROR;
  }
#endif
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
    wm_flash_erase(USER_ADDR_START, USER_ADDR_END - USER_ADDR_START);
    // 重新格式化
    dfs_mkfs("lfs2", "spi01");
    // 挂载
    dfs_mount("spi01", "/", "lfs2", 0, 0);
    t_end = rt_tick_get();
    rt_kprintf("time use %dms\n", t_end - t_start);
  }
  rt_kprintf("reinit DONE!\n");
}
MSH_CMD_EXPORT(reinit, clean all user data);
#endif

