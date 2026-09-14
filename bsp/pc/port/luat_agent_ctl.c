#include "luat_pcsim_host.h"
#include "luat_log.h"
#include "cJSON.h"
#include "SDL2/SDL.h"
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
typedef SOCKET pcsim_sock_t;
#define PCSIM_CLOSESOCKET closesocket
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/select.h>
typedef int pcsim_sock_t;
#define INVALID_SOCKET (-1)
#define PCSIM_CLOSESOCKET close
#endif
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>

#define LUAT_LOG_TAG "agent_ctl"

static SDL_Thread *s_thread = NULL;
static volatile int s_running = 0;
static pcsim_sock_t s_listen = INVALID_SOCKET;

static const char b64_table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *pcsim_b64(const uint8_t *data, size_t len)
{
    size_t out_len = 4 * ((len + 2) / 3);
    char *out = (char *)malloc(out_len + 1);
    size_t i;
    size_t j = 0;
    if (out == NULL) {
        return NULL;
    }
    for (i = 0; i < len; i += 3) {
        unsigned int n = ((unsigned int)data[i]) << 16;
        if (i + 1 < len) {
            n |= ((unsigned int)data[i + 1]) << 8;
        }
        if (i + 2 < len) {
            n |= data[i + 2];
        }
        out[j++] = b64_table[(n >> 18) & 63];
        out[j++] = b64_table[(n >> 12) & 63];
        out[j++] = (i + 1 < len) ? b64_table[(n >> 6) & 63] : '=';
        out[j++] = (i + 2 < len) ? b64_table[n & 63] : '=';
    }
    out[j] = 0;
    return out;
}

static void send_line(pcsim_sock_t sock, const char *line)
{
    size_t len = strlen(line);
    const char *p = line;
    char nl = '\n';
    while (len > 0) {
        int n = send(sock, p, (int)len, 0);
        if (n <= 0) {
            return;
        }
        p += n;
        len -= (size_t)n;
    }
    send(sock, &nl, 1, 0);
}

static void reply_result(pcsim_sock_t sock, cJSON *id, cJSON *result)
{
    cJSON *root = cJSON_CreateObject();
    char *text;
    cJSON_AddStringToObject(root, "jsonrpc", "2.0");
    if (id) {
        cJSON_AddItemToObject(root, "id", cJSON_Duplicate(id, 1));
    }
    cJSON_AddItemToObject(root, "result", result);
    text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (text) {
        send_line(sock, text);
        cJSON_free(text);
    }
}

static void reply_error(pcsim_sock_t sock, cJSON *id, int code, const char *message)
{
    cJSON *root = cJSON_CreateObject();
    cJSON *err = cJSON_CreateObject();
    char *text;
    cJSON_AddStringToObject(root, "jsonrpc", "2.0");
    if (id) {
        cJSON_AddItemToObject(root, "id", cJSON_Duplicate(id, 1));
    }
    cJSON_AddNumberToObject(err, "code", code);
    cJSON_AddStringToObject(err, "message", message ? message : "error");
    cJSON_AddItemToObject(root, "error", err);
    text = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (text) {
        send_line(sock, text);
        cJSON_free(text);
    }
}

static int json_int(cJSON *obj, const char *key, int fallback)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (cJSON_IsNumber(item)) {
        return item->valueint;
    }
    return fallback;
}

static const char *json_str(cJSON *obj, const char *key)
{
    cJSON *item = cJSON_GetObjectItemCaseSensitive(obj, key);
    if (cJSON_IsString(item) && item->valuestring) {
        return item->valuestring;
    }
    return NULL;
}

static void handle_hello(pcsim_sock_t sock, cJSON *id)
{
    cJSON *result = cJSON_CreateObject();
    cJSON_AddNumberToObject(result, "protocol", 2);
    cJSON_AddNumberToObject(result, "nativeWidth", luat_pcsim_host_native_width());
    cJSON_AddNumberToObject(result, "nativeHeight", luat_pcsim_host_native_height());
    cJSON_AddBoolToObject(result, "ready", luat_pcsim_host_ready());
    cJSON_AddStringToObject(result, "pixelFormat", "rgb565");
    cJSON_AddBoolToObject(result, "headless", luat_pcsim_host_headless());
    reply_result(sock, id, result);
}

