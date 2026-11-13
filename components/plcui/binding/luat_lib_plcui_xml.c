/*
@module plcui.xml
@summary XML 界面加载、组件查找、页面切换与资源关闭
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <string.h>

/**
 * 检查 Lua 栈第 1 项并取得 XML 实例。
 * @param L 调用状态机，第 1 项须为 PLCUI XML userdata。
 * @return XML 实例指针；元表或大小不匹配时抛出 Lua 参数异常。
 * @note 只检查句柄类型，不替代各接口对 closed 等运行状态的检查。
 */
static plcui_document_t *xml_arg(lua_State *L)
{
    plcui_document_t *xml = luaL_checkudata(L, 1, PLCUI_XML_MT);
    if (lua_rawlen(L, 1) != sizeof(*xml)) luaL_argerror(L, 1, "invalid XML instance");
    return xml;
}

/**
 * 加载 XML 和资源，创建并显示入口页面。
 * @api plcui.load(path[, options])
 * @string path XML 的绝对 VFS 路径，如 /luadb/main.xml 或 /sd/panel/main.xml
 * @table options 可选加载配置；省略时使用空 handlers 且无 prepare 回调
 * @table options.handlers 可选命名函数表；XML 声明的每个事件名称都必须有对应函数
 * @function options.prepare 可选同步函数 prepare(xml, page_id)，每次目标页离屏创建后、图片准备前调用
 * @return userdata|nil 成功返回 XML 界面实例 xml，失败返回 nil
 * @return table|nil 失败时返回含 code、message 的错误表，XML 错误还可能包含 file/id/attribute/line/column
 * @note 需要先调用 plcui.init；图片资源路径相对于 XML 所在目录。
 * @note 只准备首帧可见图像槽的当前资源；静态页图片保留像素引用，动画只保留有限活动帧，后续帧按播放需要准备。
 * @note 同一 XML 实例运行期间图片文件视为固定；替换 SD 或文件系统资源后须重新 load 才更新。
 * @note prepare 只能同步访问传入文档的目标页，不能 yield/load/show/close/deinit 或启动输入；临时句柄提交后失效，应重新 find。
 * @note prepare 内应抛出 Lua 异常报告初始化失败；库返回 E_PREPARE 并保留旧页。回调应可重复执行。
 * @note 首帧资源准备成功后替换旧界面，失败保留旧界面；隐藏与备用状态在显示时准备。
 * @note 业务事件回调中不能直接加载新 XML，否则返回 E_BUSY。
 * @note 成功后关闭此前活动 XML 及其组件句柄；失败时旧界面及旧句柄继续可用。handlers 在加载时复制，事后修改原表不会重新绑定事件。
 * @note 事件回调接收 table，公共字段为 type/page/id；textarea 另含 text，Slider 含 value/start_value，动画事件含 frame/completed_loops 等。
 * @usage
 * local handlers = {start_pump = function(e) log.info("ui", e.type, e.page, e.id) end}
 * -- handlers 的键须与实际 XML 中的事件名称一致。
 * local xml = plcui.load("/luadb/main.xml", {handlers = handlers})
 */
int luat_plcui_xml_load(lua_State *L)
{
    plcui_runtime_t *runtime = luat_plcui_runtime();
    if (runtime->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Cannot load XML during page preparation");
    if (!runtime->initialized) return luat_plcui_binding_error(L, "E_NOT_INITIALIZED", "Call plcui.init first");
    if (runtime->refreshing || (runtime->document && (runtime->document->dispatching || runtime->document->switching))) return luat_plcui_binding_error(L, "E_BUSY", "Load a new document outside an event callback");
    const char *path = luaL_checkstring(L, 1);
    plcui_document_t *xml = lua_newuserdata(L, sizeof(*xml));
    memset(xml, 0, sizeof(*xml));
    xml->L = runtime->L;
    xml->self_ref = LUA_NOREF;
    xml->handlers_ref = LUA_NOREF;
    xml->prepare_ref = LUA_NOREF;
    xml->preparing_page = -1;
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
    /* 保存函数表副本，避免调用方后续修改原表使已校验的事件绑定失效。 */
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
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "prepare");
        if (!lua_isnil(L, -1) && !lua_isfunction(L, -1)) {
            lua_pop(L, 1); luat_plcui_close(xml);
            return luat_plcui_binding_error(L, "E_HANDLER", "options.prepare must be a function");
        }
        if (lua_isfunction(L, -1)) xml->prepare_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        else lua_pop(L, 1);
    }
    plcui_error_t error;
    if (!luat_plcui_parse(xml, path, &error) || !luat_plcui_register_images(xml, &error)) {
        luat_plcui_close(xml);
        return luat_plcui_push_error(L, &error);
    }
    lua_pushvalue(L, xml_stack_index);
    xml->self_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    if (!luat_plcui_show(xml, luat_plcui_page_index(xml, xml->entry), &error)) {
        luat_plcui_close(xml);
        return luat_plcui_push_error(L, &error);
    }
    plcui_document_t *old = runtime->document;
    if (old) {
        /* 新屏幕已经可用；关闭旧文档时不应将新画面替换为空闲屏幕。 */
        runtime->document = NULL;
        luat_plcui_close(old);
    }
    runtime->document = xml;
    lua_pushvalue(L, xml_stack_index);
    return 1;
}

