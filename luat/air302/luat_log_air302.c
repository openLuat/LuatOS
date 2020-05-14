
#include "bsp.h"
#include "bsp_custom.h"
#include "osasys.h"
#include "ostask.h"
#include "queue.h"
#include "luat_base.h"
#include "luat_log.h"

void luat_print(const char* _str) {
    //
}

void luat_nprint(char *s, size_t l) {
    //
}

void luat_printf(const char* fmt, const char* value) {
    //
}

static int LOG_LEVEL = LUAT_LOG_DEBUG;
void luat_log_set_level(int level) {
    LOG_LEVEL = level;
}
int luat_log_get_level() {
    return LOG_LEVEL;
}
void luat_log_log(int level, const char* tag, const char* _fmt, ...) {
    // TODO write to uart or unilog
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
