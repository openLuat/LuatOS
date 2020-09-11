////////////////////////////////////////////////////////////////////////////////
//        Copyright (C) 2002-2006, Coolsand Technologies, Inc.
//                       All Rights Reserved
//
// This source code is property of Coolsand. The information contained in this
// file is confidential. Distribution, reproduction, as well as exploitation,
// or transmisison of any content of this file is not allowed except if
// expressly permitted.Infringements result in damage claims!
//
// FILENAME: cs_types.h
//
// DESCRIPTION:
//   This file defines all basic data types used by all files in Coolsand
//   development environment.
//
// REVISION HISTORY:
//   NAME            DATE            REMAKS
//   SHK           2006-10-29     Created initial version 1.0
//   Romuald       2007-04-25     Added PRIVATE, PROTECTED, REG16 and REG32
//   zhaoyong      2008-08-08     clean up
////////////////////////////////////////////////////////////////////////////////

#ifndef __CS_TYPE_H__
#define __CS_TYPE_H__

#ifndef __TYPE_H__

#define ELUA_TYPE_H
//#include "global_types.h"

#if 0
#define MAX_INT8                    127
#define MIN_INT8                    (-MAX_INT8 - 1)
#define MAX_UINT8                   255
#define MIN_UINT8                   0
#define MAX_INT16                   32767
#define MIN_INT16                   (-MAX_INT16 - 1)
#define MAX_UINT16                  65535
#define MIN_UINT16                  0
#define MAX_INT32                   2147483647L
#define MIN_INT32                   (-MAX_INT32 - 1)
#define MAX_UINT32                  4294967295U
#define MIN_UINT32                  0U
#ifdef WITH_LONG_LONG
#define INTMAX_MAX                  0x7fffffffffffffff
#define INTMAX_MIN                  -(0x7fffffffffffffff-1)
#define UINTMAX_MAX                 0xffffffffffffffff
#else
#define INTMAX_MAX                  0x7fffffff
#define INTMAX_MIN                  -(0x7fffffff-1)
#define UINTMAX_MAX                 0xffffffff
#endif


#define INT_MAX                     (char *)(1<<31)
#define LONG_MAX                    0x7fffffff
#define LONG_MIN                    -(0x7fffffff-1)
#undef ULONG_MAX
#define ULONG_MAX                   0xffffffff
#endif

/*begin\add by wangzhiqiang\2001.6.27\移植工作*/
#ifndef USHRT_MAX
#define USHRT_MAX                   0xFFFFU
#endif

#ifndef UCHAR_MAX
#define UCHAR_MAX                   0xFFU
#endif
/*end\add by wangzhiqiang\2001.6.27\移植工作*/
#ifdef u8
#undef u8
#endif
typedef unsigned char               u8;
#ifdef u16
#undef u16
#endif
typedef unsigned short              u16;
#ifdef u32
#undef u32
#endif
typedef unsigned long               u32;
typedef signed char                 s8;
typedef short                       s16;
typedef long                        s32;
typedef unsigned long long          u64;

#endif

#ifdef __cplusplus
#else
#ifndef bool
typedef unsigned char               bool;
#endif
#endif

typedef char                        ascii;
typedef unsigned char               byte;           /*  unsigned 8-bit data     */
typedef unsigned short              word;           /*  unsigned 16-bit data    */
typedef unsigned long               dword;          /*  unsigned 32-bit data    */
typedef unsigned char               uint8;
typedef signed char                 int8;
typedef unsigned short int          uint16;
typedef signed short int            int16;
typedef unsigned int                uint32;
typedef signed int                  int32;
#ifndef __mvUsbDefs_h__
#ifndef JPEGLIB_H
typedef char                        boolean;
#endif
#endif
#ifndef _SIZE_T_DEFINED_
#define	_SIZE_T_DEFINED_
typedef	unsigned int    size_t;
#endif
#ifndef _UTL_TYPES_INCLUDED
typedef int                         ssize_t;
#endif
typedef long long                   INT64;

