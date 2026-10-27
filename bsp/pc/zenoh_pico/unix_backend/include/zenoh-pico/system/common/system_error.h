#ifndef ZENOH_PICO_SYSTEM_COMMON_SYSTEM_ERROR_H
#define ZENOH_PICO_SYSTEM_COMMON_SYSTEM_ERROR_H

#include "zenoh-pico/utils/logging.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline void _z_report_system_error(int errcode) { _Z_ERROR("System error: %i", errcode); }

#define _Z_CHECK_SYS_ERR(expr)                      \
    do {                                            \
        int __res = expr;                           \
        if (__res != 0) {                           \
            _z_report_system_error(__res);          \
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_GENERIC); \
        }                                           \
        return _Z_RES_OK;                           \
    } while (false)

#define _Z_RETURN_IF_SYS_ERR(expr)                  \
    do {                                            \
        int __res = expr;                           \
        if (__res != 0) {                           \
            _z_report_system_error(__res);          \
            _Z_ERROR_RETURN(_Z_ERR_SYSTEM_GENERIC); \
        }                                           \
    } while (false)

#ifdef __cplusplus
}
#endif

#endif /* ZENOH_PICO_SYSTEM_COMMON_SYSTEM_ERROR_H */
