
/*
@module  libgnss
@summary NMEA数据处理
@version 1.0
@date    2020.07.03
@demo libgnss
@tag LUAT_USE_LIBGNSS
@usage
-- 提醒: 本库输出的坐标,均为 WGS84 坐标系
-- 如需要在国内地图使用, 要转换成对应地图的坐标系, 例如 GCJ02 BD09
-- 相关链接: https://lbsyun.baidu.com/index.php?title=coordinate

-- 方案1, 经lua层进行数据中转
uart.setup(2, 115200)
uart.on(2, "recv", function(id, len)
    while 1 do
        local data = uart.read(id, 1024)
        if data and #data > 1 then
            libgnss.parse(data)
        else
            break
        end
    end
end)
-- 方案2, 适合2022.12.26之后编译固件,效率更高一些
uart.setup(2, 115200)
libgnss.bind(2)

-- 可选调试模式
-- libgnss.debug(true)

sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
end)
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_mcu.h"
#include "luat_rtc.h"

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"

extern luat_libgnss_t *libgnss_gnss;
// extern luat_libgnss_t *libgnss_gnsstmp;
extern char* libgnss_recvbuff;
extern int libgnss_route_uart_id;
extern int gnss_debug;

void luat_uart_set_app_recv(int id, luat_uart_recv_callback_t cb);

static inline void push_gnss_value(lua_State *L, struct minmea_float *f, int mode) {
    if (f->value == 0) {
        lua_pushinteger(L, 0);
        return;
    }
    switch (mode)
    {
    case 0:
        lua_pushnumber(L, minmea_tofloat(f));
        break;
    case 1:
        lua_pushinteger(L, minmea_tocoord2(f));
        break;
    case 2:
        lua_pushnumber(L, minmea_tocoord(f));
        break;
    default:
        lua_pushnumber(L, minmea_tocoord(f));
        break;
    }
}

static int luat_libgnss_state_handler(lua_State *L, void* ptr) {
    (void)ptr;
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (!lua_isfunction(L, -1)) {
        return 0;
    }
/*
@sys_pub libgnss
GNSS状态变化
GNSS_STATE
@usage
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
end)
*/
    lua_pushliteral(L, "GNSS_STATE");
    switch (msg->arg1)
    {
    case GNSS_STATE_FIXED:
        lua_pushliteral(L, "FIXED");
        break;
    case GNSS_STATE_LOSE:
        lua_pushliteral(L, "LOSE");
        break;
    case GNSS_STATE_OPEN:
        lua_pushliteral(L, "OPEN");
        break;
    case GNSS_STATE_CLOSE:
        lua_pushliteral(L, "CLOSE");
        break;
    default:
        return 0;
    }
    lua_pushinteger(L, msg->arg2);
    lua_call(L, 3, 0);
    return 0;
}

int luat_libgnss_state_onchanged(int state) {
    rtos_msg_t msg = {0};
    msg.handler = luat_libgnss_state_handler;
    msg.arg1 = state;
    #ifdef LUAT_USE_MCU
    msg.arg2 = luat_mcu_ticks();
    #endif
    luat_msgbus_put(&msg, 0);
    return 0;
}

static void put_datetime(lua_State*L, struct tm* rtime) {
    lua_pushliteral(L, "year");
    lua_pushinteger(L, rtime->tm_year);
    lua_settable(L, -3);

    lua_pushliteral(L, "month");
    lua_pushinteger(L, rtime->tm_mon + 1); // 比较纠结, 要不要兼容老的呢?
    lua_settable(L, -3);

    lua_pushliteral(L, "day");
    lua_pushinteger(L, rtime->tm_mday);
    lua_settable(L, -3);

    lua_pushliteral(L, "hour");
    lua_pushinteger(L, rtime->tm_hour);
    lua_settable(L, -3);

    lua_pushliteral(L, "min");
    lua_pushinteger(L, rtime->tm_min);
    lua_settable(L, -3);

    lua_pushliteral(L, "sec");
    lua_pushinteger(L, rtime->tm_sec);
    lua_settable(L, -3);
}

