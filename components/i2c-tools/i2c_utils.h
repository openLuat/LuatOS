#ifndef _I2C_UTILS_H_
#define _I2C_UTILS_H_

#include "luat_base.h"
#include <stdlib.h>

#define I2C_TOOLS_BUFFER_SIZE 64

uint8_t strtonum(const char* str);

void i2c_help(void);
uint8_t i2c_init(const uint8_t i2c_id, int speed);
uint8_t i2c_probe(char addr);
uint8_t i2c_write(char addr, uint8_t* data, int len);
uint8_t i2c_read(uint8_t addr, uint8_t reg, uint8_t* buffer, uint8_t len);
void i2c_scan(void);
void i2c_tools(const char * data,size_t len);

#endif /*_I2C_UTILS_H_*/
