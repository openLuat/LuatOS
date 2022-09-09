
#ifndef LUAT_HTTP_H
#define LUAT_HTTP_H
#include "luat_base.h"

#define LUAT_HTTP_GET 0
#define LUAT_HTTP_POST 1
#define LUAT_HTTP_PUT 2
#define LUAT_HTTP_DELETE 3
#define LUAT_HTTP_HEAD 4


typedef struct luat_lib_http_body
{
    uint8_t type;
    size_t size;
    void *ptr;
    void *next;
}luat_lib_http_body_t;

typedef struct luat_lib_http_headers
{
    char** ptr;
    size_t size;
}luat_lib_http_headers_t;

typedef struct luat_lib_http_resp
{
    int code;
    luat_lib_http_headers_t headers;
    luat_lib_http_body_t body;
    int luacb;
}luat_lib_http_resp_t;

typedef int (* luat_http_cb) (luat_lib_http_resp_t *resp);

typedef struct luat_lib_http_req
{
    uint8_t method;
    uint8_t timeout_s;
    char* url;
    size_t url_len;
    char* ca;
    size_t ca_len;
    luat_lib_http_headers_t headers;
    luat_lib_http_body_t body;
    int luacb;
    luat_http_cb httpcb;
    char dwpath[32];
}luat_lib_http_req_t;

int luat_http_req(luat_lib_http_req_t *req);

void luat_http_req_gc(luat_lib_http_req_t *req);
void luat_http_resp_gc(luat_lib_http_resp_t *req);

#endif
