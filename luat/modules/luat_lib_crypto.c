
/*
@module  crypto
@summary 加解密和hash函数
@version 1.0
@date    2020.07.03
@demo crypto
@tag LUAT_USE_CRYPTO
*/
#include "luat_base.h"
#include "luat_crypto.h"
#include "luat_mem.h"
#include "luat_str.h"
#include <time.h>
#include "luat_zbuff.h"
// #include "mbedtls/md.h"

#define LUAT_LOG_TAG "crypto"
#define LUAT_CRYPTO_TYPE "crypto"
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
@return string 计算得出的hmac_sha256值的hex字符串
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

    if (key_size > 64) {
        luat_crypto_sha256_simple(key, key_size, dst);
        key = (const char*)dst;
        key_size = 64;
    }

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
@return string 计算得出的hmac_sha512值的hex字符串
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

    if (key_size > 128) {
        luat_crypto_sha512_simple(key, key_size, dst);
        key = (const char*)dst;
        key_size = 128;
    }

    if (luat_crypto_hmac_sha512_simple(str, str_size, key, key_size, tmp) == 0) {
        fixhex(tmp, dst, 64);
        lua_pushlstring(L, dst, 128);
        return 1;
    }
    return 0;
}

int l_crypto_cipher_xxx(lua_State *L, uint8_t flags) {
    luat_crypto_cipher_ctx_t cctx = {0};
    cctx.cipher = luaL_optlstring(L, 1, "AES-128-ECB", &cctx.cipher_size);
    cctx.pad = luaL_optlstring(L, 2, "PKCS7", &cctx.pad_size);
    cctx.str = luaL_checklstring(L, 3, &cctx.str_size);
    cctx.key = luaL_checklstring(L, 4, &cctx.key_size);
    cctx.iv = luaL_optlstring(L, 5, "", &cctx.iv_size);
    cctx.flags = flags;

    luaL_Buffer buff;
    luaL_buffinitsize(L, &buff, cctx.str_size + 16);
    cctx.outbuff = buff.b;

    int ret = luat_crypto_cipher_xxx(&cctx);
    if (ret) {
        return 0;
    }
    luaL_pushresultsize(&buff, cctx.outlen);
    return 1;
}

/**
对称加密
@api crypto.cipher_encrypt(type, padding, str, key, iv)
@string 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅crypto.cipher_list()
@string 对齐方式, 支持PKCS7/ZERO/ONE_AND_ZEROS/ZEROS_AND_LEN/NONE
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
@string 算法名称, 例如 AES-128-ECB/AES-128-CBC, 可查阅crypto.cipher_list()
@string 对齐方式, 支持PKCS7/ZERO/ONE_AND_ZEROS/ZEROS_AND_LEN/NONE
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
    size_t inputlen;
    const unsigned char *inputData;
    const char  *inputmethod = (const char*)luaL_checkstring(L, 1);
    if(lua_isuserdata(L, 2))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE));
        inputlen = buff->len - buff->cursor;
        inputData = (const unsigned char *)(buff->addr + buff->cursor);
    }else{
        inputData = (const unsigned char*)lua_tolstring(L,2,&inputlen);
    }
    uint16_t poly = luaL_optnumber(L,3,0x0000);
    uint16_t initial = luaL_optnumber(L,4,0x0000);
    uint16_t finally = luaL_optnumber(L,5,0x0000);
    uint8_t inReverse = luaL_optnumber(L,6,0);
    uint8_t outReverse = luaL_optnumber(L,7,0);
    lua_pushinteger(L, calcCRC16(inputData, inputmethod,inputlen,poly,initial,finally,inReverse,outReverse));
    return 1;
}

/**
直接计算modbus的crc16值
@api crypto.crc16_modbus(data, start)
@string 数据
@int 初始化值,默认0xFFFF
@return int 对应的CRC16值
@usage
-- 计算CRC16 modbus
local crc = crypto.crc16_modbus(data)
-- 2023.11.06 新增初始值设置
crc = crypto.crc16_modbus(data, 0xFFFF)
 */