#ifndef _AT_GBL_TYPES_H_
typedef unsigned long               UINT32;
typedef unsigned short              UINT16;
typedef long                        INT32;
typedef short                       INT16;
typedef unsigned char               UINT8;
typedef unsigned int                UINT;
#undef INT8
#define INT8  char
//typedef char                        INT8;
#if defined(_M_IX86)
#pragma warning(disable:4142)
typedef __int64                     UINT64;
typedef __int64                     INT64;
#else
typedef unsigned long long          UINT64;
#endif
typedef unsigned char               BOOL;



typedef char                        CHAR;
typedef unsigned char               BYTE;
typedef float                       FLOAT;
typedef double                      DOUBLE;
typedef void*                       HANDLE;
typedef UINT8*                      PUINT8;
typedef UINT32*                     PUINT32;
typedef INT32*                      PINT32;
typedef UINT16*                     PUINT16;
typedef INT16*                      PINT16;
typedef unsigned short              WORD;

#ifndef __TYPE_H__
typedef unsigned long               DWORD;  /* actually long, but this should be okay */
#endif

/*+\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/
#ifndef _HWREG_ACCESS_H_
typedef volatile unsigned char      REG8;
typedef volatile unsigned short     REG16;
typedef volatile unsigned int       REG32;
#endif
/*-\NEW\zhuwangbin\2020.4.26\添加openat cam接口*/

typedef int                         INT;
typedef char                        S8;
typedef char *                      PS8;
typedef unsigned char   *           PU8;
typedef unsigned short              pBOOL; 
typedef short int                   S16; 
typedef short int *                 PS16; 
typedef unsigned short int          U16; 
typedef unsigned short int *        PU16;
//typedef int                         S32;
typedef int *                       PS32;
//typedef unsigned int                U32;
typedef unsigned int *              PU32;
typedef float                       float32;

/*+\Merge\lifei\2011.12.16\Merge BV4-2*/
#ifndef WIN32
typedef unsigned long long          U64;
typedef long long                   S64;
#endif
#endif


#ifndef __INT16_T__
typedef short       int16_t;
#define __INT16_T__
#endif

typedef CHAR *                      PCHAR;
typedef void*                       PVOID;
typedef unsigned char               U8;
typedef unsigned short              WCHAR;


#ifndef wchar
#define wchar 						unsigned short
#endif

#ifndef sshort
#define sshort						signed short
#endif

typedef  unsigned short ushort;	


#ifndef sbyte
#define sbyte						signed char
#endif

#ifndef ubyte
#define ubyte 						unsigned char
#endif

typedef unsigned long ulong	;


#ifndef SINT8
#define SINT8 						signed char
#endif

#ifndef BOOLEAN
#define BOOLEAN						BOOL
#endif


#define PUBLIC
#define SRVAPI
#define PROTECTED
#define LOCAL                       static

#if !defined(PRIVATE)
#define PRIVATE                     static
#endif

#define EXPORT                      extern
#define REG                         register
#define CONST                       const
#define VOLATILE                    volatile
#define VOID                        void

#ifndef DEPRECATED
#ifdef ENABLE_DEPRECATED
#define DEPRECATED __attribute__ ((deprecated))
#else
#define DEPRECATED
#endif /* ENABLE_DEPRECATED */
#endif
#ifndef TRUE
#define TRUE                        (1==1)
#endif

#ifndef FALSE
#define FALSE                       (1==0)
#endif

#ifndef NULL
#define NULL                        0
#endif
/*-\Merge\lifei\2011.12.16\Merge BV4-2*/


typedef BOOL   kal_bool;
typedef UINT8  kal_uint8;
typedef UINT16 kal_uint16;
typedef UINT32 kal_uint32;
typedef INT32  kal_int32;
typedef char   kal_char;

typedef INT8   kal_int8;
typedef INT16  kal_int16;

#define KAL_TRUE TRUE   
#define KAL_FALSE FALSE  



