#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_httpsrv.h"
#include "luat_fs.h"

#if (defined(CONFIG_IDF_CMAKE))
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include <netinet/in.h>
#include <unistd.h>
#include <sys/socket.h>
#else
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "lwip/opt.h"
#include "lwip/sockets.h"
#endif

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "http_parser.h"

#define HTTPSRV_MAX (4)
static luat_httpsrv_ctx_t ctxs[HTTPSRV_MAX];

#define CLIENT_BUFF_SIZE (4096)

#define HTTP_RESP_400 "HTTP/1.0 400 Bad Request\r\n"
#define HTTP_RESP_200 "HTTP/1.0 200 OK\r\n"
#define HTTP_RESP_302 "HTTP/1.0 302 Found\r\n"
#define HTTP_RESP_404 "HTTP/1.0 404 Not Found\r\n"


typedef struct client_socket_ctx
{
    int id;
    int client_fd;
    SemaphoreHandle_t sem;
    struct http_parser parser;

    char *uri;
    char *headers;
    char *body;

    size_t body_size;
    uint32_t recv_done;
}client_socket_ctx_t;

static inline int tcp_send(int fd, char* data, size_t len) {
    return send(fd, data, len, 0);
}

static void client_cleanup(client_socket_ctx_t *client);

static void client_resp(client_socket_ctx_t* client, int code, const char* headers, const char* body, size_t body_size) {
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
    tcp_send(client->client_fd, buff, strlen(buff));
    
    // 然后, 发送长度和用户自定义的headers
    sprintf(buff, "Content-Length: %d\r\n", body_size);
    tcp_send(client->client_fd, buff, strlen(buff));
    tcp_send(client->client_fd, "Connection: close\r\n", strlen("Connection: close\r\n"));
    tcp_send(client->client_fd, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    if (strlen(headers)) {
        LLOGD("send headers");
        tcp_send(client->client_fd, (char*)headers, strlen(headers));
    }
    tcp_send(client->client_fd, "\r\n", 2);
    // 最后发送body
    if (body_size) {
        LLOGD("send body %d", body_size);
        tcp_send(client->client_fd, (char*)body, body_size);
    }
    tcp_send(client->client_fd, "", 0);
}

static int luat_client_cb(lua_State* L, void* ptr) {
    client_socket_ctx_t* client = (client_socket_ctx_t*)ptr;
    lua_geti(L, LUA_REGISTRYINDEX, ctxs[client->id].lua_ref_id);
    if (lua_isnil(L, -1))
        return 0;
    //lua_settop(L, 0);
    // 开始回调
    lua_pushinteger(L, client->client_fd);
    lua_pushstring(L, http_method_str(client->parser.method));
    lua_pushstring(L, client->uri);
    lua_newtable(L); // 暂时不解析headers
    lua_pushlstring(L, client->body, client->body_size);
    lua_call(L, 5, 3);

    int code = luaL_optinteger(L, -3, 404);
    if (code < 100)
        code = 200;
    size_t body_size = 0;
    const char* body = luaL_optlstring(L, -1, "", &body_size);

    client_resp(client, code, "", body, body_size);
    client_cleanup(client);
    return 0;
}

static int recv_timeout(int s, void *mem, size_t len, int flags, int timeout) {
    int ret;
    struct timeval tv;
    fd_set read_fds;
    int fd = s;

    FD_ZERO( &read_fds );
    FD_SET( fd, &read_fds );

    tv.tv_sec  = timeout / 1000;
    tv.tv_usec = ( timeout % 1000 ) * 1000;

    ret = select( fd + 1, &read_fds, NULL, NULL, timeout == 0 ? NULL : &tv );

    /* Zero fds ready means we timed out */
    if( ret == 0 )
        return 0;

    if( ret < 0 )
    {
        return ret;
    }

    /* This call will not block */
    return recv( fd, mem, len, flags);
}

// client methods

static int my_on_message_begin(http_parser* parser) {
    LLOGD("on_message_begin");
    return 0;
}

static int my_on_headers_complete(http_parser* parser) {
    LLOGD("on_headers_complete");
    return 0;
}

static int my_on_message_complete(http_parser* parser) {
    LLOGD("on_message_complete");
    client_socket_ctx_t* client = (client_socket_ctx_t*)parser->data;
    client->recv_done = 1;
    return 0;
}

static int my_on_chunk_header(http_parser* parser) {
    LLOGD("on_chunk_header");
    return 0;
}

static int my_on_chunk_complete(http_parser* parser) {
    LLOGD("on_chunk_complete");
    return 0;
}

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

static int my_on_status(http_parser* parser, const char *at, size_t length) {
    // 这个函数应该是不会出现的
    LLOGD("on_header_status %p %d", at, length);
    return 0;
}

static int my_on_header_field(http_parser* parser, const char *at, size_t length) {
    // LLOGD("on_header_field %p %d", at, length);
    return 0;
}

static int my_on_header_value(http_parser* parser, const char *at, size_t length) {
    // LLOGD("on_header_value %p %d", at, length);
    return 0;
}

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

static const struct http_parser_settings hp_settings = {
    .on_message_begin = my_on_message_begin,
    .on_url = my_on_url,
    .on_status = my_on_status,
    .on_header_field = my_on_header_field,
    .on_header_value = my_on_header_value,
    .on_headers_complete = my_on_headers_complete,
    .on_body = my_on_body,
    .on_message_complete = my_on_message_complete,
    .on_chunk_header = my_on_chunk_header,
    .on_chunk_complete = my_on_chunk_complete
};

static void client_cleanup(client_socket_ctx_t *client) {
    close(client->client_fd);
    // vSemaphoreDelete(client->sem);
    if (client->uri)
        luat_heap_free(client->uri);
    // if (client->method)
    //     luat_heap_free(client->method);
    if (client->headers)
        luat_heap_free(client->headers);
    if (client->body)
        luat_heap_free(client->body);
    luat_heap_free(client);
    LLOGD("client cleanup!!!");
}


static int client_send_static_file(client_socket_ctx_t *client, char* path, size_t len, uint8_t is_gz) {
    // 发送文件, 需要区分gz, 还得解析出content-type
    char buff[1024] = {0};
    int s = client->client_fd;
    // 首先, 发送状态行
    tcp_send(s, "HTTP/1.0 200 OK\r\n", strlen("HTTP/1.0 200 OK\r\n"));
    // 发送长度
    sprintf(buff, "Content-Length: %d\r\n", len);
    tcp_send(s, buff, strlen(buff));
    tcp_send(client->client_fd, "X-Powered-By: LuatOS\r\n", strlen("X-Powered-By: LuatOS\r\n"));
    // 如果是gz, 发送压缩头部
    if (is_gz) {
        tcp_send(s, "Content-Encoding: gzip\r\n", strlen("Content-Encoding: gzip\r\n"));
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
        tcp_send(s, "Content-Type: application/octet-stream\r\n", strlen("Content-Type: application/octet-stream\r\n"));
    }
    else {
        tcp_send(s, buff, strlen(buff));
    }
    
    // 头部发送完成
    tcp_send(s, "\r\n", 2);

    // 发送body
    FILE*  fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGE("open %s FAIL!!", path);
        return 1;
    }
    while (1) {
        int slen = luat_fs_fread(buff, 1024, 1, fd);
        if (slen < 1)
            break;
        tcp_send(s, buff, slen);
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
    return 1;
}

static void httpsrv_client_task(void* arg) {
    client_socket_ctx_t *client = (client_socket_ctx_t *)arg;
    client->parser.data = client;
    http_parser_init(&client->parser, HTTP_REQUEST);

    int time_start = xTaskGetTickCount();
    LLOGD("httpd client start time %d", time_start);

    int ret = 0;
    char buff[1024];
    size_t nparsed = 0;
    
    // 开始读取请求
    while (client->recv_done == 0) {
        nparsed = 0;
        ret = recv_timeout(client->client_fd, buff, 1024, 0, 100);
        LLOGD("socket %d recv %d", client->client_fd, ret);
        if (ret < 0) {
            LLOGD("client recv err %d", ret);
            break;
        }
        if (ret > 0) {
            // 有数据
            nparsed = http_parser_execute(&client->parser, &hp_settings, (const char*)buff, ret);
            LLOGD("nparsed %d recv %d", nparsed, ret);
            if (client->parser.http_errno != HPE_OK) {
                LLOGW("http parse err %d", client->parser.http_errno);
                break;
            }
        }
        if (ret == 0) {
            if (xTaskGetTickCount() - time_start > 5000) {
                nparsed = http_parser_execute(&client->parser, &hp_settings, (const char*)buff, 0);
                LLOGD("5s timeout, parse end");
                break;
            }
        }
        if (http_body_is_final(&client->parser)) {
            LLOGD("body final");
            break;
        }
    }

    // 拦截一下非法请求
    if (client->parser.http_errno != HPE_OK || client->uri == NULL) {
        LLOGI("bad request, return http 400");
        client_resp(client, 400, "", "Bad Request", strlen("Bad Request"));
        client_cleanup(client);
        vTaskDelete(NULL);
        return;
    }

    // 看看是不是静态文件
    // if (client->parser.method == HTTP_GET && handle_static_file(client)) {
    if (handle_static_file(client)) {
        client_cleanup(client);
        vTaskDelete(NULL);
        return;
    }

    rtos_msg_t msg = {0};
    msg.handler = luat_client_cb;
    msg.ptr = client;
    luat_msgbus_put(&msg, 0);

    // 任务完成, 在msgbus里调用回调函数
    vTaskDelete(NULL);
}

static void httpsrv_main_task(void* arg) {
    struct sockaddr_in address;
    int cliend_fd;
    int addrlen = sizeof(address);
    int server_fd = ctxs[(int)arg].server_fd;
    int ret = 0;
    while (1)
    {
        LLOGD("http accept wait");
        cliend_fd = accept(server_fd, (struct sockaddr*)&address, (socklen_t*)&addrlen);
        LLOGD("http accept %d", cliend_fd);
        if (cliend_fd < 0) {
            LLOGI("http server exist");
            break;
        }
        struct timeval tv;
        /* Set recv timeout of this fd as per config */
        tv.tv_sec = 3000;
        tv.tv_usec = 0;
        setsockopt(cliend_fd, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));

        /* Set send timeout of this fd as per config */
        tv.tv_sec = 1000;
        tv.tv_usec = 0;
        setsockopt(cliend_fd, SOL_SOCKET, SO_SNDTIMEO, (const char *)&tv, sizeof(tv));

        LLOGD("prepare client_socket_ctx_t");

        client_socket_ctx_t *client = luat_heap_malloc(sizeof(client_socket_ctx_t));
        if (client == NULL) {
            LLOGE("start client socket thread failed!!");
            close(cliend_fd);
            continue;
        }
        memset(client, 0, sizeof(client_socket_ctx_t));
        // client->sem = xSemaphoreCreateMutex();
        client->client_fd = cliend_fd;
        client->id = (int)arg;
        ret = xTaskCreate(httpsrv_client_task, "httpdc", 2*1024, (void*)client, tskIDLE_PRIORITY+3, NULL);
        if (ret != pdPASS) {
            LLOGE("start client socket thread failed!!");
            close(cliend_fd);
            // vSemaphoreDelete(client->sem);
            luat_heap_free(client);
            continue;
        }
        LLOGD("httpd client task started");
    }
    vTaskDelete(NULL);
}

