#include "luat_base.h"

#if defined(LUAT_USE_TINY_EPD)

#include "luat_spi.h"
#include "tiny_epd.h"
#include "tiny_epd_port_luatos.h"

#include <limits.h>
#include <stdint.h>
#include <string.h>

#define LUAT_TINY_EPD_DEVICE_META "epd.dev"
#define LUAT_TINY_EPD_SPI_DEVICE_META "SPI*"
#define LUAT_TINY_EPD_MODEL_1IN54 1
#define LUAT_TINY_EPD_MODEL_1IN54_V2 2
#define LUAT_TINY_EPD_MODEL_1IN54_V3 3
#define LUAT_TINY_EPD_MODEL_1IN54_SSD1607 4

typedef struct {
    tiny_epd_t *epd;
    tiny_epd_port_luatos_t port_context;
    int spi_ref;
} luat_tiny_epd_device_t;

static const char *luat_tiny_epd_error_string(int ret)
{
    switch (ret) {
    case TINY_EPD_OK:
        return "ok";
    case TINY_EPD_ERR_PARAM:
        return "invalid parameter";
    case TINY_EPD_ERR_NO_MEM:
        return "out of memory";
    case TINY_EPD_ERR_IO:
        return "SPI or GPIO I/O failed";
    case TINY_EPD_ERR_BUSY_TIMEOUT:
        return "panel busy timeout";
    case TINY_EPD_ERR_UNSUPPORTED_MODE:
        return "refresh or sleep mode is not supported by this panel";
    case TINY_EPD_ERR_BAD_STATE:
        return "panel is not initialized or is sleeping";
    default:
        return "unknown epd error";
    }
}

static int luat_tiny_epd_push_result(lua_State *L, int ret)
{
    if (ret == TINY_EPD_OK) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushboolean(L, 0);
    lua_pushstring(L, luat_tiny_epd_error_string(ret));
    return 2;
}

static int luat_tiny_epd_push_open_error(lua_State *L, const char *message)
{
    lua_pushnil(L);
    lua_pushstring(L, message);
    return 2;
}

static luat_tiny_epd_device_t *luat_tiny_epd_check_device(lua_State *L)
{
    luat_tiny_epd_device_t *device =
        (luat_tiny_epd_device_t *)luaL_checkudata(L, 1, LUAT_TINY_EPD_DEVICE_META);

    if (device->epd == NULL) {
        luaL_error(L, "epd device is closed");
    }
    return device;
}

static int luat_tiny_epd_get_model(lua_State *L)
{
    size_t name_len;
    const char *name;

    if (lua_type(L, 1) == LUA_TNUMBER) {
        lua_Integer model = luaL_checkinteger(L, 1);
        return (model == LUAT_TINY_EPD_MODEL_1IN54 ||
                model == LUAT_TINY_EPD_MODEL_1IN54_V2 ||
                model == LUAT_TINY_EPD_MODEL_1IN54_V3 ||
                model == LUAT_TINY_EPD_MODEL_1IN54_SSD1607) ? (int)model : 0;
    }

    name = luaL_checklstring(L, 1, &name_len);
    if ((name_len == 5 && memcmp(name, "1in54", 5) == 0) ||
        (name_len == 18 && memcmp(name, "waveshare_1in54_bw", 18) == 0)) {
        return LUAT_TINY_EPD_MODEL_1IN54;
    }
    if ((name_len == 8 && memcmp(name, "1in54_v2", 8) == 0) ||
        (name_len == 18 && memcmp(name, "waveshare_1in54_v2", 18) == 0) ||
        (name_len == 21 && memcmp(name, "waveshare_1in54_v2_bw", 21) == 0)) {
        return LUAT_TINY_EPD_MODEL_1IN54_V2;
    }
    if ((name_len == 8 && memcmp(name, "1in54_v3", 8) == 0) ||
        (name_len == 18 && memcmp(name, "waveshare_1in54_v3", 18) == 0) ||
        (name_len == 21 && memcmp(name, "waveshare_1in54_v3_bw", 21) == 0)) {
        return LUAT_TINY_EPD_MODEL_1IN54_V3;
    }
    if ((name_len == 13 && memcmp(name, "ssd1607_1in54", 13) == 0) ||
        (name_len == 15 && memcmp(name, "ssd1607_200x200", 15) == 0) ||
        (name_len == 21 && memcmp(name, "ssd1607_1in54_200x200", 21) == 0)) {
        return LUAT_TINY_EPD_MODEL_1IN54_SSD1607;
    }
    return 0;
}

