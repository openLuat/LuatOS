
/*
@module  gmssl
@summary 国密算法
@version 1.1
@date    2023.03.02
@author  chenxudong1208
@demo gmssl
@tag LUAT_USE_GMSSL
*/
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_str.h"
#include <time.h>
#include "luat_zbuff.h"
#include "gmssl/sm2.h"
#include "gmssl/sm3.h"
#include "gmssl/sm4.h"
// #include "mbedtls/hmac_drbg.h"

#define LUAT_LOG_TAG "sm"
#include "luat_log.h"
#define SM3_DIGEST_LENGTH    32
#define SM4_BLOCK_LEN 16
#define SM2_STR_LEN 300
#define HEX_CODE 16

extern void luat_str_fromhex(char* str, size_t len, char* buff);

static void DeletePaddingBuf(luaL_Buffer *B, uint8_t *pPadding, size_t nBufLen, uint8_t *pBuf, uint8_t pPaddLen)
{
    uint8_t nPadLen;
    if((strcmp((char*)pPadding, "PKCS5")==0) || (strcmp((char*)pPadding, "PKCS7")==0))
    {
        nPadLen = *(pBuf+nBufLen-1);
        //printf("aes DeletePaddingBuf length=%d\n", nPadLen);
        if((pPaddLen-nPadLen) >= 0)
        {
            luaL_addlstring(B, (char*)pBuf, nBufLen-nPadLen);
        }
    }
    else if(strcmp((char*)pPadding, "ZERO")==0)
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
@api sm.sm2encrypt(pkx,pky,data)
@string 公钥x,必选
@string 公钥y,必选
@string 待计算的数据,必选,最长255字节
@return string 加密后的字符串, 原样输出,未经HEX转换
@usage
local originStr = "encryption standard"
local pkx = "435B39CCA8F3B508C1488AFC67BE491A0F7BA07E581A0E4849A5CF70628A7E0A"
local pky = "75DDBA78F15FEECB4C7895E2C1CDF5FE01DEBB2CDBADF45399CCF77BBA076A42"
local private = "1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0"
local encodeStr = gmssl.sm2encrypt(pkx,pky,originStr)
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.sm2decrypt",gmssl.sm2decrypt(private,encodeStr))
*/
static int l_sm2_encrypt(lua_State *L)
{    
    size_t randLen = 0;
    size_t pkxLen = 0;
    size_t pkyLen = 0;
    size_t pBufLen = 0;
    uint8_t *pkx = lua_tolstring(L, 1,&pkxLen);
    uint8_t *pky = lua_tolstring(L, 2,&pkyLen);
    uint8_t *pBuf = lua_tolstring(L, 3,&pBufLen);
    int ret = 0;

    //检查参数合法性
    if((pkxLen!=64))
    {
        return luaL_error(L, "invalid pkx password length=%d", pkxLen);
    }
    if((pkyLen!=64))
    {
        return luaL_error(L, "invalid pky password length=%d", pkyLen);
    }
    if (pBufLen > SM2_MAX_PLAINTEXT_SIZE) {
        LLOGD("data too large max %d but %d", SM2_MAX_PLAINTEXT_SIZE, pBufLen);
        return 0;
    }

    SM2_KEY sm2 = {0};
    const SM2_POINT point;
    char x[32];
    char y[32];
    luat_str_fromhex((char*)pkx, 64, point.x);
    luat_str_fromhex((char*)pky, 64, point.y);
    ret = sm2_key_set_public_key(&sm2.public_key, &point);
    LLOGD("sm2_key_set_public_key %d", ret);

    unsigned char out[SM2_MAX_CIPHERTEXT_SIZE] = {0};
    size_t olen = 0;

    ret = sm2_encrypt(&sm2, (const unsigned char *)pBuf, pBufLen, out, &olen);
    LLOGD("sm2_encrypt ret %d", ret);
    lua_pushlstring(L, (char*)out, olen);
    return 1;
}

/*
sm2算法解密
@api sm.sm2decrypt(private,data)
@string 私钥,必选
@string 待计算的数据,必选
@return string 解密后的字符串,未经HEX转换
@usage
local originStr = "encryption standard"
local pkx = "435B39CCA8F3B508C1488AFC67BE491A0F7BA07E581A0E4849A5CF70628A7E0A"
local pky = "75DDBA78F15FEECB4C7895E2C1CDF5FE01DEBB2CDBADF45399CCF77BBA076A42"
local private = "1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0"
local rand = "4C62EEFD6ECFC2B95B92FD6C3D9575148AFA17425546D49018E5388D49DD7B4F"
local encodeStr = gmssl.sm2encrypt(pkx,pky,rand,originStr)
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.sm2decrypt",gmssl.sm2decrypt(private,encodeStr))
*/
static int l_sm2_decrypt(lua_State *L)
{    
    size_t privateLen = 0;
    size_t pBufLen = 0;
    uint8_t *private = lua_tolstring(L, 1,&privateLen);
    uint8_t *pBuf = lua_tolstring(L, 2,&pBufLen);
    int ret = 0;

    //检查参数合法性
    if((privateLen!=64))
    {
        return luaL_error(L, "invalid private password length=%d", privateLen);
    }
    
    SM2_KEY sm2 = {0};
    char out[512] = {0};
    size_t olen = 0;
    luat_str_fromhex((char*)private, 64, (char*)sm2.private_key);

    ret = sm2_decrypt(&sm2, pBuf, pBufLen, (uint8_t*)out, &olen);
    LLOGD("sm2_decrypt ret %d", ret);
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
@return string 加密后的数据
@usage
local originStr = "AES128 ECB ZeroPadding test"
--加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；密钥长度：128 bit
local encodeStr = gmssl.sm4encrypt("ECB","ZERO",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("ECB","ZERO",encodeStr,"1234567890123456"))

originStr = "AES128 ECB Pkcs5Padding test"
--加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit
encodeStr = gmssl.sm4encrypt("ECB","PKCS5",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("ECB","PKCS5",encodeStr,"1234567890123456"))

originStr = "AES256 CBC Pkcs5Padding test"
--加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：256 bit；偏移量：1234567890666666
encodeStr = gmssl.sm4encrypt("CBC","PKCS5",originStr,"1234567890123456","1234567890666666")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",gmssl.sm4decrypt("CBC","PKCS5",encodeStr,"1234567890123456","1234567890666666"))
*/
static int l_sm4_encrypt(lua_State *L)
{    
    uint8_t *pMode = luaL_checkstring(L, 1);
    uint8_t *pPadding = luaL_checkstring(L, 2);
    size_t nBufLen = 0;
    uint8_t *pBuf = lua_tolstring(L, 3, &nBufLen);
    size_t nPswdLen = 0;
    uint8_t *pPassword = lua_tolstring(L, 4, &nPswdLen);
    size_t nIVLen = 0;
    uint8_t *pIV =  lua_tolstring(L, 5, &nIVLen);

    int nPadLen = SM4_BLOCK_LEN-(nBufLen%SM4_BLOCK_LEN);
    uint8_t pPadBuf[SM4_BLOCK_LEN] = {0};
    uint8_t *pInBuf = NULL;
	
    //检查参数合法性
    if((nPswdLen!=16))
    {
        return luaL_error(L, "invalid password length=%d, only support 128bit Password", nPswdLen);
    }
    if((strcmp((char*)pMode, "ECB")!=0) && (strcmp((char*)pMode, "CBC")!=0))
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC", pMode);
    }
    if((strcmp((char*)pPadding, "NONE")!=0) && (strcmp((char*)pPadding, "PKCS5")!=0) && (strcmp((char*)pPadding, "PKCS7")!=0) && (strcmp((char*)pPadding, "ZERO")!=0))
    {
        return luaL_error(L, "invalid padding=%s, only support NONE,PKCS5,PKCS7,ZERO", pPadding);
    }
    if(((strcmp((char*)pMode, "CBC")==0)) && (nIVLen!=16))
    {
        return luaL_error(L, "invalid iv length=%d, only support 128bit IV", nIVLen);
    }

    //构造填充数据
    if((strcmp((char*)pPadding, "PKCS5")==0) || (strcmp((char*)pPadding, "PKCS7")==0))
    {
        memset(pPadBuf, nPadLen, sizeof(pPadBuf));
    }
    else if(strcmp((char*)pPadding, "ZERO")==0)
    {
        memset(pPadBuf, 0, sizeof(pPadBuf));
    }   
	else if(strcmp((char*)pPadding, "NONE")==0)
    {
    	if((strcmp((char*)pMode, "CBC")==0) || (strcmp((char*)pMode, "ECB")==0)){
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
		sm4_set_encrypt_key(&sm4_key,pPassword);

        if(strcmp((char*)pMode, "ECB") == 0)
        {
            //开始分组加密，每16字节一组
            while(nRmnLen>0)
            {
                // sm4_ecb_encrypt(pInBuf+nBufLen-nRmnLen,pInBuf+nBufLen-nRmnLen,&sm4_key,1);
                char out[SM4_BLOCK_LEN];
                sm4_encrypt(&sm4_key,pBuf+nBufLen-nRmnLen, (uint8_t*)out);
                luaL_addlstring(&b, out, SM4_BLOCK_LEN);
                nRmnLen -= SM4_BLOCK_LEN;
            }
        }
        else if((strcmp((char*)pMode, "CBC") == 0))
        {
            //待加密数据一次性传入
            // sm4_cbc_encrypt(pInBuf,pInBuf,nBufLen,&sm4_key,pIV,1);
            char *out = luat_heap_malloc(nBufLen);
            sm4_cbc_encrypt(&sm4_key, pIV, pInBuf, nBufLen / SM4_BLOCK_LEN, (uint8_t*)out);
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
@return string 解密的字符串
@usage
-- 参考gmssl.sm4encrypt
*/
static int l_sm4_decrypt(lua_State *L)
{    
    
    uint8_t *pMode = luaL_checkstring(L, 1);
    uint8_t *pPadding = luaL_checkstring(L, 2);
    size_t nBufLen = 0;
    uint8_t *pBuf = lua_tolstring(L, 3, &nBufLen);
    size_t nPswdLen = 0;
    uint8_t *pPassword = lua_tolstring(L, 4, &nPswdLen);
    size_t nIVLen = 0;
    uint8_t *pIV =  lua_tolstring(L, 5, &nIVLen);
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
        return luaL_error(L, "invalid password length=%d, only support AES128,AES192,AES256", nPswdLen);
    }
    if(!isCBC && !isECB)
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC,CTR", pMode);
    }
    if((strcmp((char*)pPadding, "NONE")!=0) && (strcmp((char*)pPadding, "PKCS5")!=0) && (strcmp((char*)pPadding, "PKCS7")!=0) && (strcmp((char*)pPadding, "ZERO")!=0))
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
        sm4_set_decrypt_key(&sm4_key,pPassword);

        if(isECB)
        {
            //开始分组解密，每16字节一组
            while(nRmnLen>0)
            {
                sm4_decrypt(&sm4_key,pBuf+nBufLen-nRmnLen, (uint8_t*)out);
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
                sm4_cbc_decrypt(&sm4_key, pIV, pBuf, nBufLen/SM4_BLOCK_LEN, (uint8_t*)out);
                DeletePaddingBuf(&b, pPadding, nBufLen, (uint8_t*)out, SM4_BLOCK_LEN);
            }
            else {
                char *out = luat_heap_malloc(nBufLen);
                if (out == NULL) {
                    LLOGE("out of memory when malloc SM4 decrypt buff");
                    return 0;
                }
                sm4_cbc_decrypt(&sm4_key, pIV, pBuf, nBufLen/SM4_BLOCK_LEN, (uint8_t*)out);
                DeletePaddingBuf(&b, pPadding, nBufLen, (uint8_t*)out, SM4_BLOCK_LEN);
                luat_heap_free(out);
            }
        }
		
        luaL_pushresult( &b );
        return 1;
    }
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

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_gmssl( lua_State *L ) {
    luat_newlib2(L, reg_gmssl);
    return 1;
}

