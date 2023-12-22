/**********************************************************\
|                                                          |
| xxtea.c                                                  |
|                                                          |
| XXTEA encryption algorithm library for C.                |
|                                                          |
| Encryption Algorithm Authors:                            |
|      David J. Wheeler                                    |
|      Roger M. Needham                                    |
|                                                          |
| Code Authors: Chen fei <cf850118@163.com>                |
|               Ma Bingyao <mabingyao@gmail.com>           |
| LastModified: Feb 7, 2016                                |
|                                                          |
\**********************************************************/

#if 1//def AM_XXTEA_SUPPORT

#include "xxtea.h"

#include <string.h>
#if defined(_MSC_VER) && _MSC_VER < 1600
typedef unsigned __int8 uint8_t;
typedef unsigned __int32 uint32_t;
#else
#if defined(__FreeBSD__) && __FreeBSD__ < 5
/* FreeBSD 4 doesn't have stdint.h file */
#include <inttypes.h>
#else
#include <stdint.h>
#endif
#endif

#include "luat_base.h"

#ifndef BYTE_ORDER
#if (BSD >= 199103)
# include <machine/endian.h>
#else
#if defined(linux) || defined(__linux__)
# include <endian.h>
#else
#define LITTLE_ENDIAN   1234    /* least-significant byte first (vax, pc) */
#define BIG_ENDIAN  4321    /* most-significant byte first (IBM, net) */
#define PDP_ENDIAN  3412    /* LSB first in word, MSW first in long (pdp)*/

#if defined(__i386__) || defined(__x86_64__) || defined(__amd64__) || \
   defined(vax) || defined(ns32000) || defined(sun386) || \
   defined(MIPSEL) || defined(_MIPSEL) || defined(BIT_ZERO_ON_RIGHT) || \
   defined(__alpha__) || defined(__alpha)
#define BYTE_ORDER    LITTLE_ENDIAN
#endif

#if defined(sel) || defined(pyr) || defined(mc68000) || defined(sparc) || \
    defined(is68k) || defined(tahoe) || defined(ibm032) || defined(ibm370) || \
    defined(MIPSEB) || defined(_MIPSEB) || defined(_IBMR2) || defined(DGUX) ||\
    defined(apollo) || defined(__convex__) || defined(_CRAY) || \
    defined(__hppa) || defined(__hp9000) || \
    defined(__hp9000s300) || defined(__hp9000s700) || \
    defined (BIT_ZERO_ON_LEFT) || defined(m68k) || defined(__sparc)
#define BYTE_ORDER  BIG_ENDIAN
#endif
#endif /* linux */
#endif /* BSD */
#endif /* BYTE_ORDER */

#ifndef BYTE_ORDER
#ifdef __BYTE_ORDER
#if defined(__LITTLE_ENDIAN) && defined(__BIG_ENDIAN)
#ifndef LITTLE_ENDIAN
#define LITTLE_ENDIAN __LITTLE_ENDIAN
#endif
#ifndef BIG_ENDIAN
#define BIG_ENDIAN __BIG_ENDIAN
#endif
#if (__BYTE_ORDER == __LITTLE_ENDIAN)
#define BYTE_ORDER LITTLE_ENDIAN
#else
#define BYTE_ORDER BIG_ENDIAN
#endif
#endif
#endif
#endif

#define MX (((z >> 5) ^ (y << 2)) + ((y >> 3) ^ (z << 4))) ^ ((sum ^ y) + (key[(p & 3) ^ e] ^ z))
#define DELTA 0x9e3779b9

#define FIXED_KEY \
    size_t i;\
    uint8_t fixed_key[16];\
    memcpy(fixed_key, key, 16);\
    for (i = 0; (i < 16) && (fixed_key[i] != 0); ++i);\
    for (++i; i < 16; ++i) fixed_key[i] = 0;\


