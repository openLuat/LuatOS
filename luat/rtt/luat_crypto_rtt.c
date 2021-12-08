
#include "luat_base.h"
#include "luat_crypto.h"

#include "rtthread.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

#ifdef RT_USING_HWCRYPTO
#include "hwcrypto.h"

#ifdef RT_HWCRYPTO_USING_MD5
#define LUAT_CRYPTO_MD5
int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    struct rt_hwcrypto_ctx *ctx;

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_MD5);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }
    rt_hwcrypto_hash_update(ctx, str, str_size);
    rt_hwcrypto_hash_finish(ctx, out_ptr, 32);
    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}

int luat_crypto_hmac_md5_simple(const char* input, size_t ilen, const char* key, size_t keylen, void* output) {
    int i;
    struct rt_hwcrypto_ctx *ctx;

    unsigned char k_ipad[64] = {0};
    unsigned char k_opad[64] = {0};
    //unsigned char tempbuf[16];

    memset(k_ipad, 0x36, 64);
    memset(k_opad, 0x5C, 64);

    for(i=0; i<keylen; i++)
    {
        if(i>=64)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_MD5);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }

    rt_hwcrypto_hash_update(ctx, k_ipad, 64);
    rt_hwcrypto_hash_update(ctx, input, ilen);
    rt_hwcrypto_hash_finish(ctx, output);

    //rt_hwcrypto_ctx_reset(ctx);
    rt_hwcrypto_hash_destroy(ctx);
    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_MD5);

    rt_hwcrypto_hash_update(ctx, k_opad, 64);
    rt_hwcrypto_hash_update(ctx, output, 16);
    rt_hwcrypto_hash_finish(ctx, output);

    //rt_memcpy(output, tempbuf, 16);

    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}

#endif

#ifdef RT_HWCRYPTO_USING_SHA1
#define LUAT_CRYPTO_SHA1
int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    struct rt_hwcrypto_ctx *ctx;

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_SHA1);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }
    rt_hwcrypto_hash_update(ctx, str, str_size);
    rt_hwcrypto_hash_finish(ctx, out_ptr, 40);
    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}
int luat_crypto_hmac_sha1_simple(const char* input, size_t ilen, const char* key, size_t keylen, void* output) {
    int i;
    struct rt_hwcrypto_ctx *ctx;

    unsigned char k_ipad[64] = {0};
    unsigned char k_opad[64] = {0};
    //unsigned char tempbuf[20];

    memset(k_ipad, 0x36, 64);
    memset(k_opad, 0x5C, 64);

    for(i=0; i<keylen; i++)
    {
        if(i>=64)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }

    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_SHA1);
    if (ctx == NULL) {
        return -1; // 内存爆了??
    }

    rt_hwcrypto_hash_update(ctx, k_ipad, 64);
    rt_hwcrypto_hash_update(ctx, input, ilen);
    rt_hwcrypto_hash_finish(ctx, output);

    //rt_hwcrypto_ctx_reset(ctx);
    rt_hwcrypto_hash_destroy(ctx);
    ctx = rt_hwcrypto_hash_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_SHA1);

    rt_hwcrypto_hash_update(ctx, k_opad, 64);
    rt_hwcrypto_hash_update(ctx, output, 20);
    rt_hwcrypto_hash_finish(ctx, output);

    //rt_memcpy(output, tempbuf, 20);

    rt_hwcrypto_hash_destroy(ctx);
    return 0;
}
#endif

#endif

