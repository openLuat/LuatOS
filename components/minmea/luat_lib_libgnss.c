
/*
@module  libgnss
@summary NMEA数据处理
@version 1.0
@date    2020.07.03
@demo libgnss
@tag LUAT_USE_LIBGNSS
@usage
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
extern luat_libgnss_t *libgnss_gnsstmp;
extern char* libgnss_recvbuff;

void luat_uart_set_app_recv(int id, luat_uart_recv_callback_t cb);

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
-- 解析nmea
libgnss.parse(indata)
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
@return int lat数据, 格式为 ddmmmmmmm
@return int lng数据, 格式为 ddmmmmmmm
@return int speed数据
@usage
-- 解析nmea
libgnss.parse(indata)
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
@api libgnss.getRmc(use_float)
@bool 输出浮点数据,默认true, 如需输出整型,请填false
@return table 原始rmc数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "rmc", json.encode(libgnss.getRmc()))
 */
static int l_libgnss_get_rmc(lua_State *L) {
    int use_float = 1;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1) == 0)
        use_float = 0;
    lua_settop(L, 0);
    lua_createtable(L, 0, 12);

    struct tm rtime = {0};

    if (libgnss_gnss != NULL) {
        lua_pushboolean(L, libgnss_gnss->frame_rmc.valid);
        lua_setfield(L, -2, "valid");

        if (libgnss_gnss->frame_rmc.valid) {
            if (use_float && libgnss_gnss->frame_rmc.latitude.value != 0)
                lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_rmc.latitude)));
            else
                lua_pushinteger(L, libgnss_gnss->frame_rmc.latitude.value);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lat");

        if (libgnss_gnss->frame_rmc.valid) {
            if (use_float && libgnss_gnss->frame_rmc.longitude.value != 0)
                lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_rmc.longitude)));
            else
                lua_pushinteger(L, libgnss_gnss->frame_rmc.longitude.value);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "lng");

        if (libgnss_gnss->frame_rmc.valid) {
            if (use_float && libgnss_gnss->frame_rmc.speed.value != 0)
                lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_rmc.speed)));
            else
                lua_pushinteger(L, libgnss_gnss->frame_rmc.speed.value);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "speed");

        if (libgnss_gnss->frame_rmc.valid) {
            if (use_float && libgnss_gnss->frame_rmc.course.value != 0)
                lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_rmc.course)));
            else
                lua_pushinteger(L, libgnss_gnss->frame_rmc.course.value);
        }
        else
            lua_pushinteger(L, 0);
        lua_setfield(L, -2, "course");

        if (libgnss_gnss->frame_rmc.valid) {
            if (use_float && libgnss_gnss->frame_rmc.variation.value != 0)
                lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_rmc.variation)));
            else
                lua_pushinteger(L, libgnss_gnss->frame_rmc.variation.value);
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

static void add_gsv(lua_State*L, struct minmea_sentence_gsv* gsvs, size_t *count) {

    for (size_t i = 0; i < 3; i++)
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
libgnss.parse(indata)
log.info("nmea", "gsv", json.encode(libgnss.getGsv()))
 */
static int l_libgnss_get_gsv(lua_State *L) {
    lua_createtable(L, 0, 2);
    if (libgnss_gnss == NULL)
        return 1;

    size_t count = 1;

    lua_createtable(L, 12, 0);
    if (libgnss_gnss->frame_gsv_gp->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_gp, &count);
    }
    if (libgnss_gnss->frame_gsv_gb->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_gb, &count);
    }
    if (libgnss_gnss->frame_gsv_gl->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_gl, &count);
    }
    if (libgnss_gnss->frame_gsv_ga->total_sats > 0) {
        add_gsv(L, libgnss_gnss->frame_gsv_ga, &count);
    }
    lua_setfield(L, -2, "sats");

    lua_pushliteral(L, "total_sats");
    lua_pushinteger(L, count - 1);
    lua_settable(L, -3);

    return 1;
}


/**
获取原始GSA信息
@api libgnss.getGsa(use_float)
@bool 输出浮点数据,默认true, 如需输出整型,请填false
@return table 原始GSA数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "gsa", json.encode(libgnss.getGsa()))
 */
