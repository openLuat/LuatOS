/*
@module plcui.component
@summary 九类组件共用的显隐、禁用、位置与状态查询接口
@version 1.0.2
@tag LUAT_USE_PLCUI
@note 本文件中的 obj 代表 xml:find 返回的任意组件句柄，不是另一个 Lua 构造器。
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_debug.h"
#include <string.h>

/**
 * 将组件类型转换为已注册的 Lua 元表名称。
 * @param type 组件描述中的类型枚举。
 * @return 静态元表名称；不支持的类型返回 NULL，调用方不释放字符串。
 */
static const char *component_metatable(plcui_widget_type_t type)
{
    switch (type) {
    case PLCUI_IMAGE: return PLCUI_IMAGE_MT;
    case PLCUI_LABEL: return PLCUI_LABEL_MT;
    case PLCUI_TEXTAREA: return PLCUI_TEXTAREA_MT;
    case PLCUI_KEYBOARD: return PLCUI_KEYBOARD_MT;
    case PLCUI_CONTAINER: return PLCUI_CONTAINER_MT;
    case PLCUI_TABLE: return PLCUI_TABLE_MT;
    case PLCUI_CHART: return PLCUI_CHART_MT;
    case PLCUI_ANIMIMG: return PLCUI_ANIMIMG_MT;
    case PLCUI_SLIDER: return PLCUI_SLIDER_MT;
    }
    return NULL;
}

/**
 * 从 Lua 栈第 1 项识别组件引用，检查 userdata 大小与九类组件元表。
 * @param L 调用状态机，第 1 项为待识别值。
 * @return 组件引用指针；不是 PLCUI 组件时返回 NULL，不抛出参数异常。
 * @note 此处不检查页面代次或对象是否关闭，完整校验由 check_object 完成。
 */
static plcui_object_ref_t *component_reference(lua_State *L)
{
    static const char *metatables[] = {
        PLCUI_IMAGE_MT, PLCUI_LABEL_MT, PLCUI_TEXTAREA_MT, PLCUI_KEYBOARD_MT, PLCUI_CONTAINER_MT,
        PLCUI_TABLE_MT, PLCUI_CHART_MT, PLCUI_ANIMIMG_MT, PLCUI_SLIDER_MT
    };
    if (lua_type(L, 1) != LUA_TUSERDATA || lua_rawlen(L, 1) != sizeof(plcui_object_ref_t)) return NULL;
    for (unsigned i = 0; i < sizeof(metatables) / sizeof(metatables[0]); ++i) {
        plcui_object_ref_t *reference = luaL_testudata(L, 1, metatables[i]);
        if (reference) return reference;
    }
    return NULL;
}

/**
 * 将 C 层错误转换为 Lua 的 nil,error 两个返回值。
 * @param L 接收返回值的 Lua 状态机。
 * @param error 已填充的错误描述；code 为空时使用 E_INTERNAL。
 * @return 2，栈顶依次为 nil 和包含 code/message 等字段的错误表。
 */
int luat_plcui_push_error(lua_State *L, const plcui_error_t *error)
{
    lua_pushnil(L);
    lua_createtable(L, 0, 7);
    lua_pushstring(L, error->code ? error->code : "E_INTERNAL");
    lua_setfield(L, -2, "code");
    lua_pushstring(L, error->message);
    lua_setfield(L, -2, "message");
    if (error->file[0]) {
        lua_pushstring(L, error->file);
        lua_setfield(L, -2, "file");
    }
    if (error->id[0]) {
        lua_pushstring(L, error->id);
        lua_setfield(L, -2, "id");
    }
    if (error->attribute[0]) {
        lua_pushstring(L, error->attribute);
        lua_setfield(L, -2, "attribute");
    }
    if (error->line) {
        lua_pushinteger(L, (lua_Integer)error->line);
        lua_setfield(L, -2, "line");
        lua_pushinteger(L, (lua_Integer)error->column);
        lua_setfield(L, -2, "column");
    }
    return 2;
}

