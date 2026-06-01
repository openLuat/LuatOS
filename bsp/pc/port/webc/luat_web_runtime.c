#include "luat_base.h"
#include "luat_posix_compat.h"
#include "luat_web_runtime.h"
#include "luat_web_gnss_uart32.h"
#include "luat_pcconf.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_uart.h"
#include "luat_uart31_console.h"
#include "luat_webc_codec.h"
#include "luat_i2c_pc_mock.h"
#include "cJSON.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>

#if defined(_WIN32) || defined(_WIN64)
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
typedef SOCKET web_fd_t;
#define WEB_INVALID_FD INVALID_SOCKET
#define web_close closesocket
#define web_errno WSAGetLastError()
#define web_send(fd, buf, len) send(fd, (const char*)(buf), (int)(len), 0)
#define web_recv(fd, buf, len) recv(fd, (char*)(buf), (int)(len), 0)
#define web_sleep_ms(ms) Sleep((DWORD)(ms))
typedef HANDLE web_thread_t;
typedef CRITICAL_SECTION web_mutex_t;
static void web_mutex_init(web_mutex_t* m) { InitializeCriticalSection(m); }
static void web_mutex_lock(web_mutex_t* m) { EnterCriticalSection(m); }
static void web_mutex_unlock(web_mutex_t* m) { LeaveCriticalSection(m); }
static void web_mutex_deinit(web_mutex_t* m) { DeleteCriticalSection(m); }
#else
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/select.h>
typedef int web_fd_t;
#define WEB_INVALID_FD (-1)
#define web_close close
#define web_errno errno
#define web_send(fd, buf, len) send(fd, buf, len, 0)
#define web_recv(fd, buf, len) recv(fd, buf, len, 0)
#define web_sleep_ms(ms) usleep((useconds_t)((ms) * 1000))
typedef pthread_t web_thread_t;
typedef pthread_mutex_t web_mutex_t;
static void web_mutex_init(web_mutex_t* m) { pthread_mutex_init(m, NULL); }
static void web_mutex_lock(web_mutex_t* m) { pthread_mutex_lock(m); }
static void web_mutex_unlock(web_mutex_t* m) { pthread_mutex_unlock(m); }
static void web_mutex_deinit(web_mutex_t* m) { pthread_mutex_destroy(m); }
#endif

#define LUAT_LOG_TAG "pc.webc"
#include "luat_log.h"

#define WEB_REQ_MAX 8192
#define WEB_HISTORY_MAX 256
#define WEB_SSE_MAX 8
#define WEB_UI_ROOT "port/webc_ui"

typedef struct telemetry_entry {
    uint64_t ts_ms;
    uint64_t uptime_ms;
    size_t lua_total;
    size_t lua_used;
    size_t lua_peak;
    size_t sys_total;
    size_t sys_used;
    size_t sys_peak;
} telemetry_entry_t;

typedef struct web_runtime_ctx {
    volatile int running;
    int port;
    int cadence_sec;
    web_fd_t listen_fd;
    web_thread_t accept_thread;
    web_thread_t telemetry_thread;
    web_mutex_t lock;
    telemetry_entry_t history[WEB_HISTORY_MAX];
    int history_start;
    int history_count;
    web_fd_t sse_clients[WEB_SSE_MAX];
} web_runtime_ctx_t;

static web_runtime_ctx_t g_web_ctx = {0};

static int web_read_request(web_fd_t fd, char* req, size_t req_cap, size_t* out_len);
static void web_handle_request(web_fd_t fd, const char* req, size_t req_len);
static void web_send_json(web_fd_t fd, int code, cJSON* root);
static int web_send_static_asset(web_fd_t fd, const char* req_path);
static cJSON* web_make_status_json(void);
static cJSON* web_make_config_json(void);
static cJSON* web_make_telemetry_json(void);
static telemetry_entry_t web_capture_telemetry(void);
static void web_push_telemetry(const telemetry_entry_t* item);
static void web_broadcast_telemetry(const telemetry_entry_t* item);
static void web_sse_add_client(web_fd_t fd);
static void web_sse_remove_client_locked(int idx);
static cJSON* web_make_sht20_json(void);
static int web_apply_sht20_patch(const char* body);
static void web_handle_uart31_console(web_fd_t fd);
static void web_handle_uart31_inject(web_fd_t fd, const char* body);

#if defined(_WIN32) || defined(_WIN64)
static DWORD WINAPI web_accept_thread_main(LPVOID arg);
static DWORD WINAPI web_telemetry_thread_main(LPVOID arg);
static DWORD WINAPI web_client_thread_main(LPVOID arg);
#else
static void* web_accept_thread_main(void* arg);
static void* web_telemetry_thread_main(void* arg);
static void* web_client_thread_main(void* arg);
#endif

typedef struct web_client_arg {
    web_fd_t fd;
} web_client_arg_t;

static int web_send_all(web_fd_t fd, const char* data, size_t len) {
    size_t sent = 0;
    while (sent < len) {
        int ret = web_send(fd, data + sent, len - sent);
        if (ret <= 0) {
            return -1;
        }
        sent += (size_t)ret;
    }
    return 0;
}