static int l_libgnss_get_gsa(lua_State *L) {
    int use_float = 1;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1) == 0)
        use_float = 0;
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
    if (use_float && libgnss_gnss->frame_gsa[0].pdop.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gsa[0].pdop)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gsa[0].pdop.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "hdop");
    if (use_float && libgnss_gnss->frame_gsa[0].hdop.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gsa[0].hdop)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gsa[0].hdop.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "vdop");
    if (use_float && libgnss_gnss->frame_gsa[0].vdop.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gsa[0].vdop)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gsa[0].vdop.value);
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
获取原始VTA位置信息
@api libgnss.getVtg(use_float)
@bool 输出浮点数据,默认true, 如需输出整型,请填false
@return table 原始VTA数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "vtg", json.encode(libgnss.getVtg()))
 */
static int l_libgnss_get_vtg(lua_State *L) {
    int use_float = 1;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1) == 0)
        use_float = 0;
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    lua_createtable(L, 0, 10);

    // lua_pushliteral(L, "faa_mode");
    // lua_pushlstring(L, libgnss_gnss->frame_vtg.faa_mode, 1);
    // lua_settable(L, -3);

    lua_pushliteral(L, "true_track_degrees");
    if (use_float && libgnss_gnss->frame_vtg.true_track_degrees.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_vtg.true_track_degrees)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_vtg.true_track_degrees.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "magnetic_track_degrees");
    if (use_float && libgnss_gnss->frame_vtg.magnetic_track_degrees.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_vtg.magnetic_track_degrees)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_vtg.magnetic_track_degrees.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_knots");
    if (use_float && libgnss_gnss->frame_vtg.speed_knots.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_vtg.speed_knots)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_vtg.speed_knots.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_kph");
    if (use_float && libgnss_gnss->frame_vtg.speed_kph.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_vtg.speed_kph)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_vtg.speed_kph.value);
    lua_settable(L, -3);

    return 1;
}

/**
获取原始ZDA时间和日期信息
@api libgnss.getZda()
@return table 原始zda数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "zda", json.encode(libgnss.getZda()))
 */
static int l_libgnss_get_zda(lua_State *L) {
    lua_createtable(L, 0, 9);
    struct tm rtime = {0};
    if (libgnss_gnss != NULL) {

        lua_pushliteral(L, "hour_offset");
        lua_pushinteger(L, libgnss_gnss->frame_zda.hour_offset);
        lua_settable(L, -3);

        lua_pushliteral(L, "minute_offset");
        lua_pushinteger(L, libgnss_gnss->frame_zda.minute_offset);
        lua_settable(L, -3);

        // 时间相关
        minmea_getdatetime(&rtime, &libgnss_gnss->frame_zda.date, &libgnss_gnss->frame_zda.time);
        put_datetime(L, &rtime);
    }

    return 1;
}

/**
设置调试模式
@api libgnss.debug(mode)
@bool true开启调试,false关闭调试,默认为false
@usage
-- 开启调试
libgnss.debug(true)
-- 关闭调试
libgnss.debug(false)
 */
static int l_libgnss_debug(lua_State *L) {
    if (libgnss_gnss == NULL && luat_libgnss_init()) {
        return 0;
    }
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1)) {
        LLOGD("Debug ON");
        libgnss_gnss->debug = 1;
    }
    else
    {
        LLOGD("Debug OFF");
        libgnss_gnss->debug = 0;
    }

    return 0;
}

/*
获取GGA数据
@api libgnss.getGga(use_float)
@bool 输出浮点数据,默认true, 如需输出整型,请填false
@return table GGA数据, 若如不存在会返回nil
local gga = libgnss.getGga()
if gga then
    log.info("GGA", json.encode(gga))
end
*/
static int l_libgnss_get_gga(lua_State* L) {
    int use_float = 1;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1) == 0)
        use_float = 0;
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    lua_newtable(L);

    lua_pushstring(L, "altitude");
    if (use_float && libgnss_gnss->frame_gga.altitude.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.altitude)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.altitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "latitude");
    if (use_float && libgnss_gnss->frame_gga.latitude.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.latitude)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.latitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    if (use_float && libgnss_gnss->frame_gga.longitude.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.longitude)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.longitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "fix_quality");
    lua_pushinteger(L, libgnss_gnss->frame_gga.fix_quality);
    lua_settable(L, -3);

    lua_pushstring(L, "satellites_tracked");
    lua_pushinteger(L, libgnss_gnss->frame_gga.satellites_tracked);
    lua_settable(L, -3);

    lua_pushstring(L, "hdop");
    if (use_float && libgnss_gnss->frame_gga.hdop.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.hdop)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.hdop.value);
    lua_settable(L, -3);

    lua_pushstring(L, "height");
    if (use_float && libgnss_gnss->frame_gga.height.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.height)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.height.value);
    lua_settable(L, -3);

    lua_pushstring(L, "dgps_age");
    if (use_float && libgnss_gnss->frame_gga.dgps_age.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gga.dgps_age)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gga.dgps_age.value);
    lua_settable(L, -3);

    return 1;
}