#ifdef PKG_USING_MBEDTLS
#include "mbedtls/cipher.h"
#endif

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags) {
    size_t cipher_size = 0;
    size_t pad_size = 0;
    size_t str_size = 0;
    size_t key_size = 0;
    size_t iv_size = 0;
    const char* cipher = luaL_optlstring(L, 1, "AES-128-ECB", &cipher_size);
    const char* pad = luaL_optlstring(L, 2, "PKCS7", &pad_size);
    const char* str = luaL_checklstring(L, 3, &str_size);
    const char* key = luaL_checklstring(L, 4, &key_size);
    const char* iv = luaL_optlstring(L, 5, "", &iv_size);

    int ret = 0;

    unsigned char output[32] = {0};
    size_t input_size = 0;
    size_t output_size = 0;
    size_t block_size = 0;
    
    luaL_Buffer buff;

#ifdef PKG_USING_MBEDTLS
    mbedtls_cipher_context_t ctx;
    mbedtls_cipher_init(&ctx);



    const mbedtls_cipher_info_t * _cipher = mbedtls_cipher_info_from_string(cipher);
    if (_cipher == NULL) {
        lua_pushstring(L, "bad cipher name");
        lua_error(L);
        return 0;
    }


	ret = mbedtls_cipher_setup(&ctx, _cipher);
    if (ret) {
        LLOGE("mbedtls_cipher_setup fail %ld", ret);
        goto _exit;
    }
    ret = mbedtls_cipher_setkey(&ctx, key, key_size * 8, flags & 0x1);
    if (ret) {
        LLOGE("mbedtls_cipher_setkey fail %ld", ret);
        goto _exit;
    }
    // TODO 设置padding mode
    // mbedtls_cipher_set_padding_mode
    if (iv_size) {
        ret = mbedtls_cipher_set_iv(&ctx, iv, iv_size);
        if (ret) {
            LLOGE("mbedtls_cipher_set_iv fail %ld", ret);
            goto _exit;
        }
    }

    mbedtls_cipher_reset(&ctx);

    //mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_PKCS7);

    // 开始注入数据
    luaL_buffinit(L, &buff);
    block_size = mbedtls_cipher_get_block_size(&ctx);
    for (size_t i = 0; i < str_size; i+=block_size) {
        input_size = str_size - i;
        if (input_size > block_size)
            input_size = block_size;
        ret = mbedtls_cipher_update(&ctx, str+i, input_size, output, &output_size);
        if (ret) {
            LLOGE("mbedtls_cipher_update fail %ld", ret);
            goto _exit;
        }
        //else LLOGD("mbedtls_cipher_update, output size=%ld", output_size);
        if (output_size > 0)
            luaL_addlstring(&buff, output, output_size);
        output_size = 0;
    }
    ret = mbedtls_cipher_finish(&ctx, output, &output_size);
    if (ret) {
        LLOGE("mbedtls_cipher_finish fail %ld", ret);
        goto _exit;
    }
    //else LLOGD("mbedtls_cipher_finish, output size=%ld", output_size);
    if (output_size > 0)
        luaL_addlstring(&buff, output, output_size);

_exit:
    mbedtls_cipher_free(&ctx);
    luaL_pushresult(&buff);
    return 1;
#else

//#ifdef RT_USING_HWCRYPTO
// rtt的AES硬件加密, CBC输出的是等长数据, 不太对吧
#if 0
    struct rt_hwcrypto_ctx *ctx = NULL;
    #ifdef RT_HWCRYPTO_USING_AES
        hwcrypto_mode mode = flags == 0 ? HWCRYPTO_MODE_DECRYPT : HWCRYPTO_MODE_ENCRYPT;
        ret = -1;
        luaL_buffinit(L, &buff);
        #ifdef RT_HWCRYPTO_USING_AES_ECB
        if (!strcmp("AES-128-ECB", cipher)) {
            LLOGD("AES-128-ECB HWCRYPTO");
            ctx = rt_hwcrypto_symmetric_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_AES_ECB);
            ret = rt_hwcrypto_symmetric_setkey(ctx, key, 128);
            ret = rt_hwcrypto_symmetric_crypt(ctx, mode, (str_size / 16) * 16, str, output);
            buff.n = str_size;
        }
        #endif
        #ifdef RT_HWCRYPTO_USING_AES_CBC
        if (!strcmp("AES-128-CBC", cipher)) {
            LLOGD("AES-128-CBC HWCRYPTO");
            ctx = rt_hwcrypto_symmetric_create(rt_hwcrypto_dev_default(), HWCRYPTO_TYPE_AES_CBC);
            ret = rt_hwcrypto_symmetric_setkey(ctx, key, 128);
            ret = rt_hwcrypto_symmetric_setiv(ctx, iv, iv_size);
            ret = rt_hwcrypto_symmetric_crypt(ctx, mode, (str_size / 16) * 16, str, output);
            buff.n = str_size + (flags == 0 ? -16 : 16);
        }
        #endif
        if (ctx)
            rt_hwcrypto_symmetric_destroy(ctx);
        if (ret) {
            LLOGW("AES FAIL %d", ret);
            return 0;
        }
        else {
            luaL_pushresult(&buff);
            return 1;
        }
    #endif
