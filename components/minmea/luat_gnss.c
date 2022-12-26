#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_rtc.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"

luat_libgnss_t *libgnss_gnss;
luat_libgnss_t *libgnss_gnsstmp;
char *libgnss_recvbuff;

// static int parse_nmea(const char* line);
// static int parse_data(const char* data, size_t len);

void luat_libgnss_uart_recv_cb(int uart_id, uint32_t data_len) {
    (void)data_len;
    if (libgnss_recvbuff == NULL)
        return;
    //LLOGD("uart recv cb");
    int len = 0;
    while (1) {
        len = luat_uart_read(uart_id, libgnss_recvbuff, RECV_BUFF_SIZE - 1);
        if (len < 1 || len > RECV_BUFF_SIZE)
            break;
        //LLOGD("uart recv %d", len);
        libgnss_recvbuff[len] = 0;
        if (libgnss_gnss == NULL)
            continue;
        if (libgnss_gnss->debug) {
            LLOGD("recv %s", libgnss_recvbuff);
        }
        luat_libgnss_parse_data(libgnss_recvbuff, len);
    }
}


static uint32_t msg_counter[MINMEA_SENTENCE_MAX_ID];

int luat_libgnss_init(void) {
    if (libgnss_gnss == NULL) {
        libgnss_gnss = luat_heap_malloc(sizeof(luat_libgnss_t));
        if (libgnss_gnss == NULL) {
            LLOGW("out of memory for libgnss data parse");
            return 0;
        }
        libgnss_gnsstmp = luat_heap_malloc(sizeof(luat_libgnss_t));
        if (libgnss_gnsstmp == NULL) {
            luat_heap_free(libgnss_gnss);
            LLOGW("out of memory for libgnss data parse");
            return 0;
        }
        // gnss->lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        memset(libgnss_gnss, 0, sizeof(luat_libgnss_t));
        memset(libgnss_gnsstmp, 0, sizeof(luat_libgnss_t));
    }
    //lua_pushboolean(L, 1);
    return 1;
}

int luat_libgnss_parse_data(const char* data, size_t len) {
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
            if (libgnss_gnss->debug) {
                LLOGD(">> %s", nmea_tmp_buff);
            }
            luat_libgnss_parse_nmea((const char*)nmea_tmp_buff);
            prev = offset + 1;
        }
    }
    return 0;
}

