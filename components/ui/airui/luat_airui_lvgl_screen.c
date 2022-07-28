#include "luat_base.h"
// #include "luat_lvgl.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#include "math.h"
#include <stdlib.h>

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

int top_screen_layout(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);
int top_screen_layout_blocks(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos);
int top_screen_layout_block(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos, lv_obj_t *scr);

int top_screens_one(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    LLOGD("parse screen");
    if (tok[pos].type != JSMN_OBJECT) {
        LLOGD("screen must be object");
        return -1;
    }
    int name_pos = jsmn_find_by_key(ctx->data, "name", tok, pos);
    if (name_pos < 1) {
        LLOGD("screen without name, skip");
        return 0;
    }
    c_str_t name = {.len = 0};
    jsmn_get_string(ctx->data, tok, name_pos + 1, &name);
    if (name.len < 1) {
        LLOGD("screen name is emtry, skip");
        return 0;
    }

    if (ctx->screen_name != NULL) {
        if (name.len != strlen(ctx->screen_name)) {
            LLOGD("skip screen, name not match");
            return 0;
        }
        if (memcmp(ctx->screen_name, name.ptr, name.len)) {
            LLOGD("skip screen, name not match");
            return 0;
        }
    }

    //LLOGD("load screen name %.*s", name.len, name);

    int layout_pos = jsmn_find_by_key(ctx->data, "layout", tok, pos);
    if (layout_pos < 1) {
        LLOGD("screen without layout, skip");
        return 0;
    }


    top_screen_layout(ctx, tok, layout_pos);

    return 0;
}

int top_screen_layout(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    LLOGD("screen layout");

    pos ++; // 跳到值
    if (tok[pos].type != JSMN_OBJECT) {
        LLOGD("layout must be map, skip");
        return 0;
    }

    int blocks_pos = jsmn_find_by_key(ctx->data, "blocks", tok, pos);
    if (blocks_pos < 1) {
        LLOGD("layout without blocks, skip");
        return 0;
    }
    
    top_screen_layout_blocks(ctx, tok, blocks_pos);

    return 0;
}

int top_screen_layout_blocks(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos) {
    LLOGD("screen.layer.blocks");
    
    // 移动到值
    pos ++;
    
    if (tok[pos].type != JSMN_ARRAY) {
        LLOGD("layout.blocks must be array, skip");
        return 0;
    }

    if (tok[pos].size < 1) {
        LLOGD("layout.blocks is emtry, skip");
        return 0;
    }
    int block_count = tok[pos].size;
    LLOGD("layout.blocks count %d", block_count);

    // 移动到blocks[0]
    pos ++;

    lv_obj_t *scr = lv_obj_create(NULL, NULL);

    for (size_t i = 0; i < block_count; i++)
    {
        top_screen_layout_block(ctx, tok, pos, scr);
        jsmn_skip_object(tok, &pos);
    }
    
    ctx->scr = scr;

    return 0;
}

