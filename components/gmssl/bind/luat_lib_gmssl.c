
/*
@module  gmssl
@summary 国密算法(SM2/SM3/SM4)
@version 1.1
@date    2023.03.02
@author  chenxudong1208
@demo gmssl
@tag LUAT_USE_GMSSL
@usage
-- 本库 支持 SM2 SM3 SM4 三个算法
-- 理论上可以扩展支持 SM9 算法
-- 不支持SM1, 因为那是硬件算法, 没有软件实现的
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_str.h"
#include <time.h>
#include "luat_zbuff.h"
#include "gmssl/sm2.h"
#include "gmssl/sm3.h"
#include "gmssl/sm4.h"
#include "luat_str.h"
// #include "mbedtls/hmac_drbg.h"

#define LUAT_LOG_TAG "sm"
#include "luat_log.h"
#define SM3_DIGEST_LENGTH    32
#define SM4_BLOCK_LEN 16
#define SM2_STR_LEN 300
#define HEX_CODE 16

static void DeletePaddingBuf(luaL_Buffer *B, const char *pPadding, size_t nBufLen, uint8_t *pBuf, uint8_t pPaddLen)
{
    uint8_t nPadLen;
    if((strcmp(pPadding, "PKCS5")==0) || (strcmp(pPadding, "PKCS7")==0))
    {
        nPadLen = *(pBuf+nBufLen-1);
        //printf("aes DeletePaddingBuf length=%d\n", nPadLen);
        if((pPaddLen-nPadLen) >= 0)
        {
            luaL_addlstring(B, (char*)pBuf, nBufLen-nPadLen);
        }
    }
    else if(strcmp(pPadding, "ZERO")==0)
    {                        
        uint8_t *pEnd = pBuf+nBufLen-1;
        nPadLen = 0;
        while(1)
        {
            if(*pEnd == 0)
            {
                nPadLen++;
                if(nPadLen == pPaddLen)
                {
                    break;
                }
                pEnd--;
            }
            else
            {
                break;
            }
        }
        //printf("aes DeletePaddingBuf length=%d\n", nPadLen);
        if((pPaddLen-nPadLen) >= 0)
        {
            luaL_addlstring(B, (char*)pBuf, nBufLen-nPadLen);
        }
    }
    else
    {
        luaL_addlstring(B, (char*)pBuf, nBufLen);
    }
}


/*
sm2算法加密
@api sm.sm2encrypt(pkx,pky,data, mode, mode2)
@string 公钥x,必选. HEX字符串
@string 公钥y,必选. HEX字符串
@string 待计算的数据,必选,最长32字节, 非HEX字符串
@boolean 输出模式,默认false. false-GMSSL默认格式DER, true-网站兼容模式
@boolean 标准版本,默认false. false-C1C3C2新国际, true-C1C2C3老国际. 仅"网站兼容模式"时有效
@return string 加密后的字符串, 原样输出,未经HEX转换. 若加密失败会返回nil或空字符串
@usage
-- 提示 mode/mode2 参数是 2023.10.17 新增
-- 由于SM2在各平台的实现都有差异,用法务必参考demo
*/
static int l_sm2_encrypt(lua_State *L)
{    
    // size_t randLen = 0;
    size_t pkxLen = 0;
    size_t pkyLen = 0;
    size_t pBufLen = 0;
    const char *pkx = lua_tolstring(L, 1,&pkxLen);
    const char *pky = lua_tolstring(L, 2,&pkyLen);
    const char *pBuf = lua_tolstring(L, 3,&pBufLen);
    int ret = 0;

    //检查参数合法性
    if((pkxLen!=64))
    {
        LLOGE("invalid pkx password length=%d", pkxLen);
        return 0;
    }
    if((pkyLen!=64))
    {
        LLOGE("invalid pky password length=%d", pkyLen);
        return 0;
    }
    if (pBufLen > SM2_MAX_PLAINTEXT_SIZE) {
        LLOGD("data too large max %d but %d", SM2_MAX_PLAINTEXT_SIZE, pBufLen);
        return 0;
    }

    int mode = 0;
    if (lua_isboolean(L, 4)) {
        mode = lua_toboolean(L, 4);
    }
    int mode2 = 0;
    if (lua_isboolean(L, 5)) {
        mode2 = lua_toboolean(L, 5);
    }

    SM2_KEY sm2 = {0};
    SM2_POINT point = {0};
    luat_str_fromhex(pkx, 64, (char*)point.x);
    luat_str_fromhex(pky, 64, (char*)point.y);
    ret = sm2_key_set_public_key(&sm2, (const SM2_POINT*)&point);
    if (ret != 1) {
        LLOGD("sm2_key_set_public_key %d", ret);
        return 0;
    }

    uint8_t out[SM2_MAX_CIPHERTEXT_SIZE] = {0};
    size_t olen = 0;
    if (mode == 1) {
        SM2_CIPHERTEXT C = {0};
        ret = sm2_do_encrypt(&sm2, (const uint8_t *)pBuf, pBufLen, &C);
        if (ret == 1) {
            if (mode2 == 0) {
                memcpy(out, &C.point.x, 32);
                memcpy(out + 32, &C.point.y, 32);
                memcpy(out + 64, C.hash, 32);
                memcpy(out + 96, C.ciphertext, C.ciphertext_size);
                olen = 96 + C.ciphertext_size;
            }
            else {
                out[0] = 0x04;
                memcpy(out + 1, &C.point.x, 32);
                memcpy(out + 32 + 1, &C.point.y, 32);
                memcpy(out + 64 + 1, C.ciphertext, C.ciphertext_size);
                memcpy(out + 64 + C.ciphertext_size + 1, C.hash, 32);
                olen = 96 + C.ciphertext_size + 1;
            }
        }
    }
    else {
        ret = sm2_encrypt(&sm2, (const uint8_t *)pBuf, pBufLen, out, &olen);
    }
    if (ret != 1) {
        LLOGD("sm2_encrypt ret %d", ret);
        return 0;
    }
    lua_pushlstring(L, (char*)out, olen);
    return 1;
}

