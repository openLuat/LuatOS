
#include "luat_base.h"
#include "luat_i2c.h"

#define LUAT_LOG_TAG "luat.i2c"
#include "luat_log.h"

int luat_i2c_exist(int id) {
    return id == 0;
}
    
int luat_i2c_setup(int id, int speed) {
    return 0;
}

int luat_i2c_close(int id) {
    return 0;
}

int luat_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop) {
    return 0;
}

int luat_i2c_recv(int id, int addr, void* buff, size_t len) {
    return 0;
}

int luat_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len) {
    return 0;
}

int luat_i2c_no_block_transfer(int id, int addr, uint8_t is_read, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len, uint16_t Toms, void *CB, void *pParam) {
	return 0;
}
