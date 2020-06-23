#ifndef LUAT_I2C
#define LUAT_I2C

#include "luat_base.h"

int luat_i2c_exist(int id);
int luat_i2c_setup(int id, int speed, int slaveaddr);
int luat_ic2_close(int id);
int luat_i2c_send(int id, int addr, void* buff, size_t len);
int luat_i2c_recv(int id, int addr, void* buff, size_t len);

int luat_i2c_write_reg(int id, int addr, int reg, uint16_t value);
int luat_i2c_read_reg(int id, int addr, int reg, uint16_t* value);

#endif
