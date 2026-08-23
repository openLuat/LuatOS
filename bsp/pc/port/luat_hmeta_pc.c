#include "luat_base.h"
#include "luat_hmeta.h"
#include "luat_mcu.h"
#include "luat_mobile.h"
#include "luat_str.h"

int luat_hmeta_chip(char* buff) {
    memcpy(buff, "x86", 4);
    return 0;
}

int luat_hmeta_model_name(char* buff) {
    memcpy(buff, "PC", 3);
    return 0;
}

int luat_hmeta_hwversion(char* buff) {
    memcpy(buff, "A10", 4);
    return 0;
}

int luat_hmeta_muid(char* buf, size_t buf_len) {
    size_t id_len = 0;
    const char* id = luat_mcu_unique_id(&id_len);
    if (id_len > 0 && buf_len > 0) {
        size_t hex_len = id_len * 2;
        if (hex_len < buf_len) {
            luat_str_tohex(id, id_len, buf);
            buf[hex_len] = '\0';
        } else {
            luat_str_tohex(id, (buf_len - 1) / 2, buf);
            buf[buf_len - 1] = '\0';
        }
    } else if (buf_len > 0) {
        buf[0] = '\0';
    }
    return 0;
}

int luat_hmeta_devid(char* buf, size_t buf_len) {
    if (buf_len > 0) {
        if (luat_mobile_get_imei(0, buf, buf_len) <= 0) {
            buf[0] = '\0';
        }
    }
    return 0;
}