/**
 * 从错误码和说明构造绑定层错误并压入 Lua 栈。
 * @param L 接收返回值的 Lua 状态机。
 * @param code 错误码字符串。
 * @param message 面向调用方的错误说明。
 * @return 2，对应 Lua 返回的 nil,error。
 */
int luat_plcui_binding_error(lua_State *L, const char *code, const char *message)
{
    plcui_error_t error;
    luat_plcui_error(&error, code, "%s", message);
    return luat_plcui_push_error(L, &error);
}

/**
 * 为成功的设置操作压入统一的 true 返回值。
 * @param L 接收返回值的 Lua 状态机。
 * @return 1，栈顶为 true。
 */
int luat_plcui_binding_success(lua_State *L)
{
    lua_pushboolean(L, true);
    return 1;
}

/**
 * 校验组件句柄的类型、文档/页面代次及 prepare 访问范围。
 * @param L 第 1 项为组件句柄的 Lua 状态机。
 * @param error 失败时写入 E_TYPE、E_BUSY 或 E_OBJECT_CLOSED。
 * @return 当前有效的组件描述；失败返回 NULL，由调用方将 error 返回给 Lua。
 */
plcui_widget_t *luat_plcui_binding_check_object(lua_State *L, plcui_error_t *error)
{
    plcui_object_ref_t *reference = component_reference(L);
    if (!reference) {
        luat_plcui_error(error, "E_TYPE", "Expected a plcui component handle");
        return NULL;
    }
    plcui_document_t *xml = reference->document;
    if (luat_plcui_runtime()->preparing_document && xml != luat_plcui_runtime()->preparing_document) {
        luat_plcui_error(error, "E_BUSY", "Only the prepared document may be accessed during preparation");
        return NULL;
    }
    if (!xml || xml->closed || reference->generation != xml->generation
        || reference->page_index != (unsigned)(xml->preparing_page >= 0 ? xml->preparing_page : xml->current_page)
        || reference->page_index >= xml->page_count
        || reference->page_generation != xml->pages[reference->page_index].instance_generation
        || reference->widget_index >= xml->pages[reference->page_index].count) {
        luat_plcui_error(error, "E_OBJECT_CLOSED", "Component belongs to a closed page instance");
        return NULL;
    }
    return &xml->pages[reference->page_index].widgets[reference->widget_index];
}

/**
 * 校验有效组件句柄并要求其属于指定类型。
 * @param L 第 1 项为组件句柄的 Lua 状态机。
 * @param type 专属方法要求的组件类型。
 * @param error 失败时接收错误，类型不符为 E_TYPE。
 * @return 组件描述；失败返回 NULL。
 */
plcui_widget_t *luat_plcui_binding_check_type(lua_State *L, plcui_widget_type_t type, plcui_error_t *error)
{
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, error);
    if (widget && widget->type != type) {
        luat_plcui_error(error, "E_TYPE", "Method does not support this component type");
        return NULL;
    }
    return widget;
}

/**
 * 创建引用指定页面实例的 Lua 组件句柄，压入栈顶。
 * @param L 接收组件 userdata 的 Lua 状态机。
 * @param xml_handle_stack_index 栈中 XML userdata 的索引。
 * @param page_index 文档内页面的零起始索引。
 * @param widget_index 页面内组件的零起始索引。
 * @note 句柄强引用 XML 并记录文档和页面代次；索引或类型非法时抛出 Lua 异常。
 */
