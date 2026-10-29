/*
@module  airui.map
@summary AIRUI 离线 XYZ 瓦片地图组件
@version 0.1.0
@date    2026.10.28
@tag     LUAT_USE_AIRUI, LUAT_USE_AIRUI_MAP
*/

#include "luat_base.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_airui_binding.h"
#include "../inc/luat_airui_map.h"
#include <limits.h>
#include <math.h>
#include <stdint.h>

#ifdef LUAT_USE_AIRUI_MAP

static lv_obj_t *map_check(lua_State *L)
{
    return airui_check_component(L, 1, AIRUI_MAP_MT);
}

static int map_check_result(lua_State *L, int result, const char *operation)
{
    if (result != AIRUI_OK) {
        return luaL_error(L, "map:%s failed (%d)", operation, result);
    }
    return 0;
}

static double map_check_number(lua_State *L, int index)
{
    double value = (double)luaL_checknumber(L, index);
    luaL_argcheck(L, isfinite(value), index, "finite number expected");
    return value;
}

static int32_t map_check_int32(lua_State *L, int index)
{
    lua_Integer value = luaL_checkinteger(L, index);
    luaL_argcheck(L, value >= INT32_MIN && value <= INT32_MAX, index, "32-bit integer expected");
    return (int32_t)value;
}

static bool map_check_boolean(lua_State *L, int index)
{
    luaL_checktype(L, index, LUA_TBOOLEAN);
    return lua_toboolean(L, index) != 0;
}

static double map_number_field(lua_State *L, int index, const char *name, double fallback, bool required)
{
    double value;
    lua_getfield(L, index, name);
    if (lua_isnil(L, -1) && !required) {
        lua_pop(L, 1);
        return fallback;
    }
    if (!lua_isnumber(L, -1)) {
        luaL_error(L, "map position.%s must be a number", name);
    }
    value = (double)lua_tonumber(L, -1);
    if (!isfinite(value)) {
        luaL_error(L, "map position.%s must be finite", name);
    }
    lua_pop(L, 1);
    return value;
}

/**
 * 创建地图；经纬度单位为十进制度，所有方法均使用经度、纬度顺序。
 * @api airui.map(config)
 * @table config 配置表
 * @int config.x 控件 X 坐标，默认 0
 * @int config.y 控件 Y 坐标，默认 0
 * @int config.w 控件宽度，受 max_tiles 容量限制
 * @int config.h 控件高度，受 max_tiles 容量限制
 * @userdata config.parent 父组件，可选
 * @table config.center 中心点 {lon=经度, lat=纬度}
 * @int config.zoom 整数缩放级别，0-22
 * @int config.min_zoom 最小缩放级别，默认 0
 * @int config.max_zoom 最大缩放级别，默认 22
 * @string config.input_crs 输入坐标系，wgs84 或 gcj02，默认 wgs84
 * @table config.source 文件瓦片数据源；type="file"，scheme="xyz"
 * @string config.source.root 瓦片根目录，默认 /sd/tiles
 * @string config.source.format 瓦片扩展名，jpg、jpeg 或 png，默认 jpg
 * @string config.source.crs 瓦片坐标系，wgs84 或 gcj02，默认 wgs84
 * @string config.source.path_template 可选绝对路径模板，必须包含 {z}、{x}、{y}
 * @boolean config.follow 是否跟随有效定位点，默认 true
 * @boolean config.draggable 是否允许触摸拖动，默认 true
 * @int config.prefetch 预加载外圈数，0 或 1，默认 0
 * @int config.cache_bytes 解码像素内存预算，默认 8 MiB，不含临时缓冲、控件和显示缓冲
 * @int config.max_tiles 瓦片槽位上限，默认 64，最大 128
 * @function config.on_click 点击回调 (self, event)
 * @function config.on_change 视口变化回调 (self, event)
 * @function config.on_ready 当前目标瓦片（含预取）处理完毕回调 (self, event)，缺图仍需查看统计
 * @function config.on_tile_error 瓦片缺失或加载失败回调 (self, event)
 * @return userdata Map 对象；无效参数或资源不足时抛出错误
 * @usage
 * local map = airui.map({
 *     x=0, y=0, w=800, h=480, zoom=15, min_zoom=14, max_zoom=17,
 *     center={lon=114.314, lat=34.797}, input_crs="wgs84",
 *     source={crs="gcj02", path_template="/luadb/tile_{z}_{x}_{y}.png"}
 * })
 * -- 真机挂载 SD 卡后可使用 source={root="/sd/tiles", crs="gcj02"}
 */
