
/*
@module  tp
@summary 触摸库
@version 1.0
@date    2025.02.19
@demo    lcd
@tag LUAT_USE_TP
*/

#include "luat_base.h"
#include "luat_tp.h"
#ifdef LUAT_USE_INPUT_TOUCH
#include "luat_tp_input.h"
#endif
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_gpio.h"
#include <stdint.h>

#ifdef LUAT_USE_LCD
#include "luat_lcd.h"
#endif

#define LUAT_LOG_TAG "tp"
#include "luat_log.h"

typedef struct tp_reg {
    const char *name;
    luat_tp_opts_t *opts;
}tp_reg_t;

static const tp_reg_t tp_regs[] = {
#ifndef LUAT_USE_TP_PC
    {"gt9xx",  &tp_config_gt9xx},
    {"gt911",  &tp_config_gt9xx},
    {"gt1158",  &tp_config_gt9xx},
    {"gt927",  &tp_config_gt9xx},
    // 临时措施, Air780EPM仅开启gt911触摸屏
    #if !defined(TYPE_EC718PM) && !defined(LUAT_USE_TP_TINY)
    {"gt9157",  &tp_config_gt9157},
    {"jd9261t",  &tp_config_jd9261t},
	{"jd9261t_inited",  &tp_config_jd9261t_inited},
	{"ft3x68", &tp_config_ft3x68},
	{"ft5446", &tp_config_ft3x68},
	{"ft5x06", &tp_config_ft3x68},
    {"cst816d", &tp_config_cst816d},
    {"cst820", &tp_config_cst820},
    {"cst9220", &tp_config_cst92xx},
    #endif
#endif
#ifdef LUAT_USE_TP_PC
    {"pc", &tp_config_pc},
#endif
    {"", NULL}
};

typedef struct {
    luat_tp_config_t *cfg;
    luat_tp_data_t data[LUAT_TP_TOUCH_MAX];
} tp_message_t;

static int l_tp_handler(lua_State* L, void* ptr) {
    (void)ptr;
    rtos_msg_t *msg = (rtos_msg_t *)lua_topointer(L, -1);
    tp_message_t *copy = msg->ptr;
    if (copy == NULL) return 0;
    luat_tp_config_t* luat_tp_config = copy->cfg;
    luat_tp_data_t* luat_tp_data = copy->data;

    if (luat_tp_config->luat_cb) {
        lua_geti(L, LUA_REGISTRYINDEX, (lua_Integer)(uintptr_t)luat_tp_config->luat_cb);
        if (lua_isfunction(L, -1)) {
            lua_pushlightuserdata(L, luat_tp_config);
            lua_newtable(L);
            for (uint8_t i=0; i<LUAT_TP_TOUCH_MAX; i++){
                if ((TP_EVENT_TYPE_DOWN == luat_tp_data[i].event) || (TP_EVENT_TYPE_UP == luat_tp_data[i].event) || (TP_EVENT_TYPE_MOVE == luat_tp_data[i].event)){
                    lua_newtable(L);
                    lua_pushstring(L, "event");
                    lua_pushinteger(L, luat_tp_data[i].event);
                    lua_settable(L, -3);
                    lua_pushstring(L, "track_id");
                    lua_pushinteger(L, luat_tp_data[i].track_id);
                    lua_settable(L, -3);
                    lua_pushstring(L, "x");
                    lua_pushinteger(L, luat_tp_data[i].x_coordinate);
                    lua_settable(L, -3);
                    lua_pushstring(L, "y");
                    lua_pushinteger(L, luat_tp_data[i].y_coordinate);
                    lua_settable(L, -3);
                    lua_pushstring(L, "width");
                    lua_pushinteger(L, luat_tp_data[i].width);
                    lua_settable(L, -3);
                    lua_pushstring(L, "timestamp");
                    lua_pushinteger(L, luat_tp_data[i].timestamp);
                    lua_settable(L, -3);

                    lua_pushinteger(L, i + 1);
                    lua_insert(L, -2);
                    lua_settable(L, -3);
                }
            }
            luat_heap_free(copy);
            lua_call(L, 2, 0);
            return 0;
        }
    }
    luat_heap_free(copy);
    // luat_tp_config->opts->read_done(luat_tp_config);
    return 0;
}

