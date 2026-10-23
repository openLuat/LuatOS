//
// Copyright (c) 2022 ZettaScale Technology
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0, or the Apache License, Version 2.0
// which is available at https://www.apache.org/licenses/LICENSE-2.0.
//
// SPDX-License-Identifier: EPL-2.0 OR Apache-2.0
//
// Contributors:
//   ZettaScale Zenoh Team, <zenoh@zettascale.tech>
//

#ifndef ZENOH_PICO_UTILS_LOGGING_H
#define ZENOH_PICO_UTILS_LOGGING_H

#include <stdio.h>

#include "zenoh-pico/system/common/platform.h"

#ifdef __cplusplus
extern "C" {
#endif

// Allows replacement of printf on targets that don't support it
#ifndef ZENOH_LOG_PRINT
#define ZENOH_LOG_PRINT printf
#endif

// Compatibility with legacy logging system where
// 1 -> ERROR
// 2 -> INFO
// 3 -> DEBUG
#ifdef ZENOH_DEBUG
#undef ZENOH_LOG_ERROR
#undef ZENOH_LOG_WARN
#undef ZENOH_LOG_INFO
#undef ZENOH_LOG_DEBUG
#undef ZENOH_LOG_TRACE
#if ZENOH_DEBUG == 1
#define ZENOH_LOG_ERROR
#elif ZENOH_DEBUG == 2
#define ZENOH_LOG_INFO
#elif ZENOH_DEBUG == 3
#define ZENOH_LOG_DEBUG
#endif
#endif

// Logging macros
#define _Z_LOG(level, ...)                                               \
    do {                                                                 \
        char __timestamp[64];                                            \
        z_time_now_as_str(__timestamp, sizeof(__timestamp));             \
        ZENOH_LOG_PRINT("[%s " #level " ::%s] ", __timestamp, __func__); \
        ZENOH_LOG_PRINT(__VA_ARGS__);                                    \
        ZENOH_LOG_PRINT("\r\n");                                         \
    } while (false)

#define _Z_LOG_NONL(level, ...)                                          \
    do {                                                                 \
        char __timestamp[64];                                            \
        z_time_now_as_str(__timestamp, sizeof(__timestamp));             \
        ZENOH_LOG_PRINT("[%s " #level " ::%s] ", __timestamp, __func__); \
        ZENOH_LOG_PRINT(__VA_ARGS__);                                    \
    } while (false)
// In debug build, if a level is not enabled, the following macro is used instead
// in order to check that the arguments are valid and compile fine.
#define _Z_CHECK_LOG(...)                        \
    do {                                         \
        if (false) ZENOH_LOG_PRINT(__VA_ARGS__); \
    } while (false)

#ifdef ZENOH_LOG_TRACE
#define ZENOH_LOG_DEBUG
#define _Z_TRACE(...) _Z_LOG(TRACE, __VA_ARGS__)
#elif defined(Z_BUILD_LOG)
#define _Z_TRACE _Z_CHECK_LOG
#else
#define _Z_TRACE(...) (void)(0)
#endif

#ifdef ZENOH_LOG_DEBUG
#define ZENOH_LOG_INFO
#define _Z_DEBUG(...) _Z_LOG(DEBUG, __VA_ARGS__)
#define _Z_DEBUG_NONL(...) _Z_LOG_NONL(DEBUG, __VA_ARGS__)
#elif defined(Z_BUILD_LOG)
#define _Z_DEBUG _Z_CHECK_LOG
#define _Z_DEBUG_NONL _Z_CHECK_LOG
#else
#define _Z_DEBUG(...) (void)(0)
#define _Z_DEBUG_NONL(...) (void)(0)
#endif

#ifdef ZENOH_LOG_INFO
#define ZENOH_LOG_WARN
#define _Z_INFO(...) _Z_LOG(INFO, __VA_ARGS__)
#elif defined(Z_BUILD_LOG)
#define _Z_INFO _Z_CHECK_LOG
#else
#define _Z_INFO(...) (void)(0)
#endif

#ifdef ZENOH_LOG_WARN
#define ZENOH_LOG_ERROR
#define _Z_WARN(...) _Z_LOG(WARN, __VA_ARGS__)
#elif defined(Z_BUILD_LOG)
#define _Z_WARN _Z_CHECK_LOG
#else
#define _Z_WARN(...) (void)(0)
#endif

#ifdef ZENOH_LOG_ERROR
#define _Z_ERROR(...) _Z_LOG(ERROR, __VA_ARGS__)
#elif defined(Z_BUILD_LOG)
#define _Z_ERROR _Z_CHECK_LOG
#else
#define _Z_ERROR(...) (void)(0)
#endif

// Error logging macros
// Potentially add a function call to a logger if needs arise
#define _Z_ERROR_RETURN(err_code)                                                \
    do {                                                                         \
        _Z_TRACE("Error generated: %d, at %s:%d", err_code, __FILE__, __LINE__); \
        return err_code;                                                         \
    } while (false)

#define _Z_ERROR_LOG(err_code)                                                   \
    do {                                                                         \
        _Z_TRACE("Error generated: %d, at %s:%d", err_code, __FILE__, __LINE__); \
    } while (false)

#ifdef __cplusplus
}
#endif

#endif  // ZENOH_PICO_UTILS_LOGGING_H
