#include "luat_base.h"

// #define LUAT_HTTP_METHOD_GET 1
// #define LUAT_HTTP_METHOD_POST 2
// #define LUAT_HTTP_METHOD_PUT 3
// #define LUAT_HTTP_METHOD_DELETE 4

#define LUAT_HTTP_MAX_REQ_HEADER_COUNT (8)
#define LUAT_HTTP_MAX_RESP_HEADER_COUNT (16)

enum LUAT_HTTP_METHOD {
    GET,
    POST,
    PUT,
    DELETE
};

// typedef struct luat_http_header
// {
//     uint16_t name_len;
//     uint16_t value_len;
//     char buff[4];
// }luat_http_header_t;


typedef struct luat_http_ctx {
    char* host;
    uint16_t port;
    int method;
    uint8_t ssl;
    char*   uri;
    char*   server_ca;
    char*   client_ca;
    char*   req_body;
    int     req_body_size;
    uint8_t req_body_type; // 0 - None, 1 - Binary , 3 - RAW_FILE, 4 - MULITE-FILE
    void*   userdata;
    size_t req_headers_size;
    char* req_headers[LUAT_HTTP_MAX_REQ_HEADER_COUNT];
    void* network;

    // 响应类
    int status_code;
    int     total_body_size;
    char*   resp_body;
    char*   resp_body_size;
    uint8_t resp_body_end;
    size_t  resp_headers_size;
    char* resp_headers[LUAT_HTTP_MAX_RESP_HEADER_COUNT];
} luat_http_ctx_t;

typedef void (*http_cb)(luat_http_ctx_t *ctx);

int luat_http_init(luat_http_ctx_t *ctx);
int luat_http_set_url(luat_http_ctx_t *ctx, char* url, int method);
int luat_http_set_ca(luat_http_ctx_t *ctx, char* server_ca, char* client_ca);
int luat_http_add_header(luat_http_ctx_t *ctx, char* name, char* value);
int luat_http_set_header(luat_http_ctx_t *ctx, char* name, char* value);
int luat_http_set_body(luat_http_ctx_t *ctx, uint8_t body_type, char* body, int bodylen);

int luat_http_send(luat_http_ctx_t *ctx, http_cb cb);

int luat_http_uninit(luat_http_ctx_t *ctx);