int l_tp_callback(luat_tp_config_t* luat_tp_config, luat_tp_data_t* luat_tp_data){
    if (!luat_tp_config->luat_cb) return 0;
	uint8_t i = 0;
    for(i = 0; i < LUAT_TP_TOUCH_MAX; i++) {
		if (luat_tp_data[i].event != TP_EVENT_TYPE_NONE) {
            tp_message_t *copy = luat_heap_malloc(sizeof(*copy));
            if (copy == NULL) return -1;
            copy->cfg = luat_tp_config;
            memcpy(copy->data, luat_tp_data, sizeof(copy->data));
            rtos_msg_t msg = {.handler = l_tp_handler, .ptr=copy};
            if (luat_msgbus_put(&msg, 1)) { luat_heap_free(copy); return -1; }
            return 0;
        }
    }
    return -1;
}

/*
触摸初始化
@api tp.init(tp, args)
@string 触摸芯片型号，当前支持：<br>gt911 <br>gt9157 <br>jd9261t
@table 附加参数,与具体设备有关：<br>port 驱动方式<br>port：硬件i2c端口,例如0,1,2...如果为软件i2c对象<br>pin_rst：复位引脚<br>pin_int：中断引脚<br>w:宽度(可选,默认会寻找已初始化的lcd的数据)<br>h:高度(可选,默认会寻找已初始化的lcd的数据)<br>direction:方向(可选,默认会寻找已初始化的lcd的数据)
@function 回调函数(可选,使用lvgl时可不传入,lvgl会自动处理), 回调参数: <br>tp_device: userdata tp.init返回的触摸设备对象 <br>tp_data: table 触摸数据,内部为多个触摸点数据的表,每个表中包括参数有: event: number 触摸事件,见文档上方的触摸事件常量 x: number 触摸位置x坐标 y: number 触摸位置y坐标 timestamp: number 时间戳
@return userdata tp_device:触摸设备对象
@usage
    local function tp_callBack(tp_device, tp_data)
        log.info("TP", tp_data[1].x, tp_data[1].y, tp_data[1].event)
        sys.publish("TP", tp_device, tp_data)
    end

    -- 硬件i2c驱动
    --tp.init("gt911",{port=0,pin_rst = 22,pin_int = 23},tp_callBack)

    -- 软件i2c驱动
    --local softI2C = i2c.createSoft(20, 21)
    --tp.init("gt911",{port=softI2C,pin_rst = 22,pin_int = 23},tp_callBack)
*/
static luat_tp_config_t *s_device;
static int l_tp_init(lua_State* L){
    int ret = 0;
    size_t len = 0;
    if (s_device){
        LLOGE("tp has been initialized!!!");
        return 0;
    }
    luat_tp_config_t config;
    luat_tp_config_t *luat_tp_config = &config;
    memset(luat_tp_config, 0x00, sizeof(luat_tp_config_t));
    luat_tp_config->callback = l_tp_callback;
    luat_tp_config->pin_rst = LUAT_GPIO_NONE;
#ifdef LUAT_USE_LCD
    luat_lcd_conf_t *lcd_conf = luat_lcd_get_default();
    if (lcd_conf){
        luat_tp_config->w = lcd_conf->w;
        luat_tp_config->h = lcd_conf->h;
        luat_tp_config->direction = lcd_conf->direction;
        if (lcd_conf->direction == LUAT_LCD_ROTATE_0 || lcd_conf->direction == LUAT_LCD_ROTATE_180){
            luat_tp_config->w = lcd_conf->w;
            luat_tp_config->h = lcd_conf->h;
        }else{
            luat_tp_config->w = lcd_conf->h;
            luat_tp_config->h = lcd_conf->w;
        }
    }
#endif

    const char* tp_name = luaL_checklstring(L, 1, &len);
    for(int i = 0; i < 100; i++){
        if (strlen(tp_regs[i].name) == 0)
          break;
        if(strcmp(tp_regs[i].name,tp_name) == 0){
            luat_tp_config->opts = tp_regs[i].opts;
            break;
        }
    }
    if (luat_tp_config->opts == NULL){
        LLOGE("tp_name:%s not found!!!", tp_name);
        return 0;
    }
    luat_tp_config->pin_int = luat_tp_config->opts->default_pin_int;

    lua_settop(L, 3);
    lua_pushstring(L, "port");
    int port = lua_gettable(L, 2);
    if (LUA_TNUMBER == port) {
        lua_Integer id = luaL_checkinteger(L, -1);
        if (id < 0 || id > UINT8_MAX) {
            LLOGE("invalid TP option: port");
            return 0;
        }
        luat_tp_config->i2c_id = id;
    }else if(LUA_TUSERDATA == port){
        luat_tp_config->soft_i2c = luaL_testudata(L, -1, LUAT_EI2C_TYPE);
        if (!luat_tp_config->soft_i2c || lua_rawlen(L, -1) < sizeof(luat_ei2c_t)) {
            LLOGE("port type error!!!");
            return 0;
        }
    }else{
        LLOGE("port type error!!!");
        return 0;
    }

    lua_pushstring(L, "pin_rst");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->pin_rst = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "pin_int");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        lua_Integer pin = luaL_checkinteger(L, -1);
        if (pin < -1 || pin > UINT8_MAX) {
            LLOGE("invalid TP option: pin_int");
            return 0;
        }
        luat_tp_config->pin_int = pin;
    }
    lua_pop(L, 1);
    lua_pushstring(L, "w");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->w = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "h");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->h = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "direction");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->direction = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "refresh_rate");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->refresh_rate = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "int_type");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->int_type = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);
    lua_pushstring(L, "tp_num");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->tp_num = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);

    lua_pushstring(L, "swap_xy");
    if (LUA_TNUMBER == lua_gettable(L, 2)) {
        luat_tp_config->swap_xy = luaL_checkinteger(L, -1);
    }
    lua_pop(L, 1);

    luat_tp_config = (luat_tp_config_t *)luat_heap_malloc(sizeof(luat_tp_config_t));
    if (luat_tp_config == NULL) {
        LLOGE("out of system memory!!!");
        return 0;
    }
    *luat_tp_config = config;
    int soft_ref = LUA_NOREF;
    if (luat_tp_config->soft_i2c) {
        lua_pushvalue(L, -1); /* port is still on the stack. */
        soft_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    }

	if (lua_isfunction(L, 3)) {
		lua_pushvalue(L, 3);
		luat_tp_config->luat_cb = (void*)(uintptr_t)luaL_ref(L, LUA_REGISTRYINDEX);
	}

