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

// https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
static const http_code_str_t http_codes[] = {
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


typedef struct ct_reg
{
    const char* suff;
    const char* value;
}ct_reg_t;

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
    {"wav",     "audio/wave"},
    {"webm",    "video/webm"},
    {"mp4",     "video/mpeg4"},
    {"bin",     "application/octet-stream"},
};


int luat_httpsrv_stop(int port);
int luat_httpsrv_start(luat_httpsrv_ctx_t* ctx);
