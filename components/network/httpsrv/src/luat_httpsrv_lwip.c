#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
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

// #define HTTPSRV_MAX (4)
// static luat_httpsrv_ctx_t ctxs[HTTPSRV_MAX];

// #define CLIENT_BUFF_SIZE (4096)

// #define HTTP_RESP_400 "HTTP/1.0 400 Bad Request\r\n"
// #define HTTP_RESP_200 "HTTP/1.0 200 OK\r\n"
// #define HTTP_RESP_302 "HTTP/1.0 302 Found\r\n"
// #define HTTP_RESP_404 "HTTP/1.0 404 Not Found\r\n"


typedef struct client_socket_ctx
{
    // int id;
    int code;
    struct http_parser parser;

    char *uri;
    // char *headers;
    char *body;

    size_t body_size;
    uint32_t recv_done;
    char *buff;
    size_t buff_offset;
    struct tcp_pcb* pcb;
    // size_t send_size;
}client_socket_ctx_t;

static struct tcp_pcb* srvpcb;
static int lua_ref_id;

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
// static int my_on_header_field(http_parser* parser, const char *at, size_t length);
// static int my_on_header_value(http_parser* parser, const char *at, size_t length);
static int my_on_body(http_parser* parser, const char *at, size_t length);

//================================
// client methods

static const struct http_parser_settings hp_settings = {
    // .on_message_begin = my_on_message_begin,
    .on_url = my_on_url,
    // .on_status = my_on_status,
    // .on_header_field = my_on_header_field,
    // .on_header_value = my_on_header_value,
    // .on_headers_complete = my_on_headers_complete,
    .on_body = my_on_body,
    .on_message_complete = my_on_message_complete,
    // .on_chunk_header = my_on_chunk_header,
    // .on_chunk_complete = my_on_chunk_complete
};
//================================

static void client_write(client_socket_ctx_t* client, char* buff, size_t len) {
    if (len == 0)
        return;
    // client->send_size += len;
#if ENABLE_PSIF
    tcp_write(client->pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY, 0, 0, 0);
#else
    tcp_write(client->pcb, (const void*)buff, len, TCP_WRITE_FLAG_COPY);
#endif
}

static void client_resp(void* arg) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)arg;
    int code = client->code;
    // const char* headers = NULL;
    // const char* body = client->body;
    size_t body_size = client->body_size;
    struct tcp_pcb* pcb = client->pcb;
    const char* msg = "";
    for (size_t i = 0; i < sizeof(http_codes)/sizeof(http_code_str_t); i++)
    {
        if (http_codes[i].code == code) {
            msg = http_codes[i].msg;
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
    client_write(client, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    // if (headers && strlen(headers)) {
    //     LLOGD("send headers %d", strlen(headers));
    //     client_write(client, (char*)headers, strlen(headers));
    // }
    client_write(client, "\r\n", 2);
    // 最后发送body
    if (body_size) {
        LLOGD("send body %d", body_size);
        client_write(client, client->body, body_size);
    }
    client_cleanup(client);
    tcp_output(pcb);
    tcp_close(pcb);
}

//================================

static void client_cleanup(client_socket_ctx_t *client) {
    if (client->uri) {
        luat_heap_free(client->uri);
        client->uri = NULL;
    }
    // if (client->headers)
    //     luat_heap_free(client->headers);
    if (client->body) {
        luat_heap_free(client->body);
        client->body = NULL;
    }
    luat_heap_free(client);
    LLOGD("client cleanup!!!");
}

static int luat_client_cb(lua_State* L, void* ptr) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)ptr;
    lua_geti(L, LUA_REGISTRYINDEX, lua_ref_id);
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
    client->code = code;
    int ret = tcpip_callback(client_resp, client);
    if (ret) {
        LLOGE("tcpip_callback %d", ret);
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
    LLOGD("tpcb %p p %p len %d err %d", tpcb, p, p->len, err);
    client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
    if (ctx->buff == NULL) {
        ctx->buff = luat_heap_malloc(4096);
        if (ctx->buff == NULL) {
            LLOGD("out of memory when malloc client buff");
            // pbuf_free(p); // 需要吗?
            tcp_abort(tpcb);
            return ERR_ABRT;
        }
        ctx->buff_offset = 0;
    }
    memcpy(ctx->buff + ctx->buff_offset, p->payload, p->len);
    ctx->buff_offset += p->len;
    //LLOGD("request %.*s", p->len, p->payload);
    tcp_recved(tpcb, p->len);
    pbuf_free(p);

    ctx->parser.data = ctx;
    http_parser_init(&ctx->parser, HTTP_REQUEST);
    size_t ret = http_parser_execute(&ctx->parser, &hp_settings, (const char*)ctx->buff, ctx->buff_offset);

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
            tcp_close(tpcb);
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
// static err_t client_sent_cb(void *arg, struct tcp_pcb *tpcb, u16_t len) {
//     client_socket_ctx_t* ctx = (client_socket_ctx_t*)arg;
//     LLOGD("sent %d/%d", len, ctx->send_size);
//     // ctx->send_size -= len;
//     // if (ctx->send_size == 0) {
//     //     // tcp_err(tpcb, NULL);
//     //     // if (tcp_close(tpcb)) {
//     //     //     tcp_abort(tpcb);
//     //     // };
//     //     // client_cleanup(ctx);
//     // }
//     return ERR_OK;
// }
// static err_t client_err_cb(void *arg, err_t err) {
//     LLOGD("client err %d", err);
//     return ERR_OK;
// }

static err_t srv_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err) {
    if (err) {
        LLOGD("accpet err %d", err);
        return ERR_OK;
    }
    client_socket_ctx_t* ctx = luat_heap_malloc(sizeof(client_socket_ctx_t));
    if (ctx == NULL) {
        LLOGD("out of memory when malloc client ctx");
        tcp_abort(newpcb);
        return ERR_ABRT;
    }
    tcp_accepted(newpcb);
    memset(ctx, 0, sizeof(client_socket_ctx_t));
    ctx->pcb = newpcb;
    tcp_arg(newpcb, ctx);
    tcp_recv(newpcb, client_recv_cb);
    // tcp_sent(newpcb, client_sent_cb);
    // tcp_err(newpcb, client_err_cb);
    return ERR_OK;
}

int luat_httpsrv_stop(int port) {
    if (srvpcb != NULL) {
        tcp_close(srvpcb);
        srvpcb = NULL;
    }
    return 0;
}

int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx) {
    if (srvpcb != NULL) {
        LLOGE("only allow 1 httpsrv");
        return -10;
    }
    struct tcp_pcb* tcp = tcp_new();
    int ret = 0;
    if (tcp == NULL) {
        LLOGD("out of memory when malloc httpsrv tcp_pcb");
        return -1;
    }
    tcp->flags |= SOF_REUSEADDR;
    ret = tcp_bind(tcp, NULL, ctx->port);
    if (ret) {
        LLOGD("httpsrv bind port %d ret %d", ctx->port);
        return -2;
    }
    lua_ref_id = ctx->lua_ref_id;
    srvpcb = tcp_listen(tcp);
    tcp_arg(srvpcb, NULL);
    tcp_accept(srvpcb, srv_accept_cb);
    return 0;
}