#ifdef LUAT_USE_INPUT_TOUCH
    ret = luat_tp_input_setup(luat_tp_config);
#endif
    if (!ret) ret = luat_tp_init(luat_tp_config);
    if (ret && (!luat_tp_config->task_handle || luat_tp_config->opts->activate)) {
        /* Legacy drivers may have queued work before failing init. */
        if (luat_tp_config->luat_cb) luaL_unref(L, LUA_REGISTRYINDEX, (int)(uintptr_t)luat_tp_config->luat_cb);
        if (soft_ref != LUA_NOREF) luaL_unref(L, LUA_REGISTRYINDEX, soft_ref);
        luat_heap_free(luat_tp_config);
        return 0;
    }
    if (soft_ref != LUA_NOREF) luat_tp_config->soft_i2c->ei2c_ref = soft_ref;
    if (ret) return 0;
    lua_pushlightuserdata(L, luat_tp_config);
    s_device = luat_tp_config;
    return 1;
}

static int s_cal_ref = LUA_NOREF; /* Lua thread only. */

static int l_tp_cal_handler(lua_State *L, void *ptr)
{
    (void)ptr;
    const rtos_msg_t *msg = lua_topointer(L, -1);
    luat_tp_cal_notice_t notice;
    if (s_cal_ref == LUA_NOREF || msg->ptr != s_device ||
        !luat_tp_calibration_notice(s_device, msg->arg1, &notice)) return 0;
    lua_rawgeti(L, LUA_REGISTRYINDEX, s_cal_ref);
    int nargs;
    if (notice.done) {
        lua_pushliteral(L, "done");
        lua_pushboolean(L, notice.ok);
        nargs = 2;
    } else {
        lua_pushliteral(L, "point");
        lua_pushinteger(L, notice.x);
        lua_pushinteger(L, notice.y);
        nargs = 3;
    }
    bool ok = lua_pcall(L, nargs, 0, 0) == LUA_OK;
    if (!ok) {
        const char *error = lua_tostring(L, -1);
        LLOGE("calibration callback: %s", error ? error : "unknown error");
        lua_pop(L, 1);
    }
    if (notice.done || !ok) {
        luaL_unref(L, LUA_REGISTRYINDEX, s_cal_ref);
        s_cal_ref = LUA_NOREF;
    }
    luat_tp_calibration_ack(s_device, msg->arg1, ok);
    return 0;
}

