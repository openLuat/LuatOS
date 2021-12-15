#ifndef LUAT_I2C_H
#define LUAT_I2C_H

#include "luat_base.h"

typedef struct luat_ei2c {
    int sda;
    int scl;
    unsigned char addr;
} luat_ei2c;//软件i2c
#define LUAT_EI2C_TYPE "EI2C*"
#define toei2c(L) ((luat_ei2c *)luaL_checkudata(L, 1, LUAT_EI2C_TYPE))

int luat_i2c_exist(int id);
int luat_i2c_setup(int id, int speed, int slaveaddr);
int luat_i2c_close(int id);
int luat_i2c_send(int id, int addr, void* buff, size_t len);
int luat_i2c_recv(int id, int addr, void* buff, size_t len);

int luat_i2c_write_reg(int id, int addr, int reg, uint16_t value);
int luat_i2c_read_reg(int id, int addr, int reg, uint16_t* value);

#endif