static uint32_t * xxtea_to_uint_array(const uint8_t * data, size_t len, int inc_len, size_t * out_len) {
    uint32_t *out;
#if !(defined(BYTE_ORDER) && (BYTE_ORDER == LITTLE_ENDIAN))
    size_t i;
#endif
    size_t n;

    n = (((len & 3) == 0) ? (len >> 2) : ((len >> 2) + 1));

    if (inc_len) {
        out = (uint32_t *)calloc(n + 1, sizeof(uint32_t));
        if (!out) return NULL;
        out[n] = (uint32_t)len;
        *out_len = n + 1;
    }
    else {
        out = (uint32_t *)calloc(n, sizeof(uint32_t));
        if (!out) return NULL;
        *out_len = n;
    }
#if defined(BYTE_ORDER) && (BYTE_ORDER == LITTLE_ENDIAN)
    memcpy(out, data, len);
#else
    for (i = 0; i < len; ++i) {
        out[i >> 2] |= (uint32_t)data[i] << ((i & 3) << 3);
    }
#endif

    return out;
}

static uint8_t * xxtea_to_ubyte_array(const uint32_t * data, size_t len, int inc_len, size_t * out_len) {
    uint8_t *out;
#if !(defined(BYTE_ORDER) && (BYTE_ORDER == LITTLE_ENDIAN))
    size_t i;
#endif
    size_t m, n;

    n = len << 2;

    if (inc_len) {
        m = data[len - 1];
        n -= 4;
        if ((m < n - 3) || (m > n)) return NULL;
        n = m;
    }

    out = (uint8_t *)malloc(n + 1);

#if defined(BYTE_ORDER) && (BYTE_ORDER == LITTLE_ENDIAN)
    memcpy(out, data, n);
#else
    for (i = 0; i < n; ++i) {
        out[i] = (uint8_t)(data[i >> 2] >> ((i & 3) << 3));
    }
#endif

    out[n] = '\0';
    *out_len = n;

    return out;
}

static uint32_t * xxtea_uint_encrypt(uint32_t * data, size_t len, uint32_t * key) {
    uint32_t n = (uint32_t)len - 1;
    uint32_t z = data[n], y, p, q = 6 + 52 / (n + 1), sum = 0, e;

    if (n < 1) return data;

    while (0 < q--) {
        sum += DELTA;
        e = sum >> 2 & 3;

        for (p = 0; p < n; p++) {
            y = data[p + 1];
            z = data[p] += MX;
        }

        y = data[0];
        z = data[n] += MX;
    }

    return data;
}

static uint32_t * xxtea_uint_decrypt(uint32_t * data, size_t len, uint32_t * key) {
    uint32_t n = (uint32_t)len - 1;
    uint32_t z, y = data[0], p, q = 6 + 52 / (n + 1), sum = q * DELTA, e;

    if (n < 1) return data;

    while (sum != 0) {
        e = sum >> 2 & 3;

        for (p = n; p > 0; p--) {
            z = data[p - 1];
            y = data[p] -= MX;
        }

        z = data[n];
        y = data[0] -= MX;
        sum -= DELTA;
    }

    return data;
}

static uint8_t * xxtea_ubyte_encrypt(const uint8_t * data, size_t len, const uint8_t * key, size_t * out_len) {
    uint8_t *out;
    uint32_t *data_array, *key_array;
    size_t data_len, key_len;

    if (!len) return NULL;

    data_array = xxtea_to_uint_array(data, len, 1, &data_len);
    if (!data_array) return NULL;

    key_array  = xxtea_to_uint_array(key, 16, 0, &key_len);
    if (!key_array) {
        free(data_array);
        return NULL;
    }

    out = xxtea_to_ubyte_array(xxtea_uint_encrypt(data_array, data_len, key_array), data_len, 0, out_len);

    free(data_array);
    free(key_array);

    return out;
}

static uint8_t * xxtea_ubyte_decrypt(const uint8_t * data, size_t len, const uint8_t * key, size_t * out_len) {
    uint8_t *out;
    uint32_t *data_array, *key_array;
    size_t data_len, key_len;

    if (!len) return NULL;

    data_array = xxtea_to_uint_array(data, len, 0, &data_len);
    if (!data_array) return NULL;

    key_array  = xxtea_to_uint_array(key, 16, 0, &key_len);
    if (!key_array) {
        free(data_array);
        return NULL;
    }

    out = xxtea_to_ubyte_array(xxtea_uint_decrypt(data_array, data_len, key_array), data_len, 1, out_len);

    free(data_array);
    free(key_array);

    return out;
}

// public functions

void * xxtea_encrypt(const void * data, size_t len, const void * key, size_t * out_len) {
    FIXED_KEY
    return xxtea_ubyte_encrypt(data, len, fixed_key, out_len);
}