static int32_t l_gnss_callback(lua_State *L, void* ptr){
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_libgnss_uart_recv_cb(msg->arg1, msg->arg2);
	return 0;
}

static void l_libgnss_uart_recv_cb(int uart_id, uint32_t data_len)
{
    rtos_msg_t msg = {0};
    msg.handler = l_gnss_callback;
    msg.arg1 = uart_id;
    msg.arg2 = data_len;
    luat_msgbus_put(&msg, 0);

}
/**
处理nmea数据
@api libgnss.parse(str)
@string 原始nmea数据
@usage
-- 解析nmea数据
libgnss.parse(indata)
log.info("nmea", json.encode(libgnss.getRmc()))
 */
static int l_libgnss_parse(lua_State *L) {
    size_t len = 0;
    const char* str = luaL_checklstring(L, 1, &len);
    if (len > 0) {
        luat_libgnss_parse_data(str, len);
    }
    return 0;
}

/**
当前是否已经定位成功
@api libgnss.isFix()
@return boolean 定位成功与否
@usage
log.info("nmea", "isFix", libgnss.isFix())
 */
static int l_libgnss_is_fix(lua_State *L) {
    if (libgnss_gnss == NULL) {
        lua_pushboolean(L, 0);
    }
    else
        lua_pushboolean(L, libgnss_gnss->frame_rmc.valid != 0 ? 1 : 0);
    return 1;
}

/**
获取位置信息
@api libgnss.getIntLocation()
@return int lat数据, 格式为 ddddddddd
@return int lng数据, 格式为 ddddddddd
@return int speed数据
@usage
-- 建议用libgnss.getRmc(1)
log.info("nmea", "loc", libgnss.getIntLocation())
 */
static int l_libgnss_get_int_location(lua_State *L) {
    if (libgnss_gnss != NULL && libgnss_gnss->frame_rmc.valid) {
        lua_pushinteger(L, libgnss_gnss->frame_rmc.latitude.value);
        lua_pushinteger(L, libgnss_gnss->frame_rmc.longitude.value);
        lua_pushinteger(L, libgnss_gnss->frame_rmc.speed.value);
    } else {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
    }
    return 3;
}

/**
获取原始RMC位置信息
@api libgnss.getRmc(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式
@return table 原始rmc数据
@usage
-- 解析nmea
log.info("nmea", "rmc", json.encode(libgnss.getRmc(2)))
-- 实例输出
--[[
{
    "course":0,
    "valid":true,   // true定位成功,false定位丢失
    "lat":23.4067,  // 纬度, 正数为北纬, 负数为南纬
    "lng":113.231,  // 经度, 正数为东经, 负数为西经
    "variation":0,  // 地面航向，单位为度，从北向起顺时针计算
    "speed":0       // 地面速度, 单位为"节"
    "year":2023,    // 年份
    "month":1,      // 月份, 1-12
    "day":5,        // 月份天, 1-31
    "hour":7,       // 小时,0-23
    "min":23,       // 分钟,0-59
    "sec":20,       // 秒,0-59
}
]]
 */