static void handle_screenshot(pcsim_sock_t sock, cJSON *id)
{
    uint8_t *png = NULL;
    size_t len = 0;
    int w = 0;
    int h = 0;
    char *b64;
    cJSON *result;
    if (!luat_pcsim_host_ready()) {
        reply_error(sock, id, -32001, "not ready");
        return;
    }
    {
        int rc = luat_pcsim_host_screenshot_png(&png, &len, &w, &h);
        if (rc != 0 || png == NULL) {
            const char *msg = "screenshot failed";
            if (rc == -2) {
                msg = "no frame yet";
            } else if (rc == -3) {
                msg = "png encode failed";
            }
            reply_error(sock, id, -32003, msg);
            return;
        }
    }
    b64 = pcsim_b64(png, len);
    free(png);
    if (b64 == NULL) {
        reply_error(sock, id, -32000, "base64 failed");
        return;
    }
    result = cJSON_CreateObject();
    cJSON_AddStringToObject(result, "mime", "image/png");
    cJSON_AddNumberToObject(result, "width", w);
    cJSON_AddNumberToObject(result, "height", h);
    cJSON_AddStringToObject(result, "data", b64);
    free(b64);
    reply_result(sock, id, result);
}

static void handle_pointer(pcsim_sock_t sock, cJSON *id, cJSON *params)
{
    const char *type = json_str(params, "type");
    const char *button = json_str(params, "button");
    int rc;
    if (!luat_pcsim_host_ready()) {
        reply_error(sock, id, -32001, "not ready");
        return;
    }
    rc = luat_pcsim_host_inject_pointer(
        type,
        json_int(params, "x", 0),
        json_int(params, "y", 0),
        button,
        json_int(params, "fromX", 0),
        json_int(params, "fromY", 0),
        json_int(params, "dx", 0),
        json_int(params, "dy", 0)
    );
    if (rc != 0) {
        reply_error(sock, id, -32602, "invalid pointer params");
        return;
    }
    {
        cJSON *result = cJSON_CreateObject();
        cJSON_AddBoolToObject(result, "ok", 1);
        reply_result(sock, id, result);
    }
}

static void handle_key(pcsim_sock_t sock, cJSON *id, cJSON *params)
{
    const char *type = json_str(params, "type");
    const char *text = json_str(params, "text");
    cJSON *keys_json = cJSON_GetObjectItemCaseSensitive(params, "keys");
    const char *names[16];
    int count = 0;
    int rc;
    if (cJSON_IsArray(keys_json)) {
        int n = cJSON_GetArraySize(keys_json);
        int i;
        for (i = 0; i < n && count < 16; i++) {
            cJSON *item = cJSON_GetArrayItem(keys_json, i);
            if (cJSON_IsString(item) && item->valuestring) {
                names[count++] = item->valuestring;
            }
        }
    }
    if (type && strcmp(type, "type") == 0 && text && strlen(text) > 31) {
        char chunk[32];
        size_t off = 0;
        size_t total = strlen(text);
        while (off < total) {
            size_t n = total - off;
            if (n > 31) {
                n = 31;
            }
            memcpy(chunk, text + off, n);
            chunk[n] = 0;
            if (luat_pcsim_host_inject_key("type", NULL, 0, chunk) != 0) {
                reply_error(sock, id, -32602, "type failed");
                return;
            }
            off += n;
        }
        {
            cJSON *result = cJSON_CreateObject();
            cJSON_AddBoolToObject(result, "ok", 1);
            reply_result(sock, id, result);
        }
        return;
    }
    rc = luat_pcsim_host_inject_key(type, names, count, text);
    if (rc == -2) {
        reply_error(sock, id, -32002, "unknown key");
        return;
    }
    if (rc != 0) {
        reply_error(sock, id, -32602, "invalid key params");
        return;
    }
    {
        cJSON *result = cJSON_CreateObject();
        cJSON_AddBoolToObject(result, "ok", 1);
        reply_result(sock, id, result);
    }
}

static void handle_wait(pcsim_sock_t sock, cJSON *id, cJSON *params)
{
    int ms = json_int(params, "ms", 0);
    if (ms < 0) {
        ms = 0;
    }
    if (ms > 10000) {
        ms = 10000;
    }
    SDL_Delay((Uint32)ms);
    {
        cJSON *result = cJSON_CreateObject();
        cJSON_AddBoolToObject(result, "ok", 1);
        reply_result(sock, id, result);
    }
}

