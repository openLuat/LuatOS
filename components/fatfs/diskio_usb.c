
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "udisk"
#include "luat_log.h"

#include "ff.h"
#include "diskio.h"

extern BYTE FATFS_DEBUG; // debug log, 0 -- disable , 1 -- enable

LUAT_WEAK DRESULT diskio_open_usb(BYTE usb_app_id, void* userdata) {
    return RES_ERROR;
}