static int web_read_request(web_fd_t fd, char* req, size_t req_cap, size_t* out_len) {
    size_t total = 0;
    int header_done = 0;
    size_t body_expect = 0;
    req[0] = 0;
    while (total + 1 < req_cap) {
        int n = web_recv(fd, req + total, req_cap - total - 1);
        if (n <= 0) {
            return -1;
        }
        total += (size_t)n;
        req[total] = 0;
        if (!header_done) {
            char* header_end = strstr(req, "\r\n\r\n");
            if (header_end) {
                header_done = 1;
                size_t header_len = (size_t)(header_end - req) + 4;
                char* cl = strstr(req, "Content-Length:");
                if (cl) {
                    body_expect = (size_t)strtoul(cl + strlen("Content-Length:"), NULL, 10);
                }
                if (total >= header_len + body_expect) {
                    break;
                }
            }
        }
        else {
            break;
        }
    }
    if (out_len) {
        *out_len = total;
    }
    return 0;
}

static cJSON* web_make_status_json(void) {
    const luat_pcconf_t* conf = luat_pcconf_get();
    telemetry_entry_t latest = {0};
    cJSON* root = cJSON_CreateObject();
    cJSON* mem = cJSON_CreateObject();
    if (!root || !mem) {
        if (root) cJSON_Delete(root);
        if (mem) cJSON_Delete(mem);
        return NULL;
    }
    web_mutex_lock(&g_web_ctx.lock);
    if (g_web_ctx.history_count > 0) {
        int idx = (g_web_ctx.history_start + g_web_ctx.history_count - 1) % WEB_HISTORY_MAX;
        latest = g_web_ctx.history[idx];
    }
    web_mutex_unlock(&g_web_ctx.lock);

    cJSON_AddBoolToObject(root, "ok", 1);
    cJSON_AddNumberToObject(root, "uptime_ms", (double)luat_mcu_tick64_ms());
    cJSON_AddNumberToObject(root, "port", g_web_ctx.port);
    cJSON_AddNumberToObject(root, "cadence_sec", g_web_ctx.cadence_sec);
    cJSON_AddNumberToObject(root, "history_count", g_web_ctx.history_count);
    cJSON_AddNumberToObject(root, "mcu_mhz", conf ? (double)conf->mcu_mhz : 0.0);
    cJSON_AddItemToObject(root, "memory", mem);
    cJSON_AddNumberToObject(mem, "lua_total", (double)latest.lua_total);
    cJSON_AddNumberToObject(mem, "lua_used", (double)latest.lua_used);
    cJSON_AddNumberToObject(mem, "lua_peak", (double)latest.lua_peak);
    cJSON_AddNumberToObject(mem, "sys_total", (double)latest.sys_total);
    cJSON_AddNumberToObject(mem, "sys_used", (double)latest.sys_used);
    cJSON_AddNumberToObject(mem, "sys_peak", (double)latest.sys_peak);
    return root;
}

static cJSON* web_make_config_json(void) {
    const luat_pcconf_t* conf = luat_pcconf_get();
    luat_pc_storage_effective_conf_t eff = {0};
    cJSON* root = cJSON_CreateObject();
    cJSON* web = cJSON_CreateObject();
    cJSON* network = cJSON_CreateObject();
    cJSON* storage = cJSON_CreateObject();
    cJSON* storage_effective = cJSON_CreateObject();
    if (!root || !web || !network || !storage || !storage_effective || !conf) {
        if (root) cJSON_Delete(root);
        if (web) cJSON_Delete(web);
        if (network) cJSON_Delete(network);
        if (storage) cJSON_Delete(storage);
        if (storage_effective) cJSON_Delete(storage_effective);
        return NULL;
    }
    cJSON_AddItemToObject(root, "web_console", web);
    cJSON_AddItemToObject(root, "network", network);
    cJSON_AddItemToObject(root, "storage", storage);
    cJSON_AddItemToObject(storage, "effective", storage_effective);
    cJSON_AddNumberToObject(web, "enabled", conf->web_console_enabled ? 1 : 0);
    cJSON_AddNumberToObject(web, "port", conf->web_console_port);
    cJSON_AddNumberToObject(web, "refresh_interval", conf->web_console_refresh_interval);
    cJSON_AddNumberToObject(web, "effective_port", g_web_ctx.port);
    cJSON_AddNumberToObject(web, "effective_refresh_interval", g_web_ctx.cadence_sec);
    cJSON_AddNumberToObject(network, "enabled", conf->network_enabled ? 1 : 0);

    cJSON_AddNumberToObject(storage, "tf_enabled", conf->tf_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage, "nor_enabled", conf->nor_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage, "nand_enabled", conf->nand_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage, "tf_capacity_mb", conf->tf_capacity_mb);
    cJSON_AddNumberToObject(storage, "nor_capacity_mb", conf->nor_capacity_mb);
    cJSON_AddNumberToObject(storage, "nand_capacity_mb", conf->nand_capacity_mb);
    cJSON_AddStringToObject(storage, "nor_model", conf->nor_model);
    cJSON_AddStringToObject(storage, "nand_model", conf->nand_model);

    luat_pc_storage_get_effective(&eff);
    cJSON_AddNumberToObject(storage_effective, "tf_enabled", eff.tf_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage_effective, "nor_enabled", eff.nor_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage_effective, "nand_enabled", eff.nand_enabled ? 1 : 0);
    cJSON_AddNumberToObject(storage_effective, "tf_capacity_mb", eff.tf_capacity_mb);
    cJSON_AddNumberToObject(storage_effective, "nor_capacity_mb", eff.nor_capacity_mb);
    cJSON_AddNumberToObject(storage_effective, "nand_capacity_mb", eff.nand_capacity_mb);
    cJSON_AddStringToObject(storage_effective, "nor_model", eff.nor_model);
    cJSON_AddStringToObject(storage_effective, "nand_model", eff.nand_model);
    return root;
}