static int l_libgnss_get_rmc(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    lua_createtable(L, 0, 12);

    struct tm rtime = {0};

    if (libgnss_gnss != NULL) {
        lua_pushboolean(L, libgnss_gnss->frame_rmc.valid);
        lua_setfield(L, -2, "valid");

        if (libgnss_gnss->frame_rmc.valid) {
            push_gnss_value(L, &(libgnss_gnss->frame_rmc.latitude), mode);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lat");

        if (libgnss_gnss->frame_rmc.valid) {
            push_gnss_value(L, &(libgnss_gnss->frame_rmc.longitude), mode);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lng");

        if (libgnss_gnss->frame_rmc.valid) {
            push_gnss_value(L, &(libgnss_gnss->frame_rmc.speed), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "speed");

        if (libgnss_gnss->frame_rmc.valid) {
            push_gnss_value(L, &(libgnss_gnss->frame_rmc.course), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "course");

        if (libgnss_gnss->frame_rmc.valid) {
            push_gnss_value(L, &(libgnss_gnss->frame_rmc.variation), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "variation");

        // 时间类
        minmea_getdatetime(&rtime, &libgnss_gnss->frame_rmc.date, &libgnss_gnss->frame_rmc.time);
        put_datetime(L, &rtime);
    }

    return 1;
}

static void add_gsv(lua_State*L, struct minmea_sentence_gsv* gsvs, size_t *count, int tp) {

    for (size_t i = 0; i < FRAME_GSV_MAX; i++)
    {
        for (size_t j = 0; j < 4; j++)
        {
            //LLOGD("nr %d snr %d", gnss->frame_gsv[i].sats[j].nr, gnss->frame_gsv[i].sats[j].snr);
            if (gsvs[i].sats[j].nr) {
                lua_pushinteger(L, *count);
                lua_createtable(L, 0, 4);

                lua_pushliteral(L, "nr");
                lua_pushinteger(L, gsvs[i].sats[j].nr);
                lua_settable(L, -3);

                lua_pushliteral(L, "snr");
                lua_pushinteger(L, gsvs[i].sats[j].snr);
                lua_settable(L, -3);

                lua_pushliteral(L, "elevation");
                lua_pushinteger(L, gsvs[i].sats[j].elevation);
                lua_settable(L, -3);

                lua_pushliteral(L, "azimuth");
                lua_pushinteger(L, gsvs[i].sats[j].azimuth);
                lua_settable(L, -3);

                lua_pushliteral(L, "tp");
                lua_pushinteger(L, tp);
                lua_settable(L, -3);

                lua_settable(L, -3);
                *count = *count + 1;
            }
        }
    }
}

/**
获取原始GSV信息
@api libgnss.getGsv()
@return table 原始GSV数据
@usage
-- 解析nmea
log.info("nmea", "gsv", json.encode(libgnss.getGsv()))
--[[实例输出
{
    "total_sats":24,      // 总可见卫星数量
    "sats":[
        {
            "snr":27,     // 信噪比
            "azimuth":278, // 方向角
            "elevation":59, // 仰角
            "tp":0,        // 0 - GPS/SASS/QSZZ, 1 - BD
            "nr":4         // 卫星编号
        },
        // 这里忽略了22个卫星的信息
        {
            "snr":0,
            "azimuth":107,
            "elevation":19,
            "tp":1,
            "nr":31
        }
    ]
}
]]
 */
static int l_libgnss_get_gsv(lua_State *L) {
    lua_createtable(L, 0, 2);
    if (libgnss_gnss == NULL)
        return 1;

    size_t count = 1;

    lua_createtable(L, 12, 0);
    if (libgnss_gnss->frame_gsv_gp->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_gp, &count, 0);
    }
    if (libgnss_gnss->frame_gsv_gb->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_gb, &count, 1);
    }
    // if (libgnss_gnss->frame_gsv_gl->total_sats > 0) {
    //     add_gsv(L, libgnss_gnss->frame_gsv_gl, &count);
    // }
    // if (libgnss_gnss->frame_gsv_ga->total_sats > 0) {
    //     add_gsv(L, libgnss_gnss->frame_gsv_ga, &count);
    // }
    lua_setfield(L, -2, "sats");

    lua_pushliteral(L, "total_sats");
    lua_pushinteger(L, count - 1);
    lua_settable(L, -3);

    return 1;
}


/**
获取原始GSA信息
@api libgnss.getGsa(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式
@return table 原始GSA数据
@usage
-- 获取
log.info("nmea", "gsa", json.encode(libgnss.getGsa()))
-- 示例数据
--[[
{
    "sats":[ // 正在使用的卫星编号
        9,
        6,
        16,
        16,
        26,
        21,
        27,
        27,
        4,
        36,
        3,
        7,
        8,
        194
    ],
    "vdop":0.03083333, // 垂直精度因子，0.00 - 99.99，不定位时值为 99.99
    "pdop":0.0455,     // 水平精度因子，0.00 - 99.99，不定位时值为 99.99
    "fix_type":3,      // 定位模式, 1-未定位, 2-2D定位, 3-3D定位
    "hdop":0.0335      // 位置精度因子，0.00 - 99.99，不定位时值为 99.99
}
]]
 */
static int l_libgnss_get_gsa(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    lua_createtable(L, 0, 10);

    //lua_pushliteral(L, "mode");
    //lua_pushlstring(L, gnss ? &(gnss->frame_gsa.mode) : "N", 1);
    //lua_settable(L, -3);

    lua_pushliteral(L, "fix_type");
    lua_pushinteger(L, libgnss_gnss->frame_gsa[0].fix_type);
    lua_settable(L, -3);

    lua_pushliteral(L, "pdop");
    push_gnss_value(L, &(libgnss_gnss->frame_gsa[0].pdop), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "hdop");
    push_gnss_value(L, &(libgnss_gnss->frame_gsa[0].hdop), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "vdop");
    push_gnss_value(L, &(libgnss_gnss->frame_gsa[0].vdop), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "sats");
    lua_createtable(L, 12, 0);
    size_t pos = 1;
    for (size_t i = 0; i < 12; i++) {
        for (size_t j = 0; j < 3; j++)
        {
            if (libgnss_gnss->frame_gsa[j].sats[i] == 0)
                continue;
            lua_pushinteger(L, libgnss_gnss->frame_gsa[j].sats[i]);
            lua_seti(L, -2, pos);
            pos ++;
        }
    }

    lua_settable(L, -3);

    return 1;
}


/**
获取VTA速度信息
@api libgnss.getVtg(data_mode)
@int 可选, 3-原始字符串, 不传或者传其他值, 则返回浮点值
@return table 原始VTA数据
@usage
-- 解析nmea
log.info("nmea", "vtg", json.encode(libgnss.getVtg()))
-- 示例
--[[
{
    "speed_knots":0,        // 速度, 英里/小时
    "true_track_degrees":0,  // 真北方向角
    "magnetic_track_degrees":0, // 磁北方向角
    "speed_kph":0           // 速度, 千米/小时
}
]]
 */
static int l_libgnss_get_vtg(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, libgnss_gnss->vtg);
        return 1;
    }
    lua_createtable(L, 0, 10);
    struct minmea_sentence_vtg frame_vtg = {0};
    minmea_parse_vtg(&frame_vtg, libgnss_gnss->vtg);

    // lua_pushliteral(L, "faa_mode");
    // lua_pushlstring(L, libgnss_gnss->frame_vtg.faa_mode, 1);
    // lua_settable(L, -3);

    lua_pushliteral(L, "true_track_degrees");
    push_gnss_value(L, &(frame_vtg.true_track_degrees), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "magnetic_track_degrees");
    push_gnss_value(L, &(frame_vtg.magnetic_track_degrees), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_knots");
    push_gnss_value(L, &(frame_vtg.speed_knots), 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_kph");
    push_gnss_value(L, &(frame_vtg.speed_kph), 0);
    lua_settable(L, -3);

    return 1;
}

/**
获取原始ZDA时间和日期信息
@api libgnss.getZda()
@return table 原始zda数据
@usage
log.info("nmea", "zda", json.encode(libgnss.getZda()))
-- 实例输出
--[[
{
    "minute_offset":0,   // 本地时区的分钟, 一般固定输出0
    "hour_offset":0,     // 本地时区的小时, 一般固定输出0
    "year":2023         // UTC 年，四位数字
    "month":1,          // UTC 月，两位，01 ~ 12
    "day":5,            // UTC 日，两位数字，01 ~ 31
    "hour":7,           // 小时
    "min":50,           // 分
    "sec":14,           // 秒
}
]]
 */
static int l_libgnss_get_zda(lua_State *L) {
    lua_createtable(L, 0, 9);
    struct tm rtime = {0};
    if (libgnss_gnss != NULL) {
        struct minmea_sentence_zda frame_zda = {0};
        minmea_parse_zda(&frame_zda, libgnss_gnss->zda);

        lua_pushliteral(L, "hour_offset");
        lua_pushinteger(L, frame_zda.hour_offset);
        lua_settable(L, -3);

        lua_pushliteral(L, "minute_offset");
        lua_pushinteger(L, frame_zda.minute_offset);
        lua_settable(L, -3);

        // 时间相关
        minmea_getdatetime(&rtime, &frame_zda.date, &frame_zda.time);
        put_datetime(L, &rtime);
    }

    return 1;
}

/**
设置调试模式
@api libgnss.debug(mode)
@bool true开启调试,false关闭调试,默认为false
@usage
-- 开启调试, 会输出GNSS原始数据到日志中
libgnss.debug(true)
-- 关闭调试
libgnss.debug(false)
 */
static int l_libgnss_debug(lua_State *L) {
    if (libgnss_gnss == NULL && luat_libgnss_init(0)) {
        return 0;
    }
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1)) {
        LLOGD("Debug ON");
        gnss_debug = 1;
    }
    else
    {
        LLOGD("Debug OFF");
        gnss_debug = 0;
    }

    return 0;
}

/*
获取GGA数据
@api libgnss.getGga(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式, 3-原始字符串
@return table GGA数据, 若如不存在会返回nil
@usage
local gga = libgnss.getGga(2)
if gga then
    log.info("GGA", json.encode(gga))
end
--实例输出
--[[
{
    "dgps_age":0,             // 差分校正时延，单位为秒
    "fix_quality":1,          // 定位状态标识 0 - 无效,1 - 单点定位,2 - 差分定位
    "satellites_tracked":14,  // 参与定位的卫星数量
    "altitude":0.255,         // 海平面分离度
    "hdop":0.0335,            // 水平精度因子，0.00 - 99.99，不定位时值为 99.99
    "longitude":113.231,      // 经度, 正数为东经, 负数为西经
    "latitude":23.4067,       // 纬度, 正数为北纬, 负数为南纬
    "height":0                // 椭球高，固定输出 1 位小数
}
]]
*/
static int l_libgnss_get_gga(lua_State* L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, libgnss_gnss->gga);
        return 1;
    }
    lua_newtable(L);
    struct minmea_sentence_gga frame_gga = {0};
    minmea_parse_gga(&frame_gga, libgnss_gnss->gga);

    lua_pushstring(L, "altitude");
    push_gnss_value(L, &(frame_gga.altitude), 0);
    lua_settable(L, -3);

    lua_pushstring(L, "latitude");
    push_gnss_value(L, &(frame_gga.latitude), mode);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    push_gnss_value(L, &(frame_gga.longitude), mode);
    lua_settable(L, -3);

    lua_pushstring(L, "fix_quality");
    lua_pushinteger(L, frame_gga.fix_quality);
    lua_settable(L, -3);

    lua_pushstring(L, "satellites_tracked");
    lua_pushinteger(L, frame_gga.satellites_tracked);
    lua_settable(L, -3);

    lua_pushstring(L, "hdop");
    push_gnss_value(L, &(frame_gga.hdop), 0);
    lua_settable(L, -3);

    lua_pushstring(L, "height");
    push_gnss_value(L, &(frame_gga.height), 0);
    lua_settable(L, -3);

    lua_pushstring(L, "dgps_age");
    push_gnss_value(L, &(frame_gga.dgps_age), 0);
    lua_settable(L, -3);

    return 1;
}