static int luat_tiny_epd_get_int_field(lua_State *L,
                                       int table_index,
                                       const char *field,
                                       int default_value,
                                       int *value)
{
    lua_Integer lua_value;

    lua_getfield(L, table_index, field);
    if (lua_isnil(L, -1)) {
        *value = default_value;
        lua_pop(L, 1);
        return 0;
    }
    if (!lua_isnumber(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }
    lua_value = luaL_checkinteger(L, -1);
    if (lua_value < INT_MIN || lua_value > INT_MAX) {
        lua_pop(L, 1);
        return -1;
    }
    *value = (int)lua_value;
    lua_pop(L, 1);
    return 0;
}

/*
@api epd.open(model, opts[, spi_device])
@number|string model 当前支持 epd.MODEL_1IN54 或 "1in54"
@table opts {port = spi_id|"device", pin_dc, pin_rst, pin_busy[, busy_pull, busy_poll_ms]}
@userdata spi_device 可选，port="device" 时传入 spi.deviceSetup() 返回的对象
@return userdata 成功时返回独立的 tiny_epd 设备对象
@return nil,string 失败时返回 nil 和错误信息
@usage
local spi_epd = spi.deviceSetup(0, 8, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
local panel, err = epd.open(epd.MODEL_1IN54,
    {port = "device", pin_dc = 10, pin_rst = 1, pin_busy = 22}, spi_epd)
assert(panel, err)
assert(panel:init())
*/
static int l_tiny_epd_open(lua_State *L)
{
    const tiny_epd_driver_t *driver;
    tiny_epd_port_t port;
    tiny_epd_port_luatos_config_t config;
    luat_tiny_epd_device_t *device;
    const char *port_name;
    size_t port_name_len;
    int model;
    int ret;
    int use_spi_device = 0;
    int busy_poll_ms;

    model = luat_tiny_epd_get_model(L);
    if (model != LUAT_TINY_EPD_MODEL_1IN54 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_V2 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_V3 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_SSD1607) {
        return luat_tiny_epd_push_open_error(L, "unsupported epd model");
    }
    luaL_checktype(L, 2, LUA_TTABLE);

    device = (luat_tiny_epd_device_t *)lua_newuserdata(L, sizeof(*device));
    memset(device, 0, sizeof(*device));
    device->spi_ref = LUA_NOREF;

    memset(&config, 0, sizeof(config));
    config.spi_id = -1;
    config.pin_dc = -1;
    config.pin_rst = -1;
    config.pin_busy = -1;

    lua_getfield(L, 2, "port");
    if (lua_isnumber(L, -1)) {
        config.spi_id = (int)luaL_checkinteger(L, -1);
    }
    else if (lua_isstring(L, -1)) {
        port_name = luaL_checklstring(L, -1, &port_name_len);
        if (port_name_len == 6 && memcmp(port_name, "device", 6) == 0) {
            use_spi_device = 1;
        }
        else {
            lua_pop(L, 1);
            return luat_tiny_epd_push_open_error(L, "opts.port must be an SPI id or \"device\"");
        }
    }
    else {
        lua_pop(L, 1);
        return luat_tiny_epd_push_open_error(L, "opts.port is required");
    }
    lua_pop(L, 1);

    if (luat_tiny_epd_get_int_field(L, 2, "pin_dc", -1, &config.pin_dc) != 0 ||
        luat_tiny_epd_get_int_field(L, 2, "pin_rst", -1, &config.pin_rst) != 0 ||
        luat_tiny_epd_get_int_field(L, 2, "pin_busy", -1, &config.pin_busy) != 0 ||
        luat_tiny_epd_get_int_field(L, 2, "busy_pull", 0, &config.busy_pull) != 0 ||
        luat_tiny_epd_get_int_field(L, 2, "busy_poll_ms", 0, &busy_poll_ms) != 0 ||
        busy_poll_ms < 0) {
        return luat_tiny_epd_push_open_error(L, "epd GPIO and polling options must be integers");
    }
    config.busy_poll_ms = (uint32_t)busy_poll_ms;

    if (use_spi_device) {
        config.spi_device = (luat_spi_device_t *)luaL_testudata(L, 3, LUAT_TINY_EPD_SPI_DEVICE_META);
        if (config.spi_device == NULL) {
            return luat_tiny_epd_push_open_error(L, "opts.port=\"device\" requires a spi.deviceSetup object");
        }
        /* Keep the Lua SPI userdata alive for the whole panel lifetime. */
        lua_pushvalue(L, 3);
        device->spi_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    else if (!lua_isnoneornil(L, 3)) {
        return luat_tiny_epd_push_open_error(L, "spi_device is only valid when opts.port=\"device\"");
    }

    ret = tiny_epd_port_luatos_init(&port, &device->port_context, &config);
    if (ret != TINY_EPD_OK) {
        if (device->spi_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, device->spi_ref);
            device->spi_ref = LUA_NOREF;
        }
        return luat_tiny_epd_push_open_error(L, luat_tiny_epd_error_string(ret));
    }

    if (model == LUAT_TINY_EPD_MODEL_1IN54_V2) {
        driver = tiny_epd_driver_1in54_v2();
    }
    else if (model == LUAT_TINY_EPD_MODEL_1IN54_V3) {
        driver = tiny_epd_driver_1in54_v3();
    }
    else if (model == LUAT_TINY_EPD_MODEL_1IN54_SSD1607) {
        driver = tiny_epd_driver_1in54_ssd1607();
    }
    else {
        driver = tiny_epd_driver_1in54();
    }
    ret = tiny_epd_create(&device->epd, driver, &port);
    if (ret != TINY_EPD_OK) {
        if (device->spi_ref != LUA_NOREF) {
            luaL_unref(L, LUA_REGISTRYINDEX, device->spi_ref);
            device->spi_ref = LUA_NOREF;
        }
        return luat_tiny_epd_push_open_error(L, luat_tiny_epd_error_string(ret));
    }

    luaL_setmetatable(L, LUAT_TINY_EPD_DEVICE_META);
    return 1;
}

/*
@api panel:init()
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_init(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    return luat_tiny_epd_push_result(L, tiny_epd_init(device->epd));
}

/*
@api panel:clear(color)
@number color epd.WHITE (默认) 或 epd.BLACK
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_clear(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    int color = (int)luaL_optinteger(L, 2, TINY_EPD_COLOR_WHITE);

    if (color != TINY_EPD_COLOR_BLACK && color != TINY_EPD_COLOR_WHITE) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L, tiny_epd_clear(device->epd, (uint8_t)color));
}

/*
@api panel:pixel(x, y[, color])
@number x X 坐标
@number y Y 坐标
@number color epd.BLACK (默认) 或 epd.WHITE
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_pixel(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    int color = (int)luaL_optinteger(L, 4, TINY_EPD_COLOR_BLACK);

    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        (color != TINY_EPD_COLOR_BLACK && color != TINY_EPD_COLOR_WHITE)) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_pixel(device->epd,
                                                         (int16_t)x,
                                                         (int16_t)y,
                                                         (uint8_t)color));
}

static int luat_tiny_epd_refresh_mode(lua_State *L, int index, tiny_epd_refresh_mode_t *mode)
{
    size_t name_len;
    const char *name;
    lua_Integer numeric_mode;

    if (lua_isnoneornil(L, index)) {
        *mode = TINY_EPD_REFRESH_FULL;
        return 0;
    }
    if (lua_isnumber(L, index)) {
        numeric_mode = luaL_checkinteger(L, index);
        if (numeric_mode >= TINY_EPD_REFRESH_AUTO && numeric_mode <= TINY_EPD_REFRESH_PARTIAL_RECT) {
            *mode = (tiny_epd_refresh_mode_t)numeric_mode;
            return 0;
        }
        return -1;
    }
    name = luaL_checklstring(L, index, &name_len);
    if (name_len == 4 && memcmp(name, "full", 4) == 0) {
        *mode = TINY_EPD_REFRESH_FULL;
    }
    else if (name_len == 4 && memcmp(name, "fast", 4) == 0) {
        *mode = TINY_EPD_REFRESH_FAST;
    }
    else if (name_len == 7 && memcmp(name, "partial", 7) == 0) {
        *mode = TINY_EPD_REFRESH_PARTIAL;
    }
    else if (name_len == 12 && memcmp(name, "partial_rect", 12) == 0) {
        *mode = TINY_EPD_REFRESH_PARTIAL_RECT;
    }
    else if (name_len == 4 && memcmp(name, "auto", 4) == 0) {
        *mode = TINY_EPD_REFRESH_AUTO;
    }
    else {
        return -1;
    }
    return 0;
}

/*
@api panel:refresh([mode[, x, y, w, h]])
@string|number mode "full" (默认)、"partial"、"partial_rect"、"fast" 或对应 REFRESH_* 常量
@number x,y,w,h mode 为 "partial_rect" 时的刷新矩形
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
panel:refresh("full")
panel:pixel(12, 18, epd.BLACK)
panel:refresh("partial_rect", 8, 16, 32, 24)
*/
static int l_tiny_epd_refresh(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_refresh_mode_t mode;
    tiny_epd_rect_t rect;
    tiny_epd_rect_t *rect_ptr = NULL;
    lua_Integer value;

    if (luat_tiny_epd_refresh_mode(L, 2, &mode) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT) {
        if (lua_gettop(L) < 6) {
            return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        }
        value = luaL_checkinteger(L, 3);
        if (value < 0 || value > UINT16_MAX) return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        rect.x = (uint16_t)value;
        value = luaL_checkinteger(L, 4);
        if (value < 0 || value > UINT16_MAX) return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        rect.y = (uint16_t)value;
        value = luaL_checkinteger(L, 5);
        if (value < 0 || value > UINT16_MAX) return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        rect.w = (uint16_t)value;
        value = luaL_checkinteger(L, 6);
        if (value < 0 || value > UINT16_MAX) return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        rect.h = (uint16_t)value;
        rect_ptr = &rect;
    }
    return luat_tiny_epd_push_result(L, tiny_epd_refresh(device->epd, mode, rect_ptr));
}

static int luat_tiny_epd_sleep_mode(lua_State *L, int index, tiny_epd_sleep_mode_t *mode)
{
    size_t name_len;
    const char *name;
    lua_Integer numeric_mode;

    if (lua_isnoneornil(L, index)) {
        *mode = TINY_EPD_SLEEP_AUTO;
        return 0;
    }
    if (lua_isnumber(L, index)) {
        numeric_mode = luaL_checkinteger(L, index);
        if (numeric_mode >= TINY_EPD_SLEEP_AUTO && numeric_mode <= TINY_EPD_SLEEP_DEEP) {
            *mode = (tiny_epd_sleep_mode_t)numeric_mode;
            return 0;
        }
        return -1;
    }
    name = luaL_checklstring(L, index, &name_len);
    if (name_len == 4 && memcmp(name, "auto", 4) == 0) {
        *mode = TINY_EPD_SLEEP_AUTO;
    }
    else if (name_len == 7 && memcmp(name, "standby", 7) == 0) {
        *mode = TINY_EPD_SLEEP_STANDBY;
    }
    else if (name_len == 4 && memcmp(name, "deep", 4) == 0) {
        *mode = TINY_EPD_SLEEP_DEEP;
    }
    else {
        return -1;
    }
    return 0;
}

/*
@api panel:sleep([mode])
@string|number mode "auto" (默认)、"standby"、"deep" 或对应 SLEEP_* 常量
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_sleep(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_sleep_mode_t mode;

    if (luat_tiny_epd_sleep_mode(L, 2, &mode) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L, tiny_epd_sleep(device->epd, mode));
}

/*
@api panel:info()
@return table {width, height, stride, bits_per_pixel, plane_count, caps}
*/
static int l_tiny_epd_info(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);

    lua_createtable(L, 0, 6);
    lua_pushinteger(L, tiny_epd_width(device->epd));
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, tiny_epd_height(device->epd));
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, tiny_epd_stride(device->epd));
    lua_setfield(L, -2, "stride");
    lua_pushinteger(L, tiny_epd_bits_per_pixel(device->epd));
    lua_setfield(L, -2, "bits_per_pixel");
    lua_pushinteger(L, tiny_epd_plane_count(device->epd));
    lua_setfield(L, -2, "plane_count");
    lua_pushinteger(L, (lua_Integer)tiny_epd_caps(device->epd));
    lua_setfield(L, -2, "caps");
    return 1;
}

