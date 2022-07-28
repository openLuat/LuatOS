#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"


extern airui_parser_t airui_top_parsers[];

int luat_airui_load_components(luat_airui_ctx_t* ctx, void *args, size_t tok_count) {
    jsmntok_t *tok = (jsmntok_t *)args;

    if (tok->type != JSMN_OBJECT) {
        LLOGE("json must be a map!!");
        return -4;
    }

    jsmntok_t *top = tok;
    size_t cur = 0;

    // 遍历数据,测试用
#if 0
    for (size_t i = 0; i < tok_count; i++)
    {
        LLOGD("tok\t%d\t%d\t%d\t%d\t%d", i, tok[i].type, tok[i].start, tok[i].end, tok[i].size);
    }
#endif


    LLOGD("top size %d", top->size);
    if (top->size < 3) {
        LLOGE("not a good ui data. top size < 3");
        return -5;
    }

    airui_parser_t* parser = airui_top_parsers;
    while (parser->cb != NULL)
    {
        int pos = jsmn_find_by_key(ctx->data, parser->name, tok, cur);
        if (pos > 0) {
            parser->cb(ctx, tok, pos);
        }
        else {
            LLOGD("parser key not found %s", parser->name);
        }
        parser ++;
    }

    return 0;
}