#define CS_NULL                     (void*)0
#define NIL                         0
#define CS_NIL                      0
#define HNULL                       0
#ifndef TELUTL_H
#define NULL_CHAR                   '\0'
#endif
#define OFFSETOF(s,m)                   ((UINT32)&(((s *)0)->m)) // Get the address offset of the specified member.
#define ALIGN(val,exp)                  (((val) + ((exp)-1)) & ~((exp)-1))
#define ARRAY_SIZE(a)                   (sizeof(a)/sizeof(a[0]))
#define LAST_ELEMENT(x)                 (&x[ARRAY_SIZE(x)-1])
#define TCHAR_SIZEOF(sz)                (sizeof(sz)/sizeof(TCHAR))
#define BOUND(x, min, max)              ( (x) < (min) ? (min) : ((x) > (max) ? (max):(x)) )
#define ROUND_SIZEOF(t)                 ((sizeof(t)+sizeof(int)-1)&~(sizeof(int)-1))
#define IS_32BIT_ALIGN(nAdd)            ((UINT32)(((UINT32)(nAdd)) & 0x3)==0)
#define IS_16_ALIGN(nSize)              ((UINT32)(((UINT32)(nSize))& 0x0f) == 0)
#define S_LAST_MEMBER_ADDR(ptr, type)   ((UINT8*)(ptr) + SIZEOF(type))
#define S_MEMBER_ADDR(s_prt, offset)    ((UINT8*)(s_prt) + offset)
#define MSB(x)                          (((x) >> 8) & 0xff) // most signif byte of 2-byte integer
#define LSB(x)                          ((x) & 0xff)        // least signif byte of 2-byte integer
#define MAKE_WORD(p)                    (((UINT16)(p)[0] << 8) | (UINT16)(p)[1])
#define MAKE_DWORD(p)                   (((UINT32)(p)[0] << 24) | ((UINT32)(p)[1] << 16) | ((UINT32)(p)[2] << 8) | (UINT32)(p)[3])
#define SWAP16(p)                       (((UINT16)((UINT16*)(p))[1] << 8) | (UINT16)((UINT16*)(p))[0])
#define SWAP32(p)                       (((UINT32)((UINT32*)(p))[3] << 24) | ((UINT32)((UINT32*)(p))[2] << 16) | ((UINT32)((UINT32*)(p))[1] << 8) | (UINT32)((UINT32*)(p))[0])
#define SWAPT(v1,v2,typ)                {typ v; v  = v1; v1 = v2; v2 = v;}

