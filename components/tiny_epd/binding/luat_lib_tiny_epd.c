#include "luat_base.h"

#if defined(LUAT_USE_TINY_EPD)

#include "luat_mem.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "luat_spi.h"
#include "tiny_epd.h"
#include "tiny_epd_bitmap.h"
#include "tiny_epd_gfx.h"
#include "tiny_epd_qrcode.h"
#include "tiny_epd_port_luatos.h"

#include <limits.h>
#include <stdint.h>
#include <string.h>

#ifdef LUAT_USE_HZFONT
#include "tiny_epd_hzfont.h"
#endif

#define LUAT_LOG_TAG "epd"
#include "luat_log.h"

#define LUAT_TINY_EPD_DEVICE_META "epd.dev"
#define LUAT_TINY_EPD_SPI_DEVICE_META "SPI*"
#define LUAT_TINY_EPD_MODEL_1IN54 1
#define LUAT_TINY_EPD_MODEL_1IN54_V2 2
#define LUAT_TINY_EPD_MODEL_1IN54_V3 3
#define LUAT_TINY_EPD_MODEL_1IN54_SSD1607 4
#define LUAT_TINY_EPD_MODEL_1IN54R 5

typedef struct {
    tiny_epd_t *epd;
    tiny_epd_port_luatos_t port_context;
    int spi_ref;
    uint8_t refresh_busy;
} luat_tiny_epd_device_t;

typedef struct {
    luat_tiny_epd_device_t *device;
    tiny_epd_refresh_mode_t mode;
    tiny_epd_rect_t rect;
    uint64_t wait_id;
    int device_ref;
    int result;
    uint8_t use_dirty_rect;
    uint8_t has_rect;
} luat_tiny_epd_refresh_request_t;

#define LUAT_TINY_EPD_REFRESH_QUEUE_LENGTH 4u
#define LUAT_TINY_EPD_REFRESH_TASK_STACK_SIZE (4u * 1024u)

static luat_rtos_queue_t g_tiny_epd_refresh_queue;
static luat_rtos_task_handle g_tiny_epd_refresh_task;
static uint8_t g_tiny_epd_refresh_worker_ready;

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
    case TINY_EPD_ERR_FONT_NOT_READY:
        return "hzfont is not initialized";
    case TINY_EPD_ERR_UNSUPPORTED_COLOR:
        return "color is not supported by this panel";
    case TINY_EPD_ERR_UNSUPPORTED_FORMAT:
        return "unsupported framebuffer format";
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

static int luat_tiny_epd_push_message_result(lua_State *L, const char *message)
{
    lua_pushboolean(L, 0);
    lua_pushstring(L, message);
    return 2;
}

static int luat_tiny_epd_is_busy(const luat_tiny_epd_device_t *device)
{
    return device != NULL && device->refresh_busy != 0;
}

static int luat_tiny_epd_push_busy(lua_State *L)
{
    return luat_tiny_epd_push_message_result(L, "busy");
}

static int luat_tiny_epd_has_cwait(lua_State *L)
{
    int available;

    lua_getglobal(L, "sys_cw");
    available = lua_isfunction(L, -1);
    lua_pop(L, 1);
    return available;
}

static int luat_tiny_epd_push_cwait_message(lua_State *L, const char *message)
{
    lua_pushboolean(L, 0);
    lua_pushstring(L, message);
    luat_pushcwait_error(L, 2);
    return 1;
}

