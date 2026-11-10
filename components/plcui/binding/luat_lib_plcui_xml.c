/** @file luat_lib_plcui_xml.c XML loading and XML instance methods. */
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <string.h>

static plcui_document_t *xml_arg(lua_State *L)
{
    plcui_document_t *xml = luaL_checkudata(L, 1, PLCUI_XML_MT);
    if (lua_rawlen(L, 1) != sizeof(*xml)) luaL_argerror(L, 1, "invalid XML instance");
    return xml;
}

/**
 * 加载 XML 和资源，创建并显示入口页面。
 * @api plcui.load(path, options)
 * @string path XML 的绝对 VFS 路径，如 /luadb/main.xml 或 /sd/panel/main.xml
 * @table options 可选加载配置
 * @table options.handlers 命名事件函数表，键需对应 XML 声明的事件名称
 * @return userdata|nil 成功返回 XML 界面实例 xml，失败返回 nil
 * @return table|nil 失败时返回错误表
 * @note 需要先调用 plcui.init；图片资源路径相对于 XML 所在目录。
 * @note 成功后替换旧界面，失败保留旧界面。
 * @note 业务事件回调中不能直接加载新 XML，否则返回 E_BUSY。
 */
int luat_plcui_xml_load(lua_State *L)
{
    plcui_runtime_t *runtime = luat_plcui_runtime();
    if (!runtime->initialized) return luat_plcui_binding_error(L, "E_NOT_INITIALIZED", "Call plcui.init first");
    if (runtime->refreshing || (runtime->document && (runtime->document->dispatching || runtime->document->switching))) return luat_plcui_binding_error(L, "E_BUSY", "Load a new document outside an event callback");
    const char *path = luaL_checkstring(L, 1);
    plcui_document_t *xml = lua_newuserdata(L, sizeof(*xml));
    memset(xml, 0, sizeof(*xml));
    xml->L = runtime->L;
    xml->self_ref = LUA_NOREF;
    xml->handlers_ref = LUA_NOREF;
    xml->current_page = -1;
    xml->pending_page = -1;
    xml->generation = 1;
    luaL_getmetatable(L, PLCUI_XML_MT);
    lua_setmetatable(L, -2);
    int xml_stack_index = lua_gettop(L);
    if (lua_istable(L, 2)) lua_getfield(L, 2, "handlers");
    else lua_pushnil(L);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
    }
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        xml->closed = true;
        return luat_plcui_binding_error(L, "E_HANDLER", "options.handlers must be a table");
    }
    /* Copy the handler table so later caller mutations cannot remove validated bindings. */
    int source = lua_gettop(L);
    lua_newtable(L);
    int target = lua_gettop(L);
    lua_pushnil(L);
    while (lua_next(L, source)) {
        if (lua_type(L, -2) == LUA_TSTRING && lua_isfunction(L, -1)) {
            lua_pushvalue(L, -2);
            lua_pushvalue(L, -2);
            lua_settable(L, target);
        }
        lua_pop(L, 1);
    }
    xml->handlers_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);
    plcui_error_t error;
    if (!luat_plcui_parse(xml, path, &error) || !luat_plcui_show(xml, luat_plcui_page_index(xml, xml->entry), &error)) {
        luat_plcui_close(xml);
        return luat_plcui_push_error(L, &error);
    }
    plcui_document_t *old = runtime->document;
    if (old) {
        /* The new screen is already valid; closing old must not replace it with idle. */
        runtime->document = NULL;
        luat_plcui_close(old);
    }
    lua_pushvalue(L, xml_stack_index);
    xml->self_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    runtime->document = xml;
    lua_pushvalue(L, xml_stack_index);
    return 1;
}

/**
 * 按页面 ID 和组件 ID 查找组件。
 * @api xml:find(page_id, component_id)
 * @string page_id 当前已实例化的页面 ID
 * @string component_id 组件 ID，支持容器后代
 * @return userdata|nil 成功返回相应类型的组件句柄，失败返回 nil
 * @return table|nil 失败时返回错误表
 * @note 非当前页面返回 E_PAGE_INACTIVE，不存在的 ID 返回 E_NOT_FOUND。
 * @note 切换到其他页面后旧组件句柄失效，应重新 find。
 */
static int l_xml_find(lua_State *L)
{
    plcui_document_t *xml = xml_arg(L);
    if (xml->closed) return luat_plcui_binding_error(L, "E_OBJECT_CLOSED", "XML instance is closed");
    const char *page_id = luaL_checkstring(L, 2);
    const char *id = luaL_checkstring(L, 3);
    int page = luat_plcui_page_index(xml, page_id);
    if (page < 0) return luat_plcui_binding_error(L, "E_NOT_FOUND", "Page does not exist");
    if (page != xml->current_page) return luat_plcui_binding_error(L, "E_PAGE_INACTIVE", "Page is not instantiated");
    for (unsigned i = 0; i < xml->pages[page].count; ++i) {
        if (!strcmp(xml->pages[page].widgets[i].id, id)) {
            luat_plcui_binding_push_object(L, 1, (unsigned)page, i);
            return 1;
        }
    }
    return luat_plcui_binding_error(L, "E_NOT_FOUND", "Component does not exist");
}

/**
 * 切换 XML 界面中的当前页面。
 * @api xml:show(page_id)
 * @string page_id 目标页面 ID
 * @return bool|nil 成功执行或接受切页请求返回 true，失败返回 nil
 * @return table|nil 同步失败时返回错误表
 * @note 回调中调用会延后执行，新页面应在后续 UI 轮次访问。
 * @note 目标页资源检查和创建成功后才释放旧页面；延后执行失败会记录日志。
 */
static int l_xml_show(lua_State *L)
{
    plcui_document_t *xml = xml_arg(L);
    if (xml->closed) return luat_plcui_binding_error(L, "E_OBJECT_CLOSED", "XML instance is closed");
    const char *id = luaL_checkstring(L, 2);
    plcui_error_t error;
    if (!luat_plcui_show(xml, luat_plcui_page_index(xml, id), &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}

/**
 * 关闭 XML 界面，释放页面对象、资源描述和事件引用。
 * @api xml:close()
 * @return bool 返回 true，重复调用可安全结束
 * @note 关闭后 XML 实例及其组件句柄不再可用，回调中调用会延后执行。
 * @note 此接口不停止自动调度，退出应用还需调用 plcui.deinit。
 */
static int l_xml_close(lua_State *L)
{
    luat_plcui_close(xml_arg(L));
    return luat_plcui_binding_success(L);
}

/**
 * Lua 回收 XML 实例时释放其持有的界面资源。
 */
static int l_xml_gc(lua_State *L)
{
    luat_plcui_close(xml_arg(L));
    return 0;
}

/**
 * 注册 XML 实例的 find、show、close 和 GC 方法。
 */
void luat_plcui_register_xml_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"find", l_xml_find},
        {"show", l_xml_show},
        {"close", l_xml_close},
        {"__gc", l_xml_gc},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_XML_MT);
    luaL_setfuncs(L, methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}
