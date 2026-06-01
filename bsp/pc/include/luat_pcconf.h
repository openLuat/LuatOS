#ifndef LUAT_PCCONF_H
#define LUAT_PCCONF_H

#include <stddef.h>
#include <stdint.h>

#define LUAT_PCCONF_MODEL_NAME_MAX (16)

typedef struct luat_pcconf
{
    size_t schema_version;

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

    // web console
    uint8_t web_console_enabled;
    uint16_t web_console_port;
    uint8_t web_console_refresh_interval;

    // placeholders
    uint8_t tf_enabled;
    uint8_t nor_enabled;
    uint8_t nand_enabled;
    uint16_t tf_capacity_mb;
    uint16_t nor_capacity_mb;
    uint16_t nand_capacity_mb;
    char nor_model[LUAT_PCCONF_MODEL_NAME_MAX];
    char nand_model[LUAT_PCCONF_MODEL_NAME_MAX];
    uint8_t network_enabled;
    uint8_t simulator_enabled;
}luat_pcconf_t;

typedef struct luat_pc_storage_effective_conf {
    uint8_t tf_enabled;
    uint8_t nor_enabled;
    uint8_t nand_enabled;
    uint32_t tf_capacity_mb;
    uint32_t nor_capacity_mb;
    uint32_t nand_capacity_mb;
    char nor_model[LUAT_PCCONF_MODEL_NAME_MAX];
    char nand_model[LUAT_PCCONF_MODEL_NAME_MAX];
} luat_pc_storage_effective_conf_t;

void luat_pcconf_init(void);

void luat_pcconf_save(void);

const luat_pcconf_t* luat_pcconf_get(void);

int luat_pcconf_update_web_console(int enabled, int port, int refresh_interval, int persist);
int luat_pcconf_update_network(int enabled, int persist);
int luat_pcconf_update_storage(int tf_enabled, int nor_enabled, int nand_enabled,
                               int tf_capacity_mb, int nor_capacity_mb, int nand_capacity_mb,
                               const char* nor_model, const char* nand_model, int persist);
void luat_pc_storage_get_effective(luat_pc_storage_effective_conf_t* out);

void free_uv_handle(void* ptr);

#endif