static cJSON* web_make_telemetry_json(void) {
    cJSON* root = cJSON_CreateObject();
    cJSON* history = cJSON_CreateArray();
    if (!root || !history) {
        if (root) cJSON_Delete(root);
        if (history) cJSON_Delete(history);
        return NULL;
    }
    cJSON_AddNumberToObject(root, "cadence_sec", g_web_ctx.cadence_sec);
    cJSON_AddItemToObject(root, "history", history);

    web_mutex_lock(&g_web_ctx.lock);
    for (int i = 0; i < g_web_ctx.history_count; i++) {
        int idx = (g_web_ctx.history_start + i) % WEB_HISTORY_MAX;
        telemetry_entry_t* it = &g_web_ctx.history[idx];
        cJSON* item = cJSON_CreateObject();
        cJSON_AddNumberToObject(item, "ts_ms", (double)it->ts_ms);
        cJSON_AddNumberToObject(item, "uptime_ms", (double)it->uptime_ms);
        cJSON_AddNumberToObject(item, "lua_total", (double)it->lua_total);
        cJSON_AddNumberToObject(item, "lua_used", (double)it->lua_used);
        cJSON_AddNumberToObject(item, "sys_total", (double)it->sys_total);
        cJSON_AddNumberToObject(item, "sys_used", (double)it->sys_used);
        cJSON_AddItemToArray(history, item);
    }
    web_mutex_unlock(&g_web_ctx.lock);
    return root;
}

static void web_send_json(web_fd_t fd, int code, cJSON* root) {
    char* body = cJSON_PrintUnformatted(root);
    char header[256];
    const char* status = "200 OK";
    if (!body) {
        return;
    }
    if (code == 400) status = "400 Bad Request";
    else if (code == 404) status = "404 Not Found";
    else if (code == 500) status = "500 Internal Server Error";
    snprintf(header, sizeof(header),
             "HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %u\r\nConnection: close\r\n\r\n",
             status, (unsigned)strlen(body));
    web_send_all(fd, header, strlen(header));
    web_send_all(fd, body, strlen(body));
    cJSON_free(body);
}

static const char* web_static_mime_type(const char* path) {
    const char* ext = strrchr(path, '.');
    if (!ext) {
        return "text/plain; charset=utf-8";
    }
    if (!strcmp(ext, ".html")) return "text/html; charset=utf-8";
    if (!strcmp(ext, ".css")) return "text/css; charset=utf-8";
    if (!strcmp(ext, ".js")) return "application/javascript; charset=utf-8";
    if (!strcmp(ext, ".json")) return "application/json; charset=utf-8";
    if (!strcmp(ext, ".svg")) return "image/svg+xml";
    if (!strcmp(ext, ".ico")) return "image/x-icon";
    return "text/plain; charset=utf-8";
}

static int web_send_static_file(web_fd_t fd, const char* fs_path, const char* content_type) {
    FILE* fp;
    long flen;
    size_t nread;
    char* body;
    char header[256];
    fp = fopen(fs_path, "rb");
    if (!fp) {
        return -1;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return -1;
    }
    flen = ftell(fp);
    if (flen < 0) {
        fclose(fp);
        return -1;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return -1;
    }
    body = (char*)malloc((size_t)flen + 1);
    if (!body) {
        fclose(fp);
        return -1;
    }
    nread = fread(body, 1, (size_t)flen, fp);
    fclose(fp);
    if (nread != (size_t)flen) {
        free(body);
        return -1;
    }
    body[nread] = 0;
    snprintf(header, sizeof(header),
             "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %u\r\nConnection: close\r\n\r\n",
             content_type, (unsigned)nread);
    if (web_send_all(fd, header, strlen(header)) || web_send_all(fd, body, nread)) {
        free(body);
        return -1;
    }
    free(body);
    return 0;
}

static int web_send_static_asset(web_fd_t fd, const char* req_path) {
    char fs_path[256];
    const char* content_type;
    const char* path = req_path ? req_path : "/";
    if (!strcmp(path, "/") || !strcmp(path, "/index.html") || !strcmp(path, "/webc_ui") || !strcmp(path, "/webc_ui/")) {
        snprintf(fs_path, sizeof(fs_path), "%s/index.html", WEB_UI_ROOT);
        return web_send_static_file(fd, fs_path, "text/html; charset=utf-8");
    }
    if (!strncmp(path, "/webc_ui/", strlen("/webc_ui/"))) {
        snprintf(fs_path, sizeof(fs_path), "port/%s", path + 1);
        content_type = web_static_mime_type(fs_path);
        return web_send_static_file(fd, fs_path, content_type);
    }
    return -1;
}

