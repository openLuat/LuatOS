#ifndef LUAT_TP_REG_H
#define LUAT_TP_REG_H

#include "luat_i2c.h"

static inline int tp_i2c_init(luat_tp_config_t* luat_tp_config){
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_setup(luat_tp_config->soft_i2c);
    }else{
        luat_i2c_setup(luat_tp_config->i2c_id, I2C_SPEED_FAST);
    }
    return 0;
}

static inline int tp_i2c_write_reg8(luat_tp_config_t* luat_tp_config, uint8_t reg, void* buff, size_t len){
    uint8_t data_reg[len+1];
    data_reg[0] = reg;
    memcpy(data_reg+1, buff, len);
    if (luat_tp_config->soft_i2c != NULL){
        return i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, len+1, 1);
    }else{
        return luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, len+1, 1);
    }
}

static inline int tp_i2c_read_reg8(luat_tp_config_t* luat_tp_config, uint8_t reg, void* buff, size_t len, uint8_t stop){
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)&reg, 1, stop);
        return i2c_soft_recv(luat_tp_config->soft_i2c, luat_tp_config->address, buff, len);
    }else{
        luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, (char *)&reg, 1, stop);
        return luat_i2c_recv(luat_tp_config->i2c_id, luat_tp_config->address, buff, len);
    }
}

static inline int tp_i2c_write_reg16(luat_tp_config_t* luat_tp_config, uint16_t reg, void* buff, size_t len){
    uint8_t data_reg[len+2];
    data_reg[0] = (reg>>8)&0xff;
    data_reg[1] = (reg&0xff);
    memcpy(data_reg+2, buff, len);
    if (luat_tp_config->soft_i2c != NULL){
        return i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, len+2, 1);
    }else{
        return luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, len+2, 1);
    }
}

static inline int tp_i2c_read_reg16(luat_tp_config_t* luat_tp_config, uint16_t reg, void* buff, size_t len, uint8_t stop){
    uint8_t data_reg[sizeof(uint16_t)] = {reg>>8, reg&0xff};
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, sizeof(uint16_t), stop);
        return i2c_soft_recv(luat_tp_config->soft_i2c, luat_tp_config->address, buff, len);
    }else{
        luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, sizeof(uint16_t), stop);
        return luat_i2c_recv(luat_tp_config->i2c_id, luat_tp_config->address, buff, len);
    }
}

static inline int tp_i2c_write_reg32(luat_tp_config_t* luat_tp_config, uint32_t reg, void* buff, size_t len){
    uint8_t data_reg[len+sizeof(uint32_t)];
    data_reg[0] = (reg>>24)&0xff;
    data_reg[1] = (reg>>16)&0xff;
    data_reg[2] = (reg>>8)&0xff;
    data_reg[3] = (reg&0xff);
    memcpy(data_reg+sizeof(uint32_t), buff, len);
    if (luat_tp_config->soft_i2c != NULL){
        return i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, len+sizeof(uint32_t), 1);
    }else{
        return luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, len+sizeof(uint32_t), 1);
    }
}

static inline int tp_i2c_read_reg32(luat_tp_config_t* luat_tp_config, uint32_t reg, void* buff, size_t len, uint8_t stop){
    uint8_t data_reg[sizeof(uint32_t)] = {(reg>>24)&0xff, (reg>>16)&0xff, (reg>>8)&0xff, reg&0xff};
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, sizeof(uint32_t), stop);
        return i2c_soft_recv(luat_tp_config->soft_i2c, luat_tp_config->address, buff, len);
    }else{
        luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, sizeof(uint32_t), stop);
        return luat_i2c_recv(luat_tp_config->i2c_id, luat_tp_config->address, buff, len);
    }
}














#endif