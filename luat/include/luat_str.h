
#ifndef LUAT_STR_H
#define LUAT_STR_H
#include "string.h"

void luat_str_tohexwithsep(const char* str, size_t len, char* separator, size_t len_j, char* buff);
void luat_str_tohex(const char* str, size_t len, char* buff);
void luat_str_fromhex(const char* str, size_t len, char* buff);
void luat_str_ucs2_to_char(char* source, size_t size, char* dst2, size_t* outlen);

int luat_str_base64_encode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );
int luat_str_base64_decode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );

int luat_str_base32_decode(const uint8_t *encoded, uint8_t *result, int bufSize);
int luat_str_base32_encode(const uint8_t *data, int length, uint8_t *result,int bufSize);

/**
 * @brief 将 UTF-8 字符串转换为 UCS2(大端)字节流, 每个码点固定 2 字节
 * @param source     输入 UTF-8 字符串, 支持 1/2/3 字节序列(即 BMP 内的码点)
 * @param source_len 输入字节长度
 * @param dst        输出缓冲区
 * @param dstlen     输出缓冲区大小(字节)
 * @param outlen     输出: 实际写入的字节数
 * @return 0 成功; -1 失败(输出缓冲区不足, 或输入含 4 字节序列/非法/被截断的 UTF-8 序列)
 */
int luat_str_utf8_to_ucs2(const char* source, size_t source_len, char* dst, size_t dstlen, size_t* outlen);

#endif
