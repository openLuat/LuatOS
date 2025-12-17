#ifndef LUAT_NETDRV_CH390H_H
#define LUAT_NETDRV_CH390H_H 1

#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_ulwip.h"

#define CH390H_MAX_TX_NUM (128)

typedef struct luat_ch390h_cstring
{
    uint16_t len;
    uint8_t buff[4];
}luat_ch390h_cstring_t;

typedef struct ch390h
{
    uint8_t spiid;
    uint8_t cspin;
    uint8_t intpin;
    uint8_t adapter_id;
    uint8_t status;
    uint8_t init_done;
    uint8_t init_step;
    luat_netdrv_t* netdrv;
    uint8_t rxbuff[1600];
    uint8_t txbuff[1600];
    luat_ch390h_cstring_t* txqueue[CH390H_MAX_TX_NUM];
    char* txtmp;  // TX临时缓冲区，避免多设备冲突
    int pkg_mem_type;  // 数据包内存类型，每个设备独立配置
    uint16_t rx_error_count;  // 读包错误计数器
    uint16_t tx_busy_count;  // TX忙计数器
    uint16_t vid_pid_error_count;  // VID/PID检查失败计数器
    uint32_t last_reset_time;  // 最后一次复位时间（毫秒）
    uint32_t total_reset_count;  // 总复位次数
    uint32_t total_tx_drop;  // 总丢弃发送包数
    uint32_t total_rx_drop;  // 总丢弃接收包数
    uint8_t flow_control;  // 流控状态：0=正常 1=背压中
}ch390h_t;

#define CH390H_STATUS_STOPPED 4


luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);

#endif
