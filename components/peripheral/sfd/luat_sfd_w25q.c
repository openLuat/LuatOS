
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_gpio.h"

#include "luat_sfd.h"

#define LUAT_LOG_TAG "sfd"
#include "luat_log.h"

#define CS_H(pin) luat_gpio_set(pin, 1)
#define CS_L(pin) luat_gpio_set(pin, 0)

// 针对drv的实现
static int sfd_w25q_init (void* userdata);
static int sfd_w25q_status (void* userdata);
static int sfd_w25q_read (void* userdata, char* buff, size_t offset, size_t len);
static int sfd_w25q_write (void* userdata, const char* buff, size_t offset, size_t len);
static int sfd_w25q_erase (void* userdata, size_t offset, size_t len);
static int sfd_w25q_ioctl (void* userdata, size_t cmd, void* buff);

const sdf_opts_t sfd_w25q_opts = {
    .initialize = sfd_w25q_init,
    .status = sfd_w25q_status,
    .read = sfd_w25q_read,
    .write = sfd_w25q_write,
    .erase = sfd_w25q_erase,
    .ioctl = sfd_w25q_ioctl,
};

static int sfd_w25q_init (void* userdata) {
    sfd_drv_t *drv = (sfd_drv_t *)userdata;
    uint8_t cmd = 0x9F;
    // 发送CMD 9F, 读取容量信息
    luat_gpio_set(drv->cfg.spi.cs, 0);
    luat_spi_send(drv->cfg.spi.id, (const char*)&cmd, 1);
    char buff[3] = {0};
    luat_spi_recv(drv->cfg.spi.id, buff, 3);
    luat_gpio_set(drv->cfg.spi.cs, 1);
    if (buff[0] != 0xEF) {
        LLOGW("can't read spi flash: cmd 9F");
        return -1;
    }
    LLOGD("spi flash %02X %02X %02X", buff[0], buff[1], buff[2]);
    if (buff[1] == 0x40) {
        switch(buff[2]) {
            case 0x13:
                drv->sector_count = 8*256;// drv80, 8M
                break;
            case 0x14:
                drv->sector_count = 16*256;// drv16, 16M
                break;
            case 0x15:
                drv->sector_count = 32*256;// drv32, 32M
                break;
            case 0x16:
                drv->sector_count = 64*256;// drv64, 64M
                break;
            case 0x17:
                drv->sector_count = 128*256;// drv128, 128M
                break;
            case 0x18:
                drv->sector_count = 256*256;// drv256, 256M
                break;
            case 0x19:
                drv->sector_count = 512*256;// drv512, 512M
                break;
            default :
                drv->sector_count = 16*256;// 默认当16M吧
                break;
        }
    }
    else {
        drv->sector_count = 16*256;// 默认当16M吧
    }
    //drv->flash_id[0] = buff[1];
    //drv->flash_id[1] = buff[2];

    // 读设备唯一id
    luat_gpio_set(drv->cfg.spi.cs, 0);
    char chip_id_cmd[] = {0x4B, 0x00, 0x00, 0x00, 0x00};
    luat_spi_send(drv->cfg.spi.id, chip_id_cmd, sizeof(chip_id_cmd));
    luat_spi_recv(drv->cfg.spi.id, drv->chip_id, 8);
    luat_gpio_set(drv->cfg.spi.cs, 1);

    return 0;
}

static int sfd_w25q_status (void* userdata) {
    sfd_drv_t *drv = (sfd_drv_t *)userdata;
    return drv->sector_count == 0 ? 0 : 1; // TODO 根据BUSY 状态返回
}

static int sfd_w25q_read (void* userdata, char* buff, size_t offset, size_t len) {
    sfd_drv_t *drv = (sfd_drv_t *)userdata;
    char cmd[4] = {0x03, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(drv->cfg.spi.cs, 0);
    luat_spi_send(drv->cfg.spi.id, (const char*)&cmd, sizeof(cmd));
    luat_spi_recv(drv->cfg.spi.id, buff, len);
    luat_gpio_set(drv->cfg.spi.cs, 1);
    return 0;
}

void sfd_w25q_write_enable(sfd_drv_t *drv) {
    luat_gpio_set(drv->cfg.spi.cs, 0);
    uint8_t cmd = 0x06;
    luat_spi_send(drv->cfg.spi.id, (const char*)&cmd, sizeof(cmd));
    luat_gpio_set(drv->cfg.spi.cs, 1);
}

static int sfd_w25q_write (void* userdata, const char* buff, size_t offset, size_t len) {
    sfd_drv_t *drv = (sfd_drv_t *)userdata;
    sfd_w25q_write_enable(drv);
    char cmd[4] = {0x02, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(drv->cfg.spi.cs, 0);
    luat_spi_send(drv->cfg.spi.id, (const char*)&cmd, sizeof(cmd));
    luat_spi_send(drv->cfg.spi.id, buff, len);
    luat_gpio_set(drv->cfg.spi.cs, 1);
    return 0;
}

static int sfd_w25q_erase (void* userdata, size_t offset, size_t len) {
    sfd_drv_t *drv = (sfd_drv_t *)userdata;
    sfd_w25q_write_enable(drv);
    char cmd[4] = {0x20, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(drv->cfg.spi.cs, 0);
    luat_spi_send(drv->cfg.spi.id, (const char*)&cmd, sizeof(cmd));
    luat_gpio_set(drv->cfg.spi.cs, 1);
    return 0;
}

static int sfd_w25q_ioctl (void* userdata, size_t cmd, void* buff) {
    return -1;
}
