#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_httpsrv.h"
#include "luat_fs.h"

#include "lwip/opt.h"
#include "lwip/tcp.h"
#include "lwip/ip_addr.h"
#include "lwip/tcpip.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "http_parser.h"

#undef LLOGD
#define LLOGD(...)

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

typedef struct client_socket_ctx
{
    int lua_ref_id;
    int code;
    struct http_parser parser;

    char *uri;
    char *headers;
    char *body;

    size_t body_size;
    size_t expect_body_size;
    int next_header_value_is_content_length;
    uint32_t recv_done;
    char *buff;
    size_t buff_offset;
    size_t buff_size;
    struct tcp_pcb* pcb;
    size_t send_size;
    size_t sent_size;

    FILE* fd;
    char sbuff[1500];
    uint32_t sbuff_offset;
    uint8_t write_done;
}client_socket_ctx_t;

static int handle_static_file(client_socket_ctx_t *client);

static void client_cleanup(client_socket_ctx_t *client);

// static int my_on_message_begin(http_parser* parser);
// static int my_on_headers_complete(http_parser* parser);
static int my_on_message_complete(http_parser* parser);
// static int my_on_chunk_header(http_parser* parser);
// static int my_on_chunk_header(http_parser* parser);
// static int my_on_chunk_complete(http_parser* parser);
static int my_on_url(http_parser* parser, const char *at, size_t length);
// static int my_on_status(http_parser* parser, const char *at, size_t length);
static int my_on_header_field(http_parser* parser, const char *at, size_t length);
static int my_on_header_value(http_parser* parser, const char *at, size_t length);
static int my_on_body(http_parser* parser, const char *at, size_t length);

//================================
// client methods

static const struct http_parser_settings hp_settings = {
    // .on_message_begin = my_on_message_begin,
    .on_url = my_on_url,
    // .on_status = my_on_status,
    .on_header_field = my_on_header_field,
    .on_header_value = my_on_header_value,
    // .on_headers_complete = my_on_headers_complete,
    .on_body = my_on_body,
    .on_message_complete = my_on_message_complete,
    // .on_chunk_header = my_on_chunk_header,
    // .on_chunk_complete = my_on_chunk_complete
};
//================================



static const ct_reg_t ct_regs[] = {
    {"html",    "text/html; charset=utf-8"},
    {"txt",     "text/txt; charset=utf-8"},
    {"xml",     "text/xml; charset=utf-8"},
    {"jpg",      "image/jpeg"},
    {"png",     "image/png"},
    {"gif",     "image/gif"},
    {"svg",     "svg+xml"},
    {"json",    "application/json; charset=utf-8"},
    {"js",      "application/javascript; charset=utf-8"},
    {"css",     "text/css"},
    {"wav",     "audio/wave"},
    {"ogg",     "audio/ogg"},
    {"webm",    "video/webm"},
    {"mp4",     "video/mpeg4"},
    {"bin",     "application/octet-stream"},
};

static int client_write(client_socket_ctx_t* client, const char* buff, size_t len) {
    if (len == 0)
        return 0;
    int ret = 0;
#if ENABLE_PSIF
    #if defined(CHIP_EC618)
    ret = tcp_write(client->pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY, 0, 0, 0);
    #else
    sockdataflag_t dataflag={0};
	dataflag.bExceptData=0;
    dataflag.dataRai=0;
    ret = tcp_write(client->pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY, dataflag, 0);
    #endif
#else
    ret = tcp_write(client->pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY);
#endif
    if (ret == 0) {
        client->send_size += len;
        LLOGD("send more %d/%d", client->sent_size, client->send_size);
    }
    else {
        LLOGE("client_write err %d", ret);
    }
    // LLOGD("Client Write len %d ret %d", len, ret);
    return ret;
}

static void client_resp(void* arg) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    int code = client->code;
    const char* headers = client->headers;
    // const char* body = client->body;
    size_t body_size = client->body_size;
    //struct tcp_pcb* pcb = client->pcb;
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
    LLOGD("httpd resp %d %s body %d", code, msg, body_size);

    char buff[64];
    // 首先, 发送状态行
    sprintf(buff, "HTTP/1.0 %d %s\r\n", code, msg);
    //LLOGD("send status line %s", buff);
    client_write(client, buff, strlen(buff));
    
    // 然后, 发送长度和用户自定义的headers
    sprintf(buff, "Content-Length: %d\r\n", body_size);
    client_write(client, buff, strlen(buff));
    client_write(client, "Connection: close\r\n", strlen("Connection: close\r\n"));
    // client_write(client, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    if (headers && strlen(headers)) {
    //     LLOGD("send headers %d", strlen(headers));
        client_write(client, (char*)headers, strlen(headers));
    }
    client_write(client, "\r\n", 2);
    // 最后发送body
    if (body_size) {
        LLOGD("send body %d", body_size);
        client_write(client, client->body, body_size);
    }
    client->write_done = 1;
    LLOGD("resp done, total send %d", client->send_size);
    tcp_output(client->pcb);
}

