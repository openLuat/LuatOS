#ifndef LUAT_MOCK_H
#define LUAT_MOCK_H

int luat_mock_init(const char* path);

#define MOCK_DISABLED (-0xFF)

typedef struct luat_mock_ctx
{
    char key[128];
    char* req_data;
    size_t req_len;
    char* resp_data;
    size_t resp_len;
    int resp_type;
    int resp_code;
}luat_mock_ctx_t;

int luat_mock_call(luat_mock_ctx_t* ctx);

#endif