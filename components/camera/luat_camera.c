
#include "luat_base.h"
#include "luat_camera.h"

#define LUAT_LOG_TAG "camera"
#include "luat_log.h"

int32_t g_camera_log_level = LUAT_LOG_WARN;

LUAT_WEAK void luat_camera_preview_data_callback(int id, uint8_t *data, uint32_t total_byte, uint16_t w, uint16_t h, uint8_t color_bytes, void *user_data)
{

}