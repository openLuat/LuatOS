// crypto库的软件实现, 基于mbedtls

#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

#include "mbedtls/cipher.h"
#include "mbedtls/md.h"

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags) {
    size_t cipher_size = 0;
    size_t pad_size = 0;
    size_t ilen = 0;
    size_t key_size = 0;
    size_t iv_size = 0;

    size_t block_size = 0;

    uint8_t output[64];
    size_t olen = 0;
    int ret = 0;
    mbedtls_cipher_context_t ctx;
    mbedtls_operation_t opt;
    const mbedtls_cipher_info_t * _cipher;
    luaL_Buffer buff;

    mbedtls_cipher_mode_t mode;

    const char* cipher = luaL_optlstring(L, 1, "AES-128-ECB", &cipher_size);
    const char* pad = luaL_optlstring(L, 2, "PKCS7", &pad_size);
    const char* in = luaL_checklstring(L, 3, &ilen);
    const char* key = luaL_checklstring(L, 4, &key_size);
    const char* iv = luaL_optlstring(L, 5, "", &iv_size);

    if (luaL_buffinitsize(L, &buff, ilen + 16) == NULL) {
        LLOGW("out of memory when malloc output");
        return 0;
    }

    mbedtls_cipher_init(&ctx);
    opt = flags & 0x01 ? MBEDTLS_ENCRYPT : MBEDTLS_DECRYPT;
    //LLOGD("mbedtls_operation_t %d", opt);

    _cipher = mbedtls_cipher_info_from_string(cipher);
    if (_cipher == NULL) {
    	LLOGW("%s not support", cipher);
        goto _error_exit;
    }
    mode = mbedtls_cipher_info_get_mode(_cipher);
    block_size = mbedtls_cipher_info_get_block_size(_cipher);
    //LLOGD("mbedtls_cipher_get_block_size %d", block_size);

	ret = mbedtls_cipher_setup(&ctx, _cipher);
    //LLOGD("mbedtls_cipher_setup %d", ret);
    if (ret) {
        LLOGW("mbedtls_cipher_setup 0x%04x %s", -ret, cipher);
        goto _error_exit;
    }


    ret = mbedtls_cipher_setkey(&ctx, (const unsigned char*)key, key_size * 8, opt);
    //LLOGD("mbedtls_cipher_setkey %d", ret);
    if (ret) {
        LLOGW("mbedtls_cipher_setkey 0x%04x %s", -ret, cipher);
        goto _error_exit;
    }

    if (MBEDTLS_MODE_ECB != mode && iv_size == 0) {
        LLOGW("need iv!!");
        goto _error_exit;
    }
    else {
        ret = mbedtls_cipher_set_iv(&ctx, (const unsigned char*)iv, iv_size);
        //LLOGD("mbedtls_cipher_set_iv %d", opt);
        if (ret) {
            LLOGW("mbedtls_cipher_set_iv 0x%04x", -ret);
            goto _error_exit;
        }
    }

    //LLOGD("mbedtls_cipher_get_cipher_mode %d", mode);
    if (MBEDTLS_MODE_CBC == mode) {
        

        // 仅CBC支持padding
        if (!strcmp("PKCS7", pad)) {
            mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_PKCS7);
        }
        else if (!strcmp("ZERO", pad) || !strcmp("ZEROS", pad)) {
            mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS);
        }
        else if (!strcmp("ONE_AND_ZEROS", pad)) {
            mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ONE_AND_ZEROS);
        }
        else if (!strcmp("ZEROS_AND_LEN", pad)) {
            mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_ZEROS_AND_LEN);
        }
        else {
            mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_NONE);
        }
    }
    
    if (MBEDTLS_MODE_CBC != mode && ilen % block_size != 0) {
        LLOGW("data size must be n*%d , but %d", block_size, ilen);
        goto _error_exit;
    }

    ret = mbedtls_cipher_reset( &ctx );
    //LLOGD("mbedtls_cipher_reset ret %d", ret);
    if (ret) {
        LLOGE("mbedtls_cipher_reset 0x%04X", -ret);
        goto _exit;
    }

    for (size_t i = 0; i < ilen; i+=block_size)
    {
        ret = mbedtls_cipher_update(&ctx, (const unsigned char*)(in + i), block_size, output, &olen);
        if (ret) {
            LLOGE("mbedtls_cipher_update 0x%04X", -ret);
            goto _exit;
        }
        if (olen > 0) {
            luaL_addlstring(&buff, (const char*)output, olen);
        }
    }
    
    ret = mbedtls_cipher_finish(&ctx, output, &olen);
    if (ret) {
        LLOGE("mbedtls_cipher_finish 0x%04X", -ret);
        goto _exit;
    }
    if (olen > 0) {
        luaL_addlstring(&buff, (const char*)output, olen);
    }

_exit:
    mbedtls_cipher_free(&ctx);
    luaL_pushresult(&buff);
    return 1;
_error_exit:
	mbedtls_cipher_free(&ctx);
	return 0;
}

int luat_crypto_md(int64_t md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len) {
    // mbedtls_md_context_t ctx;
    const mbedtls_md_info_t * info = mbedtls_md_info_from_type((mbedtls_md_type_t)md);
    if (info == NULL) {
        return -1;
    }
    if (key_len < 1) {
        mbedtls_md(info, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    else {
        mbedtls_md_hmac(info, (const unsigned char*)key, key_len, (const unsigned char*)str, str_size, (unsigned char*)out_ptr);
    }
    return 0;
}

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_MD5, str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_MD5, str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA1, str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA1, str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA256, str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA256, str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA512, str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md(MBEDTLS_MD_SHA512, str, str_size, out_ptr, mac, mac_size);
}

const int *mbedtls_cipher_list( void );

int luat_crypto_cipher_list(const char** list, size_t* len) {
    size_t count = 0;
    const int *cipher = mbedtls_cipher_list();
    for (size_t i = 0;; i++)
    {
        if (cipher[i] == 0)
            break;
        count ++;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        list[i] = mbedtls_cipher_info_get_name(mbedtls_cipher_info_from_type(cipher[i]));
#else
        list[i] = mbedtls_cipher_info_from_type(cipher[i])->name;
#endif
    }
    *len = count;
    return 0;
}
