
/*
@module  crypto
@summary 加解密和hash函数
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "luat.crypto"
#include "luat_log.h"

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
@api crypto.md5(str)
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
@api crypto.hmac_md5(str, key)
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
@api crypto.sha1(str)
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
@api crypto.hmac_sha1(str, key)
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

#if defined(FEATURE_MBEDTLS_ENABLE)
#include "cipher.h"
/**
对称加密
@api crypto.cipher(type, padding, str, key, iv)
@string 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅mbedtls的cipher_wrap.c
@string 对齐方式, 当前仅支持PKCS7
@string 需要加密的数据
@string 密钥,需要对应算法的密钥长度
@string IV值, 非ECB算法需要
@return string 加密后的字符串
@usage
-- 计算AES
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_encrypt("AES-128-CBC", "PKCS7", "1234567890123456", "1234567890123456", "1234567890666666")
 */
static int l_crypto_cipher(lua_State *L) {
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

    const mbedtls_cipher_info_t * _cipher = mbedtls_cipher_info_from_string(cipher);
    if (_cipher == NULL) {
        lua_pushstring(L, "bad cipher name");
        lua_error(L);
        return 0;
    }

    int ret = 0;

    mbedtls_cipher_context_t ctx;
    mbedtls_cipher_init(&ctx);

	ret = mbedtls_cipher_setup(&ctx, _cipher);
    if (ret) LLOGE("mbedtls_cipher_setup fail %ld", ret);
    ret = mbedtls_cipher_setkey(&ctx, key, key_size * 8, MBEDTLS_ENCRYPT);
    if (ret) LLOGE("mbedtls_cipher_setkey fail %ld", ret);
    // TODO 设置padding mode
    // mbedtls_cipher_set_padding_mode
    if (iv_size) {
        ret = mbedtls_cipher_set_iv(&ctx, iv, iv_size);
        if (ret) LLOGE("mbedtls_cipher_set_iv fail %ld", ret);
    }

    mbedtls_cipher_reset(&ctx);

    //mbedtls_cipher_set_padding_mode(&ctx, MBEDTLS_PADDING_PKCS7);

    // 开始注入数据
    luaL_Buffer buff;
    luaL_buffinit(L, &buff);

    unsigned char output[32] = {0};
    size_t input_size = 0;
    size_t output_size = 0;
    size_t block_size = mbedtls_cipher_get_block_size(&ctx);
    for (size_t i = 0; i < str_size; i+=block_size) {
        input_size = str_size - i;
        if (input_size > block_size)
            input_size = block_size;
        ret = mbedtls_cipher_update(&ctx, str+i, input_size, output, &output_size);
        if (ret) LLOGE("mbedtls_cipher_update fail %ld", ret);
        //else LLOGD("mbedtls_cipher_update, output size=%ld", output_size);
        if (output_size > 0)
            luaL_addlstring(&buff, output, output_size);
        output_size = 0;
    }
    ret = mbedtls_cipher_finish(&ctx, output, &output_size);
    if (ret) LLOGE("mbedtls_cipher_finish fail %ld", ret);
    //else LLOGD("mbedtls_cipher_finish, output size=%ld", output_size);
    if (output_size > 0)
        luaL_addlstring(&buff, output, output_size);

    luaL_pushresult(&buff);
    return 1;
}
#endif

#include "crc.h"

/**
计算CRC16
@api crypto.crc16(method, data, poly, initial, finally, inReversem outReverse)
@string 输入模式
@string 字符串
@int poly值
@int initial值
@int finally值
@int 输入反转,1反转,默认0不反转
@int 输入反转,1反转,默认0不反转
@return int 对应的CRC16值
@usage
-- 计算CRC16
local crc = crypto.crc16("")
 */
static int l_crypto_crc16(lua_State *L)
{   
    int inputLen;
    const char  *inputmethod = luaL_checkstring(L, 1);
    const char *inputData = lua_tolstring(L,2,&inputLen);
    uint16_t poly = luaL_optnumber(L,3,0x0000);
    uint16_t initial = luaL_optnumber(L,4,0x0000);
    uint16_t finally = luaL_optnumber(L,5,0x0000);
    uint8_t inReverse = luaL_optnumber(L,6,0);
    uint8_t outReverse = luaL_optnumber(L,7,0);
   
    lua_pushinteger(L, calcCRC16(inputData, inputmethod,inputLen,poly,initial,finally,inReverse,outReverse));
    return 1;
}

/**
直接计算modbus的crc16值
@api crypto.crc16_modbus(data)
@string 数据
@return int 对应的CRC16值
@usage
-- 计算CRC16 modbus
local crc = crypto.crc16_modbus(data)
 */
static int l_crypto_crc16_modbus(lua_State *L)
{
    size_t len = 0;
    const char *inputData = luaL_checklstring(L, 1, &len);

    lua_pushinteger(L, calcCRC16_modbus(inputData, len));
    return 1;
}

/**
计算crc32值
@api crypto.crc32(data)
@string 数据
@return int 对应的CRC32值
@usage
-- 计算CRC32
local crc = crypto.crc32(data)
 */
static int l_crypto_crc32(lua_State *L)
{
    size_t len = 0;
    const char *inputData = luaL_checklstring(L, 1, &len);

    lua_pushinteger(L, calcCRC32(inputData, len));
    return 1;
}

/**
计算crc8值
@api crypto.crc8(data)
@string 数据
@return int 对应的CRC8值
@usage
-- 计算CRC8
local crc = crypto.crc8(data)
 */
static int l_crypto_crc8(lua_State *L)
{
    size_t len = 0;
    const char *inputData = luaL_checklstring(L, 1, &len);

    lua_pushinteger(L, calcCRC8(inputData, len));
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_crypto[] =
{
    { "md5" ,           l_crypto_md5            ,0},
    { "hmac_md5" ,      l_crypto_hmac_md5       ,0},
    { "sha1" ,          l_crypto_sha1           ,0},
    { "hmac_sha1" ,     l_crypto_hmac_sha1      ,0},
#if defined(FEATURE_MBEDTLS_ENABLE)
    { "cipher" ,        l_crypto_cipher         ,0},
#endif
    { "crc16",          l_crypto_crc16          ,0},
    { "crc16_modbus",   l_crypto_crc16_modbus   ,0},
    { "crc32",          l_crypto_crc32          ,0},
    { "crc8",           l_crypto_crc8           ,0},
	{ NULL,             NULL                    ,0}
};

LUAMOD_API int luaopen_crypto( lua_State *L ) {
    rotable_newlib(L, reg_crypto);
    return 1;
}
