
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

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"
#define RECV_BUFF_SIZE (2048)

void luat_uart_set_app_recv(int id, luat_uart_recv_callback_t cb);

typedef struct luat_libgnss
{
    uint8_t debug;
    uint8_t prev_fixed;
    // int lua_ref;
    struct minmea_sentence_rmc frame_rmc;
    struct minmea_sentence_gga frame_gga;
    struct minmea_sentence_gll frame_gll;
    struct minmea_sentence_gst frame_gst;
    struct minmea_sentence_gsv frame_gsv[3];
    struct minmea_sentence_vtg frame_vtg;
    struct minmea_sentence_gsa frame_gsa;
    struct minmea_sentence_zda frame_zda;
} luat_libgnss_t;

static luat_libgnss_t *gnss = NULL;
static luat_libgnss_t *gnsstmp = NULL;

static int parse_nmea(const char* line);
static int parse_data(const char* data, size_t len);

static char *recvbuff;
static void nmea_uart_recv_cb(int uart_id, uint32_t data_len) {
    (void)data_len;
    if (recvbuff == NULL)
        return;
    LLOGD("uart recv cb");
    int len = 0;
    while (1) {
        len = luat_uart_read(uart_id, recvbuff, RECV_BUFF_SIZE - 1);
        if (len < 1 || len > RECV_BUFF_SIZE)
            break;
        LLOGD("uart recv %d", len);
        recvbuff[len] = 0;
        if (gnss == NULL)
            continue;
        if (gnss->debug) {
            LLOGD("recv %s", recvbuff);
        }
        parse_data(recvbuff, len);
    }
}

static uint32_t msg_counter[MINMEA_SENTENCE_MAX_ID];

static int luat_libgnss_init(void) {
    if (gnss == NULL) {
        gnss = luat_heap_malloc(sizeof(luat_libgnss_t));
        if (gnss == NULL) {
            LLOGW("out of memory for libgnss data parse");
            return 0;
        }
        gnsstmp = luat_heap_malloc(sizeof(luat_libgnss_t));
        if (gnsstmp == NULL) {
            luat_heap_free(gnss);
            LLOGW("out of memory for libgnss data parse");
            return 0;
        }
        // gnss->lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        memset(gnss, 0, sizeof(luat_libgnss_t));
        memset(gnsstmp, 0, sizeof(luat_libgnss_t));
    }
    //lua_pushboolean(L, 1);
    return 1;
}

static int parse_data(const char* data, size_t len) {
    size_t prev = 0;
    static char nmea_tmp_buff[86] = {0}; // nmea 最大长度82,含换行符
    for (size_t offset = 0; offset < len; offset++)
    {
        // \r == 0x0D  \n == 0x0A
        if (data[offset] == 0x0A) {
            // 最短也需要是 OK\r\n
            // 应该\r\n的
            // 太长了
            if (offset - prev < 3 || data[offset - 1] != 0x0D || offset - prev > 82) {
                prev = offset + 1;
                continue;
            }
            memcpy(nmea_tmp_buff, data + prev, offset - prev - 1);
            nmea_tmp_buff[offset - prev - 1] = 0x00;
            if (gnss->debug) {
                LLOGD(">> %s", nmea_tmp_buff);
            }
            parse_nmea((const char*)nmea_tmp_buff);
            prev = offset + 1;
        }
    }
    return 0;
}

