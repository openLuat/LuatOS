#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_malloc.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "net_lwip2.h"
#include "luat_ulwip.h"
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"

#include "luat_ch390h.h"

#define LUAT_LOG_TAG "ch390h.api"
#include "luat_log.h"

int luat_ch390h_read(ch390h_t* ch, uint8_t addr, uint16_t count, uint8_t* buff) {
    char tmp[1] = {0};
    luat_gpio_set(ch->cspin, 0);
    if (addr == 0x72) {
        tmp[0] = addr;
        luat_spi_send(ch->spiid, tmp, 1);
        char* ptr = (char*)buff;
        while (count > 0) {
            if (count > 64) {
                luat_spi_recv(ch->spiid, ptr, 64);
                count -= 64;
                ptr += 64;
            }
            else {
                luat_spi_recv(ch->spiid, ptr, count);
                break;
            }
        }
    }
    else {
        for (size_t i = 0; i < count; i++)
        {
            tmp[0] = addr + i;
            luat_spi_send(ch->spiid, tmp, 1);
            luat_spi_recv(ch->spiid, (char*)&buff[i], 1);
        }
    }

    luat_gpio_set(ch->cspin, 1);
    return 0;
}

int luat_ch390h_write(ch390h_t* ch, uint8_t addr, uint16_t count, uint8_t* buff) {
    static char txtmp[2048] = {0};
    luat_gpio_set(ch->cspin, 0);
    if (count > 1600) {
        return 0; // 直接不发送
    }
    if (addr == 0x78) {
        txtmp[0] = addr | 0x80;
        memcpy(txtmp+1, buff, count);
        luat_spi_send(ch->spiid, (const char* )txtmp, 1 + count);
    }
    else {
        for (size_t i = 0; i < count; i++)
        {
            txtmp[0] = (addr + i) | 0x80;
            txtmp[1] = buff[i];
            luat_spi_send(ch->spiid, (const char* )txtmp, 2);
            // LLOGD("寄存器写 addr %02X value %02X", addr, tmp[1]);
        }
    }

    luat_gpio_set(ch->cspin, 1);
    return 0;
}

int luat_ch390h_write_reg(ch390h_t* ch, uint8_t addr, uint8_t value) {
    uint8_t buff[1] = {0};
    buff[0] = value;
    luat_ch390h_write(ch, addr, 1, buff);
    return 0;
}

int luat_ch390h_read_mac(ch390h_t* ch, uint8_t* buff) {
    return luat_ch390h_read(ch, 0x10, 6, buff);
}

int luat_ch390h_read_vid_pid(ch390h_t* ch, uint8_t* buff) {
    return luat_ch390h_read(ch, 0x28, 4, buff);
}

int luat_ch390h_basic_config(ch390h_t* ch) {
    /*
    ch390h.write(0, 0x01)
    sys.wait(20)
    ch390h.write(0x01, (1 << 5) | (1 << 3) | (1 << 2))
    ch390h.write(0x7E, 0xFF)
    ch390h.write(0x2D, 0x80)
    -- write_reg(0x31, 0x1F)
    ch390h.write(0x7F, 0xFF)

    ch390h.write(0x55, 0x01)
    ch390h.write(0x75, 0x0c)
    sys.wait(20)
    -- ch390h.enable_rx()
     */
    luat_ch390h_write_reg(ch, 0x7E, 0xFF);
    luat_ch390h_write_reg(ch, 0x2D, 0x80);
    luat_ch390h_write_reg(ch, 0x7F, 0xFF);
    luat_ch390h_write_reg(ch, 0x55, 0x01);
    luat_ch390h_write_reg(ch, 0x75, 0x0C);
    return 0;
}

int luat_ch390h_software_reset(ch390h_t* ch) {
    // ch390h.write(0, 0x01)
    luat_ch390h_write_reg(ch, 0x00, 0x01);
    // sys.wait(20)
    // ch390h.write(0, 0x00)
    luat_ch390h_write_reg(ch, 0x00, 0x00);
    // ch390h.write(0, 0x01)
    luat_ch390h_write_reg(ch, 0x00, 0x01);
    // sys.wait(20)
    return 0;
}

int luat_ch390h_set_rx(ch390h_t* ch, int enable) {
    // ch390h.write(0x05, (1 <<4) | (1 <<0) | (1 << 3))
    if (enable) {
        luat_ch390h_write_reg(ch, 0x05, (1 <<4) | (1 <<0) | (1 << 3));
    }
    else {
        luat_ch390h_write_reg(ch, 0x05, 0);
    }
    return 0;
}

int luat_ch390h_set_phy(ch390h_t* ch, int enable) {
    uint8_t buff[1] = {enable == 0 ? 1 : 0};
    luat_ch390h_write(ch, 0x1F, 1, buff);
    return 0;
}

int luat_ch390h_read_pkg(ch390h_t* ch, uint8_t *buff, uint16_t* len) {
    uint8_t tmp[4] = {0};
    // 先假读一次
    luat_ch390h_read(ch, 0x70, 1, tmp);
    // 真正读取一次
    luat_ch390h_read(ch, 0x70, 1, tmp);
    uint8_t MRCMDX = tmp[0];
    if (MRCMDX & 0xFE) {
        // 出错了!!
        LLOGW("MRCMDX %02X !!! reset self", MRCMDX);
        return -1;
    }
    if ((MRCMDX & 0x01) == 0) {
        // 没有数据
        *len = 0;
        return 0;
    }
    luat_ch390h_read(ch, 0x72, 4, tmp);
    *len = tmp[2] + (tmp[3] << 8);
    if (*len == 0) {
        return 1; // 出错了啊!!!
    }
    if (*len > 1600) {
        LLOGE("pkg too large %ld", len);
        return 2;
    }
    luat_ch390h_read(ch, 0x72, *len, buff);
    return 0;
}

int luat_ch390h_write_pkg(ch390h_t* ch, uint8_t *buff, uint16_t len) {
    uint8_t tmp[4] = {0};
    luat_ch390h_read(ch, 0x02, 1, tmp);
    uint8_t TCR = tmp[0];
    if (TCR & 0x01) {
        // busy!!
        LLOGW("tx busy, drop pkg len %d", len);
        return 1;
    }
    // 写入下一个数据
    luat_ch390h_write(ch, 0x78, len, buff);
    // 写入长度
    luat_ch390h_write_reg(ch, 0x7C, len & 0xFF);
    luat_ch390h_write_reg(ch, 0x7D, (len >> 8) & 0xFF);
    // 再读一次TCR
    luat_ch390h_read(ch, 0x02, 1, tmp);
    // 发送
    luat_ch390h_write_reg(ch, 0x02, tmp[0] | 0x01);
    return 0;
}
