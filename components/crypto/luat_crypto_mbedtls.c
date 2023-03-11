// crypto库的软件实现, 基于mbedtls

#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_malloc.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

#include "mbedtls/cipher.h"
#include "mbedtls/md.h"
#include "mbedtls/ssl_ciphersuites.h"


static void add_pkcs_padding( unsigned char *output, size_t output_len,
        size_t data_len )
{
    size_t padding_len = output_len - data_len;
    unsigned char i;

    for( i = 0; i < padding_len; i++ )
        output[data_len + i] = (unsigned char) padding_len;
}

static int get_pkcs_padding( unsigned char *input, size_t input_len,
        size_t *data_len )
{
    size_t i, pad_idx;
    unsigned char padding_len, bad = 0;

    if( NULL == input || NULL == data_len )
        return( MBEDTLS_ERR_CIPHER_BAD_INPUT_DATA );

    padding_len = input[input_len - 1];
    *data_len = input_len - padding_len;

    /* Avoid logical || since it results in a branch */
    bad |= padding_len > input_len;
    bad |= padding_len == 0;

    /* The number of bytes checked must be independent of padding_len,
     * so pick input_len, which is usually 8 or 16 (one block) */
    pad_idx = input_len - padding_len;
    for( i = 0; i < input_len; i++ )
        bad |= ( input[i] ^ padding_len ) * ( i >= pad_idx );

    return( MBEDTLS_ERR_CIPHER_INVALID_PADDING * ( bad != 0 ) );
}

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
    uint8_t *temp = NULL;
    int ret = 0;

    unsigned char output[32] = {0};
    size_t input_size = 0;
    size_t output_size = 0;
    size_t block_size = 0;

    luaL_Buffer buff;
    luaL_buffinit(L, &buff);

    mbedtls_cipher_context_t ctx;
    mbedtls_cipher_init(&ctx);

    const mbedtls_cipher_info_t * _cipher = mbedtls_cipher_info_from_string(cipher);
    if (_cipher == NULL) {
    	LLOGE("mbedtls_cipher_info fail %s not support", cipher);
        goto _error_exit;
    }


	ret = mbedtls_cipher_setup(&ctx, _cipher);
    if (ret) {
        LLOGE("mbedtls_cipher_setup fail -0x%04x %s", -ret, cipher);
        goto _error_exit;
    }
    ret = mbedtls_cipher_setkey(&ctx, (const unsigned char*)key, key_size * 8, flags & 0x1);
    if (ret) {
        LLOGE("mbedtls_cipher_setkey fail -0x%04x %s", -ret, cipher);
        goto _error_exit;
    }

    if (iv_size) {
        ret = mbedtls_cipher_set_iv(&ctx, (const unsigned char*)iv, iv_size);
        if (ret) {
            LLOGE("mbedtls_cipher_set_iv fail -0x%04x %s", -ret, cipher);
            goto _error_exit;
        }
    }

    mbedtls_cipher_reset(&ctx);

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

    // 开始注入数据
    block_size = mbedtls_cipher_get_block_size(&ctx);

    #if MBEDTLS_VERSION_NUMBER >= 0x03000000
    int cipher_mode = mbedtls_cipher_info_get_mode(_cipher);
    #else
    int cipher_mode = _cipher->mode;
    #endif

    if ((cipher_mode == MBEDTLS_MODE_ECB) && !strcmp("PKCS7", pad) && (flags & 0x1)) {
    	uint32_t new_len  = ((str_size / block_size) + 1) * block_size;
    	temp = luat_heap_malloc(new_len);
    	memcpy(temp, str, str_size);
    	add_pkcs_padding(temp + str_size - str_size % block_size, block_size, str_size % block_size);
    	str_size = new_len;
    	str = (const char*)temp;
    }
    for (size_t i = 0; i < str_size; i+=block_size) {
        input_size = str_size - i;
        if (input_size > block_size) {
            input_size = block_size;
            ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(str+i), input_size, output, &output_size);
        }
        else if ((cipher_mode == MBEDTLS_MODE_ECB) && !strcmp("PKCS7", pad) && !flags)
        {
        	ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(str+i), input_size, output, &output_size);
        	get_pkcs_padding(output, output_size, &output_size);
        }
        else {
        	ret = mbedtls_cipher_update(&ctx, (const unsigned char *)(str+i), input_size, output, &output_size);
        }
        if (ret) {
            LLOGE("mbedtls_cipher_update fail 0x%04X %s", -ret, cipher);
            goto _exit;
        }
        //else LLOGD("mbedtls_cipher_update, output size=%ld", output_size);
        if (output_size > 0) {
            luaL_addlstring(&buff, (const char*)output, output_size);
        }
        output_size = 0;
    }
    output_size = 0;
    ret = mbedtls_cipher_finish(&ctx, (unsigned char *)output, &output_size);
    if (ret) {
        LLOGE("mbedtls_cipher_finish fail 0x%04X %s", -ret, cipher);
        goto _exit;
    }
    //else LLOGD("mbedtls_cipher_finish, output size=%ld", output_size);
    if (output_size > 0)
        luaL_addlstring(&buff, (const char*)output, output_size);