int airui_map_create(lua_State *L)
{
    airui_ctx_t *ctx = NULL;
    lv_obj_t *obj;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    if (ctx == NULL) {
        return luaL_error(L, "airui not initialized, call airui.init() first");
    }
    luaL_checktype(L, 1, LUA_TTABLE);
    obj = airui_map_create_from_config(L, 1);
    if (obj == NULL) {
        return luaL_error(L, "failed to create map (invalid config or insufficient memory)");
    }
    airui_push_component_userdata(L, obj, AIRUI_MAP_MT);
    return 1;
}

/**
 * 设置地理中心；不改变控件在父容器内的位置。
 * @api map:set_center(lon, lat)
 * @number lon 经度，单位度
 * @number lat 纬度，单位度；投影限制到 Mercator 可显示范围
 */
static int l_map_set_center(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    double lon = map_check_number(L, 2);
    double lat = map_check_number(L, 3);
    return map_check_result(L, airui_map_set_center(obj, lon, lat), "set_center");
}

/**
 * @api map:get_center()
 * @return number 经度，使用 input_crs
 * @return number 纬度，使用 input_crs
 */
static int l_map_get_center(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    double lon = 0.0;
    double lat = 0.0;
    if (airui_map_get_center(obj, &lon, &lat) != AIRUI_OK) {
        return luaL_error(L, "map:get_center failed");
    }
    lua_pushnumber(L, (lua_Number)lon);
    lua_pushnumber(L, (lua_Number)lat);
    return 2;
}

/**
 * @api map:set_zoom(zoom)
 * @int zoom 地图整数级别，必须在组件配置的 min_zoom 和 max_zoom 内
 */
static int l_map_set_zoom(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    lua_Integer zoom = luaL_checkinteger(L, 2);
    luaL_argcheck(L, zoom >= 0 && zoom <= 22, 2, "zoom must be between 0 and 22");
    return map_check_result(L, airui_map_set_zoom(obj, (int)zoom), "set_zoom");
}

/**
 * @api map:get_zoom()
 * @return int 当前缩放级别
 */
static int l_map_get_zoom(lua_State *L)
{
    int zoom = airui_map_get_zoom(map_check(L));
    if (zoom < 0) {
        return luaL_error(L, "map:get_zoom failed (%d)", zoom);
    }
    lua_pushinteger(L, zoom);
    return 1;
}

/**
 * 更新定位点，坐标使用 input_crs；GPS/NMEA 解析由业务层完成。
 * @api map:set_position(position)
 * @table position {lon=经度, lat=纬度, heading=方向角, valid=true}
 * @number position.heading 默认 0，北为 0 度，顺时针增大；仅旋转箭头
 * @boolean position.valid 默认 true；false 时隐藏定位点，允许省略坐标
 */
static int l_map_set_position(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    bool valid = true;
    double lon;
    double lat;
    double heading;
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_getfield(L, 2, "valid");
    if (!lua_isnil(L, -1)) {
        luaL_checktype(L, -1, LUA_TBOOLEAN);
        valid = lua_toboolean(L, -1) != 0;
    }
    lua_pop(L, 1);
    lon = map_number_field(L, 2, "lon", 0.0, valid);
    lat = map_number_field(L, 2, "lat", 0.0, valid);
    heading = map_number_field(L, 2, "heading", 0.0, false);
    return map_check_result(L, airui_map_set_position(obj, lon, lat, heading, valid), "set_position");
}

/**
 * @api map:set_follow(follow)
 * @boolean follow true 时将中心移动到有效定位点；手动拖动或 pan 会退出跟随
 */
static int l_map_set_follow(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    bool follow = map_check_boolean(L, 2);
    return map_check_result(L, airui_map_set_follow(obj, follow), "set_follow");
}

/**
 * @api map:get_follow()
 * @return boolean 是否跟随定位点
 */
static int l_map_get_follow(lua_State *L)
{
    lua_pushboolean(L, airui_map_get_follow(map_check(L)));
    return 1;
}

/**
 * @api map:set_draggable(draggable)
 * @boolean draggable 是否允许触摸拖动
 */
static int l_map_set_draggable(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    bool draggable = map_check_boolean(L, 2);
    return map_check_result(L, airui_map_set_draggable(obj, draggable), "set_draggable");
}

