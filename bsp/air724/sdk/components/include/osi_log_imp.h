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
#error "osi_log_imp.h can only be included by osi_log.h"
#endif

// pre-defined trace tags
#define LOG_TAG_NONE OSI_MAKE_LOG_TAG(' ', ' ', ' ', ' ')
#define LOG_TAG_HAL OSI_MAKE_LOG_TAG('H', 'A', 'L', ' ')
#define LOG_TAG_DRV OSI_MAKE_LOG_TAG('D', 'R', 'V', ' ')
#define LOG_TAG_USB_SVC OSI_MAKE_LOG_TAG('S', 'U', 'S', 'B')
#define LOG_TAG_FILE_SYSTEM OSI_MAKE_LOG_TAG('F', 'S', 'Y', 'S')
#define LOG_TAG_ATE OSI_MAKE_LOG_TAG('A', 'T', 'E', 'N')
#define LOG_TAG_MMI OSI_MAKE_LOG_TAG('M', 'M', 'I', ' ')
#define LOG_TAG_KERNEL OSI_MAKE_LOG_TAG('K', 'E', 'R', 'N')
#define LOG_TAG_APPSTART OSI_MAKE_LOG_TAG('A', 'P', 'P', 'S')
#define LOG_TAG_DRIVER OSI_MAKE_LOG_TAG('D', 'R', 'V', 'R')
#define LOG_TAG_FS OSI_MAKE_LOG_TAG('F', 'S', 'Y', 'S')
#define LOG_TAG_ML OSI_MAKE_LOG_TAG('M', 'L', 'A', 'N')
#define LOG_TAG_BOOT OSI_MAKE_LOG_TAG('B', 'O', 'O', 'T')
#define LOG_TAG_UNITY OSI_MAKE_LOG_TAG('U', 'N', 'I', 'T')
#define LOG_TAG_NET OSI_MAKE_LOG_TAG('N', 'E', 'T', ' ')
#define LOG_TAG_CFW OSI_MAKE_LOG_TAG('C', 'F', 'W', ' ')
#define LOG_TAG_UNIT_TEST OSI_MAKE_LOG_TAG('U', 'T', 'S', 'T')
#define LOG_TAG_AUDIO OSI_MAKE_LOG_TAG('A', 'U', 'D', 'I')
/*+NEW\2020.1.15\lijiaodi\添加openat打印*/
#define LOG_TAG_OPENAT OSI_MAKE_LOG_TAG('O', 'P', 'E', 'N')
/*-NEW\2020.1.15\lijiaodi\添加openat打印*/

void osiTracePrintf(unsigned tag, const char *fmt, ...);

void osiTraceBasic(unsigned tag, unsigned nargs, const char *fmt, ...);
void osiTraceEx(unsigned tag, unsigned partype, const char *fmt, ...);
void osiTraceIdBasic(unsigned tag, unsigned nargs, unsigned trcid, ...);
void osiTraceIdEx(unsigned tag, unsigned partype, unsigned trcid, ...);

void osiTraceTraBasic(unsigned nargs, const char *fmt, ...);
void osiTraceTraEx(unsigned partype, const char *fmt, ...);
void osiTraceTraIdBasic(unsigned nargs, unsigned trcid, ...);
void osiTraceTraIdEx(unsigned partype, unsigned trcid, ...);

void osiTraceSxIdBasic(unsigned id, unsigned nargs, unsigned fmt, ...);
void osiTraceSxIdEx(unsigned id, unsigned partype, unsigned fmt, ...);
void osiTraceSxBasic(unsigned id, unsigned nargs, const char *fmt, ...);
void osiTraceSxEx(unsigned id, unsigned partype, const char *fmt, ...);
void osiTraceSxOutput(unsigned id, const char *fmt, va_list ap);

void osiTracePubIdBasic(unsigned module, unsigned category, unsigned nargs, unsigned fmt, ...);
void osiTracePubIdEx(unsigned module, unsigned category, unsigned partype, unsigned fmt, ...);
void osiTracePubBasic(unsigned module, unsigned category, unsigned nargs, const char *fmt, ...);
void osiTracePubEx(unsigned module, unsigned category, unsigned partype, const char *fmt, ...);

void osiTraceLteIdBasic(unsigned module, unsigned category, unsigned nargs, unsigned fmt, ...);
void osiTraceLteIdEx(unsigned module, unsigned category, unsigned partype, unsigned fmt, ...);
void osiTraceLteBasic(unsigned module, unsigned category, unsigned nargs, const char *fmt, ...);
void osiTraceLteEx(unsigned module, unsigned category, unsigned partype, const char *fmt, ...);