//================================

static void client_cleanup(client_socket_ctx_t *client) {
    LLOGD("client cleanup!!!");
    if (client->uri) {
        luat_heap_free(client->uri);
        client->uri = NULL;
    }
    if (client->headers) {
        luat_heap_free(client->headers);
        client->headers = NULL;
    }
    if (client->body) {
        luat_heap_free(client->body);
        client->body = NULL;
    }
    if (client->buff) {
        luat_heap_free(client->buff);
        client->buff = NULL;
    }
    if (client->fd) {
        luat_fs_fclose(client->fd);
        client->fd = NULL;
    }
    luat_heap_free(client);
}

static int luat_client_cb(lua_State* L, void* ptr) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)ptr;
    lua_geti(L, LUA_REGISTRYINDEX, client->lua_ref_id);
    if (lua_isnil(L, -1)) {
        client_cleanup(client);
        return 0;
    }
    //lua_settop(L, 0);
    // 开始回调
    lua_pushinteger(L, (int)client->pcb);
    lua_pushstring(L, http_method_str(client->parser.method));
    lua_pushstring(L, client->uri);
    lua_newtable(L); // 暂时不解析headers
    lua_pushlstring(L, client->body, client->body_size);
    // 先释放掉
    luat_heap_free(client->uri);
    client->uri = NULL;
    if (client->body) {
        luat_heap_free(client->body);
        client->body = NULL;
        client->body_size = 0;
    }
    lua_call(L, 5, 3);

    int code = luaL_optinteger(L, -3, 404);
    if (code < 100)
        code = 200;
    size_t body_size = 0;
    const char* body = luaL_optlstring(L, -1, "", &body_size);
    if (body_size > 0) {
        client->body = luat_heap_malloc(body_size);
        client->body_size = body_size;
        memcpy(client->body, body, body_size);
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
    int ret = tcpip_callback(client_resp, client);
    if (ret) {
        LLOGE("tcpip_callback %d", ret); // 这就很不好搞了
        tcp_err(client->pcb, NULL);
        tcp_sent(client->pcb, NULL);
        tcp_abort(client->pcb);
        client_cleanup(client);
    }

    return 0;
}

//=============================

