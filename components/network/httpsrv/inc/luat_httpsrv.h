#include "luat_base.h"


typedef struct luat_httpsrv_ctx
{
    uint16_t port;
    uint16_t https;
    char static_path[32];
    int lua_ref_id;
    int server_fd;
    void* userdata;
}luat_httpsrv_ctx_t;


typedef struct http_code_str
{
    int code;
    const char* msg;
}http_code_str_t;

static const http_code_str_t http_codes[] = {
    {200, "OK"},
    {302, "Found"},
    {400, "Bad Request"},
    {401, "Unauthorized"},
    {403, "Forbidden"},
    {404, "Not Found"},
    {500, "Internal Server Error"},
    {0, ""}
};

int luat_httpsrv_stop(int port);
int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx);
