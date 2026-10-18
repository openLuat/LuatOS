/*
 * httpsrv 的传输无关层.
 *
 * 这里只放"HTTP 语义": 请求解析 / 静态文件路由 / 响应拼装 / Lua 派发.
 * 字节搬运(socket vs tcp_pcb)交给 luat_httpsrv_lwip.c 或 luat_httpsrv_posix.c,
 * 通过 luat_httpsrv_transport.h 的 vtable 调用.
 *
 * 这样真机(lwIP)与 PC(宿主 socket)跑的是同一份 HTTP 行为,
 * 静态文件 / 路径穿越防护 / 状态码表只有一处实现, 不会分叉.
 */

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_httpsrv.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "http_parser.h"

#ifdef _MSC_VER
#include <intrin.h>
#endif

/* state_word(在途计数|STOPPED 位)的原子操作, 遵循项目惯例:
 * MSVC 用 _Interlocked 内建(不需要 windows.h), 其余编译器用 __sync 内建 */
static inline uint32_t httpsrv_word_inc(volatile uint32_t* w) {
#ifdef _MSC_VER
    return (uint32_t)_InterlockedIncrement((volatile long*)w);
#else
    return __sync_add_and_fetch(w, 1u);
#endif
}
static inline uint32_t httpsrv_word_dec(volatile uint32_t* w) {
#ifdef _MSC_VER
    return (uint32_t)_InterlockedDecrement((volatile long*)w);
#else
    return __sync_sub_and_fetch(w, 1u);
#endif
}
static inline uint32_t httpsrv_word_or(volatile uint32_t* w, uint32_t bits) {
#ifdef _MSC_VER
    return (uint32_t)_InterlockedOr((volatile long*)w, (long)bits);
#else
    return __sync_or_and_fetch(w, bits);
#endif
}

int g_httpsrv_debug = 0;

#define HTTPSRV_DBG(...) if (g_httpsrv_debug) LLOGD(__VA_ARGS__)

// https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
const http_code_str_t g_luat_http_codes[] = {
    {200, "OK"},
    {301, "Moved Permanently"},
    {302, "Found"},
    {400, "Bad Request"},
    {401, "Unauthorized"},
    {403, "Forbidden"},
    {404, "Not Found"},
    {500, "Internal Server Error"},
    {0, ""}
};

static const ct_reg_t ct_regs[] = {
    {"html",    "text/html; charset=utf-8"},
    {"txt",     "text/txt; charset=utf-8"},
    {"xml",     "text/xml; charset=utf-8"},
    {"jpg",      "image/jpeg"},
    {"png",     "image/png"},
    {"gif",     "image/gif"},
    {"svg",     "image/svg+xml"},
    {"json",    "application/json; charset=utf-8"},
    {"js",      "application/javascript; charset=utf-8"},
    {"css",     "text/css"},
    {"wav",     "audio/wave"},
    {"ogg",     "audio/ogg"},
    {"webm",    "video/webm"},
    {"mp4",     "video/mpeg4"},
    {"bin",     "application/octet-stream"},
};

static const char* ct_find(const char* path) {
    size_t path_size = strlen(path);
    for (size_t i = 0; i < sizeof(ct_regs)/sizeof(ct_regs[0]); i++)
    {
        const char* suff = ct_regs[i].suff;
        size_t suff_size = strlen(suff);
        if (path_size > suff_size + 2) {
            if (!memcmp(path + path_size - suff_size, suff, suff_size)) {
                return ct_regs[i].value;
            }
        }
    }
    return NULL;
}

//================================
// client methods

static int my_on_message_begin(http_parser* parser);
static int my_on_message_complete(http_parser* parser);
static int my_on_url(http_parser* parser, const char *at, size_t length);
static int my_on_header_field(http_parser* parser, const char *at, size_t length);
static int my_on_header_value(http_parser* parser, const char *at, size_t length);
static int my_on_body(http_parser* parser, const char *at, size_t length);
static int luat_client_cb(lua_State* L, void* ptr);
static int luat_httpsrv_ctx_release_cb(lua_State* L, void* ptr);

static const struct http_parser_settings hp_settings = {
    .on_message_begin = my_on_message_begin,
    .on_url = my_on_url,
    .on_header_field = my_on_header_field,
    .on_header_value = my_on_header_value,
    .on_body = my_on_body,
    .on_message_complete = my_on_message_complete,
};

