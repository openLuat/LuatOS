
#include "luat_base.h"
#include "luat_log.h"
#include "rtthread.h"

#define DBG_TAG           "rtt.log"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

void luat_print(const char* _str) {
    rt_kputs(_str);
}

void luat_nprint(char *s, size_t l) {
    char buf[2];
    buf[1] = 0x00;
    for (size_t i = 0; i < l; i++)
    {
        buf[0] = s[i];
        rt_kputs(buf);
    }
}

void luat_printf(const char* fmt, const char* value) {
    rt_kprintf(fmt, value);
}

static int LOG_LEVEL = LUAT_LOG_DEBUG;
void luat_log_set_level(int level) {
    LOG_LEVEL = level;
}
int luat_log_get_level() {
    return LOG_LEVEL;
}
void luat_log_log(int level, const char* tag, const char* _fmt, ...) {
    va_list args;
    va_start(args, _fmt);
    #if defined(RT_USING_ULOG)
    /*
#define LOG_LVL_ASSERT                 0
#define LOG_LVL_ERROR                  3
#define LOG_LVL_WARNING                4
#define LOG_LVL_INFO                   6
#define LOG_LVL_DBG                    7
    */
    switch (level)
    {
    case LUAT_LOG_DEBUG:
        level = LOG_LVL_DBG;
        break;
    case LUAT_LOG_INFO:
        level = LOG_LVL_INFO;
        break;
    case LUAT_LOG_WARN:
        level = LOG_LVL_WARNING;
        break;
    case LUAT_LOG_ERROR:
        level = LOG_LVL_ERROR;
        break;
    default:
        level = LOG_LVL_DBG;
        break;
    }
    ulog_output(level, tag, 1, _fmt, args);
    #else
    /*
#define DBG_ERROR           0
#define DBG_WARNING         1
#define DBG_INFO            2
#define DBG_LOG             3
    */
    switch (level)
    {
    case LUAT_LOG_DEBUG:
        level = DBG_LOG;
        break;
    case LUAT_LOG_INFO:
        level = DBG_INFO;
        break;
    case LUAT_LOG_WARN:
        level = DBG_WARNING;
        break;
    case LUAT_LOG_ERROR:
        level = DBG_ERROR;
        break;
    default:
        level = DBG_LOG;
        break;
    }
    dbg_log(level, _fmt, args);
    #endif
    va_end(args);
}
void luat_log_debug(const char* tag, const char* _fmt, ...) {
    if (LOG_LEVEL > LUAT_LOG_DEBUG) return;
    va_list args;
    va_start(args, _fmt);
    luat_log_log(LUAT_LOG_DEBUG, tag, _fmt, args);
    va_end(args);
}
void luat_log_info(const char* tag, const char* _fmt, ...) {
    if (LOG_LEVEL > LUAT_LOG_INFO) return;
    va_list args;
    va_start(args, _fmt);
    luat_log_log(LUAT_LOG_INFO, tag, _fmt, args);
    va_end(args);
}
void luat_log_warn(const char* tag, const char* _fmt, ...) {
    if (LOG_LEVEL > LUAT_LOG_WARN) return;
    va_list args;
    va_start(args, _fmt);
    luat_log_log(LUAT_LOG_WARN, tag, _fmt, args);
    va_end(args);
}
void luat_log_error(const char* tag, const char* _fmt, ...) {
    if (LOG_LEVEL > LUAT_LOG_ERROR) return;
    va_list args;
    va_start(args, _fmt);
    luat_log_log(LUAT_LOG_ERROR, tag, _fmt, args);
    va_end(args);
}