static telemetry_entry_t web_capture_telemetry(void) {
    telemetry_entry_t item;
    memset(&item, 0, sizeof(item));
    item.ts_ms = luat_mcu_tick64_ms();
    item.uptime_ms = item.ts_ms;
    luat_meminfo_luavm(&item.lua_total, &item.lua_used, &item.lua_peak);
    luat_meminfo_sys(&item.sys_total, &item.sys_used, &item.sys_peak);
    return item;
}

static void web_push_telemetry(const telemetry_entry_t* item) {
    web_mutex_lock(&g_web_ctx.lock);
    if (g_web_ctx.history_count < WEB_HISTORY_MAX) {
        int idx = (g_web_ctx.history_start + g_web_ctx.history_count) % WEB_HISTORY_MAX;
        g_web_ctx.history[idx] = *item;
        g_web_ctx.history_count++;
    }
    else {
        g_web_ctx.history[g_web_ctx.history_start] = *item;
        g_web_ctx.history_start = (g_web_ctx.history_start + 1) % WEB_HISTORY_MAX;
    }
    web_mutex_unlock(&g_web_ctx.lock);
}

static void web_sse_remove_client_locked(int idx) {
    if (idx < 0 || idx >= WEB_SSE_MAX) {
        return;
    }
    if (g_web_ctx.sse_clients[idx] != WEB_INVALID_FD) {
        web_close(g_web_ctx.sse_clients[idx]);
        g_web_ctx.sse_clients[idx] = WEB_INVALID_FD;
    }
}

static void web_sse_add_client(web_fd_t fd) {
    int added = 0;
    web_mutex_lock(&g_web_ctx.lock);
    for (int i = 0; i < WEB_SSE_MAX; i++) {
        if (g_web_ctx.sse_clients[i] == WEB_INVALID_FD) {
            g_web_ctx.sse_clients[i] = fd;
            added = 1;
            break;
        }
    }
    web_mutex_unlock(&g_web_ctx.lock);
    if (!added) {
        web_close(fd);
    }
}

static void web_broadcast_telemetry(const telemetry_entry_t* item) {
    char payload[512];
    int n = snprintf(payload, sizeof(payload),
                     "event: telemetry\r\ndata:{\"ts_ms\":%llu,\"uptime_ms\":%llu,\"lua_used\":%u,\"sys_used\":%u}\r\n\r\n",
                     (unsigned long long)item->ts_ms,
                     (unsigned long long)item->uptime_ms,
                     (unsigned)item->lua_used,
                     (unsigned)item->sys_used);
    if (n <= 0) {
        return;
    }
    web_mutex_lock(&g_web_ctx.lock);
    for (int i = 0; i < WEB_SSE_MAX; i++) {
        if (g_web_ctx.sse_clients[i] == WEB_INVALID_FD) {
            continue;
        }
        if (web_send_all(g_web_ctx.sse_clients[i], payload, (size_t)n)) {
            web_sse_remove_client_locked(i);
        }
    }
    web_mutex_unlock(&g_web_ctx.lock);
}

static cJSON* web_make_sht20_json(void) {
    cJSON* root;
    double temp = 0;
    double humi = 0;
    root = cJSON_CreateObject();
    if (root == NULL) {
        return NULL;
    }
    luat_i2c_pc_sht20_get_measurement(&temp, &humi);
    cJSON_AddBoolToObject(root, "ok", 1);
    cJSON_AddNumberToObject(root, "temperature_c", temp);
    cJSON_AddNumberToObject(root, "humidity_rh", humi);
    cJSON_AddNumberToObject(root, "user_reg", (double)luat_i2c_pc_sht20_get_user_reg());
    return root;
}

static int web_apply_sht20_patch(const char* body) {
    cJSON* root;
    cJSON* temp;
    cJSON* humi;
    double new_temp;
    double new_humi;
    int has_value = 0;
    root = cJSON_Parse(body ? body : "");
    temp = NULL;
    humi = NULL;
    if (!root || !cJSON_IsObject(root)) {
        if (root) {
            cJSON_Delete(root);
        }
        return -1;
    }
    luat_i2c_pc_sht20_get_measurement(&new_temp, &new_humi);
    temp = cJSON_GetObjectItemCaseSensitive(root, "temperature_c");
    humi = cJSON_GetObjectItemCaseSensitive(root, "humidity_rh");
    if (temp && cJSON_IsNumber(temp)) {
        new_temp = temp->valuedouble;
        has_value = 1;
    }
    if (humi && cJSON_IsNumber(humi)) {
        new_humi = humi->valuedouble;
        has_value = 1;
    }
    cJSON_Delete(root);
    if (!has_value) {
        return -1;
    }
    return luat_i2c_pc_sht20_set_measurement(new_temp, new_humi);
}