void luat_httpsrv_parser_init(client_socket_ctx_t* client) {
    client->parser.data = client;
    http_parser_init(&client->parser, HTTP_REQUEST);
}

size_t luat_httpsrv_parser_exec(client_socket_ctx_t* client, const char* data, size_t len) {
    return http_parser_execute(&client->parser, &hp_settings, data, len);
}

//================================

// 释放与传输层无关的客户端资源(句柄/静态文件句柄由后端负责)
void luat_httpsrv_free_common(client_socket_ctx_t* client) {
    if (client->uri) {
        HTTPSRV_DBG("free uri %p", client->uri);
        luat_heap_free(client->uri);
        client->uri = NULL;
    }
    if (client->headers) {
        HTTPSRV_DBG("free headers %p", client->headers);
        luat_heap_free(client->headers);
        client->headers = NULL;
    }
    if (client->body) {
        HTTPSRV_DBG("free body %p", client->body);
        luat_heap_free(client->body);
        client->body = NULL;
    }
    if (client->buff) {
        HTTPSRV_DBG("free buff %p", client->buff);
        luat_heap_free(client->buff);
        client->buff = NULL;
    }
    if (client->fd) {
        HTTPSRV_DBG("close file %p", client->fd);
        luat_fs_fclose(client->fd);
        client->fd = NULL;
    }
    if (client->req_headers) {
        http_req_header_t* prev = client->req_headers;
        http_req_header_t* next = NULL;
        while (prev) {
            next = prev->next;
            luat_heap_free(prev);
            prev = next;
        }
        client->req_headers = NULL;
    }
}

void luat_httpsrv_client_cleanup(client_socket_ctx_t* client) {
    HTTPSRV_DBG("client cleanup!!! %p", client);
    if (client == NULL) {
        return;
    }
    luat_httpsrv_ctx_t* srv = client->srv_ctx;
    if (client->vt) {
        client->vt->cli_cleanup(client);
    }
    luat_httpsrv_free_common(client);
    HTTPSRV_DBG("free client %p", client);
    luat_heap_free(client);
    // 归还在途计数. 若这是最后一个收尾的连接且服务已 stop,
    // ctx 的 unref+free 交给 Lua 线程(msgbus), 本函数可能跑在后端线程, 不能 luaL_unref
    if (srv) {
        uint32_t r = httpsrv_word_dec(&srv->state_word);
        if ((r & HTTPSRV_CTX_STOPPED_BIT) && (r & ~HTTPSRV_CTX_STOPPED_BIT) == 0) {
            rtos_msg_t msg = {
                .handler = luat_httpsrv_ctx_release_cb,
                .ptr = srv
            };
            if (luat_msgbus_put(&msg, 0) != 0) {
                LLOGE("httpsrv ctx release msg put failed, leak ctx %p", srv);
            }
        }
    }
}

void luat_httpsrv_client_attached(luat_httpsrv_ctx_t* ctx, client_socket_ctx_t* client) {
    client->srv_ctx = ctx;
    httpsrv_word_inc(&ctx->state_word);
}

int luat_httpsrv_ctx_mark_stopped(luat_httpsrv_ctx_t* ctx) {
    uint32_t r = httpsrv_word_or(&ctx->state_word, HTTPSRV_CTX_STOPPED_BIT);
    return (r & ~HTTPSRV_CTX_STOPPED_BIT) == 0;
}

void luat_httpsrv_ctx_client_abandoned(luat_httpsrv_ctx_t* ctx) {
    uint32_t r = httpsrv_word_dec(&ctx->state_word);
    if ((r & HTTPSRV_CTX_STOPPED_BIT) && (r & ~HTTPSRV_CTX_STOPPED_BIT) == 0) {
        rtos_msg_t msg = {
            .handler = luat_httpsrv_ctx_release_cb,
            .ptr = ctx
        };
        if (luat_msgbus_put(&msg, 0) != 0) {
            LLOGE("httpsrv ctx release msg put failed, leak ctx %p", ctx);
        }
    }
}

//================================
// 响应拼装

