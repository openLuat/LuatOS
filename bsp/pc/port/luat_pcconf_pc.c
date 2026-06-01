
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_uart_drv.h"
#include "cJSON.h"

#include "luat_pcconf.h"

#define LUAT_LOG_TAG "pc"
#include "luat_log.h"

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#ifdef LUAT_USE_WINDOWS
#include <direct.h>
#endif

#define LUAT_PCCONF_DIR "pcconf"
#define LUAT_PCCONF_FILE "pcconf/pcconf.json"
#define LUAT_PCCONF_SCHEMA_VERSION 1
#define LUAT_PCCONF_WEB_PORT_DEFAULT 18080
#define LUAT_PCCONF_WEB_REFRESH_DEFAULT 5
#define LUAT_PCCONF_TF_CAP_MB_DEFAULT 64
#define LUAT_PCCONF_NOR_CAP_MB_DEFAULT 16
#define LUAT_PCCONF_NAND_CAP_MB_DEFAULT 128
#define LUAT_PCCONF_NOR_MODEL_DEFAULT "w25q128"
#define LUAT_PCCONF_NAND_MODEL_DEFAULT "w25n01gv"

luat_pcconf_t g_pcconf;
extern const luat_uart_drv_opts_t* uart_drvs[];
extern const luat_uart_drv_opts_t uart_udp;
extern const luat_uart_drv_opts_t uart_win32;
extern const luat_uart_drv_opts_t uart_linux;

int luat_uart_initial_win32();

static int luat_pcconf_host_dir_exists(const char* path) {
    struct stat st = {0};
    if (!path || stat(path, &st)) {
        return 0;
    }
    return (st.st_mode & S_IFDIR) != 0;
}

static int luat_pcconf_host_mkdir(const char* path) {
#ifdef LUAT_USE_WINDOWS
    return _mkdir(path);
#else
    return mkdir(path, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
#endif
}

static int luat_pcconf_ensure_dir(void) {
    if (luat_pcconf_host_dir_exists(LUAT_PCCONF_DIR)) {
        return 0;
    }
    if (luat_pcconf_host_mkdir(LUAT_PCCONF_DIR) == 0) {
        return 0;
    }
    if (luat_pcconf_host_dir_exists(LUAT_PCCONF_DIR)) {
        return 0;
    }
    return -1;
}

static void luat_pcconf_set_defaults(void) {
    memset(&g_pcconf, 0, sizeof(g_pcconf));
    g_pcconf.schema_version = LUAT_PCCONF_SCHEMA_VERSION;
    g_pcconf.mcu_mhz = 240;
    g_pcconf.mobile_csq = 20;
    g_pcconf.uart_udp_port_start = 9000;
    g_pcconf.uart_udp_id_start = 0;
    g_pcconf.uart_udp_id_count = 8;
    g_pcconf.web_console_enabled = 1;
    g_pcconf.web_console_port = LUAT_PCCONF_WEB_PORT_DEFAULT;
    g_pcconf.web_console_refresh_interval = LUAT_PCCONF_WEB_REFRESH_DEFAULT;
    g_pcconf.tf_enabled = 1;
    g_pcconf.nor_enabled = 1;
    g_pcconf.nand_enabled = 1;
    g_pcconf.tf_capacity_mb = LUAT_PCCONF_TF_CAP_MB_DEFAULT;
    g_pcconf.nor_capacity_mb = LUAT_PCCONF_NOR_CAP_MB_DEFAULT;
    g_pcconf.nand_capacity_mb = LUAT_PCCONF_NAND_CAP_MB_DEFAULT;
    strncpy(g_pcconf.nor_model, LUAT_PCCONF_NOR_MODEL_DEFAULT, sizeof(g_pcconf.nor_model) - 1);
    strncpy(g_pcconf.nand_model, LUAT_PCCONF_NAND_MODEL_DEFAULT, sizeof(g_pcconf.nand_model) - 1);
    g_pcconf.network_enabled = 1;
    g_pcconf.simulator_enabled = 1;
}

static char* luat_pcconf_read_all(size_t* out_len) {
    FILE* fd;
    long flen;
    size_t nread;
    char* buff;

    if (out_len) {
        *out_len = 0;
    }

    fd = fopen(LUAT_PCCONF_FILE, "rb");
    if (!fd) {
        return NULL;
    }
    if (fseek(fd, 0, SEEK_END)) {
        fclose(fd);
        return NULL;
    }
    flen = ftell(fd);
    if (flen <= 0) {
        fclose(fd);
        return NULL;
    }
    if (fseek(fd, 0, SEEK_SET)) {
        fclose(fd);
        return NULL;
    }

    buff = luat_heap_malloc((size_t)flen + 1);
    if (!buff) {
        fclose(fd);
        return NULL;
    }
    nread = fread(buff, 1, (size_t)flen, fd);
    fclose(fd);
    if (nread != (size_t)flen) {
        luat_heap_free(buff);
        return NULL;
    }
    buff[nread] = 0;
    if (out_len) {
        *out_len = nread;
    }
    return buff;
}

static int luat_pcconf_read_int(cJSON* obj, const char* key, int* out_value) {
    cJSON* item;
    if (!obj || !key || !out_value) {
        return 0;
    }
    item = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!item || !cJSON_IsNumber(item)) {
        return 0;
    }
    *out_value = item->valueint;
    return 1;
}