static int web_apply_config_patch(const char* body) {
    cJSON* root = cJSON_Parse(body ? body : "");
    cJSON* web;
    cJSON* network;
    cJSON* storage;
    int enabled = -1;
    int port = -1;
    int refresh = -1;
    int network_enabled = -1;
    int tf_enabled = -1;
    int nor_enabled = -1;
    int nand_enabled = -1;
    int tf_capacity_mb = -1;
    int nor_capacity_mb = -1;
    int nand_capacity_mb = -1;
    const char* nor_model = NULL;
    const char* nand_model = NULL;
    int changed_web;
    int changed_storage;
    if (!root) {
        return -1;
    }
    web = cJSON_GetObjectItemCaseSensitive(root, "web_console");
    if (!web || !cJSON_IsObject(web)) {
        web = root;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(web, "enabled"))) {
        enabled = cJSON_GetObjectItemCaseSensitive(web, "enabled")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(web, "port"))) {
        port = cJSON_GetObjectItemCaseSensitive(web, "port")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(web, "refresh_interval"))) {
        refresh = cJSON_GetObjectItemCaseSensitive(web, "refresh_interval")->valueint;
    }
    network = cJSON_GetObjectItemCaseSensitive(root, "network");
    if (!network || !cJSON_IsObject(network)) {
        network = root;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(network, "enabled"))) {
        network_enabled = cJSON_GetObjectItemCaseSensitive(network, "enabled")->valueint;
    }
    storage = cJSON_GetObjectItemCaseSensitive(root, "storage");
    if (!storage || !cJSON_IsObject(storage)) {
        storage = root;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "tf_enabled"))) {
        tf_enabled = cJSON_GetObjectItemCaseSensitive(storage, "tf_enabled")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "nor_enabled"))) {
        nor_enabled = cJSON_GetObjectItemCaseSensitive(storage, "nor_enabled")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "nand_enabled"))) {
        nand_enabled = cJSON_GetObjectItemCaseSensitive(storage, "nand_enabled")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "tf_capacity_mb"))) {
        tf_capacity_mb = cJSON_GetObjectItemCaseSensitive(storage, "tf_capacity_mb")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "nor_capacity_mb"))) {
        nor_capacity_mb = cJSON_GetObjectItemCaseSensitive(storage, "nor_capacity_mb")->valueint;
    }
    if (cJSON_IsNumber(cJSON_GetObjectItemCaseSensitive(storage, "nand_capacity_mb"))) {
        nand_capacity_mb = cJSON_GetObjectItemCaseSensitive(storage, "nand_capacity_mb")->valueint;
    }
    if (cJSON_IsString(cJSON_GetObjectItemCaseSensitive(storage, "nor_model"))) {
        nor_model = cJSON_GetObjectItemCaseSensitive(storage, "nor_model")->valuestring;
    }
    if (cJSON_IsString(cJSON_GetObjectItemCaseSensitive(storage, "nand_model"))) {
        nand_model = cJSON_GetObjectItemCaseSensitive(storage, "nand_model")->valuestring;
    }

    changed_web = luat_pcconf_update_web_console(enabled, port, refresh, 1);
    if (luat_pcconf_update_network(network_enabled, 1) < 0) {
        cJSON_Delete(root);
        return -1;
    }
    changed_storage = luat_pcconf_update_storage(tf_enabled, nor_enabled, nand_enabled,
                                                 tf_capacity_mb, nor_capacity_mb, nand_capacity_mb,
                                                 nor_model, nand_model, 1);
    if (changed_web < 0 || changed_storage < 0) {
        cJSON_Delete(root);
        return -1;
    }
    if (refresh > 0) {
        luat_web_runtime_set_cadence(refresh);
    }
    cJSON_Delete(root);
    return (changed_web || changed_storage) ? 1 : 0;
}

typedef struct web_uart31_json_ctx {
    cJSON* items;
} web_uart31_json_ctx_t;

static void web_uart31_history_to_json(int is_tx, uint64_t ts_ms, const uint8_t* data, size_t len, void* userdata) {
    web_uart31_json_ctx_t* ctx = (web_uart31_json_ctx_t*)userdata;
    cJSON* item = cJSON_CreateObject();
    char* text_utf8 = luat_webc_encode_utf8_display(data, len);
    char* text_hex = luat_webc_encode_hex_escape(data, len);
    if (!ctx || !ctx->items || !item) {
        if (item) cJSON_Delete(item);
        if (text_utf8) luat_heap_free(text_utf8);
        if (text_hex) luat_heap_free(text_hex);
        return;
    }
    cJSON_AddStringToObject(item, "direction", is_tx ? "tx" : "rx");
    cJSON_AddNumberToObject(item, "ts_ms", (double)ts_ms);
    cJSON_AddNumberToObject(item, "len", (double)len);
    cJSON_AddStringToObject(item, "payload_utf8", text_utf8 ? text_utf8 : "");
    cJSON_AddStringToObject(item, "payload_hex", text_hex ? text_hex : "");
    cJSON_AddItemToArray(ctx->items, item);
    if (text_utf8) luat_heap_free(text_utf8);
    if (text_hex) luat_heap_free(text_hex);
}

