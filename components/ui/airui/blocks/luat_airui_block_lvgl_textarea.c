#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

int airui_block_lvgl_textarea_cb(airui_block_t *bl) {
    lv_obj_t *parent = (lv_obj_t*)bl->parent;
    lv_obj_t *obj = lv_textarea_create(bl->parent, NULL);
    bl->self = obj;

    //---------------------------------------
    // 取comConf
    int comConf_pos = jsmn_find_by_key(bl->ctx->data, "comConf", bl->tok, bl->schema_pos + 1);
    if (comConf_pos < 1) {
        LLOGD("schema without comConf");
        return 0;
    }

    // -----------------------------------
    // 设置text 属性
    int text_pos = jsmn_find_by_key(bl->ctx->data, "text", bl->tok, comConf_pos + 1);
    if (text_pos < 1) {
        LLOGD("label without text");
        return 0;
    }

    c_str_t text = {.len = 0};
    jsmn_get_string(bl->ctx->data, bl->tok, text_pos + 1, &text);

    char* buff = luat_heap_malloc(text.len + 1);
    // TODO 检查buff是否为NULL
    memcpy(buff, text.ptr, text.len);
    buff[text.len] = 0;
    lv_textarea_set_text(obj, buff);
    luat_heap_free(buff);

    return 0;
}

