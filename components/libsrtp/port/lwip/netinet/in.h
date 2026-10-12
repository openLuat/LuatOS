/* Private embedded POSIX byte-order shim. No socket API is needed by libsrtp.
 * Keep this independent of LwIP: its vendor arch/debug headers assume an
 * application include order that standalone crypto translation units lack. */
#ifndef LUAT_LIBSRTP_LWIP_NETINET_IN_H
#define LUAT_LIBSRTP_LWIP_NETINET_IN_H
#include <stdint.h>

static inline uint16_t luat_srtp_net16(uint16_t value)
{
#ifdef WORDS_BIGENDIAN
    return value;
#else
    return (uint16_t)((value << 8) | (value >> 8));
#endif
}

static inline uint32_t luat_srtp_net32(uint32_t value)
{
#ifdef WORDS_BIGENDIAN
    return value;
#else
    return ((value & UINT32_C(0x000000ff)) << 24) |
           ((value & UINT32_C(0x0000ff00)) << 8) |
           ((value & UINT32_C(0x00ff0000)) >> 8) |
           ((value & UINT32_C(0xff000000)) >> 24);
#endif
}

#ifndef htons
#define htons(value) luat_srtp_net16(value)
#endif
#ifndef ntohs
#define ntohs(value) luat_srtp_net16(value)
#endif
#ifndef htonl
#define htonl(value) luat_srtp_net32(value)
#endif
#ifndef ntohl
#define ntohl(value) luat_srtp_net32(value)
#endif
#endif