_exit:
	luat_heap_free(temp);
    mbedtls_cipher_free(&ctx);
    luaL_pushresult(&buff);
    return 1;
_error_exit:
	luat_heap_free(temp);
	mbedtls_cipher_free(&ctx);
	return 0;
}

int luat_crypto_md(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
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

int luat_crypto_md_file(const char* md, void* out_ptr, const char* key, size_t key_len, const char* path) {
    const mbedtls_md_info_t * info = mbedtls_md_info_from_string(md);
    if (info == NULL) {
        LLOGI("no such message digest %s", md);
        return -1;
    }
    FILE* fd = luat_fs_fopen(path, "rb");
    if (fd == NULL) {
        LLOGI("no such file %s", path);
        return -1;
    }
    mbedtls_md_context_t ctx;

    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, info, key_len > 0 ? 1 : 0);

    uint8_t buff[512];
    int len = 0;

    if (key_len > 0) {
        mbedtls_md_hmac_starts(&ctx, (const unsigned char*)key, key_len);
    }
    else {
        mbedtls_md_starts(&ctx);
    }

    while (1) {
        len = luat_fs_fread(buff, 1, 512, fd);
        if (len < 1)
            break;
        if (key_len > 0) {
            mbedtls_md_hmac_update(&ctx, buff, len);
        }
        else {
            mbedtls_md_update(&ctx, buff, len);
        }
    }
    luat_fs_fclose(fd);

    int ret = 0;
    if (key_len > 0) {
        ret = mbedtls_md_hmac_finish(&ctx, out_ptr);
    }
    else {
        ret = mbedtls_md_finish(&ctx, out_ptr);
    }
    mbedtls_md_free(&ctx);
    if (ret == 0) {
        return mbedtls_md_get_size(info);
    }
    LLOGI("md finish ret %d", ret);
    return ret;
}

int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("MD5", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("MD5", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA1", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA1", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA256", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA256", str, str_size, out_ptr, mac, mac_size);
}

int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {
    return luat_crypto_md("SHA512", str, str_size, out_ptr, NULL, 0);
}
int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {
    return luat_crypto_md("SHA512", str, str_size, out_ptr, mac, mac_size);
}

const int *mbedtls_cipher_list( void );

int luat_crypto_cipher_list(const char** list, size_t* len) {
    size_t count = 0;
    size_t limit = *len;
    const int *cipher = mbedtls_cipher_list();
    for (size_t i = 0; i < limit; i++)
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

int luat_crypto_cipher_suites(const char** list, size_t* len) {
#if defined(MBEDTLS_SSL_TLS_C) && defined(LUAT_USE_NETWORK)
    size_t count = 0;
    size_t limit = *len;
    const int *suites = mbedtls_ssl_list_ciphersuites();
    const mbedtls_ssl_ciphersuite_t * suite = NULL;
    for (size_t i = 0; i < limit; i++)
    {
        if (suites[i] == 0)
            break;
        suite = mbedtls_ssl_ciphersuite_from_id(suites[i]);
        if (suite == NULL)
            continue;
        count ++;
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
        list[i] = mbedtls_ssl_ciphersuite_get_name(suite);
#else
        list[i] = suite->name;
#endif
    }
    *len = count;
#else
    *len = 0;
#endif
    return 0;
}