static int luat_tiny_epd_push_cwait_result(lua_State *L, int ret)
{
    if (ret == TINY_EPD_OK) {
        lua_pushboolean(L, 1);
        luat_pushcwait_error(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
        lua_pushstring(L, luat_tiny_epd_error_string(ret));
        luat_pushcwait_error(L, 2);
    }
    return 1;
}

static int luat_tiny_epd_refresh_done(lua_State *L, void *ptr)
{
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    luat_tiny_epd_refresh_request_t *request;
    luat_tiny_epd_device_t *device;
    int arg_num;

    if (msg == NULL || msg->ptr == NULL) {
        return 0;
    }
    request = (luat_tiny_epd_refresh_request_t *)msg->ptr;
    device = request->device;
    if (device != NULL) {
        device->refresh_busy = 0;
    }

    if (request->result == TINY_EPD_OK) {
        lua_pushboolean(L, 1);
        arg_num = 1;
    }
    else {
        lua_pushboolean(L, 0);
        lua_pushstring(L, luat_tiny_epd_error_string(request->result));
        arg_num = 2;
    }
    (void)luat_cbcwait(L, request->wait_id, arg_num);

    if (request->device_ref != LUA_NOREF) {
        luaL_unref(L, LUA_REGISTRYINDEX, request->device_ref);
    }
    luat_heap_free(request);
    return 0;
}

static void luat_tiny_epd_refresh_worker(void *param)
{
    luat_tiny_epd_refresh_request_t *request;
    rtos_msg_t msg;

    (void)param;
    for (;;) {
        request = NULL;
        if (luat_rtos_queue_recv(g_tiny_epd_refresh_queue, &request,
                                 sizeof(request), LUAT_WAIT_FOREVER) != 0 ||
            request == NULL) {
            continue;
        }

        if (request->use_dirty_rect) {
            request->result = tiny_epd_refresh_dirty(request->device->epd,
                                                      request->mode);
        }
        else {
            request->result = tiny_epd_refresh(request->device->epd,
                                                request->mode,
                                                request->has_rect ? &request->rect : NULL);
        }

        memset(&msg, 0, sizeof(msg));
        msg.handler = luat_tiny_epd_refresh_done;
        msg.ptr = request;
        (void)luat_msgbus_put(&msg, LUAT_WAIT_FOREVER);
    }
}

static int luat_tiny_epd_ensure_refresh_worker(void)
{
    int ret;

    if (g_tiny_epd_refresh_worker_ready) {
        return 0;
    }
    ret = luat_rtos_queue_create(&g_tiny_epd_refresh_queue,
                                 LUAT_TINY_EPD_REFRESH_QUEUE_LENGTH,
                                 sizeof(luat_tiny_epd_refresh_request_t *));
    if (ret != 0) {
        g_tiny_epd_refresh_queue = NULL;
        return -1;
    }
    ret = luat_rtos_task_create(&g_tiny_epd_refresh_task,
                                LUAT_TINY_EPD_REFRESH_TASK_STACK_SIZE,
                                50, "tiny_epd", luat_tiny_epd_refresh_worker,
                                NULL, 0);
    if (ret != 0) {
        (void)luat_rtos_queue_delete(g_tiny_epd_refresh_queue);
        g_tiny_epd_refresh_queue = NULL;
        g_tiny_epd_refresh_task = NULL;
        return -1;
    }
    g_tiny_epd_refresh_worker_ready = 1;
    return 0;
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
                model == LUAT_TINY_EPD_MODEL_1IN54_SSD1607 ||
                model == LUAT_TINY_EPD_MODEL_1IN54R) ? (int)model : 0;
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
    if ((name_len == 6 && memcmp(name, "1in54r", 6) == 0) ||
        (name_len == 16 && memcmp(name, "waveshare_1in54r", 16) == 0) ||
        (name_len == 20 && memcmp(name, "waveshare_1in54r_bwr", 20) == 0)) {
        return LUAT_TINY_EPD_MODEL_1IN54R;
    }
    return 0;
}

/* Lua colors are semantic palette IDs, not controller RAM encodings. */
static int luat_tiny_epd_get_color(lua_State *L, int index,
                                   tiny_epd_color_t default_value,
                                   tiny_epd_color_t *color)
{
    lua_Integer value;

    if (color == NULL) {
        return -1;
    }
    if (lua_isnoneornil(L, index)) {
        *color = default_value;
        return 0;
    }
    if (!lua_isinteger(L, index)) {
        return -1;
    }
    value = lua_tointeger(L, index);
    if (value < 0 || value > UINT8_MAX) {
        return -1;
    }
    *color = (tiny_epd_color_t)value;
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

static int luat_tiny_epd_parse_rotation(int value, tiny_epd_rotation_t *rotation)
{
    if (rotation == NULL) {
        return -1;
    }
    switch (value) {
    case 0:
        *rotation = TINY_EPD_ROTATE_0;
        return 0;
    case 1:
    case 90:
        *rotation = TINY_EPD_ROTATE_90;
        return 0;
    case 2:
    case 180:
        *rotation = TINY_EPD_ROTATE_180;
        return 0;
    case 3:
    case 270:
        *rotation = TINY_EPD_ROTATE_270;
        return 0;
    default:
        return -1;
    }
}

static int luat_tiny_epd_get_rotation_field(lua_State *L,
                                            int table_index,
                                            const char *field,
                                            int *present,
                                            tiny_epd_rotation_t *rotation)
{
    lua_Integer value;

    lua_getfield(L, table_index, field);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        *present = 0;
        return 0;
    }
    if (!lua_isnumber(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }
    value = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    if (value < INT_MIN || value > INT_MAX ||
        luat_tiny_epd_parse_rotation((int)value, rotation) != 0) {
        return -1;
    }
    *present = 1;
    return 0;
}

/*
@api epd.open(model, opts[, spi_device])
@number|string model 当前支持 epd.MODEL_1IN54 或 "1in54"
@table opts {port = spi_id|"device", pin_dc, pin_rst, pin_busy[, busy_pull, busy_poll_ms, rotation|direction]}
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
    int has_rotation;
    int has_direction;
    tiny_epd_rotation_t rotation = TINY_EPD_ROTATE_0;
    tiny_epd_rotation_t direction = TINY_EPD_ROTATE_0;

    model = luat_tiny_epd_get_model(L);
    if (model != LUAT_TINY_EPD_MODEL_1IN54 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_V2 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_V3 &&
        model != LUAT_TINY_EPD_MODEL_1IN54_SSD1607 &&
        model != LUAT_TINY_EPD_MODEL_1IN54R) {
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

    if (luat_tiny_epd_get_rotation_field(L, 2, "rotation", &has_rotation, &rotation) != 0 ||
        luat_tiny_epd_get_rotation_field(L, 2, "direction", &has_direction, &direction) != 0) {
        return luat_tiny_epd_push_open_error(L, "rotation/direction must be 0..3 or 0/90/180/270");
    }
    if (!has_rotation && has_direction) {
        rotation = direction;
    }

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
    else if (model == LUAT_TINY_EPD_MODEL_1IN54R) {
        driver = tiny_epd_driver_1in54r();
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
    ret = tiny_epd_set_rotation(device->epd, rotation);
    if (ret != TINY_EPD_OK) {
        tiny_epd_destroy(device->epd);
        device->epd = NULL;
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
    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    return luat_tiny_epd_push_result(L, tiny_epd_init(device->epd));
}

/*
@api panel:clear([color])
@number color 省略时使用当前背景色；也可显式传 panel palette 中的颜色
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_clear(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_color_t color;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (luat_tiny_epd_get_color(L, 2, TINY_EPD_COLOR_BG, &color) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L, tiny_epd_clear(device->epd, color));
}

/*
@api panel:pixel(x, y[, color])
@number x X 坐标
@number y Y 坐标
@number color 省略时使用当前前景色；也可显式传 panel palette 中的颜色
@note 坐标属于当前逻辑画布，和 line/rect/qrcode 一样受 setRotation() 影响。
@return boolean 成功返回 true，失败返回 false 和错误信息
*/
static int l_tiny_epd_pixel(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    tiny_epd_color_t color;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        luat_tiny_epd_get_color(L, 4, TINY_EPD_COLOR_FG, &color) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_pixel(device->epd,
                                                         (int16_t)x,
                                                         (int16_t)y,
                                                         color));
}

