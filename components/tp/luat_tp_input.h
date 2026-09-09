#ifndef LUAT_TP_INPUT_H
#define LUAT_TP_INPUT_H
#include "luat_tp.h"
#include "luat_input_service.h"

/* All adapter operations except id() require the TP task mutex.
 * They acquire the service lock only when accessing the input core. */
int luat_tp_process(luat_tp_config_t *config);
int luat_tp_input_init(luat_tp_config_t *config);
void luat_tp_input_deinit(luat_tp_config_t *config);
int luat_tp_input_feed(luat_tp_config_t *config, luat_tp_data_t *normalized);
void luat_tp_input_reset(luat_tp_config_t *config);
int luat_tp_input_running(luat_tp_config_t *config);
void luat_tp_input_suspend(luat_tp_config_t *config, int suspended);
uint32_t luat_tp_input_id(const luat_tp_config_t *config);
#endif
