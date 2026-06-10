#include "luat_ems_server.h"
#include "luat_base.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "cJSON.h"

#define LUAT_LOG_TAG "ems"
#include "luat_log.h"



// 写入emergency service配置文件（单个字段）
void luat_ems_server_write_config(uint8_t config_type, void* value)
{
    FILE* fp = NULL;
    cJSON* root = NULL;
    
    // 首先读取现有配置
    if (luat_fs_fexist(EMG_SVC_FILE)) {
        char buf[EMG_SVC_FILE_SIZE] = {0};
        fp = luat_fs_fopen(EMG_SVC_FILE, "r");
        if (fp) {
            luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
            luat_fs_fclose(fp);
            root = cJSON_Parse(buf);
        }
    }
    
    // 如果文件不存在或解析失败，创建新对象
    if (!root) {
        root = cJSON_CreateObject();
    }
    
    // 根据config_type写入对应配置
    switch (config_type) {
        case EMS_SERVER_ENABLE: {
            cJSON* item = cJSON_GetObjectItem(root, "enable");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "enable", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_KEY: {
            cJSON* item = cJSON_GetObjectItem(root, "key");
            if (item) {
                cJSON_SetValuestring(item, (const char*)value);
            } else {
                cJSON_AddStringToObject(root, "key", (const char*)value);
            }
            break;
        }
        case EMS_SERVER_INTERVAL: {
            cJSON* item = cJSON_GetObjectItem(root, "interval");
            if (item) {
                cJSON_SetNumberValue(item, *((uint32_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "interval", *((uint32_t*)value));
            }
            break;
        }
        case EMS_SERVER_EXCEPTION_MAX_COUNT: {
            cJSON* item = cJSON_GetObjectItem(root, "exception_max_count");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "exception_max_count", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_NORMAL_MAX_COUNT: {
            cJSON* item = cJSON_GetObjectItem(root, "normal_max_count");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "normal_max_count", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_POWER_EXCEPTION: {
            cJSON* item = cJSON_GetObjectItem(root, "power_exception");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "power_exception", *((uint8_t*)value));
            }
            break;
        }
        case EMS_SERVER_POWER_NORMAL: {
            cJSON* item = cJSON_GetObjectItem(root, "power_normal");
            if (item) {
                cJSON_SetNumberValue(item, *((uint8_t*)value));
            } else {
                cJSON_AddNumberToObject(root, "power_normal", *((uint8_t*)value));
            }
            break;
        }
    }
    
    // 写入文件
    char* json_str = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (json_str) {
        fp = luat_fs_fopen(EMG_SVC_FILE, "w");
        if (fp) {
            luat_fs_fwrite(json_str, 1, strlen(json_str), fp);
            luat_fs_fclose(fp);
        }
        luat_heap_free(json_str);
    }
}

// 写入emergency service配置文件（全部字段）
void luat_ems_server_write_config_all(uint8_t enable, const char* key, uint32_t interval, uint8_t exception_max_count, uint8_t normal_max_count, uint8_t power_exception, uint8_t power_normal)
{
    FILE* fp = NULL;
    cJSON* root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "enable", enable);
    cJSON_AddStringToObject(root, "key", key);
    cJSON_AddNumberToObject(root, "interval", interval);
    cJSON_AddNumberToObject(root, "exception_max_count", exception_max_count);
    cJSON_AddNumberToObject(root, "normal_max_count", normal_max_count);
    cJSON_AddNumberToObject(root, "power_exception", power_exception);
    cJSON_AddNumberToObject(root, "power_normal", power_normal);
    char* json_str = cJSON_PrintUnformatted(root);
    LLOGD("json_str: %s", json_str);
    cJSON_Delete(root);
    if (json_str) {
        fp = luat_fs_fopen(EMG_SVC_FILE, "w");
        if (fp) {
            luat_fs_fwrite(json_str, 1, strlen(json_str), fp);
            luat_fs_fclose(fp);
        }
        luat_heap_free(json_str);
    }
}

// 读取emergency service配置文件
void luat_ems_server_read_config(uint8_t config_type, void* value)
{
    FILE* fp = NULL;
	if (luat_fs_fexist(EMG_SVC_FILE)) {
		char buf[EMG_SVC_FILE_SIZE] = {0};
		fp = luat_fs_fopen(EMG_SVC_FILE, "r");
		if (fp) {
			luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
			luat_fs_fclose(fp);
			cJSON* root = cJSON_Parse(buf);
            if (root) {
                switch (config_type) {
                    case EMS_SERVER_ENABLE: {
                        cJSON* item = cJSON_GetObjectItem(root, "enable");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_KEY: {
                        cJSON* item = cJSON_GetObjectItem(root, "key");
                        if (item && item->valuestring) {
                            strncpy((char*)value, item->valuestring, 31); // 假设key长度不超过32，留一个字节给结束符
                            ((char*)value)[31] = '\0'; // 确保字符串以结束符结尾
                        }
                        break;
                    }
                    case EMS_SERVER_INTERVAL: {
                        cJSON* item = cJSON_GetObjectItem(root, "interval");
                        if (item) *((uint32_t*)value) = (uint32_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_EXCEPTION_MAX_COUNT: {
                        cJSON* item = cJSON_GetObjectItem(root, "exception_max_count");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_NORMAL_MAX_COUNT: {
                        cJSON* item = cJSON_GetObjectItem(root, "normal_max_count");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_POWER_EXCEPTION: {
                        cJSON* item = cJSON_GetObjectItem(root, "power_exception");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                    case EMS_SERVER_POWER_NORMAL: {
                        cJSON* item = cJSON_GetObjectItem(root, "power_normal");
                        if (item) *((uint8_t*)value) = (uint8_t)item->valueint;
                        break;
                    }
                }
                cJSON_Delete(root);
            }
		}
	}
}

// 读取emergency service配置文件（全部字段）
void luat_ems_server_read_config_all(uint8_t* enable, char* key, uint32_t* interval, uint8_t* exception_max_count, uint8_t* normal_max_count, uint8_t* power_exception, uint8_t* power_normal)
{
    FILE* fp = NULL;
	if (luat_fs_fexist(EMG_SVC_FILE)) {
		char buf[EMG_SVC_FILE_SIZE] = {0};
		fp = luat_fs_fopen(EMG_SVC_FILE, "r");
		if (fp) {
			luat_fs_fread(buf, 1, sizeof(buf) - 1, fp);
			luat_fs_fclose(fp);
			cJSON* root = cJSON_Parse(buf);
            if (root) {
                cJSON* item = cJSON_GetObjectItem(root, "enable");
                if (item) *((uint8_t*)enable) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "key");
                if (item && item->valuestring) {
                    strncpy(key, item->valuestring, 31); // 假设key长度不超过32，留一个字节给结束符
                    key[31] = '\0'; // 确保字符串以结束符结尾
                }
                item = cJSON_GetObjectItem(root, "interval");
                if (item) *((uint32_t*)interval) = (uint32_t)item->valueint;
                item = cJSON_GetObjectItem(root, "exception_max_count");
                if (item) *((uint8_t*)exception_max_count) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "normal_max_count");
                if (item) *((uint8_t*)normal_max_count) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "power_exception");
                if (item) *((uint8_t*)power_exception) = (uint8_t)item->valueint;
                item = cJSON_GetObjectItem(root, "power_normal");
                if (item) *((uint8_t*)power_normal) = (uint8_t)item->valueint;
                cJSON_Delete(root);
                LLOGD("enable: %d, key: %s, interval: %d, exception_max_count: %d, normal_max_count: %d, power_exception: %d, power_normal: %d",
                    *enable, key, *interval, *exception_max_count, *normal_max_count, *power_exception, *power_normal);
            }
        }
    }
}