static int l_crypto_crc16_modbus(lua_State *L)
{
    size_t len = 0;
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);
    uint16_t crc_init = luaL_optinteger(L, 2, 0xFFFF);

    lua_pushinteger(L, calcCRC16_modbus(inputData, len, crc_init));
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
@api crypto.crc8(data, poly, start, revert)
@string 数据
@int crc多项式，可选，如果不写，将忽略除了数据外所有参数
@int crc初始值，可选，默认0
@boolean 是否需要逆序处理，默认否
@return int 对应的CRC8值
@usage
-- 计算CRC8
local crc = crypto.crc8(data)
local crc = crypto.crc8(data, 0x31, 0xff, false)
 */
static int l_crypto_crc8(lua_State *L)
{
    size_t len = 0;
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);
    if (!lua_isinteger(L, 2)) {
        lua_pushinteger(L, calcCRC8(inputData, len));
    } else {
    	uint8_t poly = lua_tointeger(L, 2);
    	uint8_t start = luaL_optinteger(L, 3, 0);
    	uint8_t is_rev = 0;
    	if (lua_isboolean(L, 4)) {
    		is_rev = lua_toboolean(L, 4);
    	}
		lua_pushinteger(L, luat_crc8(inputData, len, start, poly, is_rev));
    }
    return 1;
}



static inline unsigned char crc7(const unsigned char* message, int length, unsigned char CRCPoly, unsigned char CRC)
{
    // unsigned char CRCPoly = 0xe5;
    unsigned char CRCTable[256];
    // unsigned char CRC = 0x00;
    for (int i = 0; i < 256; i++){
        CRCTable[i] = (i & 0x80) ? i ^ CRCPoly : i;
        for (int j = 1; j < 8; j++){
            CRCTable[i] <<= 1;
            if (CRCTable[i] & 0x80)
                CRCTable[i] ^= CRCPoly;
        }
    }
    for (int i = 0; i < length; i++)
        CRC = CRCTable[(CRC << 1) ^ message[i]];
    return CRC<< 1;
}

/**
计算crc7值
@api crypto.crc7(data, poly, start)
@string 数据
@int crc多项式，可选，默认0xE5
@int crc初始值，可选，默认0x00
@return int 对应的CRC7值
@usage
-- 计算CRC7, 本API于2023.10.07新增
local crc = crypto.crc7(data)
local crc = crypto.crc7(data, 0x31, 0xff)
 */
