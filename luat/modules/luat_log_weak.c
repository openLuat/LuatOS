
#include "luat_base.h"
#include "luat_log.h"
#include "luat_uart.h"
#include "printf.h"

static uint8_t luat_log_uart_port = 0;
static uint8_t luat_log_level_cur = LUAT_LOG_DEBUG;

LUAT_WEAK void luat_log_set_uart_port(int port) {
    luat_log_uart_port = port;
}

LUAT_WEAK void luat_print(const char* _str) {
    luat_nprint((char*)_str, strlen(_str));
}

LUAT_WEAK void luat_nprint(char *s, size_t l) {
    luat_uart_write(luat_log_uart_port, s, l);
}

LUAT_WEAK void luat_log_set_level(int level) {
    luat_log_level_cur = level;
}
LUAT_WEAK int luat_log_get_level() {
    return luat_log_level_cur;
}
#define LOGLOG_SIZE 1024
LUAT_WEAK void luat_log_log(int level, const char* tag, const char* _fmt, ...) {
    if (luat_log_level_cur > level) return;
    char buff[LOGLOG_SIZE];
    char *tmp = (char *)buff;
    switch (level)
        {
        case LUAT_LOG_DEBUG:
            buff[0] = 'D';
            break;
        case LUAT_LOG_INFO:
            buff[0] = 'I';
            break;
        case LUAT_LOG_WARN:
            buff[0] = 'W';
            break;
        case LUAT_LOG_ERROR:
            buff[0] = 'E';
            break;
        default:
            buff[0] = '?';
            break;
        }
    buff[1] = '/';
    tmp += 2;
    memcpy(tmp, tag, strlen(tag));
    buff[2+strlen(tag)] = ' ';
    tmp += strlen(tag) + 1;

    va_list args;
    va_start(args, _fmt);
    size_t len = vsnprintf_(tmp, LOGLOG_SIZE, _fmt, args);
    va_end(args);
    if (len > 0) {
        len = strlen(buff);
        // if (len > LOGLOG_SIZE - 2)
        //     len = LOGLOG_SIZE - 2;
        // buff[len] = '\r';
        // buff[len+1] = '\n';
        // luat_nprint(buff, len+2);
        if (len > LOGLOG_SIZE - 1)
            len = LOGLOG_SIZE - 1;
        buff[len] = '\n';
        luat_nprint(buff, len+1);
    }
}
