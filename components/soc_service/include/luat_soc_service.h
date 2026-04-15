#ifndef LUAT_SOC_SERVICE_H
#define LUAT_SOC_SERVICE_H

#include <stdarg.h>
#include "luat_base.h"

void soc_printf(const char *fmt, ...);
void soc_printf_with_tags(const char *tags, const char *fmt, ...);
void soc_vsprintf(const char *fmt, va_list ap);
void soc_vprintf_with_tags(const char *tags, const char *fmt, va_list ap);
void soc_info(const char *fmt, ...);
#define LTIO(X,Y...) soc_info(X,##Y)
#define DBG_ERR(X,Y...) soc_printf("%s %d:"X, __FUNCTION__,__LINE__,##Y)

void soc_log_to_buffer(uint8_t *data, uint32_t len);
void soc_log_to_device(uint8_t *data, uint32_t len);
uint64_t soc_get_poweron_time_ms(void);
uint64_t soc_get_poweron_time_tick(void);

void am_print_base_info(void);

#endif