static void web_handle_uart31_console(web_fd_t fd) {
    cJSON* root = cJSON_CreateObject();
    cJSON* items = cJSON_CreateArray();
    web_uart31_json_ctx_t ctx = {0};
    if (!root || !items) {
        if (root) cJSON_Delete(root);
        if (items) cJSON_Delete(items);
        return;
    }
    luat_uart31_console_mount();
    ctx.items = items;
    luat_uart31_console_visit_history(web_uart31_history_to_json, &ctx);
    cJSON_AddBoolToObject(root, "ok", 1);
    cJSON_AddItemToObject(root, "items", items);
    web_send_json(fd, 200, root);
    cJSON_Delete(root);
}

static void web_handle_uart31_inject(web_fd_t fd, const char* body) {
    cJSON* req = cJSON_Parse(body ? body : "");
    cJSON* root = cJSON_CreateObject();
    const char* direction;
    const char* encoding;
    const char* payload;
    const char* errmsg = "bad request";
    uint8_t* data = NULL;
    size_t len = 0;
    int ret = -1;
    if (!req || !root) {
        if (req) cJSON_Delete(req);
        if (root) cJSON_Delete(root);
        return;
    }
    luat_uart31_console_mount();
    direction = cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(req, "direction"));
    encoding = cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(req, "encoding"));
    payload = cJSON_GetStringValue(cJSON_GetObjectItemCaseSensitive(req, "payload"));
    if (!direction || !encoding || !payload) {
        cJSON_AddBoolToObject(root, "ok", 0);
        cJSON_AddStringToObject(root, "error", "direction/encoding/payload required");
        web_send_json(fd, 400, root);
        cJSON_Delete(req);
        cJSON_Delete(root);
        return;
    }
    if (luat_webc_decode_payload(encoding, payload, &data, &len, &errmsg)) {
        cJSON_AddBoolToObject(root, "ok", 0);
        cJSON_AddStringToObject(root, "error", errmsg ? errmsg : "decode failed");
        web_send_json(fd, 400, root);
        cJSON_Delete(req);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(direction, "rx")) {
        ret = luat_uart31_console_inject_rx(data, len);
    }
    else if (!strcmp(direction, "tx")) {
        ret = luat_uart_write(31, data, len);
    }
    else {
        errmsg = "direction must be rx or tx";
    }
    if (data) {
        luat_heap_free(data);
    }
    if (ret < 0) {
        cJSON_AddBoolToObject(root, "ok", 0);
        cJSON_AddStringToObject(root, "error", errmsg ? errmsg : "inject failed");
        web_send_json(fd, 400, root);
    }
    else {
        cJSON_AddBoolToObject(root, "ok", 1);
        cJSON_AddNumberToObject(root, "len", (double)ret);
        web_send_json(fd, 200, root);
    }
    cJSON_Delete(req);
    cJSON_Delete(root);
}

static void web_handle_request(web_fd_t fd, const char* req, size_t req_len) {
    char method[16] = {0};
    char path[128] = {0};
    char* body;
    (void)req_len;
    if (sscanf(req, "%15s %127s", method, path) != 2) {
        cJSON* err = cJSON_CreateObject();
        cJSON_AddStringToObject(err, "error", "bad request");
        web_send_json(fd, 400, err);
        cJSON_Delete(err);
        return;
    }
    body = strstr((char*)req, "\r\n\r\n");
    body = body ? body + 4 : NULL;

    if (!strcmp(method, "GET") && !strcmp(path, "/api/health")) {
        cJSON* root = cJSON_CreateObject();
        cJSON_AddBoolToObject(root, "ok", 1);
        cJSON_AddStringToObject(root, "service", "web-runtime-core");
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/status")) {
        cJSON* root = web_make_status_json();
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/config")) {
        cJSON* root = web_make_config_json();
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/telemetry")) {
        cJSON* root = web_make_telemetry_json();
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/uart31/console")) {
        web_handle_uart31_console(fd);
        return;
    }
    if (!strcmp(method, "POST") && !strcmp(path, "/api/uart31/inject")) {
        web_handle_uart31_inject(fd, body);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/mock/sht20")) {
        cJSON* root = web_make_sht20_json();
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "POST") && !strcmp(path, "/api/config")) {
        cJSON* root = cJSON_CreateObject();
        if (web_apply_config_patch(body) < 0) {
            cJSON_AddBoolToObject(root, "ok", 0);
            cJSON_AddStringToObject(root, "error", "invalid config");
            web_send_json(fd, 400, root);
        }
        else {
            cJSON_AddBoolToObject(root, "ok", 1);
            cJSON* conf = web_make_config_json();
            cJSON_AddItemToObject(root, "config", conf);
            web_send_json(fd, 200, root);
        }
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "POST") && !strcmp(path, "/api/mock/sht20")) {
        cJSON* root = cJSON_CreateObject();
        if (web_apply_sht20_patch(body) < 0) {
            cJSON_AddBoolToObject(root, "ok", 0);
            cJSON_AddStringToObject(root, "error", "invalid mock payload");
            web_send_json(fd, 400, root);
        }
        else {
            cJSON_Delete(root);
            root = web_make_sht20_json();
            web_send_json(fd, 200, root);
        }
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/events")) {
        const char* header = "HTTP/1.1 200 OK\r\n"
                             "Content-Type: text/event-stream\r\n"
                             "Cache-Control: no-cache\r\n"
                             "Connection: keep-alive\r\n\r\n";
        telemetry_entry_t item = web_capture_telemetry();
        char first[512];
        int n;
        if (web_send_all(fd, header, strlen(header))) {
            return;
        }
        n = snprintf(first, sizeof(first),
                     "event: telemetry\r\ndata:{\"ts_ms\":%llu,\"uptime_ms\":%llu,\"lua_used\":%u,\"sys_used\":%u}\r\n\r\n",
                     (unsigned long long)item.ts_ms,
                     (unsigned long long)item.uptime_ms,
                     (unsigned)item.lua_used,
                     (unsigned)item.sys_used);
        if (n <= 0 || web_send_all(fd, first, (size_t)n)) {
            return;
        }
        web_sse_add_client(fd);
        return;
    }
    if (!strcmp(method, "GET") && !strcmp(path, "/api/uart32/gnss")) {
        cJSON* root = luat_web_gnss_uart32_make_status_json();
        web_send_json(fd, 200, root);
        cJSON_Delete(root);
        return;
    }
    if (!strcmp(method, "POST") && !strcmp(path, "/api/uart32/gnss/config")) {
        cJSON* root = cJSON_CreateObject();
        if (luat_web_gnss_uart32_apply_config(body) < 0) {
            cJSON_AddBoolToObject(root, "ok", 0);
            cJSON_AddStringToObject(root, "error", "invalid gnss config");
            web_send_json(fd, 400, root);
        }
        else {
            cJSON_Delete(root);
            root = luat_web_gnss_uart32_make_status_json();
            web_send_json(fd, 200, root);
        }
        cJSON_Delete(root);
        return;
    }

    if (!strcmp(method, "GET")) {
        if (web_send_static_asset(fd, path) == 0) {
            return;
        }
    }

    cJSON* root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "error", "not found");
    web_send_json(fd, 404, root);
    cJSON_Delete(root);
}