/*
sm2算法解密
@api sm.sm2decrypt(private,data,mode,mode2)
@string 私钥,必选,HEX字符串
@string 待计算的数据,必选,原始数据,非HEX字符串
@boolean 输出模式,默认false. false-GMSSL默认格式DER, true-网站兼容模式
@boolean 标准版本,默认false. false-C1C3C2新国际, true-C1C2C3老国际
@return string 解密后的字符串,未经HEX转换.若解密失败会返回nil或空字符串
@usage
-- 提示 mode/mode2 参数是 2023.10.17 新增
-- 由于SM2在各平台的实现都有差异,用法务必参考demo
*/
static int l_sm2_decrypt(lua_State *L)
{    
    size_t privateLen = 0;
    size_t pBufLen = 0;
    const char *private = lua_tolstring(L, 1,&privateLen);
    const char *pBuf = lua_tolstring(L, 2,&pBufLen);
    int ret = 0;

    int mode = 0;
    if (lua_isboolean(L, 3)) {
        mode = lua_toboolean(L, 3);
    }
    int mode2 = 0;
    if (lua_isboolean(L, 4)) {
        mode2 = lua_toboolean(L, 4);
    }


    //检查参数合法性
    if((privateLen!=64))
    {
        LLOGE("invalid private password length=%d", privateLen);
        return 0;
    }
    if (pBufLen < 97) {
        LLOGE("待数据太短,应该要97字节以上");
        return 0;
    }
    
    SM2_KEY sm2 = {0};
    char out[512] = {0};
    size_t olen = 0;
    luat_str_fromhex(private, 64, (char*)sm2.private_key);

    if (mode) {
        // LLOGD("网站兼容模式");
        SM2_CIPHERTEXT C = {0};
        if (mode2 == 0) {
            // LLOGD("C1C3C2");
            C.ciphertext_size = (uint8_t)(pBufLen - 96);
            // LLOGD("pBufLen %d ciphertext_size %d", pBufLen, C.ciphertext_size);
            memcpy(&C.point.x, pBuf, 32);
            memcpy(&C.point.y, pBuf + 32, 32);
            memcpy(C.hash, pBuf + 64, 32);
            memcpy(C.ciphertext, pBuf + 96, C.ciphertext_size);
        }
        else {
            // LLOGD("C1C2C3");
            pBuf ++;
            pBufLen --;
            C.ciphertext_size = (uint8_t)(pBufLen - 96);
            // LLOGD("pBufLen %d ciphertext_size %d", pBufLen, C.ciphertext_size);
            memcpy(&C.point.x, pBuf, 32);
            memcpy(&C.point.y, pBuf + 32, 32);
            memcpy(C.ciphertext, pBuf + 64, C.ciphertext_size);
            memcpy(C.hash, pBuf + 64 + C.ciphertext_size, 32);
        }
        ret = sm2_do_decrypt(&sm2, &C, (uint8_t *)out, &olen);
    }
    else {
        // LLOGD("GMSSL默认模式");
        ret = sm2_decrypt(&sm2, (uint8_t*)pBuf, pBufLen, (uint8_t*)out, &olen);
    }
    if (ret != 1) {
        LLOGD("sm2_decrypt ret %d", ret);
        return 0;
    }
    lua_pushlstring(L, (char*)out, olen);
    return 1;
}