void * xxtea_decrypt(const void * data, size_t len, const void * key, size_t * out_len) {
    FIXED_KEY
    return xxtea_ubyte_decrypt(data, len, fixed_key, out_len);
}

//#define MX                      (z>>5^y<<2)+(y>>3^z<<4)^(sum^y)+(k[p&3^e]^z)
//#define DELTA                   0X9E3779B9

#define S_LOOPTIME              1
#define ENCRYPT_INT_BUFF        256 


/******************************************************************************/
/*                              内部数据类型定义                              */
/******************************************************************************/


/******************************************************************************/
/*                               全局(静态)变量                               */
/******************************************************************************/
static int sg_key_buff[4] = {0};
static int sg_data_buff[ENCRYPT_INT_BUFF] = {0};


/******************************************************************************/
/*                                内部函数原型                                */
/******************************************************************************/
static int bytes2int(unsigned char *bytes);
static void int2byte(int data, unsigned char *bytes);
static void TEA_EncryptCore(int block_size, int *buf, int *key);
static void TEA_DecrpytCore(int block_size, int *buf, int *key);


/******************************************************************************/
/*                                全局函数实现                                */
/******************************************************************************/
/*<FUNC+>**********************************************************************/
/* 函数名称: PUB_XxTEASetKey                                                  */
/* 功能描述: 设置XxTEA算法的密钥                                              */
/* 输入参数: key --- 指向秘钥的指针                                           */
/* 输出参数: 无                                                               */
/* 返 回 值: void                                                             */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
void PUB_XxTEASetKey(unsigned char* key)
{
    int i;

    for(i=0; i<4; i++)
    {
        sg_key_buff[i] = bytes2int(&key[i*4]);
    }
}

/*<FUNC+>**********************************************************************/
/* 函数名称: PUB_XxTEAEncrypt                                                 */
/* 功能描述: XXTEA加密算法实现                                                */
/* 输入参数: data --- 指向加密数据的指针                                      */
/*           data_size --- 加密数据长度                                       */
/* 输出参数: 无                                                               */
/* 返 回 值: int                                                              */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
unsigned char * PUB_XxTEAEncrypt(unsigned char *data, unsigned short data_size,size_t * out_len)
{
    int i          = 0;
    int block_size = ((data_size + 2) / 4 + 1) * 4;

	unsigned char *out_data = malloc(block_size);
	
	memset(out_data,0,data_size);
	
	memcpy(out_data,data,data_size);

    memset(sg_data_buff, 0, ENCRYPT_INT_BUFF*4);

    if (block_size > data_size)
    {
        memset(&out_data[data_size], 0, block_size-data_size);
    }
    
    for (i=data_size+1; i>=2; i--)
    {
        out_data[i]= out_data[i-2];
    }
    
    out_data[0] = (data_size >>8)&0xff;
    out_data[1] = (data_size >>0)&0xff;

    for (i=0; i<block_size/4; i++)
    {
        sg_data_buff[i] = bytes2int(&out_data[i*4]);
    }
    
    TEA_EncryptCore(block_size, sg_data_buff, sg_key_buff);
    
    for (i=0; i<block_size/4; i++)
    {
        int2byte(sg_data_buff[i], &out_data[i*4]);
    }

	* out_len = block_size;

    return out_data;
}

/*<FUNC+>**********************************************************************/
/* 函数名称: PUB_XxTEADecrypt                                                 */
/* 功能描述: XxTEA解密算法实现                                                */
/* 输入参数: data --- 指向解密数据的指针                                      */
/*           data_size --- 解密数据长度                                       */
/* 输出参数: 无                                                               */
/* 返 回 值: int                                                              */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
unsigned char * PUB_XxTEADecrypt(unsigned char* data, unsigned short data_size,size_t * out_len)
{
    int i;
    int real_data_size =0;

	unsigned char *out_data = malloc(data_size);
	
	memset(out_data,0,data_size);
	
	memcpy(out_data,data,data_size);

    memset(sg_data_buff, 0, ENCRYPT_INT_BUFF*4);
    
    for (i=0; i<data_size/4; i++)
    {
        sg_data_buff[i] = bytes2int(&out_data[i * 4]);
    }

    TEA_DecrpytCore(data_size, sg_data_buff, sg_key_buff); 

    for(i=0; i<data_size/4; i++)
    {
        int2byte(sg_data_buff[i], &out_data[i*4]);
    }

    real_data_size = ((int)out_data[0] << 8) | (int)out_data[1];

    if (real_data_size > data_size)
    {
        return 0;
    }

    for (i=0; i<real_data_size; i++)
    {
        out_data[i] = out_data[i +2];
    }

	* out_len = real_data_size;

    return out_data;
}

