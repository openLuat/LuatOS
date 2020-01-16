#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "drv_flash.h"
#include "lfs.h"

#ifdef BSP_USING_WM_LIBRARIES

static lfs_t *lfs;

static int _wm_flash_read(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size);
static int _wm_flash_prog(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size);
static int _wm_flash_erase(const struct lfs_config *c, lfs_block_t block);
static int _wm_flash_sync(const struct lfs_config *c);

const struct lfs_config cfg = {
    // block device operations
    .read  = _wm_flash_read,
    .prog  = _wm_flash_prog,
    .erase = _wm_flash_erase,
    .sync  = _wm_flash_sync,

    // block device configuration
    .read_size = 16,
    .prog_size = 16,
    .block_size = 4096,
    .block_count = 12,
    .cache_size = 16,
    .lookahead_size = 16,
    .block_cycles = 500,
};

int luat_fs_init() {
    luat_lfs_init();
    #ifdef RT_USING_SFUD
    dfs_mount("W25QXX", "/", "elm", 0, 0);
    #endif
}

int luat_lfs_init() {
    wm_flash_init();
    lfs = luat_heap_malloc(sizeof(lfs_t));
    // mount the filesystem
    int err = lfs_mount(&lfs, &cfg);

    // reformat if we can't mount the filesystem
    // this should only happen on the first boot
    if (err) {
        rt_kprintf("lfs_format wm flash !!!\n");
        lfs_format(&lfs, &cfg);
        lfs_mount(&lfs, &cfg);
    }
    else {
        rt_kprintf("lfs_mount complete !!!\n");
    }



    return 0;
}

static int _wm_flash_read(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    int re = wm_flash_read(0x00F0000 + block*c->block_size + off, buffer, size);
    return re == size ? 0 : 1;
}
static int _wm_flash_prog(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    return wm_flash_write(0x00F0000 + block*c->block_size + off, buffer, size) == size ? 0 : 1;
}
static int _wm_flash_erase(const struct lfs_config *c, lfs_block_t block) {
    return wm_flash_erase(0x00F0000 + block*c->block_size, c->block_size) == c->block_size ? 0 : 1;
}
static int _wm_flash_sync(const struct lfs_config *c) {
    return 0;
}

#ifdef RT_USING_SFUD
rt_err_t wm_spi_bus_attach_device(const char *bus_name, const char *device_name, rt_uint32_t pin);
static int rt_hw_spi_flash_init(void)
{
  wm_spi_bus_attach_device(WM_SPI_BUS_NAME, "spi01", 20);

  if (RT_NULL == rt_sfud_flash_probe("W25QXX", "spi01"))
  {
    //return -RT_ERROR;
  }
  
  return RT_EOK;
}
INIT_COMPONENT_EXPORT(rt_hw_spi_flash_init);
#endif

#endif

