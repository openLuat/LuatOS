/*
 * luat_ppp_md4.h - MSCHAPv2 需要的 MD4, 按 mbedtls 的命名对外提供。
 *
 * 为什么需要它:
 *   MSCHAPv2 的 NT-Password-Hash 必须用 MD4(RFC 2759), 而本仓库各版 mbedtls 都不提供:
 *     - components/mbedtls3: mbedtls_config.h 里没有 MBEDTLS_MD4_C(PC 与 Air1601 都用这份)
 *     - components/mbedtls: MBEDTLS_MD4_C 被注释掉
 *     - components/mbedtls4: 连 md4.h 都没有
 *   同时 lwip 自带的 polarssl 副本(lwip22/netif/ppp/polarssl/md4.c)被
 *   LWIP_INCLUDED_POLARSSL_MD4 关掉了(LWIP_USE_EXTERNAL_MBEDTLS=1)。
 *   所以这里把那份 BSD 许可的实现改名编进来, 供 pppcrypt.h 的
 *   `lwip_md4_* -> mbedtls_md4_*` 映射使用。
 *
 * 将来某个 mbedtls 版本提供了 MBEDTLS_MD4_C 时, 本文件整体让位(见下 guard)。
 */
#ifndef LUAT_PPP_MD4_H
#define LUAT_PPP_MD4_H

#include "netif/ppp/ppp_opts.h"

/* MSCHAP_SUPPORT 关闭时不需要 MD4; 已有 MBEDTLS_MD4_C 时也不重复提供 */
#if PPP_SUPPORT && MSCHAP_SUPPORT && !defined(MBEDTLS_MD4_C)

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct
{
    unsigned long total[2];     /*!< number of bytes processed  */
    unsigned long state[4];     /*!< intermediate digest state  */
    unsigned char buffer[64];   /*!< data block being processed */
}
mbedtls_md4_context;

void mbedtls_md4_init( mbedtls_md4_context *ctx );
void mbedtls_md4_free( mbedtls_md4_context *ctx );
void mbedtls_md4_starts( mbedtls_md4_context *ctx );
/* 注意: 长度参数用 int, 与本文件 .c 里 vendor 实现的签名一致(不是 mbedtls 的 size_t) */
void mbedtls_md4_update( mbedtls_md4_context *ctx, const unsigned char *input, int ilen );
void mbedtls_md4_finish( mbedtls_md4_context *ctx, unsigned char output[16] );

#ifdef __cplusplus
}
#endif

#endif /* PPP_SUPPORT && MSCHAP_SUPPORT && !MBEDTLS_MD4_C */

#endif /* LUAT_PPP_MD4_H */
