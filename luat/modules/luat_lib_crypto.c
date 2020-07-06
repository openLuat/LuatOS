
/*
@module  crypto
@summary 加解密和hash函数
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_crypto.h"

static unsigned char hexchars[] = "0123456789ABCDEF";
static void fixhex(const char* source, char* dst, size_t len) {
    for (size_t i = 0; i < len; i++)
    {
        char ch = *(source+i);
        dst[i*2] = hexchars[(unsigned char)ch >> 4];
        dst[i*2+1] = hexchars[(unsigned char)ch & 0xF];
    }
}

/**
计算md5值
@function crypto.md5(str)
@string 需要计算的字符串
@return string 计算得出的md5值的hex字符串
@usage
-- 计算字符串"abc"的md5
log.info("md5", crypto.md5("abc"))
 */
static int l_crypto_md5(lua_State *L) {
    size_t size = 0;
    const char* str = luaL_checklstring(L, 1, &size);
    char tmp[32] = {0};
    char dst[32] = {0};
    if (luat_crypto_md5_simple(str, size, tmp) == 0) {
        fixhex(tmp, dst, 16);
        lua_pushlstring(L, dst, 32);
        return 1;
    }
    return 0;
}

/**
计算hmac_md5值
@function crypto.hmac_md5(str, key)
@string 需要计算的字符串
@string 密钥
@return string 计算得出的hmac_md5值的hex字符串
@usage
-- 计算字符串"abc"的hmac_md5
log.info("hmac_md5", crypto.hmac_md5("abc", "1234567890"))
 */
static int l_crypto_hmac_md5(lua_State *L) {
    size_t str_size = 0;
    size_t key_size = 0;
    const char* str = luaL_checklstring(L, 1, &str_size);
    const char* key = luaL_checklstring(L, 2, &key_size);
    char tmp[32] = {0};
    char dst[32] = {0};
    if (luat_crypto_hmac_md5_simple(str, str_size, key, key_size, tmp) == 0) {
        fixhex(tmp, dst, 16);
        lua_pushlstring(L, dst, 32);
        return 1;
    }
    return 0;
}

/**
计算sha1值
@function crypto.sha1(str)
@string 需要计算的字符串
@return string 计算得出的sha1值的hex字符串
@usage
-- 计算字符串"abc"的sha1
log.info("sha1", crypto.sha1("abc"))
 */
static int l_crypto_sha1(lua_State *L) {
    size_t size = 0;
    const char* str = luaL_checklstring(L, 1, &size);
    char tmp[40] = {0};
    char dst[40] = {0};
    if (luat_crypto_sha1_simple(str, size, tmp) == 0) {
        fixhex(tmp, dst, 20);
        lua_pushlstring(L, dst, 40);
        return 1;
    }
    return 0;
}

/**
计算hmac_sha1值
@function crypto.hmac_sha1(str, key)
@string 需要计算的字符串
@string 密钥
@return string 计算得出的hmac_sha1值的hex字符串
@usage
-- 计算字符串"abc"的hmac_sha1
log.info("hmac_sha1", crypto.hmac_sha1("abc", "1234567890"))
 */
static int l_crypto_hmac_sha1(lua_State *L) {
    size_t str_size = 0;
    size_t key_size = 0;
    const char* str = luaL_checklstring(L, 1, &str_size);
    const char* key = luaL_checklstring(L, 2, &key_size);
    char tmp[40] = {0};
    char dst[40] = {0};
    if (luat_crypto_hmac_sha1_simple(str, str_size, key, key_size, tmp) == 0) {
        fixhex(tmp, dst, 20);
        lua_pushlstring(L, dst, 40);
        return 1;
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_crypto[] =
{
    { "md5" ,           l_crypto_md5        ,0},
    { "hmac_md5" ,      l_crypto_hmac_md5   ,0},
    { "sha1" ,          l_crypto_sha1       ,0},
    { "hmac_sha1" ,     l_crypto_hmac_sha1  ,0},
	{ NULL,             NULL                ,0}
};

LUAMOD_API int luaopen_crypto( lua_State *L ) {
    rotable_newlib(L, reg_crypto);
    return 1;
}
