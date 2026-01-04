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
    lv_screen_load(screen);
    return screen;
}

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

#else

/**
 * XML 功能关闭时的空实现，保证接口可用但执行失败。
 */
bool easylvgl_xml_init(void)
{
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

#endif

