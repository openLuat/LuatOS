/**
 * \file alignment.h
 *
 * \brief Utility code for dealing with unaligned memory accesses
 *
 *  Backported from Mbed TLS 3.x (components/mbedtls3/library/alignment.h)
 *  into the LuatOS mbedtls 2.28.x tree, so that mbedtls_xor() (see
 *  common.h) can use efficient word-at-a-time XOR where the target
 *  supports unaligned accesses.
 */
/*
 *  Copyright The Mbed TLS Contributors
 *  SPDX-License-Identifier: Apache-2.0
 *
 *  Licensed under the Apache License, Version 2.0 (the "License"); you may
 *  not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
 *  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#ifndef MBEDTLS_LIBRARY_ALIGNMENT_H
#define MBEDTLS_LIBRARY_ALIGNMENT_H

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#if !defined(MBEDTLS_ALIGNMENT_DISABLE_EFFICENT_UNALIGNED_ACCESS)
/*
 * Define MBEDTLS_EFFICIENT_UNALIGNED_ACCESS for architectures where unaligned memory
 * accesses are known to be efficient (or at least supported).
 *
 * All functions defined here will behave correctly regardless, but might be less
 * efficient when this is not defined.
 */
/* Older GCC/clang toolchains (before GCC 7 / clang 9) do not define
 * __ARM_FEATURE_UNALIGNED even for ARMv7-M/ARMv7-R/ARMv8-M targets that
 * support unaligned accesses. Cover those with an explicit architecture
 * check. ARMv6-M (Cortex-M0/M0+) does NOT support unaligned accesses and
 * is deliberately excluded here. */
#if defined(__ARM_FEATURE_UNALIGNED) \
    || defined(__x86_64__) || defined(_M_X64) \
    || defined(__i386__) || defined(_M_IX86) \
    || defined(__aarch64__) || defined(_M_ARM64) \
    || defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__) \
    || defined(__ARM_ARCH_7R__) || defined(__ARM_ARCH_8M_MAIN__)
/*
 * __ARM_FEATURE_UNALIGNED is defined where appropriate by armcc, gcc 7, clang 9
 * (and later versions) for Arm v7 and later; all x86 platforms should have
 * efficient unaligned access.
 */
#define MBEDTLS_EFFICIENT_UNALIGNED_ACCESS
#endif
#endif /* MBEDTLS_ALIGNMENT_DISABLE_EFFICENT_UNALIGNED_ACCESS */

#if defined(__IAR_SYSTEMS_ICC__) && \
    (defined(__ARM_ARCH_7M__) || defined(__ARM_ARCH_7EM__) || \
     defined(__ARM_ARCH_7R__) || defined(__ARM_ARCH_8M_MAIN__) || \
     defined(__ARM_ARCH_7A__) || defined(__ARM_ARCH_8A__))
#pragma language=save
#pragma language=extended
#define MBEDTLS_POP_IAR_LANGUAGE_PRAGMA
/* IAR recommend this technique for accessing unaligned data in
 * https://mypages.iar.com/s/article/Accessing-Unaligned-Data
 * This results in a single load / store instruction (if unaligned access is supported).
 */
#define UINT_UNALIGNED

/* Some products, like Zephyr, defines __packed as a macro for attribute(packed) and
 * that does not work with typedefs, so if __packed is defined, undef it for the
 * typedefs and restore it afterwards.
 */
#ifdef __packed
#pragma push_macro("__packed")
#undef __packed
#define MBEDTLS_IAR_PACKED_MACRO_USED
#endif

typedef uint16_t __packed mbedtls_uint16_unaligned_t;
typedef uint32_t __packed mbedtls_uint32_unaligned_t;
typedef uint64_t __packed mbedtls_uint64_unaligned_t;

#ifdef MBEDTLS_IAR_PACKED_MACRO_USED
#undef MBEDTLS_IAR_PACKED_MACRO_USED
#pragma pop_macro("__packed")
#endif

#elif defined(__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 405)
/*
 * The packed attribute specifies that a variable or structure field should have
 * the smallest possible alignment (one byte for a variable).
 *
 * Previous implementations used __attribute__((__aligned__(1)), but had issues
 * with a gcc bug: https://gcc.gnu.org/bugzilla/show_bug.cgi?id=94662
 *
 * This guarantees a single load/store instruction for the access, provided the
 * target supports unaligned accesses (which is exactly when
 * MBEDTLS_EFFICIENT_UNALIGNED_ACCESS is defined).
 */
