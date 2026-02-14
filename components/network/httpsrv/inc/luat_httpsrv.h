#ifndef LUAT_HTTPSRV_H
#define LUAT_HTTPSRV_H

#include "luat_base.h"
#include "http_parser.h"


typedef struct luat_httpsrv_ctx
{
    uint16_t port;
    uint16_t https;
    char static_path[32];
    int lua_ref_id;
    int server_fd;
    void* userdata;
    uint8_t adapter_id;
    struct netif* netif;
    struct tcp_pcb* pcb;
    uint8_t allpath;
}luat_httpsrv_ctx_t;


typedef struct http_code_str
{
    int code;
    const char* msg;
}http_code_str_t;

// 声明http_codes数组，定义在.c文件中
extern const http_code_str_t g_luat_http_codes[];


typedef struct ct_reg
{
    const char* suff;
    const char* value;
}ct_reg_t;

struct http_req_header;

typedef struct http_req_header
{
    struct http_req_header* next;
    uint16_t key_len;
    uint16_t value_len;
    char data[32];
}http_req_header_t;

typedef struct client_socket_ctx
{
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
    struct tcp_pcb* pcb;
    size_t send_size;
    size_t sent_size;

    FILE* fd;
    char sbuff[1500];
    uint32_t sbuff_offset;
    uint8_t write_done;
}client_socket_ctx_t;

luat_httpsrv_ctx_t* luat_httpsrv_malloc(int port, int adapter_index);
int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx);
int luat_httpsrv_free(luat_httpsrv_ctx_t* ctx);
int luat_httpsrv_stop(luat_httpsrv_ctx_t* ctx);

#endif // LUAT_HTTPSRV_H
