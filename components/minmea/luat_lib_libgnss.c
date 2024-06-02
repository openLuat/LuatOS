
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
-- 相关链接: https://www.openluat.com/GPS-Offset.html

-- 提醒: GPS功能, GNSS功能, NMEA解析功能,均为当前库的子功能
-- 本库的主要功能就是解析NMEA协议, 支持内置GNSS也支持外置GNSS

-- 以下是使用本libgnss的示例代码
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
#include "luat_mem.h"
#include "luat_uart.h"
#include "luat_mcu.h"
#include "luat_rtc.h"
#include "luat_zbuff.h"

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"

extern luat_libgnss_t gnssctx;
// extern luat_libgnss_t *libgnss_gnsstmp;
extern char* libgnss_recvbuff;
extern int libgnss_route_uart_id;
extern int gnss_debug;

static int gnss_raw_cb = 0;
static int gnss_txt_cb = 0;
// static int gnss_rmc_cb = 0;
static int gnss_other_cb = 0;

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

static int l_gnss_callback(lua_State *L, void* ptr){
    (void)ptr;
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
log.info("nmea", json.encode(libgnss.getRmc(), "11g"))
 */
static int l_libgnss_parse(lua_State *L) {
    size_t len = 0;
    const char* str = NULL;
    luat_zbuff_t* zbuff = NULL;
    if (lua_type(L, 1) == LUA_TSTRING) {
        str = luaL_checklstring(L, 1, &len);
    }
    else if (lua_isuserdata(L, 1)) {
        zbuff = tozbuff(L);
        str = (const char*)zbuff->addr;
        len = zbuff->used;
    }
    else {
        return 0;
    }
    
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
    lua_pushboolean(L, gnssctx.frame_rmc.valid != 0 ? 1 : 0);
    return 1;
}

/**
获取位置信息
@api libgnss.getIntLocation(speed_type)
@int 速度单位,默认是m/h
@return int lat数据, 格式为 ddddddddd
@return int lng数据, 格式为 ddddddddd
@return int speed数据, 单位米. 于2023.9.26修正
@usage
-- 建议用libgnss.getRmc(1)
log.info("nmea", "loc", libgnss.getIntLocation())

-- 2023.12.11 新增speed_type参数
--[[
速度单位可选值
0 - m/h 米/小时, 默认值, 整型
1 - m/s 米/秒, 浮点数
2 - km/h 千米/小时, 浮点数
3 - kn/h 英里/小时, 浮点数
]]
-- 默认 米/小时
log.info("nmea", "loc", libgnss.getIntLocation())
-- 米/秒
log.info("nmea", "loc", libgnss.getIntLocation(1))
-- 千米/小时
log.info("nmea", "loc", libgnss.getIntLocation(2))
-- 英里/小时
log.info("nmea", "loc", libgnss.getIntLocation(3))
 */
static int l_libgnss_get_int_location(lua_State *L) {
    if (gnssctx.frame_rmc.valid) {
        lua_pushinteger(L, gnssctx.frame_rmc.latitude.value);
        lua_pushinteger(L, gnssctx.frame_rmc.longitude.value);
        int speed_type = luaL_optinteger(L, 1, 0);
        switch (speed_type)
        {
        case 1: // 米/秒
            lua_pushnumber(L, (minmea_tofloat(&(gnssctx.frame_rmc.speed)) * 1852 / 3600));
            break;
        case 2: // 千米/小时
            lua_pushnumber(L, (minmea_tofloat(&(gnssctx.frame_rmc.speed)) * 1.852));
            break;
        case 3: // 英里/小时
            lua_pushnumber(L, minmea_tofloat(&(gnssctx.frame_rmc.speed)));
            break;
        default: // 米/小时
            lua_pushinteger(L, (int32_t)(minmea_tofloat(&(gnssctx.frame_rmc.speed)) * 1852));
            break;
        }
        
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
@int 坐标类数据的格式, 0-DDMM.MMM格式, 1-DDDDDDD格式, 2-DD.DDDDD格式, 3-原始RMC字符串
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

    if (mode == 3) {
        if (gnssctx.rmc == NULL)
            return 0;
        lua_pushstring(L, gnssctx.rmc->data);
        return 1;
    }

    if (1) {
        lua_pushboolean(L, gnssctx.frame_rmc.valid);
        lua_setfield(L, -2, "valid");

        if (gnssctx.frame_rmc.valid) {
            push_gnss_value(L, &(gnssctx.frame_rmc.latitude), mode);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lat");

        if (gnssctx.frame_rmc.valid) {
            push_gnss_value(L, &(gnssctx.frame_rmc.longitude), mode);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lng");

        if (gnssctx.frame_rmc.valid) {
            push_gnss_value(L, &(gnssctx.frame_rmc.speed), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "speed");

        if (gnssctx.frame_rmc.valid) {
            push_gnss_value(L, &(gnssctx.frame_rmc.course), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "course");

        if (gnssctx.frame_rmc.valid) {
            push_gnss_value(L, &(gnssctx.frame_rmc.variation), 0);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "variation");

        // 时间类
        minmea_getdatetime(&rtime, &gnssctx.frame_rmc.date, &gnssctx.frame_rmc.time);
        put_datetime(L, &rtime);
    }

    return 1;
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
            "tp":0,        // 0 - GPS, 1 - BD
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
    size_t count = 1;
    uint64_t tnow = luat_mcu_tick64_ms();
    struct minmea_sentence_gsv frame_gsv = {0};
    lua_createtable(L, FRAME_GSV_MAX, 0);
    for (size_t i = 0; i < FRAME_GSV_MAX; i++)
    {
        if (!luat_libgnss_data_check(gnssctx.gsv[i], 3500, tnow) || !minmea_parse_gsv(&frame_gsv, gnssctx.gsv[i]->data)) {
            continue;
        }

        for (size_t j = 0; j < 4; j++)
        {
            if (!frame_gsv.sats[j].nr) {
                continue;
            }
            lua_pushinteger(L, count);
            lua_createtable(L, 0, 4);

            lua_pushliteral(L, "nr");
            lua_pushinteger(L, frame_gsv.sats[j].nr);
            lua_settable(L, -3);
    
            lua_pushliteral(L, "snr");
            lua_pushinteger(L, frame_gsv.sats[j].snr);
            lua_settable(L, -3);
    
            lua_pushliteral(L, "elevation");
            lua_pushinteger(L, frame_gsv.sats[j].elevation);
            lua_settable(L, -3);
    
            lua_pushliteral(L, "azimuth");
            lua_pushinteger(L, frame_gsv.sats[j].azimuth);
            lua_settable(L, -3);
    
            // 区分不同的卫星系统
            // https://receiverhelp.trimble.com/alloy-gnss/en-us/NMEA-0183messages_GSA.html
            lua_pushliteral(L, "tp");
            if (memcmp(gnssctx.gsv[i], "$GP", 3) == 0) {
                lua_pushinteger(L, 0);
            }
            else if (memcmp(gnssctx.gsv[i], "$GL", 3) == 0) {
                lua_pushinteger(L, 2);
            }
            else if (memcmp(gnssctx.gsv[i], "$GA", 3) == 0) {
                lua_pushinteger(L, 3);
            }
            else if (memcmp(gnssctx.gsv[i], "$BD", 3) == 0 || memcmp(gnssctx.gsv[i], "$GB", 3) == 0) {
                lua_pushinteger(L, 1);
            }
            else if (memcmp(gnssctx.gsv[i], "$QZ", 3) == 0) {
                lua_pushinteger(L, 4);
            }
            else {
                lua_pushinteger(L, 0);
            }
            lua_settable(L, -3);

            // 新增一个类型, 字符串的, 实在是各种变化无法应对
            lua_pushliteral(L, "tpstr");
            lua_pushlstring(L, gnssctx.gsv[i]->data + 1, 2);
            lua_settable(L, -3);

            lua_settable(L, -3);
            count = count + 1;
        }
    }
    lua_setfield(L, -2, "sats");

    lua_pushliteral(L, "total_sats");
    lua_pushinteger(L, count - 1);
    lua_settable(L, -3);

    return 1;
}


/**
获取原始GSA信息
@api libgnss.getGsa(data_mode)
@int 模式
@return table 原始GSA数据
@usage
-- 获取
log.info("nmea", "gsa", json.encode(libgnss.getGsa(), "11g"))
-- 示例数据(模式0, 也就是默认模式)
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

-- 示例数据(模式1), 2024.5.26新增
[
    {"pdop":7.8299999,"sats":[13,15,18,23],"vdop":3.2400000,"hdop":7.1300001,"fix_type":3},
    {"pdop":7.8299999,"sats":[20,35,8,13],"vdop":3.2400000,"hdop":7.1300001,"fix_type":3}
]
 */

static int l_libgnss_get_gsa_mode0(lua_State *L) {
    struct minmea_sentence_gsa frame_gsa = {0};
    uint64_t tnow = luat_mcu_tick64_ms();
    lua_createtable(L, 0, 12);

    for (size_t i = 0; i < FRAME_GSA_MAX; i++)
    {
        if (!luat_libgnss_data_check(gnssctx.gsa[i], 1500, tnow) || minmea_parse_gsa(&frame_gsa, gnssctx.gsa[i]->data) != 1)
        {
            continue;
        }
        lua_pushliteral(L, "fix_type");
        lua_pushinteger(L, frame_gsa.fix_type);
        lua_settable(L, -3);

        lua_pushliteral(L, "pdop");
        push_gnss_value(L, &(frame_gsa.pdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "hdop");
        push_gnss_value(L, &(frame_gsa.hdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "vdop");
        push_gnss_value(L, &(frame_gsa.vdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "sysid");
        lua_pushinteger(L, frame_gsa.sysid);
        lua_settable(L, -3);
        break;
    }

    lua_pushliteral(L, "sats");
    lua_createtable(L, FRAME_GSA_MAX, 0);
    size_t pos = 1;
    for (size_t i = 0; i < FRAME_GSA_MAX; i++) {
        if (gnssctx.gsa[i] == NULL || minmea_parse_gsa(&frame_gsa, gnssctx.gsa[i]->data) != 1)
        {
            continue;
        }
        if (tnow - gnssctx.gsa[i]->tm > 1000) {
            continue;
        }
        // LLOGD("GSA: %s", gnssctx.gsa[i]->data);
        for (size_t j = 0; j < 12; j++)
        {
            if (frame_gsa.sats[j] == 0)
                continue;
            
            lua_pushinteger(L, frame_gsa.sats[j]);
            lua_seti(L, -2, pos);
            pos ++;
        }
    }
    lua_settable(L, -3);
    return 1;
}

static int l_libgnss_get_gsa_mode1(lua_State *L) {
    struct minmea_sentence_gsa frame_gsa = {0};
    uint64_t tnow = luat_mcu_tick64_ms();
    
    lua_createtable(L, FRAME_GSA_MAX, 0);
    size_t count = 0;
    for (size_t i = 0; i < FRAME_GSA_MAX; i++) {
        if (gnssctx.gsa[i] == NULL || minmea_parse_gsa(&frame_gsa, gnssctx.gsa[i]->data) != 1)
        {
            continue;
        }
        if (tnow - gnssctx.gsa[i]->tm > 1000) {
            continue;
        }
        count ++;
        lua_createtable(L, 0, 12);
        lua_pushliteral(L, "fix_type");
        lua_pushinteger(L, frame_gsa.fix_type);
        lua_settable(L, -3);

        lua_pushliteral(L, "pdop");
        push_gnss_value(L, &(frame_gsa.pdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "hdop");
        push_gnss_value(L, &(frame_gsa.hdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "vdop");
        push_gnss_value(L, &(frame_gsa.vdop), 0);
        lua_settable(L, -3);

        lua_pushliteral(L, "sysid");
        lua_pushinteger(L, frame_gsa.sysid);
        lua_settable(L, -3);
        
        lua_pushliteral(L, "sats");
        lua_createtable(L, 12, 0);
        size_t pos = 1;
        for (size_t j = 0; j < 12; j++)
        {
            if (frame_gsa.sats[j] == 0)
                continue;
            
            lua_pushinteger(L, frame_gsa.sats[j]);
            lua_seti(L, -2, pos);
            pos ++;
        }
        lua_settable(L, -3);
        lua_seti(L, -2, count);
    }
    return 1;
}
static int l_libgnss_get_gsa(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (1 == mode) {
        return l_libgnss_get_gsa_mode1(L);
    }
    else {
        return l_libgnss_get_gsa_mode0(L);
    }
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
-- 提醒: Air780EG和Air510U,在速度<5km/h时, 不会返回方向角
]]
 */
static int l_libgnss_get_vtg(lua_State *L) {
    int mode = luaL_optinteger(L, 1, 0);
    lua_settop(L, 0);
    if (gnssctx.vtg == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, gnssctx.vtg->data);
        return 1;
    }
    lua_createtable(L, 0, 10);
    struct minmea_sentence_vtg frame_vtg = {0};
    minmea_parse_vtg(&frame_vtg, gnssctx.vtg->data);

    // lua_pushliteral(L, "faa_mode");
    // lua_pushlstring(L, gnssctx.frame_vtg.faa_mode, 1);
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
    if (gnssctx.zda != NULL) {
        struct minmea_sentence_zda frame_zda = {0};
        minmea_parse_zda(&frame_zda, gnssctx.zda->data);

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
    log.info("GGA", json.encode(gga, "11g"))
end
--实例输出
--[[
{
    "dgps_age":0,             // 差分校正时延，单位为秒
    "fix_quality":1,          // 定位状态标识 0 - 无效,1 - 单点定位,2 - 差分定位
    "satellites_tracked":14,  // 参与定位的卫星数量
    "altitude":0.255,         // 海平面分离度, 或者成为海拔, 单位是米,
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
    if (gnssctx.gga == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, gnssctx.gga->data);
        return 1;
    }
    lua_newtable(L);
    struct minmea_sentence_gga frame_gga = {0};
    minmea_parse_gga(&frame_gga, gnssctx.gga->data);

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
    log.info("GLL", json.encode(gll, "11g"))
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
    if (gnssctx.gll == NULL)
        return 0;
    if (mode == 3) {
        lua_pushstring(L, gnssctx.vtg->data);
        return 1;
    }
    lua_newtable(L);
    struct minmea_sentence_gll frame_gll = {0};
    minmea_parse_gll(&frame_gll, gnssctx.gll->data);

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
    memset(&gnssctx.frame_rmc, 0, sizeof(struct minmea_sentence_rmc));
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
    float lat_f = minmea_tofloat(&gnssctx.frame_rmc.latitude);
    float lng_f = minmea_tofloat(&gnssctx.frame_rmc.longitude);
    switch (mode)
    {
    case 0:
        snprintf_(buff, 63, "%.7g,%c,%.7g,%c,1.0", 
                            fabs(lat_f), lat_f > 0 ? 'N' : 'S', 
                            fabs(lng_f), lng_f > 0 ? 'E' : 'W');
        break;
    case 1:
        snprintf_(buff, 63, "%d,%d", gnssctx.frame_rmc.latitude.value, gnssctx.frame_rmc.longitude.value);
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
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1)) {
        gnssctx.rtc_auto = 1;
        LLOGD("GNSS->RTC Auto-Set now is ON");
    }
    else {
        gnssctx.rtc_auto = 0;
        LLOGD("GNSS->RTC Auto-Set now is OFF");
    }
    return 0;
}

static int l_libgnss_data_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    // lua_getglobal(L, "sys_pub");
    lua_geti(L, LUA_REGISTRYINDEX, msg->arg2);
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

int luat_libgnss_on_rawdata(const char* data, size_t len, int type) {
    int cb = 0;
    if (type == 0) {
        if (gnss_raw_cb == 0)
            return 0;
        cb = gnss_raw_cb;
    }
    else if (type == 1) {
        if (gnss_txt_cb == 0)
            return 0;
        cb = gnss_txt_cb;
    }
    else if (type == 2) {
        if (gnss_other_cb == 0)
            return 0;
        cb = gnss_other_cb;
    }
    else {
        return 0;
    }
    char* ptr = luat_heap_malloc(len);
    if (ptr == NULL)
        return 0;
    memcpy(ptr, data, len);
    rtos_msg_t msg = {
        .handler = l_libgnss_data_cb,
        .arg1 = len,
        .arg2 = cb,
        .ptr = ptr
    };
    luat_msgbus_put(&msg, 0);
    return 0;
}

/**
底层事件回调
@api libgnss.on(tp, fn)
@string 事件类型,当前支持"raw"
@usage
-- 本函数一般用于调试, 用于获取底层实际收到的数据
libgnss.on("raw", function(data)
    log.info("GNSS", data)
end)
 */
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
    else if (!strcmp("txt", tp)) {
        if (gnss_txt_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, gnss_txt_cb);
            gnss_txt_cb = 0;
        }
        if (lua_isfunction(L, 2)) {
            lua_pushvalue(L, 2);
            gnss_txt_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    else if (!strcmp("other", tp)) {
        if (gnss_other_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, gnss_other_cb);
            gnss_other_cb = 0;
        }
        if (lua_isfunction(L, 2)) {
            lua_pushvalue(L, 2);
            gnss_other_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        }
    }
    return 0;
}

/**
获取非标的GPTXT数据
@api libgnss.getTxt()
@return GPTXT所携带的字符串
@usage
-- 本函数于2023.6.6 添加
log.info("gnss", "txt", libgnss.getTxt())

-- 测试语句
libgnss.parse("$GPTXT,01,01,01,ANTENNA SHORT*63\r\n")
log.info("GNSS", libgnss.getTxt())
libgnss.parse("$GPTXT,01,01,01,ANTENNA OPEN*25\r\n")
log.info("GNSS", libgnss.getTxt())
libgnss.parse("$GPTXT,01,01,01,ANTENNA OK*35\r\n")
log.info("GNSS", libgnss.getTxt())
 */
static int l_libgnss_get_txt(lua_State *L) {
    if (gnssctx.txt == NULL) {
        lua_pushliteral(L, "");
        return 1;
    }
    struct minmea_sentence_txt txt = {0};
    minmea_parse_txt(&txt, gnssctx.txt->data);
    txt.txt[FRAME_TXT_MAX_LEN] = 0x00;
    lua_pushstring(L, txt.txt);
    return 1;
}

/*
合成Air530Z所需要的辅助定位数据
@api libgnss.casic_aid(dt, loc)
@table 时间信息
@table 经纬度及海拔
@return string 辅助定位数据
@usage
-- 本函数适合CASIC系列GNSS模块的辅助定位信息的合成
-- 本函数 2023.11.14 新增

-- 首先是时间信息,注意是UTC时间
-- 时间来源很多, 一般建议socket.sntp()时间同步后的系统时间
local dt = os.date("!*t")

-- 然后是辅助定位坐标
-- 来源有很多方式:
-- 1. 从历史定位数据得到, 例如之前定位成功后保存到本地文件系统了
-- 2. 通过基站定位或者wifi定位获取到
-- 3. 通过IP定位获取到大概坐标
-- 坐标系是WGS84, 但鉴于是辅助定位,精度不是关键因素
local lla = {
    lat = 23.12,
    lng = 114.12
}

local aid = libgnss.casic_aid(dt, lla)
*/
#include "luat_casic_gnss.h"
double strtod(const char *s,char **ptr);
static int l_libgnss_casic_aid(lua_State* L) {
    DATETIME_STR dt = {0};
    POS_LLA_STR lla = {0};
    const char* data = "";

    if (lua_istable(L, 1)) {
        if (LUA_TNUMBER == lua_getfield(L, 1, "day")) {
            dt.day = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);
        // 这里兼容month和mon两种, os.date 和 rtc.get
        if (LUA_TNUMBER == lua_getfield(L, 1, "month")) {
            dt.month = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);
        if (LUA_TNUMBER == lua_getfield(L, 1, "mon")) {
            dt.month = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);

        if (LUA_TNUMBER == lua_getfield(L, 1, "year")) {
            dt.year = lua_tointeger(L, -1);
            if (dt.year > 2022)
                dt.valid = 1;
        };
        lua_pop(L, 1);
        if (LUA_TNUMBER == lua_getfield(L, 1, "hour")) {
            dt.hour = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);
        if (LUA_TNUMBER == lua_getfield(L, 1, "min")) {
            dt.minute = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);
        if (LUA_TNUMBER == lua_getfield(L, 1, "sec")) {
            dt.second = lua_tointeger(L, -1);
        };
        lua_pop(L, 1);
    }
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "lat");
        if (LUA_TNUMBER == lua_type(L, -1)) {
            lla.lat = lua_tonumber(L, -1);
        }
        else if (LUA_TSTRING == lua_type(L, -1)) {
            data = luaL_checkstring(L, -1);
            lla.lat = strtod(data, NULL);
        }
        lua_pop(L, 1);

        lua_getfield(L, 2, "lng");
        if (LUA_TNUMBER == lua_type(L, -1)) {
            lla.lon = lua_tonumber(L, -1);
        }
        else if (LUA_TSTRING == lua_type(L, -1)) {
            data = luaL_checkstring(L, -1);
            lla.lon = strtod(data, NULL);
        }
        lua_pop(L, 1);
        if (LUA_TNUMBER == lua_getfield(L, 2, "alt")) {
            lla.alt = lua_tonumber(L, -1);
        };

        if (lla.lat > 0.001 || lla.lat < -0.01)
            if (lla.lon > 0.001 || lla.lon < -0.01)
                lla.valid = 1;
    }
    char tmp[66] = {0};
    casicAgnssAidIni(&dt, &lla, tmp);
    lua_pushlstring(L, tmp, 66);
    return 1;
};

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

    { "getTxt", ROREG_FUNC(l_libgnss_get_txt)},
    { "casic_aid",   ROREG_FUNC(l_libgnss_casic_aid)},

	{ NULL,      ROREG_INT(0)}
};

LUAMOD_API int luaopen_libgnss( lua_State *L ) {
    luat_newlib2(L, reg_libgnss);
    return 1;
}