/*
@api panel:setColor(fg, bg)
@number fg 前景逻辑颜色
@number bg 背景逻辑颜色
@return boolean 成功返回 true；颜色不在当前 panel palette 时返回 false 和错误信息
@usage
assert(panel:setColor(epd.RED, epd.WHITE))
*/
static int l_tiny_epd_set_color(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_color_t foreground;
    tiny_epd_color_t background;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (lua_isnoneornil(L, 2) || lua_isnoneornil(L, 3) ||
        luat_tiny_epd_get_color(L, 2, TINY_EPD_COLOR_BLACK, &foreground) != 0 ||
        luat_tiny_epd_get_color(L, 3, TINY_EPD_COLOR_WHITE, &background) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_color_set(device->epd,
                                                        foreground, background));
}

/* @api panel:getColor() @return number fg @return number bg */
static int l_tiny_epd_get_color(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_color_t foreground;
    tiny_epd_color_t background;
    int ret;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    ret = tiny_epd_color_get(device->epd, &foreground, &background);
    if (ret != TINY_EPD_OK) {
        return luat_tiny_epd_push_result(L, ret);
    }
    lua_pushinteger(L, foreground);
    lua_pushinteger(L, background);
    return 2;
}

/* @api panel:supportsColor(color) @return boolean 是否由当前 panel palette 支持 */
static int l_tiny_epd_supports_color(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_color_t color;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (luat_tiny_epd_get_color(L, 2, TINY_EPD_COLOR_BLACK, &color) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    lua_pushboolean(L, tiny_epd_color_supported(device->epd, color));
    return 1;
}

static int luat_tiny_epd_refresh_mode(lua_State *L, int index, tiny_epd_refresh_mode_t *mode)
{
    lua_Integer numeric_mode;

    if (lua_isnoneornil(L, index)) {
        *mode = TINY_EPD_REFRESH_FULL;
        return 0;
    }
    if (!lua_isinteger(L, index)) {
        return -1;
    }
    numeric_mode = lua_tointeger(L, index);
    if (numeric_mode < TINY_EPD_REFRESH_AUTO ||
        numeric_mode > TINY_EPD_REFRESH_PARTIAL_RECT) {
        return -1;
    }
    *mode = (tiny_epd_refresh_mode_t)numeric_mode;
    return 0;
}

static int luat_tiny_epd_refresh_u16(lua_State *L, int index, uint16_t *value)
{
    lua_Integer input;

    if (!lua_isinteger(L, index)) {
        return -1;
    }
    input = lua_tointeger(L, index);
    if (input < 0 || input > UINT16_MAX) {
        return -1;
    }
    *value = (uint16_t)input;
    return 0;
}

/*
@api panel:refresh([mode[, x, y, w, h]])
@number mode epd.FULL（默认）、epd.FAST、epd.PARTIAL、epd.PARTIAL_RECT 或 epd.AUTO
@number x,y,w,h 仅 epd.PARTIAL_RECT 时的显式刷新矩形；省略时使用 dirty rectangle
@return cwait 使用 .wait() 得到 true，或 false 和错误信息
@usage
assert(panel:refresh(epd.FULL).wait())
panel:pixel(12, 18, epd.BLACK)
assert(panel:refresh(epd.PARTIAL_RECT).wait()) -- 自动刷新绘制过的包围矩形
*/
static int l_tiny_epd_refresh(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    tiny_epd_refresh_mode_t mode;
    luat_tiny_epd_refresh_request_t *request;
    uint64_t wait_id;
    int top = lua_gettop(L);

    if (!luat_tiny_epd_has_cwait(L)) {
        return luaL_error(L, "epd.refresh requires require('sys')");
    }
    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_cwait_message(L, "busy");
    }
    if (luat_tiny_epd_refresh_mode(L, 2, &mode) != 0) {
        return luat_tiny_epd_push_cwait_result(L, TINY_EPD_ERR_PARAM);
    }
    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT && top != 2 && top != 6) {
        return luat_tiny_epd_push_cwait_result(L, TINY_EPD_ERR_PARAM);
    }
    if (mode != TINY_EPD_REFRESH_PARTIAL_RECT && top != 2) {
        return luat_tiny_epd_push_cwait_result(L, TINY_EPD_ERR_PARAM);
    }
    if (luat_tiny_epd_ensure_refresh_worker() != 0) {
        return luat_tiny_epd_push_cwait_message(L, "failed to start refresh worker");
    }

    request = (luat_tiny_epd_refresh_request_t *)luat_heap_malloc(sizeof(*request));
    if (request == NULL) {
        return luat_tiny_epd_push_cwait_result(L, TINY_EPD_ERR_NO_MEM);
    }
    memset(request, 0, sizeof(*request));
    request->device = device;
    request->mode = mode;
    request->device_ref = LUA_NOREF;

    if (mode == TINY_EPD_REFRESH_PARTIAL_RECT && top == 6) {
        request->has_rect = 1;
        if (luat_tiny_epd_refresh_u16(L, 3, &request->rect.x) != 0 ||
            luat_tiny_epd_refresh_u16(L, 4, &request->rect.y) != 0 ||
            luat_tiny_epd_refresh_u16(L, 5, &request->rect.w) != 0 ||
            luat_tiny_epd_refresh_u16(L, 6, &request->rect.h) != 0) {
            luat_heap_free(request);
            return luat_tiny_epd_push_cwait_result(L, TINY_EPD_ERR_PARAM);
        }
    }
    else if (mode == TINY_EPD_REFRESH_PARTIAL_RECT || mode == TINY_EPD_REFRESH_AUTO) {
        request->use_dirty_rect = 1;
    }

    wait_id = luat_pushcwait(L);
    if (wait_id == 0) {
        luat_heap_free(request);
        return luaL_error(L, "epd.refresh requires require('sys')");
    }
    request->wait_id = wait_id;
    lua_pushvalue(L, 1);
    request->device_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    device->refresh_busy = 1;
    if (luat_rtos_queue_send(g_tiny_epd_refresh_queue, &request,
                             sizeof(request), LUAT_NO_WAIT) != 0) {
        device->refresh_busy = 0;
        luaL_unref(L, LUA_REGISTRYINDEX, request->device_ref);
        luat_heap_free(request);
        lua_pop(L, 1);
        return luat_tiny_epd_push_cwait_message(L, "refresh queue is full");
    }
    return 1;
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

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (luat_tiny_epd_sleep_mode(L, 2, &mode) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L, tiny_epd_sleep(device->epd, mode));
}

