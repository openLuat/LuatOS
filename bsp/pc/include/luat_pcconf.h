#ifndef LUAT_PCCONF_H
#define LUAT_PCCONF_H

typedef struct luat_pcconf
{
    // MCU
    char   mcu_unique_id[64];
    size_t mcu_unique_id_len;
    size_t mcu_mhz;

    // mobile
    char mobile_imei[16];
    char mobile_muid[20];
    char mobile_imsi[20];
    char mobile_iccid[20];
    char mobile_iccid2[20];
    int  mobile_csq;

    // uart udp
    size_t uart_udp_port_start;
    size_t uart_udp_id_start;
    size_t uart_udp_id_count;
}luat_pcconf_t;

void luat_pcconf_init(void);

void luat_pcconf_save(void);

void free_uv_handle(void* ptr);

#endif
