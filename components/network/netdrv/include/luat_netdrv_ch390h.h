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
}ch390h_t;


luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);

#endif
