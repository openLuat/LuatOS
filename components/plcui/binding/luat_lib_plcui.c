/*
@module plcui
@summary XML-first PLC UI module entry and global runtime interfaces
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "rotable2.h"
#include <string.h>

/**
 * 初始化 plcui，创建显示和输入设备，并启动自动刷新。
 * @api plcui.init(options)
 * @table options 初始化配置
 * @int options.width 逻辑屏幕宽度，必填，范围 1～2048 像素
 * @int options.height 逻辑屏幕高度，必填，范围 1～2048 像素
 * @note CCM4211 display/RGB 真机目前最大 1024×600，固定方向 0。
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 目标调度频率为 60Hz，应用不需要额外创建刷新循环定时器。
 * @note 重复初始化或 AirUI 已初始化时返回 E_DISPLAY_BUSY。
 */
static int l_init(lua_State *L)
{
    plcui_runtime_t *runtime = luat_plcui_runtime();
    if (runtime->initialized) return luat_plcui_binding_error(L, "E_DISPLAY_BUSY", "plcui is already initialized");
    luaL_checktype(L, 1, LUA_TTABLE);
    lua_getfield(L, 1, "width");
    lua_Integer width = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 1, "height");
    lua_Integer height = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    if (width <= 0 || width > 2048 || height <= 0 || height > 2048) return luat_plcui_binding_error(L, "E_SCHEMA", "Display size must be between 1 and 2048 pixels per dimension");
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    bool airui_active = !lua_isnil(L, -1);
    lua_pop(L, 1);
    if (airui_active) return luat_plcui_binding_error(L, "E_DISPLAY_BUSY", "Deinitialize AirUI before initializing plcui");
    if (lv_is_initialized() && lv_display_get_next(NULL)) {
        return luat_plcui_binding_error(L, "E_DISPLAY_BUSY", "Another LVGL display is still active");
    }
    /* A previous AirUI session can leave global LVGL caches and FS drivers.
       No display owner is active here, so rebuild that global state once. */
    if (lv_is_initialized()) lv_deinit();
    lv_init();
    if (plcui_platform_init((int)width, (int)height) != 0) {
        lv_deinit();
        return luat_plcui_binding_error(L, "E_PLATFORM", "Cannot initialize display; check size, RGB565, buffers and rotation");
    }
    int services = plcui_fs_init();
    if (!services) services = plcui_platform_image_init();
    if (services) {
        plcui_platform_deinit();
        plcui_platform_image_deinit();
        lv_deinit();
        return luat_plcui_binding_error(L, "E_PLATFORM", "Cannot initialize VFS/image services");
    }
    memset(runtime, 0, sizeof(*runtime));
    lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_MAINTHREAD);
    runtime->L = lua_tothread(L, -1);
    lua_pop(L, 1);
    runtime->initialized = true;
    runtime->width = (int)width;
    runtime->height = (int)height;
    runtime->idle_screen = lv_screen_active();
    lua_pushboolean(L, true);
    lua_setfield(L, LUA_REGISTRYINDEX, "plcui_active");
    if (!luat_plcui_start_refresh()) {
        luat_plcui_deinit();
        return luat_plcui_binding_error(L, "E_PLATFORM", "Cannot start the automatic refresh timer");
    }
    return luat_plcui_binding_success(L);
}

/**
 * 手动处理一次输入、LVGL 定时器和排队事件。
 * @api plcui.refresh()
 * @return bool 返回 true
 * @note 正常运行由库自动调度，无需重复注册 Lua 刷新定时器。
 * @note 未初始化或正在刷新时不重复执行。
 */
static int l_refresh(lua_State *L)
{
    luat_plcui_refresh();
    return luat_plcui_binding_success(L);
}

/**
 * 关闭当前 XML 界面，停止自动刷新并释放平台资源。
 * @api plcui.deinit()
 * @return bool 返回 true，重复调用可安全结束
 * @note 在业务回调中调用时延后到安全位置执行。
 */
static int l_deinit(lua_State *L)
{
    (void)L;
    luat_plcui_deinit();
    return luat_plcui_binding_success(L);
}

/**
 * 绑定已由业务初始化的触摸对象；nil 解除绑定。
 * @api plcui.device_bind_touch(tp_cfg)
 * @userdata tp_cfg tp.init 返回的 lightuserdata，nil 表示解绑
 * @return bool|nil 成功返回 true，失败返回 nil 和错误表
 * @note 须先调用 plcui.init；PC 兼容此调用并使用 SDL 鼠标输入。
 */
static int l_device_bind_touch(lua_State *L)
{
    if (!luat_plcui_runtime()->initialized) return luat_plcui_binding_error(L, "E_NOT_INITIALIZED", "Call plcui.init first");
    if (!lua_isnil(L, 1) && !lua_islightuserdata(L, 1)) {
        return luat_plcui_binding_error(L, "E_TYPE", "Expected the touch handle returned by tp.init, or nil");
    }
    struct luat_tp_config *config = lua_isnil(L, 1) ? NULL : lua_touserdata(L, 1);
    if (plcui_platform_bind_touch(config)) return luat_plcui_binding_error(L, "E_PLATFORM", "Touch device is not ready or incompatible");
    lua_pushvalue(L, 1);
    lua_setfield(L, LUA_REGISTRYINDEX, "plcui_touch");
    return luat_plcui_binding_success(L);
}

