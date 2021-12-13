
/*
@module  crypto
@summary 加解密和hash函数
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "crypto"
#include "luat_log.h"

static const unsigned char hexchars[] = "0123456789ABCDEF";
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


/**
计算sha256值
@api crypto.sha256(str)
@string 需要计算的字符串
@return string 计算得出的sha256值的hex字符串
@usage
-- 计算字符串"abc"的sha256
log.info("sha256", crypto.sha256("abc"))
 */
static int l_crypto_sha256(lua_State *L) {
    size_t size = 0;
    const char* str = luaL_checklstring(L, 1, &size);
    char tmp[64] = {0};
    char dst[64] = {0};
    if (luat_crypto_sha256_simple(str, size, tmp) == 0) {
        fixhex(tmp, dst, 32);
        lua_pushlstring(L, dst, 64);
        return 1;
    }
    return 0;
}

/**
计算hmac_sha256值
@api crypto.hmac_sha256(str, key)
@string 需要计算的字符串
@string 密钥
@return string 计算得出的hmac_sha1值的hex字符串
@usage
-- 计算字符串"abc"的hmac_sha256
log.info("hmac_sha256", crypto.hmac_sha256("abc", "1234567890"))
 */
static int l_crypto_hmac_sha256(lua_State *L) {
    size_t str_size = 0;
    size_t key_size = 0;
    const char* str = luaL_checklstring(L, 1, &str_size);
    const char* key = luaL_checklstring(L, 2, &key_size);
    char tmp[64] = {0};
    char dst[64] = {0};
    if (luat_crypto_hmac_sha256_simple(str, str_size, key, key_size, tmp) == 0) {
        fixhex(tmp, dst, 32);
        lua_pushlstring(L, dst, 64);
        return 1;
    }
    return 0;
}

//---

/**
计算sha512值
@api crypto.sha512(str)
@string 需要计算的字符串
@return string 计算得出的sha512值的hex字符串
@usage
-- 计算字符串"abc"的sha512
log.info("sha512", crypto.sha512("abc"))
 */
static int l_crypto_sha512(lua_State *L) {
    size_t size = 0;
    const char* str = luaL_checklstring(L, 1, &size);
    char tmp[128] = {0};
    char dst[128] = {0};
    if (luat_crypto_sha512_simple(str, size, tmp) == 0) {
        fixhex(tmp, dst, 64);
        lua_pushlstring(L, dst, 128);
        return 1;
    }
    return 0;
}

/**
计算hmac_sha512值
@api crypto.hmac_sha512(str, key)
@string 需要计算的字符串
@string 密钥
@return string 计算得出的hmac_sha1值的hex字符串
@usage
-- 计算字符串"abc"的hmac_sha512
log.info("hmac_sha512", crypto.hmac_sha512("abc", "1234567890"))
 */
static int l_crypto_hmac_sha512(lua_State *L) {
    size_t str_size = 0;
    size_t key_size = 0;
    const char* str = luaL_checklstring(L, 1, &str_size);
    const char* key = luaL_checklstring(L, 2, &key_size);
    char tmp[128] = {0};
    char dst[128] = {0};
    if (luat_crypto_hmac_sha512_simple(str, str_size, key, key_size, tmp) == 0) {
        fixhex(tmp, dst, 64);
        lua_pushlstring(L, dst, 128);
        return 1;
    }
    return 0;
}

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags);

/**
对称加密
@api crypto.cipher_encrypt(type, padding, str, key, iv)
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
int l_crypto_cipher_encrypt(lua_State *L) {
    return l_crypto_cipher_xxx(L, 1);
}
/**
对称解密
@api crypto.cipher_decrypt(type, padding, str, key, iv)
@string 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅mbedtls的cipher_wrap.c
@string 对齐方式, 当前仅支持PKCS7
@string 需要解密的数据
@string 密钥,需要对应算法的密钥长度
@string IV值, 非ECB算法需要
@return string 解密后的字符串
@usage
-- 用AES加密,然后用AES解密
local data = crypto.cipher_encrypt("AES-128-ECB", "PKCS7", "1234567890123456", "1234567890123456")
local data2 = crypto.cipher_decrypt("AES-128-ECB", "PKCS7", data, "1234567890123456")
-- data的hex为 757CCD0CDC5C90EADBEEECF638DD0000
-- data2的值为 1234567890123456
 */
int l_crypto_cipher_decrypt(lua_State *L) {
    return l_crypto_cipher_xxx(L, 0);
}

#include "crc.h"

/**
计算CRC16
@api crypto.crc16(method, data, poly, initial, finally, inReversem outReverse)
@string CRC16模式（"IBM","MAXIM","USB","MODBUS","CCITT","CCITT-FALSE","X25","XMODEM","DNP","USER-DEFINED"）
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
    size_t inputLen;
    const char  *inputmethod = (const char*)luaL_checkstring(L, 1);
    const unsigned char *inputData = (const unsigned char*)lua_tolstring(L,2,&inputLen);
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
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);

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
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);

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
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);

    lua_pushinteger(L, calcCRC8(inputData, len));
    return 1;
}

/**
生成真随机数
@api crypto.trng(len)
@int 数据长度
@return string 指定随机数字符串
@usage
-- 生成32位随机数ir
local r = crypto.trng(4)
local _, ir = pack.unpack(r, "I")
 */
static int l_crypto_trng(lua_State *L) {
    int ret = 0;
    size_t len = luaL_checkinteger(L, 1);
    if (len < 1) {
        return 0;
    }
    if (len > 128)
        len = 128;
    char buff[128];
    ret = luat_crypto_trng(buff, len);
    if(ret ==0){
        lua_pushlstring(L, buff, len);
        return 1;
    }
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_crypto[] =
{
    { "md5" ,           l_crypto_md5            ,0},
    { "sha1" ,          l_crypto_sha1           ,0},
    { "sha256" ,        l_crypto_sha256         ,0},
    { "sha512" ,        l_crypto_sha512         ,0},
    { "hmac_md5" ,      l_crypto_hmac_md5       ,0},
    { "hmac_sha1" ,     l_crypto_hmac_sha1      ,0},
    { "hmac_sha256" ,   l_crypto_hmac_sha256    ,0},
    { "hmac_sha512" ,   l_crypto_hmac_sha512    ,0},
    { "cipher" ,        l_crypto_cipher_encrypt ,0},
    { "cipher_encrypt" ,l_crypto_cipher_encrypt ,0},
    { "cipher_decrypt" ,l_crypto_cipher_decrypt ,0},
    { "crc16",          l_crypto_crc16          ,0},
    { "crc16_modbus",   l_crypto_crc16_modbus   ,0},
    { "crc32",          l_crypto_crc32          ,0},
    { "crc8",           l_crypto_crc8           ,0},
    { "trng",           l_crypto_trng           ,0},
	{ NULL,             NULL                    ,0}
};

LUAMOD_API int luaopen_crypto( lua_State *L ) {
    luat_newlib(L, reg_crypto);
    return 1;
}

// 添加几个默认实现

LUAT_WEAK int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr) {return -1;}
LUAT_WEAK int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {return -1;}

LUAT_WEAK int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr) {return -1;}
LUAT_WEAK int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {return -1;}

LUAT_WEAK int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr) {return -1;}
LUAT_WEAK int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {return -1;}

LUAT_WEAK int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) {return -1;}
LUAT_WEAK int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) {return -1;}

LUAT_WEAK int luat_crypto_trng(char* buff, size_t len) {
    memset(buff, 0, len);
    return 0;
}