// 发送 Lua 回调产生的响应(状态行 + Content-Length + Connection + 自定义头 + body)
void luat_httpsrv_send_response(client_socket_ctx_t* client) {
    int code = client->code;
    const char* headers = client->headers;
    size_t body_size = client->body_size;
    const char* msg = "";
    for (size_t i = 0; i < sizeof(g_luat_http_codes)/sizeof(http_code_str_t); i++)
    {
        if (g_luat_http_codes[i].code == code) {
            msg = g_luat_http_codes[i].msg;
            break;
        }
    }
    if (strlen(msg) == 0) {
        LLOGW("unkown http code %d, set as 200 Ok", code);
        code = 200;
        msg = "Ok";
    }
    HTTPSRV_DBG("httpd resp %d %s body %d", code, msg, body_size);

    char buff[64];
    snprintf(buff, sizeof(buff), "HTTP/1.0 %d %s\r\n", code, msg);
    client->vt->cli_send(client, buff, strlen(buff));

    // 固件 SDK 的 printf 不支持 %zu 长度修饰符(实测输出字面 "zu", 导致
    // 严格 HTTP 客户端报 Invalid Content-Length), 这里用 %u + unsigned 截断
    snprintf(buff, sizeof(buff), "Content-Length: %u\r\n", (unsigned)body_size);
    client->vt->cli_send(client, buff, strlen(buff));
    client->vt->cli_send(client, "Connection: close\r\n", strlen("Connection: close\r\n"));
    if (headers && strlen(headers)) {
        client->vt->cli_send(client, headers, strlen(headers));
    }
    client->vt->cli_send(client, "\r\n", 2);
    if (body_size) {
        HTTPSRV_DBG("send body %d", body_size);
        client->vt->cli_send(client, client->body, body_size);
    }
    client->write_done = 1;
    HTTPSRV_DBG("resp done, total send %d", client->send_size);
}

