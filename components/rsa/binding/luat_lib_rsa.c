/*
@module  rsa
@summary RSA加密解密
@version 1.0
@date    2022.11.03
@demo    rsa
@tag LUAT_USE_RSA
@usage
-- 请在电脑上生成私钥和公钥, 当前最高支持4096bit, 一般来说2048bit就够用了
-- openssl genrsa -out privkey.pem 2048
-- openssl rsa -in privkey.pem -pubout -out public.pem
-- privkey.pem 是私钥, public.pem 是公钥
-- 私钥用于 加密 和 签名, 通常保密, 放在服务器端
-- 公钥用于 解密 和 验签, 一般可公开,放在设备端

-- 为了演示API使用, 这里把私钥也放在设备上

local res = rsa.encrypt((io.readFile("/luadb/public.pem")), "abc")
-- 打印结果
log.info("rsa", "encrypt", res and #res or 0, res and res:toHex() or "")

-- 下面是解密, 通常不会在设备端进行, 这里主要是演示用法, 会很慢
if res then
    -- 读取私钥, 然后解码数据
    local dst = rsa.decrypt((io.readFile("/luadb/privkey.pem")), res, "")
    log.info("rsa", "decrypt", dst and #dst or 0, dst and dst:toHex() or "")
end

-- 演示签名和验签
local hash = crypto.sha1("1234567890"):fromHex()
-- 签名通常很慢, 通常是服务器做
local sig = rsa.sign((io.readFile("/luadb/privkey.pem")), rsa.MD_SHA1, hash, "")
log.info("rsa", "sign", sig and #sig or 0, sig and sig:toHex() or "")
if sig then
    -- 验签是很快的
    local ret = rsa.verify((io.readFile("/luadb/public.pem")), rsa.MD_SHA1, hash, sig)
    log.info("rsa", "verify", ret)
end
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "rs"
#include "luat_log.h"

#include "mbedtls/rsa.h"
#include "mbedtls/pk.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/md.h"

static int myrand( void *rng_state, unsigned char *output, size_t len ) {
    luat_crypto_trng((char*)output, len);
    return 0;
}

/*
RSA加密
@api rsa.encrypt(key, data)
@string 公钥数据,仅支持PEM格式
@string 待加密数据, 不能超过公钥位数的一半, 例如 2048bit的公钥, 只能加密128字节的数据
@return string 加密成功后的数据,若失败会返回nil
@usage
-- 下面代码中的 "abc" 是待加密数据
local res = rsa.encrypt((io.readFile("/luadb/public.pem")), "abc")
-- 打印结果
log.info("rsa", "encrypt", res and #res or 0, res and res:toHex() or "")
*/
static int l_rsa_encrypt(lua_State* L) {
    int ret = 0;
    size_t ilen = 0;
    size_t keylen = 0;
    size_t olen = 0;
    char buff[1024];
    const char* key = luaL_checklstring(L, 1, &keylen);
    const char* data = luaL_checklstring(L, 2, &ilen);

    mbedtls_pk_context ctx_pk;
    mbedtls_pk_init(&ctx_pk);
    ret = mbedtls_pk_parse_public_key(&ctx_pk, (const unsigned char*)key, keylen + 1);
    if (ret) {
        mbedtls_pk_free(&ctx_pk);
        LLOGW("bad public key %04X", -ret);
        return 0;
    }

    ret = mbedtls_pk_encrypt(&ctx_pk, (const unsigned char*)data, ilen, (unsigned char*)buff, &olen, 1024, myrand, NULL);
    mbedtls_pk_free(&ctx_pk);

    if (ret) {
        LLOGW("mbedtls_rsa_pkcs1_encrypt %04X", -ret);
        return 0;
    }
    lua_pushlstring(L, buff, olen);
    return 1;
}

/*
RSA解密
@api rsa.decrypt(key, data, pwd)
@string 私钥数据,仅支持PEM格式
@string 待解密数据
@string 私钥的密码,可选
@return string 解密成功后的数据,若失败会返回nil
@usage
-- 注意, 解密通常很慢, 建议在服务器端进行
-- res 是待解密的数据
local dst = rsa.decrypt((io.readFile("/luadb/privkey.pem")), res, "")
log.info("rsa", "decrypt", dst and #dst or 0, dst and dst:toHex() or "")
*/
static int l_rsa_decrypt(lua_State* L) {
    int ret = 0;
    size_t ilen = 0;
    size_t keylen = 0;
    size_t rsa_len = 0;
    size_t olen = 0;
    size_t pwdlen = 0;
    char buff[1024];
    const char* key = luaL_checklstring(L, 1, &keylen);
    const char* data = luaL_checklstring(L, 2, &ilen);
    const char* pwd = luaL_optlstring(L, 3, "", &pwdlen);

    mbedtls_pk_context ctx_pk;
    mbedtls_pk_init(&ctx_pk);
    ret = mbedtls_pk_parse_key(&ctx_pk, (const unsigned char*)key, keylen + 1, (const unsigned char*)pwd, pwdlen
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    , myrand, NULL
#endif
    );
    if (ret) {
        mbedtls_pk_free(&ctx_pk);
        LLOGW("bad private key %04X", -ret);
        return 0;
    }
    rsa_len = (mbedtls_pk_get_bitlen(&ctx_pk) + 7 ) / 8;
    if (rsa_len != ilen) {
        mbedtls_pk_free(&ctx_pk);
        LLOGW("data len NOT match expect %d but %d", rsa_len, ilen);
        return 0;
    }
    ret = mbedtls_pk_decrypt(&ctx_pk, (const unsigned char*)data, ilen, (unsigned char*)buff, &olen, 1024, myrand, NULL);
    mbedtls_pk_free(&ctx_pk);

    if (ret) {
        LLOGW("mbedtls_rsa_pkcs1_decrypt %04X", -ret);
        return 0;
    }
    lua_pushlstring(L, buff, olen);
    return 1;
}

