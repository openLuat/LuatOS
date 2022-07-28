#include "luat_base.h"
#include "luat_airui.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"
#include "luat_malloc.h"

int airui_block_lvgl_img_cb(airui_block_t *bl) {
    lv_obj_t *parent = (lv_obj_t*)bl->parent;    
    //LLOGD("create img parent %p", parent);
    lv_obj_t *obj = lv_img_create(parent, NULL);
    bl->self = obj;

    // 取src
    int comConf_pos = jsmn_find_by_key(bl->ctx->data, "comConf", bl->tok, bl->schema_pos + 1);
    if (comConf_pos < 1) {
        LLOGD("schema without comConf");
        return 0;
    }
    int src_pos = jsmn_find_by_key(bl->ctx->data, "src", bl->tok, comConf_pos + 1);
    if (src_pos < 1) {
        LLOGD("img without src");
        return 0;
    }
    c_str_t src = {.len = 0};
    jsmn_get_string(bl->ctx->data, bl->tok, src_pos + 1, &src);

    char* buff = luat_heap_malloc(src.len + 1);
    // TODO 校验buff是否为null
    memcpy(buff, src.ptr, src.len);
    buff[src.len] = 0;
    LLOGD("img src %s", buff);
    lv_img_set_src(obj, buff);
    luat_heap_free(buff);

    return 0;
}

