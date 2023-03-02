
/*
@module  sm
@summary 国密算法
@version 1.0
@date    2020.07.03
@demo sm
@tag LUAT_USE_SM
*/
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_str.h"
#include <time.h>
#include "luat_zbuff.h"
#include "sm2.h"
#include "sm3.h"
#include "sm4.h"

#define LUAT_LOG_TAG "sm"
#include "luat_log.h"
#define SM3_DIGEST_LENGTH    32
#define SM4_BLOCK_LEN 16
#define SM2_STR_LEN 300
#define HEX_CODE 16

static int myrand(void *ctx, unsigned char *msg, size_t size)
{
	mbedtls_mpi k;
	mbedtls_mpi_init(&k);
	mbedtls_mpi_read_string(&k, HEX_CODE,
							ctx);
	mbedtls_mpi_write_binary(&k, msg, size);
	mbedtls_mpi_free(&k);
	return 0;
}

static void DeletePaddingBuf(luaL_Buffer *B, uint8_t *pPadding, size_t nBufLen, uint8_t *pBuf, uint8_t pPaddLen)
{
    uint8_t nPadLen;
    if((strcmp(pPadding, "PKCS5")==0) || (strcmp(pPadding, "PKCS7")==0))
    {
        nPadLen = *(pBuf+nBufLen-1);
        //printf("aes DeletePaddingBuf length=%d\n", nPadLen);
        if((pPaddLen-nPadLen) >= 0)
        {
            luaL_addlstring(B, pBuf, nBufLen-nPadLen);
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
            luaL_addlstring(B, pBuf, nBufLen-nPadLen);
        }
    }
    else
    {
        luaL_addlstring(B, pBuf, nBufLen);
    }
}


/*
sm2算法加密
@api sm.sm2encrypt(pkx,pky,rand,data)
@string 公钥x,必选
@string 公钥y,必选
@string 随机数,必选
@string 待计算的数据,必选
@return 
@usage
local originStr = "encryption standard"
local pkx = "435B39CCA8F3B508C1488AFC67BE491A0F7BA07E581A0E4849A5CF70628A7E0A"
local pky = "75DDBA78F15FEECB4C7895E2C1CDF5FE01DEBB2CDBADF45399CCF77BBA076A42"
local private = "1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0"
local rand = "4C62EEFD6ECFC2B95B92FD6C3D9575148AFA17425546D49018E5388D49DD7B4F"
local encodeStr = sm.sm2encrypt(pkx,pky,rand,originStr)
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.sm2decrypt",sm.sm2decrypt(private,encodeStr))
*/
static int l_sm2_encrypt(lua_State *L)
{    
    size_t randLen = 0;
    size_t pkxLen = 0;
    size_t pkyLen = 0;
    size_t pBufLen = 0;
    uint8_t *pkx = lua_tolstring(L, 1,&pkxLen);
    uint8_t *pky = lua_tolstring(L, 2,&pkyLen);
    uint8_t *rand = lua_tolstring(L, 3,&randLen);
    uint8_t *pBuf = lua_tolstring(L, 4,&pBufLen);

    //检查参数合法性
    if((pkxLen!=64))
    {
        return luaL_error(L, "invalid pkx password length=%d", pkxLen);
    }
    if((pkyLen!=64))
    {
        return luaL_error(L, "invalid pky password length=%d", pkyLen);
    }
    if((randLen!=64))
    {
        return luaL_error(L, "invalid rand length=%d", randLen);
    }
    
    unsigned char *out = calloc(SM2_STR_LEN, sizeof(unsigned char));
    int ret = 0;
    size_t olen = 0;
    sm2_context sm2;
	sm2_init(&sm2);

    //set key
	sm2_read_string_public(&sm2, pkx, pky);

    ret = sm2_do_encrypt(&sm2, (const unsigned char *)pBuf, pBufLen, out, SM2_STR_LEN, &olen,
							 myrand, rand);

    luaL_Buffer b;
    luaL_buffinit( L, &b );                         
    luaL_addlstring(&b, out, olen);
    luaL_pushresult( &b );

    sm2_free(&sm2);
    free(out);
    return 1;
}

