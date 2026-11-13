/*
@module plcui
@summary 以 XML 组织界面的 PLCUI 初始化、加载、状态和调试接口
@version 1.0.2
@tag LUAT_USE_PLCUI
@note Lua 类型检查失败或参数不能转换为所需整数时，部分接口会抛出 Lua 参数异常，可用 pcall 捕获；nil,error 用于接口明确返回的校验或运行错误。
@note 错误表至少包含 code、message；按需附带 file、id、attribute、line、column，便于定位 XML 或资源问题。
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_debug.h"
#include "lvgl9/src/misc/cache/instance/lv_image_cache.h"
#include "lvgl9/src/misc/cache/instance/lv_image_header_cache.h"
#include "rotable2.h"
#include <string.h>

/**
 * 初始化 plcui，创建显示和输入设备，并启动自动刷新。
 * @api plcui.init(options)
 * @table options 初始化配置
 * @int options.width 逻辑屏幕宽度，必填，范围 1～2048 像素
 * @int options.height 逻辑屏幕高度，必填，范围 1～2048 像素
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 目标调度频率为 60Hz，应用不需要额外创建刷新循环定时器。
 * @note 重复初始化或 AirUI 已初始化时返回 E_DISPLAY_BUSY。
 * @note 真机须先完成 display 屏幕初始化；CCM4211 display/RGB 目前最大 1024×600，固定方向 0。
 * @note AIRUI 与 PLCUI 每次运行选择其中一套；初始化失败时不要继续加载 XML。
 * @usage
 * -- 真机先完成板级屏幕初始化，传入与 display 一致的尺寸。
 * plcui.init({width = 1024, height = 600})
 */
