#ifndef LUAT_CC_UART_STORAGE_H
#define LUAT_CC_UART_STORAGE_H
#include "luat_cc_uart_bridge.h"
#ifdef LUAT_USE_CC_UART_BRIDGE
int luat_cc_uart_storage_init(const luat_cc_uart_config_t *config, luat_cc_uart_notice_fn notify);
int luat_cc_uart_storage_play(uint64_t session, const char *path);
void luat_cc_uart_storage_play_stop(void);
/* No file operations in these media-clock APIs. Silence while prefetching. */
void luat_cc_uart_storage_play_frame(int16_t pcm[320]);
int luat_cc_uart_storage_record(uint64_t session, const char *path);
void luat_cc_uart_storage_record_stop(int abnormal);
int luat_cc_uart_storage_record_frame(const int16_t left[320], const int16_t right[320]);
int luat_cc_uart_storage_idle(void);
void luat_cc_uart_storage_stats(uint32_t *active, uint32_t *frames, uint32_t *failed);
#endif
#endif
