/*
@module  rsa
@summary RSA加密解密
@version 1.0
@date    2022.11.03
@demo    rsa
@usage
-- 在电脑上生成私钥和公钥, 当前最高支持4096bit, 一般来说2048bit就够用了
-- openssl genrsa -out privkey.pem 2048
-- openssl rsa -in privkey.pem -pubout -out public.pem
-- privkey.pem 是解码用的, public.pem 是加密用的
-- public.pem 一般放在设备端,上传时加密用, 服务器端使用privkey.pem解密,当然这取决于你的业务需要.

local res = rsa.encrypt((io.readFile("/luadb/public.pem")), "abc")
-- 打印结果
log.info("rsa", "encrypt", res and #res or 0, res and res:toHex() or "")

-- 下面是解密, 通常不会在设备端进行, 这里主要是演示用法, 会很慢
if res then
    -- 读取私钥, 然后解码数据
    local dst = rsa.decrypt((io.readFile("/luadb/privkey.pem")), res, "")
    log.info("rsa", "decrypt", dst and #dst or 0, dst and dst:toHex() or "")
end
*/

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "rs"
#include "luat_log.h"

#include "mbedtls/rsa.h"
#include "mbedtls/pk.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"

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
@api rsa.encrypt(key, data, pwd)
@string 私钥数据,仅支持PEM格式
@string 待解密数据
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

#include "rotable2.h"
static const rotable_Reg_t reg_rsa[] =
{
    { "encrypt" ,        ROREG_FUNC(l_rsa_encrypt)},
    { "decrypt" ,        ROREG_FUNC(l_rsa_decrypt)},
	{ NULL,              ROREG_INT(0) }
};

LUAMOD_API int luaopen_rsa( lua_State *L ) {
    luat_newlib2(L, reg_rsa);
    return 1;
}
