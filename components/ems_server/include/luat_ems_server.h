#ifndef LUAT_EMS_SERVER_H
#define LUAT_EMS_SERVER_H

#include "luat_base.h"

#define EMG_SVC_FILE "/emg_svc"
#define EMG_SVC_FILE_SIZE 258

enum {
    EMS_SERVER_ENABLE = 0,
    EMS_SERVER_KEY = 1,
    EMS_SERVER_INTERVAL = 2,
    EMS_SERVER_EXCEPTION_MAX_COUNT = 3,
    EMS_SERVER_NORMAL_MAX_COUNT = 4,
    EMS_SERVER_POWER_EXCEPTION = 5,
    EMS_SERVER_POWER_NORMAL = 6,
};

extern const char* ems_server_lua_code;

// 写入emergency service配置文件（单个字段）
void luat_ems_server_write_config(uint8_t config_type, void* value);

// 写入emergency service配置文件（全部字段）
void luat_ems_server_write_config_all(uint8_t enable, const char* key, uint32_t interval, uint8_t exception_max_count, uint8_t normal_max_count, uint8_t power_exception, uint8_t power_normal);

// 读取emergency service配置文件（单个字段）
void luat_ems_server_read_config(uint8_t config_type, void* value);

// 读取emergency service配置文件（全部字段）
void luat_ems_server_read_config_all(uint8_t* enable, char* key, uint32_t* interval, uint8_t* exception_max_count, uint8_t* normal_max_count, uint8_t* power_exception, uint8_t* power_normal);

#endif /* LUAT_EMS_SERVER_H */