#endif

    return 0;
#endif
}


#ifdef PKG_USING_MBEDTLS

#if !defined(MBEDTLS_CONFIG_FILE)
#include "mbedtls/config.h"
#else
#include MBEDTLS_CONFIG_FILE
#endif

#include "mbedtls/sha1.h"
#include "mbedtls/sha256.h"
#ifdef MBEDTLS_SHA512_C
#include "mbedtls/sha512.h"
#endif
#include "mbedtls/md5.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

void luat_crypto_HmacSha1(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacSha256(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacSha512(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);
void luat_crypto_HmacMd5(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen);

#ifndef LUAT_CRYPTO_MD5
#define LUAT_CRYPTO_MD5
int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_md5_context ctx;
    mbedtls_md5_init(&ctx);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_md5_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_md5_free(&ctx);
    return 0;
}
#endif
#ifndef LUAT_CRYPTO_SHA1
#define LUAT_CRYPTO_SHA1
int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha1_context ctx;
    mbedtls_sha1_init(&ctx);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha1_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha1_free(&ctx);
    return 0;
}
#endif

int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha256_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha256_free(&ctx);
    return 0;
}
#ifdef MBEDTLS_SHA512_C
int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {
    mbedtls_sha512_context ctx;
    mbedtls_sha512_init(&ctx);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, (const unsigned char *)str, str_size);
    mbedtls_sha512_finish(&ctx, (unsigned char *)out_ptr);
    mbedtls_sha512_free(&ctx);
    return 0;
}
#endif

#ifndef LUAT_CRYPTO_MD5
#define LUAT_CRYPTO_MD5
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacMd5((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}
#endif
#ifndef LUAT_CRYPTO_SHA1
#define LUAT_CRYPTO_SHA1
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha1((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}
#endif

int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha256((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}
#ifdef MBEDTLS_SHA512_C
int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    luat_crypto_HmacSha512((const unsigned char *)str, str_size, (unsigned char *)out_ptr, (const unsigned char *)mac, mac_size);
    return 0;
}
#endif


///----------------------------

#define ALI_SHA1_KEY_IOPAD_SIZE (64)
#define ALI_SHA1_DIGEST_SIZE    (20)

#define ALI_SHA256_KEY_IOPAD_SIZE   (64)
#define ALI_SHA256_DIGEST_SIZE      (32)

#define ALI_SHA512_KEY_IOPAD_SIZE   (128)
#define ALI_SHA512_DIGEST_SIZE      (64)

#define ALI_MD5_KEY_IOPAD_SIZE  (64)
#define ALI_MD5_DIGEST_SIZE     (16)

// char atHb2Hex(unsigned char hb)
// {
//     hb = hb&0xF;
//     return (char)(hb<10 ? '0'+hb : hb-10+'a');
// }


/*
 * output = SHA-1( input buffer )
 */
void luat_crypto_HmacSha1(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha1_context ctx;
    unsigned char k_ipad[ALI_SHA1_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA1_KEY_IOPAD_SIZE] = {0};
    unsigned char tempbuf[ALI_SHA1_DIGEST_SIZE];

    memset(k_ipad, 0x36, ALI_SHA1_KEY_IOPAD_SIZE);
    memset(k_opad, 0x5C, ALI_SHA1_KEY_IOPAD_SIZE);

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA1_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha1_init(&ctx);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, k_ipad, ALI_SHA1_KEY_IOPAD_SIZE);
    mbedtls_sha1_update(&ctx, input, ilen);
    mbedtls_sha1_finish(&ctx, tempbuf);

    mbedtls_sha1_starts(&ctx);
    mbedtls_sha1_update(&ctx, k_opad, ALI_SHA1_KEY_IOPAD_SIZE);
    mbedtls_sha1_update(&ctx, tempbuf, ALI_SHA1_DIGEST_SIZE);
    mbedtls_sha1_finish(&ctx, tempbuf);

    // for(i=0; i<ALI_SHA1_DIGEST_SIZE; ++i)
    // {
    //     output[i*2] = atHb2Hex(tempbuf[i]>>4);
    //     output[i*2+1] = atHb2Hex(tempbuf[i]);
    // }
    memcpy(output, tempbuf, ALI_SHA1_DIGEST_SIZE);

    mbedtls_sha1_free(&ctx);
}
/*
 * output = SHA-256( input buffer )
 */
void luat_crypto_HmacSha256(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha256_context ctx;
    unsigned char k_ipad[ALI_SHA256_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA256_KEY_IOPAD_SIZE] = {0};

    memset(k_ipad, 0x36, 64);
    memset(k_opad, 0x5C, 64);

    if ((NULL == input) || (NULL == key) || (NULL == output)) {
        return;
    }

    if (keylen > ALI_SHA256_KEY_IOPAD_SIZE) {
        return;
    }

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA256_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha256_init(&ctx);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, k_ipad, ALI_SHA256_KEY_IOPAD_SIZE);
    mbedtls_sha256_update(&ctx, input, ilen);
    mbedtls_sha256_finish(&ctx, output);

    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, k_opad, ALI_SHA256_KEY_IOPAD_SIZE);
    mbedtls_sha256_update(&ctx, output, ALI_SHA256_DIGEST_SIZE);
    mbedtls_sha256_finish(&ctx, output);

    mbedtls_sha256_free(&ctx);
}
#ifdef MBEDTLS_SHA512_C
/*
 * output = SHA-512( input buffer )
 */