static int l_init(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Page preparation is in progress");
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
    /* 当前没有显示对象持有 LVGL；重建可能遗留的全局缓存和文件系统驱动。 */
    if (lv_is_initialized()) lv_deinit();
    lv_init();
    lv_image_cache_resize(PLCUI_IMAGE_CACHE_BYTES, true);
    lv_image_header_cache_resize(PLCUI_IMAGE_HEADER_CACHE_COUNT, true);
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
 * 手动执行一次界面刷新，处理输入、组件调度、绘制及排队事件。
 * @api plcui.refresh()
 * @return bool|nil 调用被接受时返回 true；prepare 期间返回 nil
 * @return table|nil 失败时返回错误表，prepare 期间为 E_BUSY
 * @note 正常运行由库自动调度，无需重复注册 Lua 刷新定时器。
 * @note 未初始化或正在刷新时不重复执行。
 * @note true 不表示必然发生物理刷屏，也不代表显示面板已经完成扫描。
 * @usage
 * plcui.refresh() -- 通常由自动刷新完成，仅按需手动调用。
 */
static int l_refresh(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Page preparation is in progress");
    luat_plcui_refresh();
    return luat_plcui_binding_success(L);
}

/**
 * 关闭当前 XML 界面，停止自动刷新并释放平台资源。
 * @api plcui.deinit()
 * @return bool|nil 调用被接受时返回 true，prepare 期间返回 nil
 * @return table|nil 失败时返回错误表，prepare 期间为 E_BUSY
 * @note 在业务回调中调用时延后到安全位置执行。
 * @note 未初始化时也可调用；会汇总并关闭调试统计，已取得的 XML/组件句柄随后失效。
 * @usage
 * plcui.deinit()
 */
static int l_deinit(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Page preparation is in progress");
    (void)L;
    luat_plcui_deinit();
    return luat_plcui_binding_success(L);
}

/**
 * 绑定已由业务初始化的触摸对象；nil 解除绑定。
 * @api plcui.device_bind_touch(tp_cfg)
 * @userdata tp_cfg tp.init 返回的 lightuserdata；须显式传 nil 才表示解绑
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回错误表，如 E_NOT_INITIALIZED、E_TYPE、E_PLATFORM 或 E_BUSY
 * @note 须先调用 plcui.init；PC 兼容此调用并使用 SDL 鼠标输入。
 * @note 本接口不负责配置触摸芯片引脚或总线；tp_cfg 须是业务已成功初始化的设备。
 * @usage
 * plcui.device_bind_touch(tp_cfg) -- tp_cfg 由板级 tp.init(...) 获得。
 * -- plcui.device_bind_touch(nil) -- 显式解绑。
 */
static int l_device_bind_touch(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document) return luat_plcui_binding_error(L, "E_BUSY", "Page preparation is in progress");
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
 * @return string 当前库版本字符串，例如 "1.0.2"
 * @note 无需先初始化；此值与 XML 根节点的 version="0.1" 分别管理。
 * @usage
 * log.info("plcui", "version", plcui.version())
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
 * @note 仅支持提供截图能力的平台；当前 display/RGB 真机返回 E_UNSUPPORTED。
 * @usage
 * -- PC 模拟器示例；输出目录须已存在。
 * plcui.snapshot("C:/temp/plcui.bmp")
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
 * @note image_cache_bytes/image_header_cache_entries 是共享 LVGL 实际缓存容量；尚未建立缓存时为 0。
 * @note image_hw_decodes/image_sw_decodes 为平台适配器成功解码次数，包含预检，不是帧数；未统计的平台返回 0。
 * @note platform 表示当前显示后端；未加载有效 XML 时没有 page 等活动文档字段。容量字段不是当前使用量。
 * @usage
 * local status = plcui.status()
 * log.info("plcui", status.version, status.platform, status.page, status.events_dropped)
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
    lua_pushinteger(L, luat_plcui_image_cache_capacity());
    lua_setfield(L, -2, "image_cache_bytes");
    lua_pushinteger(L, luat_plcui_image_header_cache_capacity());
    lua_setfield(L, -2, "image_header_cache_entries");
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

/**
 * 开关组件创建和已有组件更新的简版耗时统计，默认关闭。
 * @api plcui.debug([enabled])
 * @bool enabled 可选；true 开启，false 关闭并输出剩余汇总；不传参数查询状态
 * @return bool|nil 设置成功返回 true；无参数时返回当前开关状态；运行错误返回 nil
 * @return table|nil 失败时返回错误表，如 E_NOT_SUPPORTED 或 E_BUSY
 * @note 可在 init/load 前开启；deinit 自动输出剩余数据并关闭。
 * @note 每秒汇总各类组件 create/prepare/update 的次数、失败数、总/平均/最大微秒及最慢组件ID。
 * @note update 是现有对象方法的同步耗时（包含同值调用），不包含后续异步绘制或屏幕显示。
 * @note 参数类型异常和失效句柄不计入；有效句柄的方法返回 nil,error 时计入 failed。
 * @note 统计含九类组件及 set_*、move、focus、add_point、play/pause/stop、clear_crop；getter 不计时。
 * @note 各类操作按秒汇总；false 会输出剩余统计。统计槽最多 64 种组合，槽满时报告 dropped。
 * @usage
 * plcui.debug(true) -- 可放在 init/load 前。
 * -- 执行固定次数的切页、交互或数据更新，再比较 count/total_us/max_us。
 * plcui.debug(false)
 * local enabled = plcui.debug() -- 查询返回当前开关状态。
 */
static int l_debug(lua_State *L)
{
    if (lua_isnone(L, 1)) {
        lua_pushboolean(L, plcui_debug_enabled());
        return 1;
    }
    if (luat_plcui_runtime()->preparing_document)
        return luat_plcui_binding_error(L, "E_BUSY", "Cannot change debug settings during page preparation");
    luaL_checktype(L, 1, LUA_TBOOLEAN);
    bool enabled = lua_toboolean(L, 1) != 0;
    if (enabled && !PLCUI_PERF_ENABLE)
        return luat_plcui_binding_error(L, "E_NOT_SUPPORTED", "PLCUI timing support is not compiled");
    if (!enabled) plcui_perf_fail("debug_off");
    plcui_debug_set(enabled);
    return luat_plcui_binding_success(L);
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
    {"debug", ROREG_FUNC(l_debug)},
    {NULL, ROREG_INT(0)}
};

/**
 * 注册 XML 实例、组件元表和 plcui 模块全局接口。
 * @param L 接收模块表的 Lua 状态机。
 * @return 1，栈顶为模块表；由 Lua 模块加载器调用。
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
    luat_plcui_register_animimg_meta(L);
    luat_plcui_register_slider_meta(L);
    luat_newlib2(L, reg_plcui);
    return 1;
}