/*
获取GLL数据
@api libgnss.getGll(data_mode)
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式
@return table GLL数据, 若如不存在会返回nil
@usage
local gll = libgnss.getGll(2)
if gll then
    log.info("GLL", json.encode(gll))
end
-- 实例数据
--[[
{
    "status":"A",        // 定位状态, A有效, B无效
    "mode":"A",          // 定位模式, V无效, A单点解, D差分解
    "sec":20,            // 秒, UTC时间为准
    "min":23,            // 分钟, UTC时间为准
    "hour":7,            // 小时, UTC时间为准
    "longitude":113.231, // 经度, 正数为东经, 负数为西经
    "latitude":23.4067,  // 纬度, 正数为北纬, 负数为南纬
    "us":0               // 微妙数, 通常为0
}
]]
*/
static int l_libgnss_get_gll(lua_State* L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, libgnss_gnss->vtg);
        return 1;
    }
    lua_newtable(L);
    struct minmea_sentence_gll frame_gll = {0};
    minmea_parse_gll(&frame_gll, libgnss_gnss->gll);

    lua_pushstring(L, "latitude");
    push_gnss_value(L, &(frame_gll.latitude), mode);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    push_gnss_value(L, &(frame_gll.longitude), mode);
    lua_settable(L, -3);

    lua_pushstring(L, "mode");
    lua_pushfstring(L, "%c", frame_gll.mode);
    lua_settable(L, -3);

    lua_pushstring(L, "status");
    lua_pushfstring(L, "%c", frame_gll.status);
    lua_settable(L, -3);

    lua_pushstring(L, "hour");
    lua_pushinteger(L, frame_gll.time.hours);
    lua_settable(L, -3);
    lua_pushstring(L, "us");
    lua_pushinteger(L, frame_gll.time.microseconds);
    lua_settable(L, -3);
    lua_pushstring(L, "min");
    lua_pushinteger(L, frame_gll.time.minutes);
    lua_settable(L, -3);
    lua_pushstring(L, "sec");
    lua_pushinteger(L, frame_gll.time.seconds);
    lua_settable(L, -3);

    return 1;
}

