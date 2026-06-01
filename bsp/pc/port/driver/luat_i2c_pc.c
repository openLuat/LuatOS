
#include "luat_base.h"
#include "luat_i2c.h"
#include "luat_i2c_pc_mock.h"
#ifdef LUAT_USE_WINDOWS
#include "luat_ch347_pc.h"
#endif

#define LUAT_LOG_TAG "luat.i2c"
#include "luat_log.h"

#define SHT20_ADDR 0x40
#define SHT20_CMD_TEMP_NOHOLD 0xF3
#define SHT20_CMD_HUM_NOHOLD 0xF5
#define SHT20_CMD_READ_USER_REG 0xE7
#define SHT20_CMD_WRITE_USER_REG 0xE6
#define SHT20_CMD_SOFT_RESET 0xFE
#define SHT20_USER_REG_DEFAULT 0x02

typedef struct luat_i2c_sht20_state {
    int32_t temperature_centi;
    int32_t humidity_centi;
    uint8_t user_reg;
    uint8_t pending_cmd;
} luat_i2c_sht20_state_t;

static luat_i2c_sht20_state_t g_sht20 = {
    .temperature_centi = 2500,
    .humidity_centi = 5000,
    .user_reg = SHT20_USER_REG_DEFAULT,
    .pending_cmd = 0,
};

static int32_t luat_i2c_clamp_i32(int32_t v, int32_t min_v, int32_t max_v) {
    if (v < min_v) return min_v;
    if (v > max_v) return max_v;
    return v;
}

static uint16_t luat_i2c_sht20_temp_raw(void) {
    double temp_c = (double)g_sht20.temperature_centi / 100.0;
    double raw_d = ((temp_c + 46.85) * 65536.0) / 175.72;
    if (raw_d < 0) raw_d = 0;
    if (raw_d > 65535.0) raw_d = 65535.0;
    return (uint16_t)(raw_d + 0.5);
}

static uint16_t luat_i2c_sht20_humi_raw(void) {
    double humi = (double)g_sht20.humidity_centi / 100.0;
    double raw_d = ((humi + 6.0) * 65536.0) / 125.0;
    if (raw_d < 0) raw_d = 0;
    if (raw_d > 65535.0) raw_d = 65535.0;
    return (uint16_t)(raw_d + 0.5);
}

int luat_i2c_pc_sht20_set_measurement(double temperature_c, double humidity_rh) {
    int32_t t = (int32_t)(temperature_c * 100.0 + (temperature_c >= 0 ? 0.5 : -0.5));
    int32_t h = (int32_t)(humidity_rh * 100.0 + (humidity_rh >= 0 ? 0.5 : -0.5));
    g_sht20.temperature_centi = luat_i2c_clamp_i32(t, -4685, 12887);
    g_sht20.humidity_centi = luat_i2c_clamp_i32(h, -600, 11900);
    return 0;
}

void luat_i2c_pc_sht20_get_measurement(double* temperature_c, double* humidity_rh) {
    if (temperature_c) {
        *temperature_c = (double)g_sht20.temperature_centi / 100.0;
    }
    if (humidity_rh) {
        *humidity_rh = (double)g_sht20.humidity_centi / 100.0;
    }
}

uint8_t luat_i2c_pc_sht20_get_user_reg(void) {
    return g_sht20.user_reg;
}

static int luat_i2c_sht20_send(void* buff, size_t len) {
    uint8_t* data = (uint8_t*)buff;
    if (!data || len == 0) {
        return 0;
    }
    switch (data[0]) {
        case SHT20_CMD_TEMP_NOHOLD:
        case SHT20_CMD_HUM_NOHOLD:
        case SHT20_CMD_READ_USER_REG:
            g_sht20.pending_cmd = data[0];
            break;
        case SHT20_CMD_WRITE_USER_REG:
            if (len >= 2) {
                g_sht20.user_reg = data[1];
            }
            g_sht20.pending_cmd = 0;
            break;
        case SHT20_CMD_SOFT_RESET:
            g_sht20.user_reg = SHT20_USER_REG_DEFAULT;
            g_sht20.pending_cmd = 0;
            break;
        default:
            g_sht20.pending_cmd = 0;
            break;
    }
    return 0;
}

static int luat_i2c_sht20_recv(void* buff, size_t len) {
    uint8_t* out = (uint8_t*)buff;
    uint16_t raw = 0;
    if (!out || len == 0) {
        return 0;
    }
    memset(out, 0, len);
    switch (g_sht20.pending_cmd) {
        case SHT20_CMD_TEMP_NOHOLD:
            raw = luat_i2c_sht20_temp_raw();
            if (len >= 1) out[0] = (uint8_t)(raw >> 8);
            if (len >= 2) out[1] = (uint8_t)(raw & 0xFF);
            break;
        case SHT20_CMD_HUM_NOHOLD:
            raw = luat_i2c_sht20_humi_raw();
            if (len >= 1) out[0] = (uint8_t)(raw >> 8);
            if (len >= 2) out[1] = (uint8_t)(raw & 0xFF);
            break;
        case SHT20_CMD_READ_USER_REG:
            out[0] = g_sht20.user_reg;
            break;
        default:
            break;
    }
    g_sht20.pending_cmd = 0;
    return 0;
}

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
    (void)id;
    (void)stop;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_send(id, addr, buff, len, stop);
        return 0;
    }
    #endif
    if (addr == SHT20_ADDR) {
        return luat_i2c_sht20_send(buff, len);
    }
    return 0;
}

int luat_i2c_recv(int id, int addr, void* buff, size_t len) {
    (void)id;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_recv(id, addr, buff, len);
        return 0;
    }
    #endif
    if (addr == SHT20_ADDR) {
        return luat_i2c_sht20_recv(buff, len);
    }
    return 0;
}

int luat_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len) {
    (void)id;
    #ifdef LUAT_USE_WINDOWS
    if(g_ch3470_DevIsOpened == 1) {
        luat_ch347_i2c_transfer(id, addr, reg, reg_len, buff, len);
        return 0;
    }
    #endif
    if (addr == SHT20_ADDR) {
        if (reg && reg_len) {
            luat_i2c_sht20_send(reg, reg_len);
        }
        if (buff && len) {
            return luat_i2c_sht20_recv(buff, len);
        }
    }
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
