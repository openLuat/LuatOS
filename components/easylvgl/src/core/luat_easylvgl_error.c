/**
 * @file luat_easylvgl_error.c
 * @summary EasyLVGL 错误码转换
 * @responsible 错误码到字符串的转换
 */

#include "luat_easylvgl.h"

/**
 * 错误码转字符串
 * @param err 错误码
 * @return 错误描述字符串
 */
const char *easylvgl_strerror(easylvgl_err_t err)
{
    switch (err) {
        case EASYLVGL_OK:
            return "Success";
        case EASYLVGL_ERR_INVALID_PARAM:
            return "Invalid parameter";
        case EASYLVGL_ERR_NO_MEM:
            return "Out of memory";
        case EASYLVGL_ERR_INIT_FAILED:
            return "Initialization failed";
        case EASYLVGL_ERR_NOT_INITIALIZED:
            return "Not initialized";
        case EASYLVGL_ERR_PLATFORM_ERROR:
            return "Platform error";
        default:
            return "Unknown error";
    }
}

