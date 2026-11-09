/** @file luat_lib_plcui_common.c Shared Lua errors, handle lifetime and component methods. */
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <string.h>

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
    }
    return NULL;
}

static plcui_object_ref_t *component_reference(lua_State *L)
{
    static const char *metatables[] = {
        PLCUI_IMAGE_MT, PLCUI_LABEL_MT, PLCUI_TEXTAREA_MT, PLCUI_KEYBOARD_MT, PLCUI_CONTAINER_MT,
        PLCUI_TABLE_MT, PLCUI_CHART_MT
    };
    if (lua_type(L, 1) != LUA_TUSERDATA || lua_rawlen(L, 1) != sizeof(plcui_object_ref_t)) return NULL;
    for (unsigned i = 0; i < sizeof(metatables) / sizeof(metatables[0]); ++i) {
        plcui_object_ref_t *reference = luaL_testudata(L, 1, metatables[i]);
        if (reference) return reference;
    }
    return NULL;
}

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

int luat_plcui_binding_error(lua_State *L, const char *code, const char *message)
{
    plcui_error_t error;
    luat_plcui_error(&error, code, "%s", message);
    return luat_plcui_push_error(L, &error);
}

int luat_plcui_binding_success(lua_State *L)
{
    lua_pushboolean(L, true);
    return 1;
}

plcui_widget_t *luat_plcui_binding_check_object(lua_State *L, plcui_error_t *error)
{
    plcui_object_ref_t *reference = component_reference(L);
    if (!reference) {
        luat_plcui_error(error, "E_TYPE", "Expected a plcui component handle");
        return NULL;
    }
    plcui_document_t *xml = reference->document;
    if (!xml || xml->closed || reference->generation != xml->generation
        || reference->page_index != (unsigned)xml->current_page
        || reference->page_index >= xml->page_count
        || reference->widget_index >= xml->pages[reference->page_index].count) {
        luat_plcui_error(error, "E_OBJECT_CLOSED", "Component belongs to a closed page instance");
        return NULL;
    }
    return &xml->pages[reference->page_index].widgets[reference->widget_index];
}

plcui_widget_t *luat_plcui_binding_check_type(lua_State *L, plcui_widget_type_t type, plcui_error_t *error)
{
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, error);
    if (widget && widget->type != type) {
        luat_plcui_error(error, "E_TYPE", "Method does not support this component type");
        return NULL;
    }
    return widget;
}

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
    reference->page_index = page_index;
    reference->widget_index = widget_index;
    luaL_getmetatable(L, metatable);
    lua_setmetatable(L, -2);
    lua_pushvalue(L, xml_index);
    reference->document_ref = luaL_ref(L, LUA_REGISTRYINDEX);
}

/**
 * Lua 回收组件句柄时解除其对 XML 实例的强引用。
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
    widget->hidden = hidden;
    if (hidden) lv_obj_add_flag(widget->obj, LV_OBJ_FLAG_HIDDEN);
    else lv_obj_remove_flag(widget->obj, LV_OBJ_FLAG_HIDDEN);
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
 */
static int component_set_disabled(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    widget->disabled = lua_toboolean(L, 2) != 0;
    plcui_document_t *xml = widget->document;
    if (widget->disabled && (luat_plcui_component_is_within(xml->editing, widget)
                             || luat_plcui_component_is_within(xml->keyboard, widget))) {
        luat_plcui_input_finish(xml, false, true);
    }
    luat_plcui_component_sync_disabled(widget);
    return luat_plcui_binding_success(L);
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
 */
static int component_state(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_object(L, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    static const char *types[] = {"image", "label", "textarea", "keyboard", "container", "table", "chart"};
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
        lua_pushnumber(L, (lua_Number)widget->chart->minimum / PLCUI_CHART_SCALE);
        lua_setfield(L, -2, "y_min");
        lua_pushnumber(L, (lua_Number)widget->chart->maximum / PLCUI_CHART_SCALE);
        lua_setfield(L, -2, "y_max");
    }
    return 1;
}

/**
 * 向当前组件元表注册公共方法、GC 和索引表。
 */
void luat_plcui_binding_register_common(lua_State *L)
{
    static const luaL_Reg common_methods[] = {
        {"set_hidden", component_set_hidden},
        {"set_disabled", component_set_disabled},
        {"state", component_state},
        {"__gc", component_gc},
        {NULL, NULL}
    };
    luaL_setfuncs(L, common_methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
}
