#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_mem.h"
#include "luat_uart.h"
#include "luat_rtc.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"

luat_libgnss_t gnssctx;
char *libgnss_recvbuff;
int libgnss_route_uart_id = -1;
int gnss_debug = 0;

void luat_libgnss_uart_recv_cb(int uart_id, uint32_t data_len) {
    (void)data_len;
    if (libgnss_recvbuff == NULL)
        return;
    // LLOGD("uart recv cb");
    int len = 0;
    while (1) {
        len = luat_uart_read(uart_id, libgnss_recvbuff, RECV_BUFF_SIZE - 1);
        if (len < 1 || len >= RECV_BUFF_SIZE)
            break;
        if (libgnss_route_uart_id > 0) {
            luat_uart_write(libgnss_route_uart_id, libgnss_recvbuff, len);
        }
        luat_libgnss_on_rawdata(libgnss_recvbuff, len, 0);
        libgnss_recvbuff[len] = 0;
        if (gnss_debug) {
            LLOGD(">> %s", libgnss_recvbuff);
        }
        luat_libgnss_parse_data(libgnss_recvbuff, len);
    }
}

static void clear_data(minmea_data_t* ptr) {
    if (ptr) {
        memset(ptr, 0, sizeof(minmea_data_t));
    }
}

int luat_libgnss_init(int clear) {
    if (clear) {
        memset(&gnssctx.frame_rmc, 0, sizeof(struct minmea_sentence_rmc));
        clear_data(gnssctx.rmc);
        clear_data(gnssctx.gga);
        clear_data(gnssctx.gll);
        clear_data(gnssctx.gst);
        clear_data(gnssctx.vtg);
        clear_data(gnssctx.zda);
        clear_data(gnssctx.txt);
        for (size_t i = 0; i < FRAME_GSV_MAX; i++)
        {
            clear_data(gnssctx.gsv[i]);
        }
        for (size_t i = 0; i < FRAME_GSA_MAX; i++)
        {
            clear_data(gnssctx.gsa[i]);
        }
    }
    return 0;
}

#define MAX_LEN (120)
static char nmea_tmp_buff[MAX_LEN] = {0}; // nmea 最大长度82,含换行符
int luat_libgnss_parse_data(const char* data, size_t len) {
    size_t offset = strlen(nmea_tmp_buff);
    // 流式解析nmea数据
    for (size_t i = 0; i < len; i++)
    {
        if (offset >= MAX_LEN) {
            offset = 0;
        }
        if (data[i] == 0x0A) {
            nmea_tmp_buff[offset] = 0;
            luat_libgnss_parse_nmea((const char*)nmea_tmp_buff);
            offset = 0;
            continue;
        }
        else {
            nmea_tmp_buff[offset++] = data[i];
        }
        //LLOGD("当前数据 %s", nmea_tmp_buff);
    }
    nmea_tmp_buff[offset] = 0;
    return 0;
}

static void copynmea(minmea_data_t** dst, const char* src) {
    if (*dst == NULL) {
        *dst = luat_heap_malloc(sizeof(minmea_data_t));
    }
    if (*dst != NULL) {
        strcpy((*dst)->data, src);
        (*dst)->tm = luat_mcu_tick64_ms();
    }
}