static int l_crypto_crc7(lua_State* L) {
    size_t len = 0;
    const unsigned char *inputData = (const unsigned char*)luaL_checklstring(L, 1, &len);
    unsigned char poly = luaL_optinteger(L, 2, 0xe5);
    unsigned char start = luaL_optinteger(L, 3, 0);
    unsigned char result = crc7(inputData, len, poly, start);
    lua_pushinteger(L, result);
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

/**
计算TOTP动态密码的结果
@api crypto.totp(secret,time)
@string 网站提供的密钥（就是BASE32编码后的结果）
@int 可选，时间戳，默认当前时间
@return int 计算得出的六位数结果 计算失败返回nil
@usage
--使用当前系统时间计算
local otp = crypto.totp("asdfassdfasdfass")
 */
static int l_crypto_totp(lua_State *L) {
    size_t len = 0;
    const char* secret_base32 = luaL_checklstring(L,1,&len);

    char * secret = (char *)luat_heap_malloc(len+1);
    len = (size_t)luat_str_base32_decode((const uint8_t * )secret_base32,(uint8_t*)secret,len+1);

    uint64_t t = 0;
    if (lua_isinteger(L, 2)) {
        t = (uint64_t)(luaL_checkinteger(L, 2))/30;
    }
    else {
        t = (uint64_t)(time(NULL)/30);
    }
    uint8_t data[sizeof(uint64_t)] = {0};
    for(size_t i=0;i<sizeof(uint64_t);i++)
        data[sizeof(uint64_t)-1-i] = *(((uint8_t*)&t)+i);
    uint8_t hmac[20] = {0};
    int ret = luat_crypto_hmac_sha1_simple((const char *)data, sizeof(data), (const char *)secret, len, hmac);
    luat_heap_free(secret);
    if(ret == 0)
    {
        uint8_t offset = hmac[19] & 0x0f;
        uint32_t r = (
                        ((uint32_t)((hmac[offset + 0] & 0x7f)) << 24) |
                        ((uint32_t)((hmac[offset + 1] & 0xff)) << 16) |
                        ((uint32_t)((hmac[offset + 2] & 0xff)) << 8) |
                        ((uint32_t)(hmac[offset + 3] & 0xff))
                    ) % 1000000;
        lua_pushinteger(L,r);
        return 1;
    }
    return 0;
}

/**
将数据进行base64编码
@api crypto.base64_encode(data)
@string 待编码的数据
@return string 编码后的数据
@usage
-- 本函数与 string.toBase64 是同一个
local data = "123"
local bdata = crypto.base64_encode(data)
log.info("base64", "encode", data, bdata)
data = crypto.base64_decode(data)
log.info("base64", "decode", data, bdata)
 */
int l_str_toBase64(lua_State *L);

/**
将数据进行base64解码
@api crypto.base64_decode(data)
@string 待解码的数据
@return string 解码后的数据
@usage
-- 本函数与 string.fromBase64 是同一个
local data = "123"
local bdata = crypto.base64_encode(data)
log.info("base64", "encode", data, bdata)
data = crypto.base64_decode(data)
log.info("base64", "decode", data, bdata)
 */
int l_str_fromBase64(lua_State *L);

/**
获取当前固件支持的cipher列表
@api crypto.cipher_list()
@return table 本固件支持的cipher列表,字符串数组
@usage
-- 本API于2022.07.27添加
local ciphers = crypto.cipher_list()
if ciphers then
    log.info("crypto", "ciphers list", json.encode(ciphers))
end
 */
int l_crypto_cipher_list(lua_State *L) {
    const char* list[64] = {0};
    size_t len = 64;
    lua_newtable(L);
    int ret = luat_crypto_cipher_list(list, &len);
    if (ret == 0) {
        for (size_t i = 0; i < len; i++){
            lua_pushstring(L, list[i]);
            lua_seti(L, -2, i + 1);
        }
    }
    else {
        LLOGD("bsp not support cipher_list");
    }
    return 1;
}

/**
获取当前固件支持的cipher suites列表
@api crypto.cipher_suites()
@return table 本固件支持的cipher suites列表,字符串数组
@usage
-- 本API于2022.11.16添加
local suites = crypto.cipher_suites()
if suites then
    log.info("crypto", "ciphers suites", json.encode(suites))
end
 */
int l_crypto_cipher_suites(lua_State *L) {
    const char* list[128] = {0};
    size_t len = 128;
    lua_newtable(L);
    int ret = luat_crypto_cipher_suites(list, &len);
    if (ret == 0) {
        for (size_t i = 0; i < len; i++){
            lua_pushstring(L, list[i]);
            lua_seti(L, -2, i + 1);
        }
    }
    else {
        LLOGD("bsp not support cipher_suites");
    }
    return 1;
}

/**
计算文件的hash值(md5/sha1/sha256及hmac形式)
@api crypto.md_file(tp, path, hmac)
@string hash类型, 大小字母, 例如 "MD5" "SHA1" "SHA256"
@string 文件路径, 例如 /luadb/logo.jpg
@string hmac值,可选
@return string HEX过的hash值,若失败会无返回值
@usage

-- 无hmac的hash值
log.info("md5", crypto.md_file("MD5", "/luadb/logo.jpg"))
log.info("sha1", crypto.md_file("SHA1", "/luadb/logo.jpg"))
log.info("sha256", crypto.md_file("SHA256", "/luadb/logo.jpg"))

-- 带hmac的hash值
log.info("hmac_md5", crypto.md_file("MD5", "/luadb/logo.jpg", "123456"))
log.info("hmac_sha1", crypto.md_file("SHA1", "/luadb/logo.jpg", "123456"))
log.info("hmac_sha256", crypto.md_file("SHA256", "/luadb/logo.jpg", "123456"))
 */
static int l_crypto_md_file(lua_State *L) {
    size_t key_len = 0;
    size_t path_size = 0;
    const char* key = NULL;
    const char *md = luaL_checkstring(L, 1);
    const char* path = luaL_checklstring(L, 2, &path_size);
    if (path_size < 2)
        return 0;
    if (lua_type(L, 3) == LUA_TSTRING) {
        key = luaL_checklstring(L, 3, &key_len);
    }
    char buff[128] = {0};
    char output[64];

    int ret = luat_crypto_md_file(md, output, key, key_len, path);
    if (ret < 1) {
        return 0;
    }

    fixhex(output, buff, ret);
    lua_pushlstring(L, buff, ret *2);
    return 1;
}

/**
计算数据的hash值(md5/sha1/sha256及hmac形式)
@api crypto.md(tp, data, hmac)
@string hash类型, 大小字母, 例如 "MD5" "SHA1" "SHA256"
@string 待处理的数据
@string hmac值,可选
@return string HEX过的hash值,若失败会无返回值
@usage

-- 无hmac的hash值
log.info("md5", crypto.md("MD5", "1234567890"))
log.info("sha1", crypto.md("SHA1", "1234567890"))
log.info("sha256", crypto.md("SHA256", "1234567890"))

-- 带hmac的hash值
log.info("hmac_md5", crypto.md("MD5", "1234567890", "123456"))
log.info("hmac_sha1", crypto.md("SHA1", "1234567890", "123456"))
log.info("hmac_sha256", crypto.md("SHA256", "1234567890", "123456"))
 */
static int l_crypto_md(lua_State *L) {
    size_t key_len = 0;
    size_t data_size = 0;
    const char* key = NULL;
    const char *md = luaL_checkstring(L, 1);
    const char* data = luaL_checklstring(L, 2, &data_size);
    if (lua_type(L, 3) == LUA_TSTRING) {
        key = luaL_checklstring(L, 3, &key_len);
    }
    char buff[128] = {0};
    char output[64];

    int ret = luat_crypto_md(md, data, data_size, output, key, key_len);
    if (ret < 1) {
        return 0;
    }

    fixhex(output, buff, ret);
    lua_pushlstring(L, buff, ret *2);
    return 1;
}

/*
创建流式hash用的stream
@api crypto.hash_init(tp)
@string hash类型, 大写字母, 例如 "MD5" "SHA1" "SHA256"
@string hmac值，可选
@return userdata 成功返回一个数据结构,否则返回nil
@usage
-- 无hmac的hash stream
local md5_stream = crypto.hash_init("MD5")
local sha1_stream = crypto.hash_init("SHA1")
local sha256_stream = crypto.hash_init("SHA256")

-- 带hmac的hash stream
local md5_stream = crypto.hash_init("MD5", "123456")
local sha1_stream = crypto.hash_init("SHA1", "123456")
local sha256_stream = crypto.hash_init("SHA256", "123456")
*/
static int l_crypt_hash_init(lua_State *L) {
    luat_crypt_stream_t *stream = (luat_crypt_stream_t *)lua_newuserdata(L, sizeof(luat_crypt_stream_t));
    if(stream == NULL) {
        return 0;
    } else {
        memset(stream, 0x00, sizeof(luat_crypt_stream_t));
        const char* key = NULL;
        const char* md = luaL_checkstring(L, 1);
        if(lua_type(L, 2) == LUA_TSTRING) {
            key = luaL_checklstring(L, 2, &(stream->key_len));
        }
        int ret = luat_crypto_md_init(md, key, stream);
        if (ret < 0) {
            return 0;
        } else {
            luaL_setmetatable(L, LUAT_CRYPTO_TYPE);
        }
    }
    return 1;
}

/*
流式hash更新数据
@api crypto.hash_update(stream, data)
@userdata crypto.hash_init()创建的stream, 必选
@string 待计算的数据,必选
@return 无
@usage
crypto.hash_update(stream, "OK")
*/
static int l_crypt_hash_update(lua_State *L) {
    luat_crypt_stream_t *stream = (luat_crypt_stream_t *)luaL_checkudata(L, 1, LUAT_CRYPTO_TYPE);
    size_t data_len = 0;
    const char *data = luaL_checklstring(L, 2, &data_len);
    luat_crypto_md_update(data, data_len ,stream);
    return 0;
}

/*
获取流式hash校验值并释放创建的stream
@api crypto.hash_finish(stream)
@userdata crypto.hash_init()创建的stream,必选
@return string 成功返回计算得出的流式hash值的hex字符串，失败无返回
@usage
local hashResult = crypto.hash_finish(stream)
*/
static int l_crypt_hash_finish(lua_State *L) {
    luat_crypt_stream_t *stream = (luat_crypt_stream_t *)luaL_checkudata(L, 1, LUAT_CRYPTO_TYPE);
    char buff[128] = {0};
    char output[64];
    int ret = luat_crypto_md_finish(output, stream);
    //LLOGD("finish result %d", ret);
    if (ret < 1) {
        return 0;
    }
    fixhex(output, buff, ret);
    lua_pushlstring(L, buff, ret * 2);
    return 1;
}


/*
计算checksum校验和
@api crypto.checksum(data, mode)
@string 待计算的数据,必选
@int 模式,累加模式, 0 - 异或, 1 - 累加, 默认为0
@return int checksum值,校验和
@usage
-- 本函数在 2022.12.28 添加
-- 单纯计算checksum值
local ck = crypto.checksum("OK")
log.info("checksum", "ok", string.format("%02X", ck))
-- 第二个参数mode在2023.5.23日添加
*/
static int l_crypt_checksum(lua_State *L) {
    size_t len = 0;
    uint8_t checksum = 0x00;
    uint8_t tmp = 0;
    const char* sentence = luaL_checklstring(L, 1, &len);
    int mode = luaL_optinteger(L, 2, 0);
    // LLOGD("mode %d", mode);
    for (size_t i = 0; i < len; i++)
    {
        tmp = *sentence;
        if (mode == 1) {
            checksum += tmp;
        }
        else {
            checksum ^= tmp;
        }
        // LLOGD("> %02X > %02X", checksum, tmp);
        sentence ++;
    }
    lua_pushinteger(L, checksum);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_crypto[] =
{
    { "md5" ,           ROREG_FUNC(l_crypto_md5            )},
    { "sha1" ,          ROREG_FUNC(l_crypto_sha1           )},
    { "sha256" ,        ROREG_FUNC(l_crypto_sha256         )},
    { "sha512" ,        ROREG_FUNC(l_crypto_sha512         )},
    { "hmac_md5" ,      ROREG_FUNC(l_crypto_hmac_md5       )},
    { "hmac_sha1" ,     ROREG_FUNC(l_crypto_hmac_sha1      )},
    { "hmac_sha256" ,   ROREG_FUNC(l_crypto_hmac_sha256    )},
    { "hmac_sha512" ,   ROREG_FUNC(l_crypto_hmac_sha512    )},
    { "cipher" ,        ROREG_FUNC(l_crypto_cipher_encrypt )},
    { "cipher_encrypt" ,ROREG_FUNC(l_crypto_cipher_encrypt )},
    { "cipher_decrypt" ,ROREG_FUNC(l_crypto_cipher_decrypt )},
    { "cipher_list" ,   ROREG_FUNC(l_crypto_cipher_list     )},
    { "cipher_suites",  ROREG_FUNC(l_crypto_cipher_suites)},
    { "crc16",          ROREG_FUNC(l_crypto_crc16          )},
    { "crc16_modbus",   ROREG_FUNC(l_crypto_crc16_modbus   )},
    { "crc32",          ROREG_FUNC(l_crypto_crc32          )},
    { "crc8",           ROREG_FUNC(l_crypto_crc8           )},
    { "crc7",           ROREG_FUNC(l_crypto_crc7           )},
    { "trng",           ROREG_FUNC(l_crypto_trng           )},
    { "totp",           ROREG_FUNC(l_crypto_totp           )},
    { "base64_encode",  ROREG_FUNC(l_str_toBase64)},
    { "base64_decode",  ROREG_FUNC(l_str_fromBase64)},
    { "md_file",        ROREG_FUNC(l_crypto_md_file)},
    { "md",             ROREG_FUNC(l_crypto_md)},
    { "checksum",       ROREG_FUNC(l_crypt_checksum)},
    { "hash_init",      ROREG_FUNC(l_crypt_hash_init)},
    { "hash_update",    ROREG_FUNC(l_crypt_hash_update)},
    { "hash_finish",    ROREG_FUNC(l_crypt_hash_finish)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_crypto( lua_State *L ) {
    luat_newlib2(L, reg_crypto);
    luaL_newmetatable(L, LUAT_CRYPTO_TYPE);
    lua_pop(L, 1);
    return 1;
}

// 添加几个默认实现
#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int luat_crypto_trng(char* buff, size_t len) {
    memset(buff, 0, len);
    return 0;
}

#endif
