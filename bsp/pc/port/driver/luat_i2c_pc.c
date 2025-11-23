
#include "luat_base.h"
#include "luat_i2c.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"
#endif

#define LUAT_LOG_TAG "luat.i2c"
#include "luat_log.h"

int luat_i2c_exist(int id) {
    return id == 0;
}

int luat_i2c_setup(int id, int speed) {
    #ifdef LUAT_USE_WINDOWS
    if(!g_ch3470_DevIsOpened)
        luat_load_ch347(0);
    if(g_ch3470_DevIsOpened) {
        if(luat_ch347_i2c_setup(id, speed)) {
            LLOGD("i2c set up success");
        } else {
            LLOGD("i2c set up failed");
        }

    }
    return 0;
    #else
    return -1;
    #endif
}

int luat_i2c_close(int id) {
    return 0;
}

int luat_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop) {
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_send(id, addr, buff, len, stop);
    }
    #endif
    return 0;
}

int luat_i2c_recv(int id, int addr, void* buff, size_t len) {
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_recv(id, addr, buff, len);
    }
    #endif
    return 0;
}

int luat_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len) {
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_transfer(id, addr, reg, reg_len, buff, len);
    }
    #endif
    return 0;
}

int luat_i2c_no_block_transfer(int id, int addr, uint8_t is_read, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len, uint16_t Toms, void *CB, void *pParam) {
	#ifdef LUAT_USE_WINDOWS
    if (g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_no_block_transfer(id, addr, is_read, reg, reg_len, buff, len, Toms, CB, pParam);
    }
    #endif
    return 0;
}
