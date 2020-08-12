
#include "luat_base.h"
#include "luat_crypto.h"

#include "rtthread.h"

#define LUAT_LOG_TAG "luat.crypto"
#include "luat_log.h"

#ifdef RT_USING_HWCRYPTO
#include "hwcrypto.h"

#ifdef RT_HWCRYPTO_USING_MD5
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

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags) {
    LLOGE("not support yet");
    lua_pushliteral(L, "");
    return 1;
}