/*
sm3算法,算HASH值
@api sm.sm3(data)
@string 待计算的数据,必选
@return string 对应的hash值
@usage
local encodeStr = gmssl.sm3("lqlq666lqlq946")
log.info("testsm.sm3update",string.toHex(encodeStr))
*/
static int l_sm3_update(lua_State *L)
{
    size_t inputLen = 0;
    uint8_t dgst[SM3_DIGEST_LENGTH];
    const char *inputData = lua_tolstring(L,1,&inputLen);
    sm3_digest((uint8_t*)inputData, inputLen, dgst);

    lua_pushlstring(L, (char*)dgst, SM3_DIGEST_LENGTH);   
    return 1;
}


/*
sm3算法,算HASH值,但带HMAC
@api sm.sm3hmac(data, key)
@string 待计算的数据,必选
@string 密钥
@return string 对应的hash值
@usage
local encodeStr = gmssl.sm3hmac("lqlq666lqlq946", "123")
log.info("testsm.sm3update",string.toHex(encodeStr))
*/
static int l_sm3hmac_update(lua_State *L)
{
    size_t inputLen = 0;
    size_t keyLen = 0;
    uint8_t dgst[SM3_DIGEST_LENGTH];
    const char *inputData = lua_tolstring(L, 1, &inputLen);
    const char *keyData = lua_tolstring(L, 2, &keyLen);
    sm3_hmac((uint8_t*)keyData, keyLen, (uint8_t*)inputData, inputLen, dgst);

    lua_pushlstring(L, (char*)dgst, SM3_DIGEST_LENGTH);   
    return 1;
}

