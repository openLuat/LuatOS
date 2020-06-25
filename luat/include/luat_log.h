

#ifndef LUAT_LOG
#define LUAT_LOG

#define LUAT_LOG_DEBUG 1
#define LUAT_LOG_INFO  2
#define LUAT_LOG_WARN  3
#define LUAT_LOG_ERROR 4
#define LUAT_LOG_CLOSE 7

void luat_print(const char* _str);
void luat_nprint(char *s, size_t l);
void luat_log_set_uart_port(int port);

void luat_log_set_level(int level);
int luat_log_get_level(void);
void luat_log_log(int level, const char* tag, const char* _fmt, ...);
// void luat_log_debug(const char* tag, const char* _fmt, ...);
// void luat_log_info(const char* tag, const char* _fmt, ...);
// void luat_log_warn(const char* tag, const char* _fmt, ...);
// void luat_log_error(const char* tag, const char* _fmt, ...);

#define LLOGE(format, ...) luat_log_log(LUAT_LOG_ERROR, LUAT_LOG_TAG, format, ##__VA_ARGS__)
#define LLOGW(format, ...) luat_log_log(LUAT_LOG_WARN, LUAT_LOG_TAG, format, ##__VA_ARGS__)
#define LLOGI(format, ...) luat_log_log(LUAT_LOG_INFO, LUAT_LOG_TAG, format, ##__VA_ARGS__)
#define LLOGD(format, ...) luat_log_log(LUAT_LOG_DEBUG, LUAT_LOG_TAG, format, ##__VA_ARGS__)

#define luat_log_error(XTAG, format, ...)   luat_log_log(LUAT_LOG_ERROR, XTAG, format, ##__VA_ARGS__)
#define luat_log_warn(XTAG, format, ...)    luat_log_log(LUAT_LOG_WARN, XTAG, format, ##__VA_ARGS__)
#define luat_log_info(XTAG, format, ...)    luat_log_log(LUAT_LOG_INFO, XTAG, format, ##__VA_ARGS__)
#define luat_log_debug(XTAG, format, ...)   luat_log_log(LUAT_LOG_DEBUG, XTAG, format, ##__VA_ARGS__)

#endif