/*
RSA验签
@api rsa.verify(key, md, hash, sig)
@string 公钥数据,仅支持PEM格式
@int    签名模式, 例如 rsa.MD_SHA1 , rsa.MD_SHA256
@string hash数据, 如果是HEX字符串,记得fromHex转二进制数据
@string sig数据, 如果是HEX字符串,记得fromHex转二进制数据
@return bool 有效返回true,否则为false,出错返回nil
@usage
local ret = rsa.verify((io.readFile("/luadb/public.pem")), rsa.MD_SHA1, hash, sig)
log.info("rsa", "verify", ret)
*/
static int l_rsa_verify(lua_State* L) {
    int ret = 0;
    size_t hash_len = 0;
    size_t sig_len = 0;
    size_t keylen = 0;

    const char* key =  luaL_checklstring(L,  1, &keylen);
    mbedtls_md_type_t md = luaL_checkinteger(L, 2);
    const char* hash = luaL_checklstring(L, 3, &hash_len);
    const char* sig =  luaL_checklstring(L,  4, &sig_len);

    mbedtls_pk_context ctx_pk;
    mbedtls_pk_init(&ctx_pk);
    ret = mbedtls_pk_parse_public_key(&ctx_pk, (const unsigned char*)key, keylen + 1);
    if (ret) {
        mbedtls_pk_free(&ctx_pk);
        LLOGW("bad public key %04X", -ret);
        return 0;
    }

    ret = mbedtls_pk_verify(&ctx_pk, md, (const unsigned char*)hash, hash_len, (const unsigned char*)sig, sig_len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}


/*
RSA签名
@api rsa.sign(key, md, hash, pwd)
@string 私钥数据,仅支持PEM格式
@int    签名模式, 例如 rsa.MD_SHA1 , rsa.MD_SHA256
@string hash数据, 如果是HEX字符串,记得fromHex转二进制数据
@string 私钥密码, 可选
@return string 成功返回sig数据, 否则返回nil
@usage
local sig = rsa.sign((io.readFile("/luadb/privkey.pem")), rsa.MD_SHA1, hash, "")
log.info("rsa", "sign", sig and #sig or 0, sig and sig:toHex() or "")
*/
static int l_rsa_sign(lua_State* L) {
    int ret = 0;
    size_t pwdlen = 0;
    size_t hash_len = 0;
    size_t sig_len = 0;
    size_t keylen = 0;

    char sig[MBEDTLS_PK_SIGNATURE_MAX_SIZE] = {0};

    const char* key =  luaL_checklstring(L,  1, &keylen);
    mbedtls_md_type_t md = luaL_checkinteger(L, 2);
    const char* hash = luaL_checklstring(L, 3, &hash_len);
    const char* pwd = luaL_optlstring(L, 4, "", &pwdlen);

    mbedtls_pk_context ctx_pk;
    mbedtls_pk_init(&ctx_pk);
    ret = mbedtls_pk_parse_key(&ctx_pk, (const unsigned char*)key, keylen + 1, (const unsigned char*)pwd, pwdlen
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    , myrand, NULL
#endif
    );
    if (ret) {
        mbedtls_pk_free(&ctx_pk);
        LLOGW("bad private key %04X", -ret);
        return 0;
    }
    ret = mbedtls_pk_sign(&ctx_pk, md, (const unsigned char*)hash, hash_len, (unsigned char*)sig, 
#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    MBEDTLS_PK_SIGNATURE_MAX_SIZE,
#endif 
    &sig_len, myrand, NULL);
    mbedtls_pk_free(&ctx_pk);

    if (ret) {
        LLOGW("mbedtls_pk_sign %04X", -ret);
        return 0;
    }
    lua_pushlstring(L, sig, sig_len);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_rsa[] =
{
    { "encrypt" ,        ROREG_FUNC(l_rsa_encrypt)},
    { "decrypt" ,        ROREG_FUNC(l_rsa_decrypt)},

    { "verify",          ROREG_FUNC(l_rsa_verify)},
    { "sign",            ROREG_FUNC(l_rsa_sign)},

    //@const MD_MD5 MD5模式,用于签名和验签
    { "MD_MD5",          ROREG_INT(MBEDTLS_MD_MD5)},
    //@const MD_SHA1 SHA1模式,用于签名和验签
    { "MD_SHA1",         ROREG_INT(MBEDTLS_MD_SHA1)},
    //@const MD_SHA224 SHA224模式,用于签名和验签
    { "MD_SHA224",       ROREG_INT(MBEDTLS_MD_SHA224)},
    //@const MD_SHA256 SHA256模式,用于签名和验签
    { "MD_SHA256",       ROREG_INT(MBEDTLS_MD_SHA256)},
	{ NULL,              ROREG_INT(0) }
};

LUAMOD_API int luaopen_rsa( lua_State *L ) {
    luat_newlib2(L, reg_rsa);
    return 1;
}