// 发送静态文件的响应头(body 由后端流式发送)
void luat_httpsrv_send_static_head(client_socket_ctx_t* client, const char* path, size_t len) {
    HTTPSRV_DBG("sending %s", path);
    char *buff = client->sbuff;
    client->vt->cli_send(client, "HTTP/1.0 200 OK\r\n", strlen("HTTP/1.0 200 OK\r\n"));
    // 同 send_response: SDK printf 不支持 %zu, 用 %u + unsigned(文件不可能超 4GB)
    snprintf(buff, sizeof(client->sbuff), "Content-Length: %u\r\n", (unsigned)len);
    client->vt->cli_send(client, buff, strlen(buff));
    client->vt->cli_send(client, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    const char* ctype = ct_find(path);
    if (ctype == NULL) {
        client->vt->cli_send(client, "Content-Type: application/octet-stream\r\n",
                             strlen("Content-Type: application/octet-stream\r\n"));
    }
    else {
        snprintf(buff, sizeof(client->sbuff), "Content-Type: %s\r\n", ctype);
        client->vt->cli_send(client, buff, strlen(buff));
    }
    // 根据path判断一下文件后缀, 如果不是 html/htm/js/css就当文件下载
    size_t plen = strlen(path);
    if (plen >= 5 && strcmp(path + plen - 5, ".html") == 0) {
        HTTPSRV_DBG("普通文件模式 %s", path);
    }
    else if (plen >= 4 && (strcmp(path + plen - 4, ".htm") == 0 || strcmp(path + plen - 4, ".css") == 0)) {
        HTTPSRV_DBG("普通文件模式 %s", path);
    }
    else if (plen >= 3 && strcmp(path + plen - 3, ".js") == 0) {
        HTTPSRV_DBG("普通文件模式 %s", path);
    }
    else {
        HTTPSRV_DBG("启用文件下载模式 %s", path);
        const char* filename = strrchr(path, '/');
        if (filename) {
            filename++; // 跳过 '/'
            snprintf(buff, sizeof(client->sbuff), "Content-Disposition: attachment; filename=\"%s\"\r\n", filename);
            client->vt->cli_send(client, buff, strlen(buff));
        }
    }
    client->vt->cli_send(client, "\r\n", 2);
}

//================================
// 静态文件路由

// 把 uri 解析成实际文件路径. 命中返回 1 并填充 path_out/out_len.
int luat_httpsrv_resolve_static(client_socket_ctx_t* client, char* path_out, size_t path_size, size_t* out_len) {
    // 静态路由只看路径部分: query string(如 /style.css?v=1 的 cache-busting 参数)不参与文件查找,
    // 但完整 uri 仍原样传给 Lua 回调, 用户脚本可自取参数
    const char* q = strchr(client->uri, '?');
    size_t uri_len = q ? (size_t)(q - client->uri) : strlen(client->uri);
    if (uri_len < 1 || uri_len > 200) {
        // 太长就不支持了
        HTTPSRV_DBG("path too long [%s] > 200", client->uri);
        return 0;
    }
    char uri_path[201] = {0};
    memcpy(uri_path, client->uri, uri_len);
    // 检查路径遍历攻击
    if (strstr(uri_path, "..") != NULL) {
        LLOGW("path traversal attack detected: %s", client->uri);
        return 0;
    }
    char path[256] = {0};
    const char* uri_to_use = uri_len == 1 ? "/index.html" : uri_path;
    int ret = snprintf(path, sizeof(path), "/luadb%s", uri_to_use);
    if (ret < 0 || ret >= sizeof(path)) {
        LLOGW("path buffer overflow prevented");
        return 0;
    }
    size_t fz = luat_fs_fsize(path);
    if (fz < 1) {
        ret = snprintf(path, sizeof(path), "%s", uri_to_use);
        if (ret < 0 || ret >= sizeof(path)) {
            LLOGW("path buffer overflow prevented");
            return 0;
        }
        fz = luat_fs_fsize(path);
        if (fz < 1) {
            return 0;
        }
    }
    // path 是本函数的局部缓冲, 拷到调用方缓冲
    ret = snprintf(path_out, path_size, "%s", path);
    if (ret < 0 || ret >= (int)path_size) {
        LLOGW("path buffer overflow prevented");
        return 0;
    }
    *out_len = fz;
    return 1;
}

// 请求完整解析后的统一出口. 返回 1 = 已由静态文件路径处理; 0 = 已派发到 Lua 线程
int luat_httpsrv_dispatch_request(client_socket_ctx_t* client) {
    char path[256] = {0};
    size_t len = 0;
    if (luat_httpsrv_resolve_static(client, path, sizeof(path), &len)) {
        if (client->vt->cli_serve_static(client, path, len)) {
            return 1;
        }
    }
    rtos_msg_t msg = {
        .handler = luat_client_cb,
        .ptr = client
    };
    // 投递失败时没有任何人会去 signal 这个 client, 连接会一直悬到后端超时.
    // 这里直接返回 1, 让后端走"请求已处理"的回收路径.
    if (luat_msgbus_put(&msg, 0) != 0) {
        LLOGE("luat_msgbus_put failed");
        return 1;
    }
    return 0;
}

//================================
// Lua 派发

static int luat_client_cb(lua_State* L, void* ptr) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)ptr;
    lua_geti(L, LUA_REGISTRYINDEX, client->lua_ref_id);
    if (!lua_isfunction(L, -1)) {
        // 回调函数不存在(服务已 stop 且 ref 已被回收)或被复用成非函数值,
        // 需要关闭连接并清理资源. 用 isfunction 而不是 isnil 挡住 ref 槽位复用的情况
        lua_pop(L, 1);
        client->discard = 1;
        int ret = client->vt->cli_dispatch_resp(client);
        if (ret) {
            luat_httpsrv_client_cleanup(client);
        }
        return 0;
    }
    // 开始回调
    lua_pushinteger(L, (int)(intptr_t)client->hconn);
    lua_pushstring(L, http_method_str(client->parser.method));
    lua_pushstring(L, client->uri);
    lua_newtable(L); // 暂时不解析headers
    if (client->req_headers) {
        http_req_header_t* prev = client->req_headers;
        http_req_header_t* next = NULL;
        while (prev) {
            next = prev->next;
            lua_pushlstring(L, prev->data, prev->key_len);
            lua_pushlstring(L, prev->data + prev->key_len, prev->value_len);
            lua_settable(L, -3);
            luat_heap_free(prev);
            prev = next;
        }
        client->req_headers = NULL;
    }

    lua_pushlstring(L, client->body, client->body_size);
    // 先释放掉
    luat_heap_free(client->uri);
    client->uri = NULL;
    if (client->body) {
        luat_heap_free(client->body);
        client->body = NULL;
        client->body_size = 0;
    }
    // 用 pcall 兜住: 用户回调报错时也要继续走到 cli_dispatch_resp,
    // 否则这条连接既没有响应也不会被回收, 会一直挂着.
    if (lua_pcall(L, 5, 3, 0) != 0) {
        LLOGE("httpsrv callback error: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
        lua_pushinteger(L, 500);
        lua_newtable(L);
        lua_pushstring(L, "Internal Server Error");
    }

    int code = luaL_optinteger(L, -3, 404);
    if (code < 100)
        code = 200;
    size_t body_size = 0;
    const char* body = luaL_optlstring(L, -1, "", &body_size);
    if (body_size > 0) {
        client->body = luat_heap_malloc(body_size);
        if (client->body == NULL) {
            LLOGE("malloc response body fail, %d", body_size);
            body_size = 0;
        }
        else {
            client->body_size = body_size;
            memcpy(client->body, body, body_size);
        }
    }
    if (lua_istable(L, -2)) {
        lua_pushvalue(L, -2);
        lua_pushnil(L);
        lua_pushnil(L);
        size_t keylen = 0;
        size_t vallen = 0;
		while (lua_next(L, -3) != 0) {
			lua_pushvalue(L, -2);
            const char* key = lua_tolstring(L, -1, &keylen);
            const char* value = lua_tolstring(L, -2, &vallen);
            if (client->headers == NULL) {
                client->headers = luat_heap_malloc(keylen + vallen + 6);
                sprintf(client->headers, "%s: %s\r\n", key, value);
            }
            else {
                char* ptr = luat_heap_realloc(client->headers, strlen(client->headers) + keylen + vallen + 6);
                if (ptr) {
                    sprintf(ptr + strlen(ptr), "%s: %s\r\n", key, value);
                    client->headers = ptr;
                }
            }
			lua_pop(L, 2);
		}
    }
    client->code = code;
    // 回调引用与 3 个返回值一起出栈: lua_geti 压入的回调此前一直没弹, 每个请求会漏 3 个栈槽
    lua_pop(L, 4);
    int ret = client->vt->cli_dispatch_resp(client);
    if (ret) {
        LLOGE("cli_dispatch_resp %d", ret); // 这就很不好搞了
        luat_httpsrv_client_cleanup(client);
    }

    return 0;
}