static int parse_nmea(const char* line) {
    // $GNRMC,080313.00,A,2324.40756,N,11313.86184,E,0.284,,010720,,,A*68
    //if (gnss != NULL && gnss->debug)
    //    LLOGD("GNSS [%s]", line);
    if (gnss == NULL && !luat_libgnss_init()) {
        return 0;
    }
    struct minmea_sentence_gsv frame_gsv = {0};
    enum minmea_sentence_id id = minmea_sentence_id(line, false);
    if (id == MINMEA_UNKNOWN || id >= MINMEA_SENTENCE_MAX_ID || id == MINMEA_INVALID)
        return -1;
    msg_counter[id] ++;
    switch (id) {
        case MINMEA_SENTENCE_RMC: {
            if (minmea_parse_rmc(&(gnsstmp->frame_rmc), line)) {
                if (gnsstmp->frame_rmc.valid) {
                    memcpy(&(gnss->frame_rmc), &gnsstmp->frame_rmc, sizeof(struct minmea_sentence_rmc));
                }
                else {
                    gnss->frame_rmc.valid = 0;
                    if (gnsstmp->frame_rmc.date.year > 0) {
                        memcpy(&(gnss->frame_rmc.date), &(gnsstmp->frame_rmc.date), sizeof(struct minmea_date));
                    }
                    if (gnsstmp->frame_rmc.time.hours > 0) {
                        memcpy(&(gnss->frame_rmc.time), &(gnsstmp->frame_rmc.time), sizeof(struct minmea_time));
                    }
                }
                //memcpy(&(gnss->frame_rmc), &frame_rmc, sizeof(struct minmea_sentence_rmc));
                //LLOGD("RMC %s", line);
                //LLOGD("RMC isFix(%d) Lat(%ld) Lng(%ld)", gnss->frame_rmc.valid, gnss->frame_rmc.latitude.value, gnss->frame_rmc.longitude.value);
                // if (prev_gnss_fixed != gnss->frame_rmc.valid) {
                //     lua_getglobal(L, "sys_pub");
                //     if (lua_isfunction(L, -1)) {
                //         lua_pushliteral(L, "GPS_STATE");
                //         lua_pushstring(L, gnss->frame_rmc.valid ? "LOCATION_SUCCESS" : "LOCATION_FAIL");
                //         lua_call(L, 2, 0);
                //     }
                //     else {
                //         lua_pop(L, 1);
                //     }
                //     prev_gnss_fixed = gnss->frame_rmc.valid;
                // }
            }
        } break;

        case MINMEA_SENTENCE_GGA: {
            //struct minmea_sentence_gga frame_gga;
            if (minmea_parse_gga(&gnsstmp->frame_gga, line)) {
                memcpy(&(gnss->frame_gga), &gnsstmp->frame_gga, sizeof(struct minmea_sentence_gga));
                //LLOGD("$GGA: fix quality: %d", frame_gga.fix_quality);
            }
        } break;

        case MINMEA_SENTENCE_GSA: {
            if (minmea_parse_gsa(&(gnss->frame_gsa), line)) {

            }
        } break;

        case MINMEA_SENTENCE_GLL: {
            if (minmea_parse_gll(&(gnss->frame_gll), line)) {
                // memcpy(&(gnss->frame_gll), &frame_gll, sizeof(struct minmea_sentence_gsa));
            }
        } break;

        // case MINMEA_SENTENCE_GST: {
        //     if (minmea_parse_gst(&gnsstmp->frame_gst, line)) {
        //         memcpy(&(gnss->frame_gst), &gnsstmp->frame_gst, sizeof(struct minmea_sentence_gst));
        //     }
        // } break;

        case MINMEA_SENTENCE_GSV: {
            //LLOGD("Got GSV : %s", line);
            if (minmea_parse_gsv(&frame_gsv, line)) {
                //LLOGD("$GSV: message %d of %d", frame_gsv.msg_nr, frame_gsv.total_msgs);
                if (frame_gsv.msg_nr == 1) {
                    //LLOGD("Clean GSV");
                    memset(&(gnss->frame_gsv), 0, sizeof(struct minmea_sentence_gsv) * 3);
                }
                if (frame_gsv.msg_nr >= 1 && frame_gsv.msg_nr <= 3) {
                    //LLOGD("memcpy GSV %d", frame_gsv.msg_nr);
                    memcpy(&(gnss->frame_gsv[frame_gsv.msg_nr - 1]), &frame_gsv, sizeof(struct minmea_sentence_gsv));
                }
                // LLOGD("$GSV: message %d of %d", frame_gsv.msg_nr, frame_gsv.total_msgs);
                // LLOGD("$GSV: sattelites in view: %d", frame_gsv.total_sats);
                // for (int i = 0; i < 4; i++)
                //     LLOGD("$GSV: sat nr %d, elevation: %d, azimuth: %d, snr: %d dbm",
                //         frame_gsv.sats[i].nr,
                //         frame_gsv.sats[i].elevation,
                //         frame_gsv.sats[i].azimuth,
                //         frame_gsv.sats[i].snr);
            }
            else {
                //LLOGD("bad GSV %s", line);
            }
        } break;

        case MINMEA_SENTENCE_VTG: {
            //struct minmea_sentence_vtg frame_vtg;
            if (minmea_parse_vtg(&(gnsstmp->frame_vtg), line)) {
                memcpy(&(gnss->frame_vtg), &gnsstmp->frame_vtg, sizeof(struct minmea_sentence_vtg));
                //--------------------------------------
                // 暂时不发GPS_MSG_REPORT
                // lua_getglobal(L, "sys_pub");
                // if (lua_isfunction(L, -1)) {
                //     lua_pushstring(L, "GPS_MSG_REPORT");
                //     lua_call(L, 1, 0);
                // }
                // else {
                //     lua_pop(L, 1);
                // }
                //--------------------------------------
            }
        } break;
        case MINMEA_SENTENCE_ZDA: {
            if (minmea_parse_zda(&(gnsstmp->frame_zda), line)) {
                memcpy(&(gnss->frame_zda), &gnsstmp->frame_zda, sizeof(struct minmea_sentence_zda));
            }
        } break;
        default:
            //LLOGD("why happen");
            break;
    }
    return 0;
}

