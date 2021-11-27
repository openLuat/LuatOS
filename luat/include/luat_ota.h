
#include "luat_base.h"

#ifndef LUAT_OTA_H
#define LUAT_OTA_H

#define UPDATE_BIN_PATH "/update.bin"
#define ROLLBACK_MARK_PATH "/rollback_mark"
#define UPDATE_MARK "/update_mark"
#define FLASHX_PATH "/flashx.bin"

#ifndef LUAT_OTA_MODE
#define LUAT_OTA_MODE 1
#endif

#ifndef LUAT_EXIT_REBOOT_DELAY
#define LUAT_EXIT_REBOOT_DELAY 15000
#endif

int luat_ota_update_or_rollback(void);
void luat_ota_reboot(int timeout_ms);

#endif