void luat_crypto_HmacSha512(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_sha512_context ctx;
    unsigned char k_ipad[ALI_SHA512_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_SHA512_KEY_IOPAD_SIZE] = {0};

    memset(k_ipad, 0x36, 64);
    memset(k_opad, 0x5C, 64);

    if ((NULL == input) || (NULL == key) || (NULL == output)) {
        return;
    }

    if (keylen > ALI_SHA512_KEY_IOPAD_SIZE) {
        return;
    }

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_SHA512_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_sha512_init(&ctx);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, k_ipad, ALI_SHA512_KEY_IOPAD_SIZE);
    mbedtls_sha512_update(&ctx, input, ilen);
    mbedtls_sha512_finish(&ctx, output);

    mbedtls_sha512_starts(&ctx, 0);
    mbedtls_sha512_update(&ctx, k_opad, ALI_SHA512_KEY_IOPAD_SIZE);
    mbedtls_sha512_update(&ctx, output, ALI_SHA512_DIGEST_SIZE);
    mbedtls_sha512_finish(&ctx, output);

    mbedtls_sha512_free(&ctx);
}
#endif
/*
 * output = MD-5( input buffer )
 */
void luat_crypto_HmacMd5(const unsigned char *input, int ilen, unsigned char *output,const unsigned char *key, int keylen)
{
    int i;
    mbedtls_md5_context ctx;
    unsigned char k_ipad[ALI_MD5_KEY_IOPAD_SIZE] = {0};
    unsigned char k_opad[ALI_MD5_KEY_IOPAD_SIZE] = {0};
    unsigned char tempbuf[ALI_MD5_DIGEST_SIZE];

    memset(k_ipad, 0x36, ALI_MD5_KEY_IOPAD_SIZE);
    memset(k_opad, 0x5C, ALI_MD5_KEY_IOPAD_SIZE);

    for(i=0; i<keylen; i++)
    {
        if(i>=ALI_MD5_KEY_IOPAD_SIZE)
        {
            break;
        }
        k_ipad[i] ^=key[i];
        k_opad[i] ^=key[i];
    }
    mbedtls_md5_init(&ctx);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, k_ipad, ALI_MD5_KEY_IOPAD_SIZE);
    mbedtls_md5_update(&ctx, input, ilen);
    mbedtls_md5_finish(&ctx, tempbuf);

    mbedtls_md5_starts(&ctx);
    mbedtls_md5_update(&ctx, k_opad, ALI_MD5_KEY_IOPAD_SIZE);
    mbedtls_md5_update(&ctx, tempbuf, ALI_MD5_DIGEST_SIZE);
    mbedtls_md5_finish(&ctx, tempbuf);

    // for(i=0; i<ALI_MD5_DIGEST_SIZE; ++i)
    // {
    //     output[i*2] = atHb2Hex(tempbuf[i]>>4);
    //     output[i*2+1] = atHb2Hex(tempbuf[i]);
    // }
    memcpy(output, tempbuf, ALI_MD5_DIGEST_SIZE);
    mbedtls_md5_free(&ctx);
}
#endif
