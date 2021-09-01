
#include "luat_base.h"

int luat_sdio_init(int id);
int luat_sdio_sd_read(int id, int rca, char* buff, size_t offset, size_t len);
int luat_sdio_sd_write(int id, int rca, char* buff, size_t offset, size_t len);
int luat_sdio_sd_mount(int id, int rca, int auto_format);
int luat_sdio_sd_format(int id, int rca);