/**
 * @api map:set_size(w, h)
 * @int w 控件宽度；所需瓦片数量不能超过 max_tiles
 * @int h 控件高度
 */
static int l_map_set_size(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    lua_Integer w = luaL_checkinteger(L, 2);
    lua_Integer h = luaL_checkinteger(L, 3);
    luaL_argcheck(L, w >= 1 && w <= 4096, 2, "width must be between 1 and 4096");
    luaL_argcheck(L, h >= 1 && h <= 4096, 3, "height must be between 1 and 4096");
    return map_check_result(L, airui_map_set_size(obj, (int)w, (int)h), "set_size");
}

/**
 * 平移地图内容，不移动控件；正 dx 向右、正 dy 向下。
 * @api map:pan(dx, dy)
 * @number dx 水平像素偏移
 * @number dy 垂直像素偏移
 */
static int l_map_pan(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    double dx = map_check_number(L, 2);
    double dy = map_check_number(L, 3);
    return map_check_result(L, airui_map_pan(obj, dx, dy), "pan");
}

/**
 * 经纬度转换为地图控件内的局部像素坐标。
 * @api map:geo_to_screen(lon, lat)
 * @return number 局部 X；可能在视口外
 * @return number 局部 Y；可能在视口外
 */
static int l_map_geo_to_screen(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    double lon = map_check_number(L, 2);
    double lat = map_check_number(L, 3);
    double x = 0.0;
    double y = 0.0;
    if (airui_map_geo_to_screen(obj, lon, lat, &x, &y) != AIRUI_OK) {
        return luaL_error(L, "map:geo_to_screen failed");
    }
    lua_pushnumber(L, (lua_Number)x);
    lua_pushnumber(L, (lua_Number)y);
    return 2;
}

/**
 * 控件内的局部像素坐标转换为 input_crs 经纬度。
 * @api map:screen_to_geo(x, y)
 * @return number 经度
 * @return number 纬度
 */
static int l_map_screen_to_geo(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    double x = map_check_number(L, 2);
    double y = map_check_number(L, 3);
    double lon = 0.0;
    double lat = 0.0;
    if (airui_map_screen_to_geo(obj, x, y, &lon, &lat) != AIRUI_OK) {
        return luaL_error(L, "map:screen_to_geo failed");
    }
    lua_pushnumber(L, (lua_Number)lon);
    lua_pushnumber(L, (lua_Number)lat);
    return 2;
}

/**
 * 重新检查并加载当前瓦片，用于文件补齐或更新后刷新。
 * @api map:refresh()
 */
static int l_map_refresh(lua_State *L)
{
    return map_check_result(L, airui_map_refresh(map_check(L)), "refresh");
}

/**
 * 获取有界加载状态；ready/missing/failed/pending 包含预取，visible 仅计可见瓦片。
 * @api map:get_stats()
 * @return table generation、loaded_total、decode_failures、bytes_used、cache_bytes、capacity、visible、visible_ready、ready、pending、missing、failed
 */
static int l_map_get_stats(lua_State *L)
{
    airui_map_stats_t stats = {0};
    if (airui_map_get_stats(map_check(L), &stats) != AIRUI_OK) {
        return luaL_error(L, "map:get_stats failed");
    }
    lua_createtable(L, 0, 12);
#define MAP_PUSH_STAT(name) do { lua_pushinteger(L, (lua_Integer)stats.name); lua_setfield(L, -2, #name); } while (0)
    MAP_PUSH_STAT(generation);
    MAP_PUSH_STAT(loaded_total);
    MAP_PUSH_STAT(decode_failures);
    MAP_PUSH_STAT(bytes_used);
    MAP_PUSH_STAT(cache_bytes);
    MAP_PUSH_STAT(capacity);
    MAP_PUSH_STAT(visible);
    MAP_PUSH_STAT(visible_ready);
    MAP_PUSH_STAT(ready);
    MAP_PUSH_STAT(pending);
    MAP_PUSH_STAT(missing);
    MAP_PUSH_STAT(failed);
#undef MAP_PUSH_STAT
    return 1;
}

static int map_set_callback(lua_State *L, const char *name)
{
    lv_obj_t *obj = map_check(L);
    luaL_argcheck(L, lua_isfunction(L, 2) || lua_isnoneornil(L, 2), 2, "function or nil expected");
    return map_check_result(L, airui_map_set_callback(obj, L, 2, name), name);
}

/** @api map:set_on_click(callback)
 * @function callback 点击回调 (self, event)，nil 清除
 */