#define UINT_UNALIGNED_STRUCT
typedef struct {
    uint16_t x;
} __attribute__((packed, may_alias)) mbedtls_uint16_unaligned_t;
typedef struct {
    uint32_t x;
} __attribute__((packed, may_alias)) mbedtls_uint32_unaligned_t;
typedef struct {
    uint64_t x;
} __attribute__((packed, may_alias)) mbedtls_uint64_unaligned_t;
#endif

/*
 * We try to force mbedtls_(get|put)_unaligned_uintXX to be always inline, because this
 * results in code that is both smaller and faster. IAR and gcc both benefit from this
 * when optimising for size.
 */

/**
 * Read the unsigned 16 bits integer from the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 2 bytes of data
 * \return  Data at the given address
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline uint16_t mbedtls_get_unaligned_uint16( const void *p )
{
    uint16_t r;
#if defined(UINT_UNALIGNED)
    mbedtls_uint16_unaligned_t *p16 = (mbedtls_uint16_unaligned_t *) p;
    r = *p16;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint16_unaligned_t *p16 = (mbedtls_uint16_unaligned_t *) p;
    r = p16->x;
#else
    memcpy( &r, p, sizeof( r ) );
#endif
    return( r );
}

/**
 * Write the unsigned 16 bits integer to the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 2 bytes of data
 * \param   x data to write
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline void mbedtls_put_unaligned_uint16( void *p, uint16_t x )
{
#if defined(UINT_UNALIGNED)
    mbedtls_uint16_unaligned_t *p16 = (mbedtls_uint16_unaligned_t *) p;
    *p16 = x;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint16_unaligned_t *p16 = (mbedtls_uint16_unaligned_t *) p;
    p16->x = x;
#else
    memcpy( p, &x, sizeof( x ) );
#endif
}

/**
 * Read the unsigned 32 bits integer from the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 4 bytes of data
 * \return  Data at the given address
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline uint32_t mbedtls_get_unaligned_uint32( const void *p )
{
    uint32_t r;
#if defined(UINT_UNALIGNED)
    mbedtls_uint32_unaligned_t *p32 = (mbedtls_uint32_unaligned_t *) p;
    r = *p32;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint32_unaligned_t *p32 = (mbedtls_uint32_unaligned_t *) p;
    r = p32->x;
#else
    memcpy( &r, p, sizeof( r ) );
#endif
    return( r );
}

/**
 * Write the unsigned 32 bits integer to the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 4 bytes of data
 * \param   x data to write
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline void mbedtls_put_unaligned_uint32( void *p, uint32_t x )
{
#if defined(UINT_UNALIGNED)
    mbedtls_uint32_unaligned_t *p32 = (mbedtls_uint32_unaligned_t *) p;
    *p32 = x;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint32_unaligned_t *p32 = (mbedtls_uint32_unaligned_t *) p;
    p32->x = x;
#else
    memcpy( p, &x, sizeof( x ) );
#endif
}

/**
 * Read the unsigned 64 bits integer from the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 8 bytes of data
 * \return  Data at the given address
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline uint64_t mbedtls_get_unaligned_uint64( const void *p )
{
    uint64_t r;
#if defined(UINT_UNALIGNED)
    mbedtls_uint64_unaligned_t *p64 = (mbedtls_uint64_unaligned_t *) p;
    r = *p64;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint64_unaligned_t *p64 = (mbedtls_uint64_unaligned_t *) p;
    r = p64->x;
#else
    memcpy( &r, p, sizeof( r ) );
#endif
    return( r );
}

/**
 * Write the unsigned 64 bits integer to the given address, which need not
 * be aligned.
 *
 * \param   p pointer to 8 bytes of data
 * \param   x data to write
 */
#if defined(__IAR_SYSTEMS_ICC__)
#pragma inline = forced
#elif defined(__GNUC__)
__attribute__((always_inline))
#endif
static inline void mbedtls_put_unaligned_uint64( void *p, uint64_t x )
{
#if defined(UINT_UNALIGNED)
    mbedtls_uint64_unaligned_t *p64 = (mbedtls_uint64_unaligned_t *) p;
    *p64 = x;
#elif defined(UINT_UNALIGNED_STRUCT)
    mbedtls_uint64_unaligned_t *p64 = (mbedtls_uint64_unaligned_t *) p;
    p64->x = x;
#else
    memcpy( p, &x, sizeof( x ) );
#endif
}

#if defined(MBEDTLS_POP_IAR_LANGUAGE_PRAGMA)
#pragma language=restore
#endif

#endif /* MBEDTLS_LIBRARY_ALIGNMENT_H */