static void luat_pcconf_read_toggle(cJSON* obj, const char* key, uint8_t* out_value, int* migration) {
    int value = 0;
    if (!luat_pcconf_read_int(obj, key, &value)) {
        *migration = 1;
        return;
    }
    *out_value = value ? 1 : 0;
}

static void luat_pcconf_read_capacity(cJSON* obj, const char* key, uint16_t* out_value,
                                      uint16_t minv, uint16_t maxv, int* migration) {
    int value = 0;
    if (!luat_pcconf_read_int(obj, key, &value)) {
        *migration = 1;
        return;
    }
    if (value < minv) {
        value = minv;
    }
    if (value > maxv) {
        value = maxv;
    }
    *out_value = (uint16_t)value;
}

static void luat_pcconf_read_model(cJSON* obj, const char* key, char* out_value,
                                   size_t out_len, const char* fallback, int* migration) {
    cJSON* item;
    if (!obj || !key || !out_value || out_len < 2) {
        return;
    }
    item = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (!item || !cJSON_IsString(item) || !item->valuestring || item->valuestring[0] == 0) {
        strncpy(out_value, fallback, out_len - 1);
        out_value[out_len - 1] = 0;
        *migration = 1;
        return;
    }
    strncpy(out_value, item->valuestring, out_len - 1);
    out_value[out_len - 1] = 0;
}