/**
 * 获取 plcui 库版本号。
 * @api plcui.version()
 * @return string 版本字符串，例如 "0.2.0"
 */
static int l_version(lua_State *L)
{
    lua_pushstring(L, PLCUI_VERSION);
    return 1;
}

/**
 * 保存当前 PC 模拟器画面为 BMP 图片。
 * @api plcui.snapshot(path)
 * @string path 主机文件系统输出路径，父目录需已存在
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 需要先初始化；path 是主机路径，不是 LuatOS VFS 路径。
 */
static int l_snapshot(lua_State *L)
{
    if (!luat_plcui_runtime()->initialized) return luat_plcui_binding_error(L, "E_NOT_INITIALIZED", "Call plcui.init first");
    const char *path = luaL_checkstring(L, 1);
    int result = plcui_platform_snapshot(path);
    if (result == PLCUI_PLATFORM_UNSUPPORTED) return luat_plcui_binding_error(L, "E_UNSUPPORTED", "Snapshots are not supported by this display backend");
    if (result != 0) return luat_plcui_binding_error(L, "E_RESOURCE", "Cannot save display snapshot to the host path");
    return luat_plcui_binding_success(L);
}

/**
 * 查询 plcui 运行状态。
 * @api plcui.status()
 * @return table 运行状态表
 * @note 基础字段：version、initialized、width、height、active、auto_refresh、refresh_hz、auto_refresh_count。
 * @note active 为 true 时还包含 page、component_count、resource_count、events_dropped、editing。
 * @note refresh_hz 是目标频率，auto_refresh_count 是自动调度次数，不代表实际绘制帧数。
 * @note platform 和 image_cache_bytes 分别表示平台和编译配置的缓存容量。
 * @note image_hw_decodes/image_sw_decodes 为平台适配器成功解码次数，包含预检，不是帧数；未统计的平台返回 0。
 */
static int l_status(lua_State *L)
{
    plcui_runtime_t *runtime = luat_plcui_runtime();
    plcui_document_t *xml = runtime->document;
    lua_createtable(L, 0, 10);
    lua_pushstring(L, PLCUI_VERSION);
    lua_setfield(L, -2, "version");
    lua_pushboolean(L, runtime->initialized);
    lua_setfield(L, -2, "initialized");
    lua_pushboolean(L, runtime->auto_refresh);
    lua_setfield(L, -2, "auto_refresh");
    lua_pushinteger(L, PLCUI_REFRESH_RATE_HZ);
    lua_setfield(L, -2, "refresh_hz");
    lua_pushinteger(L, runtime->auto_refresh_count);
    lua_setfield(L, -2, "auto_refresh_count");
    lua_pushinteger(L, runtime->width);
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, runtime->height);
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, LV_CACHE_DEF_SIZE);
    lua_setfield(L, -2, "image_cache_bytes");
    lua_pushstring(L, plcui_platform_name());
    lua_setfield(L, -2, "platform");
    lua_pushinteger(L, plcui_platform_image_hw_count());
    lua_setfield(L, -2, "image_hw_decodes");
    lua_pushinteger(L, plcui_platform_image_sw_count());
    lua_setfield(L, -2, "image_sw_decodes");
    lua_pushboolean(L, xml && !xml->closed);
    lua_setfield(L, -2, "active");
    if (xml && !xml->closed) {
        lua_pushstring(L, xml->pages[xml->current_page].id);
        lua_setfield(L, -2, "page");
        lua_pushinteger(L, xml->widget_count);
        lua_setfield(L, -2, "component_count");
        lua_pushinteger(L, xml->resource_count);
        lua_setfield(L, -2, "resource_count");
        lua_pushinteger(L, xml->events_dropped);
        lua_setfield(L, -2, "events_dropped");
        lua_pushboolean(L, xml->editing != NULL);
        lua_setfield(L, -2, "editing");
    }
    return 1;
}

static const rotable_Reg_t reg_plcui[] = {
    {"init", ROREG_FUNC(l_init)},
    {"load", ROREG_FUNC(luat_plcui_xml_load)},
    {"refresh", ROREG_FUNC(l_refresh)},
    {"deinit", ROREG_FUNC(l_deinit)},
    {"device_bind_touch", ROREG_FUNC(l_device_bind_touch)},
    {"version", ROREG_FUNC(l_version)},
    {"snapshot", ROREG_FUNC(l_snapshot)},
    {"status", ROREG_FUNC(l_status)},
    {NULL, ROREG_INT(0)}
};

/**
 * 注册 XML 实例、组件元表和 plcui 模块全局接口。
 */
LUAMOD_API int luaopen_plcui(lua_State *L)
{
    luat_plcui_register_xml_meta(L);
    luat_plcui_register_image_meta(L);
    luat_plcui_register_label_meta(L);
    luat_plcui_register_textarea_meta(L);
    luat_plcui_register_keyboard_meta(L);
    luat_plcui_register_container_meta(L);
    luat_plcui_register_table_meta(L);
    luat_plcui_register_chart_meta(L);
    luat_newlib2(L, reg_plcui);
    return 1;
}
