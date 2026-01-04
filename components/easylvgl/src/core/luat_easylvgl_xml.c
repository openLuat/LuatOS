/**
 * @file luat_easylvgl_xml.c
 * @summary EasyLVGL XML helper implementations
 */

#include "luat_easylvgl_conf.h"
#include "luat_easylvgl.h"
#include "luat_easylvgl_xml.h"

#define LUAT_LOG_TAG "easylvgl.xml"
#include "luat_log.h"

#if LV_USE_XML

#include "lvgl9/lvgl.h"
#include "lvgl9/src/core/lv_obj_tree.h"
#include "lvgl9/src/others/xml/lv_xml.h"

/**
 * 初始化 LVGL XML 子系统，供后续 XML 解析与创建使用。
 */
bool easylvgl_xml_init(void)
{
    lv_xml_init();
    return true;
}

/**
 * 反初始化 XML 子系统，释放临时占用的资源。
 */
bool easylvgl_xml_deinit(void)
{
    lv_xml_deinit();
    return true;
}

/**
 * 通过文件路径注册一个 XML 组件定义。
 *
 * @param path XML 文件在文件系统中的路径
 * @return LVGL 是否成功注册
 */
bool easylvgl_xml_register_from_file(const char *path)
{
    if (path == NULL) {
        LLOGW("xml_register_from_file: invalid path");
        return false;
    }
    lv_result_t res = lv_xml_register_component_from_file(path);
    return res == LV_RESULT_OK;
}

/**
 * 直接通过字符串注册 XML 组件定义。
 *
 * @param name 组件名称（例如 "screen/main"）
 * @param xml_def XML 文本内容
 * @return 是否成功注册
 */
bool easylvgl_xml_register_from_data(const char *name, const char *xml_def)
{
    if (name == NULL || xml_def == NULL) {
        LLOGW("xml_register_from_data: invalid args");
        return false;
    }
    lv_result_t res = lv_xml_register_component_from_data(name, xml_def);
    return res == LV_RESULT_OK;
}

/**
 * 注册 XML 所需的图片资源，可配合 globals.xml 中的 image name 使用。
 */
bool easylvgl_xml_register_image(const char *name, const void *src)
{
    if (name == NULL || src == NULL) {
        LLOGW("xml_register_image: invalid args");
        return false;
    }
    lv_result_t res = lv_xml_register_image(NULL, name, src);
    return res == LV_RESULT_OK;
}

/**
 * 注册给 XML 使用的 lv_font_t，以便在样式或控件中通过 font 名称引用。
 */
bool easylvgl_xml_register_font(const char *name, const lv_font_t *font)
{
    if (name == NULL || font == NULL) {
        LLOGW("xml_register_font: invalid args");
        return false;
    }
    lv_result_t res = lv_xml_register_font(NULL, name, font);
    return res == LV_RESULT_OK;
}

/**
 * 根据注册的 XML 名称创建并加载一个屏幕。
 *
 * @param name 之前注册的屏幕/组件名
 * @return 创建的屏幕对象，失败返回 NULL
 */
lv_obj_t *easylvgl_xml_create_screen(const char *name)
{
    if (name == NULL) {
        LLOGW("xml_create_screen: name is NULL");
        return NULL;
    }
    lv_obj_t *screen = lv_xml_create_screen(name);
    if (screen == NULL) {
        return NULL;
    }
    // 直接加载屏幕保持 LVGL 运行状态一致
    lv_screen_load(screen);
    return screen;
}

/**
 * 根据名称查找对象。
 * @param name 对象名称
 * @return 找到的对象，失败返回 NULL
 */
lv_obj_t *easylvgl_xml_find_object(const char *name)
{
#if LV_USE_OBJ_NAME
    if (name == NULL) {
        return NULL;
    }
    return lv_obj_find_by_name(NULL, name);
#else
    (void)name;
    return NULL;
#endif
}
/**
 * 给对象添加 LVGL 事件回调，并在 delete 事件中执行 release。
 * @param obj 目标对象
 * @param code 事件码
 * @param cb 回调函数
 * @param user_data 用户数据
 * @param release_cb 释放回调函数
 * @return 是否成功添加
 */
bool easylvgl_xml_add_event_cb(lv_obj_t *obj, lv_event_code_t code, lv_event_cb_t cb, void *user_data, lv_event_cb_t release_cb)
{
    if (obj == NULL || cb == NULL) {
        return false;
    }
    lv_obj_add_event_cb(obj, cb, code, user_data);
    if (release_cb != NULL) {
        lv_obj_add_event_cb(obj, release_cb, LV_EVENT_DELETE, user_data);
    }
    return true;
}

bool easylvgl_xml_bind_keyboard_events(lv_obj_t *textarea, lv_event_cb_t focus_cb, lv_event_cb_t defocus_cb, lv_event_cb_t release_cb, void *user_data)
{
    if (textarea == NULL || focus_cb == NULL) {
        return false;
    }
    lv_obj_add_event_cb(textarea, focus_cb, LV_EVENT_FOCUSED, user_data);
    if (defocus_cb != NULL) {
        lv_obj_add_event_cb(textarea, defocus_cb, LV_EVENT_DEFOCUSED, user_data);
    }
    if (release_cb != NULL) {
        lv_obj_add_event_cb(textarea, release_cb, LV_EVENT_DELETE, user_data);
    }
    return true;
}

/**
 * XML 功能关闭时的辅助接口实现。
 */
#else

/**
 * XML 功能关闭时的空实现，保证接口可用但执行失败。
 */
bool easylvgl_xml_init(void)
{
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_register_font(const char *name, const lv_font_t *font)
{
    (void)name;
    (void)font;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_deinit(void)
{
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_register_from_file(const char *path)
{
    (void)path;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_register_from_data(const char *name, const char *xml_def)
{
    (void)name;
    (void)xml_def;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

lv_obj_t *easylvgl_xml_create_screen(const char *name)
{
    (void)name;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return NULL;
}

lv_obj_t *easylvgl_xml_find_object(const char *name)
{
    (void)name;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return NULL;
}

bool easylvgl_xml_register_image(const char *name, const void *src)
{
    (void)name;
    (void)src;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_add_event_cb(lv_obj_t *obj, lv_event_code_t code, lv_event_cb_t cb, void *user_data, lv_event_cb_t release_cb)
{
    (void)obj;
    (void)code;
    (void)cb;
    (void)user_data;
    (void)release_cb;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

bool easylvgl_xml_bind_keyboard_events(lv_obj_t *textarea, lv_event_cb_t focus_cb, lv_event_cb_t defocus_cb, lv_event_cb_t release_cb, void *user_data)
{
    (void)textarea;
    (void)focus_cb;
    (void)defocus_cb;
    (void)release_cb;
    (void)user_data;
    LLOGW("LVGL XML disabled (LV_USE_XML=0)");
    return false;
}

#endif

