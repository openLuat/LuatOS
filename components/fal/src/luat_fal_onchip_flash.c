#include "luat_base.h"
#include "luat_sfd.h"

#ifndef LUAT_LOG_TAG
#define LUAT_LOG_TAG "fal"
#include "luat_log.h"
#endif

#include "fal.h"

static sfd_onchip_t onchip;

int sfd_onchip_init (void* userdata);
int sfd_onchip_status (void* userdata);
int sfd_onchip_read (void* userdata, char* buff, size_t offset, size_t len);
int sfd_onchip_write (void* userdata, const char* buff, size_t offset, size_t len);
int sfd_onchip_erase (void* userdata, size_t offset, size_t len);
int sfd_onchip_ioctl (void* userdata, size_t cmd, void* buff);

static int (onchip_flash_init)(void) {
    return sfd_onchip_init(&onchip);
}
static int (onchip_flash_read)(long offset, uint8_t *buf, size_t size) {
    //LLOGD("onchip_flash_read %08X %04X", offset, size);
    return sfd_onchip_read(&onchip, (char*)buf, offset, size);
}
static int (onchip_flash_write)(long offset, const uint8_t *buf, size_t size) {
    //LLOGD("onchip_flash_write %08X %04X", offset, size);
    return sfd_onchip_write(&onchip, (char*)buf, offset, size);
}
static int (onchip_flash_erase)(long offset, size_t size) {
    //LLOGD("onchip_flash_write %08X %04X", offset, size);
    return sfd_onchip_erase(&onchip, offset, size);
}

const struct fal_flash_dev onchip_flash = {
    .name = "onchip_flash",
    .len = 64*1024, // TODO 改成选配置
    .blk_size = 4096,
    .addr = 0,
    .write_gran = 32,
    .ops = {onchip_flash_init, onchip_flash_read, onchip_flash_write, onchip_flash_erase}
};