/**
 * 按页面 ID 和组件 ID 查找组件。
 * @api xml:find(page_id, component_id)
 * @string page_id 当前已实例化的页面 ID；prepare 回调中为本次目标页面 ID
 * @string component_id XML 中声明的组件 ID，支持任意层容器后代，不使用路径表达式
 * @return userdata|nil 成功返回相应类型的组件句柄，失败返回 nil
 * @return table|nil 失败时返回错误表
 * @note 非当前页面返回 E_PAGE_INACTIVE，不存在的 ID 返回 E_NOT_FOUND。
 * @note 切换到其他页面后旧组件句柄失效，应重新 find。
 * @note 九种公开组件返回各自类型的句柄；资源、动画 frame 和键盘内部候选对象不能单独 find。
 * @usage
 * local image = xml:find("main", "logo")
 * image:set_hidden(false)
 */
static int l_xml_find(lua_State *L)
{
    plcui_document_t *xml = xml_arg(L);
    if (luat_plcui_runtime()->preparing_document && xml != luat_plcui_runtime()->preparing_document)
        return luat_plcui_binding_error(L, "E_BUSY", "Only the prepared document may be accessed during preparation");
    if (xml->closed) return luat_plcui_binding_error(L, "E_OBJECT_CLOSED", "XML instance is closed");
    const char *page_id = luaL_checkstring(L, 2);
    const char *id = luaL_checkstring(L, 3);
    int page = luat_plcui_page_index(xml, page_id);
    if (page < 0) return luat_plcui_binding_error(L, "E_NOT_FOUND", "Page does not exist");
    if (page != (xml->preparing_page >= 0 ? xml->preparing_page : xml->current_page))
        return luat_plcui_binding_error(L, "E_PAGE_INACTIVE", "Page is not instantiated");
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
 * @note 同一当前页的重复 show 不重建页面；切到其他页再返回会重建原生对象，需重新 find 组件。
 * @note 组件运行时保存的文本、位置等描述可随重建保留；重新 load 从 XML 恢复初始描述，prepare 可覆盖每次初值。
 * @note prepare 期间禁止切页，返回 E_BUSY；XML 已关闭时返回 E_OBJECT_CLOSED。
 * @usage
 * -- 普通任务中可在同步 show 成功后查找目标页；事件回调中须等延后切页完成。
 * xml:show("settings")
 * local input = xml:find("settings", "setpoint")
 */
static int l_xml_show(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Cannot switch pages during page preparation");
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
 * @return bool|nil 关闭请求被接受时返回 true，prepare 期间返回 nil
 * @return table|nil 失败时返回错误表，prepare 期间为 E_BUSY
 * @note 关闭后 XML 实例及其组件句柄不再可用，回调中调用会延后执行。
 * @note 此接口不停止自动调度，退出应用还需调用 plcui.deinit。
 * @usage
 * xml:close()
 * plcui.deinit() -- 不再使用界面时同时释放平台资源。
 */
static int l_xml_close(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Cannot close XML during page preparation");
    luat_plcui_close(xml_arg(L));
    return luat_plcui_binding_success(L);
}

/**
 * Lua 回收 XML 实例时释放其持有的界面资源。
 * @param L 第 1 项为待回收 XML 实例的 Lua 状态机。
 * @return 0，不向 Lua 返回值；由 __gc 元方法调用。
 */
static int l_xml_gc(lua_State *L)
{
    luat_plcui_close(xml_arg(L));
    return 0;
}

/**
 * 注册 XML 实例的 find、show、close 和 GC 方法。
 * @param L 接收 XML 元表的 Lua 状态机；注册完成后恢复原栈高度。
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