// 静态文件的处理

static int client_send_static_file(client_socket_ctx_t *client, char* path, size_t len, uint8_t is_gz) {
    LLOGD("sending %s", path);
    // 发送文件, 需要区分gz, 还得解析出content-type
    char buff[512] = {0};
    // 首先, 发送状态行
    client_write(client, "HTTP/1.0 200 OK\r\n", strlen("HTTP/1.0 200 OK\r\n"));
    // 发送长度
    sprintf(buff, "Content-Length: %d\r\n", len);
    client_write(client, buff, strlen(buff));
    client_write(client, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    // 如果是gz, 发送压缩头部
    if (is_gz) {
        client_write(client, "Content-Encoding: gzip\r\n", strlen("Content-Encoding: gzip\r\n"));
    }
    // 解析content-type, 并发送
    size_t path_size = strlen(path);
    buff[0] = 0x00;
    for (size_t i = 0; i < sizeof(ct_regs)/sizeof(ct_regs[0]); i++)
    {
        const char* suff = ct_regs[i].suff;
        size_t suff_size = strlen(suff);
        // 判断后缀,不含.gz
        if (path_size > suff_size + 2) {
            if (!memcmp(path + path_size - suff_size, suff, suff_size)) {
                sprintf(buff, "Content-Type: %s\r\n", ct_regs[i].value);
                break;
            }
        }
        if (is_gz && path_size > suff_size + 5) {
            if (!memcmp(path + path_size - suff_size - 3, suff, suff_size)) {
                sprintf(buff, "Content-Type: %s\r\n", ct_regs[i].value);
                break;
            }
        }
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
        LLOGE("open %s FAIL!!", path);
        return 1;
    }
    while (1) {
        int slen = luat_fs_fread(buff, 512, 1, fd);
        if (slen < 1)
            break;
        client_write(client, buff, slen);
    }
    luat_fs_fclose(fd);
    return 0;
}

static int handle_static_file(client_socket_ctx_t *client) {
    //处理静态文件
    if (strlen(client->uri) < 1 || strlen(client->uri) > 20) {
        // 太长就不支持了
        return 0;
    }
    char path[64] = {0};
    uint8_t is_gz = 0;
    sprintf(path, "/luadb%s", strlen(client->uri) == 1 ? "/index.html" : client->uri);
    size_t fz = luat_fs_fsize(path);
    if (fz < 1) {
        sprintf(path, "/luadb%s.gz", strlen(client->uri) == 1 ? "/index.html" : client->uri);
        fz = luat_fs_fsize(path);
        if (fz < 1) {
            return 0;
        }
        is_gz = 1;
    }

    client_send_static_file(client, path, fz, is_gz);
    client_cleanup(client);
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
        LLOGW("request URL is too long!!!");
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

// static int my_on_header_field(http_parser* parser, const char *at, size_t length) {
//     // LLOGD("on_header_field %p %d", at, length);
//     return 0;
// }

// static int my_on_header_value(http_parser* parser, const char *at, size_t length) {
//     // LLOGD("on_header_value %p %d", at, length);
//     return 0;
// }

static int my_on_body(http_parser* parser, const char *at, size_t length) {
    LLOGD("on_body %p %d", at, length);
    if (length == 0)
        return 0;
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    if (client->body == NULL) {
        client->body = luat_heap_malloc(length);
        //client->body_size = length;
        if (client->body == NULL) {
            LLOGE("malloc body FAIL!!!");
            return HPE_INVALID_STATUS;
        }
    }
    else {
        char* tmp = luat_heap_realloc(client->body, client->body_size + length);
        if (tmp == NULL) {
            LLOGE("realloc body FAIL!!!");
            return HPE_INVALID_STATUS;
        }
        client->body = tmp;
    }
    memcpy(client->body + client->body_size, at, length);
    client->body_size += length;
    return 0;
}

// ==============================