/*
获取GLL数据
@api libgnss.getGll(use_float)
@bool 输出浮点数据,默认true, 如需输出整型,请填false
@return table GLL数据, 若如不存在会返回nil
local gll = libgnss.getGll()
if gll then
    log.info("GLL", json.encode(gll))
end
*/
static int l_libgnss_get_gll(lua_State* L) {
    int use_float = 1;
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1) == 0)
        use_float = 0;
    lua_settop(L, 0);
    if (libgnss_gnss == NULL)
        return 0;
    lua_newtable(L);

    lua_pushstring(L, "latitude");
    if (use_float && libgnss_gnss->frame_gll.latitude.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gll.latitude)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gll.latitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    if (use_float && libgnss_gnss->frame_gll.longitude.value != 0)
        lua_pushnumber(L, minmea_tofloat(&(libgnss_gnss->frame_gll.longitude)));
    else
        lua_pushinteger(L, libgnss_gnss->frame_gll.longitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "mode");
    lua_pushfstring(L, "%c", libgnss_gnss->frame_gll.mode);
    lua_settable(L, -3);

    lua_pushstring(L, "status");
    lua_pushfstring(L, "%c", libgnss_gnss->frame_gll.status);
    lua_settable(L, -3);

    lua_pushstring(L, "hour");
    lua_pushinteger(L, libgnss_gnss->frame_gll.time.hours);
    lua_settable(L, -3);
    lua_pushstring(L, "us");
    lua_pushinteger(L, libgnss_gnss->frame_gll.time.microseconds);
    lua_settable(L, -3);
    lua_pushstring(L, "min");
    lua_pushinteger(L, libgnss_gnss->frame_gll.time.minutes);
    lua_settable(L, -3);
    lua_pushstring(L, "sec");
    lua_pushinteger(L, libgnss_gnss->frame_gll.time.seconds);
    lua_settable(L, -3);

    return 1;
}

/**
清除历史定位数据
@api libgnss.clear()
@return nil 无返回值
 */
static int l_libgnss_clear(lua_State*L) {
    (void)L;
    if (libgnss_gnss == NULL && !luat_libgnss_init())
        return 0;
    memset(libgnss_gnss, 0, sizeof(luat_libgnss_t));
    return 0;
}

/*
绑定uart端口进行GNSS数据读取
@api libgnss.bind(id)
@int uart端口号
@usage
-- 配置串口信息, 通常为 115200 8N1
uart.setup(2, 115200)
-- 绑定uart, 马上开始解析GNSS数据
libgnss.bind(2)
-- 无需再调用uart.on然后调用libgnss.parse
-- 开发期可打开调试日志
libgnss.debug(true)
*/
static int l_libgnss_bind(lua_State* L) {
    int uart_id = luaL_checkinteger(L, 1);
    l_libgnss_clear(L);
    if (libgnss_recvbuff == NULL) {
        libgnss_recvbuff = luat_heap_malloc(RECV_BUFF_SIZE);
    }
    if (luat_uart_exist(uart_id)) {
        //uart_app_recvs[uart_id] = nmea_uart_recv_cb;
        luat_uart_set_app_recv(uart_id, luat_libgnss_uart_recv_cb);
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
    
    { "debug",  ROREG_FUNC(l_libgnss_debug)},
    { "clear",  ROREG_FUNC(l_libgnss_clear)},
    { "bind",   ROREG_FUNC(l_libgnss_bind)},

	{ NULL,      ROREG_INT(0)}
};

LUAMOD_API int luaopen_libgnss( lua_State *L ) {
    luat_newlib2(L, reg_libgnss);
    return 1;
}
