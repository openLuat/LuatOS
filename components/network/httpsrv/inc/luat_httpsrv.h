#ifndef LUAT_HTTPSRV_H
#define LUAT_HTTPSRV_H

#include "luat_base.h"


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

luat_httpsrv_ctx_t* luat_httpsrv_malloc(int port, int adapter_index);
int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx);
int luat_httpsrv_free(luat_httpsrv_ctx_t* ctx);
int luat_httpsrv_stop(luat_httpsrv_ctx_t* ctx);

#endif // LUAT_HTTPSRV_H
