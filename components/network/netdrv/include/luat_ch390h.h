#ifndef LUAT_CH390H_API_H
#define LUAT_CH390H_API_H 1

#include "luat_netdrv_ch390h.h"

#define MAX_CH390H_NUM (5)

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
