#include "luat_base.h"
#include "ff.h"
#include "diskio.h"

extern void luat_spi_set_sdhc_ctrl_default(block_disk_t *disk);

void luat_spi_set_sdhc_ctrl(block_disk_t *disk) {
    luat_spi_set_sdhc_ctrl_default(disk);
}

void luat_sdio_set_sdhc_ctrl(block_disk_t *disk) {
}