int luat_libgnss_parse_nmea(const char* line) {
    // $GNRMC,080313.00,A,2324.40756,N,11313.86184,E,0.284,,010720,,,A*68
    //if (gnss != NULL && gnss->debug)
    //    LLOGD("GNSS [%s]", line);
    if (libgnss_gnss == NULL && !luat_libgnss_init()) {
        return 0;
    }
    struct minmea_sentence_gsv frame_gsv = {0};
    enum minmea_sentence_id id = minmea_sentence_id(line, false);
    if (id == MINMEA_UNKNOWN || id >= MINMEA_SENTENCE_MAX_ID || id == MINMEA_INVALID)
        return -1;
    msg_counter[id] ++;
    // int ticks = 0;
    struct tm tblock = {0};
    int ticks = luat_mcu_ticks();
    switch (id) {
        case MINMEA_SENTENCE_RMC: {
            if (minmea_parse_rmc(&(libgnss_gnsstmp->frame_rmc), line)) {
                if (libgnss_gnsstmp->frame_rmc.valid) {
                    memcpy(&(libgnss_gnss->frame_rmc), &libgnss_gnsstmp->frame_rmc, sizeof(struct minmea_sentence_rmc));
                    #ifdef LUAT_USE_MCU
                    if (libgnss_gnss->rtc_auto && ((uint32_t)(ticks - libgnss_gnss->fix_at_ticks)) > 600*1000) {
                        LLOGI("Auto-Set RTC by GNSS RMC");
                        tblock.tm_sec =  libgnss_gnss->frame_rmc.time.seconds;
                        tblock.tm_min =  libgnss_gnss->frame_rmc.time.minutes;
                        tblock.tm_hour = libgnss_gnss->frame_rmc.time.hours;
                        tblock.tm_mday = libgnss_gnss->frame_rmc.date.day;
                        tblock.tm_mon =  libgnss_gnss->frame_rmc.date.month;
                        tblock.tm_year = libgnss_gnss->frame_rmc.date.year;
                        luat_rtc_set(&tblock);
                    }
                    if (libgnss_gnss->fix_at_ticks == 0) {
                        LLOGI("Fixed"); // TODO 发布系统消息
                    }
                    libgnss_gnss->fix_at_ticks = luat_mcu_ticks();
                    #endif
                }
                else {
                    if (libgnss_gnss->fix_at_ticks && libgnss_gnss->frame_rmc.valid) {
                        LLOGI("Lose"); // TODO 发布系统消息
                    }
                    libgnss_gnss->fix_at_ticks = 0;
                    libgnss_gnss->frame_rmc.valid = 0;
                    if (libgnss_gnsstmp->frame_rmc.date.year > 0) {
                        memcpy(&(libgnss_gnss->frame_rmc.date), &(libgnss_gnsstmp->frame_rmc.date), sizeof(struct minmea_date));
                    }
                    if (libgnss_gnsstmp->frame_rmc.time.hours > 0) {
                        memcpy(&(libgnss_gnss->frame_rmc.time), &(libgnss_gnsstmp->frame_rmc.time), sizeof(struct minmea_time));
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
            if (minmea_parse_gga(&libgnss_gnsstmp->frame_gga, line)) {
                memcpy(&(libgnss_gnss->frame_gga), &libgnss_gnsstmp->frame_gga, sizeof(struct minmea_sentence_gga));
                //LLOGD("$GGA: fix quality: %d", frame_gga.fix_quality);
            }
        } break;

        case MINMEA_SENTENCE_GSA: {
            if (minmea_parse_gsa(&(libgnss_gnss->frame_gsa), line)) {

            }
        } break;

        case MINMEA_SENTENCE_GLL: {
            if (minmea_parse_gll(&(libgnss_gnss->frame_gll), line)) {
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
                struct minmea_sentence_gsv *gsvs = libgnss_gnss->frame_gsv_gp;
                if (0 == memcmp("$GPGSV", line, strlen("$GPGSV"))) {
                    gsvs = libgnss_gnss->frame_gsv_gp;
                }
                else if (0 == memcmp("$GBGSV", line, strlen("$GBGSV"))) {
                    gsvs = libgnss_gnss->frame_gsv_gb;
                }
                else if (0 == memcmp("$GLGSV", line, strlen("$GLGSV"))) {
                    gsvs = libgnss_gnss->frame_gsv_gl;
                }
                else if (0 == memcmp("$GAGSV", line, strlen("$GAGSV"))) {
                    gsvs = libgnss_gnss->frame_gsv_ga;
                }
                //LLOGD("$GSV: message %d of %d", frame_gsv.msg_nr, frame_gsv.total_msgs);
                if (frame_gsv.msg_nr == 1) {
                    //LLOGD("Clean GSV");
                    memset(gsvs, 0, sizeof(struct minmea_sentence_gsv) * 3);
                }
                if (frame_gsv.msg_nr >= 1 && frame_gsv.msg_nr <= 3) {
                    //LLOGD("memcpy GSV %d", frame_gsv.msg_nr);
                    memcpy(&gsvs[frame_gsv.msg_nr - 1], &frame_gsv, sizeof(struct minmea_sentence_gsv));
                }
            }
            else {
                //LLOGD("bad GSV %s", line);
            }
        } break;

        case MINMEA_SENTENCE_VTG: {
            //struct minmea_sentence_vtg frame_vtg;
            if (minmea_parse_vtg(&(libgnss_gnsstmp->frame_vtg), line)) {
                memcpy(&(libgnss_gnss->frame_vtg), &libgnss_gnsstmp->frame_vtg, sizeof(struct minmea_sentence_vtg));
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
            if (minmea_parse_zda(&(libgnss_gnsstmp->frame_zda), line)) {
                memcpy(&(libgnss_gnss->frame_zda), &libgnss_gnsstmp->frame_zda, sizeof(struct minmea_sentence_zda));
            }
        } break;
        default:
            //LLOGD("why happen");
            break;
    }
    return 0;
}