/**
清除历史定位数据
@api libgnss.clear()
@return nil 无返回值
@usage
-- 该操作会清除所有定位数据
 */
static int l_libgnss_clear(lua_State*L) {
    (void)L;
    if (libgnss_gnss == NULL && luat_libgnss_init(1))
        return 0;
    memset(libgnss_gnss, 0, sizeof(luat_libgnss_t));
    return 0;
}

/*
绑定uart端口进行GNSS数据读取
@api libgnss.bind(id, next_id)
@int uart端口号
@int 转发到uart的id, 例如虚拟uart.VUART_0
@usage
-- 配置串口信息, 通常为 115200 8N1
uart.setup(2, 115200)
-- 绑定uart, 马上开始解析GNSS数据
libgnss.bind(2)
-- 无需再调用uart.on然后调用libgnss.parse
-- 开发期可打开调试日志
libgnss.debug(true)

-- 2023-01-02之后编译的固件有效
-- 从uart2读取并解析, 同时转发到虚拟串口0
libgnss.bind(2, uart.VUART_0)
*/
static int l_libgnss_bind(lua_State* L) {
    int uart_id = luaL_checkinteger(L, 1);
    l_libgnss_clear(L);
    if (libgnss_recvbuff == NULL) {
        libgnss_recvbuff = luat_heap_malloc(RECV_BUFF_SIZE);
    }
    if (luat_uart_exist(uart_id)) {
        //uart_app_recvs[uart_id] = nmea_uart_recv_cb;
        luat_uart_set_app_recv(uart_id, l_libgnss_uart_recv_cb);
    }
    if (lua_isinteger(L, 2)) {
        libgnss_route_uart_id = luaL_checkinteger(L, 2);
    }
    return 0;
}


