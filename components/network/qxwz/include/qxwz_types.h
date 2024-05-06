/**
 * Copyright (c) 2015-2022 QXSI. All rights reserved.
 *
 * @file qxwz_types.h
 * @brief header for type definition
 * @version 1.0.0
 * @author Kong Yingjun
 * @date   2022-03-16
 *
 * CHANGELOG:
 * DATE             AUTHOR          REASON
 * 2022-03-16       Kong Yingjun    Init version;
 */
#ifndef QXWZ_TYPES_H__
#define QXWZ_TYPES_H__

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h> /* NULL */

/*
 * basic types definition
 */
/* character */
#ifndef QXWZ_CHAR_T
#define QXWZ_CHAR_T
typedef char qxwz_char_t;
#endif

/* 8bits signed integer */
#ifndef QXWZ_INT8_T
#define QXWZ_INT8_T
typedef signed char qxwz_int8_t;
#endif

/* 8bits unsigned integer */
#ifndef QXWZ_UINT8_T
#define QXWZ_UINT8_T
typedef unsigned char qxwz_uint8_t;
#endif

/* 16bits signed integer */
#ifndef QXWZ_INT16_T
#define QXWZ_INT16_T
typedef signed short qxwz_int16_t;
#endif

/* 16bits unsigned integer */
#ifndef QXWZ_UINT16_T
#define QXWZ_UINT16_T
typedef unsigned short qxwz_uint16_t;
#endif

/* 32bits signed integer */
#ifndef QXWZ_INT32_t
#define QXWZ_INT32_t
typedef signed int qxwz_int32_t;
#endif

/* 32bits unsigned integer */
#ifndef QXWZ_UINT32_T
#define QXWZ_UINT32_T
typedef unsigned int qxwz_uint32_t;
#endif

#ifndef QXWZ_ULONG32_T
#define QXWZ_ULONG32_T
typedef unsigned long qxwz_ulong32_t;
#endif

/* 64bits signed integer */
#ifndef QXWZ_INT64_T
#define QXWZ_INT64_T
typedef signed long long qxwz_int64_t;
#endif

/* 64bits unsigned integer */
#ifndef QXWZ_UINT64_T
#define QXWZ_UINT64_T
typedef unsigned long long qxwz_uint64_t;
#endif

/* single precision float number */
#ifndef QXWZ_FLOAT32_T
#define QXWZ_FLOAT32_T
typedef float qxwz_float32_t;
#endif

/* double precision float number */
#ifndef QXWZ_FLOAT64_T
#define QXWZ_FLOAT64_T
typedef double qxwz_float64_t;
#endif

/* void */
#ifndef QXWZ_VOID_T
#define QXWZ_VOID_T
typedef void qxwz_void_t;
#endif

/* time_t */
#ifndef QXWZ_TIME_T
#define QXWZ_TIME_T
typedef qxwz_uint64_t qxwz_time_t;
#endif

/* NULL */
#ifndef QXWZ_NULL
#define QXWZ_NULL    ( void * ) 0
#endif

/* boolean representation */
#ifndef QXWZ_BOOT_T
#define QXWZ_BOOT_T
typedef enum {
    /* FALSE value */
    QXWZ_FALSE,
    /* TRUE value */
    QXWZ_TRUE
} qxwz_bool_t;
#endif

/* MISRA-C[pm098] */
// #ifndef NULL
// #define NULL    ((void*)0)
// #endif

/* unused var */
#ifndef UNUSED_VAR
#define UNUSED_VAR(x) ((void)(x))
#endif

#ifdef __cplusplus
}
#endif

#endif
