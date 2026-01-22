/**
 * @file luat_airui_error.c
 * @summary AIRUI 错误码转换
 * @responsible 错误码到字符串的转换
 */

#include "luat_airui.h"

/**
 * 错误码转字符串
 * @param err 错误码
 * @return 错误描述字符串
 */
const char *airui_strerror(airui_err_t err)
{
    switch (err) {
        case AIRUI_OK:
            return "Success";
        case AIRUI_ERR_INVALID_PARAM:
            return "Invalid parameter";
        case AIRUI_ERR_NO_MEM:
            return "Out of memory";
        case AIRUI_ERR_INIT_FAILED:
            return "Initialization failed";
        case AIRUI_ERR_NOT_INITIALIZED:
            return "Not initialized";
        case AIRUI_ERR_PLATFORM_ERROR:
            return "Platform error";
        default:
            return "Unknown error";
    }
}