static int l_map_set_on_click(lua_State *L) { return map_set_callback(L, "on_click"); }

/** @api map:set_on_change(callback)
 * @function callback 视口变化回调 (self, event)，nil 清除
 */
static int l_map_set_on_change(lua_State *L) { return map_set_callback(L, "on_change"); }

/** @api map:set_on_ready(callback)
 * @function callback 当前目标瓦片（含预取）处理完毕回调 (self, event)，nil 清除
 */
static int l_map_set_on_ready(lua_State *L) { return map_set_callback(L, "on_ready"); }

/** @api map:set_on_tile_error(callback)
 * @function callback 瓦片错误回调 (self, event)，nil 清除
 */
static int l_map_set_on_tile_error(lua_State *L) { return map_set_callback(L, "on_tile_error"); }

/**
 * @api map:get_pos()
 * @return int 控件在父容器内的 X
 * @return int 控件在父容器内的 Y
 */
static int l_map_get_pos(lua_State *L)
{
    int32_t x = 0;
    int32_t y = 0;
    if (airui_component_get_pos(map_check(L), &x, &y) != AIRUI_OK) {
        return luaL_error(L, "map:get_pos failed");
    }
    lua_pushinteger(L, (lua_Integer)x);
    lua_pushinteger(L, (lua_Integer)y);
    return 2;
}

/**
 * 移动控件在父容器内的位置，不改变地理中心。
 * @api map:set_pos(x, y)
 */
static int l_map_set_pos(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    int32_t x = map_check_int32(L, 2);
    int32_t y = map_check_int32(L, 3);
    return map_check_result(L, airui_component_set_pos(obj, x, y), "set_pos");
}

/**
 * @api map:move(dx, dy)
 * @int dx 控件水平移动量
 * @int dy 控件垂直移动量
 */
static int l_map_move(lua_State *L)
{
    lv_obj_t *obj = map_check(L);
    int32_t dx = map_check_int32(L, 2);
    int32_t dy = map_check_int32(L, 3);
    int32_t x = 0;
    int32_t y = 0;
    int64_t next_x;
    int64_t next_y;
    if (airui_component_get_pos(obj, &x, &y) != AIRUI_OK) {
        return luaL_error(L, "map:move failed");
    }
    next_x = (int64_t)x + dx;
    next_y = (int64_t)y + dy;
    if (next_x < INT32_MIN || next_x > INT32_MAX || next_y < INT32_MIN || next_y > INT32_MAX) {
        return luaL_error(L, "map:move position out of range");
    }
    return map_check_result(L, airui_component_set_pos(obj, (int32_t)next_x, (int32_t)next_y), "move");
}

/**
 * 销毁地图并释放瓦片与加载任务；允许重复调用。
 * @api map:destroy()
 */
static int l_map_destroy(lua_State *L)
{
    return airui_component_destroy_userdata(L, 1, AIRUI_MAP_MT);
}

void airui_register_map_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_center", l_map_set_center},
        {"get_center", l_map_get_center},
        {"set_zoom", l_map_set_zoom},
        {"get_zoom", l_map_get_zoom},
        {"set_position", l_map_set_position},
        {"set_follow", l_map_set_follow},
        {"get_follow", l_map_get_follow},
        {"set_draggable", l_map_set_draggable},
        {"set_size", l_map_set_size},
        {"pan", l_map_pan},
        {"geo_to_screen", l_map_geo_to_screen},
        {"screen_to_geo", l_map_screen_to_geo},
        {"refresh", l_map_refresh},
        {"get_stats", l_map_get_stats},
        {"set_on_click", l_map_set_on_click},
        {"set_on_change", l_map_set_on_change},
        {"set_on_ready", l_map_set_on_ready},
        {"set_on_tile_error", l_map_set_on_tile_error},
        {"get_pos", l_map_get_pos},
        {"set_pos", l_map_set_pos},
        {"move", l_map_move},
        {"destroy", l_map_destroy},
        {"is_destroyed", airui_component_is_destroyed},
        {NULL, NULL}
    };
    luaL_newmetatable(L, AIRUI_MAP_MT);
    airui_component_set_metatable_gc(L);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    lua_pop(L, 1);
}

#else  /* LUAT_USE_AIRUI_MAP */

void airui_register_map_meta(lua_State *L)
{
    (void)L;
}

int airui_map_create(lua_State *L)
{
    lua_pushnil(L);
    return 1;
}

#endif /* LUAT_USE_AIRUI_MAP */
