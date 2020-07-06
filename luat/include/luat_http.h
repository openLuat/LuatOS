
#include "luat_base.h"

#define LUAT_HTTP_GET 1
#define LUAT_HTTP_POST 2
#define LUAT_HTTP_PUT 3
#define LUAT_HTTP_DELETE 4

typedef struct luat_lib_http_body
{
    uint8_t type;
    size_t size;
    void *ptr;
    void *next;
}luat_lib_http_body_t;

typedef struct luat_lib_http_header
{
    char* str;
    void *next;
}luat_lib_http_header_t;

typedef struct luat_lib_http_req
{
    uint8_t method;
    char* url;
    size_t url_len;
    char* ca;
    size_t ca_len;
    luat_lib_http_header_t headers;
    luat_lib_http_body_t body;
    int cb;
}luat_lib_http_req_t;

typedef struct luat_lib_http_resp
{
    int code;
    luat_lib_http_header_t headers;
    luat_lib_http_body_t body;
}luat_lib_http_resp_t;

int luat_http_req(luat_lib_http_req_t *req);