static err_t client_recv_cb(void *arg, struct tcp_pcb *tpcb,
                             struct pbuf *p, err_t err) {
    if (err) {
        LLOGD("tpcb %p err %d", tpcb, err);
        return ERR_OK;
    }
    if (p == NULL) {
        LLOGI("recv p is NULL");
        tcp_abort(tpcb);
        return ERR_ABRT;
    }
    LLOGD("tpcb %p p %p len %d err %d", tpcb, p, p->tot_len, err);
    client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
    if (ctx->buff == NULL) {
        ctx->buff = luat_heap_malloc(p->tot_len);
        if (ctx->buff == NULL) {
            LLOGW("out of memory when malloc client buff %d", p->tot_len);
            // pbuf_free(p); // 需要吗?
            tcp_abort(tpcb);
            return ERR_ABRT;
        }
        ctx->buff_offset = 0;
        ctx->buff_size = p->tot_len;
    }
    if (ctx->buff_offset + p->tot_len > ctx->buff_size) {
        char* ptr = luat_heap_realloc(ctx->buff, ctx->buff_offset + p->tot_len);
        if (ptr == NULL) {
            LLOGW("out of memory when realloc client buff %d", ctx->buff_offset + p->tot_len);
            luat_heap_free(ctx->buff);
            ctx->buff = NULL;
            tcp_abort(tpcb);
            return ERR_ABRT;
        }
        ctx->buff = ptr;
        ctx->buff_size = ctx->buff_offset + p->tot_len;
    }
    pbuf_copy_partial(p, ctx->buff + ctx->buff_offset, p->tot_len, 0);
    ctx->buff_offset += p->tot_len;
    //LLOGD("request %.*s", p->len, p->payload);
    tcp_recved(tpcb, p->tot_len);
    pbuf_free(p);

    ctx->parser.data = ctx;
    http_parser_init(&ctx->parser, HTTP_REQUEST);
    size_t ret = http_parser_execute(&ctx->parser, &hp_settings, (const char*)ctx->buff, ctx->buff_offset);
    if (ret) {
        // 暂时不管
    }

    if (ctx->recv_done) {
        // 停止接收更多的数据
        tcp_recv(tpcb, NULL);
        luat_heap_free(ctx->buff);
        ctx->buff = NULL;
        LLOGD("http request is ready");
        if (ctx->parser.http_errno != HPE_OK || ctx->uri == NULL) {
            LLOGI("bad request, close socket");
            tcp_close(tpcb);
            return ERR_OK;
        }
        ctx->recv_done = 0;
        if (handle_static_file(ctx)) {
            // tcp_close(tpcb);
            return ERR_OK;
        }
        rtos_msg_t msg = {
            .handler = luat_client_cb,
            .ptr = ctx
        };
        luat_msgbus_put(&msg, 0);
    }
    else {
        LLOGD("wait more data");
    }

    return ERR_OK;
}
static err_t client_sent_cb(void *arg, struct tcp_pcb *tpcb, u16_t len) {
    (void)tpcb;
    client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
    ctx->sent_size += len;
    int ret = 0;
    if (ctx->fd) {
        if (ctx->sbuff_offset) {
            ret = client_write(ctx, (const char*)ctx->sbuff, ctx->sbuff_offset);
            if (ret == 0) {
                // ctx->send_size += ctx->sbuff_offset;
                ctx->sbuff_offset = 0;
            }
        }
        else {
            while (tcp_sndbuf(tpcb) > 1400)
            {
                ret = luat_fs_fread(ctx->sbuff, 1400, 1, ctx->fd);
                if (ret < 1) {
                    luat_fs_fclose(ctx->fd);
                    ctx->fd = NULL;
                    // tcp_err(ctx->pcb, NULL);
                    // tcp_sent(ctx->pcb, NULL);
                    // tcp_close(ctx->pcb);
                    // client_cleanup(ctx);
                    ctx->write_done = 1;
                    break;
                }
                else {
                    ctx->sbuff_offset = ret;
                    ret = client_write(ctx, (const char*)ctx->sbuff, ctx->sbuff_offset);
                    if (ret == 0) {
                        // ctx->send_size += ctx->sbuff_offset;
                        ctx->sbuff_offset = 0;
                    }
                    ctx->sbuff_offset = 0;
                }
            }
        }
    }
    LLOGD("done? %d sent %d/%d", ctx->write_done, ctx->sent_size, ctx->send_size);
    if (ctx->write_done && ctx->send_size == ctx->sent_size) {
        tcp_err(ctx->pcb, NULL);
        tcp_sent(ctx->pcb, NULL);
        tcp_close(ctx->pcb);
        client_cleanup(ctx);
    }
    // LLOGD("sent %d/%d", ctx->sent_size, ctx->send_size);
    // ctx->send_size -= len;
    // if (ctx->send_size == 0) {
    //     // tcp_err(tpcb, NULL);
    //     // if (tcp_close(tpcb)) {
    //     //     tcp_abort(tpcb);
    //     // };
    //     // client_cleanup(ctx);
    // }
    return ERR_OK;
}
static void client_err_cb(void *arg, err_t err) {
    LLOGD("client_err_cb %d", err);
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    if(ERR_RST == err)
    {
        tcp_err(client->pcb, NULL);
        tcp_sent(client->pcb, NULL);
    }
    client_cleanup(client);
}

static err_t srv_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err) {
    if (err) {
        LLOGD("accpet err %d", err);
        tcp_abort(newpcb);
        return ERR_OK;
    }
    luat_httpsrv_ctx_t* srvctx = (luat_httpsrv_ctx_t*) arg;
    client_socket_ctx_t* ctx = luat_heap_malloc(sizeof(client_socket_ctx_t));
    if (ctx == NULL) {
        LLOGD("out of memory when malloc client ctx");
        tcp_abort(newpcb);
        return ERR_ABRT;
    }
    tcp_accepted(newpcb);
    memset(ctx, 0, sizeof(client_socket_ctx_t));
    ctx->pcb = newpcb;
    ctx->lua_ref_id = srvctx->lua_ref_id;
    tcp_arg(newpcb, ctx);
    tcp_recv(newpcb, client_recv_cb);
    tcp_sent(newpcb, client_sent_cb);
    tcp_err(newpcb, client_err_cb);
    return ERR_OK;
}

