#ifndef LUAT_WEB_GNSS_UART32_H
#define LUAT_WEB_GNSS_UART32_H

#include <stdint.h>
typedef struct cJSON cJSON;

void luat_web_gnss_uart32_init(void);
void luat_web_gnss_uart32_deinit(void);
void luat_web_gnss_uart32_tick(uint64_t now_ms);
int luat_web_gnss_uart32_apply_config(const char* body);
cJSON* luat_web_gnss_uart32_make_status_json(void);

#endif
