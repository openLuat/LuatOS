#include "luat_base.h"
#include "luat_airui.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airui"
#include "luat_log.h"

lv_obj_t * lv_qrcode_create(lv_obj_t * parent, lv_coord_t size, lv_color_t dark_color, lv_color_t light_color);
lv_res_t lv_qrcode_update(lv_obj_t * qrcode, const void * data, uint32_t data_len);

int airui_block_lvgl_qrcode_cb(airui_block_t *bl) {
    lv_obj_t * obj = lv_qrcode_create(bl->parent, 200, lv_color_hex(0xFFFFFF), lv_color_hex(0x000000));
    bl->self = obj;

    // 首先, 读取comConf
    int comConf_pos = jsmn_find_by_key(bl->ctx->data, "comConf", bl->tok, bl->schema_pos + 1);
    if (comConf_pos < 1) {
        LLOGD("schema without comConf");
        return 0;
    }

    // qrcode当前就一个属性, txt, 如果没有就结束
    int text_pos = jsmn_find_by_key(bl->ctx->data, "text", bl->tok, comConf_pos + 1);
    if (text_pos < 1) {
        LLOGD("qrcode without text");
    }
    else {
        // 读取 txt, 设置为默认值
        c_str_t text = {.len = 0};
        jsmn_get_string(bl->ctx->data, bl->tok, text_pos + 1, &text);

        if (text.len > 1) {
            lv_qrcode_update(obj, text.ptr, text.len);
        }
    }
    return 0;
}

