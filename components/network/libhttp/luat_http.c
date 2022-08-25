#include "luat_base.h"
#include "luat_http.h"
#include "luat_malloc.h"
#include "string.h"

#define LUAT_LOG_TAG "http"
#include "luat_log.h"

int luat_http_init(luat_http_ctx_t *ctx) {
    if (ctx == NULL)
        return -1;
    memset(ctx, 0, sizeof(ctx));
    return 0;
}

int luat_http_set_url(luat_http_ctx_t *ctx, char* url, int method) {
    if (ctx == NULL || url == NULL)
        return -1;
    ctx->method = method;
    // 首先, 截取 http/https头部
    char *tmp = url;
    if (!strncmp("https://", url, strlen("https://"))) {
        ctx->ssl = 1;
        tmp += strlen("https://");
    }
    else if (!strncmp("http://", url, strlen("http://"))) {
        ctx->ssl = 0;
        tmp += strlen("http://");
    }
    else {
        LLOGI("only http/https supported %s", url);
        return -2;
    }
    // 然后, 分解URL成 host:port 和 uri 两部分
    int tmplen = strlen(tmp);
    if (tmplen < 5) {
        LLOGI("url too short %s", url);
        return -3;
    }
    char tmphost[256] = {0};
    char *tmpuri = NULL;
    for (size_t i = 1; i < tmplen; i++)
    {
        if (tmp[i] == '/') {
            if (i > 255) {
                LLOGI("host too long %s", url);
                return -4;
            } 
            memcpy(tmphost, tmp, i);
            tmpuri = tmp + i;
            break;
        }
    }
    if (strlen(tmphost) < 1) {
        LLOGI("host not found %s", url);
        return -5;
    }
    // 如果uri是\0, 那就指向 "/"
    if (strlen(tmpuri) == 0) {
        tmpuri = "/";
    }

    // 分解host:port
    for (size_t i = 1; i < strlen(tmphost); i++)
    {
        if (tmp[i] == ":") {
            tmp[i] = 0x00;
            ctx->port = atoi(&tmp[i+1]);
            break;
        }
    }
    // 对port进行修正
    if (ctx->port <= 0) {
        if (ctx->ssl)
            ctx->port = 443;
        else
            ctx->port = 80;
    }
    
    ctx->host = luat_heap_malloc(strlen(tmphost + 1));
    if (ctx->host == NULL) {
        LLOGE("out of memory when malloc host");
        goto exit;
    }
    memcpy(ctx->host, tmphost, strlen(tmphost + 1));

    ctx->uri = luat_heap_malloc(strlen(tmpuri + 1));
    if (ctx->uri == NULL) {
        LLOGE("out of memory when malloc url");
        goto exit;
    }
    memcpy(ctx->uri, tmpuri, strlen(tmpuri + 1));

    return 0;

exit:
    return -0xAF;
}

int luat_http_set_ca(luat_http_ctx_t *ctx, char* server_ca, char* client_ca) {
    LLOGE("luat_http_set_ca NOT support yet");
    return -1;
}

typedef  struct {
    char* old_str;
    char* str;
}URL_PARAMETES;

int luat_http_add_header(luat_http_ctx_t *ctx, char* name, char* value) {
    if (ctx->req_headers_size >= LUAT_HTTP_MAX_REQ_HEADER_COUNT) {
        LLOGE("too many custom header");
        return -1;
    }
    if (strlen(name) > 256 || strlen(value) > 256) {
        LLOGE("header key/value MUST less than 256 byte");
        return -2;
    }

    // URL encode
    char temp[256 * 3]     = {0};
    URL_PARAMETES url_patametes[] = {
        {"+","%2B"},
        {" ","%20"},
        {"/","%2F"},
        {"?","%3F"},
        {"%","%25"},
        {"#","%23"},
        {"&","%26"},
        {"=","%3D"},
    };
    size_t slen = strlen(value);
    int i = 0, j = 0, k = 0;
    for (i = 0,j = 0; i < slen; i++) {
        for(k = 0; k < 8; k++){
            if(value[i] == url_patametes[k].old_str[0]) {
                memcpy(&temp[j],url_patametes[k].str,strlen(url_patametes[k].str));
                j+=3;
                break;
            }
        }
        if (k == 8) {
            temp[j++] = value[i];
        }
	}
    char *header = luat_heap_malloc(strlen(name) + strlen(temp) + 3);
    if (header == NULL) {
        LLOGW("out of memory when malloc header");
        return -3;
    }
    sprintf("%s: %s", header, name, temp);
    ctx->req_headers[ctx->req_headers_size] = header;
    ctx->req_headers_size ++;
    return 0;
}

// int luat_http_set_header(luat_http_ctx_t *ctx, char* name, char* value);
int luat_http_set_body(luat_http_ctx_t *ctx, uint8_t body_type, char* body, int body_size) {
    if (ctx->req_body != NULL) {
        luat_heap_free(ctx->req_body);
    }
    ctx->req_body = luat_heap_malloc(body_size + 1);
    if (ctx->req_body == NULL) {
        LLOGW("out of memory when malloc header");
        return -1;
    }
    ctx->req_body_size = body_size;
    ctx->req_body_type = body_type;
    memcpy(ctx->req_body, body, body_size);
    ctx->req_body[ctx->req_body_size] = 0x00;
    return 0;
}

int luat_http_uninit(luat_http_ctx_t *ctx) {
    if (ctx == NULL)
        return 0;
    if (ctx->host) {
        luat_heap_free(ctx->host);
        ctx->host = NULL;
    }
    if (ctx->uri) {
        luat_heap_free(ctx->uri);
        ctx->uri = NULL;
    }
    if (ctx->server_ca) {
        luat_heap_free(ctx->server_ca);
        ctx->server_ca = NULL;
    }
    if (ctx->client_ca) {
        luat_heap_free(ctx->client_ca);
        ctx->client_ca = NULL;
    }
    if (ctx->req_body) {
        luat_heap_free(ctx->req_body);
        ctx->req_body = NULL;
        // ctx->req_body_size = 0;
        // ctx->req_body_type = 0;
    }
    if (ctx->req_headers_size) {
        for (size_t i = 0; i < ctx->req_headers_size; i++)
        {
            if (ctx->req_headers[i]) {
                luat_heap_free(ctx->req_headers[i]);
                ctx->req_headers[i] = NULL;
            }
        }
        ctx->req_headers_size = 0;
    }
    return 0;
}

int luat_http_send(luat_http_ctx_t *ctx, http_cb cb);