static int l_tp_cal_notify(luat_tp_config_t *cfg, int serial)
{
    if (!luat_msgbus_freesize()) return -1;
    rtos_msg_t msg = {.handler = l_tp_cal_handler, .ptr = cfg, .arg1 = serial};
    return luat_msgbus_put(&msg, 0) ? -1 : 0;
}

enum { TP_CAL_VERSION = 1 };

static int l_tp_cal_error(lua_State *L, bool get, const char *reason)
{
    if (get) lua_pushnil(L); else lua_pushboolean(L, 0);
    lua_pushstring(L, reason);
    return 2;
}

static const char *l_tp_cal_reason(int ret)
{
    switch (ret) {
    case LUAT_TP_CAL_BUSY: return "busy";
    case LUAT_TP_CAL_NOT_CALIBRATED: return "not_calibrated";
    case LUAT_TP_CAL_INVALID_DATA: return "invalid_data";
    default: return "unsupported";
    }
}

static void l_tp_cal_putint(lua_State *L, const char *key, lua_Integer value)
{
    lua_pushinteger(L, value);
    lua_setfield(L, -2, key);
}

static int l_tp_cal_get(lua_State *L, luat_tp_config_t *cfg)
{
    if (!cfg->opts->name) return l_tp_cal_error(L, true, "unsupported");
    luat_tp_cal_data_t data;
    int ret = luat_tp_calibration_get(cfg, &data);
    if (ret) return l_tp_cal_error(L, true, l_tp_cal_reason(ret));

    lua_createtable(L, 0, 9);
    l_tp_cal_putint(L, "version", TP_CAL_VERSION);
    lua_pushstring(L, cfg->opts->name);
    lua_setfield(L, -2, "model");
    l_tp_cal_putint(L, "w", cfg->w);
    l_tp_cal_putint(L, "h", cfg->h);
    lua_pushboolean(L, data.swap);
    lua_setfield(L, -2, "swap");
    l_tp_cal_putint(L, "left", data.left);
    l_tp_cal_putint(L, "right", data.right);
    l_tp_cal_putint(L, "top", data.top);
    l_tp_cal_putint(L, "bottom", data.bottom);
    return 1;
}

static int l_tp_cal_field(lua_State *L, const char *key)
{
    lua_pushstring(L, key);
    return lua_rawget(L, 2);
}

static bool l_tp_cal_readint(lua_State *L, const char *key, int32_t *out)
{
    int type = l_tp_cal_field(L, key), is_integer;
    int64_t value = lua_tointegerx(L, -1, &is_integer);
    lua_pop(L, 1);
    if (type != LUA_TNUMBER || !is_integer || value < 0 || value > INT32_MAX) return false;
    *out = (int32_t)value;
    return true;
}