/**
处理nmea数据
@api libgnss.parse(str)
@string 原始nmea数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", json.encode(libgnss.getRmc()))
 */
static int l_libgnss_parse(lua_State *L) {
    size_t len = 0;
    const char* str = luaL_checklstring(L, 1, &len);
    if (len > 0) {
        parse_data(str, len);
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
    if (gnss == NULL) {
        lua_pushboolean(L, 0);
    }
    else
        lua_pushboolean(L, gnss->frame_rmc.valid != 0 ? 1 : 0);
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
    if (gnss != NULL && gnss->frame_rmc.valid) {
        lua_pushinteger(L, minmea_tofloat(&(gnss->frame_rmc.latitude)));
        lua_pushinteger(L, minmea_tofloat(&(gnss->frame_rmc.longitude)));
        lua_pushinteger(L, gnss->frame_rmc.speed.value);
    } else {
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
        lua_pushinteger(L, 0);
    }
    return 3;
}

/**
获取原始RMC位置信息
@api libgnss.getRmc()
@return table 原始rmc数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "rmc", json.encode(libgnss.getRmc()))
 */
static int l_libgnss_get_rmc(lua_State *L) {
    lua_createtable(L, 0, 12);

    if (gnss != NULL) {

        lua_pushliteral(L, "valid");
        lua_pushboolean(L, gnss->frame_rmc.valid);
        lua_settable(L, -3);

        lua_pushliteral(L, "lat");
        lua_pushnumber(L, minmea_tofloat(&(gnss->frame_rmc.latitude)));
        lua_settable(L, -3);

        lua_pushliteral(L, "lng");
        lua_pushnumber(L, minmea_tofloat(&(gnss->frame_rmc.longitude)));
        lua_settable(L, -3);

        lua_pushliteral(L, "speed");
        lua_pushinteger(L, gnss->frame_rmc.speed.value);
        lua_settable(L, -3);

        lua_pushliteral(L, "course");
        lua_pushinteger(L, gnss->frame_rmc.course.value);
        lua_settable(L, -3);


        lua_pushliteral(L, "variation");
        lua_pushinteger(L, gnss->frame_rmc.variation.value);
        lua_settable(L, -3);

        lua_pushliteral(L, "year");
        lua_pushinteger(L, gnss->frame_rmc.date.year + 2000);
        lua_settable(L, -3);

        lua_pushliteral(L, "month");
        lua_pushinteger(L, gnss->frame_rmc.date.month);
        lua_settable(L, -3);

        lua_pushliteral(L, "day");
        lua_pushinteger(L, gnss->frame_rmc.date.day);
        lua_settable(L, -3);

        lua_pushliteral(L, "hour");
        lua_pushinteger(L, gnss->frame_rmc.time.hours);
        lua_settable(L, -3);

        lua_pushliteral(L, "min");
        lua_pushinteger(L, gnss->frame_rmc.time.minutes);
        lua_settable(L, -3);

        lua_pushliteral(L, "sec");
        lua_pushinteger(L, gnss->frame_rmc.time.seconds);
        lua_settable(L, -3);
    }

    return 1;
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

    if (gnss != NULL) {
        int count = 1;
        lua_pushliteral(L, "total_sats");
        lua_pushinteger(L, gnss->frame_gsv[0].total_sats);
        lua_settable(L, -3);

        lua_pushliteral(L, "sats");
        lua_createtable(L, 12, 0);
        for (size_t i = 0; i < 3; i++)
        {
            for (size_t j = 0; j < 4; j++)
            {
                //LLOGD("nr %d snr %d", gnss->frame_gsv[i].sats[j].nr, gnss->frame_gsv[i].sats[j].snr);
                if (gnss->frame_gsv[i].sats[j].nr) {
                    lua_pushinteger(L, count++);
                    lua_createtable(L, 0, 4);

                    lua_pushliteral(L, "nr");
                    lua_pushinteger(L, gnss->frame_gsv[i].sats[j].nr);
                    lua_settable(L, -3);

                    lua_pushliteral(L, "snr");
                    lua_pushinteger(L, gnss->frame_gsv[i].sats[j].snr);
                    lua_settable(L, -3);

                    lua_pushliteral(L, "elevation");
                    lua_pushinteger(L, gnss->frame_gsv[i].sats[j].elevation);
                    lua_settable(L, -3);

                    lua_pushliteral(L, "azimuth");
                    lua_pushinteger(L, gnss->frame_gsv[i].sats[j].azimuth);
                    lua_settable(L, -3);

                    lua_settable(L, -3);
                }
            }
        }
        lua_settable(L, -3);
    }

    return 1;
}


/**
获取原始GSA信息
@api libgnss.getGsa()
@return table 原始GSA数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "gsa", json.encode(libgnss.getGsa()))
 */
static int l_libgnss_get_gsa(lua_State *L) {
    lua_createtable(L, 0, 10);

    //lua_pushliteral(L, "mode");
    //lua_pushlstring(L, gnss ? &(gnss->frame_gsa.mode) : "N", 1);
    //lua_settable(L, -3);

    lua_pushliteral(L, "fix_type");
    lua_pushinteger(L, gnss ? gnss->frame_gsa.fix_type : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "pdop");
    lua_pushinteger(L, gnss ? gnss->frame_gsa.pdop.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "hdop");
    lua_pushinteger(L, gnss ? gnss->frame_gsa.hdop.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "vdop");
    lua_pushinteger(L, gnss ? gnss->frame_gsa.vdop.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "sats");
    lua_createtable(L, 12, 0);
    if (gnss != NULL) {
        for (size_t i = 0; i < 12; i++) {
            if (gnss->frame_gsa.sats[i] == 0) break;
            lua_pushinteger(L, i + 1);
            lua_pushinteger(L, gnss->frame_gsa.sats[i]);
            lua_settable(L, -3);
        }
    }

    lua_settable(L, -3);

    return 1;
}


/**
获取原始VTA位置信息
@api libgnss.getVtg()
@return table 原始VTA数据
@usage
-- 解析nmea
libgnss.parse(indata)
log.info("nmea", "vtg", json.encode(libgnss.getVtg()))
 */
static int l_libgnss_get_vtg(lua_State *L) {
    lua_createtable(L, 0, 10);

    //lua_pushliteral(L, "faa_mode");
    //lua_pushlstring(L, gnss ? &(gnss->frame_vtg.faa_mode) : 'N', 1);
    //lua_settable(L, -3);

    lua_pushliteral(L, "true_track_degrees");
    lua_pushinteger(L, gnss ? gnss->frame_vtg.true_track_degrees.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "magnetic_track_degrees");
    lua_pushinteger(L, gnss ? gnss->frame_vtg.magnetic_track_degrees.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_knots");
    lua_pushinteger(L, gnss ? gnss->frame_vtg.speed_knots.value : 0);
    lua_settable(L, -3);

    lua_pushliteral(L, "speed_kph");
    lua_pushinteger(L, gnss ? gnss->frame_vtg.speed_kph.value : 0);
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

    if (gnss != NULL) {

        lua_pushliteral(L, "hour_offset");
        lua_pushinteger(L, gnss->frame_zda.hour_offset);
        lua_settable(L, -3);

        lua_pushliteral(L, "minute_offset");
        lua_pushinteger(L, gnss->frame_zda.minute_offset);
        lua_settable(L, -3);

        lua_pushliteral(L, "year");
        lua_pushinteger(L, gnss->frame_zda.date.year);
        lua_settable(L, -3);

        lua_pushliteral(L, "month");
        lua_pushinteger(L, gnss->frame_zda.date.month);
        lua_settable(L, -3);

        lua_pushliteral(L, "day");
        lua_pushinteger(L, gnss->frame_zda.date.day);
        lua_settable(L, -3);

        lua_pushliteral(L, "hour");
        lua_pushinteger(L, gnss->frame_zda.time.hours);
        lua_settable(L, -3);

        lua_pushliteral(L, "min");
        lua_pushinteger(L, gnss->frame_zda.time.minutes);
        lua_settable(L, -3);

        lua_pushliteral(L, "sec");
        lua_pushinteger(L, gnss->frame_zda.time.seconds);
        lua_settable(L, -3);

        lua_pushliteral(L, "mic");
        lua_pushinteger(L, gnss->frame_zda.time.microseconds);
        lua_settable(L, -3);
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
    if (gnss == NULL && luat_libgnss_init()) {
        return 0;
    }
    if (lua_isboolean(L, 1) && lua_toboolean(L, 1)) {
        LLOGD("Debug ON");
        gnss->debug = 1;
    }
    else
    {
        LLOGD("Debug OFF");
        gnss->debug = 0;
    }

    return 0;
}

/*
获取GGA数据
@api libgnss.getGga()
@return table GGA数据, 若如不存在会返回nil
local gga = libgnss.getGga()
if gga then
    log.info("GGA", json.encode(gga))
end
*/
static int l_libgnss_get_gga(lua_State* L) {
    if (gnss == NULL)
        return 0;
    lua_newtable(L);

    lua_pushstring(L, "altitude");
    lua_pushinteger(L, gnss->frame_gga.altitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "latitude");
    lua_pushinteger(L, gnss->frame_gga.latitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    lua_pushinteger(L, gnss->frame_gga.longitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "fix_quality");
    lua_pushinteger(L, gnss->frame_gga.fix_quality);
    lua_settable(L, -3);

    lua_pushstring(L, "satellites_tracked");
    lua_pushinteger(L, gnss->frame_gga.satellites_tracked);
    lua_settable(L, -3);

    lua_pushstring(L, "hdop");
    lua_pushinteger(L, gnss->frame_gga.hdop.value);
    lua_settable(L, -3);

    lua_pushstring(L, "height");
    lua_pushinteger(L, gnss->frame_gga.height.value);
    lua_settable(L, -3);

    lua_pushstring(L, "dgps_age");
    lua_pushinteger(L, gnss->frame_gga.dgps_age.value);
    lua_settable(L, -3);

    return 1;
}

/*
获取GLL数据
@api libgnss.getGll()
@return table GLL数据, 若如不存在会返回nil
local gll = libgnss.getGll()
if gll then
    log.info("GLL", json.encode(gll))
end
*/
static int l_libgnss_get_gll(lua_State* L) {
    if (gnss == NULL)
        return 0;
    lua_newtable(L);

    lua_pushstring(L, "latitude");
    lua_pushinteger(L, gnss->frame_gll.latitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "longitude");
    lua_pushinteger(L, gnss->frame_gll.longitude.value);
    lua_settable(L, -3);

    lua_pushstring(L, "mode");
    lua_pushinteger(L, gnss->frame_gll.mode);
    lua_settable(L, -3);

    lua_pushstring(L, "status");
    lua_pushinteger(L, gnss->frame_gll.status);
    lua_settable(L, -3);

    lua_pushstring(L, "hour");
    lua_pushinteger(L, gnss->frame_gll.time.hours);
    lua_settable(L, -3);
    lua_pushstring(L, "us");
    lua_pushinteger(L, gnss->frame_gll.time.microseconds);
    lua_settable(L, -3);
    lua_pushstring(L, "min");
    lua_pushinteger(L, gnss->frame_gll.time.minutes);
    lua_settable(L, -3);
    lua_pushstring(L, "sec");
    lua_pushinteger(L, gnss->frame_gll.time.seconds);
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
    if (gnss == NULL && !luat_libgnss_init())
        return 0;
    memset(gnss, 0, sizeof(luat_libgnss_t));
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
    if (recvbuff == NULL) {
        recvbuff = luat_heap_malloc(2048);
    }
    if (luat_uart_exist(uart_id)) {
        //uart_app_recvs[uart_id] = nmea_uart_recv_cb;
        luat_uart_set_app_recv(uart_id, nmea_uart_recv_cb);
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