static void srv_stop_cb(void* arg) {
    luat_httpsrv_ctx_t* ctx = (luat_httpsrv_ctx_t*)arg;
    if (ctx == NULL) {
        return;
    }
    if (ctx->pcb) {
        tcp_recv(ctx->pcb, NULL);
        tcp_sent(ctx->pcb, NULL);
        if(tcp_close(ctx->pcb))
        {
            tcp_abort(ctx->pcb);
        }
        ctx->pcb = NULL;
    }
    luat_httpsrv_free(ctx);
}
int luat_httpsrv_stop(luat_httpsrv_ctx_t* ctx) {
    tcpip_callback(srv_stop_cb, ctx);
    return 0;
}

static void luat_httpsrv_start_cb(luat_httpsrv_ctx_t* ctx) {
    struct tcp_pcb* tcp = tcp_new();
    int ret = 0;
    if (tcp == NULL) {
        LLOGD("out of memory when malloc httpsrv tcp_pcb");
        return;
    }
    tcp->flags |= SOF_REUSEADDR;
    ret = tcp_bind(tcp, &ctx->netif->ip_addr, ctx->port);
    if (ret) {
        LLOGD("httpsrv bind port %d ret %d", ctx->port);
        return;
    }
    ctx->pcb = tcp_listen_with_backlog(tcp, 1);
    tcp_arg(ctx->pcb, ctx);
    tcp_accept(ctx->pcb, srv_accept_cb);
    return;
}

luat_httpsrv_ctx_t* luat_httpsrv_malloc(int port, int adapter_index) {
    luat_httpsrv_ctx_t* ctx = luat_heap_malloc(sizeof(luat_httpsrv_ctx_t));
    if (ctx == NULL) {
        LLOGD("out of memory when malloc httpsrv ctx");
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_httpsrv_ctx_t));
    ctx->port = port;
    ctx->adapter_id = adapter_index;
    return ctx;
}

int luat_httpsrv_free(luat_httpsrv_ctx_t* ctx) {
    if (ctx == NULL) {
        return 0;
    }
    luat_heap_free(ctx);
    ctx = NULL;
    return 0;
} 

int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx) {
    int ret = tcpip_callback(luat_httpsrv_start_cb, ctx);
    if (ret) {
        LLOGE("启动失败 %d", ret);
    }
    return ret;
}

// 静态文件的处理

static int client_send_static_file(client_socket_ctx_t *client, char* path, size_t len) {
    LLOGD("sending %s", path);
    // 发送文件, 解析出content-type
    char *buff = client->sbuff;
    // 首先, 发送状态行
    client_write(client, "HTTP/1.0 200 OK\r\n", strlen("HTTP/1.0 200 OK\r\n"));
    // 发送长度
    sprintf(buff, "Content-Length: %d\r\n", len);
    client_write(client, buff, strlen(buff));
    client_write(client, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    // 解析content-type, 并发送
    size_t path_size = strlen(path);
    buff[0] = 0x00;
    for (size_t i = 0; i < sizeof(ct_regs)/sizeof(ct_regs[0]); i++)
    {
        const char* suff = ct_regs[i].suff;
        size_t suff_size = strlen(suff);
        // 判断后缀
        if (path_size > suff_size + 2) {
            if (!memcmp(path + path_size - suff_size, suff, suff_size)) {
                sprintf(buff, "Content-Type: %s\r\n", ct_regs[i].value);
                break;
            }
        }
    }
    // 根据path判断一下文件后缀, 如果不是 html/htm/js/css就当文件下载
    size_t plen = strlen(path);
    if (strcmp(path + plen - 5, ".html") == 0 || strcmp(path + plen - 4, ".htm") == 0
        || strcmp(path + plen - 3, ".js") == 0 || strcmp(path + plen - 4, ".css") == 0) {
        // nop
        LLOGD("普通文件模式 %s", path);
    }
    else {
        LLOGD("启用文件下载模式 %s", path);
        sprintf(buff, "Content-Disposition: attachment; filename=\"%s\"\r\n", strrchr(path, '/') + 1);
    }

    if (buff[0] == 0) {
        client_write(client, "Content-Type: application/octet-stream\r\n", strlen("Content-Type: application/octet-stream\r\n"));
    }
    else {
        client_write(client, buff, strlen(buff));
    }
    
    // 头部发送完成
    client_write(client, "\r\n", 2);

    // 发送body
    FILE*  fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        tcp_recv(client->pcb, NULL);
        tcp_sent(client->pcb, NULL);
        if(tcp_close(client->pcb))
        {
            tcp_abort(client->pcb);
        }
        LLOGE("open %s FAIL!!", path);
        return 1;
    }
    client->fd = fd;
    client->sbuff_offset = 0;
    return 0;
}

