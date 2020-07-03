
/*
@module  libgnss
@summary NMEA数据处理
@version 1.0
@data    2020.07.03
*/
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "luat.gnss"
#include "luat_log.h"

#include "minmea.h"

struct minmea_sentence_rmc frame_rmc = {0};
struct minmea_sentence_gga frame_gga = {0};
struct minmea_sentence_gsv frame_gsv = {0};

static int parse_nmea(const char* line) {
    // $GNRMC,080313.00,A,2324.40756,N,11313.86184,E,0.284,,010720,,,A*68
    // LLOGD(">> %s", line);
    switch (minmea_sentence_id(line, false)) {
        case MINMEA_SENTENCE_RMC: {
            //struct minmea_sentence_rmc frame;
            if (minmea_parse_rmc(&frame_rmc, line)) {
                // LLOGD("$RMC: raw coordinates and speed: (%d/%d,%d/%d) %d/%d",
                //         frame_rmc.latitude.value, frame_rmc.latitude.scale,
                //         frame_rmc.longitude.value, frame_rmc.longitude.scale,
                //         frame_rmc.speed.value, frame_rmc.speed.scale);
                // LLOGD("$RMC fixed-point coordinates and speed scaled to three decimal places: (%d,%d) %d",
                //         minmea_rescale(&frame_rmc.latitude, 1000),
                //         minmea_rescale(&frame_rmc.longitude, 1000),
                //         minmea_rescale(&frame_rmc.speed, 1000));
                // LLOGD("$RMC floating point degree coordinates and speed: (%f,%f) %f",
                //         minmea_tocoord(&frame_rmc.latitude),
                //         minmea_tocoord(&frame_rmc.longitude),
                //         minmea_tofloat(&frame_rmc.speed));
            }
        } break;

        case MINMEA_SENTENCE_GGA: {
            //struct minmea_sentence_gga frame;
            if (minmea_parse_gga(&frame_gga, line)) {
                //LLOGD("$GGA: fix quality: %d", frame_gga.fix_quality);
            }
        } break;

        case MINMEA_SENTENCE_GSV: {
            if (minmea_parse_gsv(&frame_gsv, line)) {
                // LLOGD("$GSV: message %d of %d", frame_gsv.msg_nr, frame_gsv.total_msgs);
                // LLOGD("$GSV: sattelites in view: %d", frame_gsv.total_sats);
                // for (int i = 0; i < 4; i++)
                //     LLOGD("$GSV: sat nr %d, elevation: %d, azimuth: %d, snr: %d dbm",
                //         frame_gsv.sats[i].nr,
                //         frame_gsv.sats[i].elevation,
                //         frame_gsv.sats[i].azimuth,
                //         frame_gsv.sats[i].snr);
            }
        } break;
    }
    return 0;
}

static int l_libgnss_parse(lua_State *L) {
    size_t len = 0;
    const char* str = luaL_checklstring(L, 1, &len);
    if (len == 0) {
        return 0;
    }
    char buff[85] = {0}; // nmea 最大长度82,含换行符
    char *ptr = (char*)str;
    size_t prev = 0;
    for (size_t i = 1; i < len; i++)
    {
        if (*(ptr + i) == 0x0A) {
            if (i - prev > 10 && i - prev < 82) {
                memcpy(buff, ptr + prev, i - prev - 1);
                if (buff[0] == '$') {
                    buff[i - prev - 1] = 0; // 确保结束符存在
                    parse_nmea((const char*)buff);
                }
            }
            i ++;
            prev = i;
        }
    }
    
    return 0;
}

static int l_libgnss_is_fix(lua_State *L) {
    lua_pushboolean(L, frame_rmc.valid);
    return 1;
}

static int l_libgnss_get_int_location(lua_State *L) {
    if (frame_rmc.valid) {
        lua_pushinteger(L, frame_rmc.latitude.value);
        lua_pushinteger(L, frame_rmc.longitude.value);
        lua_pushinteger(L, frame_rmc.speed.value);
    } else {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
    }
    return 3;
}

static int l_libgnss_get_rmc(lua_State *L) {
    lua_createtable(L, 0, 12);

    lua_pushliteral(L, "valid");
    lua_pushboolean(L, frame_rmc.valid);
    lua_settable(L, -3);

    lua_pushliteral(L, "lat");
    lua_pushinteger(L, frame_rmc.latitude.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "lng");
    lua_pushinteger(L, frame_rmc.longitude.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed");
    lua_pushinteger(L, frame_rmc.speed.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "course");
    lua_pushinteger(L, frame_rmc.course.value);
    lua_settable(L, -3);


    lua_pushliteral(L, "variation");
    lua_pushinteger(L, frame_rmc.variation.value);
    lua_settable(L, -3);

    lua_pushliteral(L, "year");
    lua_pushinteger(L, frame_rmc.date.year + 2000);
    lua_settable(L, -3);

    lua_pushliteral(L, "month");
    lua_pushinteger(L, frame_rmc.date.month);
    lua_settable(L, -3);

    lua_pushliteral(L, "day");
    lua_pushinteger(L, frame_rmc.date.day);
    lua_settable(L, -3);

    lua_pushliteral(L, "hour");
    lua_pushinteger(L, frame_rmc.time.hours);
    lua_settable(L, -3);

    lua_pushliteral(L, "min");
    lua_pushinteger(L, frame_rmc.time.minutes);
    lua_settable(L, -3);

    lua_pushliteral(L, "sec");
    lua_pushinteger(L, frame_rmc.time.seconds);
    lua_settable(L, -3);

    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_libgnss[] =
{
    { "parse", l_libgnss_parse, 0},
    { "isFix", l_libgnss_is_fix, 0},
    { "getIntLocation", l_libgnss_get_int_location, 0},
    { "getRmc", l_libgnss_get_rmc, 0},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_libgnss( lua_State *L ) {
    rotable_newlib(L, reg_libgnss);
    return 1;
}
