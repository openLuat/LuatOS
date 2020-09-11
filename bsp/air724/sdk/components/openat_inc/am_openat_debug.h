#ifndef __AM_OPENAT_DEBUG_H__
#define __AM_OPENAT_DEBUG_H__
#include "am_openat.h"

#define UART_LOG_MAX_LENTH  256



typedef enum
{
  OPENAT_TRACE_U1,
  OPENAT_TRACE_U2,
  OPENAT_TRACE_U3,
  OPENAT_TRACE_USB,
  OPENAT_TRACE_QTY
}E_AMOPENAT_TRACE_PORT;


typedef struct
{
    BOOL opened;      // avoid double open
    UINT32 lost;      // lost count
    BOOL outputlostmsg;
}openatTraceCtx;






















#endif