static int handle_static_file(client_socket_ctx_t *client) {
    //处理静态文件
    if (strlen(client->uri) < 1 || strlen(client->uri) > 200) {
        // 太长就不支持了
        LLOGD("path too long [%s] > 200", client->uri);
        return 0;
    }
    // 检查路径遍历攻击
    if (strstr(client->uri, "..") != NULL) {
        LLOGW("path traversal attack detected: %s", client->uri);
        return 0;
    }
    char path[256] = {0};
    const char* uri_to_use = strlen(client->uri) == 1 ? "/index.html" : client->uri;
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

    client_send_static_file(client, path, fz);
    // client_cleanup(client);
    return 1;
}


// ==============================
// 处理请求

// static int my_on_message_begin(http_parser* parser) {
//     LLOGD("on_message_begin");
//     return 0;
// }

// static int my_on_headers_complete(http_parser* parser) {
//     LLOGD("on_headers_complete");
//     return 0;
// }

static int my_on_message_complete(http_parser* parser) {
    LLOGD("on_message_complete");
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->expect_body_size > 0 && client->body_size < client->expect_body_size) {
        LLOGD("body size not match expect %d/%d", client->body_size, client->expect_body_size);
        return HPE_INVALID_CONTENT_LENGTH;
    }
    client->recv_done = 1;
    return 0;
}

// static int my_on_chunk_header(http_parser* parser) {
//     LLOGD("on_chunk_header");
//     return 0;
// }

// static int my_on_chunk_complete(http_parser* parser) {
//     LLOGD("on_chunk_complete");
//     return 0;
// }

static int my_on_url(http_parser* parser, const char *at, size_t length) {
    LLOGD("on_header_url %p %d", at, length);
    if (length > 1024) {
        LLOGW("request URL is too long!!! %d", length);
        return HPE_INVALID_URL;
    }
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    client->uri = luat_heap_malloc(length + 1);
    if (client->uri) {
        memcpy(client->uri, at, length);
        client->uri[length] = 0;
    }
    else {
        LLOGE("fail to malloc uri!!!");
        return HPE_INVALID_URL;
    }
    return 0;
}

// static int my_on_status(http_parser* parser, const char *at, size_t length) {
//     // 这个函数应该是不会出现的
//     LLOGD("on_header_status %p %d", at, length);
//     return 0;
// }

static int my_on_header_field(http_parser* parser, const char *at, size_t length) {
    // LLOGI("on_header_field %.*s", (int)length, at);
    if (length == 14 && !memcmp(at, "Content-Length", 14)) {
        client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
        client->next_header_value_is_content_length = 1;
    }
    else {
        client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
        client->next_header_value_is_content_length = 0;
    }
    return 0;
}

static int my_on_header_value(http_parser* parser, const char *at, size_t length) {
    // LLOGI("on_header_value %.*s", (int)length, at);
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->next_header_value_is_content_length) {
        client->expect_body_size = atoi(at);
        client->next_header_value_is_content_length = 0;
    }
    return 0;
}

static int my_on_body(http_parser* parser, const char *at, size_t length) {
    LLOGD("on_body %p %d", at, length);
    if (length == 0)
        return 0;
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->expect_body_size > 0 && length < client->expect_body_size) {
        return 0; // 等数据
    }
    if (client->body == NULL) {
        client->body = luat_heap_malloc(client->expect_body_size > 0 ? client->expect_body_size : length);
        //client->body_size = length;
        if (client->body == NULL) {
            LLOGE("malloc body FAIL!!!");
            return HPE_INVALID_STATUS;
        }
    }
    else {
        // TODO 做成链表
        char* tmp = luat_heap_realloc(client->body, length);
        if (tmp == NULL) {
            LLOGE("realloc body FAIL!!! %d", length);
            return HPE_INVALID_STATUS;
        }
        client->body = tmp;
    }
    memcpy(client->body, at, length);
    client->body_size = length;
    return 0;
}

// ==============================
