#ifndef LUAT_TP_REG_H
#define LUAT_TP_REG_H

#include "luat_i2c.h"

static inline int tp_i2c_write(luat_tp_config_t* luat_tp_config, uint8_t* cmd, size_t cmd_len, void* data, size_t data_len){
    size_t len = cmd_len+data_len;
    uint8_t data_reg[len];
    memcpy(data_reg, cmd, cmd_len);
    memcpy(data_reg+cmd_len, data, data_len);
    if (luat_tp_config->soft_i2c != NULL){
        return i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)data_reg, len, 1);
    }else{
        return luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, data_reg, len, 1);
    }
}

static inline int tp_i2c_read(luat_tp_config_t* luat_tp_config, uint8_t* cmd, size_t cmd_len, void* data, size_t data_len, uint8_t stop){
    if (luat_tp_config->soft_i2c != NULL){
        i2c_soft_send(luat_tp_config->soft_i2c, luat_tp_config->address, (char *)cmd, cmd_len, stop);
        return i2c_soft_recv(luat_tp_config->soft_i2c, luat_tp_config->address, data, data_len);
    }else{
        luat_i2c_send(luat_tp_config->i2c_id, luat_tp_config->address, (char *)cmd, cmd_len, stop);
        return luat_i2c_recv(luat_tp_config->i2c_id, luat_tp_config->address, data, data_len);
    }
}

static inline int tp_i2c_write_reg8(luat_tp_config_t* luat_tp_config, uint8_t reg, void* buff, size_t len){
    uint8_t data_reg[sizeof(uint8_t)] = {reg};
    return tp_i2c_write(luat_tp_config, data_reg, sizeof(uint8_t), buff, len);
}

static inline int tp_i2c_read_reg8(luat_tp_config_t* luat_tp_config, uint8_t reg, void* buff, size_t len, uint8_t stop){
    uint8_t data_reg[sizeof(uint8_t)] = {reg};
    return tp_i2c_read(luat_tp_config, data_reg, sizeof(uint8_t), buff, len, stop);
}

static inline int tp_i2c_write_reg16(luat_tp_config_t* luat_tp_config, uint16_t reg, void* buff, size_t len){
    uint8_t data_reg[sizeof(uint16_t)] = {reg>>8, reg&0xff};
    return tp_i2c_write(luat_tp_config, data_reg, sizeof(uint16_t), buff, len);
}

static inline int tp_i2c_read_reg16(luat_tp_config_t* luat_tp_config, uint16_t reg, void* buff, size_t len, uint8_t stop){
    uint8_t data_reg[sizeof(uint16_t)] = {reg>>8, reg&0xff};
    return tp_i2c_read(luat_tp_config, data_reg, sizeof(uint16_t), buff, len, stop);
}

static inline int tp_i2c_write_reg32(luat_tp_config_t* luat_tp_config, uint32_t reg, void* buff, size_t len){
    uint8_t data_reg[sizeof(uint32_t)] = {(reg>>24)&0xff,(reg>>16)&0xff,(reg>>8)&0xff,reg&0xff};
    return tp_i2c_write(luat_tp_config, data_reg, sizeof(uint32_t), buff, len);
}

static inline int tp_i2c_read_reg32(luat_tp_config_t* luat_tp_config, uint32_t reg, void* buff, size_t len, uint8_t stop){
    uint8_t data_reg[sizeof(uint32_t)] = {(reg>>24)&0xff,(reg>>16)&0xff,(reg>>8)&0xff,reg&0xff};
    return tp_i2c_read(luat_tp_config, data_reg, sizeof(uint32_t), buff, len, stop);
}














#endif