static int luat_pcconf_load_json(const char* json_data) {
    cJSON* root;
    cJSON* web;
    cJSON* storage;
    cJSON* network;
    cJSON* simulator;
    int migration = 0;
    int value = 0;

    root = cJSON_Parse(json_data);
    if (!root || !cJSON_IsObject(root)) {
        if (root) {
            cJSON_Delete(root);
        }
        return -1;
    }

    if (luat_pcconf_read_int(root, "schema_version", &value) && value > 0) {
        g_pcconf.schema_version = (size_t)value;
    }
    else {
        migration = 1;
    }

    if (luat_pcconf_read_int(root, "mcu_mhz", &value) && value > 0) {
        g_pcconf.mcu_mhz = (size_t)value;
    }
    if (luat_pcconf_read_int(root, "uart_udp_port_start", &value) && value >= 0) {
        g_pcconf.uart_udp_port_start = (size_t)value;
    }
    if (luat_pcconf_read_int(root, "uart_udp_id_start", &value) && value >= 0) {
        g_pcconf.uart_udp_id_start = (size_t)value;
    }
    if (luat_pcconf_read_int(root, "uart_udp_id_count", &value) && value > 0) {
        g_pcconf.uart_udp_id_count = (size_t)value;
    }

    web = cJSON_GetObjectItemCaseSensitive(root, "web_console");
    if (web && cJSON_IsObject(web)) {
        if (luat_pcconf_read_int(web, "enabled", &value)) {
            g_pcconf.web_console_enabled = value ? 1 : 0;
        }
        else {
            migration = 1;
        }
        if (luat_pcconf_read_int(web, "port", &value) && value > 0 && value <= 65535) {
            g_pcconf.web_console_port = (uint16_t)value;
        }
        else {
            migration = 1;
        }
        if (luat_pcconf_read_int(web, "refresh_interval", &value) && (value == 1 || value == 5 || value == 15)) {
            g_pcconf.web_console_refresh_interval = (uint8_t)value;
        }
        else {
            migration = 1;
        }
    }
    else {
        migration = 1;
    }

    storage = cJSON_GetObjectItemCaseSensitive(root, "storage");
    if (storage && cJSON_IsObject(storage)) {
        luat_pcconf_read_toggle(storage, "tf_enabled", &g_pcconf.tf_enabled, &migration);
        luat_pcconf_read_toggle(storage, "nor_enabled", &g_pcconf.nor_enabled, &migration);
        luat_pcconf_read_toggle(storage, "nand_enabled", &g_pcconf.nand_enabled, &migration);
        luat_pcconf_read_capacity(storage, "tf_capacity_mb", &g_pcconf.tf_capacity_mb, 1, 2048, &migration);
        luat_pcconf_read_capacity(storage, "nor_capacity_mb", &g_pcconf.nor_capacity_mb, 1, 512, &migration);
        luat_pcconf_read_capacity(storage, "nand_capacity_mb", &g_pcconf.nand_capacity_mb, 1, 2048, &migration);
        luat_pcconf_read_model(storage, "nor_model", g_pcconf.nor_model, sizeof(g_pcconf.nor_model), LUAT_PCCONF_NOR_MODEL_DEFAULT, &migration);
        luat_pcconf_read_model(storage, "nand_model", g_pcconf.nand_model, sizeof(g_pcconf.nand_model), LUAT_PCCONF_NAND_MODEL_DEFAULT, &migration);
    }
    else {
        migration = 1;
    }

    network = cJSON_GetObjectItemCaseSensitive(root, "network");
    if (network && cJSON_IsObject(network)) {
        luat_pcconf_read_toggle(network, "enabled", &g_pcconf.network_enabled, &migration);
    }
    else {
        migration = 1;
    }

    simulator = cJSON_GetObjectItemCaseSensitive(root, "simulator");
    if (simulator && cJSON_IsObject(simulator)) {
        luat_pcconf_read_toggle(simulator, "enabled", &g_pcconf.simulator_enabled, &migration);
    }
    else {
        migration = 1;
    }

    if (g_pcconf.schema_version != LUAT_PCCONF_SCHEMA_VERSION) {
        g_pcconf.schema_version = LUAT_PCCONF_SCHEMA_VERSION;
        migration = 1;
    }

    cJSON_Delete(root);
    return migration;
}

static int luat_pcconf_load(void) {
    size_t json_len = 0;
    char* json_data;
    int ret;
    (void)json_len;

    luat_pcconf_set_defaults();
    json_data = luat_pcconf_read_all(&json_len);
    if (!json_data) {
        return -1;
    }
    ret = luat_pcconf_load_json(json_data);
    luat_heap_free(json_data);
    return ret;
}

void luat_pcconf_init(void) {
    int save_after_init = 0;

    if (luat_pcconf_ensure_dir()) {
        LLOGW("pcconf目录创建失败");
        luat_pcconf_set_defaults();
    }
    else {
        int load_ret = luat_pcconf_load();
        if (load_ret < 0) {
            LLOGW("pcconf加载失败, 使用默认值");
            save_after_init = 1;
        }
        else if (load_ret > 0) {
            save_after_init = 1;
        }
    }

    if (save_after_init) {
        luat_pcconf_save();
    }

    #ifdef LUA_USE_WINDOWS
    // LLOGD("执行uart_win32初始化");
    if (luat_uart_initial_win32() == 0) {
        for (size_t i = 0; i < 128; i++)
        {
            uart_drvs[i] = &uart_win32;
        }
        // LLOGD("执行uart_win32初始化成功, 驱动已注册 %p", uart_drvs[1]);
        return;
    }
    #endif
    #ifdef LUA_USE_LINUX
    for (size_t i = 0; i < 128; i++)
    {
        uart_drvs[i] = &uart_linux;
    }
    return;
    #endif
    for (size_t i = 0; i < 128; i++)
    {
        uart_drvs[i] = &uart_udp;
    }
}

