/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
* All rights reserved.
*
* This software is supplied "AS IS" without any warranties.
* RDA assumes no responsibility or liability for the use of the software,
* conveys no license or title under any patent, copyright, or mask work
* right to the product. RDA reserves the right to make changes in the
* software without notification.  RDA also make no representation or
* warranty that such application will be suitable for the specified use
* without further testing or modification.
*/

#ifndef _OSI_LOG_H_
#define _OSI_LOG_H_

#include <stdarg.h>
#include "kernel_config.h"
#include "osi_compiler.h"

OSI_EXTERN_C_BEGIN

#ifndef DOXYGEN
#ifndef OSI_LOCAL_LOG_LEVEL
#define OSI_LOCAL_LOG_LEVEL OSI_LOG_LEVEL_INFO
#endif

#ifdef OSI_LOG_DISABLED
#undef OSI_LOCAL_LOG_LEVEL
#define OSI_LOCAL_LOG_LEVEL OSI_LOG_LEVEL_NEVER
#endif

#ifndef OSI_LOCAL_LOG_TAG
#ifdef OSI_LOG_TAG
#define OSI_LOCAL_LOG_TAG OSI_LOG_TAG
#else
#define OSI_LOCAL_LOG_TAG LOG_TAG_NONE
#endif
#endif
#endif

/**
 * trace level, larger value is less important
 */
enum
{
    OSI_LOG_LEVEL_NEVER,  ///< only used in control, for not to output trace
    OSI_LOG_LEVEL_ERROR,  ///< error
    OSI_LOG_LEVEL_WARN,   ///< warning
    OSI_LOG_LEVEL_INFO,   ///< information
    OSI_LOG_LEVEL_DEBUG,  ///< for debug
    OSI_LOG_LEVEL_VERBOSE ///< verbose
};

/**
 * macro for trace tag
 */
#define OSI_MAKE_LOG_TAG(a, b, c, d) ((unsigned)(a) | ((unsigned)(b) << 7) | ((unsigned)(c) << 14) | ((unsigned)(d) << 21))

/**
 * macro for extended trace argument types
 */
#define OSI_LOGPAR(...) __OSI_LOGPAR(__VA_ARGS__)

/**
 * macros for trace level condition
 *
 * \code{.cpp}
 * if (OSI_LOGD_EN) {
 *     ......
 * }
 * \endcode
 *
 * When DEBUG trace is not enabled, the above codes will be expanded as empty.
 */
#define OSI_LOGE_EN (OSI_LOCAL_LOG_LEVEL >= OSI_LOG_LEVEL_ERROR)
#define OSI_LOGW_EN (OSI_LOCAL_LOG_LEVEL >= OSI_LOG_LEVEL_WARN)
#define OSI_LOGI_EN (OSI_LOCAL_LOG_LEVEL >= OSI_LOG_LEVEL_INFO)
#define OSI_LOGD_EN (OSI_LOCAL_LOG_LEVEL >= OSI_LOG_LEVEL_DEBUG)
#define OSI_LOGV_EN (OSI_LOCAL_LOG_LEVEL >= OSI_LOG_LEVEL_VERBOSE)

/**
 * macros for basic trace
 *
 * When the trace level is not enabled, the macro will be expanded as empty.
 *
 * At most 16 arguments are supported.
 *
 * @param trcid     trace ID, 0 for not use trace ID
 * @param fmt       format string, only used when trace ID is 0
 */
#define OSI_LOGE(trcid, fmt, ...) __OSI_LOGB(OSI_LOG_LEVEL_ERROR, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGW(trcid, fmt, ...) __OSI_LOGB(OSI_LOG_LEVEL_WARN, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGI(trcid, fmt, ...) __OSI_LOGB(OSI_LOG_LEVEL_INFO, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGD(trcid, fmt, ...) __OSI_LOGB(OSI_LOG_LEVEL_DEBUG, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGV(trcid, fmt, ...) __OSI_LOGB(OSI_LOG_LEVEL_VERBOSE, trcid, fmt, ##__VA_ARGS__)

/**
 * macros for extended trace
 *
 * When the trace level is not enabled, the macro will be expanded as empty.
 *
 * At most 16 arguments are supported.
 *
 * @param partype   arguments types
 * @param trcid     trace ID, 0 for not use trace ID
 * @param fmt       format string, only used when trace ID is 0
 */