/* align size withe the specified bits.*/
#define ALIGN_SIZE(x, align)            (((UINT32)(x)+align-1)&~(align-1))
#define Arg(arg, type)                  (*(type *)(arg))
#define NextArg(arg, type)              ((arg) = (TCHAR *)(arg) + roundedsizeof(type))
// Get the data from "arg" to "in".
#define ARG_IN(r,arg,type)              (memcpy(&(r), (type *) (arg), sizeof (arg)))
// Put the data from "w" to "arg".
#define ARG_OUT(arg, w, type)           (memcpy((type *) (arg), &(w), sizeof (w)))
#define MAKEINT16(a, b)                 ((INT16)(((UINT8)(a)) | ((INT16)((UINT8)(b))) << 8))
#define MAKEINT32(a, b)                 ((INT32)(((UINT16)(a)) | ((INT32)((UINT16)(b))) << 16))
#define MAKEUINT16(a, b)                ((UINT16)(((UINT8)(a)) | ((UINT16)((UINT8)(b))) << 8))
#define MAKEUINT32(a, b)                ((UINT32)(((UINT16)(a)) | ((UINT32)((UINT16)(b))) << 16))
#define LOINT8(w)                       ((INT8)(w))
#define HIINT8(w)                       ((INT8)((UINT16)(w) >> 8))
#define LOUINT8(w)                      ((UINT8)(w))
#define HIUINT8(w)                      ((UINT8)((UINT16)(w) >> 8))
#define LOINT16(l)                      ((INT16)(l))
#define HIINT16(l)                      ((INT16)((UINT32)(l) >> 16))
#define LOUINT16(l)                     ((UINT16)(l))
#define HIUINT16(l)                     ((UINT16)((UINT32)(l) >> 16))
#ifndef offsetof
#define offsetof(TYPE, MEMBER)          ((u32) &((TYPE *)0)->MEMBER)
#endif
#define offsetofvar(VAR, MEMBER)        (((u32) &(VAR.MEMBER)) - ((u32) &VAR))
/* Remove const cast-away warnings from gcc -Wcast-qual */
#define __UNCONST(a)                    ((void *)(unsigned long)(const void *)(a))
//#define __P(protos)  protos
#define ALIGN(val,exp)                  (((val) + ((exp)-1)) & ~((exp)-1))
#define ARRAY_SIZE(a)                   (sizeof(a)/sizeof(a[0]))
#define LAST_ELEMENT(x)                 (&x[ARRAY_SIZE(x)-1])
#define TCHAR_SIZEOF(sz)                (sizeof(sz)/sizeof(TCHAR))
#define BOUND(x, min, max)              ( (x) < (min) ? (min) : ((x) > (max) ? (max):(x)) )
#define roundedsizeof(t)                ((sizeof(t)+sizeof(int)-1)&~(sizeof(int)-1))
#define IS_32BIT_ALIGN(nAdd)            ((UINT32)(((UINT32)(nAdd)) & 0x3)==0)
#define IS_16_ALIGN(nSize)              ((UINT32)(((UINT32)(nSize))& 0x0f) == 0)

// Set a breakpoint, to enter GDB.
#define BREAKPOINT                      asm volatile("break 1\n\tnop\n\tnop\n\tnop")
#define BKPT                            BREAKPOINT;
#define GDB_FUNC_IN_RAM                 __attribute__((section(".ram")))

// Preprocessor macros.
#define STRINGIFY_VALUE(s) STRINGIFY(s)
#define STRINGIFY(s) #s


#if defined(UNICODE)
#undef SIZEOF
#define SIZEOF(type) (sizeof(type)/sizeof(UINT16))
typedef UINT16* PSTR;
typedef CONST UINT16* PCSTR;
#error: it should not define  this type for TCHAR 
typedef UINT16 TCHAR;
#undef TEXT
#define TEXT(x) L ## x
#else
#undef SIZEOF
#define SIZEOF(type) sizeof(type)
typedef UINT8* PSTR;
typedef CONST UINT8* PCSTR;
#ifndef _AT_GBL_TYPES_H_
typedef UINT8 TCHAR;
#endif
typedef UINT8* PTCHAR;
#undef TEXT
#define TEXT(x) x
#endif

#define CPP_START  extern "C" {
#define CPP_END    }
#define TSTXT(x)  x

/// From http://www.ibm.com/developerworks/linux/library/l-gcc-hacks/
/// Macro to use in a if statement to tell the compiler this branch
/// is likely taken, and optimize accordingly.
#define LIKELY(x)   __builtin_expect(!!(x), 1)
/// Macro to use in a if statement to tell the compiler this branch
/// is unlikely take, and optimize accordingly.
#define UNLIKELY(x) __builtin_expect(!!(x), 0)


/// For packing structure
//#define PACKED      __attribute__((packed))

/// To describe alignment
#define ALIGNED(a)  __attribute__((aligned(a)))

#ifndef __MICRON_ALIGN__
#define MICRON_ALIGN(n) __attribute__ ((aligned (n)))
#endif

/// For possibly unused functions or variables (e.g., debugging stuff)
#define POSSIBLY_UNUSED  __attribute__((unused))


// C++ needs to know that types and declarations are C, not C++.
#ifdef __cplusplus
# define EXTERN_C_START extern "C" {
# define EXTERN_C_END }
#else
# define EXTERN_C_START
# define EXTERN_C_END
#endif


#endif // __CS_TYPE_H__

