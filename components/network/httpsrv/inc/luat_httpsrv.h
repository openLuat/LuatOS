#ifndef LUAT_HTTPSRV_H
#define LUAT_HTTPSRV_H

#include "luat_base.h"
#include "http_parser.h"

#include "luat_httpsrv_transport.h"

struct netif;   // 仅 lwIP 后端使用, 指向绑定的网卡

struct http_req_header;

// 服务端上下文. hlisten/priv 是后端句柄, 上层不解释其具体类型.
typedef struct luat_httpsrv_ctx
{
    uint16_t port;
    uint8_t adapter_id;     // NW_ADAPTER_INDEX_LWIP_ANY(127) 表示绑定全部网卡
    int lua_ref_id;
    const luat_httpsrv_transport_t* vt;
    void* hlisten;           // 后端监听句柄: tcp_pcb* 或 socket fd
    void* priv;              // 后端私有数据: lwIP 存 netif, posix 存 posix_srv_t*
    void* start_sem;        // luat_rtos_semaphore_t, start 同步用
    int start_ret;          // 后端线程回写的 bind/listen 结果
}luat_httpsrv_ctx_t;


typedef struct http_code_str
{
    int code;
    const char* msg;
}http_code_str_t;

// 声明http_codes数组，定义在luat_httpsrv_http.c中
extern const http_code_str_t g_luat_http_codes[];


typedef struct ct_reg
{
    const char* suff;
    const char* value;
}ct_reg_t;


typedef struct http_req_header
{
    struct http_req_header* next;
    uint16_t key_len;
    uint16_t value_len;
    char data[32];
}http_req_header_t;

// 客户端(连接)上下文. 一个请求一个, 由后端独占, 共享层只负责 HTTP 语义.
typedef struct client_socket_ctx
{
    const luat_httpsrv_transport_t* vt;
    void* hconn;             // 连接句柄: tcp_pcb* 或 socket fd
    void* priv;              // 后端私有数据(posix 后端放互斥量/条件变量等)
    int lua_ref_id;
    int code;
    struct http_parser parser;

    char *uri;
    char *headers;
    char *body;

    http_req_header_t* req_headers;

    size_t body_size;
    size_t expect_body_size;
    int next_header_value_is_content_length;
    uint32_t recv_done;
    char *buff;
    size_t buff_offset;
    size_t buff_size;
    size_t send_size;
    size_t sent_size;

    FILE* fd;
    char sbuff[1500];
    uint32_t sbuff_offset;
    uint8_t write_done;
    uint8_t discard;           // Lua 回调已失效, 后端收到响应信号时直接回收而不是发送
}client_socket_ctx_t;

luat_httpsrv_ctx_t* luat_httpsrv_malloc(int port, int adapter_index, const luat_httpsrv_transport_t* vt);
int luat_httpsrv_free(luat_httpsrv_ctx_t* ctx);

//================================
// luat_httpsrv_http.c 提供的传输无关能力, 两个后端共用

/* http_parser 生命周期 */
void luat_httpsrv_parser_init(client_socket_ctx_t* client);
size_t luat_httpsrv_parser_exec(client_socket_ctx_t* client, const char* data, size_t len);

/* 资源回收 */
void luat_httpsrv_free_common(client_socket_ctx_t* client);
void luat_httpsrv_client_cleanup(client_socket_ctx_t* client);

/* 发送 */
void luat_httpsrv_send_response(client_socket_ctx_t* client);
void luat_httpsrv_send_static_head(client_socket_ctx_t* client, const char* path, size_t len);

/* 静态文件路由; 返回 1 表示命中并填充 path_out/out_len */
int luat_httpsrv_resolve_static(client_socket_ctx_t* client, char* path_out, size_t path_size, size_t* out_len);

/* 请求解析完成后的统一出口. 返回 1 = 静态文件路径已处理, 0 = 已派发到 Lua 线程 */
int luat_httpsrv_dispatch_request(client_socket_ctx_t* client);

#endif // LUAT_HTTPSRV_H
