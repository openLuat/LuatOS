/**
 * @file luat_airui_bar.c
 * @summary Bar/进度条组件实现
 * @responsible Bar 组件创建、值/颜色设置
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/bar/lv_bar.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>
#include <stdbool.h>

/**
 * 通过 Lua config 创建 Bar 组件
 * @brief 根据传入的 Lua 表参数解析并创建 LVGL Bar（进度条）对象，配置其样式、范围、初始值等。
 * @param L Lua 虚拟机指针（lua_State*，void* 以适应泛型调用）
 * @param idx Lua 参数表在 Lua 栈中的索引
 * @return 新创建的 lv_obj_t* Bar 对象，失败时为 NULL
 */
lv_obj_t *airui_bar_create_from_config(void *L, int idx)
{
    // 检查 Lua 虚拟机指针是否有效
    if (L == NULL) {
        return NULL;
    }

    // 强转为 lua_State
    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = NULL;

    // 从全局注册表获取 airui_ctx（上下文）
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    // 上下文校验，未初始化直接返回
    if (ctx == NULL) {
        return NULL;
    }

    // 1. 解析配置参数
    lv_obj_t *parent = airui_marshal_parent(L, idx); // 父对象（容器等）
    int x = airui_marshal_integer(L, idx, "x", 0);   // X 坐标
    int y = airui_marshal_integer(L, idx, "y", 0);   // Y 坐标
    int w = airui_marshal_integer(L, idx, "w", 200); // 宽度
    int h = airui_marshal_integer(L, idx, "h", 20);  // 高度
    int min = airui_marshal_integer(L, idx, "min", 0); // 最小值
    int max = airui_marshal_integer(L, idx, "max", 100); // 最大值
    if (max < min) {
        max = min;
    }

    // 2. 创建 Bar 对象
    lv_obj_t *bar = lv_bar_create(parent);
    if (bar == NULL) {
        return NULL;
    }

    // 3. 配置基本属性（位置、尺寸、范围）
    lv_obj_set_pos(bar, x, y);
    lv_obj_set_size(bar, w, h);
    lv_bar_set_range(bar, min, max);

    // 4. 解析初始值并设置（保证范围合法）
    lv_coord_t value = airui_marshal_integer(L, idx, "value", min);
    if (value < min) value = min;
    if (value > max) value = max;
    lv_bar_set_value(bar, value, LV_ANIM_OFF);

    // 5. 解析样式参数
    int radius = airui_marshal_integer(L, idx, "radius", 4);              // 圆角
    int border_width = airui_marshal_integer(L, idx, "border_width", 0);  // 边框宽度

    // 6. 默认颜色设置
    lv_color_t bg_default = lv_color_make(0x20, 0x28, 0x35);
    lv_color_t indicator_default = lv_color_make(0x00, 0xb4, 0xff);
    lv_color_t border_default = lv_color_make(0x00, 0x44, 0xaa);

    lv_color_t bg_color = bg_default;
    lv_color_t indicator_color = indicator_default;
    lv_color_t border_color = border_default;

    // 7. 解析颜色参数（bg_color、indicator_color、border_color）
    lv_color_t parsed_color;
    if (airui_marshal_color(L_state, idx, "bg_color", &parsed_color)) {
        bg_color = parsed_color;
    }
    if (airui_marshal_color(L_state, idx, "indicator_color", &parsed_color)) {
        indicator_color = parsed_color;
    }
    if (airui_marshal_color(L_state, idx, "border_color", &parsed_color)) {
        border_color = parsed_color;
    }

    // 8. 应用样式（圆角、边框、颜色等）
    lv_obj_set_style_radius(bar, radius, LV_PART_MAIN | LV_STATE_DEFAULT); // 主体圆角
    lv_obj_set_style_radius(bar, radius, LV_PART_INDICATOR | LV_STATE_DEFAULT); // 指示器圆角
    lv_obj_set_style_border_width(bar, border_width, LV_PART_MAIN | LV_STATE_DEFAULT); // 主体边框宽度
    lv_obj_set_style_border_color(bar, border_color, LV_PART_MAIN | LV_STATE_DEFAULT); // 主体边框颜色
    lv_obj_set_style_bg_color(bar, bg_color, LV_PART_MAIN | LV_STATE_DEFAULT); // 主体背景色
    lv_obj_set_style_bg_color(bar, indicator_color, LV_PART_INDICATOR | LV_STATE_DEFAULT); // 指示器色

    // 9. 组件元数据注册，失败则释放对象
    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, bar, AIRUI_COMPONENT_BAR);
    if (meta == NULL) {
        lv_obj_delete(bar);
        return NULL;
    }

    // 返回创建成功的 Bar
    return bar;
}

/**
 * 设置 Bar 当前值
 */
int airui_bar_set_value(lv_obj_t *bar, lv_coord_t value, bool animated)
{
    if (bar == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_bar_set_value(bar, value, animated ? LV_ANIM_ON : LV_ANIM_OFF);
    return AIRUI_OK;
}

/**
 * 设置 Bar 范围
 */
int airui_bar_set_range(lv_obj_t *bar, lv_coord_t min, lv_coord_t max)
{
    if (bar == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (max < min) {
        lv_coord_t tmp = min;
        min = max;
        max = tmp;
    }

    lv_bar_set_range(bar, min, max);
    return AIRUI_OK;
}

/**
 * 设置进度指示器颜色
 */
int airui_bar_set_indicator_color(lv_obj_t *bar, lv_color_t color)
{
    if (bar == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_style_bg_color(bar, color, LV_PART_INDICATOR | LV_STATE_DEFAULT);
    return AIRUI_OK;
}

/**
 * 设置背景颜色
 */
int airui_bar_set_bg_color(lv_obj_t *bar, lv_color_t color)
{
    if (bar == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_style_bg_color(bar, color, LV_PART_MAIN | LV_STATE_DEFAULT);
    return AIRUI_OK;
}

/**
 * 获取 Bar 当前值
 */
int airui_bar_get_value(lv_obj_t *bar)
{
    if (bar == NULL) {
        return 0;
    }
    return (int)lv_bar_get_value(bar);
}