#define OSI_LOGXE(partype, trcid, fmt, ...) __OSI_LOGX(OSI_LOG_LEVEL_ERROR, partype, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGXW(partype, trcid, fmt, ...) __OSI_LOGX(OSI_LOG_LEVEL_WARN, partype, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGXI(partype, trcid, fmt, ...) __OSI_LOGX(OSI_LOG_LEVEL_INFO, partype, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGXD(partype, trcid, fmt, ...) __OSI_LOGX(OSI_LOG_LEVEL_DEBUG, partype, trcid, fmt, ##__VA_ARGS__)
#define OSI_LOGXV(partype, trcid, fmt, ...) __OSI_LOGX(OSI_LOG_LEVEL_VERBOSE, partype, trcid, fmt, ##__VA_ARGS__)

/**
 * macros for trace with format string parsing
 *
 * When the trace level is not enabled, the macro will be expanded as empty.
 *
 * At most 16 arguments are supported.
 *
 * @param fmt       format string, only used when trace ID is 0
 */
#define OSI_PRINTFE(fmt, ...) __OSI_PRINTF(OSI_LOG_LEVEL_ERROR, fmt, ##__VA_ARGS__)
#define OSI_PRINTFW(fmt, ...) __OSI_PRINTF(OSI_LOG_LEVEL_WARN, fmt, ##__VA_ARGS__)
#define OSI_PRINTFI(fmt, ...) __OSI_PRINTF(OSI_LOG_LEVEL_INFO, fmt, ##__VA_ARGS__)
#define OSI_PRINTFD(fmt, ...) __OSI_PRINTF(OSI_LOG_LEVEL_DEBUG, fmt, ##__VA_ARGS__)
#define OSI_PRINTFV(fmt, ...) __OSI_PRINTF(OSI_LOG_LEVEL_VERBOSE, fmt, ##__VA_ARGS__)

/**
 * macros for SX style trace and dump
 *
 * \p id is a complex bit fields. The definition follows SX definition.
 */
#define OSI_SXPRINTF(id, fmt, ...) __OSI_SXPRINTF(id, fmt, ##__VA_ARGS__)
#define OSI_SXDUMP(id, fmt, data, size) __OSI_SXDUMP(id, fmt, data, size)

/**
 * macros for new SX style trace
 *
 * Only module level in \p id will be used. When SX style trace is wanted to
 * be kept, it is suggested to migrate to these 2 macros.
 */
#define OSI_SX_TRACE(id, trcid, fmt, ...) __OSI_SX_TRACE(id, trcid, fmt, ##__VA_ARGS__)
#define OSI_SX_TRACEX(id, partype, trcid, fmt, ...) __OSI_SX_TRACEX(id, partype, trcid, fmt, ##__VA_ARGS__)

/**
 * macros for stack trace of pub modules
 */
#define OSI_PUB_TRACE(module, category, trcid, fmt, ...) __OSI_PUB_TRACE(module, category, trcid, fmt, ##__VA_ARGS__)
#define OSI_PUB_TRACEX(module, category, partype, trcid, fmt, ...) __OSI_PUB_TRACEX(module, category, partype, trcid, fmt, ##__VA_ARGS__)

/**
 * macros for stack trace of lte modules
 */
#define OSI_LTE_TRACE(module, category, trcid, fmt, ...) __OSI_LTE_TRACE(module, category, trcid, fmt, ##__VA_ARGS__)
#define OSI_LTE_TRACEX(module, category, partype, trcid, fmt, ...) __OSI_LTE_TRACEX(module, category, partype, trcid, fmt, ##__VA_ARGS__)

/**
 * macros for stack trace without module and category control
 *
 * It is suggested to use these 2 for quick debug only. The above macros
 * with module and category control should be used.
 */
#define OSI_TRACE(trcid, fmt, ...) __OSI_TRACE(trcid, fmt, ##__VA_ARGS__)
#define OSI_TRACEX(partype, trcid, fmt, ...) __OSI_TRACEX(partype, trcid, fmt, ##__VA_ARGS__)

/**
 * \brief trace vprintf by parsing format string
 *
 * This can be used to implement trace functions in third party library.
 * When there are chances to modify source codes, the appropriate macros
 * from above should be used.
 *
 * @param tag   packed trace tag and trace level
 * @param fmt   format string
 * @param ap    variadic argument list
 */
void osiTraceVprintf(unsigned tag, const char *fmt, va_list ap);

#include "osi_log_imp.h"

OSI_EXTERN_C_END
#endif
