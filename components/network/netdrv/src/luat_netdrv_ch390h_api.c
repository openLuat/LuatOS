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
    int ret = 0;
    luat_spi_lock(ch->spiid);
    if (addr == CH390H_REG_RX_DATA) {
        tmp[0] = addr;
        luat_gpio_set(ch->cspin, 0);
        ret = luat_spi_send(ch->spiid, tmp, 1);
        if (ret != 1) {
            LLOGE("luat_spi_send失败 expect=1 ret=%d", ret);
            luat_gpio_set(ch->cspin, 1);
            luat_spi_unlock(ch->spiid);
            return -1;
        }
        ret = luat_spi_recv(ch->spiid, (char*)buff, count);
        luat_gpio_set(ch->cspin, 1);
    }
    else {
        for (size_t i = 0; i < count; i++)
        {
            tmp[0] = addr + i;
            luat_gpio_set(ch->cspin, 0);
            luat_spi_send(ch->spiid, tmp, 1);
            luat_spi_recv(ch->spiid, (char*)&buff[i], 1);
            luat_gpio_set(ch->cspin, 1);
        }
    }

    luat_spi_unlock(ch->spiid);
    return 0;
}

int luat_ch390h_write(ch390h_t* ch, uint8_t addr, uint16_t count, uint8_t* buff) {
    if (ch->txtmp == NULL) {
        ch->txtmp = luat_heap_malloc(3 * 1024);
        if (ch->txtmp == NULL) {
            LLOGE("txtmp内存分配失败");
            return -1;
        }
    }
    if (count > 1600) {
        LLOGW("数据包过大(%d),丢弃", count);
        return -2;
    }
    luat_spi_lock(ch->spiid);
    if (addr == CH390H_REG_TX_DATA) {
        ch->txtmp[0] = addr | 0x80;
        memcpy(ch->txtmp+1, buff, count);
        luat_gpio_set(ch->cspin, 0);
        luat_spi_send(ch->spiid, (const char* )ch->txtmp, 1 + count);
        luat_gpio_set(ch->cspin, 1);
    }
    else {
        for (size_t i = 0; i < count; i++)
        {
            ch->txtmp[0] = (addr + i) | 0x80;
            ch->txtmp[1] = buff[i];
            luat_gpio_set(ch->cspin, 0);
            luat_spi_send(ch->spiid, (const char* )ch->txtmp, 2);
            luat_gpio_set(ch->cspin, 1);
        }
    }

    luat_spi_unlock(ch->spiid);
    return 0;
}

int luat_ch390h_write_reg(ch390h_t* ch, uint8_t addr, uint8_t value) {
    uint8_t buff[1] = {0};
    buff[0] = value;
    luat_ch390h_write(ch, addr, 1, buff);
    return 0;
}

int luat_ch390h_read_mac(ch390h_t* ch, uint8_t* buff) {
    return luat_ch390h_read(ch, CH390H_REG_MAC, 6, buff);
}

int luat_ch390h_read_vid_pid(ch390h_t* ch, uint8_t* buff) {
    return luat_ch390h_read(ch, CH390H_REG_VID_PID, 4, buff);
}

int luat_ch390h_basic_config(ch390h_t* ch) {
    luat_ch390h_write_reg(ch, CH390H_REG_ISR, 0xFF);
    luat_ch390h_write_reg(ch, CH390H_REG_WCR, 0x80);
    luat_ch390h_write_reg(ch, CH390H_REG_IMR, 0xFF);
    luat_ch390h_write_reg(ch, CH390H_REG_TP_PTR, 0x01);
    luat_ch390h_write_reg(ch, CH390H_REG_RX_LEN, 0x0C);
    return 0;
}

int luat_ch390h_software_reset(ch390h_t* ch) {
    luat_ch390h_write_reg(ch, CH390H_REG_NCR, 0x01);
    luat_ch390h_write_reg(ch, CH390H_REG_NCR, 0x00);
    luat_ch390h_write_reg(ch, CH390H_REG_NCR, 0x01);
    return 0;
}

int luat_ch390h_set_rx(ch390h_t* ch, int enable) {
    if (enable) {
        luat_ch390h_write_reg(ch, CH390H_REG_RCR, (1 <<4) | (1 <<0) | (1 << 3));
    }
    else {
        luat_ch390h_write_reg(ch, CH390H_REG_RCR, 0);
    }
    return 0;
}

int luat_ch390h_set_phy(ch390h_t* ch, int enable) {
    uint8_t buff[1] = {enable == 0 ? 1 : 0};
    luat_ch390h_write(ch, CH390H_REG_GPR, 1, buff);
    return 0;
}