//================================
// 服务端上下文

luat_httpsrv_ctx_t* luat_httpsrv_malloc(int port, int adapter_index, const luat_httpsrv_transport_t* vt) {
    luat_httpsrv_ctx_t* ctx = luat_heap_malloc(sizeof(luat_httpsrv_ctx_t));
    if (ctx == NULL) {
        HTTPSRV_DBG("out of memory when malloc httpsrv ctx");
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_httpsrv_ctx_t));
    ctx->port = port;
    ctx->adapter_id = adapter_index;
    ctx->vt = vt;
    return ctx;
}

int luat_httpsrv_free(luat_httpsrv_ctx_t* ctx) {
    if (ctx == NULL) {
        return 0;
    }
    luat_heap_free(ctx);
    return 0;
}

// ctx 延迟释放的出口, 只在 Lua 线程执行(msgbus).
// 走到这里说明 listen 已停且最后一个在途连接也已收尾, lua_ref 可以安全 unref
static int luat_httpsrv_ctx_release_cb(lua_State* L, void* ptr) {
    luat_httpsrv_ctx_t* ctx = (luat_httpsrv_ctx_t*)ptr;
    if (ctx->lua_ref_id != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, ctx->lua_ref_id);
        ctx->lua_ref_id = LUA_NOREF;
    }
    HTTPSRV_DBG("httpsrv ctx released %p", ctx);
    return luat_httpsrv_free(ctx);
}

//================================
// http_parser 回调

static int my_on_message_begin(http_parser* parser) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->recv_done) {
        // 流水线里的后续消息: 本条连接只处理一个请求, 保留已收完的 uri
        return 0;
    }
    // 新的一条请求开始: 重置上一条的 uri 累积状态
    if (client->uri) {
        luat_heap_free(client->uri);
        client->uri = NULL;
    }
    return 0;
}

static int my_on_message_complete(http_parser* parser) {
    HTTPSRV_DBG("on_message_complete");
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->expect_body_size > 0 && client->body_size < client->expect_body_size) {
        LLOGW("body size not match expect %d/%d", client->body_size, client->expect_body_size);
        return HPE_INVALID_CONTENT_LENGTH;
    }
    client->recv_done = 1;
    return 0;
}