static bool l_tp_cal_read(lua_State *L, const luat_tp_config_t *cfg, luat_tp_cal_data_t *data)
{
    int32_t version, w, h;
    if (!l_tp_cal_readint(L, "version", &version) || version != TP_CAL_VERSION ||
        !l_tp_cal_readint(L, "w", &w) || w != cfg->w ||
        !l_tp_cal_readint(L, "h", &h) || h != cfg->h) return false;

    size_t len;
    const char *model = l_tp_cal_field(L, "model") == LUA_TSTRING ? lua_tolstring(L, -1, &len) : NULL;
    bool same_model = model && len == strlen(cfg->opts->name) && !memcmp(model, cfg->opts->name, len);
    lua_pop(L, 1);
    if (!same_model) return false;

    bool boolean = l_tp_cal_field(L, "swap") == LUA_TBOOLEAN;
    data->swap = lua_toboolean(L, -1);
    lua_pop(L, 1);
    return boolean && l_tp_cal_readint(L, "left", &data->left) && l_tp_cal_readint(L, "right", &data->right) &&
           l_tp_cal_readint(L, "top", &data->top) && l_tp_cal_readint(L, "bottom", &data->bottom);
}

static int l_tp_cal_set(lua_State *L, luat_tp_config_t *cfg)
{
    const luat_tp_calibration_ops_t *ops = cfg->opts->calibration;
    if (!ops || !ops->set || !cfg->opts->name) return l_tp_cal_error(L, false, "unsupported");
    luat_tp_cal_data_t data;
    if (!l_tp_cal_read(L, cfg, &data)) return l_tp_cal_error(L, false, "invalid_data");
    int ret = luat_tp_calibration_set(cfg, &data);
    if (ret) return l_tp_cal_error(L, false, l_tp_cal_reason(ret));
    lua_pushboolean(L, 1);
    return 1;
}

/*
执行触摸标定、读取或恢复当前标定。应用可自行保存标定数据，开机后恢复。
@api tp.calibration(dev, arg)
@userdata tp.init 返回的触摸设备
@any 可选。省略读取当前结果的副本；传入 table 恢复结果；传入函数异步启动标定。显式传 nil 无效。
@return any 读取成功返回 table，失败返回 nil；启动受理或恢复成功返回 true，失败返回 false
@return string 失败原因：not_calibrated（尚无结果）、busy（正在按压或标定）、unsupported（驱动不支持）、invalid_device（句柄无效）、invalid_data（记录不合法）
@usage
-- 开机 tp.init 成功后恢复，应用自行实现存取。
local saved = load_calibration()
if saved then tp.calibration(dev, saved) end

-- 松手后启动。收到 point 时画十字，坐标与普通触摸回调一致。
-- 回调内不能等待。标定按压不产生普通触摸事件。
-- 标定失败保留旧值。恢复成功后下一次触摸即使用新值。
local function start_calibration()
    return tp.calibration(dev, function(event, a, b)
        if event == "point" then
            draw_cross(a, b) -- 在十字处按住片刻再松手
        elseif event == "done" and a then
            save_calibration(tp.calibration(dev))
        end
    end)
end

-- 记录格式：version=1、model、w、h、swap、left、right、top、bottom。
-- w/h 是未旋转尺寸；swap 表示 ADC 两轴互换，与显示旋转、镜像独立。
-- 四个端点是换轴后的 ADC 整数，分别对应未旋转面板内缩约 10% 的十字。
-- 端点可以递减。恢复时版本、型号和尺寸必须匹配；换屏或改接线后应重新标定。
*/
static int l_tp_calibration(lua_State *L)
{
    int type = lua_type(L, 2);
    if (!s_device || !lua_islightuserdata(L, 1) || lua_touserdata(L, 1) != s_device) {
        return l_tp_cal_error(L, type == LUA_TNONE, "invalid_device");
    }
    if (type == LUA_TNONE) return l_tp_cal_get(L, s_device);
    if (type == LUA_TTABLE) return l_tp_cal_set(L, s_device);
    if (type != LUA_TFUNCTION) return l_tp_cal_error(L, false, "invalid_data");

    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    int ret = luat_tp_calibration_begin(s_device, l_tp_cal_notify);
    if (!ret) {
        s_cal_ref = ref;
        lua_pushboolean(L, 1);
        return 1;
    }
    luaL_unref(L, LUA_REGISTRYINDEX, ref);
    return l_tp_cal_error(L, false, l_tp_cal_reason(ret));
}

