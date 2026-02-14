#ifndef LUAT_CH390H_API_H
#define LUAT_CH390H_API_H 1

#include "luat_netdrv_ch390h.h"

#define MAX_CH390H_NUM (5)

// CH390H 寄存器地址定义
#define CH390H_REG_NCR          0x00    // 网络控制寄存器
#define CH390H_REG_NSR          0x01    // 网络状态寄存器
#define CH390H_REG_TCR          0x02    // 发送控制寄存器
#define CH390H_REG_RCR          0x05    // 接收控制寄存器
#define CH390H_REG_MAC          0x10    // MAC地址寄存器 (6字节)
#define CH390H_REG_GPR          0x1F    // 通用寄存器 (PHY开关)
#define CH390H_REG_VID_PID      0x28    // VID/PID寄存器 (4字节)
#define CH390H_REG_WCR          0x2D    // 唤醒控制寄存器
#define CH390H_REG_TP_PTR       0x55    // TX/RX内存指针
#define CH390H_REG_RX_STATUS    0x70    // RX就绪状态
#define CH390H_REG_RX_DATA      0x72    // RX FIFO数据
#define CH390H_REG_RX_LEN       0x75    // RX长度
#define CH390H_REG_TX_DATA      0x78    // TX FIFO数据
#define CH390H_REG_TX_LEN_L     0x7C    // TX长度低字节
#define CH390H_REG_TX_LEN_H     0x7D    // TX长度高字节
#define CH390H_REG_ISR          0x7E    // 中断状态寄存器
#define CH390H_REG_IMR          0x7F    // 中断屏蔽寄存器

int luat_ch390h_read(ch390h_t* ch, uint8_t addr, uint16_t count, uint8_t* buff);
int luat_ch390h_write(ch390h_t* ch, uint8_t addr, uint16_t count, uint8_t* buff);

int luat_ch390h_read_mac(ch390h_t* ch, uint8_t* buff);
int luat_ch390h_read_vid_pid(ch390h_t* ch, uint8_t* buff);

int luat_ch390h_basic_config(ch390h_t* ch);
int luat_ch390h_software_reset(ch390h_t* ch);

int luat_ch390h_set_rx(ch390h_t* ch, int enable);
int luat_ch390h_set_phy(ch390h_t* ch, int enable);

int luat_ch390h_read_pkg(ch390h_t* ch, uint8_t *buff, uint16_t* len);
int luat_ch390h_write_pkg(ch390h_t* ch, uint8_t *buff, uint16_t len);

int luat_ch390h_write_reg(ch390h_t* ch, uint8_t addr, uint8_t value);

#endif