static int my_on_url(http_parser* parser, const char *at, size_t length) {
    HTTPSRV_DBG("on_header_url %p %d", at, length);
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->recv_done) {
        // 同一条连接上流水线带了下一个请求: 当前实现一条连接只处理一个请求,
        // 忽略后续请求的 url, 保留本条 uri 供即将进行的 dispatch
        return 0;
    }
    if (length > 1024) {
        LLOGW("request URL is too long!!! %d", length);
        return HPE_INVALID_URL;
    }
    // 同一条消息的 URL 可能分多个 chunk 到达(跨 TCP 分段), 必须累积而不是覆盖,
    // 否则只剩最后一段, dispatch 拿到的就是残缺的 uri
    size_t old_len = client->uri ? strlen(client->uri) : 0;
    if (old_len + length > 1024) {
        LLOGW("request URL is too long!!! %d", old_len + length);
        return HPE_INVALID_URL;
    }
    char* ptr = (char*)luat_heap_realloc(client->uri, old_len + length + 1);
    if (ptr == NULL) {
        LLOGE("fail to malloc uri!!!");
        return HPE_INVALID_URL;
    }
    client->uri = ptr;
    memcpy(ptr + old_len, at, length);
    ptr[old_len + length] = 0;
    return 0;
}

// header名大小写不敏感比较, 仅用于识别Content-Length
static int hdr_key_is_content_length(const char *at, size_t length) {
    if (length != 14)
        return 0;
    const char* cl = "Content-Length";
    for (size_t i = 0; i < 14; i++) {
        if (tolower((unsigned char)at[i]) != tolower((unsigned char)cl[i]))
            return 0;
    }
    return 1;
}

static int my_on_header_field(http_parser* parser, const char *at, size_t length) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (hdr_key_is_content_length(at, length)) {
        client->next_header_value_is_content_length = 1;
    }
    else {
        client->next_header_value_is_content_length = 0;
    }
    // 填充到 req_headers 链表中
    http_req_header_t* header = luat_heap_malloc(sizeof(http_req_header_t) + length);
    if (header) {
        header->key_len = length;
        header->value_len = 0;
        memcpy(header->data, at, length);
        header->next = client->req_headers;
        client->req_headers = header;
    }
    else {
        LLOGE("fail to malloc header!!!");
        return -1;
    }
    return 0;
}

static int my_on_header_value(http_parser* parser, const char *at, size_t length) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->next_header_value_is_content_length) {
        // at 不是 NUL 结尾的字符串: lwIP 后端里 buff 恰好只分配 pbuf->tot_len 字节,
        // 头值在缓冲区末尾被截断时 atoi() 会读越界(读到未初始化/越界字节).
        // 先拷进本地小缓冲再解析, 顺便把超长数字截断掉.
        char num[16] = {0};
        size_t n = length < sizeof(num) - 1 ? length : sizeof(num) - 1;
        memcpy(num, at, n);
        client->expect_body_size = (size_t)strtoul(num, NULL, 10);
        client->next_header_value_is_content_length = 0;
    }
    // 填充到 req_headers 链表中
    if (client->req_headers) {
        http_req_header_t* header = client->req_headers;
        header->value_len = length;
        // 判断一下长度，防止越界, 并根据长度重新分配内存
        if (header->key_len + length > 4096) {
            LLOGW("header too long, key_len %d value_len %d", header->key_len, length);
            return -1;
        }
        void* ptr = luat_heap_realloc(header, sizeof(http_req_header_t) + header->key_len + length);
        if (ptr == NULL) {
            LLOGE("fail to realloc header!!!");
            return -1;
        }
        header = ptr;
        client->req_headers = header;
        memcpy(header->data + header->key_len, at, length);
    }
    return 0;
}

static int my_on_body(http_parser* parser, const char *at, size_t length) {
    HTTPSRV_DBG("on_body %p %d", at, length);
    if (length == 0)
        return 0;
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    // 限制body大小，防止内存耗尽
    size_t max_body_size = 64 * 1024; // 64KB
    if (client->body_size + length > max_body_size) {
        LLOGW("body too large, limit %d", max_body_size);
        return HPE_INVALID_STATUS;
    }
    if (client->body == NULL) {
        size_t alloc_size = client->expect_body_size > 0 ? client->expect_body_size : length;
        if (alloc_size > max_body_size) {
            alloc_size = max_body_size;
        }
        client->body = luat_heap_malloc(alloc_size);
        if (client->body == NULL) {
            LLOGE("malloc body FAIL!!!");
            return HPE_INVALID_STATUS;
        }
        memcpy(client->body, at, length);
        client->body_size = length;
    }
    else {
        // 追加数据到已有body
        char* tmp = luat_heap_realloc(client->body, client->body_size + length);
        if (tmp == NULL) {
            LLOGE("realloc body FAIL!!! %d", client->body_size + length);
            return HPE_INVALID_STATUS;
        }
        client->body = tmp;
        memcpy(client->body + client->body_size, at, length);
        client->body_size += length;
    }
    return 0;
}
