#ifndef LUAT_CRYPTO_H
#define LUAT_CRYPTO_H
#include "luat_base.h"

#define LUAT_CRYPTO_AES_ECB 1
#define LUAT_CRYPTO_AES_CBC 2
#define LUAT_CRYPTO_AES_CTR 3
#define LUAT_CRYPTO_AES_CFB 4
#define LUAT_CRYPTO_AES_OFB 5

#define LUAT_CRYPTO_AES_PAD_ZERO 1
#define LUAT_CRYPTO_AES_PAD_5 2
#define LUAT_CRYPTO_AES_PAD_7 3

typedef struct
{
    size_t result_size;
    size_t key_len;
	void* ctx;
}luat_crypt_stream_t;
/**
 * @defgroup luatos_crypto crypto数据加密
 * @{
 */
/**
 * @brief 生成随机数
 * 
 * @param buff 随机数保存内存
 * @param len 长度
 * @return int
 */
int luat_crypto_trng(char* buff, size_t len);
/// @brief 计算md5值
/// @param str 需要计算的字符串
/// @param str_size  需要计算的字符串的长度
/// @param out_ptr 输出
/// @return 成功0，失败-1
int luat_crypto_md5_simple(const char* str, size_t str_size, void* out_ptr);
/// @brief 计算hmac_md5值
/// @param str 需要计算的字符串
/// @param str_size 字符串长度
/// @param mac 密钥
/// @param mac_size 密钥的长度
/// @param out_ptr 输出
/// @return 成功0，失败-1
int luat_crypto_hmac_md5_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);

/// @brief 计算sha1值
/// @param str  需要计算的字符串
/// @param str_size 需要计算的字符串的长度
/// @param out_ptr 输出
/// @return  成功0，失败-1
int luat_crypto_sha1_simple(const char* str, size_t str_size, void* out_ptr);
/// @brief 计算hmac_sha1值
/// @param str 需要计算的字符串
/// @param str_size 字符串长度
/// @param mac 密钥
/// @param mac_size 密钥的长度
/// @param out_ptr 输出
/// @return 成功0，失败-1
int luat_crypto_hmac_sha1_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr);
/// @brief 计算sha256值
/// @param str  需要计算的字符串
/// @param str_size 需要计算的字符串的长度
/// @param out_ptr 输出
/// @return  成功0，失败-1
int luat_crypto_sha256_simple(const char* str, size_t str_size, void* out_ptr);
/// @brief 计算hmac_sha256值
/// @param str 需要计算的字符串
/// @param str_size 字符串长度
/// @param mac 密钥
/// @param mac_size 密钥的长度
/// @param out_ptr 输出
/// @return 成功0，失败-1
int luat_crypto_hmac_sha256_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) ;
/// @brief 计算sha512值
/// @param str  需要计算的字符串
/// @param str_size 需要计算的字符串的长度
/// @param out_ptr 输出
/// @return  成功0，失败-1
int luat_crypto_sha512_simple(const char* str, size_t str_size, void* out_ptr) ;
/// @brief 计算hmac_sha512值
/// @param str 需要计算的字符串
/// @param str_size 字符串长度
/// @param mac 密钥
/// @param mac_size 密钥的长度
/// @param out_ptr 输出
/// @return 成功0，失败-1
int luat_crypto_hmac_sha512_simple(const char* str, size_t str_size, const char* mac, size_t mac_size, void* out_ptr) ;
/**
 * @brief BASE64加密
 * @param dst buffer
 * @param dlen buffer长度
 * @param olen 写入的字节数
 * @param src 加密密钥
 * @param slen 加密密钥长度
 * @return 0成功
 */
int luat_crypto_base64_encode( unsigned char *dst, size_t dlen, size_t *olen, const unsigned char *src, size_t slen ) ;
/**
 * @brief BASE64解密
 * @param dst buffer
 * @param dlen buffer长度
 * @param olen 写入的字节数
 * @param src 密钥
 * @param slen 密钥长度
 * @return 0成功
 */
int luat_crypto_base64_decode( unsigned char *dst, size_t dlen, size_t *olen, const unsigned char *src, size_t slen ) ;
/**@}*/ 
int luat_crypto_cipher_list(const char** list, size_t* len);
int luat_crypto_cipher_suites(const char** list, size_t* len);

int luat_crypto_md(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len);
int luat_crypto_md_file(const char* md, void* out_ptr, const char* key, size_t key_len, const char* path);

int luat_crypto_md_init(const char* md, const char* key, luat_crypt_stream_t *stream);
int luat_crypto_md_update(const char* str, size_t str_size, luat_crypt_stream_t *stream);
int luat_crypto_md_finish(void* out_ptr, luat_crypt_stream_t *stream);

typedef struct luat_crypto_cipher_ctx
{
    const char* cipher;
    const char* pad;
    const char* str;
    const char* key;
    const char* iv;
    
    size_t cipher_size;
    size_t pad_size;
    size_t str_size;
    size_t key_size;
    size_t iv_size;
    char* outbuff;
    size_t outlen;
    uint8_t flags;
}luat_crypto_cipher_ctx_t;

int luat_crypto_cipher_xxx(luat_crypto_cipher_ctx_t* cctx);

/**
 * @brief crc8通用算法
 * @param data 输入数据
 * @param len 长度
 * @param start 起始值，一般是0
 * @param poly 多项式
 * @param is_reverse 是否逆序计算，顺序从MSB算到LSB，逆序从LSB算到MSB，不清楚的2个都试试
 * @return 输出值
 */
uint8_t luat_crc8(const void *data, uint32_t len, uint8_t start, uint8_t poly, uint8_t is_reverse);

/**
 * @brief crc16通用算法
 * @param data 输入数据
 * @param len 长度
 * @param start 起始值
 * @param poly 多项式
 * @param is_reverse 是否逆序计算，顺序从MSB算到LSB，逆序从LSB算到MSB，不清楚的2个都试试
 * @return 输出值
 */
uint16_t luat_crc16(const void *data, uint32_t len, uint16_t start, uint16_t poly, uint8_t is_reverse);

/**
 * @brief crc32常用算法
 * @param data 输入数据
 * @param len 长度
 * @param start 起始值，一般是0xffffffff
 * @param poly 多项式，一般是0x04C11DB7，填0会自动设置成0x04C11DB7
 * @return 输出值
 */
uint32_t luat_crc32(const void *data, uint32_t len, uint32_t start, uint32_t poly);

// 快速modbus crc16算法
uint16_t luat_crc16_modbus( const uint8_t *buf, uint32_t len);
#endif
