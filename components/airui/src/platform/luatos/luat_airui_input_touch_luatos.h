#ifndef LUAT_AIRUI_INPUT_TOUCH_LUATOS_H
#define LUAT_AIRUI_INPUT_TOUCH_LUATOS_H
#include "luat_airui.h"
#include "luat_tp.h"
/* GUI thread entry; producer copies frames under the shared input service lock. */
bool airui_input_touch_read(airui_ctx_t *ctx, lv_indev_t *indev,
    lv_indev_data_t *data, luat_tp_config_t *config, unsigned pointer_slot);
#endif
