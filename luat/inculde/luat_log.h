

#ifndef LUAT_LOG
#define LUAT_LOG

#define LUAT_LOG_TRACE (1 << 5)
#define LUAT_LOG_DEBUG (1 << 4)
#define LUAT_LOG_INFO  (1 << 3)
#define LUAT_LOG_WARN  (1 << 2)
#define LUAT_LOG_ERROR (1 << 1)

void luat_print(const char* _str);
void luat_nprint(char *s, size_t l);
void luat_printf(const char* _fmt, ...);

#endif
