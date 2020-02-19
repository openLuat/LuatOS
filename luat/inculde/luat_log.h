

#ifndef LUAT_LOG
#define LUAT_LOG

#define LUAT_LOG_DEBUG 1
#define LUAT_LOG_INFO  2
#define LUAT_LOG_WARN  3
#define LUAT_LOG_ERROR 4
#define LUAT_LOG_CLOSE 7

void luat_print(const char* _str);
void luat_nprint(char *s, size_t l);
void luat_printf(const char* _fmt, const char* value);

void luat_log_set_level(int level);
int luat_log_get_level(void);
void luat_log_log(int level, const char* tag, const char* _fmt, ...);
void luat_log_debug(const char* tag, const char* _fmt, ...);
void luat_log_info(const char* tag, const char* _fmt, ...);
void luat_log_warn(const char* tag, const char* _fmt, ...);
void luat_log_error(const char* tag, const char* _fmt, ...);
void luat_log_fatal(const char* tag, const char* _fmt, ...);

#endif
