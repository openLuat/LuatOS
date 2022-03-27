/*
处理基本的remotem命令
*/
#include "luat_base.h"
#include "luat_remotem.h"
#include "luat_malloc.h"

extern void luat_str_fromhex(char* str, size_t len, char* buff);

// 初始包, 主要是为了确认交互通畅
void luat_remotem_typeopt_init(cJSON* top, cJSON* data) {
    // nop yet
}

// 心跳包, 还没确定是否需要
void luat_remotem_typeopt_ping(cJSON* top, cJSON* data) {
    // nop yet
}

// 服务器下发的日志, 直接在输出
void luat_remotem_typeopt_log(cJSON* top, cJSON* data) {
    //printf("json log income\n");
    cJSON* value = cJSON_GetObjectItem(data, "value");
    if (value == NULL || value->type != cJSON_String) {
        return;
    }
    size_t slen = strlen(value->valuestring) / 2;
    //printf("json log len %d\n", slen);
    char* buff = luat_heap_malloc(slen);
    if (buff == NULL) {
        return;
    }
    memset(buff, 0, slen);
    luat_str_fromhex(value->valuestring, slen*2, buff);
    for (size_t i = 0; i < slen; i++)
    {
        fputc(buff[i], stdout);
    }

}