void luat_pcconf_save(void) {
    FILE* fd;
    cJSON* root;
    cJSON* web;
    cJSON* storage;
    cJSON* network;
    cJSON* simulator;
    char* str;

    if (luat_pcconf_ensure_dir()) {
        LLOGW("pcconf目录创建失败, 跳过保存");
        return;
    }

    root = cJSON_CreateObject();
    if (!root) {
        return;
    }

    cJSON_AddNumberToObject(root, "schema_version", (double)LUAT_PCCONF_SCHEMA_VERSION);
    cJSON_AddNumberToObject(root, "mcu_mhz", (double)g_pcconf.mcu_mhz);
    cJSON_AddNumberToObject(root, "uart_udp_port_start", (double)g_pcconf.uart_udp_port_start);
    cJSON_AddNumberToObject(root, "uart_udp_id_start", (double)g_pcconf.uart_udp_id_start);
    cJSON_AddNumberToObject(root, "uart_udp_id_count", (double)g_pcconf.uart_udp_id_count);

    web = cJSON_CreateObject();
    storage = cJSON_CreateObject();
    network = cJSON_CreateObject();
    simulator = cJSON_CreateObject();
    if (!web || !storage || !network || !simulator) {
        cJSON_Delete(root);
        return;
    }

    cJSON_AddItemToObject(root, "web_console", web);
    cJSON_AddItemToObject(root, "storage", storage);
    cJSON_AddItemToObject(root, "network", network);
    cJSON_AddItemToObject(root, "simulator", simulator);

    cJSON_AddNumberToObject(web, "enabled", (double)g_pcconf.web_console_enabled);
    cJSON_AddNumberToObject(web, "port", (double)g_pcconf.web_console_port);
    cJSON_AddNumberToObject(web, "refresh_interval", (double)g_pcconf.web_console_refresh_interval);

    cJSON_AddNumberToObject(storage, "tf_enabled", (double)g_pcconf.tf_enabled);
    cJSON_AddNumberToObject(storage, "nor_enabled", (double)g_pcconf.nor_enabled);
    cJSON_AddNumberToObject(storage, "nand_enabled", (double)g_pcconf.nand_enabled);
    cJSON_AddNumberToObject(storage, "tf_capacity_mb", (double)g_pcconf.tf_capacity_mb);
    cJSON_AddNumberToObject(storage, "nor_capacity_mb", (double)g_pcconf.nor_capacity_mb);
    cJSON_AddNumberToObject(storage, "nand_capacity_mb", (double)g_pcconf.nand_capacity_mb);
    cJSON_AddStringToObject(storage, "nor_model", g_pcconf.nor_model);
    cJSON_AddStringToObject(storage, "nand_model", g_pcconf.nand_model);

    cJSON_AddNumberToObject(network, "enabled", (double)g_pcconf.network_enabled);
    cJSON_AddNumberToObject(simulator, "enabled", (double)g_pcconf.simulator_enabled);

    str = cJSON_Print(root);
    cJSON_Delete(root);
    if (!str) {
        return;
    }

    fd = fopen(LUAT_PCCONF_FILE, "wb");
    if (!fd) {
        cJSON_free(str);
        return;
    }
    fwrite(str, 1, strlen(str), fd);
    fclose(fd);
    cJSON_free(str);

}

const luat_pcconf_t* luat_pcconf_get(void) {
    return &g_pcconf;
}