int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx) {
    int id = -1;
    for (size_t i = 0; i < HTTPSRV_MAX; i++)
    {
        if (ctxs[i].port == 0) {
            id = i;
            break;
        }
    }
    if (id < 0) {
        LLOGE("too many http server , start failed");
        return -1;
    }

    memcpy(&ctxs[id], ctx, sizeof(luat_httpsrv_ctx_t));

    // 开始初始化
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd == 0) {
        LLOGE("create server socket failed!!");
        luat_httpsrv_stop(ctx->port);
        return -1;
    }
    ctxs[id].server_fd = server_fd;
    int opt = 1;
    struct sockaddr_in address;
    // int addrlen = sizeof(address);
    // char buffer[1024] = { 0 };

    int enable = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &enable, sizeof(enable));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(ctx->port);

    if (bind(server_fd, (struct sockaddr*)&address,sizeof(address)) < 0) {
        LLOGE("server socket bind failed!!");
        luat_httpsrv_stop(ctx->port);
        return -3;
    }
    if (listen(server_fd, 3) < 0) {
        LLOGE("server socket bind failed!!");
        luat_httpsrv_stop(ctx->port);
        return -3;
    }

    int ret = xTaskCreate(httpsrv_main_task, "httpd", 4*1024, (void*)id, tskIDLE_PRIORITY+3, NULL);
    if (ret != pdPASS) {
        LLOGE("start server socket thread failed!!");
        luat_httpsrv_stop(ctx->port);
        return -4;
    }
    LLOGI("http listen at 0.0.0.0:%d", ctx->port);
    return 0;
}

int luat_httpsrv_stop(int port) {
    for (size_t i = 0; i < HTTPSRV_MAX; i++)
    {
        if (ctxs[i].port == port) {
            if (ctxs[i].server_fd) {
                shutdown(ctxs[i].server_fd, SHUT_RDWR);
            }
            ctxs[i].port = 0;
            return 0;
        }
    }
    return -1;
}