static void handle_request(pcsim_sock_t sock, cJSON *req, int *subscribed)
{
    cJSON *id = cJSON_GetObjectItem(req, "id");
    const char *method = json_str(req, "method");
    cJSON *params = cJSON_GetObjectItemCaseSensitive(req, "params");
    if (method == NULL) {
        reply_error(sock, id, -32600, "missing method");
        return;
    }
    if (strcmp(method, "hello") == 0) {
        handle_hello(sock, id);
        return;
    }
    if (strcmp(method, "ping") == 0) {
        {
            cJSON *result = cJSON_CreateObject();
            cJSON_AddBoolToObject(result, "ok", 1);
            reply_result(sock, id, result);
        }
        return;
    }
    if (strcmp(method, "subscribe_frames") == 0) {
        if (subscribed) {
            *subscribed = 1;
        }
        {
            cJSON *result = cJSON_CreateObject();
            cJSON_AddBoolToObject(result, "ok", 1);
            reply_result(sock, id, result);
        }
        return;
    }
    if (strcmp(method, "screenshot") == 0) {
        handle_screenshot(sock, id);
        return;
    }
    if (strcmp(method, "pointer") == 0) {
        handle_pointer(sock, id, params);
        return;
    }
    if (strcmp(method, "key") == 0) {
        handle_key(sock, id, params);
        return;
    }
    if (strcmp(method, "wait") == 0) {
        handle_wait(sock, id, params);
        return;
    }
    reply_error(sock, id, -32601, "unknown method");
}

#pragma pack(push, 1)
typedef struct {
    char magic[4];
    uint32_t seq;
    uint16_t width;
    uint16_t height;
    uint8_t format;
    uint16_t stride;
    uint32_t payload_len;
} pcsim_frame_hdr_t;
#pragma pack(pop)

static int send_all(pcsim_sock_t sock, const char *data, size_t len)
{
    while (len > 0) {
        int n = send(sock, data, (int)len, 0);
        if (n <= 0) {
            return -1;
        }
        data += n;
        len -= (size_t)n;
    }
    return 0;
}

static int push_frame_if_new(pcsim_sock_t sock, uint8_t *pixels, size_t cap, uint32_t *last_seq)
{
    uint32_t seq = 0;
    int w = 0;
    int h = 0;
    uint8_t format = 0;
    uint16_t stride = 0;
    int rc;
    pcsim_frame_hdr_t hdr;

    rc = luat_pcsim_host_copy_frame(*last_seq, pixels, cap, &seq, &w, &h, &format, &stride);
    if (rc != 0) {
        return rc == 1 ? 0 : -1;
    }
    memset(&hdr, 0, sizeof(hdr));
    memcpy(hdr.magic, "PCF2", 4);
    hdr.seq = seq;
    hdr.width = (uint16_t)w;
    hdr.height = (uint16_t)h;
    hdr.format = format;
    hdr.stride = stride;
    hdr.payload_len = (uint32_t)((size_t)h * (size_t)stride);
    if (hdr.payload_len > cap) {
        return -1;
    }
    if (send_all(sock, (const char *)&hdr, sizeof(hdr)) != 0) {
        return -1;
    }
    if (send_all(sock, (const char *)pixels, hdr.payload_len) != 0) {
        return -1;
    }
    *last_seq = seq;
    return 0;
}