/*
SM4加密算法
@api gmssl.sm4encrypt(mode,padding,originStr,password)
@string  加密模式, CBC或ECB   
@string  填充方式, NONE/ZERO/PKCS5/PKCS7
@string  加密的字符串
@string  密钥
@string  偏移量
@return string 加密后的数据
@usage
local originStr = "SM4 ECB ZeroPadding test"
--加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；密钥长度：128 bit
local encodeStr = gmssl.sm4encrypt("ECB","ZERO",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("ECB","ZERO",encodeStr,"1234567890123456"))

originStr = "SM4 ECB Pkcs5Padding test"
--加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit
encodeStr = gmssl.sm4encrypt("ECB","PKCS5",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("ECB","PKCS5",encodeStr,"1234567890123456"))

originStr = "SM4 CBC Pkcs5Padding test"
--加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：256 bit；偏移量：1234567890666666
encodeStr = gmssl.sm4encrypt("CBC","PKCS5",originStr,"1234567890123456","1234567890666666")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("CBC","PKCS5",encodeStr,"1234567890123456","1234567890666666"))
*/
static int l_sm4_encrypt(lua_State *L)
{    
    const char *pMode = luaL_checkstring(L, 1);
    const char *pPadding = luaL_checkstring(L, 2);
    size_t nBufLen = 0;
    const char *pBuf = lua_tolstring(L, 3, &nBufLen);
    size_t nPswdLen = 0;
    const char *pPassword = lua_tolstring(L, 4, &nPswdLen);
    size_t nIVLen = 0;
    const char *pIV =  lua_tolstring(L, 5, &nIVLen);

    int nPadLen = SM4_BLOCK_LEN-(nBufLen%SM4_BLOCK_LEN);
    uint8_t pPadBuf[SM4_BLOCK_LEN] = {0};
    uint8_t *pInBuf = NULL;
	
    //检查参数合法性
    if((nPswdLen!=16))
    {
        return luaL_error(L, "invalid password length=%d, only support 128bit Password", nPswdLen);
    }
    if((strcmp(pMode, "ECB")!=0) && (strcmp(pMode, "CBC")!=0))
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC", pMode);
    }
    if((strcmp(pPadding, "NONE")!=0) && (strcmp(pPadding, "PKCS5")!=0) && (strcmp(pPadding, "PKCS7")!=0) && (strcmp((char*)pPadding, "ZERO")!=0))
    {
        return luaL_error(L, "invalid padding=%s, only support NONE,PKCS5,PKCS7,ZERO", pPadding);
    }
    if(((strcmp(pMode, "CBC")==0)) && (nIVLen!=16))
    {
        return luaL_error(L, "invalid iv length=%d, only support 128bit IV", nIVLen);
    }

    //构造填充数据
    if((strcmp(pPadding, "PKCS5")==0) || (strcmp(pPadding, "PKCS7")==0))
    {
        memset(pPadBuf, nPadLen, sizeof(pPadBuf));
    }
    else if(strcmp(pPadding, "ZERO")==0)
    {
        memset(pPadBuf, 0, sizeof(pPadBuf));
    }   
	else if(strcmp(pPadding, "NONE")==0)
    {
    	if((strcmp(pMode, "CBC")==0) || (strcmp(pMode, "ECB")==0)){
	        if(nBufLen%SM4_BLOCK_LEN != 0)
	        {
	            return luaL_error(L, "buf len should be multiple of 16, len=%d", nBufLen);
	        }
        }
        nPadLen = 0;
    }

    //加密
    {       
        luaL_Buffer b;
        uint32_t nRmnLen;
        luaL_buffinit( L, &b );

         //原始数据和填充数据拼接在一起
        if (strcmp((char*)pPadding, "NONE")!=0)
        {
            pInBuf = luat_heap_malloc(nBufLen+nPadLen);
            if(pInBuf == NULL)
            {
                //LLOGD("aes_encrypt malloc error!!!\n");
                luaL_pushresult( &b );
                return 1;
            }
            memcpy(pInBuf, pBuf, nBufLen);
            memcpy(pInBuf+nBufLen, pPadBuf, nPadLen); 
            nBufLen += nPadLen;
            nRmnLen = nBufLen;
        }
        else
        {
            pInBuf =  luat_heap_malloc(nBufLen);
			nRmnLen = nBufLen;
            if(pInBuf == NULL)
            {
                //LLOGD("aes_encrypt malloc error!!!\n");
                luaL_pushresult( &b );
                return 1;
            }
            memcpy(pInBuf, pBuf, nBufLen);
        }

		SM4_KEY sm4_key;
        memset(&sm4_key,0,sizeof(SM4_KEY));
		sm4_set_encrypt_key(&sm4_key, (uint8_t*)pPassword);

        if(strcmp(pMode, "ECB") == 0)
        {
            //开始分组加密，每16字节一组
            char out[SM4_BLOCK_LEN];
            while(nRmnLen>0)
            {
                sm4_encrypt(&sm4_key, (uint8_t*)(pInBuf+nBufLen-nRmnLen), (uint8_t*)out);
                luaL_addlstring(&b, out, SM4_BLOCK_LEN);
                nRmnLen -= SM4_BLOCK_LEN;
            }
        }
        else if((strcmp(pMode, "CBC") == 0))
        {
            //待加密数据一次性传入
            // sm4_cbc_encrypt(pInBuf,pInBuf,nBufLen,&sm4_key,pIV,1);
            char *out = luat_heap_malloc(nBufLen);
            sm4_cbc_encrypt(&sm4_key, (uint8_t*)pIV, pInBuf, nBufLen / SM4_BLOCK_LEN, (uint8_t*)out);
            luaL_addlstring(&b, out, nBufLen);
            luat_heap_free(out);
        }

        if(pInBuf != NULL)
        {
            luat_heap_free(pInBuf);
            pInBuf = NULL;
        }

        luaL_pushresult( &b );
        return 1;
    }   
}