/*
触摸休眠
@api tp.sleep(tp_device)
@userdata tp_device:触摸设备对象
@return boolean 休眠成功返回true,失败返回false
@usage
    local function tp_callBack(tp_device, tp_data)
        log.info("TP", tp_data[1].x, tp_data[1].y, tp_data[1].event)
        sys.publish("TP", tp_device, tp_data)
    end

    tp_device = tp.init("gt911",{port=0,pin_rst = 22,pin_int = 23},tp_callBack)

    tp.sleep(tp_device)
*/
static int l_tp_sleep(lua_State* L){
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)lua_touserdata(L, 1);
    if (luat_tp_config == NULL){
        LLOGE("luat_tp_config is NULL!!!");
        return 0;
    }
    if (luat_tp_sleep(luat_tp_config)){
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/*
触摸休眠唤醒
@api tp.wakeup(tp_device)
@userdata tp_device:触摸设备对象
@return boolean 唤醒成功返回true,失败返回false
@usage
    local function tp_callBack(tp_device, tp_data)
        log.info("TP", tp_data[1].x, tp_data[1].y, tp_data[1].event)
        sys.publish("TP", tp_device, tp_data)
    end

    tp_device = tp.init("gt911",{port=0,pin_rst = 22,pin_int = 23},tp_callBack)
    tp.sleep(tp_device)
    tp.wakeup(tp_device)
*/
static int l_tp_wakeup(lua_State* L){
    luat_tp_config_t* luat_tp_config = (luat_tp_config_t*)lua_touserdata(L, 1);
    if (luat_tp_config == NULL){
        LLOGE("luat_tp_config is NULL!!!");
        return 0;
    }
    if (luat_tp_wakeup(luat_tp_config)){
        return 0;
    }
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"

static const rotable_Reg_t reg_tp[] =
{
	{ "init",	    ROREG_FUNC(l_tp_init)},
	{ "calibration", ROREG_FUNC(l_tp_calibration)},
    { "sleep",	    ROREG_FUNC(l_tp_sleep)},
    { "wakeup",	    ROREG_FUNC(l_tp_wakeup)},

    //@const EVENT_NONE number 空事件,不应出现
    { "EVENT_NONE",    ROREG_INT(TP_EVENT_TYPE_NONE)},
    //@const EVENT_DOWN number 按下
    { "EVENT_DOWN",    ROREG_INT(TP_EVENT_TYPE_DOWN)},
    //@const EVENT_UP number 抬起
    { "EVENT_UP",      ROREG_INT(TP_EVENT_TYPE_UP)},
    //@const EVENT_MOVE number 移动
    { "EVENT_MOVE",    ROREG_INT(TP_EVENT_TYPE_MOVE)},

    { "EVENT_TYPE_DOWN",    ROREG_INT(TP_EVENT_TYPE_DOWN)},
    { "EVENT_TYPE_DOWN",    ROREG_INT(TP_EVENT_TYPE_DOWN)},
    { "EVENT_TYPE_UP",      ROREG_INT(TP_EVENT_TYPE_UP)},
    { "EVENT_TYPE_MOVE",    ROREG_INT(TP_EVENT_TYPE_MOVE)},

    { "SWAP_NONE",  ROREG_INT(LUAT_TP_SWAP_NONE)},
    { "SWAP_X",     ROREG_INT(LUAT_TP_SWAP_X)},
    { "SWAP_Y",     ROREG_INT(LUAT_TP_SWAP_Y)},
    { "SWAP_XY",    ROREG_INT(LUAT_TP_SWAP_XY)},

    { "RISING",     ROREG_INT(LUAT_GPIO_RISING_IRQ)},
    { "FALLING",    ROREG_INT(LUAT_GPIO_FALLING_IRQ)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_tp(lua_State *L)
{
    luat_newlib2(L, reg_tp);
    return 1;
}