static int serve_client(pcsim_sock_t client)
{
    char *buf = (char *)malloc(1024 * 1024);
    uint8_t *pixels = (uint8_t *)malloc(2 * 1024 * 1024);
    size_t used = 0;
    int subscribed = 0;
    uint32_t last_seq = 0;
    if (buf == NULL || pixels == NULL) {
        free(buf);
        free(pixels);
        return -1;
    }
    while (s_running) {
        fd_set rfds;
        struct timeval tv;
        int nsel;
        FD_ZERO(&rfds);
        FD_SET(client, &rfds);
        tv.tv_sec = 0;
        tv.tv_usec = 50000;
        nsel = select((int)client + 1, &rfds, NULL, NULL, &tv);
        if (nsel < 0) {
            break;
        }
        if (nsel > 0 && FD_ISSET(client, &rfds)) {
            int n;
            char *nl;
            if (used + 4096 >= 1024 * 1024) {
                break;
            }
            n = recv(client, buf + used, (int)(1024 * 1024 - used - 1), 0);
            if (n <= 0) {
                break;
            }
            used += (size_t)n;
            buf[used] = 0;
            while ((nl = strchr(buf, '\n')) != NULL) {
                size_t line_len = (size_t)(nl - buf);
                char saved = *nl;
                cJSON *req;
                *nl = 0;
                if (line_len > 0 && buf[line_len - 1] == '\r') {
                    buf[line_len - 1] = 0;
                }
                req = cJSON_Parse(buf);
                if (req == NULL) {
                    reply_error(client, NULL, -32700, "parse error");
                } else {
                    handle_request(client, req, &subscribed);
                    cJSON_Delete(req);
                }
                *nl = saved;
                memmove(buf, nl + 1, used - line_len - 1);
                used -= line_len + 1;
                buf[used] = 0;
            }
        }
        if (subscribed && luat_pcsim_host_ready()) {
            if (push_frame_if_new(client, pixels, 2 * 1024 * 1024, &last_seq) < 0) {
                break;
            }
        }
    }
    free(buf);
    free(pixels);
    return 0;
}

static int serve_client_thread(void *userdata)
{
    pcsim_sock_t *psock = (pcsim_sock_t *)userdata;
    pcsim_sock_t sock = *psock;
    free(psock);
    serve_client(sock);
    PCSIM_CLOSESOCKET(sock);
    return 0;
}

static int agent_ctl_thread(void *userdata)
{
    struct sockaddr_in addr;
    int yes = 1;
    (void)userdata;
#if defined(_WIN32)
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        LLOGE("WSAStartup failed");
        return -1;
    }
#endif
    s_listen = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s_listen == INVALID_SOCKET) {
        LLOGE("socket failed");
        return -1;
    }
    setsockopt(s_listen, SOL_SOCKET, SO_REUSEADDR, (const char *)&yes, sizeof(yes));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)luat_pcsim_host_agent_ctl_port());
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (bind(s_listen, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        LLOGE("bind 127.0.0.1:%d failed", luat_pcsim_host_agent_ctl_port());
        PCSIM_CLOSESOCKET(s_listen);
        s_listen = INVALID_SOCKET;
        return -1;
    }
    if (listen(s_listen, 4) != 0) {
        LLOGE("listen failed");
        PCSIM_CLOSESOCKET(s_listen);
        s_listen = INVALID_SOCKET;
        return -1;
    }
    LLOGI("agent-ctl listening on 127.0.0.1:%d", luat_pcsim_host_agent_ctl_port());
    while (s_running) {
        pcsim_sock_t client = accept(s_listen, NULL, NULL);
        SDL_Thread *th;
        pcsim_sock_t *job;
        if (client == INVALID_SOCKET) {
            continue;
        }
        setsockopt(client, IPPROTO_TCP, TCP_NODELAY, (const char *)&yes, sizeof(yes));
        job = (pcsim_sock_t *)malloc(sizeof(*job));
        if (job == NULL) {
            PCSIM_CLOSESOCKET(client);
            continue;
        }
        *job = client;
        th = SDL_CreateThread(serve_client_thread, "agent-cli", job);
        if (th == NULL) {
            serve_client(client);
            PCSIM_CLOSESOCKET(client);
            free(job);
        } else {
            SDL_DetachThread(th);
        }
    }
    if (s_listen != INVALID_SOCKET) {
        PCSIM_CLOSESOCKET(s_listen);
        s_listen = INVALID_SOCKET;
    }
#if defined(_WIN32)
    WSACleanup();
#endif
    return 0;
}

int luat_agent_ctl_start(void)
{
    int port = luat_pcsim_host_agent_ctl_port();
    if (port <= 0 || s_thread != NULL) {
        return 0;
    }
    s_running = 1;
    s_thread = SDL_CreateThread(agent_ctl_thread, "agent-ctl", NULL);
    if (s_thread == NULL) {
        s_running = 0;
        LLOGE("create agent-ctl thread failed: %s", SDL_GetError());
        return -1;
    }
    return 0;
}

void luat_agent_ctl_stop(void)
{
    s_running = 0;
    if (s_listen != INVALID_SOCKET) {
        PCSIM_CLOSESOCKET(s_listen);
        s_listen = INVALID_SOCKET;
    }
    if (s_thread) {
        SDL_WaitThread(s_thread, NULL);
        s_thread = NULL;
    }
}