/*
@api panel:info()
@return table {width, height, native_width, native_height, stride, bits_per_pixel, plane_count, format, color_count, palette, caps, rotate}
*/
static int l_tiny_epd_info(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    uint16_t i;
    uint16_t color_count;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    lua_createtable(L, 0, 12);
    lua_pushinteger(L, tiny_epd_width(device->epd));
    lua_setfield(L, -2, "width");
    lua_pushinteger(L, tiny_epd_height(device->epd));
    lua_setfield(L, -2, "height");
    lua_pushinteger(L, tiny_epd_native_width(device->epd));
    lua_setfield(L, -2, "native_width");
    lua_pushinteger(L, tiny_epd_native_height(device->epd));
    lua_setfield(L, -2, "native_height");
    lua_pushinteger(L, tiny_epd_stride(device->epd));
    lua_setfield(L, -2, "stride");
    lua_pushinteger(L, tiny_epd_bits_per_pixel(device->epd));
    lua_setfield(L, -2, "bits_per_pixel");
    lua_pushinteger(L, tiny_epd_plane_count(device->epd));
    lua_setfield(L, -2, "plane_count");
    lua_pushinteger(L, tiny_epd_surface_format(device->epd));
    lua_setfield(L, -2, "format");
    color_count = tiny_epd_palette_count(device->epd);
    lua_pushinteger(L, color_count);
    lua_setfield(L, -2, "color_count");
    lua_createtable(L, (int)color_count, 0);
    for (i = 0; i < color_count; i++) {
        tiny_epd_palette_entry_t entry;

        if (tiny_epd_palette_get(device->epd, i, &entry) != TINY_EPD_OK) {
            continue;
        }
        lua_createtable(L, 0, 3);
        lua_pushinteger(L, entry.color);
        lua_setfield(L, -2, "color");
        lua_pushinteger(L, entry.storage_code);
        lua_setfield(L, -2, "code");
        lua_pushinteger(L, (lua_Integer)entry.rgb888);
        lua_setfield(L, -2, "rgb");
        lua_rawseti(L, -2, (int)i + 1);
    }
    lua_setfield(L, -2, "palette");
    lua_pushinteger(L, (lua_Integer)tiny_epd_caps(device->epd));
    lua_setfield(L, -2, "caps");
    /* Expose the current rotation; mirrored by tiny_epd_set_rotation. */
    lua_pushinteger(L, tiny_epd_rotate_get(device->epd));
    lua_setfield(L, -2, "rotate");
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

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    luat_tiny_epd_destroy(L, device);
    lua_pushboolean(L, 1);
    return 1;
}