/**
获取位置字符串
@api libgnss.locStr(mode)
@int 字符串模式. 0- Air780EG所需的格式
@return 指定模式的字符串
@usage
-- 仅推荐在定位成功后调用
 */
static int l_libgnss_locStr(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    char buff[64] = {0};
    float lat_f = minmea_tofloat(&libgnss_gnss->frame_rmc.latitude);
    float lng_f = minmea_tofloat(&libgnss_gnss->frame_rmc.longitude);
    switch (mode)
    {
    case 0:
        snprintf_(buff, 63, "%.7g,%c,%.7g,%c,1.0", 
                            fabs(lat_f), lat_f > 0 ? 'N' : 'S', 
                            fabs(lng_f), lng_f > 0 ? 'E' : 'W');
        break;
    case 1:
        snprintf_(buff, 63, "%d,%d", libgnss_gnss->frame_rmc.latitude.value, libgnss_gnss->frame_rmc.longitude.value);
        break;
    default:
        break;
    }
    lua_pushstring(L, buff);
    return 1;
}

/**
定位成功后自动设置RTC
@api libgnss.rtcAuto(enable)
@bool 开启与否, 默认是false关闭
@usage
-- 开启自动设置RTC
libgnss.rtcAuto(true)
 */
static int l_libgnss_rtc_auto(lua_State *L) {
    if (libgnss_gnss == NULL)
        return 0;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1)) {
        libgnss_gnss->rtc_auto = 1;
        LLOGD("GNSS->RTC Auto-Set now is ON");
    }
    else {
        libgnss_gnss->rtc_auto = 0;
        LLOGD("GNSS->RTC Auto-Set now is OFF");
    }
    return 0;
}