int luat_ch390h_read_pkg(ch390h_t* ch, uint8_t *buff, uint16_t* len) {
    uint8_t tmp[4] = {0};
    uint8_t rx_ready;

    // 先假读一次
    luat_ch390h_read(ch, CH390H_REG_RX_STATUS, 1, tmp);
    // 真正读取一次
    luat_ch390h_read(ch, CH390H_REG_RX_STATUS, 1, tmp);
    rx_ready = tmp[0];

    if (rx_ready & 0xFE) {
        // Reset RX FIFO pointer (按照CH官方实现)
        uint8_t rcr = 0;
        luat_ch390h_read(ch, CH390H_REG_RCR, 1, &rcr);
        luat_ch390h_write_reg(ch, CH390H_REG_RCR, rcr & ~(1 << 0));
        luat_ch390h_write_reg(ch, CH390H_REG_TP_PTR, 0x01);
        luat_ch390h_write_reg(ch, CH390H_REG_RX_LEN, 0x0C);
        luat_timer_us_delay(1000);
        luat_ch390h_write_reg(ch, CH390H_REG_RCR, rcr | (1 << 0));
        *len = 0;
        return 0;
    }

    // 检查是否有数据包
    if (!(rx_ready & 0x01)) {
        // 没有数据
        *len = 0;
        return 0;
    }
    luat_ch390h_read(ch, CH390H_REG_RX_DATA, 4, tmp);
    *len = tmp[2] + (tmp[3] << 8);
    if (*len == 0) {
        return 1; // 出错了啊!!!
    }
    if (*len > 1600) {
        LLOGE("pkg too large %u", *len);
        return 2;
    }
    luat_ch390h_read(ch, CH390H_REG_RX_DATA, *len, buff);
    return 0;
}

int luat_ch390h_write_pkg(ch390h_t* ch, uint8_t *buff, uint16_t len) {
    uint8_t tmp[4] = {0};
    
    luat_ch390h_read(ch, CH390H_REG_TCR, 1, tmp);
    uint8_t TCR = tmp[0];
    uint8_t NCR = 0;
    uint8_t NSR = 0;
    if (TCR & 0x01) {
        // busy!! 增加重试次数
        for (size_t i = 0; i < 100; i++)
        {
            luat_timer_us_delay(10);
            luat_ch390h_read(ch, CH390H_REG_TCR, 1, tmp);
            TCR = tmp[0];
            if (!(TCR & 0x01)) {
                ch->tx_busy_count = 0;  // 成功后清零计数器
                break;
            }
        }
        if (TCR & 0x01) {
            ch->tx_busy_count++;
            LLOGW("tx busy, drop pkg len %d, busy_count=%d", len, ch->tx_busy_count);
            // 只有连续多次TX忙且距离上次复位超过5秒才复位
            extern uint64_t luat_mcu_tick64_ms(void);
            uint32_t now = (uint32_t)luat_mcu_tick64_ms();
            if (ch->tx_busy_count >= 10 && (now - ch->last_reset_time > 5000)) {
                // 读出NCR 和 NSR
                luat_ch390h_read(ch, CH390H_REG_NCR, 1, tmp);
                NCR = tmp[0];
                luat_ch390h_read(ch, CH390H_REG_NSR, 1, tmp);
                NSR = tmp[0];
                LLOGE("连续TX忙超过阈值，执行复位 NCR=%02X NSR=%02X", NCR, NSR);
                LLOGD("NCR->FDR %02X NSR->SPEED %02X NSR->LINKST %02X", NCR & (1<<3), NSR & (1<<7), NSR & (1<<6));
                luat_ch390h_software_reset(ch);
                luat_timer_mdelay(2);
                luat_ch390h_basic_config(ch);
                luat_ch390h_set_phy(ch, 1);
                luat_ch390h_set_rx(ch, 1);
                ch->tx_busy_count = 0;
                ch->last_reset_time = now;
                ch->total_reset_count++;
            }
            return -1;
        }
    }
    luat_ch390h_write_reg(ch, CH390H_REG_TP_PTR, 2);     // 发数据之前重置一下tx的内存指针
    // 写入下一个数据
    luat_ch390h_write(ch, CH390H_REG_TX_DATA, len, buff);
    // TCR == 0之后, 才能写入长度
    luat_ch390h_write_reg(ch, CH390H_REG_TX_LEN_L, len & 0xFF);
    luat_ch390h_write_reg(ch, CH390H_REG_TX_LEN_H, (len >> 8) & 0xFF);
    // 再读一次TCR
    luat_ch390h_read(ch, CH390H_REG_TCR, 1, tmp);
    // 发送
    luat_ch390h_write_reg(ch, CH390H_REG_TCR, tmp[0] | 0x01);
    return 0;
}
