#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_i2s.h"
#include "lua.h"

#define LUAT_LOG_TAG "i2s_pc"
#include "luat_log.h"

// PC模拟器i2s配置数组
#define I2S_MAX_DEVICE 1
static luat_i2s_conf_t i2s_confs[I2S_MAX_DEVICE] = {0};

// i2s的假实现
int luat_i2s_setup(const luat_i2s_conf_t *conf) {
    if (conf == NULL || conf->id >= I2S_MAX_DEVICE) {
        LLOGE("i2s setup: invalid id");
        return -1;
    }

    LLOGD("i2s[%d] setup: mode=%d, sample_rate=%d, data_bits=%d, channel_format=%d, standard=%d",
        conf->id, conf->mode, conf->sample_rate, conf->data_bits, conf->channel_format, conf->standard);

    // 保存配置
    memcpy(&i2s_confs[conf->id], conf, sizeof(luat_i2s_conf_t));
    i2s_confs[conf->id].state = LUAT_I2S_STATE_RUNING;

    return 0;
}

int luat_i2s_modify(uint8_t id, uint8_t channel_format, uint8_t data_bits, uint32_t sample_rate) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    LLOGD("i2s[%d] modify: sample_rate=%d, data_bits=%d, channel_format=%d",
        id, sample_rate, data_bits, channel_format);

    i2s_confs[id].sample_rate = sample_rate;
    i2s_confs[id].data_bits = data_bits;
    i2s_confs[id].channel_format = channel_format;

    return 0;
}

int luat_i2s_send(uint8_t id, uint8_t* buff, size_t len) {
    if (id >= I2S_MAX_DEVICE || buff == NULL || len == 0) {
        return -1;
    }
    return len;
}

int luat_i2s_recv(uint8_t id, uint8_t* buff, size_t len) {
    if (id >= I2S_MAX_DEVICE || buff == NULL || len == 0) {
        return -1;
    }

    return 0;
}

int luat_i2s_transfer(uint8_t id, uint8_t* txbuff, size_t len) {
    return -1;
}

int luat_i2s_transfer_loop(uint8_t id, uint8_t* buff, uint32_t one_truck_byte_len, uint32_t total_trunk_cnt, uint8_t need_callback) {
    return -1;
}

int luat_i2s_pause(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    LLOGD("i2s[%d] pause", id);
    return 0;
}

int luat_i2s_resume(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    LLOGD("i2s[%d] resume", id);
    return 0;
}

int luat_i2s_close(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    i2s_confs[id].state = LUAT_I2S_STATE_STOP;
    return 0;
}

luat_i2s_conf_t *luat_i2s_get_config(uint8_t id) {
    if (id >= I2S_MAX_DEVICE) {
        return NULL;
    }
    return &i2s_confs[id];
}

int luat_i2s_save_old_config(uint8_t id) {
    return 0;
}

int luat_i2s_load_old_config(uint8_t id) {
    return 0;
}

int luat_i2s_txbuff_info(uint8_t id, size_t *buffsize, size_t* remain) {
    if (id >= I2S_MAX_DEVICE || buffsize == NULL || remain == NULL) {
        return -1;
    }

    *buffsize = 4096;
    *remain = 4096;
    return 0;
}

int luat_i2s_rxbuff_info(uint8_t id, size_t *buffsize, size_t* remain) {
    if (id >= I2S_MAX_DEVICE || buffsize == NULL || remain == NULL) {
        return -1;
    }
    *buffsize = 4096;
    *remain = 0;
    return 0;
}

int luat_i2s_set_user_data(uint8_t id, void *user_data) {
    if (id >= I2S_MAX_DEVICE) {
        return -1;
    }

    i2s_confs[id].userdata = user_data;
    return 0;
}

LUAT_WEAK int l_i2s_play(lua_State *L) {
    LLOGD("i2s.play not supported on PC");
    return 0;
}

LUAT_WEAK int l_i2s_pause(lua_State *L) {
    LLOGD("i2s.pause not supported on PC");
    return 0;
}

LUAT_WEAK int l_i2s_stop(lua_State *L) {
    LLOGD("i2s.stop not supported on PC");
    return 0;
}