//临时处理, 当前GNSS处理均在lua线程
// static lua_State *gnss_L;
static int gnss_raw_cb = 0;

int luat_libgnss_rawdata_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    // lua_getglobal(L, "sys_pub");
    lua_geti(L, LUA_REGISTRYINDEX, gnss_raw_cb);
    if (lua_isfunction(L, -1)) {
        // lua_pushliteral(gnss_L, "GNSS_RAW_DATA");
        lua_pushlstring(L, ptr, msg->arg1);
        luat_heap_free(ptr);
        ptr = NULL;
        lua_call(L, 1, 0);
    }
    else {
        luat_heap_free(ptr);
    }
    return 0;
}

int luat_libgnss_on_rawdata(const char* data, size_t len) {
    if (gnss_raw_cb == 0)
        return 0;
    char* ptr = luat_heap_malloc(len);
    if (ptr == NULL)
        return 0;
    memcpy(ptr, data, len);
    rtos_msg_t msg = {
        .handler = luat_libgnss_rawdata_cb,
        .arg1 = len,
        .ptr = ptr
    };
    luat_msgbus_put(&msg, 0);
    return 0;
}

static int l_libgnss_on(lua_State *L) {
    size_t len = 0;
    const char* tp = luaL_checklstring(L, 1, &len);
    if (!strcmp("raw", tp)) {
        if (gnss_raw_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, gnss_raw_cb);
            gnss_raw_cb = 0;
        }
        if (lua_isfunction(L, 2)) {
            lua_pushvalue(L, 2);
            gnss_raw_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_libgnss[] =
{
    { "parse", ROREG_FUNC(l_libgnss_parse)},
    { "isFix", ROREG_FUNC(l_libgnss_is_fix)},
    { "getIntLocation", ROREG_FUNC(l_libgnss_get_int_location)},
    { "getRmc", ROREG_FUNC(l_libgnss_get_rmc)},
    { "getGsv", ROREG_FUNC(l_libgnss_get_gsv)},
    { "getGsa", ROREG_FUNC(l_libgnss_get_gsa)},
    { "getVtg", ROREG_FUNC(l_libgnss_get_vtg)},
    { "getGga", ROREG_FUNC(l_libgnss_get_gga)},
    { "getGll", ROREG_FUNC(l_libgnss_get_gll)},
    { "getZda", ROREG_FUNC(l_libgnss_get_zda)},
    { "locStr", ROREG_FUNC(l_libgnss_locStr)},
    { "rtcAuto",ROREG_FUNC(l_libgnss_rtc_auto)},
    { "on",     ROREG_FUNC(l_libgnss_on)},
    
    { "debug",  ROREG_FUNC(l_libgnss_debug)},
    { "clear",  ROREG_FUNC(l_libgnss_clear)},
    { "bind",   ROREG_FUNC(l_libgnss_bind)},

	{ NULL,      ROREG_INT(0)}
};

LUAMOD_API int luaopen_libgnss( lua_State *L ) {
    luat_newlib2(L, reg_libgnss);
    return 1;
}