/*
SM4解密算法
@api gmssl.sm4decrypt(mode,padding,encodeStr,password)
@string  加密模式, CBC或ECB   
@string  填充方式, NONE/ZERO/PKCS5/PKCS7
@string  已加密的字符串
@string  密钥
@string  偏移量
@return string 解密的字符串
@usage
-- 参考gmssl.sm4encrypt
*/
static int l_sm4_decrypt(lua_State *L)
{    
    
    const char *pMode = luaL_checkstring(L, 1);
    const char *pPadding = luaL_checkstring(L, 2);
    size_t nBufLen = 0;
    const char *pBuf = lua_tolstring(L, 3, &nBufLen);
    size_t nPswdLen = 0;
    const char *pPassword = lua_tolstring(L, 4, &nPswdLen);
    size_t nIVLen = 0;
    const char *pIV =  lua_tolstring(L, 5, &nIVLen);
    char out[SM4_BLOCK_LEN];

    //检查参数合法性
    int isCBC = strcmp((char*)pMode, "CBC") == 0;
    int isECB = strcmp((char*)pMode, "ECB") == 0;
    if(isCBC || isECB){
	    if((nBufLen % 16) != 0){
			return luaL_error(L, "invalid BufLen length=%d, BufLen must be Integer multiples of 16", nBufLen);
		}
	}
    if((nPswdLen!=16))
    {
        return luaL_error(L, "invalid password length=%d, only support 128, 192, 256 bits", nPswdLen);
    }
    if(!isCBC && !isECB)
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC,CTR", pMode);
    }
    if((strcmp(pPadding, "NONE")!=0) && (strcmp(pPadding, "PKCS5")!=0) && (strcmp(pPadding, "PKCS7")!=0) && (strcmp((char*)pPadding, "ZERO")!=0))
    {
        return luaL_error(L, "invalid padding=%s, only support NONE,PKCS5,PKCS7,ZERO", pPadding);
    }
    if(isCBC && (nIVLen!=16)) 
    {
        return luaL_error(L, "invalid iv length=%d, only support 16", nIVLen);
    }    
    
    //解密
    {       
        luaL_Buffer b;
        uint32_t nRmnLen;
        luaL_buffinit( L, &b );

        nRmnLen = nBufLen;
		SM4_KEY sm4_key;
        memset(&sm4_key,0,sizeof(SM4_KEY));
        sm4_set_decrypt_key(&sm4_key,(uint8_t*)pPassword);

        if(isECB)
        {
            //开始分组解密，每16字节一组
            while(nRmnLen>0)
            {
                sm4_decrypt(&sm4_key,(uint8_t*)(pBuf+nBufLen-nRmnLen), (uint8_t*)out);
                //删除填充数据
                if(nRmnLen==SM4_BLOCK_LEN)
                {
                    DeletePaddingBuf(&b, pPadding, SM4_BLOCK_LEN, (uint8_t*)out, SM4_BLOCK_LEN);
                }
                else
                {
                    luaL_addlstring(&b, out, SM4_BLOCK_LEN);
                }
                nRmnLen -= SM4_BLOCK_LEN;
            }
        }
        else if (isCBC)
        {
            //待解密数据一次性传入
            if (nBufLen <= 1024) {
                char out[1024];
                sm4_cbc_decrypt(&sm4_key, (uint8_t*)pIV, (uint8_t*)pBuf, nBufLen/SM4_BLOCK_LEN, (uint8_t*)out);
                DeletePaddingBuf(&b, pPadding, nBufLen, (uint8_t*)out, SM4_BLOCK_LEN);
            }
            else {
                char *out = luat_heap_malloc(nBufLen);
                if (out == NULL) {
                    LLOGE("out of memory when malloc SM4 decrypt buff");
                    return 0;
                }
                sm4_cbc_decrypt(&sm4_key, (uint8_t*)pIV, (uint8_t*)pBuf, nBufLen/SM4_BLOCK_LEN, (uint8_t*)out);
                DeletePaddingBuf(&b, pPadding, nBufLen, (uint8_t*)out, SM4_BLOCK_LEN);
                luat_heap_free(out);
            }
        }
		
        luaL_pushresult( &b );
        return 1;
    }
}


