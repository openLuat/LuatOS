#ifndef __IOT_TYPES_H__
#define __IOT_TYPES_H__

#define INVALID_HANDLE_VALUE			(0xffffffff)

#if !(defined(WIN32) || defined(_USERGEN))
#ifndef __INT8_T__
typedef char        int8_t;
#define __INT8_T__
#endif

#ifndef __INT16_T__
typedef short       int16_t;
#define __INT16_T__
#endif

#ifndef __INT32_T__
typedef int         int32_t;
#define __INT32_T__
#endif

#ifndef __U8_T__
typedef unsigned char u8_t;
#define __U8_T__
#endif

#ifndef __UINT8_T__
typedef unsigned char   uint8_t;
#define __UINT8_T__
#endif

#ifndef __UINT16_T__
typedef unsigned short  uint16_t;
#define __UINT16_T__
#endif

#ifndef __U16_T__
typedef unsigned short u16_t;
#define __U16_T__
#endif


#ifndef __UINT32_T__
typedef unsigned int    uint32_t;
#define __UINT32_T__
#endif

typedef unsigned long long  uint64_t;
typedef long long   int64_t;
#endif

#endif