static void luat_tiny_epd_destroy(lua_State *L, luat_tiny_epd_device_t *device)
{
    if (device->epd != NULL) {
        tiny_epd_destroy(device->epd);
        device->epd = NULL;
    }
    if (device->spi_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, device->spi_ref);
        device->spi_ref = LUA_NOREF;
    }
}

/* @api panel:close() @return boolean 释放 tiny_epd 的 framebuffer 和设备对象 */
static int l_tiny_epd_close(lua_State *L)
{
    luat_tiny_epd_device_t *device =
        (luat_tiny_epd_device_t *)luaL_checkudata(L, 1, LUAT_TINY_EPD_DEVICE_META);

    luat_tiny_epd_destroy(L, device);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_tiny_epd_gc(lua_State *L)
{
    luat_tiny_epd_device_t *device =
        (luat_tiny_epd_device_t *)luaL_checkudata(L, 1, LUAT_TINY_EPD_DEVICE_META);

    luat_tiny_epd_destroy(L, device);
    return 0;
}

static const luaL_Reg tiny_epd_device_methods[] = {
    {"init", l_tiny_epd_init},
    {"clear", l_tiny_epd_clear},
    {"pixel", l_tiny_epd_pixel},
    {"refresh", l_tiny_epd_refresh},
    {"sleep", l_tiny_epd_sleep},
    {"info", l_tiny_epd_info},
    {"close", l_tiny_epd_close},
    {NULL, NULL}
};

static void luat_tiny_epd_register_device_metatable(lua_State *L)
{
    luaL_newmetatable(L, LUAT_TINY_EPD_DEVICE_META);
    luaL_newlib(L, tiny_epd_device_methods);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, l_tiny_epd_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
}

#include "rotable2.h"
static const rotable_Reg_t reg_tiny_epd[] = {
    {"open", ROREG_FUNC(l_tiny_epd_open)},
    {"MODEL_1IN54", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54)},
    {"MODEL_1IN54_V2", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V2)},
    {"MODEL_1IN54_V3", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V3)},
    {"MODEL_1IN54_SSD1607", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_SSD1607)},
    /* Same spelling as the legacy eink module, for easier migration. */
    {"MODEL_1in54", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54)},
    {"MODEL_1in54_V2", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V2)},
    {"MODEL_1in54_V3", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V3)},
    {"MODEL_1in54_SSD1607", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_SSD1607)},
    {"BLACK", ROREG_INT(TINY_EPD_COLOR_BLACK)},
    {"WHITE", ROREG_INT(TINY_EPD_COLOR_WHITE)},
    {"REFRESH_AUTO", ROREG_INT(TINY_EPD_REFRESH_AUTO)},
    {"REFRESH_FULL", ROREG_INT(TINY_EPD_REFRESH_FULL)},
    {"REFRESH_FAST", ROREG_INT(TINY_EPD_REFRESH_FAST)},
    {"REFRESH_PARTIAL", ROREG_INT(TINY_EPD_REFRESH_PARTIAL)},
    {"REFRESH_PARTIAL_RECT", ROREG_INT(TINY_EPD_REFRESH_PARTIAL_RECT)},
    {"SLEEP_AUTO", ROREG_INT(TINY_EPD_SLEEP_AUTO)},
    {"SLEEP_STANDBY", ROREG_INT(TINY_EPD_SLEEP_STANDBY)},
    {"SLEEP_DEEP", ROREG_INT(TINY_EPD_SLEEP_DEEP)},
    {"CAP_REFRESH_FULL", ROREG_INT(TINY_EPD_CAP_REFRESH_FULL)},
    {"CAP_REFRESH_FAST", ROREG_INT(TINY_EPD_CAP_REFRESH_FAST)},
    {"CAP_REFRESH_PARTIAL", ROREG_INT(TINY_EPD_CAP_REFRESH_PARTIAL)},
    {"CAP_REFRESH_PARTIAL_RECT", ROREG_INT(TINY_EPD_CAP_REFRESH_PARTIAL_RECT)},
    {"CAP_SLEEP_STANDBY", ROREG_INT(TINY_EPD_CAP_SLEEP_STANDBY)},
    {"CAP_SLEEP_DEEP", ROREG_INT(TINY_EPD_CAP_SLEEP_DEEP)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_tiny_epd(lua_State *L)
{
    luat_newlib2(L, reg_tiny_epd);
    luat_tiny_epd_register_device_metatable(L);
    return 1;
}

#endif
