#include "luat_base.h"
#include "luat_malloc.h"

#include "string.h"

#ifdef LUAT_USE_LIBTCPIP_MBEDTLS

#include "mbedtls/net_sockets.h"
#include "mbedtls/net.h"
#include "mbedtls/ssl.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/debug.h"

#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>

#include "luat_libtcpip.h"

#define LUAT_LOG_TAG "mbedtls"
#include "luat_log.h"

#define mbedtls_printf    LLOGD

typedef struct luat_libtcpip_mbedtls_ssl_ctx
{
    mbedtls_net_context server_fd;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_x509_crt cacert;
}luat_libtcpip_mbedtls_ssl_ctx_t;


static int luat_libtcpip_socket_mbedtls_ssl(int domain, int type, int protocol) {
    int ret = 0;
    const char *pers = "ssl_client1";
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = luat_heap_malloc(sizeof(luat_libtcpip_mbedtls_ssl_ctx_t));
    if (ctx == NULL)
        return 0;
    mbedtls_net_init( &ctx->server_fd );
    mbedtls_ssl_init( &ctx->ssl );
    mbedtls_ssl_config_init( &ctx->conf );
    mbedtls_x509_crt_init( &ctx->cacert );
    mbedtls_ctr_drbg_init( &ctx->ctr_drbg );

    mbedtls_entropy_init( &ctx->entropy );


    // 初始化种子
    if( ( ret = mbedtls_ctr_drbg_seed( &ctx->ctr_drbg, mbedtls_entropy_func, &ctx->entropy,
                           (const unsigned char *) pers,
                           strlen( pers ) ) ) != 0 )
    {
        printf( " failed\n  ! mbedtls_ctr_drbg_seed returned %d\n", ret );
        goto fail;
    }

    // 处理证书，如果有的话
    // ret = mbedtls_x509_crt_parse( &ctx->cacert, (const unsigned char *) iotda_crt_pem, sizeof(iotda_crt_pem) );
    // if (ret != 0) {
    //     printf( " failed\n  ! mbedtls_x509_crt_parse returned %d\n", ret );
    //     goto fail;
    // }

    return (int)ctx;

fail:
    luat_heap_free(ctx);
    return 0;

}

static int luat_libtcpip_send_mbedtls_ssl(int s, const void *data, size_t size, int flags) {
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = (luat_libtcpip_mbedtls_ssl_ctx_t*)s;
    return mbedtls_ssl_write(&ctx->ssl, data, size);
}

static int luat_libtcpip_recv_mbedtls_ssl(int s, void *mem, size_t len, int flags) {
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = (luat_libtcpip_mbedtls_ssl_ctx_t*)s;
    // 设置好超时
    mbedtls_ssl_conf_read_timeout(&ctx->conf, 1);

    int ret = mbedtls_ssl_read(&ctx->ssl, mem, len);
    if( ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE )
        return 0;
    if( ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY )
        return -1;
    if (ret < 0) {
        // mbedtls_printf("mbedtls_ssl_read ret = %d", ret);
        return ret;
    }
    return ret;
}

static int luat_libtcpip_recv_timeout_mbedtls_ssl(int s, void *mem, size_t len, int flags, int timeout) {
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = (luat_libtcpip_mbedtls_ssl_ctx_t*)s;
    // 设置好超时
    mbedtls_ssl_conf_read_timeout(&ctx->conf, timeout);

    int ret = mbedtls_ssl_read(&ctx->ssl, mem, len);
    if( ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE )
        return 0;
    if( ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY )
        return -1;
    if (ret < 0) {
        // mbedtls_printf("mbedtls_ssl_read ret = %d", ret);
        return ret;
    }
    return ret;
}

// static int luat_libtcpip_select_mbedtls_ssl(int maxfdp1, fd_set *readset, fd_set *writeset, fd_set *exceptset,
//             struct timeval *timeout) {
//     return select(maxfdp1, readset, writeset, exceptset, timeout);
// }

static int luat_libtcpip_close_mbedtls_ssl(int s) {
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = (luat_libtcpip_mbedtls_ssl_ctx_t*)s;
    if (ctx == NULL)
        return 0;
    mbedtls_net_free( &ctx->server_fd );

    mbedtls_x509_crt_free( &ctx->cacert );
    mbedtls_ssl_free( &ctx->ssl );
    mbedtls_ssl_config_free( &ctx->conf );
    mbedtls_ctr_drbg_free( &ctx->ctr_drbg );
    mbedtls_entropy_free( &ctx->entropy );
    luat_heap_free(ctx);
    return 0;
}