#if defined(_WIN32) || defined(_WIN64)
static DWORD WINAPI web_client_thread_main(LPVOID arg)
#else
static void* web_client_thread_main(void* arg)
#endif
{
    web_client_arg_t* c = (web_client_arg_t*)arg;
    char req[WEB_REQ_MAX];
    size_t req_len = 0;
    web_fd_t fd = c->fd;
    free(c);
    if (web_read_request(fd, req, sizeof(req), &req_len) == 0) {
        web_handle_request(fd, req, req_len);
        if (strstr(req, "GET /api/events ") == NULL) {
            web_close(fd);
        }
    }
    else {
        web_close(fd);
    }
#if defined(_WIN32) || defined(_WIN64)
    return 0;
#else
    return NULL;
#endif
}

#if defined(_WIN32) || defined(_WIN64)
static DWORD WINAPI web_accept_thread_main(LPVOID arg)
#else
static void* web_accept_thread_main(void* arg)
#endif
{
    (void)arg;
    while (g_web_ctx.running) {
        struct sockaddr_in cli_addr;
#if defined(_WIN32) || defined(_WIN64)
        int cli_len = sizeof(cli_addr);
#else
        socklen_t cli_len = sizeof(cli_addr);
#endif
        web_fd_t cfd = accept(g_web_ctx.listen_fd, (struct sockaddr*)&cli_addr, &cli_len);
        if (cfd == WEB_INVALID_FD) {
            if (!g_web_ctx.running) {
                break;
            }
            web_sleep_ms(20);
            continue;
        }
        web_client_arg_t* carg = (web_client_arg_t*)malloc(sizeof(web_client_arg_t));
        if (!carg) {
            web_close(cfd);
            continue;
        }
        carg->fd = cfd;
#if defined(_WIN32) || defined(_WIN64)
        HANDLE th = CreateThread(NULL, 0, web_client_thread_main, carg, 0, NULL);
        if (th) {
            CloseHandle(th);
        }
        else {
            web_close(cfd);
            free(carg);
        }
#else
        pthread_t th;
        if (pthread_create(&th, NULL, web_client_thread_main, carg) == 0) {
            pthread_detach(th);
        }
        else {
            web_close(cfd);
            free(carg);
        }
#endif
    }
#if defined(_WIN32) || defined(_WIN64)
    return 0;
#else
    return NULL;
#endif
}

#if defined(_WIN32) || defined(_WIN64)
static DWORD WINAPI web_telemetry_thread_main(LPVOID arg)
#else
static void* web_telemetry_thread_main(void* arg)
#endif
{
    uint64_t last_emit = 0;
    (void)arg;
    while (g_web_ctx.running) {
        uint64_t now = luat_mcu_tick64_ms();
        int cadence = g_web_ctx.cadence_sec;
        if (cadence <= 0) cadence = 5;
        if (last_emit == 0 || now - last_emit >= (uint64_t)cadence * 1000ULL) {
            telemetry_entry_t item = web_capture_telemetry();
            web_push_telemetry(&item);
            web_broadcast_telemetry(&item);
            last_emit = now;
        }
        luat_web_gnss_uart32_tick(now);
        web_sleep_ms(100);
    }
#if defined(_WIN32) || defined(_WIN64)
    return 0;
#else
    return NULL;
#endif
}