/*
sm2算法签名
@api sm.sm2sign(private,data,id)
@string 私钥,必选,HEX字符串
@string 待计算的数据,必选,原始数据,非HEX字符串
@string id值,非HEX字符串,可选,默认值"1234567812345678"
@return string 前面字符串,未经HEX转换.若签名失败会返回nil
@usage
-- 本API于 2023.10.19 新增
-- 具体用法请查阅demo
*/
static int l_sm2_sign(lua_State *L)
{
    int ret = 0;
    size_t pkLen = 0;
    size_t pBufLen = 0;
    size_t idLen = 0;
    // uint8_t sig[SM2_MAX_SIGNATURE_SIZE];
    // size_t siglen = 0;
    const char *pk =   luaL_checklstring(L, 1, &pkLen);
    const char *pBuf = luaL_checklstring(L, 2 ,&pBufLen);
    const char *id =   luaL_optlstring(L, 3, "1234567812345678", &idLen);

    SM2_SIGN_CTX ctx = {0};
    uint8_t dgst[SM3_DIGEST_SIZE];
    SM2_SIGNATURE sig;
    uint8_t pkey[32] = {0};
    if (pkLen != 64) {
        LLOGW("private key len must be 64 byte HEX string");
        return 0;
    }
    if (pBufLen < 1) {
        LLOGW("待签名数据不能为空字符串");
        return 0;
    }

    luat_str_fromhex(pk, 64, (char*)pkey);
    ret = sm2_key_set_private_key(&ctx.key, (const uint8_t*)pkey);
    if (ret != 1) {
        LLOGW("sm2_key_set_private_key %d", ret);
        return 0;
    }
    sm3_init(&ctx.sm3_ctx);
    if (id && idLen > 0) {
        uint8_t z[SM3_DIGEST_SIZE];
        sm2_compute_z(z, &ctx.key.public_key, id, idLen);
		sm3_update(&ctx.sm3_ctx, z, sizeof(z));
    }
    sm3_update(&ctx.sm3_ctx, (const uint8_t*)pBuf, pBufLen);
    sm3_finish(&ctx.sm3_ctx, dgst);
    ret = sm2_do_sign(&ctx.key, dgst, &sig);
    if (ret == 1) {
        lua_pushlstring(L, (const char*)sig.r, 64);
        return 1;
    }
    return 0;
}