int luat_pcconf_update_web_console(int enabled, int port, int refresh_interval, int persist) {
    int changed = 0;
    if (enabled >= 0) {
        uint8_t next = enabled ? 1 : 0;
        if (g_pcconf.web_console_enabled != next) {
            g_pcconf.web_console_enabled = next;
            changed = 1;
        }
    }
    if (port >= 0) {
        if (port < 1 || port > 65535) {
            return -1;
        }
        if (g_pcconf.web_console_port != (uint16_t)port) {
            g_pcconf.web_console_port = (uint16_t)port;
            changed = 1;
        }
    }
    if (refresh_interval >= 0) {
        if (refresh_interval != 1 && refresh_interval != 5 && refresh_interval != 15) {
            return -1;
        }
        if (g_pcconf.web_console_refresh_interval != (uint8_t)refresh_interval) {
            g_pcconf.web_console_refresh_interval = (uint8_t)refresh_interval;
            changed = 1;
        }
    }
    if (changed && persist) {
        luat_pcconf_save();
    }
    return changed;
}

int luat_pcconf_update_network(int enabled, int persist) {
    int changed = 0;
    if (enabled >= 0) {
        uint8_t next = enabled ? 1 : 0;
        if (g_pcconf.network_enabled != next) {
            g_pcconf.network_enabled = next;
            changed = 1;
        }
    }
    if (changed && persist) {
        luat_pcconf_save();
    }
    return changed;
}

int luat_pcconf_update_storage(int tf_enabled, int nor_enabled, int nand_enabled,
                               int tf_capacity_mb, int nor_capacity_mb, int nand_capacity_mb,
                               const char* nor_model, const char* nand_model, int persist) {
    int changed = 0;

    if (tf_enabled >= 0) {
        uint8_t next = tf_enabled ? 1 : 0;
        if (g_pcconf.tf_enabled != next) {
            g_pcconf.tf_enabled = next;
            changed = 1;
        }
    }
    if (nor_enabled >= 0) {
        uint8_t next = nor_enabled ? 1 : 0;
        if (g_pcconf.nor_enabled != next) {
            g_pcconf.nor_enabled = next;
            changed = 1;
        }
    }
    if (nand_enabled >= 0) {
        uint8_t next = nand_enabled ? 1 : 0;
        if (g_pcconf.nand_enabled != next) {
            g_pcconf.nand_enabled = next;
            changed = 1;
        }
    }

    if (tf_capacity_mb >= 0) {
        if (tf_capacity_mb < 1 || tf_capacity_mb > 2048) {
            return -1;
        }
        if (g_pcconf.tf_capacity_mb != (uint16_t)tf_capacity_mb) {
            g_pcconf.tf_capacity_mb = (uint16_t)tf_capacity_mb;
            changed = 1;
        }
    }
    if (nor_capacity_mb >= 0) {
        if (nor_capacity_mb < 1 || nor_capacity_mb > 512) {
            return -1;
        }
        if (g_pcconf.nor_capacity_mb != (uint16_t)nor_capacity_mb) {
            g_pcconf.nor_capacity_mb = (uint16_t)nor_capacity_mb;
            changed = 1;
        }
    }
    if (nand_capacity_mb >= 0) {
        if (nand_capacity_mb < 1 || nand_capacity_mb > 2048) {
            return -1;
        }
        if (g_pcconf.nand_capacity_mb != (uint16_t)nand_capacity_mb) {
            g_pcconf.nand_capacity_mb = (uint16_t)nand_capacity_mb;
            changed = 1;
        }
    }

    if (nor_model && nor_model[0]) {
        char next[sizeof(g_pcconf.nor_model)] = {0};
        strncpy(next, nor_model, sizeof(next) - 1);
        if (strcmp(g_pcconf.nor_model, next)) {
            memcpy(g_pcconf.nor_model, next, sizeof(next));
            changed = 1;
        }
    }
    if (nand_model && nand_model[0]) {
        char next[sizeof(g_pcconf.nand_model)] = {0};
        strncpy(next, nand_model, sizeof(next) - 1);
        if (strcmp(g_pcconf.nand_model, next)) {
            memcpy(g_pcconf.nand_model, next, sizeof(next));
            changed = 1;
        }
    }

    if (changed && persist) {
        luat_pcconf_save();
    }
    return changed;
}