static int l_tiny_epd_gc(lua_State *L)
{
    luat_tiny_epd_device_t *device =
        (luat_tiny_epd_device_t *)luaL_checkudata(L, 1, LUAT_TINY_EPD_DEVICE_META);

    if (!luat_tiny_epd_is_busy(device)) {
        luat_tiny_epd_destroy(L, device);
    }
    return 0;
}

/* -------------------------------------------------------------------------
 * Drawing primitives (line / rect / circle / qrcode) + rotation
 * ------------------------------------------------------------------------- */

/*
@api panel:setRotation(rotate)
@number rotate 旋转角度 0/90/180/270，或索引 0/1/2/3
@return boolean 成功返回 true
@usage
panel:setRotation(90)
panel:line(0, 0, 100, 100, epd.BLACK)  -- 在 90° 旋转坐标系下画线
*/
static int l_tiny_epd_set_rotation(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer v = luaL_checkinteger(L, 2);

    tiny_epd_rotation_t rotation;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (v < INT_MIN || v > INT_MAX ||
        luat_tiny_epd_parse_rotation((int)v, &rotation) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_set_rotation(device->epd, rotation));
}

/*
@api panel:line(x0, y0, x1, y1[, color])
@number x0 起点 X
@number y0 起点 Y
@number x1 终点 X
@number y1 终点 Y
@number color 省略时使用当前前景色；也可显式传 panel palette 中的颜色
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
panel:line(0, 0, 100, 100, epd.BLACK)
*/
static int l_tiny_epd_line(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x0 = luaL_checkinteger(L, 2);
    lua_Integer y0 = luaL_checkinteger(L, 3);
    lua_Integer x1 = luaL_checkinteger(L, 4);
    lua_Integer y1 = luaL_checkinteger(L, 5);
    tiny_epd_color_t color;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x0 < INT16_MIN || x0 > INT16_MAX || y0 < INT16_MIN || y0 > INT16_MAX ||
        x1 < INT16_MIN || x1 > INT16_MAX || y1 < INT16_MIN || y1 > INT16_MAX ||
        luat_tiny_epd_get_color(L, 6, TINY_EPD_COLOR_FG, &color) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_line(device->epd,
                                                        (int16_t)x0, (int16_t)y0,
                                                        (int16_t)x1, (int16_t)y1,
                                                        color));
}

/*
@api panel:rect(x, y, x2, y2[, color[, fill]])
@number x,y 左上角坐标
@number x2,y2 右下角坐标（end-point 形式）
@number color 省略时使用当前前景色；也可显式传 panel palette 中的颜色
@number fill 0=仅描边（默认），1=实心
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
panel:rect(0, 0, 199, 199, epd.BLACK, 1)   -- 实心边框
panel:rect(20, 20, 80, 80, epd.BLACK, 0)   -- 空心矩形
*/
static int l_tiny_epd_rect(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    lua_Integer x2 = luaL_checkinteger(L, 4);
    lua_Integer y2 = luaL_checkinteger(L, 5);
    tiny_epd_color_t color;
    int fill = (int)luaL_optinteger(L, 7, 0);

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        x2 < INT16_MIN || x2 > INT16_MAX || y2 < INT16_MIN || y2 > INT16_MAX ||
        luat_tiny_epd_get_color(L, 6, TINY_EPD_COLOR_FG, &color) != 0 ||
        (fill != 0 && fill != 1)) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_rect(device->epd,
                                                        (int16_t)x, (int16_t)y,
                                                        (int16_t)x2, (int16_t)y2,
                                                        color,
                                                        (uint8_t)fill));
}

/*
@api panel:circle(x, y, r[, color[, fill]])
@number x,y 圆心坐标
@number r 半径（0..255）
@number color 省略时使用当前前景色；也可显式传 panel palette 中的颜色
@number fill 0=仅描边（默认），1=实心
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
panel:circle(100, 100, 50, epd.BLACK, 0)   -- 空心圆
panel:circle(100, 100, 20, epd.BLACK, 1)   -- 实心圆
*/
static int l_tiny_epd_circle(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    lua_Integer r = luaL_checkinteger(L, 4);
    tiny_epd_color_t color;
    int fill = (int)luaL_optinteger(L, 6, 0);

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        r < 0 || r > 255 ||
        luat_tiny_epd_get_color(L, 5, TINY_EPD_COLOR_FG, &color) != 0 ||
        (fill != 0 && fill != 1)) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_circle(device->epd,
                                                          (int16_t)x, (int16_t)y,
                                                          (uint8_t)r,
                                                          color,
                                                          (uint8_t)fill));
}