#ifdef OSI_LOG_USE_PRINTF
extern int printf(const char *format, ...);
#define __OSI_LOGB(level, fmtid, fmt, ...) printf(fmt, ##__VA_ARGS__)
#define __OSI_LOGX(level, partype, fmtid, fmt, ...) printf(fmt, ##__VA_ARGS__)
#define __OSI_PRINTF(level, fmt, ...) printf(fmt, ##__VA_ARGS__)
#else
#ifdef CONFIG_KERNEL_DISABLE_TRACEID
#define __OSI_LOG_DISABLE_ID 1
#else
#define __OSI_LOG_DISABLE_ID 0
#endif
#define __OSI_LOGB(level, fmtid, fmt, ...)                                                                             \
    do                                                                                                                 \
    {                                                                                                                  \
        if (OSI_LOCAL_LOG_LEVEL >= level)                                                                              \
        {                                                                                                              \
            if ((fmtid) == 0 || __OSI_LOG_DISABLE_ID)                                                                  \
                __OSI_LOGB_IMP((level << 28) | (OSI_LOCAL_LOG_TAG), OSI_VA_NARGS(__VA_ARGS__), fmt, ##__VA_ARGS__);    \
            else                                                                                                       \
                __OSI_DLOGB_IMP((level << 28) | (OSI_LOCAL_LOG_TAG), OSI_VA_NARGS(__VA_ARGS__), fmtid, ##__VA_ARGS__); \
        }                                                                                                              \
    } while (0)

#define __OSI_LOGX(level, partype, fmtid, fmt, ...)                                                  \
    do                                                                                               \
    {                                                                                                \
        if (OSI_LOCAL_LOG_LEVEL >= level)                                                            \
        {                                                                                            \
            if ((fmtid) == 0 || __OSI_LOG_DISABLE_ID)                                                \
                __OSI_LOGX_IMP((level << 28) | (OSI_LOCAL_LOG_TAG), partype, fmt, ##__VA_ARGS__);    \
            else                                                                                     \
                __OSI_DLOGX_IMP((level << 28) | (OSI_LOCAL_LOG_TAG), partype, fmtid, ##__VA_ARGS__); \
        }                                                                                            \
    } while (0)
#define __OSI_PRINTF(level, fmt, ...)                                                \
    do                                                                               \
    {                                                                                \
        if (OSI_LOCAL_LOG_LEVEL >= level)                                            \
            osiTracePrintf((level << 28) | (OSI_LOCAL_LOG_TAG), fmt, ##__VA_ARGS__); \
    } while (0)

#define __OSI_LOGB_IMP(tag, nargs, fmt, ...) osiTraceBasic(tag, nargs, fmt, ##__VA_ARGS__)
#define __OSI_LOGX_IMP(tag, partype, fmt, ...) osiTraceEx(tag, partype, fmt, ##__VA_ARGS__)
#define __OSI_DLOGB_IMP(tag, nargs, fmtid, ...) osiTraceIdBasic(tag, nargs, fmtid, ##__VA_ARGS__)
#define __OSI_DLOGX_IMP(tag, partype, fmtid, ...) osiTraceIdEx(tag, partype, fmtid, ##__VA_ARGS__)
#endif

enum
{
    __OSI_LOGPAR_I = 1,
    __OSI_LOGPAR_D = 2,
    __OSI_LOGPAR_F = 3,
    __OSI_LOGPAR_S = 4,
    __OSI_LOGPAR_M = 5
};

static inline unsigned OSI_TSMAP_PARTYPE(unsigned n, unsigned tsmap)
{
    unsigned partype = 0;
    if ((n) >= 1)
        partype |= (((tsmap)&0x01) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 0;
    if ((n) >= 2)
        partype |= (((tsmap)&0x02) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 4;
    if ((n) >= 3)
        partype |= (((tsmap)&0x04) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 8;
    if ((n) >= 4)
        partype |= (((tsmap)&0x08) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 12;
    if ((n) >= 5)
        partype |= (((tsmap)&0x10) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 16;
    if ((n) >= 6)
        partype |= (((tsmap)&0x20) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 20;
    if ((n) >= 7)
        partype |= (((tsmap)&0x40) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 24;
    if ((n) >= 8)
        partype |= (((tsmap)&0x80) ? __OSI_LOGPAR_S : __OSI_LOGPAR_I) << 28;
    return partype;
}

#define __OSI_SXPRINTF(id, fmt, ...)                                        \
    do                                                                      \
    {                                                                       \
        unsigned tdb = (id) & (1 << 12);                                    \
        unsigned tsmap = ((id) >> 15) & 0x3f;                               \
        unsigned nargs = OSI_VA_NARGS(__VA_ARGS__);                         \
        unsigned partype = OSI_TSMAP_PARTYPE(nargs, tsmap);                 \
        if (tdb && tsmap == 0)                                              \
            osiTraceSxIdBasic(id, nargs, (unsigned)(fmt), ##__VA_ARGS__);   \
        else if (tdb && tsmap != 0)                                         \
            osiTraceSxIdEx(id, partype, (unsigned)(fmt), ##__VA_ARGS__);    \
        else if (tsmap == 0)                                                \
            osiTraceSxBasic(id, nargs, (const char *)(fmt), ##__VA_ARGS__); \
        else                                                                \
            osiTraceSxEx(id, partype, (const char *)(fmt), ##__VA_ARGS__);  \
    } while (0)

#define __OSI_SXDUMP(id, fmt, data, size) osiTraceSxIdEx(id, OSI_LOGPAR_M, 0x10005236, size, data)

#define __OSI_SX_TRACE(id, trcid, fmt, ...)                                         \
    do                                                                              \
    {                                                                               \
        if (trcid == 0)                                                             \
            osiTraceSxBasic(id, OSI_VA_NARGS(__VA_ARGS__), fmt, ##__VA_ARGS__);     \
        else                                                                        \
            osiTraceSxIdBasic(id, OSI_VA_NARGS(__VA_ARGS__), trcid, ##__VA_ARGS__); \
    } while (0)
#define __OSI_SX_TRACEX(id, partype, trcid, fmt, ...)          \
    do                                                         \
    {                                                          \
        if (trcid == 0)                                        \
            osiTraceSxEx(id, partype, fmt, ##__VA_ARGS__);     \
        else                                                   \
            osiTraceSxIdEx(id, partype, trcid, ##__VA_ARGS__); \
    } while (0)

#define OSI_TRACE_CATEGORY_CONTROL (0xffffffff)
#define OSI_TRACE_PUB_MODULE_CTRL (0xffffffff)
#define OSI_TRACE_LTE_MODULE_CTRL (0xffffffff)

#define __OSI_PUB_TRACE(module, category, trcid, fmt, ...)                                             \
    do                                                                                                 \
    {                                                                                                  \
        if ((OSI_TRACE_PUB_MODULE_CTRL & (module)) && (OSI_TRACE_CATEGORY_CONTROL & (category)))       \
        {                                                                                              \
            if (trcid == 0)                                                                            \
                osiTracePubBasic(module, category, OSI_VA_NARGS(__VA_ARGS__), fmt, ##__VA_ARGS__);     \
            else                                                                                       \
                osiTracePubIdBasic(module, category, OSI_VA_NARGS(__VA_ARGS__), trcid, ##__VA_ARGS__); \
        }                                                                                              \
    } while (0)
#define __OSI_PUB_TRACEX(module, category, partype, trcid, fmt, ...)                             \
    do                                                                                           \
    {                                                                                            \
        if ((OSI_TRACE_PUB_MODULE_CTRL & (module)) && (OSI_TRACE_CATEGORY_CONTROL & (category))) \
        {                                                                                        \
            if (trcid == 0)                                                                      \
                osiTracePubEx(module, category, partype, fmt, ##__VA_ARGS__);                    \
            else                                                                                 \
                osiTracePubIdEx(module, category, partype, trcid, ##__VA_ARGS__);                \
        }                                                                                        \
    } while (0)
#define __OSI_LTE_TRACE(module, category, trcid, fmt, ...)                                             \
    do                                                                                                 \
    {                                                                                                  \
        if ((OSI_TRACE_PUB_MODULE_CTRL & (module)) && (OSI_TRACE_CATEGORY_CONTROL & (category)))       \
        {                                                                                              \
            if (trcid == 0)                                                                            \
                osiTraceLteBasic(module, category, OSI_VA_NARGS(__VA_ARGS__), fmt, ##__VA_ARGS__);     \
            else                                                                                       \
                osiTraceLteIdBasic(module, category, OSI_VA_NARGS(__VA_ARGS__), trcid, ##__VA_ARGS__); \
        }                                                                                              \
    } while (0)
#define __OSI_LTE_TRACEX(module, category, partype, trcid, fmt, ...)                             \
    do                                                                                           \
    {                                                                                            \
        if ((OSI_TRACE_LTE_MODULE_CTRL & (module)) && (OSI_TRACE_CATEGORY_CONTROL & (category))) \
        {                                                                                        \
            if (trcid == 0)                                                                      \
                osiTraceLteEx(module, category, partype, fmt, ##__VA_ARGS__);                    \
            else                                                                                 \
                osiTraceLteIdEx(module, category, partype, trcid, ##__VA_ARGS__);                \
        }                                                                                        \
    } while (0)
#define __OSI_TRACE(trcid, fmt, ...)                                             \
    do                                                                           \
    {                                                                            \
        if (trcid == 0)                                                          \
            osiTraceTraBasic(OSI_VA_NARGS(__VA_ARGS__), fmt, ##__VA_ARGS__);     \
        else                                                                     \
            osiTraceTraIdBasic(OSI_VA_NARGS(__VA_ARGS__), trcid, ##__VA_ARGS__); \
    } while (0)
#define __OSI_TRACEX(partype, trcid, fmt, ...)              \
    do                                                      \
    {                                                       \
        if (trcid == 0)                                     \
            osiTraceTraEx(partype, fmt, ##__VA_ARGS__);     \
        else                                                \
            osiTraceTraIdEx(partype, trcid, ##__VA_ARGS__); \
    } while (0)

#define __OSI_LOGPAR_IMP2(count, ...) __OSI_LOGPAR_X##count(__VA_ARGS__)
#define __OSI_LOGPAR_IMP1(count, ...) __OSI_LOGPAR_IMP2(count, __VA_ARGS__)
#define __OSI_LOGPAR(...) __OSI_LOGPAR_IMP1(OSI_VA_NARGS(__VA_ARGS__), __VA_ARGS__)

#define __OSI_LOGPAR_POS(n, p) (__OSI_LOGPAR_##p << (n * 4))
#define __OSI_LOGPAR_X1(a) (__OSI_LOGPAR_POS(0, a))
#define __OSI_LOGPAR_X2(a, b) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b))
#define __OSI_LOGPAR_X3(a, b, c) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b) | __OSI_LOGPAR_POS(2, c))
#define __OSI_LOGPAR_X4(a, b, c, d) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b) | __OSI_LOGPAR_POS(2, c) | __OSI_LOGPAR_POS(3, d))
#define __OSI_LOGPAR_X5(a, b, c, d, e) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b) | __OSI_LOGPAR_POS(2, c) | __OSI_LOGPAR_POS(3, d) | __OSI_LOGPAR_POS(4, e))
#define __OSI_LOGPAR_X6(a, b, c, d, e, f) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b) | __OSI_LOGPAR_POS(2, c) | __OSI_LOGPAR_POS(3, d) | __OSI_LOGPAR_POS(4, e) | __OSI_LOGPAR_POS(5, f))
#define __OSI_LOGPAR_X7(a, b, c, d, e, f, g) (__OSI_LOGPAR_POS(0, a) | __OSI_LOGPAR_POS(1, b) | __OSI_LOGPAR_POS(2, c) | __OSI_LOGPAR_POS(3, d) | __OSI_LOGPAR_POS(4, e) | __OSI_LOGPAR_POS(5, f) | __OSI_LOGPAR_POS(6, g))

/*
for a in I D F S M; do
    echo "#define OSI_LOGPAR_${a} __OSI_LOGPAR_X1($a)"
    for b in I D F S M; do
        echo "#define OSI_LOGPAR_${a}${b} __OSI_LOGPAR_X2($a, $b)"
        for c in I D F S M; do
            echo "#define OSI_LOGPAR_${a}${b}${c} __OSI_LOGPAR_X3($a, $b, $c)"
            for d in I D F S M; do
                echo "#define OSI_LOGPAR_${a}${b}${c}${d} __OSI_LOGPAR_X4($a, $b, $c, $d)"
            done
        done
    done
done
*/
#define OSI_LOGPAR_I __OSI_LOGPAR_X1(I)
#define OSI_LOGPAR_II __OSI_LOGPAR_X2(I, I)
#define OSI_LOGPAR_III __OSI_LOGPAR_X3(I, I, I)
#define OSI_LOGPAR_IIII __OSI_LOGPAR_X4(I, I, I, I)
#define OSI_LOGPAR_IIID __OSI_LOGPAR_X4(I, I, I, D)
#define OSI_LOGPAR_IIIF __OSI_LOGPAR_X4(I, I, I, F)
#define OSI_LOGPAR_IIIS __OSI_LOGPAR_X4(I, I, I, S)
#define OSI_LOGPAR_IIIM __OSI_LOGPAR_X4(I, I, I, M)
#define OSI_LOGPAR_IID __OSI_LOGPAR_X3(I, I, D)
#define OSI_LOGPAR_IIDI __OSI_LOGPAR_X4(I, I, D, I)
#define OSI_LOGPAR_IIDD __OSI_LOGPAR_X4(I, I, D, D)
#define OSI_LOGPAR_IIDF __OSI_LOGPAR_X4(I, I, D, F)
#define OSI_LOGPAR_IIDS __OSI_LOGPAR_X4(I, I, D, S)
#define OSI_LOGPAR_IIDM __OSI_LOGPAR_X4(I, I, D, M)
#define OSI_LOGPAR_IIF __OSI_LOGPAR_X3(I, I, F)
#define OSI_LOGPAR_IIFI __OSI_LOGPAR_X4(I, I, F, I)
#define OSI_LOGPAR_IIFD __OSI_LOGPAR_X4(I, I, F, D)
#define OSI_LOGPAR_IIFF __OSI_LOGPAR_X4(I, I, F, F)
#define OSI_LOGPAR_IIFS __OSI_LOGPAR_X4(I, I, F, S)
#define OSI_LOGPAR_IIFM __OSI_LOGPAR_X4(I, I, F, M)
#define OSI_LOGPAR_IIS __OSI_LOGPAR_X3(I, I, S)
#define OSI_LOGPAR_IISI __OSI_LOGPAR_X4(I, I, S, I)
#define OSI_LOGPAR_IISD __OSI_LOGPAR_X4(I, I, S, D)
#define OSI_LOGPAR_IISF __OSI_LOGPAR_X4(I, I, S, F)
#define OSI_LOGPAR_IISS __OSI_LOGPAR_X4(I, I, S, S)
#define OSI_LOGPAR_IISM __OSI_LOGPAR_X4(I, I, S, M)
#define OSI_LOGPAR_IIM __OSI_LOGPAR_X3(I, I, M)
#define OSI_LOGPAR_IIMI __OSI_LOGPAR_X4(I, I, M, I)
#define OSI_LOGPAR_IIMD __OSI_LOGPAR_X4(I, I, M, D)
#define OSI_LOGPAR_IIMF __OSI_LOGPAR_X4(I, I, M, F)
#define OSI_LOGPAR_IIMS __OSI_LOGPAR_X4(I, I, M, S)
#define OSI_LOGPAR_IIMM __OSI_LOGPAR_X4(I, I, M, M)
#define OSI_LOGPAR_ID __OSI_LOGPAR_X2(I, D)
#define OSI_LOGPAR_IDI __OSI_LOGPAR_X3(I, D, I)
#define OSI_LOGPAR_IDII __OSI_LOGPAR_X4(I, D, I, I)
#define OSI_LOGPAR_IDID __OSI_LOGPAR_X4(I, D, I, D)
#define OSI_LOGPAR_IDIF __OSI_LOGPAR_X4(I, D, I, F)
#define OSI_LOGPAR_IDIS __OSI_LOGPAR_X4(I, D, I, S)
#define OSI_LOGPAR_IDIM __OSI_LOGPAR_X4(I, D, I, M)
#define OSI_LOGPAR_IDD __OSI_LOGPAR_X3(I, D, D)
#define OSI_LOGPAR_IDDI __OSI_LOGPAR_X4(I, D, D, I)
#define OSI_LOGPAR_IDDD __OSI_LOGPAR_X4(I, D, D, D)
#define OSI_LOGPAR_IDDF __OSI_LOGPAR_X4(I, D, D, F)
#define OSI_LOGPAR_IDDS __OSI_LOGPAR_X4(I, D, D, S)
#define OSI_LOGPAR_IDDM __OSI_LOGPAR_X4(I, D, D, M)
#define OSI_LOGPAR_IDF __OSI_LOGPAR_X3(I, D, F)
#define OSI_LOGPAR_IDFI __OSI_LOGPAR_X4(I, D, F, I)
#define OSI_LOGPAR_IDFD __OSI_LOGPAR_X4(I, D, F, D)
#define OSI_LOGPAR_IDFF __OSI_LOGPAR_X4(I, D, F, F)
#define OSI_LOGPAR_IDFS __OSI_LOGPAR_X4(I, D, F, S)
#define OSI_LOGPAR_IDFM __OSI_LOGPAR_X4(I, D, F, M)
#define OSI_LOGPAR_IDS __OSI_LOGPAR_X3(I, D, S)
#define OSI_LOGPAR_IDSI __OSI_LOGPAR_X4(I, D, S, I)
#define OSI_LOGPAR_IDSD __OSI_LOGPAR_X4(I, D, S, D)
#define OSI_LOGPAR_IDSF __OSI_LOGPAR_X4(I, D, S, F)
#define OSI_LOGPAR_IDSS __OSI_LOGPAR_X4(I, D, S, S)
#define OSI_LOGPAR_IDSM __OSI_LOGPAR_X4(I, D, S, M)
#define OSI_LOGPAR_IDM __OSI_LOGPAR_X3(I, D, M)
#define OSI_LOGPAR_IDMI __OSI_LOGPAR_X4(I, D, M, I)
#define OSI_LOGPAR_IDMD __OSI_LOGPAR_X4(I, D, M, D)
#define OSI_LOGPAR_IDMF __OSI_LOGPAR_X4(I, D, M, F)
#define OSI_LOGPAR_IDMS __OSI_LOGPAR_X4(I, D, M, S)
#define OSI_LOGPAR_IDMM __OSI_LOGPAR_X4(I, D, M, M)
#define OSI_LOGPAR_IF __OSI_LOGPAR_X2(I, F)
#define OSI_LOGPAR_IFI __OSI_LOGPAR_X3(I, F, I)
#define OSI_LOGPAR_IFII __OSI_LOGPAR_X4(I, F, I, I)
#define OSI_LOGPAR_IFID __OSI_LOGPAR_X4(I, F, I, D)
#define OSI_LOGPAR_IFIF __OSI_LOGPAR_X4(I, F, I, F)
#define OSI_LOGPAR_IFIS __OSI_LOGPAR_X4(I, F, I, S)
#define OSI_LOGPAR_IFIM __OSI_LOGPAR_X4(I, F, I, M)
#define OSI_LOGPAR_IFD __OSI_LOGPAR_X3(I, F, D)
#define OSI_LOGPAR_IFDI __OSI_LOGPAR_X4(I, F, D, I)
#define OSI_LOGPAR_IFDD __OSI_LOGPAR_X4(I, F, D, D)
#define OSI_LOGPAR_IFDF __OSI_LOGPAR_X4(I, F, D, F)
#define OSI_LOGPAR_IFDS __OSI_LOGPAR_X4(I, F, D, S)
#define OSI_LOGPAR_IFDM __OSI_LOGPAR_X4(I, F, D, M)
#define OSI_LOGPAR_IFF __OSI_LOGPAR_X3(I, F, F)
#define OSI_LOGPAR_IFFI __OSI_LOGPAR_X4(I, F, F, I)
#define OSI_LOGPAR_IFFD __OSI_LOGPAR_X4(I, F, F, D)
#define OSI_LOGPAR_IFFF __OSI_LOGPAR_X4(I, F, F, F)
#define OSI_LOGPAR_IFFS __OSI_LOGPAR_X4(I, F, F, S)
#define OSI_LOGPAR_IFFM __OSI_LOGPAR_X4(I, F, F, M)
#define OSI_LOGPAR_IFS __OSI_LOGPAR_X3(I, F, S)
#define OSI_LOGPAR_IFSI __OSI_LOGPAR_X4(I, F, S, I)
#define OSI_LOGPAR_IFSD __OSI_LOGPAR_X4(I, F, S, D)
#define OSI_LOGPAR_IFSF __OSI_LOGPAR_X4(I, F, S, F)
#define OSI_LOGPAR_IFSS __OSI_LOGPAR_X4(I, F, S, S)
#define OSI_LOGPAR_IFSM __OSI_LOGPAR_X4(I, F, S, M)
#define OSI_LOGPAR_IFM __OSI_LOGPAR_X3(I, F, M)
#define OSI_LOGPAR_IFMI __OSI_LOGPAR_X4(I, F, M, I)
#define OSI_LOGPAR_IFMD __OSI_LOGPAR_X4(I, F, M, D)
#define OSI_LOGPAR_IFMF __OSI_LOGPAR_X4(I, F, M, F)
#define OSI_LOGPAR_IFMS __OSI_LOGPAR_X4(I, F, M, S)
#define OSI_LOGPAR_IFMM __OSI_LOGPAR_X4(I, F, M, M)
#define OSI_LOGPAR_IS __OSI_LOGPAR_X2(I, S)
#define OSI_LOGPAR_ISI __OSI_LOGPAR_X3(I, S, I)
#define OSI_LOGPAR_ISII __OSI_LOGPAR_X4(I, S, I, I)
#define OSI_LOGPAR_ISID __OSI_LOGPAR_X4(I, S, I, D)
#define OSI_LOGPAR_ISIF __OSI_LOGPAR_X4(I, S, I, F)
#define OSI_LOGPAR_ISIS __OSI_LOGPAR_X4(I, S, I, S)
#define OSI_LOGPAR_ISIM __OSI_LOGPAR_X4(I, S, I, M)
#define OSI_LOGPAR_ISD __OSI_LOGPAR_X3(I, S, D)
#define OSI_LOGPAR_ISDI __OSI_LOGPAR_X4(I, S, D, I)
#define OSI_LOGPAR_ISDD __OSI_LOGPAR_X4(I, S, D, D)
#define OSI_LOGPAR_ISDF __OSI_LOGPAR_X4(I, S, D, F)
#define OSI_LOGPAR_ISDS __OSI_LOGPAR_X4(I, S, D, S)
#define OSI_LOGPAR_ISDM __OSI_LOGPAR_X4(I, S, D, M)
#define OSI_LOGPAR_ISF __OSI_LOGPAR_X3(I, S, F)
#define OSI_LOGPAR_ISFI __OSI_LOGPAR_X4(I, S, F, I)
#define OSI_LOGPAR_ISFD __OSI_LOGPAR_X4(I, S, F, D)
#define OSI_LOGPAR_ISFF __OSI_LOGPAR_X4(I, S, F, F)
#define OSI_LOGPAR_ISFS __OSI_LOGPAR_X4(I, S, F, S)
#define OSI_LOGPAR_ISFM __OSI_LOGPAR_X4(I, S, F, M)
#define OSI_LOGPAR_ISS __OSI_LOGPAR_X3(I, S, S)
#define OSI_LOGPAR_ISSI __OSI_LOGPAR_X4(I, S, S, I)
#define OSI_LOGPAR_ISSD __OSI_LOGPAR_X4(I, S, S, D)
#define OSI_LOGPAR_ISSF __OSI_LOGPAR_X4(I, S, S, F)
#define OSI_LOGPAR_ISSS __OSI_LOGPAR_X4(I, S, S, S)
#define OSI_LOGPAR_ISSM __OSI_LOGPAR_X4(I, S, S, M)
#define OSI_LOGPAR_ISM __OSI_LOGPAR_X3(I, S, M)
#define OSI_LOGPAR_ISMI __OSI_LOGPAR_X4(I, S, M, I)
#define OSI_LOGPAR_ISMD __OSI_LOGPAR_X4(I, S, M, D)
#define OSI_LOGPAR_ISMF __OSI_LOGPAR_X4(I, S, M, F)
#define OSI_LOGPAR_ISMS __OSI_LOGPAR_X4(I, S, M, S)
#define OSI_LOGPAR_ISMM __OSI_LOGPAR_X4(I, S, M, M)
#define OSI_LOGPAR_IM __OSI_LOGPAR_X2(I, M)
#define OSI_LOGPAR_IMI __OSI_LOGPAR_X3(I, M, I)
#define OSI_LOGPAR_IMII __OSI_LOGPAR_X4(I, M, I, I)
#define OSI_LOGPAR_IMID __OSI_LOGPAR_X4(I, M, I, D)
#define OSI_LOGPAR_IMIF __OSI_LOGPAR_X4(I, M, I, F)
#define OSI_LOGPAR_IMIS __OSI_LOGPAR_X4(I, M, I, S)
#define OSI_LOGPAR_IMIM __OSI_LOGPAR_X4(I, M, I, M)
#define OSI_LOGPAR_IMD __OSI_LOGPAR_X3(I, M, D)
#define OSI_LOGPAR_IMDI __OSI_LOGPAR_X4(I, M, D, I)
#define OSI_LOGPAR_IMDD __OSI_LOGPAR_X4(I, M, D, D)
#define OSI_LOGPAR_IMDF __OSI_LOGPAR_X4(I, M, D, F)
#define OSI_LOGPAR_IMDS __OSI_LOGPAR_X4(I, M, D, S)
#define OSI_LOGPAR_IMDM __OSI_LOGPAR_X4(I, M, D, M)
#define OSI_LOGPAR_IMF __OSI_LOGPAR_X3(I, M, F)
#define OSI_LOGPAR_IMFI __OSI_LOGPAR_X4(I, M, F, I)
#define OSI_LOGPAR_IMFD __OSI_LOGPAR_X4(I, M, F, D)
#define OSI_LOGPAR_IMFF __OSI_LOGPAR_X4(I, M, F, F)
#define OSI_LOGPAR_IMFS __OSI_LOGPAR_X4(I, M, F, S)
#define OSI_LOGPAR_IMFM __OSI_LOGPAR_X4(I, M, F, M)
#define OSI_LOGPAR_IMS __OSI_LOGPAR_X3(I, M, S)
#define OSI_LOGPAR_IMSI __OSI_LOGPAR_X4(I, M, S, I)
#define OSI_LOGPAR_IMSD __OSI_LOGPAR_X4(I, M, S, D)
#define OSI_LOGPAR_IMSF __OSI_LOGPAR_X4(I, M, S, F)
#define OSI_LOGPAR_IMSS __OSI_LOGPAR_X4(I, M, S, S)
#define OSI_LOGPAR_IMSM __OSI_LOGPAR_X4(I, M, S, M)
#define OSI_LOGPAR_IMM __OSI_LOGPAR_X3(I, M, M)
#define OSI_LOGPAR_IMMI __OSI_LOGPAR_X4(I, M, M, I)
#define OSI_LOGPAR_IMMD __OSI_LOGPAR_X4(I, M, M, D)
#define OSI_LOGPAR_IMMF __OSI_LOGPAR_X4(I, M, M, F)
#define OSI_LOGPAR_IMMS __OSI_LOGPAR_X4(I, M, M, S)
#define OSI_LOGPAR_IMMM __OSI_LOGPAR_X4(I, M, M, M)
#define OSI_LOGPAR_D __OSI_LOGPAR_X1(D)
#define OSI_LOGPAR_DI __OSI_LOGPAR_X2(D, I)
#define OSI_LOGPAR_DII __OSI_LOGPAR_X3(D, I, I)
#define OSI_LOGPAR_DIII __OSI_LOGPAR_X4(D, I, I, I)
#define OSI_LOGPAR_DIID __OSI_LOGPAR_X4(D, I, I, D)
#define OSI_LOGPAR_DIIF __OSI_LOGPAR_X4(D, I, I, F)
#define OSI_LOGPAR_DIIS __OSI_LOGPAR_X4(D, I, I, S)
#define OSI_LOGPAR_DIIM __OSI_LOGPAR_X4(D, I, I, M)
#define OSI_LOGPAR_DID __OSI_LOGPAR_X3(D, I, D)
#define OSI_LOGPAR_DIDI __OSI_LOGPAR_X4(D, I, D, I)
#define OSI_LOGPAR_DIDD __OSI_LOGPAR_X4(D, I, D, D)
#define OSI_LOGPAR_DIDF __OSI_LOGPAR_X4(D, I, D, F)
#define OSI_LOGPAR_DIDS __OSI_LOGPAR_X4(D, I, D, S)
#define OSI_LOGPAR_DIDM __OSI_LOGPAR_X4(D, I, D, M)
#define OSI_LOGPAR_DIF __OSI_LOGPAR_X3(D, I, F)
#define OSI_LOGPAR_DIFI __OSI_LOGPAR_X4(D, I, F, I)
#define OSI_LOGPAR_DIFD __OSI_LOGPAR_X4(D, I, F, D)
#define OSI_LOGPAR_DIFF __OSI_LOGPAR_X4(D, I, F, F)
#define OSI_LOGPAR_DIFS __OSI_LOGPAR_X4(D, I, F, S)
#define OSI_LOGPAR_DIFM __OSI_LOGPAR_X4(D, I, F, M)
#define OSI_LOGPAR_DIS __OSI_LOGPAR_X3(D, I, S)
#define OSI_LOGPAR_DISI __OSI_LOGPAR_X4(D, I, S, I)
#define OSI_LOGPAR_DISD __OSI_LOGPAR_X4(D, I, S, D)
#define OSI_LOGPAR_DISF __OSI_LOGPAR_X4(D, I, S, F)
#define OSI_LOGPAR_DISS __OSI_LOGPAR_X4(D, I, S, S)
#define OSI_LOGPAR_DISM __OSI_LOGPAR_X4(D, I, S, M)
#define OSI_LOGPAR_DIM __OSI_LOGPAR_X3(D, I, M)
#define OSI_LOGPAR_DIMI __OSI_LOGPAR_X4(D, I, M, I)
#define OSI_LOGPAR_DIMD __OSI_LOGPAR_X4(D, I, M, D)
#define OSI_LOGPAR_DIMF __OSI_LOGPAR_X4(D, I, M, F)
#define OSI_LOGPAR_DIMS __OSI_LOGPAR_X4(D, I, M, S)
#define OSI_LOGPAR_DIMM __OSI_LOGPAR_X4(D, I, M, M)
#define OSI_LOGPAR_DD __OSI_LOGPAR_X2(D, D)
#define OSI_LOGPAR_DDI __OSI_LOGPAR_X3(D, D, I)
#define OSI_LOGPAR_DDII __OSI_LOGPAR_X4(D, D, I, I)
#define OSI_LOGPAR_DDID __OSI_LOGPAR_X4(D, D, I, D)
#define OSI_LOGPAR_DDIF __OSI_LOGPAR_X4(D, D, I, F)
#define OSI_LOGPAR_DDIS __OSI_LOGPAR_X4(D, D, I, S)
#define OSI_LOGPAR_DDIM __OSI_LOGPAR_X4(D, D, I, M)
#define OSI_LOGPAR_DDD __OSI_LOGPAR_X3(D, D, D)
#define OSI_LOGPAR_DDDI __OSI_LOGPAR_X4(D, D, D, I)
#define OSI_LOGPAR_DDDD __OSI_LOGPAR_X4(D, D, D, D)
#define OSI_LOGPAR_DDDF __OSI_LOGPAR_X4(D, D, D, F)
#define OSI_LOGPAR_DDDS __OSI_LOGPAR_X4(D, D, D, S)
#define OSI_LOGPAR_DDDM __OSI_LOGPAR_X4(D, D, D, M)
#define OSI_LOGPAR_DDF __OSI_LOGPAR_X3(D, D, F)
#define OSI_LOGPAR_DDFI __OSI_LOGPAR_X4(D, D, F, I)
#define OSI_LOGPAR_DDFD __OSI_LOGPAR_X4(D, D, F, D)
#define OSI_LOGPAR_DDFF __OSI_LOGPAR_X4(D, D, F, F)
#define OSI_LOGPAR_DDFS __OSI_LOGPAR_X4(D, D, F, S)
#define OSI_LOGPAR_DDFM __OSI_LOGPAR_X4(D, D, F, M)
#define OSI_LOGPAR_DDS __OSI_LOGPAR_X3(D, D, S)
#define OSI_LOGPAR_DDSI __OSI_LOGPAR_X4(D, D, S, I)
#define OSI_LOGPAR_DDSD __OSI_LOGPAR_X4(D, D, S, D)
#define OSI_LOGPAR_DDSF __OSI_LOGPAR_X4(D, D, S, F)
#define OSI_LOGPAR_DDSS __OSI_LOGPAR_X4(D, D, S, S)
#define OSI_LOGPAR_DDSM __OSI_LOGPAR_X4(D, D, S, M)
#define OSI_LOGPAR_DDM __OSI_LOGPAR_X3(D, D, M)
#define OSI_LOGPAR_DDMI __OSI_LOGPAR_X4(D, D, M, I)
#define OSI_LOGPAR_DDMD __OSI_LOGPAR_X4(D, D, M, D)
#define OSI_LOGPAR_DDMF __OSI_LOGPAR_X4(D, D, M, F)
#define OSI_LOGPAR_DDMS __OSI_LOGPAR_X4(D, D, M, S)
#define OSI_LOGPAR_DDMM __OSI_LOGPAR_X4(D, D, M, M)
#define OSI_LOGPAR_DF __OSI_LOGPAR_X2(D, F)
#define OSI_LOGPAR_DFI __OSI_LOGPAR_X3(D, F, I)
#define OSI_LOGPAR_DFII __OSI_LOGPAR_X4(D, F, I, I)
#define OSI_LOGPAR_DFID __OSI_LOGPAR_X4(D, F, I, D)
#define OSI_LOGPAR_DFIF __OSI_LOGPAR_X4(D, F, I, F)
#define OSI_LOGPAR_DFIS __OSI_LOGPAR_X4(D, F, I, S)
#define OSI_LOGPAR_DFIM __OSI_LOGPAR_X4(D, F, I, M)
#define OSI_LOGPAR_DFD __OSI_LOGPAR_X3(D, F, D)
#define OSI_LOGPAR_DFDI __OSI_LOGPAR_X4(D, F, D, I)
#define OSI_LOGPAR_DFDD __OSI_LOGPAR_X4(D, F, D, D)
#define OSI_LOGPAR_DFDF __OSI_LOGPAR_X4(D, F, D, F)
#define OSI_LOGPAR_DFDS __OSI_LOGPAR_X4(D, F, D, S)
#define OSI_LOGPAR_DFDM __OSI_LOGPAR_X4(D, F, D, M)
#define OSI_LOGPAR_DFF __OSI_LOGPAR_X3(D, F, F)
#define OSI_LOGPAR_DFFI __OSI_LOGPAR_X4(D, F, F, I)
#define OSI_LOGPAR_DFFD __OSI_LOGPAR_X4(D, F, F, D)
#define OSI_LOGPAR_DFFF __OSI_LOGPAR_X4(D, F, F, F)
#define OSI_LOGPAR_DFFS __OSI_LOGPAR_X4(D, F, F, S)
#define OSI_LOGPAR_DFFM __OSI_LOGPAR_X4(D, F, F, M)
#define OSI_LOGPAR_DFS __OSI_LOGPAR_X3(D, F, S)
#define OSI_LOGPAR_DFSI __OSI_LOGPAR_X4(D, F, S, I)
#define OSI_LOGPAR_DFSD __OSI_LOGPAR_X4(D, F, S, D)
#define OSI_LOGPAR_DFSF __OSI_LOGPAR_X4(D, F, S, F)
#define OSI_LOGPAR_DFSS __OSI_LOGPAR_X4(D, F, S, S)
#define OSI_LOGPAR_DFSM __OSI_LOGPAR_X4(D, F, S, M)
#define OSI_LOGPAR_DFM __OSI_LOGPAR_X3(D, F, M)
#define OSI_LOGPAR_DFMI __OSI_LOGPAR_X4(D, F, M, I)
#define OSI_LOGPAR_DFMD __OSI_LOGPAR_X4(D, F, M, D)
#define OSI_LOGPAR_DFMF __OSI_LOGPAR_X4(D, F, M, F)
#define OSI_LOGPAR_DFMS __OSI_LOGPAR_X4(D, F, M, S)
#define OSI_LOGPAR_DFMM __OSI_LOGPAR_X4(D, F, M, M)
#define OSI_LOGPAR_DS __OSI_LOGPAR_X2(D, S)
#define OSI_LOGPAR_DSI __OSI_LOGPAR_X3(D, S, I)
#define OSI_LOGPAR_DSII __OSI_LOGPAR_X4(D, S, I, I)
#define OSI_LOGPAR_DSID __OSI_LOGPAR_X4(D, S, I, D)
#define OSI_LOGPAR_DSIF __OSI_LOGPAR_X4(D, S, I, F)
#define OSI_LOGPAR_DSIS __OSI_LOGPAR_X4(D, S, I, S)
#define OSI_LOGPAR_DSIM __OSI_LOGPAR_X4(D, S, I, M)
#define OSI_LOGPAR_DSD __OSI_LOGPAR_X3(D, S, D)
#define OSI_LOGPAR_DSDI __OSI_LOGPAR_X4(D, S, D, I)
#define OSI_LOGPAR_DSDD __OSI_LOGPAR_X4(D, S, D, D)
#define OSI_LOGPAR_DSDF __OSI_LOGPAR_X4(D, S, D, F)
#define OSI_LOGPAR_DSDS __OSI_LOGPAR_X4(D, S, D, S)
#define OSI_LOGPAR_DSDM __OSI_LOGPAR_X4(D, S, D, M)
#define OSI_LOGPAR_DSF __OSI_LOGPAR_X3(D, S, F)
#define OSI_LOGPAR_DSFI __OSI_LOGPAR_X4(D, S, F, I)
#define OSI_LOGPAR_DSFD __OSI_LOGPAR_X4(D, S, F, D)
#define OSI_LOGPAR_DSFF __OSI_LOGPAR_X4(D, S, F, F)
#define OSI_LOGPAR_DSFS __OSI_LOGPAR_X4(D, S, F, S)
#define OSI_LOGPAR_DSFM __OSI_LOGPAR_X4(D, S, F, M)
#define OSI_LOGPAR_DSS __OSI_LOGPAR_X3(D, S, S)
#define OSI_LOGPAR_DSSI __OSI_LOGPAR_X4(D, S, S, I)
#define OSI_LOGPAR_DSSD __OSI_LOGPAR_X4(D, S, S, D)
#define OSI_LOGPAR_DSSF __OSI_LOGPAR_X4(D, S, S, F)
#define OSI_LOGPAR_DSSS __OSI_LOGPAR_X4(D, S, S, S)
#define OSI_LOGPAR_DSSM __OSI_LOGPAR_X4(D, S, S, M)
#define OSI_LOGPAR_DSM __OSI_LOGPAR_X3(D, S, M)
#define OSI_LOGPAR_DSMI __OSI_LOGPAR_X4(D, S, M, I)
#define OSI_LOGPAR_DSMD __OSI_LOGPAR_X4(D, S, M, D)
#define OSI_LOGPAR_DSMF __OSI_LOGPAR_X4(D, S, M, F)
#define OSI_LOGPAR_DSMS __OSI_LOGPAR_X4(D, S, M, S)
#define OSI_LOGPAR_DSMM __OSI_LOGPAR_X4(D, S, M, M)
#define OSI_LOGPAR_DM __OSI_LOGPAR_X2(D, M)
#define OSI_LOGPAR_DMI __OSI_LOGPAR_X3(D, M, I)
#define OSI_LOGPAR_DMII __OSI_LOGPAR_X4(D, M, I, I)
#define OSI_LOGPAR_DMID __OSI_LOGPAR_X4(D, M, I, D)
#define OSI_LOGPAR_DMIF __OSI_LOGPAR_X4(D, M, I, F)
#define OSI_LOGPAR_DMIS __OSI_LOGPAR_X4(D, M, I, S)
#define OSI_LOGPAR_DMIM __OSI_LOGPAR_X4(D, M, I, M)
#define OSI_LOGPAR_DMD __OSI_LOGPAR_X3(D, M, D)
#define OSI_LOGPAR_DMDI __OSI_LOGPAR_X4(D, M, D, I)
#define OSI_LOGPAR_DMDD __OSI_LOGPAR_X4(D, M, D, D)
#define OSI_LOGPAR_DMDF __OSI_LOGPAR_X4(D, M, D, F)
#define OSI_LOGPAR_DMDS __OSI_LOGPAR_X4(D, M, D, S)
#define OSI_LOGPAR_DMDM __OSI_LOGPAR_X4(D, M, D, M)
#define OSI_LOGPAR_DMF __OSI_LOGPAR_X3(D, M, F)
#define OSI_LOGPAR_DMFI __OSI_LOGPAR_X4(D, M, F, I)
#define OSI_LOGPAR_DMFD __OSI_LOGPAR_X4(D, M, F, D)
#define OSI_LOGPAR_DMFF __OSI_LOGPAR_X4(D, M, F, F)
#define OSI_LOGPAR_DMFS __OSI_LOGPAR_X4(D, M, F, S)
#define OSI_LOGPAR_DMFM __OSI_LOGPAR_X4(D, M, F, M)
#define OSI_LOGPAR_DMS __OSI_LOGPAR_X3(D, M, S)
#define OSI_LOGPAR_DMSI __OSI_LOGPAR_X4(D, M, S, I)
#define OSI_LOGPAR_DMSD __OSI_LOGPAR_X4(D, M, S, D)
#define OSI_LOGPAR_DMSF __OSI_LOGPAR_X4(D, M, S, F)
#define OSI_LOGPAR_DMSS __OSI_LOGPAR_X4(D, M, S, S)
#define OSI_LOGPAR_DMSM __OSI_LOGPAR_X4(D, M, S, M)
#define OSI_LOGPAR_DMM __OSI_LOGPAR_X3(D, M, M)
#define OSI_LOGPAR_DMMI __OSI_LOGPAR_X4(D, M, M, I)
#define OSI_LOGPAR_DMMD __OSI_LOGPAR_X4(D, M, M, D)
#define OSI_LOGPAR_DMMF __OSI_LOGPAR_X4(D, M, M, F)
#define OSI_LOGPAR_DMMS __OSI_LOGPAR_X4(D, M, M, S)
#define OSI_LOGPAR_DMMM __OSI_LOGPAR_X4(D, M, M, M)
#define OSI_LOGPAR_F __OSI_LOGPAR_X1(F)
#define OSI_LOGPAR_FI __OSI_LOGPAR_X2(F, I)
#define OSI_LOGPAR_FII __OSI_LOGPAR_X3(F, I, I)
#define OSI_LOGPAR_FIII __OSI_LOGPAR_X4(F, I, I, I)
#define OSI_LOGPAR_FIID __OSI_LOGPAR_X4(F, I, I, D)
#define OSI_LOGPAR_FIIF __OSI_LOGPAR_X4(F, I, I, F)
#define OSI_LOGPAR_FIIS __OSI_LOGPAR_X4(F, I, I, S)
#define OSI_LOGPAR_FIIM __OSI_LOGPAR_X4(F, I, I, M)
#define OSI_LOGPAR_FID __OSI_LOGPAR_X3(F, I, D)
#define OSI_LOGPAR_FIDI __OSI_LOGPAR_X4(F, I, D, I)
#define OSI_LOGPAR_FIDD __OSI_LOGPAR_X4(F, I, D, D)
#define OSI_LOGPAR_FIDF __OSI_LOGPAR_X4(F, I, D, F)
#define OSI_LOGPAR_FIDS __OSI_LOGPAR_X4(F, I, D, S)
#define OSI_LOGPAR_FIDM __OSI_LOGPAR_X4(F, I, D, M)
#define OSI_LOGPAR_FIF __OSI_LOGPAR_X3(F, I, F)
#define OSI_LOGPAR_FIFI __OSI_LOGPAR_X4(F, I, F, I)
#define OSI_LOGPAR_FIFD __OSI_LOGPAR_X4(F, I, F, D)
#define OSI_LOGPAR_FIFF __OSI_LOGPAR_X4(F, I, F, F)
#define OSI_LOGPAR_FIFS __OSI_LOGPAR_X4(F, I, F, S)
#define OSI_LOGPAR_FIFM __OSI_LOGPAR_X4(F, I, F, M)
#define OSI_LOGPAR_FIS __OSI_LOGPAR_X3(F, I, S)
#define OSI_LOGPAR_FISI __OSI_LOGPAR_X4(F, I, S, I)
#define OSI_LOGPAR_FISD __OSI_LOGPAR_X4(F, I, S, D)
#define OSI_LOGPAR_FISF __OSI_LOGPAR_X4(F, I, S, F)
#define OSI_LOGPAR_FISS __OSI_LOGPAR_X4(F, I, S, S)
#define OSI_LOGPAR_FISM __OSI_LOGPAR_X4(F, I, S, M)
#define OSI_LOGPAR_FIM __OSI_LOGPAR_X3(F, I, M)
#define OSI_LOGPAR_FIMI __OSI_LOGPAR_X4(F, I, M, I)
#define OSI_LOGPAR_FIMD __OSI_LOGPAR_X4(F, I, M, D)
#define OSI_LOGPAR_FIMF __OSI_LOGPAR_X4(F, I, M, F)
#define OSI_LOGPAR_FIMS __OSI_LOGPAR_X4(F, I, M, S)
#define OSI_LOGPAR_FIMM __OSI_LOGPAR_X4(F, I, M, M)
#define OSI_LOGPAR_FD __OSI_LOGPAR_X2(F, D)
#define OSI_LOGPAR_FDI __OSI_LOGPAR_X3(F, D, I)
#define OSI_LOGPAR_FDII __OSI_LOGPAR_X4(F, D, I, I)
#define OSI_LOGPAR_FDID __OSI_LOGPAR_X4(F, D, I, D)
#define OSI_LOGPAR_FDIF __OSI_LOGPAR_X4(F, D, I, F)
#define OSI_LOGPAR_FDIS __OSI_LOGPAR_X4(F, D, I, S)
#define OSI_LOGPAR_FDIM __OSI_LOGPAR_X4(F, D, I, M)
#define OSI_LOGPAR_FDD __OSI_LOGPAR_X3(F, D, D)
#define OSI_LOGPAR_FDDI __OSI_LOGPAR_X4(F, D, D, I)
#define OSI_LOGPAR_FDDD __OSI_LOGPAR_X4(F, D, D, D)
#define OSI_LOGPAR_FDDF __OSI_LOGPAR_X4(F, D, D, F)
#define OSI_LOGPAR_FDDS __OSI_LOGPAR_X4(F, D, D, S)
#define OSI_LOGPAR_FDDM __OSI_LOGPAR_X4(F, D, D, M)
#define OSI_LOGPAR_FDF __OSI_LOGPAR_X3(F, D, F)
#define OSI_LOGPAR_FDFI __OSI_LOGPAR_X4(F, D, F, I)
#define OSI_LOGPAR_FDFD __OSI_LOGPAR_X4(F, D, F, D)
#define OSI_LOGPAR_FDFF __OSI_LOGPAR_X4(F, D, F, F)
#define OSI_LOGPAR_FDFS __OSI_LOGPAR_X4(F, D, F, S)
#define OSI_LOGPAR_FDFM __OSI_LOGPAR_X4(F, D, F, M)
#define OSI_LOGPAR_FDS __OSI_LOGPAR_X3(F, D, S)
#define OSI_LOGPAR_FDSI __OSI_LOGPAR_X4(F, D, S, I)
#define OSI_LOGPAR_FDSD __OSI_LOGPAR_X4(F, D, S, D)
#define OSI_LOGPAR_FDSF __OSI_LOGPAR_X4(F, D, S, F)
#define OSI_LOGPAR_FDSS __OSI_LOGPAR_X4(F, D, S, S)
#define OSI_LOGPAR_FDSM __OSI_LOGPAR_X4(F, D, S, M)
#define OSI_LOGPAR_FDM __OSI_LOGPAR_X3(F, D, M)
#define OSI_LOGPAR_FDMI __OSI_LOGPAR_X4(F, D, M, I)
#define OSI_LOGPAR_FDMD __OSI_LOGPAR_X4(F, D, M, D)
#define OSI_LOGPAR_FDMF __OSI_LOGPAR_X4(F, D, M, F)
#define OSI_LOGPAR_FDMS __OSI_LOGPAR_X4(F, D, M, S)
#define OSI_LOGPAR_FDMM __OSI_LOGPAR_X4(F, D, M, M)
#define OSI_LOGPAR_FF __OSI_LOGPAR_X2(F, F)
#define OSI_LOGPAR_FFI __OSI_LOGPAR_X3(F, F, I)
#define OSI_LOGPAR_FFII __OSI_LOGPAR_X4(F, F, I, I)
#define OSI_LOGPAR_FFID __OSI_LOGPAR_X4(F, F, I, D)
#define OSI_LOGPAR_FFIF __OSI_LOGPAR_X4(F, F, I, F)
#define OSI_LOGPAR_FFIS __OSI_LOGPAR_X4(F, F, I, S)
#define OSI_LOGPAR_FFIM __OSI_LOGPAR_X4(F, F, I, M)
#define OSI_LOGPAR_FFD __OSI_LOGPAR_X3(F, F, D)
#define OSI_LOGPAR_FFDI __OSI_LOGPAR_X4(F, F, D, I)
#define OSI_LOGPAR_FFDD __OSI_LOGPAR_X4(F, F, D, D)
#define OSI_LOGPAR_FFDF __OSI_LOGPAR_X4(F, F, D, F)
#define OSI_LOGPAR_FFDS __OSI_LOGPAR_X4(F, F, D, S)
#define OSI_LOGPAR_FFDM __OSI_LOGPAR_X4(F, F, D, M)
#define OSI_LOGPAR_FFF __OSI_LOGPAR_X3(F, F, F)
#define OSI_LOGPAR_FFFI __OSI_LOGPAR_X4(F, F, F, I)
#define OSI_LOGPAR_FFFD __OSI_LOGPAR_X4(F, F, F, D)
#define OSI_LOGPAR_FFFF __OSI_LOGPAR_X4(F, F, F, F)
#define OSI_LOGPAR_FFFS __OSI_LOGPAR_X4(F, F, F, S)
#define OSI_LOGPAR_FFFM __OSI_LOGPAR_X4(F, F, F, M)
#define OSI_LOGPAR_FFS __OSI_LOGPAR_X3(F, F, S)
#define OSI_LOGPAR_FFSI __OSI_LOGPAR_X4(F, F, S, I)
#define OSI_LOGPAR_FFSD __OSI_LOGPAR_X4(F, F, S, D)
#define OSI_LOGPAR_FFSF __OSI_LOGPAR_X4(F, F, S, F)
#define OSI_LOGPAR_FFSS __OSI_LOGPAR_X4(F, F, S, S)
#define OSI_LOGPAR_FFSM __OSI_LOGPAR_X4(F, F, S, M)
#define OSI_LOGPAR_FFM __OSI_LOGPAR_X3(F, F, M)
#define OSI_LOGPAR_FFMI __OSI_LOGPAR_X4(F, F, M, I)
#define OSI_LOGPAR_FFMD __OSI_LOGPAR_X4(F, F, M, D)
#define OSI_LOGPAR_FFMF __OSI_LOGPAR_X4(F, F, M, F)
#define OSI_LOGPAR_FFMS __OSI_LOGPAR_X4(F, F, M, S)
#define OSI_LOGPAR_FFMM __OSI_LOGPAR_X4(F, F, M, M)
#define OSI_LOGPAR_FS __OSI_LOGPAR_X2(F, S)
#define OSI_LOGPAR_FSI __OSI_LOGPAR_X3(F, S, I)
#define OSI_LOGPAR_FSII __OSI_LOGPAR_X4(F, S, I, I)
#define OSI_LOGPAR_FSID __OSI_LOGPAR_X4(F, S, I, D)
#define OSI_LOGPAR_FSIF __OSI_LOGPAR_X4(F, S, I, F)
#define OSI_LOGPAR_FSIS __OSI_LOGPAR_X4(F, S, I, S)
#define OSI_LOGPAR_FSIM __OSI_LOGPAR_X4(F, S, I, M)
#define OSI_LOGPAR_FSD __OSI_LOGPAR_X3(F, S, D)
#define OSI_LOGPAR_FSDI __OSI_LOGPAR_X4(F, S, D, I)
#define OSI_LOGPAR_FSDD __OSI_LOGPAR_X4(F, S, D, D)
#define OSI_LOGPAR_FSDF __OSI_LOGPAR_X4(F, S, D, F)
#define OSI_LOGPAR_FSDS __OSI_LOGPAR_X4(F, S, D, S)
#define OSI_LOGPAR_FSDM __OSI_LOGPAR_X4(F, S, D, M)
#define OSI_LOGPAR_FSF __OSI_LOGPAR_X3(F, S, F)
#define OSI_LOGPAR_FSFI __OSI_LOGPAR_X4(F, S, F, I)
#define OSI_LOGPAR_FSFD __OSI_LOGPAR_X4(F, S, F, D)
#define OSI_LOGPAR_FSFF __OSI_LOGPAR_X4(F, S, F, F)
#define OSI_LOGPAR_FSFS __OSI_LOGPAR_X4(F, S, F, S)
#define OSI_LOGPAR_FSFM __OSI_LOGPAR_X4(F, S, F, M)
#define OSI_LOGPAR_FSS __OSI_LOGPAR_X3(F, S, S)
#define OSI_LOGPAR_FSSI __OSI_LOGPAR_X4(F, S, S, I)
#define OSI_LOGPAR_FSSD __OSI_LOGPAR_X4(F, S, S, D)
#define OSI_LOGPAR_FSSF __OSI_LOGPAR_X4(F, S, S, F)
#define OSI_LOGPAR_FSSS __OSI_LOGPAR_X4(F, S, S, S)
#define OSI_LOGPAR_FSSM __OSI_LOGPAR_X4(F, S, S, M)
#define OSI_LOGPAR_FSM __OSI_LOGPAR_X3(F, S, M)
#define OSI_LOGPAR_FSMI __OSI_LOGPAR_X4(F, S, M, I)
#define OSI_LOGPAR_FSMD __OSI_LOGPAR_X4(F, S, M, D)
#define OSI_LOGPAR_FSMF __OSI_LOGPAR_X4(F, S, M, F)
#define OSI_LOGPAR_FSMS __OSI_LOGPAR_X4(F, S, M, S)
#define OSI_LOGPAR_FSMM __OSI_LOGPAR_X4(F, S, M, M)
#define OSI_LOGPAR_FM __OSI_LOGPAR_X2(F, M)
#define OSI_LOGPAR_FMI __OSI_LOGPAR_X3(F, M, I)
#define OSI_LOGPAR_FMII __OSI_LOGPAR_X4(F, M, I, I)
#define OSI_LOGPAR_FMID __OSI_LOGPAR_X4(F, M, I, D)
#define OSI_LOGPAR_FMIF __OSI_LOGPAR_X4(F, M, I, F)
#define OSI_LOGPAR_FMIS __OSI_LOGPAR_X4(F, M, I, S)
#define OSI_LOGPAR_FMIM __OSI_LOGPAR_X4(F, M, I, M)
#define OSI_LOGPAR_FMD __OSI_LOGPAR_X3(F, M, D)
#define OSI_LOGPAR_FMDI __OSI_LOGPAR_X4(F, M, D, I)
#define OSI_LOGPAR_FMDD __OSI_LOGPAR_X4(F, M, D, D)
#define OSI_LOGPAR_FMDF __OSI_LOGPAR_X4(F, M, D, F)
#define OSI_LOGPAR_FMDS __OSI_LOGPAR_X4(F, M, D, S)
#define OSI_LOGPAR_FMDM __OSI_LOGPAR_X4(F, M, D, M)
#define OSI_LOGPAR_FMF __OSI_LOGPAR_X3(F, M, F)
#define OSI_LOGPAR_FMFI __OSI_LOGPAR_X4(F, M, F, I)
#define OSI_LOGPAR_FMFD __OSI_LOGPAR_X4(F, M, F, D)
#define OSI_LOGPAR_FMFF __OSI_LOGPAR_X4(F, M, F, F)
#define OSI_LOGPAR_FMFS __OSI_LOGPAR_X4(F, M, F, S)
#define OSI_LOGPAR_FMFM __OSI_LOGPAR_X4(F, M, F, M)
#define OSI_LOGPAR_FMS __OSI_LOGPAR_X3(F, M, S)
#define OSI_LOGPAR_FMSI __OSI_LOGPAR_X4(F, M, S, I)
#define OSI_LOGPAR_FMSD __OSI_LOGPAR_X4(F, M, S, D)
#define OSI_LOGPAR_FMSF __OSI_LOGPAR_X4(F, M, S, F)
#define OSI_LOGPAR_FMSS __OSI_LOGPAR_X4(F, M, S, S)
#define OSI_LOGPAR_FMSM __OSI_LOGPAR_X4(F, M, S, M)
#define OSI_LOGPAR_FMM __OSI_LOGPAR_X3(F, M, M)
#define OSI_LOGPAR_FMMI __OSI_LOGPAR_X4(F, M, M, I)
#define OSI_LOGPAR_FMMD __OSI_LOGPAR_X4(F, M, M, D)
#define OSI_LOGPAR_FMMF __OSI_LOGPAR_X4(F, M, M, F)
#define OSI_LOGPAR_FMMS __OSI_LOGPAR_X4(F, M, M, S)
#define OSI_LOGPAR_FMMM __OSI_LOGPAR_X4(F, M, M, M)
#define OSI_LOGPAR_S __OSI_LOGPAR_X1(S)
#define OSI_LOGPAR_SI __OSI_LOGPAR_X2(S, I)
#define OSI_LOGPAR_SII __OSI_LOGPAR_X3(S, I, I)
#define OSI_LOGPAR_SIII __OSI_LOGPAR_X4(S, I, I, I)
#define OSI_LOGPAR_SIID __OSI_LOGPAR_X4(S, I, I, D)
#define OSI_LOGPAR_SIIF __OSI_LOGPAR_X4(S, I, I, F)
#define OSI_LOGPAR_SIIS __OSI_LOGPAR_X4(S, I, I, S)
#define OSI_LOGPAR_SIIM __OSI_LOGPAR_X4(S, I, I, M)
#define OSI_LOGPAR_SID __OSI_LOGPAR_X3(S, I, D)
#define OSI_LOGPAR_SIDI __OSI_LOGPAR_X4(S, I, D, I)
#define OSI_LOGPAR_SIDD __OSI_LOGPAR_X4(S, I, D, D)
#define OSI_LOGPAR_SIDF __OSI_LOGPAR_X4(S, I, D, F)
#define OSI_LOGPAR_SIDS __OSI_LOGPAR_X4(S, I, D, S)
#define OSI_LOGPAR_SIDM __OSI_LOGPAR_X4(S, I, D, M)
#define OSI_LOGPAR_SIF __OSI_LOGPAR_X3(S, I, F)
#define OSI_LOGPAR_SIFI __OSI_LOGPAR_X4(S, I, F, I)
#define OSI_LOGPAR_SIFD __OSI_LOGPAR_X4(S, I, F, D)
#define OSI_LOGPAR_SIFF __OSI_LOGPAR_X4(S, I, F, F)
#define OSI_LOGPAR_SIFS __OSI_LOGPAR_X4(S, I, F, S)
#define OSI_LOGPAR_SIFM __OSI_LOGPAR_X4(S, I, F, M)
#define OSI_LOGPAR_SIS __OSI_LOGPAR_X3(S, I, S)
#define OSI_LOGPAR_SISI __OSI_LOGPAR_X4(S, I, S, I)
#define OSI_LOGPAR_SISD __OSI_LOGPAR_X4(S, I, S, D)
#define OSI_LOGPAR_SISF __OSI_LOGPAR_X4(S, I, S, F)
#define OSI_LOGPAR_SISS __OSI_LOGPAR_X4(S, I, S, S)
#define OSI_LOGPAR_SISM __OSI_LOGPAR_X4(S, I, S, M)
#define OSI_LOGPAR_SIM __OSI_LOGPAR_X3(S, I, M)
#define OSI_LOGPAR_SIMI __OSI_LOGPAR_X4(S, I, M, I)
#define OSI_LOGPAR_SIMD __OSI_LOGPAR_X4(S, I, M, D)
#define OSI_LOGPAR_SIMF __OSI_LOGPAR_X4(S, I, M, F)
#define OSI_LOGPAR_SIMS __OSI_LOGPAR_X4(S, I, M, S)
#define OSI_LOGPAR_SIMM __OSI_LOGPAR_X4(S, I, M, M)
#define OSI_LOGPAR_SD __OSI_LOGPAR_X2(S, D)
#define OSI_LOGPAR_SDI __OSI_LOGPAR_X3(S, D, I)
#define OSI_LOGPAR_SDII __OSI_LOGPAR_X4(S, D, I, I)
#define OSI_LOGPAR_SDID __OSI_LOGPAR_X4(S, D, I, D)
#define OSI_LOGPAR_SDIF __OSI_LOGPAR_X4(S, D, I, F)
#define OSI_LOGPAR_SDIS __OSI_LOGPAR_X4(S, D, I, S)
#define OSI_LOGPAR_SDIM __OSI_LOGPAR_X4(S, D, I, M)
#define OSI_LOGPAR_SDD __OSI_LOGPAR_X3(S, D, D)
#define OSI_LOGPAR_SDDI __OSI_LOGPAR_X4(S, D, D, I)
#define OSI_LOGPAR_SDDD __OSI_LOGPAR_X4(S, D, D, D)
#define OSI_LOGPAR_SDDF __OSI_LOGPAR_X4(S, D, D, F)
#define OSI_LOGPAR_SDDS __OSI_LOGPAR_X4(S, D, D, S)
#define OSI_LOGPAR_SDDM __OSI_LOGPAR_X4(S, D, D, M)
#define OSI_LOGPAR_SDF __OSI_LOGPAR_X3(S, D, F)
#define OSI_LOGPAR_SDFI __OSI_LOGPAR_X4(S, D, F, I)
#define OSI_LOGPAR_SDFD __OSI_LOGPAR_X4(S, D, F, D)
#define OSI_LOGPAR_SDFF __OSI_LOGPAR_X4(S, D, F, F)
#define OSI_LOGPAR_SDFS __OSI_LOGPAR_X4(S, D, F, S)
#define OSI_LOGPAR_SDFM __OSI_LOGPAR_X4(S, D, F, M)
#define OSI_LOGPAR_SDS __OSI_LOGPAR_X3(S, D, S)
#define OSI_LOGPAR_SDSI __OSI_LOGPAR_X4(S, D, S, I)
#define OSI_LOGPAR_SDSD __OSI_LOGPAR_X4(S, D, S, D)
#define OSI_LOGPAR_SDSF __OSI_LOGPAR_X4(S, D, S, F)
#define OSI_LOGPAR_SDSS __OSI_LOGPAR_X4(S, D, S, S)
#define OSI_LOGPAR_SDSM __OSI_LOGPAR_X4(S, D, S, M)
#define OSI_LOGPAR_SDM __OSI_LOGPAR_X3(S, D, M)
#define OSI_LOGPAR_SDMI __OSI_LOGPAR_X4(S, D, M, I)
#define OSI_LOGPAR_SDMD __OSI_LOGPAR_X4(S, D, M, D)
#define OSI_LOGPAR_SDMF __OSI_LOGPAR_X4(S, D, M, F)
#define OSI_LOGPAR_SDMS __OSI_LOGPAR_X4(S, D, M, S)
#define OSI_LOGPAR_SDMM __OSI_LOGPAR_X4(S, D, M, M)
#define OSI_LOGPAR_SF __OSI_LOGPAR_X2(S, F)
#define OSI_LOGPAR_SFI __OSI_LOGPAR_X3(S, F, I)
#define OSI_LOGPAR_SFII __OSI_LOGPAR_X4(S, F, I, I)
#define OSI_LOGPAR_SFID __OSI_LOGPAR_X4(S, F, I, D)
#define OSI_LOGPAR_SFIF __OSI_LOGPAR_X4(S, F, I, F)
#define OSI_LOGPAR_SFIS __OSI_LOGPAR_X4(S, F, I, S)
#define OSI_LOGPAR_SFIM __OSI_LOGPAR_X4(S, F, I, M)
#define OSI_LOGPAR_SFD __OSI_LOGPAR_X3(S, F, D)
#define OSI_LOGPAR_SFDI __OSI_LOGPAR_X4(S, F, D, I)
#define OSI_LOGPAR_SFDD __OSI_LOGPAR_X4(S, F, D, D)
#define OSI_LOGPAR_SFDF __OSI_LOGPAR_X4(S, F, D, F)
#define OSI_LOGPAR_SFDS __OSI_LOGPAR_X4(S, F, D, S)
#define OSI_LOGPAR_SFDM __OSI_LOGPAR_X4(S, F, D, M)
#define OSI_LOGPAR_SFF __OSI_LOGPAR_X3(S, F, F)
#define OSI_LOGPAR_SFFI __OSI_LOGPAR_X4(S, F, F, I)
#define OSI_LOGPAR_SFFD __OSI_LOGPAR_X4(S, F, F, D)
#define OSI_LOGPAR_SFFF __OSI_LOGPAR_X4(S, F, F, F)
#define OSI_LOGPAR_SFFS __OSI_LOGPAR_X4(S, F, F, S)
#define OSI_LOGPAR_SFFM __OSI_LOGPAR_X4(S, F, F, M)
#define OSI_LOGPAR_SFS __OSI_LOGPAR_X3(S, F, S)
#define OSI_LOGPAR_SFSI __OSI_LOGPAR_X4(S, F, S, I)
#define OSI_LOGPAR_SFSD __OSI_LOGPAR_X4(S, F, S, D)
#define OSI_LOGPAR_SFSF __OSI_LOGPAR_X4(S, F, S, F)
#define OSI_LOGPAR_SFSS __OSI_LOGPAR_X4(S, F, S, S)
#define OSI_LOGPAR_SFSM __OSI_LOGPAR_X4(S, F, S, M)
#define OSI_LOGPAR_SFM __OSI_LOGPAR_X3(S, F, M)
#define OSI_LOGPAR_SFMI __OSI_LOGPAR_X4(S, F, M, I)
#define OSI_LOGPAR_SFMD __OSI_LOGPAR_X4(S, F, M, D)
#define OSI_LOGPAR_SFMF __OSI_LOGPAR_X4(S, F, M, F)
#define OSI_LOGPAR_SFMS __OSI_LOGPAR_X4(S, F, M, S)
#define OSI_LOGPAR_SFMM __OSI_LOGPAR_X4(S, F, M, M)
#define OSI_LOGPAR_SS __OSI_LOGPAR_X2(S, S)
#define OSI_LOGPAR_SSI __OSI_LOGPAR_X3(S, S, I)
#define OSI_LOGPAR_SSII __OSI_LOGPAR_X4(S, S, I, I)
#define OSI_LOGPAR_SSID __OSI_LOGPAR_X4(S, S, I, D)
#define OSI_LOGPAR_SSIF __OSI_LOGPAR_X4(S, S, I, F)
#define OSI_LOGPAR_SSIS __OSI_LOGPAR_X4(S, S, I, S)
#define OSI_LOGPAR_SSIM __OSI_LOGPAR_X4(S, S, I, M)
#define OSI_LOGPAR_SSD __OSI_LOGPAR_X3(S, S, D)
#define OSI_LOGPAR_SSDI __OSI_LOGPAR_X4(S, S, D, I)
#define OSI_LOGPAR_SSDD __OSI_LOGPAR_X4(S, S, D, D)
#define OSI_LOGPAR_SSDF __OSI_LOGPAR_X4(S, S, D, F)
#define OSI_LOGPAR_SSDS __OSI_LOGPAR_X4(S, S, D, S)
#define OSI_LOGPAR_SSDM __OSI_LOGPAR_X4(S, S, D, M)
#define OSI_LOGPAR_SSF __OSI_LOGPAR_X3(S, S, F)
#define OSI_LOGPAR_SSFI __OSI_LOGPAR_X4(S, S, F, I)
#define OSI_LOGPAR_SSFD __OSI_LOGPAR_X4(S, S, F, D)
#define OSI_LOGPAR_SSFF __OSI_LOGPAR_X4(S, S, F, F)
#define OSI_LOGPAR_SSFS __OSI_LOGPAR_X4(S, S, F, S)
#define OSI_LOGPAR_SSFM __OSI_LOGPAR_X4(S, S, F, M)
#define OSI_LOGPAR_SSS __OSI_LOGPAR_X3(S, S, S)
#define OSI_LOGPAR_SSSI __OSI_LOGPAR_X4(S, S, S, I)
#define OSI_LOGPAR_SSSD __OSI_LOGPAR_X4(S, S, S, D)
#define OSI_LOGPAR_SSSF __OSI_LOGPAR_X4(S, S, S, F)
#define OSI_LOGPAR_SSSS __OSI_LOGPAR_X4(S, S, S, S)
#define OSI_LOGPAR_SSSM __OSI_LOGPAR_X4(S, S, S, M)
#define OSI_LOGPAR_SSM __OSI_LOGPAR_X3(S, S, M)
#define OSI_LOGPAR_SSMI __OSI_LOGPAR_X4(S, S, M, I)
#define OSI_LOGPAR_SSMD __OSI_LOGPAR_X4(S, S, M, D)
#define OSI_LOGPAR_SSMF __OSI_LOGPAR_X4(S, S, M, F)
#define OSI_LOGPAR_SSMS __OSI_LOGPAR_X4(S, S, M, S)
#define OSI_LOGPAR_SSMM __OSI_LOGPAR_X4(S, S, M, M)
#define OSI_LOGPAR_SM __OSI_LOGPAR_X2(S, M)
#define OSI_LOGPAR_SMI __OSI_LOGPAR_X3(S, M, I)
#define OSI_LOGPAR_SMII __OSI_LOGPAR_X4(S, M, I, I)
#define OSI_LOGPAR_SMID __OSI_LOGPAR_X4(S, M, I, D)
#define OSI_LOGPAR_SMIF __OSI_LOGPAR_X4(S, M, I, F)
#define OSI_LOGPAR_SMIS __OSI_LOGPAR_X4(S, M, I, S)
#define OSI_LOGPAR_SMIM __OSI_LOGPAR_X4(S, M, I, M)
#define OSI_LOGPAR_SMD __OSI_LOGPAR_X3(S, M, D)
#define OSI_LOGPAR_SMDI __OSI_LOGPAR_X4(S, M, D, I)
#define OSI_LOGPAR_SMDD __OSI_LOGPAR_X4(S, M, D, D)
#define OSI_LOGPAR_SMDF __OSI_LOGPAR_X4(S, M, D, F)
#define OSI_LOGPAR_SMDS __OSI_LOGPAR_X4(S, M, D, S)
#define OSI_LOGPAR_SMDM __OSI_LOGPAR_X4(S, M, D, M)
#define OSI_LOGPAR_SMF __OSI_LOGPAR_X3(S, M, F)
#define OSI_LOGPAR_SMFI __OSI_LOGPAR_X4(S, M, F, I)
#define OSI_LOGPAR_SMFD __OSI_LOGPAR_X4(S, M, F, D)
#define OSI_LOGPAR_SMFF __OSI_LOGPAR_X4(S, M, F, F)
#define OSI_LOGPAR_SMFS __OSI_LOGPAR_X4(S, M, F, S)
#define OSI_LOGPAR_SMFM __OSI_LOGPAR_X4(S, M, F, M)
#define OSI_LOGPAR_SMS __OSI_LOGPAR_X3(S, M, S)
#define OSI_LOGPAR_SMSI __OSI_LOGPAR_X4(S, M, S, I)
#define OSI_LOGPAR_SMSD __OSI_LOGPAR_X4(S, M, S, D)
#define OSI_LOGPAR_SMSF __OSI_LOGPAR_X4(S, M, S, F)
#define OSI_LOGPAR_SMSS __OSI_LOGPAR_X4(S, M, S, S)
#define OSI_LOGPAR_SMSM __OSI_LOGPAR_X4(S, M, S, M)
#define OSI_LOGPAR_SMM __OSI_LOGPAR_X3(S, M, M)
#define OSI_LOGPAR_SMMI __OSI_LOGPAR_X4(S, M, M, I)
#define OSI_LOGPAR_SMMD __OSI_LOGPAR_X4(S, M, M, D)
#define OSI_LOGPAR_SMMF __OSI_LOGPAR_X4(S, M, M, F)
#define OSI_LOGPAR_SMMS __OSI_LOGPAR_X4(S, M, M, S)
#define OSI_LOGPAR_SMMM __OSI_LOGPAR_X4(S, M, M, M)
#define OSI_LOGPAR_M __OSI_LOGPAR_X1(M)
#define OSI_LOGPAR_MI __OSI_LOGPAR_X2(M, I)
#define OSI_LOGPAR_MII __OSI_LOGPAR_X3(M, I, I)
#define OSI_LOGPAR_MIII __OSI_LOGPAR_X4(M, I, I, I)
#define OSI_LOGPAR_MIID __OSI_LOGPAR_X4(M, I, I, D)
#define OSI_LOGPAR_MIIF __OSI_LOGPAR_X4(M, I, I, F)
#define OSI_LOGPAR_MIIS __OSI_LOGPAR_X4(M, I, I, S)
#define OSI_LOGPAR_MIIM __OSI_LOGPAR_X4(M, I, I, M)
#define OSI_LOGPAR_MID __OSI_LOGPAR_X3(M, I, D)
#define OSI_LOGPAR_MIDI __OSI_LOGPAR_X4(M, I, D, I)
#define OSI_LOGPAR_MIDD __OSI_LOGPAR_X4(M, I, D, D)
#define OSI_LOGPAR_MIDF __OSI_LOGPAR_X4(M, I, D, F)
#define OSI_LOGPAR_MIDS __OSI_LOGPAR_X4(M, I, D, S)
#define OSI_LOGPAR_MIDM __OSI_LOGPAR_X4(M, I, D, M)
#define OSI_LOGPAR_MIF __OSI_LOGPAR_X3(M, I, F)
#define OSI_LOGPAR_MIFI __OSI_LOGPAR_X4(M, I, F, I)
#define OSI_LOGPAR_MIFD __OSI_LOGPAR_X4(M, I, F, D)
#define OSI_LOGPAR_MIFF __OSI_LOGPAR_X4(M, I, F, F)
#define OSI_LOGPAR_MIFS __OSI_LOGPAR_X4(M, I, F, S)
#define OSI_LOGPAR_MIFM __OSI_LOGPAR_X4(M, I, F, M)
#define OSI_LOGPAR_MIS __OSI_LOGPAR_X3(M, I, S)
#define OSI_LOGPAR_MISI __OSI_LOGPAR_X4(M, I, S, I)
#define OSI_LOGPAR_MISD __OSI_LOGPAR_X4(M, I, S, D)
#define OSI_LOGPAR_MISF __OSI_LOGPAR_X4(M, I, S, F)
#define OSI_LOGPAR_MISS __OSI_LOGPAR_X4(M, I, S, S)
#define OSI_LOGPAR_MISM __OSI_LOGPAR_X4(M, I, S, M)
#define OSI_LOGPAR_MIM __OSI_LOGPAR_X3(M, I, M)
#define OSI_LOGPAR_MIMI __OSI_LOGPAR_X4(M, I, M, I)
#define OSI_LOGPAR_MIMD __OSI_LOGPAR_X4(M, I, M, D)
#define OSI_LOGPAR_MIMF __OSI_LOGPAR_X4(M, I, M, F)
#define OSI_LOGPAR_MIMS __OSI_LOGPAR_X4(M, I, M, S)
#define OSI_LOGPAR_MIMM __OSI_LOGPAR_X4(M, I, M, M)
#define OSI_LOGPAR_MD __OSI_LOGPAR_X2(M, D)
#define OSI_LOGPAR_MDI __OSI_LOGPAR_X3(M, D, I)
#define OSI_LOGPAR_MDII __OSI_LOGPAR_X4(M, D, I, I)
#define OSI_LOGPAR_MDID __OSI_LOGPAR_X4(M, D, I, D)
#define OSI_LOGPAR_MDIF __OSI_LOGPAR_X4(M, D, I, F)
#define OSI_LOGPAR_MDIS __OSI_LOGPAR_X4(M, D, I, S)
#define OSI_LOGPAR_MDIM __OSI_LOGPAR_X4(M, D, I, M)
#define OSI_LOGPAR_MDD __OSI_LOGPAR_X3(M, D, D)
#define OSI_LOGPAR_MDDI __OSI_LOGPAR_X4(M, D, D, I)
#define OSI_LOGPAR_MDDD __OSI_LOGPAR_X4(M, D, D, D)
#define OSI_LOGPAR_MDDF __OSI_LOGPAR_X4(M, D, D, F)
#define OSI_LOGPAR_MDDS __OSI_LOGPAR_X4(M, D, D, S)
#define OSI_LOGPAR_MDDM __OSI_LOGPAR_X4(M, D, D, M)
#define OSI_LOGPAR_MDF __OSI_LOGPAR_X3(M, D, F)
#define OSI_LOGPAR_MDFI __OSI_LOGPAR_X4(M, D, F, I)
#define OSI_LOGPAR_MDFD __OSI_LOGPAR_X4(M, D, F, D)
#define OSI_LOGPAR_MDFF __OSI_LOGPAR_X4(M, D, F, F)
#define OSI_LOGPAR_MDFS __OSI_LOGPAR_X4(M, D, F, S)
#define OSI_LOGPAR_MDFM __OSI_LOGPAR_X4(M, D, F, M)
#define OSI_LOGPAR_MDS __OSI_LOGPAR_X3(M, D, S)
#define OSI_LOGPAR_MDSI __OSI_LOGPAR_X4(M, D, S, I)
#define OSI_LOGPAR_MDSD __OSI_LOGPAR_X4(M, D, S, D)
#define OSI_LOGPAR_MDSF __OSI_LOGPAR_X4(M, D, S, F)
#define OSI_LOGPAR_MDSS __OSI_LOGPAR_X4(M, D, S, S)
#define OSI_LOGPAR_MDSM __OSI_LOGPAR_X4(M, D, S, M)
#define OSI_LOGPAR_MDM __OSI_LOGPAR_X3(M, D, M)
#define OSI_LOGPAR_MDMI __OSI_LOGPAR_X4(M, D, M, I)
#define OSI_LOGPAR_MDMD __OSI_LOGPAR_X4(M, D, M, D)
#define OSI_LOGPAR_MDMF __OSI_LOGPAR_X4(M, D, M, F)
#define OSI_LOGPAR_MDMS __OSI_LOGPAR_X4(M, D, M, S)
#define OSI_LOGPAR_MDMM __OSI_LOGPAR_X4(M, D, M, M)
#define OSI_LOGPAR_MF __OSI_LOGPAR_X2(M, F)
#define OSI_LOGPAR_MFI __OSI_LOGPAR_X3(M, F, I)
#define OSI_LOGPAR_MFII __OSI_LOGPAR_X4(M, F, I, I)
#define OSI_LOGPAR_MFID __OSI_LOGPAR_X4(M, F, I, D)
#define OSI_LOGPAR_MFIF __OSI_LOGPAR_X4(M, F, I, F)
#define OSI_LOGPAR_MFIS __OSI_LOGPAR_X4(M, F, I, S)
#define OSI_LOGPAR_MFIM __OSI_LOGPAR_X4(M, F, I, M)
#define OSI_LOGPAR_MFD __OSI_LOGPAR_X3(M, F, D)
#define OSI_LOGPAR_MFDI __OSI_LOGPAR_X4(M, F, D, I)
#define OSI_LOGPAR_MFDD __OSI_LOGPAR_X4(M, F, D, D)
#define OSI_LOGPAR_MFDF __OSI_LOGPAR_X4(M, F, D, F)
#define OSI_LOGPAR_MFDS __OSI_LOGPAR_X4(M, F, D, S)
#define OSI_LOGPAR_MFDM __OSI_LOGPAR_X4(M, F, D, M)
#define OSI_LOGPAR_MFF __OSI_LOGPAR_X3(M, F, F)
#define OSI_LOGPAR_MFFI __OSI_LOGPAR_X4(M, F, F, I)
#define OSI_LOGPAR_MFFD __OSI_LOGPAR_X4(M, F, F, D)
#define OSI_LOGPAR_MFFF __OSI_LOGPAR_X4(M, F, F, F)
#define OSI_LOGPAR_MFFS __OSI_LOGPAR_X4(M, F, F, S)
#define OSI_LOGPAR_MFFM __OSI_LOGPAR_X4(M, F, F, M)
#define OSI_LOGPAR_MFS __OSI_LOGPAR_X3(M, F, S)
#define OSI_LOGPAR_MFSI __OSI_LOGPAR_X4(M, F, S, I)
#define OSI_LOGPAR_MFSD __OSI_LOGPAR_X4(M, F, S, D)
#define OSI_LOGPAR_MFSF __OSI_LOGPAR_X4(M, F, S, F)
#define OSI_LOGPAR_MFSS __OSI_LOGPAR_X4(M, F, S, S)
#define OSI_LOGPAR_MFSM __OSI_LOGPAR_X4(M, F, S, M)
#define OSI_LOGPAR_MFM __OSI_LOGPAR_X3(M, F, M)
#define OSI_LOGPAR_MFMI __OSI_LOGPAR_X4(M, F, M, I)
#define OSI_LOGPAR_MFMD __OSI_LOGPAR_X4(M, F, M, D)
#define OSI_LOGPAR_MFMF __OSI_LOGPAR_X4(M, F, M, F)
#define OSI_LOGPAR_MFMS __OSI_LOGPAR_X4(M, F, M, S)
#define OSI_LOGPAR_MFMM __OSI_LOGPAR_X4(M, F, M, M)
#define OSI_LOGPAR_MS __OSI_LOGPAR_X2(M, S)
#define OSI_LOGPAR_MSI __OSI_LOGPAR_X3(M, S, I)
#define OSI_LOGPAR_MSII __OSI_LOGPAR_X4(M, S, I, I)
#define OSI_LOGPAR_MSID __OSI_LOGPAR_X4(M, S, I, D)
#define OSI_LOGPAR_MSIF __OSI_LOGPAR_X4(M, S, I, F)
#define OSI_LOGPAR_MSIS __OSI_LOGPAR_X4(M, S, I, S)
#define OSI_LOGPAR_MSIM __OSI_LOGPAR_X4(M, S, I, M)
#define OSI_LOGPAR_MSD __OSI_LOGPAR_X3(M, S, D)
#define OSI_LOGPAR_MSDI __OSI_LOGPAR_X4(M, S, D, I)
#define OSI_LOGPAR_MSDD __OSI_LOGPAR_X4(M, S, D, D)
#define OSI_LOGPAR_MSDF __OSI_LOGPAR_X4(M, S, D, F)
#define OSI_LOGPAR_MSDS __OSI_LOGPAR_X4(M, S, D, S)
#define OSI_LOGPAR_MSDM __OSI_LOGPAR_X4(M, S, D, M)
#define OSI_LOGPAR_MSF __OSI_LOGPAR_X3(M, S, F)
#define OSI_LOGPAR_MSFI __OSI_LOGPAR_X4(M, S, F, I)
#define OSI_LOGPAR_MSFD __OSI_LOGPAR_X4(M, S, F, D)
#define OSI_LOGPAR_MSFF __OSI_LOGPAR_X4(M, S, F, F)
#define OSI_LOGPAR_MSFS __OSI_LOGPAR_X4(M, S, F, S)
#define OSI_LOGPAR_MSFM __OSI_LOGPAR_X4(M, S, F, M)
#define OSI_LOGPAR_MSS __OSI_LOGPAR_X3(M, S, S)
#define OSI_LOGPAR_MSSI __OSI_LOGPAR_X4(M, S, S, I)
#define OSI_LOGPAR_MSSD __OSI_LOGPAR_X4(M, S, S, D)
#define OSI_LOGPAR_MSSF __OSI_LOGPAR_X4(M, S, S, F)
#define OSI_LOGPAR_MSSS __OSI_LOGPAR_X4(M, S, S, S)
#define OSI_LOGPAR_MSSM __OSI_LOGPAR_X4(M, S, S, M)
#define OSI_LOGPAR_MSM __OSI_LOGPAR_X3(M, S, M)
#define OSI_LOGPAR_MSMI __OSI_LOGPAR_X4(M, S, M, I)
#define OSI_LOGPAR_MSMD __OSI_LOGPAR_X4(M, S, M, D)
#define OSI_LOGPAR_MSMF __OSI_LOGPAR_X4(M, S, M, F)
#define OSI_LOGPAR_MSMS __OSI_LOGPAR_X4(M, S, M, S)
#define OSI_LOGPAR_MSMM __OSI_LOGPAR_X4(M, S, M, M)
#define OSI_LOGPAR_MM __OSI_LOGPAR_X2(M, M)
#define OSI_LOGPAR_MMI __OSI_LOGPAR_X3(M, M, I)
#define OSI_LOGPAR_MMII __OSI_LOGPAR_X4(M, M, I, I)
#define OSI_LOGPAR_MMID __OSI_LOGPAR_X4(M, M, I, D)
#define OSI_LOGPAR_MMIF __OSI_LOGPAR_X4(M, M, I, F)
#define OSI_LOGPAR_MMIS __OSI_LOGPAR_X4(M, M, I, S)
#define OSI_LOGPAR_MMIM __OSI_LOGPAR_X4(M, M, I, M)
#define OSI_LOGPAR_MMD __OSI_LOGPAR_X3(M, M, D)
#define OSI_LOGPAR_MMDI __OSI_LOGPAR_X4(M, M, D, I)
#define OSI_LOGPAR_MMDD __OSI_LOGPAR_X4(M, M, D, D)
#define OSI_LOGPAR_MMDF __OSI_LOGPAR_X4(M, M, D, F)
#define OSI_LOGPAR_MMDS __OSI_LOGPAR_X4(M, M, D, S)
#define OSI_LOGPAR_MMDM __OSI_LOGPAR_X4(M, M, D, M)
#define OSI_LOGPAR_MMF __OSI_LOGPAR_X3(M, M, F)
#define OSI_LOGPAR_MMFI __OSI_LOGPAR_X4(M, M, F, I)
#define OSI_LOGPAR_MMFD __OSI_LOGPAR_X4(M, M, F, D)
#define OSI_LOGPAR_MMFF __OSI_LOGPAR_X4(M, M, F, F)
#define OSI_LOGPAR_MMFS __OSI_LOGPAR_X4(M, M, F, S)
#define OSI_LOGPAR_MMFM __OSI_LOGPAR_X4(M, M, F, M)
#define OSI_LOGPAR_MMS __OSI_LOGPAR_X3(M, M, S)
#define OSI_LOGPAR_MMSI __OSI_LOGPAR_X4(M, M, S, I)
#define OSI_LOGPAR_MMSD __OSI_LOGPAR_X4(M, M, S, D)
#define OSI_LOGPAR_MMSF __OSI_LOGPAR_X4(M, M, S, F)
#define OSI_LOGPAR_MMSS __OSI_LOGPAR_X4(M, M, S, S)
#define OSI_LOGPAR_MMSM __OSI_LOGPAR_X4(M, M, S, M)
#define OSI_LOGPAR_MMM __OSI_LOGPAR_X3(M, M, M)
#define OSI_LOGPAR_MMMI __OSI_LOGPAR_X4(M, M, M, I)
#define OSI_LOGPAR_MMMD __OSI_LOGPAR_X4(M, M, M, D)
#define OSI_LOGPAR_MMMF __OSI_LOGPAR_X4(M, M, M, F)
#define OSI_LOGPAR_MMMS __OSI_LOGPAR_X4(M, M, M, S)
#define OSI_LOGPAR_MMMM __OSI_LOGPAR_X4(M, M, M, M)
