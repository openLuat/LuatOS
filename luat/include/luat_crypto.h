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

/* MD type constants — 与 MBEDTLS_MD_* 枚举值一致 */
#define LUAT_CRYPTO_MD_MD5    0x03
#define LUAT_CRYPTO_MD_SHA1   0x05
#define LUAT_CRYPTO_MD_SHA224 0x08
#define LUAT_CRYPTO_MD_SHA256 0x09
#define LUAT_CRYPTO_MD_SHA384 0x0a
#define LUAT_CRYPTO_MD_SHA512 0x0b
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

// 返回是 0 或者 -1
int luat_crypto_md(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len);
// 返回值是 -1 或者 hash长度
int luat_crypto_md_v2(const char* md, const char* str, size_t str_size, void* out_ptr, const char* key, size_t key_len);
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
    uint8_t tag[16];
    uint8_t tag_len;
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
uint16_t luat_crc16(const void *data, uint32_t len, uint16_t start, uint16_t final, uint16_t poly, uint8_t is_reverse);

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

uint8_t luat_crc7(const uint8_t* message, int length, uint8_t CRCPoly, uint8_t CRC);

/**
 * @brief 使用PK私钥签名(支持RSA/EC等, 自动识别PEM或DER格式)
 * @param md_type  hash算法类型, 取 MBEDTLS_MD_* 枚举值, 例如 MBEDTLS_MD_SHA256(=6)
 * @param hash     已计算好的hash值
 * @param hash_len hash长度
 * @param privkey  私钥数据(PEM或DER二进制)
 * @param privkey_len 私钥数据长度
 * @param password 私钥密码(加密PEM时使用), 可为NULL
 * @param pwd_len  密码长度
 * @param sig_out  输出: 堆上分配的签名数据, 调用方负责释放
 * @param sig_len_out 输出: 签名数据长度
 * @return 0成功, 非0失败
 */
int luat_crypto_pk_sign(int md_type,
                        const uint8_t *hash, size_t hash_len,
                        const uint8_t *privkey, size_t privkey_len,
                        const char *password, size_t pwd_len,
                        uint8_t **sig_out, size_t *sig_len_out);

/**
 * @brief 使用PK公钥验签(支持RSA/EC等, 自动识别PEM或DER格式)
 * @param md_type  hash算法类型, 取 MBEDTLS_MD_* 枚举值, 例如 MBEDTLS_MD_SHA256(=6)
 * @param hash     已计算好的hash值
 * @param hash_len hash长度
 * @param pubkey   公钥数据(PEM或DER二进制)
 * @param pubkey_len 公钥数据长度
 * @param sig      签名数据
 * @param sig_len  签名长度
 * @return 0验签成功, 非0失败
 */
int luat_crypto_pk_verify(int md_type,
                          const uint8_t *hash, size_t hash_len,
                          const uint8_t *pubkey, size_t pubkey_len,
                          const uint8_t *sig, size_t sig_len);

/**
 * @brief 获取密钥类型字符串("rsa"/"ec"/"ecdsa"等)
 * @param key       密钥数据(PEM或DER二进制)
 * @param key_len   密钥数据长度
 * @param is_private 1=私钥, 0=公钥
 * @return 类型字符串(静态常量), 失败返回NULL
 */
const char* luat_crypto_pk_type(const uint8_t *key, size_t key_len, int is_private);

/**
 * @brief 生成密钥对(RSA或EC), 以PEM格式输出
 * @param key_type    "rsa" 或 "ec"
 * @param param       RSA时为位数(1024/2048/4096), EC时为曲线名("P-256"/"P-384"/"P-521")
 * @param priv_pem    输出: 堆上分配的私钥PEM字符串(含NUL), 调用方负责释放
 * @param priv_len    输出: 私钥PEM长度(不含NUL)
 * @param pub_pem     输出: 堆上分配的公钥PEM字符串(含NUL), 调用方负责释放
 * @param pub_len     输出: 公钥PEM长度(不含NUL)
 * @return 0成功, 非0失败
 */
int luat_crypto_pk_generate(const char *key_type,
                            const char *param,
                            uint8_t **priv_pem, size_t *priv_len,
                            uint8_t **pub_pem,  size_t *pub_len);

#endif