/*
@api panel:drawXbm(x, y, width, height, data[, fg[, bg]])
@number x,y 位图左上角逻辑坐标；允许负坐标，屏幕外部分自动裁剪
@number width,height 位图像素尺寸
@string data XBM 数据：逐行存储，每行 ceil(width/8) 字节，低位在左
@number fg 置位像素颜色；省略时使用当前前景色
@number|nil bg 清零像素颜色；省略时使用当前背景色，显式传 nil 表示透明
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
-- 与 eink.drawXbm()/u8g2.DrawXBM 格式相同：每个字节 bit0 是最左侧像素
local xbm = string.char(0x81, 0x42, 0x24, 0x18, 0x24, 0x42, 0x81, 0x00)
assert(panel:drawXbm(20, 30, 8, 8, xbm))
-- 透明叠加：只有位图中的 1 写入 framebuffer
assert(panel:drawXbm(20, 30, 8, 8, xbm, epd.BLACK, nil))
*/
static int l_tiny_epd_draw_xbm(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    lua_Integer width = luaL_checkinteger(L, 4);
    lua_Integer height = luaL_checkinteger(L, 5);
    size_t data_len;
    const char *data = luaL_checklstring(L, 6, &data_len);
    tiny_epd_color_t fg;
    tiny_epd_color_t color;
    int16_t bg = TINY_EPD_COLOR_BG;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    /* An omitted eighth argument preserves legacy eink opaque semantics;
     * an explicit nil selects transparent XBM zero bits. */
    if (lua_gettop(L) >= 8) {
        if (lua_isnil(L, 8)) {
            bg = TINY_EPD_BITMAP_TRANSPARENT;
        }
        else if (luat_tiny_epd_get_color(L, 8, TINY_EPD_COLOR_BG, &color) != 0) {
            return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        }
        else {
            bg = (int16_t)color;
        }
    }

    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        width < 1 || width > UINT16_MAX || height < 1 || height > UINT16_MAX ||
        luat_tiny_epd_get_color(L, 7, TINY_EPD_COLOR_FG, &fg) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_xbm(device->epd,
                                                       (int16_t)x, (int16_t)y,
                                                       (uint16_t)width, (uint16_t)height,
                                                       (const uint8_t *)data, data_len,
                                                       fg, bg));
}

/*
@api panel:qrcode(x, y, str[, size[, color]])
@number x,y 左上角坐标
@string  str QR 内容
@number size QR 占用的像素正方形边长（必须 >= qrcode 模块数）
@number color 省略时使用当前前景/背景色；显式黑白色保持旧的反色背景行为
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
panel:qrcode(10, 10, "https://openluat.com", 120, epd.BLACK)
*/
static int l_tiny_epd_qrcode(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    const char *str = luaL_checkstring(L, 4);
    lua_Integer size = luaL_optinteger(L, 5, 0);
    tiny_epd_color_t color;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    if (luat_tiny_epd_get_color(L, 6, TINY_EPD_COLOR_FG, &color) != 0) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    if (size < 0 || size > UINT16_MAX) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }

    return luat_tiny_epd_push_result(L,
                                     tiny_epd_draw_qrcode(device->epd,
                                                          (int16_t)x, (int16_t)y,
                                                          str,
                                                          (uint16_t)size,
                                                          color));
}

#ifdef LUAT_USE_HZFONT
static int luat_tiny_epd_hzfont_style_int(lua_State *L,
                                          int table_index,
                                          const char *field,
                                          int minimum, int maximum,
                                          int *value)
{
    lua_Integer input;

    lua_getfield(L, table_index, field);
    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);
        return 0;
    }
    if (!lua_isnumber(L, -1)) {
        lua_pop(L, 1);
        return -1;
    }
    input = luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    if (input < minimum || input > maximum) {
        return -1;
    }
    *value = (int)input;
    return 1;
}