int luat_web_runtime_set_cadence(int cadence_sec) {
    if (cadence_sec != 1 && cadence_sec != 5 && cadence_sec != 15) {
        return -1;
    }
    g_web_ctx.cadence_sec = cadence_sec;
    return 0;
}

int luat_web_runtime_start(int port, int cadence_sec) {
    struct sockaddr_in addr;
    int opt = 1;
    if (port <= 0) {
        return 0;
    }
    if (g_web_ctx.running) {
        return 0;
    }
    luat_uart31_console_mount();
    memset(&g_web_ctx, 0, sizeof(g_web_ctx));
    g_web_ctx.listen_fd = WEB_INVALID_FD;
    for (int i = 0; i < WEB_SSE_MAX; i++) {
        g_web_ctx.sse_clients[i] = WEB_INVALID_FD;
    }
    web_mutex_init(&g_web_ctx.lock);
    g_web_ctx.port = port;
    g_web_ctx.cadence_sec = (cadence_sec == 1 || cadence_sec == 5 || cadence_sec == 15) ? cadence_sec : 5;

    g_web_ctx.listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (g_web_ctx.listen_fd == WEB_INVALID_FD) {
        LLOGE("web runtime 启动失败, 无法创建 socket, err=%d", (int)web_errno);
        web_mutex_deinit(&g_web_ctx.lock);
        return -1;
    }
#if defined(_WIN32) || defined(_WIN64)
    setsockopt(g_web_ctx.listen_fd, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));
#else
    setsockopt(g_web_ctx.listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
#endif
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr) != 1) {
        LLOGE("web runtime 启动失败, 无法解析绑定地址");
        web_close(g_web_ctx.listen_fd);
        web_mutex_deinit(&g_web_ctx.lock);
        return -1;
    }
    if (bind(g_web_ctx.listen_fd, (struct sockaddr*)&addr, sizeof(addr)) != 0) {
        LLOGE("web runtime 启动失败, 绑定 127.0.0.1:%d err=%d", port, (int)web_errno);
        web_close(g_web_ctx.listen_fd);
        web_mutex_deinit(&g_web_ctx.lock);
        return -1;
    }
    if (listen(g_web_ctx.listen_fd, 16) != 0) {
        LLOGE("web runtime 启动失败, 监听 127.0.0.1:%d err=%d", port, (int)web_errno);
        web_close(g_web_ctx.listen_fd);
        web_mutex_deinit(&g_web_ctx.lock);
        return -1;
    }
    g_web_ctx.running = 1;
    luat_web_gnss_uart32_init();
    {
        telemetry_entry_t first = web_capture_telemetry();
        web_push_telemetry(&first);
    }

#if defined(_WIN32) || defined(_WIN64)
    g_web_ctx.accept_thread = CreateThread(NULL, 0, web_accept_thread_main, NULL, 0, NULL);
    g_web_ctx.telemetry_thread = CreateThread(NULL, 0, web_telemetry_thread_main, NULL, 0, NULL);
    if (!g_web_ctx.accept_thread || !g_web_ctx.telemetry_thread) {
        luat_web_runtime_stop();
        return -1;
    }
#else
    if (pthread_create(&g_web_ctx.accept_thread, NULL, web_accept_thread_main, NULL) != 0 ||
        pthread_create(&g_web_ctx.telemetry_thread, NULL, web_telemetry_thread_main, NULL) != 0) {
        luat_web_runtime_stop();
        return -1;
    }
#endif
    LLOGI("web console enabled, bind 127.0.0.1:%d", port);
    return 0;
}

void luat_web_runtime_stop(void) {
    if (!g_web_ctx.running) {
        return;
    }
    g_web_ctx.running = 0;
    if (g_web_ctx.listen_fd != WEB_INVALID_FD) {
        web_close(g_web_ctx.listen_fd);
        g_web_ctx.listen_fd = WEB_INVALID_FD;
    }
#if defined(_WIN32) || defined(_WIN64)
    if (g_web_ctx.accept_thread) {
        WaitForSingleObject(g_web_ctx.accept_thread, 2000);
        CloseHandle(g_web_ctx.accept_thread);
        g_web_ctx.accept_thread = NULL;
    }
    if (g_web_ctx.telemetry_thread) {
        WaitForSingleObject(g_web_ctx.telemetry_thread, 2000);
        CloseHandle(g_web_ctx.telemetry_thread);
        g_web_ctx.telemetry_thread = NULL;
    }
#else
    pthread_join(g_web_ctx.accept_thread, NULL);
    pthread_join(g_web_ctx.telemetry_thread, NULL);
#endif
    web_mutex_lock(&g_web_ctx.lock);
    for (int i = 0; i < WEB_SSE_MAX; i++) {
        web_sse_remove_client_locked(i);
    }
    web_mutex_unlock(&g_web_ctx.lock);
    luat_web_gnss_uart32_deinit();
    web_mutex_deinit(&g_web_ctx.lock);
}
