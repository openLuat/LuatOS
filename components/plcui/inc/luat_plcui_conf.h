/** @file luat_plcui_conf.h
 * PC validation profile for the XML-driven plcui runtime.
 */
#ifndef LUAT_PLCUI_CONF_H
#define LUAT_PLCUI_CONF_H

#define PLCUI_VERSION "0.1.0"
#define PLCUI_IMAGE_CACHE_BYTES (8U * 1024U * 1024U)
#define PLCUI_DISPLAY_LINES 80
#define PLCUI_HZFONT_DEFAULT_SIZE 16U
#define PLCUI_REFRESH_RATE_HZ 60U
#define PLCUI_HANDLER_PERIOD_MS 5U
#define PLCUI_REFRESH_PERIOD_MS ((1000U + PLCUI_REFRESH_RATE_HZ - 1U) / PLCUI_REFRESH_RATE_HZ)

#endif