static int luat_libtcpip_connect_mbedtls_ssl(int s, const char *hostname, uint16_t _port) {
    // 1. Start the connection
    int ret = 0;
    uint32_t flags;
    char port[8] = {0};
    sprintf(port, "%d", _port);
    luat_libtcpip_mbedtls_ssl_ctx_t* ctx = (luat_libtcpip_mbedtls_ssl_ctx_t*)s;
    ret = mbedtls_net_connect(&ctx->server_fd, hostname, port, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        mbedtls_printf("mbedtls_net_connect %d\n", ret);
        return -1;
    }

    // Setting up the SSL/TLS structure...
    if( ( ret = mbedtls_ssl_config_defaults( &ctx->conf,
                    MBEDTLS_SSL_IS_CLIENT,
                    MBEDTLS_SSL_TRANSPORT_STREAM,
                    MBEDTLS_SSL_PRESET_DEFAULT ) ) != 0 )
    {
        mbedtls_printf( " failed\n  ! mbedtls_ssl_config_defaults returned %d\n\n", ret );
        return -2;
    }

    // 暂时禁用证书验证
    // mbedtls_ssl_conf_authmode( &ctx->conf, MBEDTLS_SSL_VERIFY_OPTIONAL );
    mbedtls_ssl_conf_authmode( &ctx->conf, MBEDTLS_SSL_VERIFY_NONE );
    //mbedtls_ssl_conf_ca_chain( &ctx->conf, &ctx->cacert, NULL );
    mbedtls_ssl_conf_rng( &ctx->conf, mbedtls_ctr_drbg_random, &ctx->ctr_drbg );

    if( ( ret = mbedtls_ssl_setup( &ctx->ssl, &ctx->conf ) ) != 0 )
    {
        mbedtls_printf( " failed\n  ! mbedtls_ssl_setup returned %d\n\n", ret );
        return -3;
    }

    if( ( ret = mbedtls_ssl_set_hostname( &ctx->ssl, hostname ) ) != 0 )
    {
        mbedtls_printf( " failed\n  ! mbedtls_ssl_set_hostname returned %d\n\n", ret );
        return -4;
    }

    mbedtls_ssl_set_bio( &ctx->ssl, &ctx->server_fd, mbedtls_net_send, NULL, mbedtls_net_recv_timeout );
    while( ( ret = mbedtls_ssl_handshake( &ctx->ssl ) ) != 0 )
    {
        if( ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE )
        {
            mbedtls_printf( " failed\n  ! mbedtls_ssl_handshake returned -0x%x\n\n", (unsigned int) -ret );
            // goto exit;
            return -5;
        }
    }

    if( ( flags = mbedtls_ssl_get_verify_result( &ctx->ssl ) ) != 0 ) {
        mbedtls_printf( " failed\n  ! mbedtls_ssl_get_verify_result returned %d\n\n", flags );
        return -6;
    }

    return 0;

// exit :
//     return -1;
}

static struct hostent* luat_libtcpip_gethostbyname_mbedtls_ssl(const char* name) {
    return gethostbyname(name);
}

static int luat_libtcpip_setsockopt_mbedtls_ssl(int s, int level, int optname, const void *optval, uint32_t optlen) {
    // return setsockopt(s, level, optname, optval, optlen);
    return 0; // nop
}

luat_libtcpip_opts_t luat_libtcpip_mbedtls_ssl = {
    ._socket = luat_libtcpip_socket_mbedtls_ssl,
    ._close = luat_libtcpip_close_mbedtls_ssl,
    ._connect = luat_libtcpip_connect_mbedtls_ssl,
    ._gethostbyname = luat_libtcpip_gethostbyname_mbedtls_ssl,
    ._recv = luat_libtcpip_recv_mbedtls_ssl,
    ._recv_timeout = luat_libtcpip_recv_timeout_mbedtls_ssl,
    // ._select = luat_libtcpip_select_mbedtls_ssl,
    ._send = luat_libtcpip_send_mbedtls_ssl,
    ._setsockopt = luat_libtcpip_setsockopt_mbedtls_ssl
};

#endif