int luat_libgnss_parse_nmea(const char* line) {
    if (strlen(line) > (LUAT_LIBGNSS_MAX_LINE - 1)) {
        return -1;
    }
    char tmpbuff[128] = {0};
    struct minmea_sentence_gsv *frame_gsv = (struct minmea_sentence_gsv*)tmpbuff;
    struct minmea_sentence_rmc *frame_rmc = (struct minmea_sentence_rmc*)tmpbuff;
    struct minmea_sentence_gsa *frame_gsa = (struct minmea_sentence_gsa*)tmpbuff;
    enum minmea_sentence_id id = minmea_sentence_id(line, false);
    if (id == MINMEA_UNKNOWN || id >= MINMEA_SENTENCE_MAX_ID || id == MINMEA_INVALID) {
        //LLOGD("非法的NMEA数据 %s", line);
        return -1;
    }
    uint64_t tnow = luat_mcu_tick64_ms();
    struct tm tblock = {0};
    int ticks = luat_mcu_ticks();
    switch (id) {
        case MINMEA_SENTENCE_RMC: {
            if (minmea_parse_rmc(frame_rmc, line)) {
                copynmea(&gnssctx.rmc, line);
                if (frame_rmc->valid) {
                    memcpy(&(gnssctx.frame_rmc), frame_rmc, sizeof(struct minmea_sentence_rmc));
                    #ifdef LUAT_USE_MCU
                    if (gnssctx.rtc_auto && (gnssctx.fix_at_ticks == 0 || ((uint32_t)(ticks - gnssctx.fix_at_ticks)) > 600*1000)) {
                        LLOGI("Auto-Set RTC by GNSS RMC");
                        minmea_getdatetime(&tblock, &gnssctx.frame_rmc.date, &gnssctx.frame_rmc.time);
                        tblock.tm_year -= 1900;
                        luat_rtc_set(&tblock);
                        // luat_rtc_set_tamp32(mktime(&tblock));
                    }
                    if (gnssctx.fix_at_ticks == 0) {
                        LLOGI("Fixed %d %d", gnssctx.frame_rmc.latitude.value, gnssctx.frame_rmc.longitude.value);
                        // 发布系统消息
                        luat_libgnss_state_onchanged(GNSS_STATE_FIXED);
                    }
                    gnssctx.fix_at_ticks = luat_mcu_ticks();
                    #endif
                }
                else {
                    if (gnssctx.fix_at_ticks && gnssctx.frame_rmc.valid) {
                        LLOGI("Lose"); // 发布系统消息
                        luat_libgnss_state_onchanged(GNSS_STATE_LOSE);
                    }
                    gnssctx.fix_at_ticks = 0;
                    gnssctx.frame_rmc.valid = 0;
                    // if (libgnss_gnsstmp->frame_rmc.date.year > 0) {
                        memcpy(&(gnssctx.frame_rmc.date), &(frame_rmc->date), sizeof(struct minmea_date));
                    // }
                    // if (libgnss_gnsstmp->frame_rmc.time.hours > 0) {
                        memcpy(&(gnssctx.frame_rmc.time), &(frame_rmc->time), sizeof(struct minmea_time));
                    // }
                }
            }
        } break;

        case MINMEA_SENTENCE_GSA: {
            if (minmea_parse_gsa(frame_gsa, line)) {
                copynmea(&gnssctx.gsa[gnssctx.gsa_offset], line);
                if (gnssctx.gsa_offset + 1 >= FRAME_GSA_MAX) {
                    gnssctx.gsa_offset = 0;
                }
                else {
                    gnssctx.gsa_offset ++;
                }
                // 把失效的GSA清理掉
                for (size_t i = 0; i < FRAME_GSA_MAX; i++)
                {
                    if (gnssctx.gsa[i] && gnssctx.gsa[i]->data[0] != 0 && tnow - gnssctx.gsa[i]->tm > 950) {
                        memset(gnssctx.gsa[i], 0, sizeof(minmea_data_t));
                    }
                }
                
            }
        } break;

        case MINMEA_SENTENCE_GSV: {
            //LLOGD("Got GSV : %s", line);
            if (minmea_parse_gsv(frame_gsv, line)) {
                if (frame_gsv->msg_nr == 1) {
                    // 检测到开头, 那么清空所有相同头部的数据
                    for (size_t i = 0; i < FRAME_GSV_MAX; i++)
                    {
                        if (gnssctx.gsv[i] && 0 == memcmp(line, gnssctx.gsv[i], 6)) {
                            memset(gnssctx.gsv[i]->data, 0, sizeof(minmea_data_t));
                        }
                    }
                }
                // 找一个空位,放进去
                for (size_t i = 0; i < FRAME_GSV_MAX; i++)
                {
                    if (gnssctx.gsv[i] == NULL) {
                        copynmea(&gnssctx.gsv[i], line);
                        break;
                    }
                    if (gnssctx.gsv[i]->data[0] == 0) {
                        // LLOGD("填充GSV到%d %s", i, line);
                        copynmea(&gnssctx.gsv[i], line);
                        break;
                    }
                }
            }
        } break;
        case MINMEA_SENTENCE_GGA: {
            copynmea(&gnssctx.gga, line);
        } break;
        case MINMEA_SENTENCE_GLL: {
            copynmea(&gnssctx.gll, line);
            break;
        }
        case MINMEA_SENTENCE_GST: {
            copynmea(&gnssctx.gst, line);
            break;
        }
        case MINMEA_SENTENCE_VTG: {
            copynmea(&gnssctx.vtg, line);
        } break;
        case MINMEA_SENTENCE_ZDA: {
            copynmea(&gnssctx.zda, line);
        } break;
        case MINMEA_SENTENCE_TXT: {
            luat_libgnss_on_rawdata(line, strlen(line), 1);
            copynmea(&gnssctx.txt, line);
            break;
        }
        default: {
            luat_libgnss_on_rawdata(line, strlen(line), 2);
            break;
        }
    }
    return 0;
}

int luat_libgnss_data_check(minmea_data_t* data, uint32_t timeout, uint64_t tnow) {
    if (data == NULL) {
        return 0;
    }
    if (data->tm == 0 || tnow - data->tm > timeout) {
        return 0;
    }
    return 1;
}
