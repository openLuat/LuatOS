#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

typedef struct block_reg
{
    const char* comName;
    airui_block_cb cb;
}block_reg_t;

int airui_block_lvgl_bar_cb(airui_block_t *bl);
int airui_block_lvgl_button_cb(airui_block_t *bl);
int airui_block_lvgl_img_cb(airui_block_t *bl);
int airui_block_lvgl_label_cb(airui_block_t *bl);
int airui_block_lvgl_qrcode_cb(airui_block_t *bl);
int airui_block_lvgl_slider_cb(airui_block_t *bl);
int airui_block_lvgl_textarea_cb(airui_block_t *bl);

static block_reg_t block_regs[] = {
    {.comName="LvglButton", .cb=airui_block_lvgl_button_cb},
    {.comName="LvglImg", .cb=airui_block_lvgl_img_cb},
    {.comName="LvglLabel", .cb=airui_block_lvgl_label_cb},
    {.comName="LvglSlider", .cb=airui_block_lvgl_slider_cb},
    {.comName="LvglBar", .cb=airui_block_lvgl_bar_cb},
    {.comName="LvglQrcode", .cb=airui_block_lvgl_qrcode_cb},
    {.comName="LvglLvglTextarea", .cb=airui_block_lvgl_textarea_cb},
    {.comName = "", .cb = NULL}
};


int top_screen_layout_block(luat_airui_ctx_t* ctx, jsmntok_t *tok, int pos, lv_obj_t *scr) {
    if (tok[pos].type != JSMN_OBJECT) {
        LLOGD("layout.blocks item must be obj, skip");
        return 0;
    }
    if (tok[pos].size == 0) {
        LLOGD("layout.blocks item is emtry, skip");
        return 0;
    }
    
    int name_pos = jsmn_find_by_key(ctx->data, "name", tok, pos);
    int body_pos = jsmn_find_by_key(ctx->data, "body", tok, pos);
    int x_pos = jsmn_find_by_key(ctx->data, "x", tok, pos);
    int y_pos = jsmn_find_by_key(ctx->data, "y", tok, pos);
    int width_pos = jsmn_find_by_key(ctx->data, "width", tok, pos);
    int height_pos = jsmn_find_by_key(ctx->data, "height", tok, pos);

    if (name_pos < 1) {
        LLOGD("layout.blocks item miss name, skip");
        return 0;
    }
    if (body_pos < 1) {
        LLOGD("layout.blocks item miss body, skip");
        return 0;
    }
    if (x_pos < 1) {
        LLOGD("layout.blocks item miss x, skip");
        return 0;
    }
    if (y_pos < 1) {
        LLOGD("layout.blocks item miss y, skip");
        return 0;
    }
    if (width_pos < 1) {
        LLOGD("layout.blocks item miss width, skip");
        return 0;
    }
    if (height_pos < 1) {
        LLOGD("layout.blocks item miss height, skip");
        return 0;
    }

    air_block_info_t info = {0};

    info.x = jsmn_toint(ctx->data, &tok[x_pos+1]);
    info.y = jsmn_toint(ctx->data, &tok[y_pos+1]);
    info.width = jsmn_toint(ctx->data, &tok[width_pos+1]);
    info.height = jsmn_toint(ctx->data, &tok[height_pos+1]);
    jsmn_get_string(ctx->data, tok, name_pos+1, &info.name);
    jsmn_get_string(ctx->data, tok, body_pos+1, &info.body);

    LLOGD("x %d y %d width %d height %d", info.x, info.y, info.width, info.height);

    char tmp[128];
    mempcpy(tmp, info.body.ptr, info.body.len);
    tmp[info.body.len] = 0;

    // 查找schema 从而确定 block 的内容, 并创建之

    int schema_top_pos = jsmn_find_by_key(ctx->data, "schema", tok, 0);
    if (schema_top_pos < 1) {
        LLOGW("data without schema, skip!");
        return 0;
    }
    int my_schema_pos = jsmn_find_by_key(ctx->data, tmp, tok, schema_top_pos + 1);
    if (my_schema_pos < 1) {
        LLOGW("data without my schema [%s], skip!", tmp);
        return 0;
    }
    else {
        LLOGD("found my schema [%s]", tmp);
    }

    int comType_pos = jsmn_find_by_key(ctx->data, "comType", tok, my_schema_pos + 1);
    if (comType_pos < 1) {
        LLOGW("schema without comType, skip!");
        return 0;
    }
    c_str_t comType = {.len = 0};
    jsmn_get_string(ctx->data, tok, comType_pos+1, &comType);

    block_reg_t* reg = block_regs;
    airui_block_t bl = {
        .ctx = ctx,
        .info = &info,
        .parent = scr,
        .schema_pos = my_schema_pos,
        .tok = tok,
        .self = NULL
    };
    while (reg->cb != NULL) {
        if (strlen(reg->comName) == comType.len) {
            if (!memcmp(reg->comName, comType.ptr, comType.len)) {
                reg->cb(&bl);
                if (bl.self != NULL) {
                    LLOGD("comType %s %p %p", reg->comName, bl.parent, bl.self);
                    lv_obj_set_pos((lv_obj_t*)bl.self, info.x, info.y);
                    lv_obj_set_size((lv_obj_t*)bl.self, info.width, info.height);
                }
                else {
                    LLOGD("self is NULL");
                }
                return 0;
            }
        }
        reg++;
    }

    memcpy(tmp, comType.ptr, comType.len);
    tmp[comType.len] = 0;
    LLOGW("unsupoort comType [%s]", tmp);

    return 0;
}
