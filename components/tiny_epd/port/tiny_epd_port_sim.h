#ifndef LUAT_TINY_EPD_PORT_SIM_H
#define LUAT_TINY_EPD_PORT_SIM_H

#include "tiny_epd.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * PC test double.  It records the port traffic instead of accessing hardware.
 * This header belongs to port/ deliberately: it is not part of the production
 * tiny_epd public API.
 */
typedef struct {
    uint8_t last_cmd;
    uint8_t has_data[256];
    uint8_t first_data[256];
    uint8_t last_data[256];
    uint32_t cmd_count[256];
    uint32_t data_count[256];
    uint32_t checksum[256];

    uint32_t write_cmd_total;
    uint32_t write_data_total;
    uint32_t reset_count;
    uint32_t reset_step_count;
    uint32_t busy_wait_count;
    uint32_t delay_ms_total;
    uint8_t last_reset_level;
    uint8_t last_busy_idle_level;
    uint32_t last_busy_timeout_ms;

    uint8_t fail_next_cmd;
    uint8_t fail_next_data;
    uint8_t fail_next_reset;
    uint8_t fail_next_busy;
} tiny_epd_sim_t;

void tiny_epd_sim_init(tiny_epd_sim_t *sim);
void tiny_epd_sim_reset_trace(tiny_epd_sim_t *sim);
tiny_epd_port_t tiny_epd_sim_port(tiny_epd_sim_t *sim);
uint32_t tiny_epd_sim_checksum_bytes(const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif

#endif
