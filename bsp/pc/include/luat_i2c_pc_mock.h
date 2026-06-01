#ifndef LUAT_I2C_PC_MOCK_H
#define LUAT_I2C_PC_MOCK_H

#include <stdint.h>

int luat_i2c_pc_sht20_set_measurement(double temperature_c, double humidity_rh);
void luat_i2c_pc_sht20_get_measurement(double* temperature_c, double* humidity_rh);
uint8_t luat_i2c_pc_sht20_get_user_reg(void);

#endif