/*
sm2算法验签
@api sm.sm2verify(pkx, pky, data, id, sig)
@string 公钥X,必选,HEX字符串
@string 公钥Y,必选,HEX字符串
@string 待计算的数据,必选,原始数据,非HEX字符串
@string id值,非HEX字符串,可选,默认值"1234567812345678"
@string 签名数据,必须64字节,非HEX字符串
@return boolean 验证成功返回true,否则返回nil
@usage
-- 本API于 2023.10.19 新增
-- 具体用法请查阅demo
*/
static int l_sm2_verify(lua_State *L)
{    
    int ret = 0;
    size_t pkxLen = 0;
    size_t pkyLen = 0;
    size_t pBufLen = 0;
    size_t idLen = 0;
    size_t siglen = 0;
    const char *pkx =  luaL_checklstring(L, 1, &pkxLen);
    const char *pky =  luaL_checklstring(L, 2, &pkyLen);
    const char *pBuf = luaL_checklstring(L, 3, &pBufLen);
    const char *id =   luaL_optlstring(L, 4, "1234567812345678", &idLen);
    const char *sig = luaL_checklstring(L, 5, &siglen);

    if (pkxLen != 64 || pkyLen != 64) {
        LLOGW("public key x/y len must be 64 byte HEX string");
        return 0;
    }
    if (pBufLen < 1) {
        LLOGW("待签名数据不能为空字符串");
        return 0;
    }
    if (siglen != 64) {
        LLOGW("sig数据长度应该在64字节");
        return 0;
    }

    SM2_SIGN_CTX ctx = {0};
    uint8_t dgst[SM3_DIGEST_SIZE];
    SM2_SIGNATURE sigT = {0};
    
    luat_str_fromhex(pkx, 64, (char*)ctx.key.public_key.x);
    luat_str_fromhex(pky, 64, (char*)ctx.key.public_key.y);
    memcpy(sigT.r, sig, 64);

    sm3_init(&ctx.sm3_ctx);
    if (id && idLen > 0) {
        uint8_t z[SM3_DIGEST_SIZE];
        sm2_compute_z(z, &ctx.key.public_key, id, idLen);
		sm3_update(&ctx.sm3_ctx, z, sizeof(z));
    }
    sm3_update(&ctx.sm3_ctx, (const uint8_t*)pBuf, pBufLen);
    sm3_finish(&ctx.sm3_ctx, dgst);
    ret = sm2_do_verify(&ctx.key, dgst, &sigT);
    lua_pushboolean(L, ret == 1 ? 1 : 0);
    return 1;
}

/*
SM2密钥生成
@api sm.sm2keygen()
@return string 公钥X, HEX字符串
@return string 公钥Y, HEX字符串
@return string 私钥, HEX字符串
@usage
-- 本函数于2025.8.27新增
-- 注意返回值是HEX字符串, 传递给sm2系列函数可以直接使用
-- 如果传递给服务器, 按格式需要, 可能需要 fromHex 操作
local pkx, pky, private = gmssl.sm2keygen()
local originStr = "32wrniosadnfvnadsio;fasiow"
local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr)
log.info("sm2默认模式", "加密后", encodeStr and  string.toHex(encodeStr))
if encodeStr then
    log.info("sm2默认模式", "解密后", gmssl.sm2decrypt(private,encodeStr))
end

-- 提醒, 生成的密钥对请妥善保管
-- 一定要看 gmssl.sm2encrypt 的文档和demo
*/
static int l_sm2_keygen(lua_State *L)
{
    int ret = 0;
    SM2_SIGN_CTX ctx = {0};
    ret = sm2_key_generate(&ctx.key);
    if (ret != 1) {
        LLOGW("sm2_keygen %d", ret);
        return 0;
    }
    char tmp[128] = {0};
    luat_str_tohex((const char*)ctx.key.public_key.x, 32, tmp);
    lua_pushlstring(L, tmp, 64);
    luat_str_tohex((const char*)ctx.key.public_key.y, 32, tmp);
    lua_pushlstring(L, tmp, 64);
    luat_str_tohex((const char*)ctx.key.private_key, 32, tmp);
    lua_pushlstring(L, tmp, 64);
    return 3;
}

#include "rotable2.h"
static const rotable_Reg_t reg_gmssl[] =
{
    { "sm2encrypt",      ROREG_FUNC(l_sm2_encrypt)},
    { "sm2decrypt",      ROREG_FUNC(l_sm2_decrypt)},
    { "sm3update",       ROREG_FUNC(l_sm3_update)},
    { "sm3",             ROREG_FUNC(l_sm3_update)},
    { "sm3hmac",         ROREG_FUNC(l_sm3hmac_update)},
    { "sm4encrypt",      ROREG_FUNC(l_sm4_encrypt)},
    { "sm4decrypt",      ROREG_FUNC(l_sm4_decrypt)},
    { "sm2sign",         ROREG_FUNC(l_sm2_sign)},
    { "sm2verify",       ROREG_FUNC(l_sm2_verify)},
    { "sm2keygen",       ROREG_FUNC(l_sm2_keygen)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_gmssl( lua_State *L ) {
    luat_newlib2(L, reg_gmssl);
    return 1;
}

