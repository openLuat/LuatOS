#include "luat_base.h"
// #include "luat_lvgl.h"
#include "luat_airui.h"
#include "math.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

static int top_device_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);
static int top_schema_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);
static int top_screens_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);

airui_parser_t airui_top_parsers[] = {
    // 注意顺序, 先处理schema, 再处理screens, 因为后者依赖前者.
    {.name = "device", .cb = top_device_parser},
    {.name = "screens", .cb = top_screens_parser},
    {.name = "schema", .cb = top_schema_parser},
    {.name = "", .cb = NULL}
};

// 处理设备信息, 实际上没啥用, 仅调试日志
static int top_device_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    // LLOGD("parse device");
    // int width_pos = jsmn_find_by_key(ctx->data, "width", tok, pos + 1);
    // int height_pos = jsmn_find_by_key(ctx->data, "height", tok, pos + 1);

    // if (width_pos > 0 && height_pos > 0) {
    //     LLOGD("device width %d height %d", 
    //                 jsmn_toint(ctx->data, &tok[width_pos + 1]),
    //                 jsmn_toint(ctx->data, &tok[height_pos + 1])
    //                 );
    // }
    // else {
    //     LLOGD("device width height not found");
    // }

    return 0;
}


int top_screens_one(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);
// 重头戏, 解析screens
static int top_screens_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    LLOGD("parse screens");

    pos ++;

    jsmntok_t* screens = &tok[pos];
    if (screens->type != JSMN_ARRAY) {
        LLOGW("screens must be array");
        return -1;
    }
    
    if (screens->size == 0) {
        LLOGW("screens is emtry");
        return 0;
    }
    else {
        LLOGD("screens count %d", screens->size);
    }

    size_t scount = screens->size;

    pos ++; // 移动到一个元素

    for (size_t i = 0; i < scount; i++)
    {
        top_screens_one(ctx, tok, pos);
        jsmn_skip_object(tok, &pos);
    }
    

    return 0;
}

// 解析schema
static int top_schema_parser(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    //LLOGD("parse schema");
    return 0;
}