void luat_plcui_binding_push_object(lua_State *L, int xml_handle_stack_index, unsigned page_index, unsigned widget_index)
{
    int xml_index = lua_absindex(L, xml_handle_stack_index);
    plcui_document_t *xml = luaL_checkudata(L, xml_index, PLCUI_XML_MT);
    if (xml->closed || page_index >= xml->page_count || widget_index >= xml->pages[page_index].count) {
        luaL_error(L, "Invalid plcui component index");
        return;
    }
    const char *metatable = component_metatable(xml->pages[page_index].widgets[widget_index].type);
    if (!metatable) {
        luaL_error(L, "Unknown plcui component type");
        return;
    }
    plcui_object_ref_t *reference = lua_newuserdata(L, sizeof(*reference));
    memset(reference, 0, sizeof(*reference));
    reference->document = xml;
    reference->document_ref = LUA_NOREF;
    reference->generation = xml->generation;
    reference->page_generation = xml->pages[page_index].instance_generation;
    reference->page_index = page_index;
    reference->widget_index = widget_index;
    luaL_getmetatable(L, metatable);
    lua_setmetatable(L, -2);
    lua_pushvalue(L, xml_index);
    reference->document_ref = luaL_ref(L, LUA_REGISTRYINDEX);
}

/**
 * Lua 回收组件句柄时解除其对 XML 实例的强引用。
 * @param L 第 1 项为待回收组件句柄的 Lua 状态机。
 * @return 0，不向 Lua 返回值；不会单独销毁原生组件对象。
 */
static int component_gc(lua_State *L)
{
    plcui_object_ref_t *reference = component_reference(L);
    if (!reference) return 0;
    int xml_reference = reference->document_ref;
    reference->document_ref = LUA_NOREF;
    reference->document = NULL;
    if (xml_reference != LUA_NOREF && xml_reference != LUA_REFNIL) luaL_unref(L, LUA_REGISTRYINDEX, xml_reference);
    return 0;
}

/**
 * 设置组件显示或隐藏状态。
 * @api obj:set_hidden(hidden)
 * @bool hidden true 为隐藏，false 为显示
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 适用于全部组件；隐藏容器会影响全部后代。
 * @note 影响当前编辑的 textarea 或 keyboard 时取消编辑。
 * @note keyboard 只能在已有输入会话中显示，直接显示未绑定键盘返回 E_INPUT_SESSION。
 * @note 显示时同步准备新可见资源，失败恢复原显隐状态；prepare 中延后到首帧统一准备。
 * @note 隐藏会取消受影响的按压/拖动，动画暂停；滚动 Label 停止，重新显示从头滚动。
 * @usage
 * local obj = xml:find("main", "panel")
 * obj:set_hidden(true)
 * obj:set_hidden(false)
 */
