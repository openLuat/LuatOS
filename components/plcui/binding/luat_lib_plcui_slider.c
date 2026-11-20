/*
@module plcui.slider
@summary XML 单值滑块
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"

#if LV_USE_SLIDER
/**
 * 读取并校验 Slider 使用的有符号整数参数。
 * @param L Lua 状态机。
 * @param index 待检查参数的栈索引。
 * @param value 成功时接收 -32768～32767 范围内的整数。
 * @return 校验通过返回 true，类型或范围不匹配返回 false，不压入 Lua 返回值。
 */
static bool slider_integer(lua_State *L, int index, int32_t *value)
{
    if (!lua_isinteger(L, index)) return false;
    lua_Integer candidate = lua_tointeger(L, index);
    if (candidate < -32768 || candidate > 32767) return false;
    *value = (int32_t)candidate;
    return true;
}

/**
 * 获取 Slider 当前值；拖动过程中返回当前预览值。
 * @api slider:get_value()
 * @return int|nil 成功返回当前整数值，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 预览值按 step 吸附，旋钮在拖动中跟随指针，松手后停在步进位置。
 * @note 没有拖动时为已提交或程序设置的值；方法本身不改变数值或派发事件。
 * @usage
 * local slider = xml:find("main", "speed")
 * local value = slider:get_value()
 */
static int slider_get_value(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_SLIDER, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushinteger(L, widget->slider->value);
    return 1;
}

/**
 * 校验后静默设置数值；正在拖动时先取消本轮拖动。
 * @api slider:set_value(value)
 * @int value -32768～32767 范围内的整数，须位于当前 min/max 之间，且 value-min 为 step 的整数倍
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 非整数、越界或不在步进网格上返回 E_SCHEMA，旧值和拖动状态保持不变。
 * @note 有效调用时先取消正在进行的拖动，即使 value 与当前预览值相同也会取消；取消事件 reason="programmatic"。
 * @note 程序赋值不产生 on-change 或 on-submit，拖动取消产生的 on-cancel 仍按原规则派发。
 * @usage
 * local slider = xml:find("main", "speed")
 * slider:set_value(50) -- 当前范围和 step 必须允许 50
 */
static int slider_set_value(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_SLIDER, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_slider_t *slider = widget->slider;
    int32_t value;
    if (!slider_integer(L, 2, &value) || value < slider->minimum || value > slider->maximum
        || (uint32_t)(value - slider->minimum) % slider->step) {
        return luat_plcui_binding_error(L, "E_SCHEMA", "Slider value must be an integer on its range and step grid");
    }
    luat_plcui_slider_cancel(widget, "programmatic");
    slider->value = value;
    lv_slider_set_value(widget->obj, value, LV_ANIM_OFF);
    return luat_plcui_binding_success(L);
}

/**
 * 原子更新整数范围和步进，并将当前值夹取、吸附到新网格。
 * @api slider:set_range(minimum, maximum[, step])
 * @int minimum 范围下限，-32768～32767，须小于 maximum
 * @int maximum 范围上限，-32768～32767
 * @int step 可选整数，1～65535，省略或 nil 时保留当前 step，须整除 maximum-minimum
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 全部参数校验成功后才取消当前拖动；非法参数返回 E_SCHEMA，旧范围、数值和拖动状态不变。
 * @note 取消拖动后按恢复的起点值做新范围夹取、就近步进吸附，再静默设置；不产生用户 on-submit。
 * @note 默认 XML 范围为 0～100、step=1；此接口不改变横纵方向或组件尺寸。
 * @usage
 * local slider = xml:find("main", "speed")
 * slider:set_range(0, 100, 5)
 * slider:set_value(50)
 */
static int slider_set_range(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_SLIDER, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    plcui_slider_t *slider = widget->slider;
    int32_t minimum, maximum;
    lua_Integer step = slider->step;
    if (!lua_isnoneornil(L, 4)) {
        if (!lua_isinteger(L, 4)) return luat_plcui_binding_error(L, "E_SCHEMA", "Slider step must be an integer");
        step = lua_tointeger(L, 4);
    }
    if (!slider_integer(L, 2, &minimum) || !slider_integer(L, 3, &maximum) || minimum >= maximum
        || step < 1 || step > 65535 || (maximum - minimum) % step) {
        return luat_plcui_binding_error(L, "E_SCHEMA", "Slider requires -32768 <= min < max <= 32767 and a step dividing its range");
    }
    luat_plcui_slider_cancel(widget, "programmatic");
    int32_t value = luat_plcui_slider_snap(slider->value, minimum, maximum, (uint32_t)step);
    slider->minimum = minimum;
    slider->maximum = maximum;
    slider->step = (uint32_t)step;
    slider->value = value;
    lv_slider_set_range(widget->obj, minimum, maximum);
    lv_slider_set_value(widget->obj, value, LV_ANIM_OFF);
    return luat_plcui_binding_success(L);
}
#else
/**
 * 在未编译 Slider 时返回统一的 Lua 不支持错误。
 * @param L Lua 状态机。
 * @return Lua 返回值个数，固定为 2，内容为 nil 和 E_NOT_SUPPORTED 错误表。
 * @note 仅为禁用功能构建的内部占位入口，三个 Slider 方法共用。
 */
static int slider_get_value(lua_State *L)
{
    return luat_plcui_binding_error(L, "E_NOT_SUPPORTED", "Slider support is not compiled");
}
#define slider_set_value slider_get_value
#define slider_set_range slider_get_value
#endif

/**
 * 注册 Slider 的数值、范围方法与公共组件方法。
 * @param L Lua 状态机。
 * @note 仅为 C 层注册入口；Lua 通过 xml:find 获取 slider 句柄。
 */
void luat_plcui_register_slider_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"get_value", slider_get_value},
        {"set_value", slider_set_value},
        {"set_range", slider_set_range},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_SLIDER_MT);
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
