#ifndef LUAT_AIRUI_XML_H
#define LUAT_AIRUI_XML_H

#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/core/lv_obj_tree.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lvgl9/src/font/lv_font.h"
#include "lvgl9/src/others/xml/lv_xml.h"

#ifdef __cplusplus
extern "C" {
#endif

/// 初始化 XML 功能模块（依赖 LVGL XML 功能）
bool airui_xml_init(void);
/// 反初始化 XML 模块，释放内部资源
bool airui_xml_deinit(void);
/// 从文件注册屏幕/组件定义
bool airui_xml_register_from_file(const char *path);
/// 通过字符串注册 XML 内容
bool airui_xml_register_from_data(const char *name, const char *xml_def);
/// 创建已经注册的 screen 并返回对应 lv_obj_t
lv_obj_t *airui_xml_create_screen(const char *name);
/// 按照名称查找当前屏幕中的对象（依赖 LV_USE_OBJ_NAME）
lv_obj_t *airui_xml_find_object(const char *name);
/// 注册 XML 中使用的图片资源（支持路径或 lv_img_dsc userdata）
bool airui_xml_register_image(const char *name, const void *src);
/// 注册供 XML 使用的字体（名字需与 XML 中 font 属性一致）
bool airui_xml_register_font(const char *name, const lv_font_t *font);
/// 给指定对象添加事件回调，包含 delete 事件自动清理
bool airui_xml_add_event_cb(lv_obj_t *obj, lv_event_code_t code, lv_event_cb_t cb, void *user_data, lv_event_cb_t release_cb);
/// 为 textarea 注册键盘 focus/defocus/release 事件
bool airui_xml_bind_keyboard_events(lv_obj_t *textarea, lv_event_cb_t focus_cb, lv_event_cb_t defocus_cb, lv_event_cb_t release_cb, void *user_data);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_AIRUI_XML_H */