static int component_set_hidden(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    bool hidden = lua_toboolean(L, 2) != 0;
    plcui_document_t *xml = widget->document;
    if (widget->type == PLCUI_KEYBOARD) {
        if (hidden && xml->keyboard == widget) luat_plcui_input_finish(xml, false, true);
        if (!hidden && xml->keyboard != widget) return luat_plcui_binding_error(L, "E_INPUT_SESSION", "Keyboard visibility requires an active input session");
    } else if (hidden && (luat_plcui_component_is_within(xml->editing, widget)
                          || luat_plcui_component_is_within(xml->keyboard, widget))) {
        luat_plcui_input_finish(xml, false, true);
    }
    bool previous = widget->hidden;
    widget->hidden = hidden;
    if (hidden) lv_obj_add_flag(widget->obj, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_remove_flag(widget->obj, LV_OBJ_FLAG_HIDDEN);
    if (!hidden && xml->preparing_page < 0
        && !luat_plcui_prepare_page_images(xml, (int)widget->page_index, &error)) {
        widget->hidden = previous;
        if (previous) lv_obj_add_flag(widget->obj, LV_OBJ_FLAG_HIDDEN);
        return luat_plcui_push_error(L, &error);
    }
    if (hidden) luat_plcui_component_cancel_pointer(widget, "hidden");
    luat_plcui_components_sync(xml);
    return luat_plcui_binding_success(L);
}

/**
 * 设置组件是否禁用交互。
 * @api obj:set_disabled(disabled)
 * @bool disabled true 为禁用，false 为启用
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 容器禁用会限制后代交互，重新启用时保留后代自身的禁用设置。
 * @note 影响当前编辑的 textarea 或 keyboard 时取消编辑。
 * @note 禁用不会等同隐藏；受影响的拖动/按压会取消，动画和滚动文字暂停。
 * @note 状态图准备失败时返回错误并恢复禁用配置；prepare 中由首帧统一准备。
 * @usage
 * local obj = xml:find("main", "start_button")
 * obj:set_disabled(true)
 * obj:set_disabled(false)
 */
static int component_set_disabled(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    bool previous = widget->disabled;
    widget->disabled = lua_toboolean(L, 2) != 0;
    plcui_document_t *xml = widget->document;
    if (!luat_plcui_component_sync_disabled(widget, &error)) {
        widget->disabled = previous;
        plcui_error_t ignored;
        luat_plcui_component_sync_disabled(widget, &ignored);
        return luat_plcui_push_error(L, &error);
    }
    if (widget->disabled && (luat_plcui_component_is_within(xml->editing, widget)
                             || luat_plcui_component_is_within(xml->keyboard, widget))) {
        luat_plcui_input_finish(xml, false, true);
    }
    if (widget->disabled) luat_plcui_component_cancel_pointer(widget, "disabled");
    luat_plcui_components_sync(xml);
    return luat_plcui_binding_success(L);
}

/**
 * 设置组件相对于父容器内容区的逻辑位置。
 * @api obj:set_pos(x, y)
 * @int x 水平坐标，范围 -4096～4096 像素
 * @int y 垂直坐标，范围 -4096～4096 像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回含 code、message 的错误表
 * @note 所有组件共用；移动 container 时子组件自然跟随，子组件局部坐标不变。
 * @note 立即移动，不提供平滑动画；不会回写 XML。当前值相同时不做额外处理。
 * @note 新可见资源准备失败时回滚位置；真实移动会取消受影响的按压/拖动。
 * @note 正在编辑的输入框保持可见时保留会话；目标或关联键盘完全移出可见区域时取消编辑。
 * @note 同文档切页重建保留当前位置；重新 load 恢复 XML 初值，prepare 可覆盖本次位置。
 * @usage
 * local obj = xml:find("main", "logo")
 * obj:set_pos(100, 50)
 */
static int component_set_pos(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    if (!lua_isinteger(L, 2) || !lua_isinteger(L, 3)) return luat_plcui_binding_error(L, "E_SCHEMA", "Position requires two integers");
    lua_Integer x = lua_tointeger(L, 2), y = lua_tointeger(L, 3);
    if (x < -4096 || x > 4096 || y < -4096 || y > 4096) return luat_plcui_binding_error(L, "E_SCHEMA", "Position must be between -4096 and 4096");
    if (!luat_plcui_component_set_pos(widget, (int32_t)x, (int32_t)y, &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}

/**
 * 在组件当前局部逻辑位置上累加偏移，立即完成移动。
 * @api obj:move(dx, dy)
 * @int dx 水平偏移，范围 -8192～8192 像素
 * @int dy 垂直偏移，范围 -8192～8192 像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回含 code、message 的错误表
 * @note 最终 x/y 仍须落在 -4096～4096；非整数或越界返回 E_SCHEMA，原位置不变。
 * @note 其余语义与 set_pos 相同；move(0, 0) 不取消输入、不重复准备资源。
 * @usage
 * local obj = xml:find("main", "panel")
 * obj:move(20, -10)
 */
static int component_move(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    if (!lua_isinteger(L, 2) || !lua_isinteger(L, 3)) return luat_plcui_binding_error(L, "E_SCHEMA", "Movement requires two integers");
    lua_Integer dx = lua_tointeger(L, 2), dy = lua_tointeger(L, 3);
    if (dx < -8192 || dx > 8192 || dy < -8192 || dy > 8192) return luat_plcui_binding_error(L, "E_SCHEMA", "Movement exceeds position range");
    if (!luat_plcui_component_set_pos(widget, widget->x + (int32_t)dx, widget->y + (int32_t)dy, &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}

/**
 * 获取组件相对于父容器内容区的局部逻辑坐标。
 * @api obj:get_pos()
 * @return int|nil 成功返回 x；句柄无效等运行错误返回 nil
 * @return int|table 成功返回 y；失败时为含 code、message 的错误表
 * @note 不同于 state().x/y 的页面坐标；返回值可直接作为 set_pos 的位置参数。
 * @usage
 * local obj = xml:find("main", "logo")
 * local x, y = obj:get_pos()
 * log.info("ui", "local position", x, y)
 */
static int component_get_pos(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushinteger(L, widget->x); lua_pushinteger(L, widget->y);
    return 2;
}

/**
 * 获取组件当前状态和实际布局。
 * @api obj:state()
 * @return table|nil 成功返回状态表，运行错误返回 nil
 * @return table|nil 失败时返回错误表
 * @note 字段包括 id、type、x、y、w、h、hidden、disabled、checked、pressed；image 另含默认资源 ID src。
 * @note 文字组件另含 font；使用 HZFont 时还返回有效的 font_size。
 * @note table 另含 rows/columns；chart 另含 point_count/series_count/y_min/y_max。
 * @note x、y 是页面绝对坐标，XML 子节点坐标相对于父容器内容区。
 * @note hidden、disabled 描述组件自身状态，祖先状态仍影响实际交互。
 * @note image 还含 fit/opacity/antialias 和 crop={enabled,x,y,w,h}；非裁片 center 模式另含 zoom、rotation 及 pivot={explicit,x,y}。
 * @note image 的 rotation 为 0.1 度单位，zoom 以 256 为原始倍率；状态表描述配置，不将自动 fit 比例作为手动 zoom 返回。
 * @note Slider 还含 min/max/step/value/dragging；value 为当前预览值，拖动结束语义见 Slider 事件。
 * @note animimg 还含 animation_state、frame（1 起）、completed_loops、playing；playing 表示当前未因可见性暂停的播放状态。
 * @note animation_state 为 stopped/playing/paused/finished/error；组件状态表是快照，修改表不会更新界面。
 * @usage
 * local obj = xml:find("main", "logo")
 * local state = obj:state()
 * log.info("ui", state.type, state.x, state.y, state.w, state.h)
 */
static int component_state(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    static const char *types[] = {"image", "label", "textarea", "keyboard", "container", "table", "chart", "animimg", "slider"};
    lv_area_t bounds, screen_bounds;
    lv_obj_update_layout(widget->obj);
    lv_obj_get_coords(widget->obj, &bounds);
    lv_obj_get_coords(widget->document->pages[widget->page_index].screen, &screen_bounds);
    lua_createtable(L, 0, 12);
    lua_pushstring(L, widget->id);
    lua_setfield(L, -2, "id");
    lua_pushstring(L, types[widget->type]);
    lua_setfield(L, -2, "type");
    lua_pushboolean(L, lv_obj_has_flag(widget->obj, LV_OBJ_FLAG_HIDDEN));
    lua_setfield(L, -2, "hidden");
    lua_pushboolean(L, widget->disabled);
    lua_setfield(L, -2, "disabled");
    lua_pushboolean(L, widget->checked);
    lua_setfield(L, -2, "checked");
    lua_pushboolean(L, widget->pressed);
    lua_setfield(L, -2, "pressed");
    lua_pushinteger(L, bounds.x1 - screen_bounds.x1);
    lua_setfield(L, -2, "x");
    lua_pushinteger(L, bounds.y1 - screen_bounds.y1);
    lua_setfield(L, -2, "y");
    lua_pushinteger(L, lv_area_get_width(&bounds));
    lua_setfield(L, -2, "w");
    lua_pushinteger(L, lv_area_get_height(&bounds));
    lua_setfield(L, -2, "h");
    if (widget->type == PLCUI_IMAGE) {
        lua_pushstring(L, widget->source[0]);
        lua_setfield(L, -2, "src");
        plcui_image_t *image = widget->image;
        lv_image_align_t fit = image ? image->fit : LV_IMAGE_ALIGN_STRETCH;
        const char *name = fit == LV_IMAGE_ALIGN_CENTER ? "center" : fit == LV_IMAGE_ALIGN_CONTAIN ? "contain" : fit == LV_IMAGE_ALIGN_COVER ? "cover" : "stretch";
        lua_pushstring(L, name); lua_setfield(L, -2, "fit");
        lua_pushinteger(L, image ? image->opacity : 255); lua_setfield(L, -2, "opacity");
        lua_pushboolean(L, !image || image->antialias); lua_setfield(L, -2, "antialias");
        if (fit == LV_IMAGE_ALIGN_CENTER && image && !image->crop) {
            lua_pushinteger(L, image->zoom); lua_setfield(L, -2, "zoom");
            lua_pushinteger(L, image->rotation); lua_setfield(L, -2, "rotation");
            lua_createtable(L, 0, 3);
            lua_pushboolean(L, image->pivot_explicit); lua_setfield(L, -2, "explicit");
            lua_pushinteger(L, image->pivot_explicit ? image->pivot_x : (int32_t)lv_image_get_src_width(widget->obj) / 2); lua_setfield(L, -2, "x");
            lua_pushinteger(L, image->pivot_explicit ? image->pivot_y : (int32_t)lv_image_get_src_height(widget->obj) / 2); lua_setfield(L, -2, "y");
            lua_setfield(L, -2, "pivot");
        }
        lua_createtable(L, 0, 5);
        lua_pushboolean(L, image && image->crop); lua_setfield(L, -2, "enabled");
        lua_pushinteger(L, image ? image->crop_x : 0); lua_setfield(L, -2, "x");
        lua_pushinteger(L, image ? image->crop_y : 0); lua_setfield(L, -2, "y");
        lua_pushinteger(L, widget->w); lua_setfield(L, -2, "w");
        lua_pushinteger(L, widget->h); lua_setfield(L, -2, "h");
        lua_setfield(L, -2, "crop");
    }
    if (widget->slider) {
        lua_pushinteger(L, widget->slider->minimum); lua_setfield(L, -2, "min");
        lua_pushinteger(L, widget->slider->maximum); lua_setfield(L, -2, "max");
        lua_pushinteger(L, widget->slider->step); lua_setfield(L, -2, "step");
        lua_pushinteger(L, widget->slider->value); lua_setfield(L, -2, "value");
        lua_pushboolean(L, widget->slider->dragging); lua_setfield(L, -2, "dragging");
    }
    if (widget->animation) {
        static const char *states[] = {"stopped", "playing", "paused", "finished", "error"};
        lua_pushstring(L, states[widget->animation->state]); lua_setfield(L, -2, "animation_state");
        lua_pushinteger(L, widget->animation->frame + 1U); lua_setfield(L, -2, "frame");
        lua_pushinteger(L, widget->animation->completed_loops); lua_setfield(L, -2, "completed_loops");
        lua_pushboolean(L, widget->animation->state == PLCUI_ANIM_PLAYING && !widget->animation->suspended); lua_setfield(L, -2, "playing");
    }
    if (widget->type == PLCUI_LABEL || widget->type == PLCUI_TEXTAREA || widget->type == PLCUI_KEYBOARD
        || widget->type == PLCUI_TABLE) {
        lua_pushstring(L, widget->font_id);
        lua_setfield(L, -2, "font");
        if (widget->use_hzfont) {
            lua_pushinteger(L, widget->font_size);
            lua_setfield(L, -2, "font_size");
        }
    }
    if (widget->table) {
        lua_pushinteger(L, widget->table->rows);
        lua_setfield(L, -2, "rows");
        lua_pushinteger(L, widget->table->columns);
        lua_setfield(L, -2, "columns");
    }
    if (widget->chart) {
        lua_pushinteger(L, widget->chart->points);
        lua_setfield(L, -2, "point_count");
        lua_pushinteger(L, widget->chart->count);
        lua_setfield(L, -2, "series_count");
        lua_pushnumber(L, (lua_Number)widget->chart->minimum);
        lua_setfield(L, -2, "y_min");
        lua_pushnumber(L, (lua_Number)widget->chart->maximum);
        lua_setfield(L, -2, "y_max");
    }
    return 1;
}

/**
 * 在保留原方法返回值和参数异常语义的前提下，记录一次同步调用耗时。
 * @param L 第 1 项为组件句柄；第 1 个 upvalue 为静态 luaL_Reg 方法描述。
 * @return 被包装方法的 Lua 返回值个数，不新增返回值。
 * @note 调试关闭或句柄校验失败时直接调用原方法；Lua 异常不通过 pcall 截获。
 */
static int timed_component_method(lua_State *L)
{
    const luaL_Reg *method = lua_touserdata(L, lua_upvalueindex(1));
    if (!plcui_debug_enabled()) return method->func(L);
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return method->func(L); /* 保留原方法的错误返回路径。 */
    unsigned type = widget->type;
    bool preparing = widget->document->preparing_page >= 0;
    char page[PLCUI_ID_MAX], id[PLCUI_ID_MAX];
    memcpy(page, widget->document->pages[widget->page_index].id, sizeof(page));
    memcpy(id, widget->id, sizeof(id));
    uint32_t started = plcui_debug_now();
    /* 不加 pcall 包装或全局作用域，保留 luaL_error 原有的栈语义。 */
    int results = method->func(L);
    uint32_t elapsed = plcui_debug_now() - started;
    bool success = results > 0 && !lua_isnil(L, -results);
    plcui_debug_record(type, preparing ? "prepare" : "update", method->name,
                       page, id, elapsed, success);
    return results;
}

/**
 * 将静态方法表注册到栈顶元表，并为可更新方法安装可选计时包装。
 * @param L 栈顶为目标元表的 Lua 状态机。
 * @param methods 以 name=NULL 结束的静态 luaL_Reg 数组，生命周期覆盖全部调用。
 * @note getter 直接注册；包装只统计同步调用，不包括后续异步绘制或面板扫描。
 */
void luat_plcui_binding_register_methods(lua_State *L, const luaL_Reg *methods)
{
    int table = lua_absindex(L, -1);
    for (const luaL_Reg *method = methods; method->name; ++method) {
        if (PLCUI_PERF_ENABLE && (!strncmp(method->name, "set_", 4)
            || !strcmp(method->name, "add_point") || !strcmp(method->name, "focus")
            || !strcmp(method->name, "move") || !strcmp(method->name, "clear_crop")
            || !strcmp(method->name, "play") || !strcmp(method->name, "pause") || !strcmp(method->name, "stop"))) {
            lua_pushlightuserdata(L, (void *)method);
            lua_pushcclosure(L, timed_component_method, 1);
        } else lua_pushcfunction(L, method->func);
        lua_setfield(L, table, method->name);
    }
}

/**
 * 向栈顶组件元表注册公共方法、GC 和 __index。
 * @param L 栈顶为目标组件元表的 Lua 状态机。
 * @note 供九类组件注册函数共用；不创建组件对象，不改变原有专属方法。
 */
void luat_plcui_binding_register_common(lua_State *L)
{
    static const luaL_Reg common_methods[] = {
        {"set_hidden", component_set_hidden},
        {"set_disabled", component_set_disabled},
        {"set_pos", component_set_pos},
        {"move", component_move},
        {"get_pos", component_get_pos},
        {"state", component_state},
        {"__gc", component_gc},
        {NULL, NULL}
    };
    luat_plcui_binding_register_methods(L, common_methods);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
}