static int luat_tiny_epd_hzfont_parse_style(lua_State *L,
                                             int index,
                                             tiny_epd_hzfont_style_t *style)
{
    int value;
    int present;
    int has_fg;

    tiny_epd_hzfont_style_init(style);
    if (lua_isnoneornil(L, index)) {
        return 0;
    }
    /* Compatibility with eink.drawHzfont(..., antialias). */
    if (lua_isnumber(L, index)) {
        value = (int)luaL_checkinteger(L, index);
        if (value < -1 || value > 3) {
            return -1;
        }
        style->antialias = (int8_t)value;
        return 0;
    }
    if (!lua_istable(L, index)) {
        return -1;
    }

    present = luat_tiny_epd_hzfont_style_int(L, index, "fg", 0, UINT8_MAX, &value);
    if (present < 0) return -1;
    has_fg = present > 0;
    if (has_fg) style->fg = (uint8_t)value;
    /* color is an fg alias, useful for LCD-style code. */
    if (!has_fg) {
        present = luat_tiny_epd_hzfont_style_int(L, index, "color", 0, UINT8_MAX, &value);
        if (present < 0) return -1;
        if (present > 0) style->fg = (uint8_t)value;
    }
    present = luat_tiny_epd_hzfont_style_int(L, index, "bg", 0, UINT8_MAX, &value);
    if (present < 0) return -1;
    if (present > 0) style->bg = (int16_t)value;
    present = luat_tiny_epd_hzfont_style_int(L, index, "antialias", -1, 3, &value);
    if (present < 0) return -1;
    if (present > 0) style->antialias = (int8_t)value;
    present = luat_tiny_epd_hzfont_style_int(L, index, "threshold", 0, 255, &value);
    if (present < 0) return -1;
    if (present > 0) style->threshold = (uint8_t)value;

    lua_getfield(L, index, "dither");
    if (!lua_isnil(L, -1)) {
        if (!lua_isinteger(L, -1)) {
            lua_pop(L, 1);
            return -1;
        }
        value = (int)lua_tointeger(L, -1);
        if (value != TINY_EPD_HZFONT_DITHER_THRESHOLD &&
            value != TINY_EPD_HZFONT_DITHER_BAYER4) {
            lua_pop(L, 1);
            return -1;
        }
        style->dither = (tiny_epd_hzfont_dither_t)value;
    }
    lua_pop(L, 1);
    return 0;
}

/*
@api panel:drawHzfont(x, y, text, size[, style])
@number x X 坐标
@number y 基线 Y 坐标
@string text UTF-8 文本
@number size 字号（1..255 像素）
@nil|number|table style 省略或 nil 时使用当前前景/背景色；兼容旧接口时传 antialias(-1..3)；推荐传
 {fg=epd.RED, bg=epd.WHITE, antialias=-1, threshold=128, dither=epd.DITHER_THRESHOLD}
@return boolean 成功返回 true，失败返回 false 和错误信息
@usage
-- 省略 style：使用 setColor() 设置的前景/背景
assert(panel:drawHzfont(10, 36, "合宙LuatOS", 24))
-- 白底覆盖旧文字；bayer4 可改善黑白屏的边缘观感
assert(panel:drawHzfont(10, 68, "Hello世界", 20,
    {fg = epd.BLACK, bg = epd.WHITE, dither = epd.DITHER_BAYER4}))
*/
static int l_tiny_epd_draw_hzfont(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    lua_Integer x = luaL_checkinteger(L, 2);
    lua_Integer y = luaL_checkinteger(L, 3);
    const char *text = luaL_checkstring(L, 4);
    lua_Integer size = luaL_checkinteger(L, 5);
    tiny_epd_hzfont_style_t style;
    const tiny_epd_hzfont_style_t *style_ptr = NULL;

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (x < INT16_MIN || x > INT16_MAX || y < INT16_MIN || y > INT16_MAX ||
        size < 1 || size > UINT8_MAX) {
        return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
    }
    if (!lua_isnoneornil(L, 6)) {
        if (luat_tiny_epd_hzfont_parse_style(L, 6, &style) != 0) {
            return luat_tiny_epd_push_result(L, TINY_EPD_ERR_PARAM);
        }
        style_ptr = &style;
    }
    return luat_tiny_epd_push_result(L,
                                     tiny_epd_hzfont_draw_utf8(device->epd,
                                                               (int16_t)x, (int16_t)y,
                                                               text, (uint8_t)size,
                                                               style_ptr));
}

/*
@api panel:getHzfontWidth(text, size)
@string text UTF-8 文本
@number size 字号（1..255 像素）
@return number 文本像素宽度；HzFont 未初始化或参数错误时返回 0
*/
static int l_tiny_epd_get_hzfont_width(lua_State *L)
{
    luat_tiny_epd_device_t *device = luat_tiny_epd_check_device(L);
    const char *text = luaL_checkstring(L, 2);
    lua_Integer size = luaL_checkinteger(L, 3);

    if (luat_tiny_epd_is_busy(device)) {
        return luat_tiny_epd_push_busy(L);
    }
    if (size < 1 || size > UINT8_MAX) {
        lua_pushinteger(L, 0);
        return 1;
    }
    lua_pushinteger(L, tiny_epd_hzfont_get_utf8_width(text, (uint8_t)size));
    return 1;
}
#endif

