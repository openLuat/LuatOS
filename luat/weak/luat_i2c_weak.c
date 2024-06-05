#include "luat_base.h"

#include "luat_i2c.h"




LUAT_WEAK int luat_i2c_write_reg(int id, int addr, int reg, void* buff, size_t len, uint8_t stop){
    uint8_t data[len+1];
    data[0]=reg;
    memcpy(data+1, buff, len);
    return luat_i2c_send(id, addr, data, len+1, stop);
}

LUAT_WEAK int luat_i2c_read_reg(int id, int addr, int reg, void* buff, size_t len){
    int ret = luat_i2c_send(id, addr, &reg, 1, 0);
    ret |= luat_i2c_recv(id, addr, buff, len);
    return ret;
}


