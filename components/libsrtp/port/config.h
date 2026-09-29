/* LuatOS configuration for the pinned libsrtp 2.8.1 sources. */
#ifndef LUAT_LIBSRTP_CONFIG_H
#define LUAT_LIBSRTP_CONFIG_H

#define PACKAGE_VERSION "2.8.1"
#define PACKAGE_STRING "libsrtp 2.8.1"
#define MBEDTLS 1
/* GCM and debug logging are deliberately disabled. */
#define HAVE_STDLIB_H 1
#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_UINT8_T 1
#define HAVE_UINT16_T 1
#define HAVE_UINT32_T 1
#define HAVE_UINT64_T 1
#define HAVE_INT32_T 1
#define HAVE_INLINE 1

#if defined(_WIN32)
#define HAVE_WINSOCK2_H 1
#define CPU_CISC 1
#elif defined(__unix__) || defined(__APPLE__)
#define HAVE_NETINET_IN_H 1
#define CPU_CISC 1
#else
/* The private port/lwip/netinet/in.h shim supplies byte order helpers. */
#define HAVE_NETINET_IN_H 1
#define CPU_RISC 1
#define ALIGNMENT_32BIT_REQUIRED 1
#endif

#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define WORDS_BIGENDIAN 1
#endif

#if defined(_MSC_VER) && !defined(__clang__)
#define inline __inline
#endif
#endif
