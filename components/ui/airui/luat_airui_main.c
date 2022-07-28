#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

static jsmn_parser parser;

int luat_airui_load_buff(luat_airui_ctx_t** _ctx, int backend, const char* screen_name, const char* buff, size_t len) {
    int ret;
    luat_airui_ctx_t *ctx = luat_heap_malloc(sizeof(luat_airui_ctx_t));
    if (ctx == NULL) {
        LLOGW("out of memory when malloc luat_airui_ctx_t");
        return -1;
    }
    
    // 首先, 初始化处理器
    jsmn_init(&parser);
    // 然后,先扫描一遍, 获取总的token数量, 若处理失败,会返回负数
    ret = jsmn_parse(&parser, buff, len, NULL, 0);
    if (ret <= 0) {
        LLOGW("invaild json ret %d", ret);
        return -2;
    }
    LLOGD("found json token count %d", ret);
    // 再然后, 分配内存
    jsmntok_t *tok = luat_heap_malloc(sizeof(jsmntok_t) * ret);
    if (tok == NULL) {
        luat_heap_free(ctx);
        LLOGW("out of memory when malloc jsmntok_t");
        return -3;
    }
    // 真正的解析, 肯定不会出错
    jsmn_init(&parser);
    ret = jsmn_parse(&parser, buff, len, tok, ret);
    if (ret <= 0) {
        // 还是防御一下吧
        luat_heap_free(tok);
        luat_heap_free(ctx);
        LLOGW("invaild json ret %d", ret);
        return -2;
    }

    // 现在解析完成了, 开始生成的组件树
    LLOGD("json parse complete, begin components jobs ...");
    ctx->data = buff;
    ctx->screen_name = screen_name;
    ret = luat_airui_load_components(ctx, tok, ret);
    LLOGD("json parse complete, end components jobs, ret %d", ret);
    luat_heap_free(tok);
    if (ret == 0) {
        *_ctx = ctx;
    }
    else {
        luat_heap_free(ctx);
    }
    return ret;
}

int luat_airui_load_file(luat_airui_ctx_t** ctx, int backend, const char* screen_name, const char* path) {
    return -1;
}

int luat_airui_get(luat_airui_ctx_t* ctx, const char* key) {
    return -1;
}