/******************************************************************************/
/*                                内部函数实现                                */
/******************************************************************************/
/*<FUNC+>**********************************************************************/
/* 函数名称: bytes2int                                                        */
/* 功能描述: 字节转换为字                                                     */
/* 输入参数: bytes --- 指向字节流的指针                                       */
/* 输出参数: 无                                                               */
/* 返 回 值: int                                                              */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
static int bytes2int(unsigned char *bytes) 
{
    int result = bytes[0] & 0xFF;

    result |= ((bytes[1] << 8) & 0xFF00);
    result |= ((bytes[2] << 16) & 0xFF0000);
    result |= ((bytes[3] << 24) & 0xFF000000);

    return result;
}

/*<FUNC+>**********************************************************************/
/* 函数名称: int2byte                                                         */
/* 功能描述: 字转换为字节                                                     */
/* 输入参数: data --- 要转换的字                                              */
/*           bytes --- 指向字节缓冲区的指针                                   */
/* 输出参数: 无                                                               */
/* 返 回 值: void                                                             */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
static void int2byte(int data, unsigned char *bytes) 
{
    bytes[0] = (unsigned char)(0xff & data);
    bytes[1] = (unsigned char)((0xff00 & data) >> 8);
    bytes[2] = (unsigned char)((0xff0000 & data) >> 16);
    bytes[3] = (unsigned char)((0xff000000 & data) >> 24);
}

/*<FUNC+>**********************************************************************/
/* 函数名称: TEA_EncryptCore                                                  */
/* 功能描述: XXTEA加密核心算法                                                */
/* 输入参数: block_size --- 块大小                                            */
/*           buf --- 指向加密数据的指针                                       */
/*           key --- 指向秘钥的指针                                           */
/* 输出参数: 无                                                               */
/* 返 回 值: static void                                                      */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
static void TEA_EncryptCore(int block_size, int *buf, int *key)
{
    char n   = block_size /4;
    int *v   =(int*)buf;
    int *k   =(int*)key;
    long z   = v[n -1];
    long y   = v[0];
    long sum =0;
    long e;
    char p;
    char q;

    q = S_LOOPTIME + 52 / n;

    while (q-->0)
    {
        sum += DELTA;
        e = sum >> 2 & 3;

        for (p=0; p<(n-1); p++)
        {
            y = v[p + 1];
            z = v[p] += MX;
        }
        y = v[0];
        z = v[n - 1] += MX;
    }
}

/*<FUNC+>**********************************************************************/
/* 函数名称: TEA_DecrpytCore                                                  */
/* 功能描述: XXTEA解密核心函数                                                */
/* 输入参数: block_size --- 块大小                                            */
/*           buf --- 指向解密数据的指针                                       */
/*           key --- 指向密钥的指针                                           */
/* 输出参数: 无                                                               */
/* 返 回 值: static void                                                      */
/* 操作流程:                                                                  */
/* 其它说明: 无                                                               */
/* 修改记录:                                                                  */
/* -------------------------------------------------------------------------- */
/*     2018-03-31              V1.0          maag          创建函数           */
/*<FUNC->**********************************************************************/
static void TEA_DecrpytCore(int block_size, int *buf, int *key)
{
    char  n   = block_size /4;
    long *v   = (long*)buf;
    long *k   = (long*)key;
    long  z   = v[n -1];
    long  y   = v[0];
    long  sum = 0;
    long  e;
    unsigned char p;
    unsigned char q;

    q = S_LOOPTIME + 52 / n;
    sum = q * DELTA;

    while (sum !=0)
    {
        e = sum >> 2 & 3;

        for (p=(n -1); p>0; p--)
        {
            z = v[p - 1];
            y = v[p] -= MX;
        }
        z = v[n - 1];
        y = v[0] -= MX;
        sum -= DELTA;
    }
}

#endif
