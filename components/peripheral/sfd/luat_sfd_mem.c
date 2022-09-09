
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_gpio.h"

#include "luat_sfd.h"

#define LUAT_LOG_TAG "sfd"
#include "luat_log.h"

//--------------------------------------------------------------------
// SFD at memory ,  for test
#include "luat_zbuff.h"

static int sfd_mem_init (void* userdata);
static int sfd_mem_status (void* userdata);
static int sfd_mem_read (void* userdata, char* buff, size_t offset, size_t len);
static int sfd_mem_write (void* userdata, const char* buff, size_t offset, size_t len);
static int sfd_mem_erase (void* userdata, size_t offset, size_t len);
static int sfd_mem_ioctl (void* userdata, size_t cmd, void* buff);

const sdf_opts_t sfd_mem_opts = {
    .initialize = sfd_mem_init,
    .status = sfd_mem_status,
    .read = sfd_mem_read,
    .write = sfd_mem_write,
    .erase = sfd_mem_erase,
    .ioctl = sfd_mem_ioctl,
};

static int sfd_mem_init (void* userdata) {
    if (userdata == NULL) {
        LLOGE("userdata for sfd_mem must NOT NULL");
        return -1;
    }
    sfd_drv_t *drv = (sfd_drv_t*)userdata;
    luat_zbuff_t* zbuff = drv->cfg.zbuff;
    if (zbuff->len < 16*1024) {
        LLOGE("zbuff for sfd_mem is too small");
        return -1;
    }
    return 0;
}
static int sfd_mem_status (void* userdata) {
    if (userdata == NULL) {
        LLOGE("userdata for sfd_mem must NOT NULL");
        return -1;
    }
    return 0;
}
static int sfd_mem_read (void* userdata, char* buff, size_t offset, size_t len) {
    if (userdata == NULL) {
        LLOGE("userdata for sfd_mem must NOT NULL");
        return -1;
    }
    sfd_drv_t *drv = (sfd_drv_t*)userdata;
    luat_zbuff_t* zbuff = drv->cfg.zbuff;
    if (offset > zbuff->len) {
        // LLOGD("over read");
        return 0;
    }
    if (offset+len > zbuff->len) {
        len = zbuff->len  - offset;
    }
    if (len > 0) {
        memcpy(buff, zbuff->addr + offset, len);
    }
    return len;
}
static int sfd_mem_write (void* userdata, const char* buff, size_t offset, size_t len) {
    if (userdata == NULL) {
        LLOGE("userdata for sfd_mem must NOT NULL");
        return -1;
    }
    sfd_drv_t *drv = (sfd_drv_t*)userdata;
    luat_zbuff_t* zbuff = drv->cfg.zbuff;
    if (offset > zbuff->len) {
        // LLOGD("over read");
        return 0;
    }
    if (offset+len > zbuff->len) {
        len = zbuff->len  - offset;
    }
    if (len > 0) {
        memcpy(zbuff->addr + offset, buff, len);
    }
    return len;
}
static int sfd_mem_erase (void* userdata, size_t offset, size_t len) {
    if (userdata == NULL) {
        LLOGE("userdata for sfd_mem must NOT NULL");
        return -1;
    }
    sfd_drv_t *drv = (sfd_drv_t*)userdata;
    luat_zbuff_t* zbuff = drv->cfg.zbuff;
    if (offset > zbuff->len) {
        // LLOGD("over read");
        return 0;
    }
    if (offset+len > zbuff->len) {
        len = zbuff->len  - offset;
    }
    if (len > 0) {
        memset(zbuff->addr + offset, 0, len);
    }
    return 0;
}
static int sfd_mem_ioctl (void* userdata, size_t cmd, void* buff) {
    return 0;
}
