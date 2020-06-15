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
#define DBG_LVL           DBG_DEBUG
#include <rtdbg.h>

#ifdef SOC_VEXPRESS_A9

int luat_fs_init(void) {
    
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

// #include "wm_flash_map.h"
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
    dfs_mkfs("lfs2", "spi01");
    // 挂载
    dfs_mount("spi01", "/", "lfs2", 0, 0);
    t_end = rt_tick_get();
    LOG_I("time use %dms", t_end - t_start);
  }
  LOG_I("reinit DONE!");
}
MSH_CMD_EXPORT(reinit, clean all user data);
#endif