/*
sm2算法解密
@api sm.sm2decrypt(private,data)
@string 私钥,必选
@string 待计算的数据,必选
@return 
@usage
local originStr = "encryption standard"
local pkx = "435B39CCA8F3B508C1488AFC67BE491A0F7BA07E581A0E4849A5CF70628A7E0A"
local pky = "75DDBA78F15FEECB4C7895E2C1CDF5FE01DEBB2CDBADF45399CCF77BBA076A42"
local private = "1649AB77A00637BD5E2EFE283FBF353534AA7F7CB89463F208DDBC2920BB0DA0"
local rand = "4C62EEFD6ECFC2B95B92FD6C3D9575148AFA17425546D49018E5388D49DD7B4F"
local encodeStr = sm.sm2encrypt(pkx,pky,rand,originStr)
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.sm2decrypt",sm.sm2decrypt(private,encodeStr))
*/
static int l_sm2_decrypt(lua_State *L)
{    
    size_t privateLen = 0;
    size_t pBufLen = 0;
    uint8_t *private = lua_tolstring(L, 1,&privateLen);
    uint8_t *pBuf = lua_tolstring(L, 2,&pBufLen);

    //检查参数合法性
    if((privateLen!=64))
    {
        return luaL_error(L, "invalid private password length=%d", privateLen);
    }
    
    unsigned char *out = calloc(SM2_STR_LEN, sizeof(unsigned char));
    int ret = 0;
    size_t olen = 0;
    sm2_context sm2;
	sm2_init(&sm2);

    //set key
    sm2_read_string_private(&sm2, private);

    ret = sm2_do_decrypt(&sm2, pBuf, pBufLen, out, SM2_STR_LEN, &olen);

    luaL_Buffer b;
    luaL_buffinit( L, &b );                         
    luaL_addlstring(&b, out, olen);
    luaL_pushresult( &b );

    sm2_free(&sm2);
    free(out);
    return 1;
}

/*
流式sm3算法加密
@api sm.sm3update(data)
@string 待计算的数据,必选
@return 
@usage
local encodeStr = sm.sm3update("lqlq666lqlq946")
log.info("testsm.sm3update",string.toHex(encodeStr))
*/
static int l_sm3_update(lua_State *L)
{
    sm3_context ctx;
    size_t inputLen;
    uint8_t out[SM3_DIGEST_LENGTH];
	uint32_t i = 0;
    luaL_Buffer b;
    luaL_buffinit(L, &b);  

    const char *inputData = lua_tolstring(L,1,&inputLen);
    sm3_init(&ctx);
    sm3_starts(&ctx);
    sm3_update(&ctx,(unsigned char *)inputData, inputLen);
    memset(out, 0, SM3_DIGEST_LENGTH);   
    sm3_finish(&ctx, out);
    sm3_free(&ctx);

    luaL_addlstring(&b, out, SM3_DIGEST_LENGTH);
    luaL_pushresult(&b);
    
    return 1;
}

