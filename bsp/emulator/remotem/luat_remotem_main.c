#include "luat_base.h"

#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#include "cJSON.h"

#include "luat_remotem.h"
#include "unistd.h"
#include <getopt.h>
#include "windows.h"

#define debug_printf printf

static luat_remotem_uplink_cb uplink;

luat_remotem_ctx_t rctx = {
    .bsp = "win32",
    .wait = 1,
    .mqtt = {
        .host = "emqx.site0.cn",
        .port = 1883,
        .protocol = "tcp",
        .topic_uplink = "",
        .topic_downlink = "",
    },
    .self_id = "",
    .session_id = "",
};

static const type_opt_t opts[] = {
    {"init", luat_remotem_typeopt_init},
    {"log", luat_remotem_typeopt_log},
    // {"ping", luat_remotem_typeopt_ping},
    // {"gpio", luat_remotem_typeopt_gpio},
    // {"uart", luat_remotem_typeopt_uart},
    {"indev", luat_remotem_typeopt_indev},
    {NULL, NULL}
};

void luat_remotem_init(int argc, char** argv) {

    // 解析命令行参数
    int c;
    int digit_optind = 0;
    int aopt = 0, bopt = 0;
    char *copt = 0, *dopt = 0;
    static struct option long_options[] = {
    /*   NAME           ARGUMENT           FLAG  SHORTNAME */
        {"bsp",             required_argument, NULL, 0},
        {"selfid",          required_argument, NULL, 0},
        {"sessionid",       required_argument, NULL, 0},
        {"mqtt.host",       required_argument, NULL, 0},
        {"mqtt.port",       required_argument, NULL, 0},
        {"mqtt.clientid",   required_argument, NULL, 0},
        {"mqtt.user",       required_argument, NULL, 0},
        {"mqtt.password",   required_argument, NULL, 0},
        {"wait",            required_argument, NULL, 0},
        {NULL,      0,                 NULL, 0}
    };
    int option_index = 0;
    while ((c = getopt_long(argc, argv, "d",
                long_options, &option_index)) != -1) {
        int this_option_optind = optind ? optind : 1;
        switch (c) {
        case 0:
            //printf ("option %s", long_options[option_index].name);
            if (!strcmp("bsp", long_options[option_index].name)) {
                strcpy(rctx.bsp, optarg);
            }
            else if (!strcmp("selfid", long_options[option_index].name)) {
                strcpy(rctx.self_id, optarg);
            }
            else if (!strcmp("sessionid", long_options[option_index].name)) {
                strcpy(rctx.session_id, optarg);
            }
            else if (!strcmp("wait", long_options[option_index].name)) {
                rctx.wait = atoi(optarg);
            }
            else if (!strcmp("mqtt.host", long_options[option_index].name)) {
                strcpy(rctx.mqtt.host, optarg);
            }
            else if (!strcmp("mqtt.port", long_options[option_index].name)) {
                rctx.mqtt.port = atoi(optarg);
            }
            else if (!strcmp("mqtt.user", long_options[option_index].name)) {
                strcpy(rctx.mqtt.user, optarg);
            }
            else if (!strcmp("mqtt.password", long_options[option_index].name)) {
                strcpy(rctx.mqtt.password, optarg);
            }
            else if (!strcmp("mqtt.protocol", long_options[option_index].name)) {
                strcpy(rctx.mqtt.protocol, optarg);
            }
            break;
        case 'd':
            break;
        }
    }

    // 修正部分默认参数,确保值是合法的
    HCRYPTPROV   hCryptProv = 0;
    BYTE         pbData[16];
    if (strlen(rctx.self_id) < 1) {
        CryptGenRandom(hCryptProv, 8, pbData);
        luat_str_tohex(pbData, 8, rctx.self_id);
        rctx.self_id[16] = 0x00;
    }
    if (strlen(rctx.session_id) < 1) {
        strcpy(rctx.session_id, rctx.self_id);
    }

    if (strlen(rctx.mqtt.topic_downlink) < 1) {
        sprintf(rctx.mqtt.topic_downlink, "/sys/luatos/emulator/%s/down", rctx.self_id);
    }
    if (strlen(rctx.mqtt.topic_uplink) < 1) {
        sprintf(rctx.mqtt.topic_uplink, "/sys/luatos/emulator/%s/up", rctx.self_id);
    }

#if 1
    printf("bsp        %s\n", rctx.bsp);
    // printf("self id    %s\n", rctx.self_id);
    printf("session id %s\n", rctx.session_id);
    printf("mqtt url %s://%s:%d\n", rctx.mqtt.protocol, rctx.mqtt.host, rctx.mqtt.port);
    printf("mqtt uplink %s\n", rctx.mqtt.topic_uplink);
    printf("mqtt downlink %s\n", rctx.mqtt.topic_downlink);
#endif
}

void luat_remotem_set_uplink(luat_remotem_uplink_cb _uplink) {
    uplink = _uplink;
}

int luat_remotem_ready(void) {
    if (uplink == NULL) return 0;
    return 1;
}

static void handle_json(cJSON* top);

void luat_remotem_putbuff(char* buff, size_t len) {
    cJSON* top = cJSON_ParseWithLength((const char*)buff, len);
    if (top == NULL) {
        debug_printf("bad JSON income!!!");
        return;
    }
    handle_json(top);
    cJSON_Delete(top);
    return;
}

cJSON* luat_remotem_json_init(cJSON* top) {
    cJSON_AddNumberToObject(top, "version", 1);
    cJSON_AddStringToObject(top, "session", rctx.session_id);
    cJSON_AddStringToObject(top, "id",      rctx.self_id);
    cJSON_AddStringToObject(top, "role",    "client");
    return cJSON_AddObjectToObject(top,     "data");
}

int luat_remotem_up(cJSON* top) {
    if (uplink == NULL)
        return -1;
    char* json = cJSON_PrintUnformatted(top);
    uplink(json, strlen(json));
    cJSON_free(json);
    return 0;
}

static void handle_json(cJSON* top) {
    // 验证必要的顶层元素
    cJSON* id       = cJSON_GetObjectItem(top, "id");
    cJSON* type     = cJSON_GetObjectItem(top, "type");
    cJSON* session  = cJSON_GetObjectItem(top, "session");
    cJSON* version  = cJSON_GetObjectItem(top, "version");
    cJSON* role     = cJSON_GetObjectItem(top, "role");
    cJSON* data     = cJSON_GetObjectItem(top, "data");

    // 逐一检查是否存在
    if (id == NULL || id->type != cJSON_String) {
        debug_printf("json miss id\n");
        return;
    }
    if (type == NULL || type->type != cJSON_String) {
        debug_printf("json miss type\n");
        return;
    }
    if (session == NULL || session->type != cJSON_String) {
        debug_printf("json miss session\n");
        return;
    }
    if (version == NULL || version->type != cJSON_Number) {
        debug_printf("json miss version\n");
        return;
    }
    if (data == NULL) {
        debug_printf("json miss data\n");
        return;
    }

    // 对值进行校验
    if (version->valueint != 1) {
        debug_printf("bad version value\n");
        return;
    }

    // 进行type进行分类处理
    for (size_t i = 0; i < 256; i++)
    {
        if (opts[i].name == NULL) {
            printf("unknow json type %s\n", type->valuestring);
            break;
        }
        if (!strcmp(opts[i].name, type->valuestring)) {
            opts[i].typeopt(top, data);
            break;
        }
    }
    
}