static const luaL_Reg tiny_epd_device_methods[] = {
    {"init",         l_tiny_epd_init},
    {"clear",        l_tiny_epd_clear},
    {"pixel",        l_tiny_epd_pixel},
    {"setColor",     l_tiny_epd_set_color},
    {"getColor",     l_tiny_epd_get_color},
    {"supportsColor", l_tiny_epd_supports_color},
    {"setRotation",  l_tiny_epd_set_rotation},
    {"line",         l_tiny_epd_line},
    {"rect",         l_tiny_epd_rect},
    {"circle",       l_tiny_epd_circle},
    {"drawXbm",      l_tiny_epd_draw_xbm},
    {"qrcode",       l_tiny_epd_qrcode},
#ifdef LUAT_USE_HZFONT
    {"drawHzfont",   l_tiny_epd_draw_hzfont},
    {"getHzfontWidth", l_tiny_epd_get_hzfont_width},
#endif
    {"refresh",      l_tiny_epd_refresh},
    {"sleep",        l_tiny_epd_sleep},
    {"info",         l_tiny_epd_info},
    {"close",        l_tiny_epd_close},
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
    {"MODEL_1IN54R", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54R)},
    /* Same spelling as the legacy eink module, for easier migration. */
    {"MODEL_1in54", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54)},
    {"MODEL_1in54_V2", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V2)},
    {"MODEL_1in54_V3", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_V3)},
    {"MODEL_1in54_SSD1607", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54_SSD1607)},
    {"MODEL_1in54r", ROREG_INT(LUAT_TINY_EPD_MODEL_1IN54R)},
    {"BLACK", ROREG_INT(TINY_EPD_COLOR_BLACK)},
    {"WHITE", ROREG_INT(TINY_EPD_COLOR_WHITE)},
    {"RED", ROREG_INT(TINY_EPD_COLOR_RED)},
    {"YELLOW", ROREG_INT(TINY_EPD_COLOR_YELLOW)},
    {"ORANGE", ROREG_INT(TINY_EPD_COLOR_ORANGE)},
    {"BLUE", ROREG_INT(TINY_EPD_COLOR_BLUE)},
    {"GREEN", ROREG_INT(TINY_EPD_COLOR_GREEN)},
    {"FORMAT_INDEX1", ROREG_INT(TINY_EPD_SURFACE_INDEX1)},
    {"FORMAT_INDEX2", ROREG_INT(TINY_EPD_SURFACE_INDEX2)},
    {"FORMAT_INDEX4", ROREG_INT(TINY_EPD_SURFACE_INDEX4)},
    {"FORMAT_INDEX8", ROREG_INT(TINY_EPD_SURFACE_INDEX8)},
    {"FORMAT_PLANAR1", ROREG_INT(TINY_EPD_SURFACE_PLANAR1)},
    {"AUTO", ROREG_INT(TINY_EPD_REFRESH_AUTO)},
    {"FULL", ROREG_INT(TINY_EPD_REFRESH_FULL)},
    {"FAST", ROREG_INT(TINY_EPD_REFRESH_FAST)},
    {"PARTIAL", ROREG_INT(TINY_EPD_REFRESH_PARTIAL)},
    {"PARTIAL_RECT", ROREG_INT(TINY_EPD_REFRESH_PARTIAL_RECT)},
#ifdef LUAT_USE_HZFONT
    {"DITHER_THRESHOLD", ROREG_INT(TINY_EPD_HZFONT_DITHER_THRESHOLD)},
    {"DITHER_BAYER4", ROREG_INT(TINY_EPD_HZFONT_DITHER_BAYER4)},
#endif
    {"SLEEP_AUTO", ROREG_INT(TINY_EPD_SLEEP_AUTO)},
    {"SLEEP_STANDBY", ROREG_INT(TINY_EPD_SLEEP_STANDBY)},
    {"SLEEP_DEEP", ROREG_INT(TINY_EPD_SLEEP_DEEP)},
    {"CAP_REFRESH_FULL", ROREG_INT(TINY_EPD_CAP_REFRESH_FULL)},
    {"CAP_REFRESH_FAST", ROREG_INT(TINY_EPD_CAP_REFRESH_FAST)},
    {"CAP_REFRESH_PARTIAL", ROREG_INT(TINY_EPD_CAP_REFRESH_PARTIAL)},
    {"CAP_REFRESH_PARTIAL_RECT", ROREG_INT(TINY_EPD_CAP_REFRESH_PARTIAL_RECT)},
    {"CAP_SLEEP_STANDBY", ROREG_INT(TINY_EPD_CAP_SLEEP_STANDBY)},
    {"CAP_SLEEP_DEEP", ROREG_INT(TINY_EPD_CAP_SLEEP_DEEP)},
    {"CAP_COLOR_BW", ROREG_INT(TINY_EPD_CAP_COLOR_BW)},
    {"CAP_COLOR_BWR", ROREG_INT(TINY_EPD_CAP_COLOR_BWR)},
    {"CAP_COLOR_BWY", ROREG_INT(TINY_EPD_CAP_COLOR_BWY)},
    {"CAP_COLOR_4", ROREG_INT(TINY_EPD_CAP_COLOR_4)},
    {"CAP_COLOR_7", ROREG_INT(TINY_EPD_CAP_COLOR_7)},
    {"CAP_GRAY", ROREG_INT(TINY_EPD_CAP_GRAY)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_tiny_epd(lua_State *L)
{
    luat_newlib2(L, reg_tiny_epd);
    luat_tiny_epd_register_device_metatable(L);
    return 1;
}

#endif