/*
SM4加密算法
@api sm.sm4encrypt(mode,padding,originStr,password)
@number  加密模式   
@number  填充方式 
@string  加密的字符串
@string  密钥
@return string 加密后的数据
@usage
local originStr = "AES128 ECB ZeroPadding test"
--加密模式：ECB；填充方式：ZeroPadding；密钥：1234567890123456；密钥长度：128 bit
local encodeStr = sm.sm4encrypt("ECB","ZERO",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",sm.sm4decrypt("ECB","ZERO",encodeStr,"1234567890123456"))

originStr = "AES128 ECB Pkcs5Padding test"
--加密模式：ECB；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：128 bit
encodeStr = sm.sm4encrypt("ECB","PKCS5",originStr,"1234567890123456")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",sm.sm4decrypt("ECB","PKCS5",encodeStr,"1234567890123456"))

originStr = "AES256 CBC Pkcs5Padding test"
--加密模式：CBC；填充方式：Pkcs5Padding；密钥：1234567890123456；密钥长度：256 bit；偏移量：1234567890666666
encodeStr = sm.sm4encrypt("CBC","PKCS5",originStr,"1234567890123456","1234567890666666")
print(originStr,"encrypt",string.toHex(encodeStr))
log.info("testsm.decrypt",sm.sm4decrypt("CBC","PKCS5",encodeStr,"1234567890123456","1234567890666666"))
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
        return luaL_error(L, "invalid password length=%d, only support AES128,AES192,AES256", nPswdLen);
    }
    if((strcmp(pMode, "ECB")!=0) && (strcmp(pMode, "CBC")!=0))
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC,CTR", pMode);
    }
    if((strcmp(pPadding, "NONE")!=0) && (strcmp(pPadding, "PKCS5")!=0) && (strcmp(pPadding, "PKCS7")!=0) && (strcmp(pPadding, "ZERO")!=0))
    {
        return luaL_error(L, "invalid padding=%s, only support NONE,PKCS5,PKCS7,ZERO", pPadding);
    }
    if(((strcmp(pMode, "CBC")==0)) && (nIVLen!=16))
    {
        return luaL_error(L, "invalid iv length=%d, only support 16", nIVLen);
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
        if (strcmp(pPadding, "NONE")!=0)
        {
            pInBuf = malloc(nBufLen+nPadLen);
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
            pInBuf =  malloc(nBufLen);
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

        if(strcmp(pMode, "ECB") == 0)
        {
            //开始分组加密，每16字节一组
            while(nRmnLen>0)
            {
                sm4_ecb_encrypt(pInBuf+nBufLen-nRmnLen,pInBuf+nBufLen-nRmnLen,&sm4_key,1);	
                luaL_addlstring(&b, pInBuf+nBufLen-nRmnLen, SM4_BLOCK_LEN);
                nRmnLen -= SM4_BLOCK_LEN;
            }
        }
        else if((strcmp(pMode, "CBC") == 0))
        {
            //待加密数据一次性传入
            sm4_cbc_encrypt(pInBuf,pInBuf,nBufLen,&sm4_key,pIV,1);
            luaL_addlstring(&b, pInBuf, nBufLen);
        }

        if(pInBuf != NULL)
        {
            free(pInBuf);
            pInBuf = NULL;
        }

        luaL_pushresult( &b );
        return 1;
    }   
}


/*
SM4解密算法
@api sm.sm4_decrypt(mode,padding,encodeStr,password)
@number  加密模式   
@number  填充方式 
@string  已加密的字符串
@string  密钥
@return string 解密的字符串
@usage
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

    //检查参数合法性
    if((strcmp(pMode, "CBC")==0) || (strcmp(pMode, "ECB")==0)){
	    if((nBufLen % 16) != 0){
			return luaL_error(L, "invalid BufLen length=%d, BufLen must be Integer multiples of 16", nBufLen);
		}
	}
    if((nPswdLen!=16))
    {
        return luaL_error(L, "invalid password length=%d, only support AES128,AES192,AES256", nPswdLen);
    }
    if((strcmp(pMode, "ECB")!=0) && (strcmp(pMode, "CBC")!=0))
    {
        return luaL_error(L, "invalid mode=%s, only support ECB,CBC,CTR", pMode);
    }
    if((strcmp(pPadding, "NONE")!=0) && (strcmp(pPadding, "PKCS5")!=0) && (strcmp(pPadding, "PKCS7")!=0) && (strcmp(pPadding, "ZERO")!=0))
    {
        return luaL_error(L, "invalid padding=%s, only support NONE,PKCS5,PKCS7,ZERO", pPadding);
    }
    if(((strcmp(pMode, "CBC")==0)) && (nIVLen!=16)) 
    {
        return luaL_error(L, "invalid iv length=%d, only support 16", nIVLen);
    }    
    
    //解密
    {       
        luaL_Buffer b;
        uint32_t nRmnLen;
        memset(b.initb,0,LUAL_BUFFERSIZE);
        luaL_buffinit( L, &b );

        nRmnLen = nBufLen;
		SM4_KEY sm4_key;
        memset(&sm4_key,0,sizeof(SM4_KEY));
        sm4_set_decrypt_key(&sm4_key,pPassword);

        if(strcmp(pMode, "ECB") == 0)
        {
            //开始分组解密，每16字节一组
            while(nRmnLen>0)
            {
                sm4_ecb_encrypt(pBuf+nBufLen-nRmnLen,pBuf+nBufLen-nRmnLen,&sm4_key,0);
                //删除填充数据
                if(nRmnLen==SM4_BLOCK_LEN)
                {
                    DeletePaddingBuf(&b, pPadding, SM4_BLOCK_LEN, pBuf+nBufLen-nRmnLen, SM4_BLOCK_LEN);
                }
                else
                {
                    luaL_addlstring(&b, pBuf+nBufLen-nRmnLen, SM4_BLOCK_LEN);
                }
                nRmnLen -= SM4_BLOCK_LEN;
            }
        }
        else if((strcmp(pMode, "CBC") == 0))
        {
            //待解密数据一次性传入
            sm4_cbc_encrypt(pBuf,pBuf,nBufLen,&sm4_key,pIV,0);
            DeletePaddingBuf(&b, pPadding, nBufLen, pBuf, SM4_BLOCK_LEN);
        }
		
        luaL_pushresult( &b );
        return 1;
    }    
}

#include "rotable2.h"
static const rotable_Reg_t reg_sm[] =
{
    { "sm2encrypt",      ROREG_FUNC(l_sm2_encrypt)},
    { "sm2decrypt",      ROREG_FUNC(l_sm2_decrypt)},
    { "sm3update",      ROREG_FUNC(l_sm3_update)},
    { "sm4encrypt",      ROREG_FUNC(l_sm4_encrypt)},
    { "sm4decrypt",      ROREG_FUNC(l_sm4_decrypt)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_sm( lua_State *L ) {
    luat_newlib2(L, reg_sm);
    return 1;
}

