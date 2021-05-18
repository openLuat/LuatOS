
#include "luat_base.h"
#include "luat_spi.h"
#include "luat_gpio.h"

#include "luat_sfd.h"

#define LUAT_LOG_TAG "sfd"
#include "luat_log.h"

#define CS_H(pin) luat_gpio_set(pin, 1)
#define CS_L(pin) luat_gpio_set(pin, 0)

// 针对W25Q的实现

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
    sfd_w25q_t *w25q = (sfd_w25q_t *)userdata;
    uint8_t cmd = 0x9F;
    // 发送CMD 9F, 读取容量信息
    luat_gpio_set(w25q->spi_cs, 0);
    luat_spi_send(w25q->spi_id, (const char*)&cmd, 1);
    char buff[3] = {0};
    luat_spi_recv(w25q->spi_id, buff, 3);
    luat_gpio_set(w25q->spi_cs, 1);
    if (buff[0] != 0x40) {
        LLOGW("can't read spi flash: cmd 9F");
        return -1;
    }
    LLOGD("spi flash %02X %02X %02X", buff[0], buff[1], buff[2]);
    if (buff[1] == 0xEF) {
        switch(buff[2]) {
            case 0x13:
                w25q->sector_count = 8*256;// w25q80, 8M
                break;
            case 0x14:
                w25q->sector_count = 16*256;// w25q16, 16M
                break;
            case 0x15:
                w25q->sector_count = 32*256;// w25q32, 32M
                break;
            case 0x16:
                w25q->sector_count = 64*256;// w25q64, 64M
                break;
            case 0x17:
                w25q->sector_count = 128*256;// w25q128, 128M
                break;
            case 0x18:
                w25q->sector_count = 256*256;// w25q256, 256M
                break;
            case 0x19:
                w25q->sector_count = 512*256;// w25q512, 512M
                break;
            default :
                w25q->sector_count = 16*256;// 默认当16M吧
                break;
        }
    }
    else {
        w25q->sector_count = 16*256;// 默认当16M吧
    }
    //w25q->flash_id[0] = buff[1];
    //w25q->flash_id[1] = buff[2];

    // 读设备唯一id
    luat_gpio_set(w25q->spi_cs, 0);
    char chip_id_cmd[] = {0x4B, 0x00, 0x00, 0x00, 0x00};
    luat_spi_send(w25q->spi_id, chip_id_cmd, 5);
    luat_spi_read(w25q->spi_id, w25q->chip_id, 8);
    luat_gpio_set(w25q->spi_cs, 1);

    return 0;
}

static int sfd_w25q_status (void* userdata) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)userdata;
    return w25q->sector_count == 0 ? 0 : 1; // TODO 根据BUSY 状态返回
}

static int sfd_w25q_read (void* userdata, char* buff, size_t offset, size_t len) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)userdata;
    char cmd[4] = {0x03, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(w25q->spi_cs, 0);
    luat_spi_send(w25q->spi_id, (const char*)&cmd, 4);
    luat_spi_read(w25q->spi_id, buff, len);
    luat_gpio_set(w25q->spi_cs, 1);
    return 0;
}

static int sfd_w25q_write (void* userdata, const char* buff, size_t offset, size_t len) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)userdata;
    char cmd[4] = {0x02, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(w25q->spi_cs, 0);
    luat_spi_send(w25q->spi_id, (const char*)&cmd, 4);
    luat_spi_send(w25q->spi_id, buff, len);
    luat_gpio_set(w25q->spi_cs, 1);
    return 0;
}

static int sfd_w25q_erase (void* userdata, size_t offset, size_t len) {
    sfd_w25q_t *w25q = (sfd_w25q_t *)userdata;
    char cmd[4] = {0x20, offset >> 16, (offset >> 8) & 0xFF, offset & 0xFF};
    luat_gpio_set(w25q->spi_cs, 0);
    luat_spi_send(w25q->spi_id, (const char*)&cmd, 4);
    luat_gpio_set(w25q->spi_cs, 1);
    return 0;
}

static int sfd_w25q_ioctl (void* userdata, size_t cmd, void* buff) {
    return -1;
}
