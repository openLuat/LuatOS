
#ifndef LUAT_STR_H
#define LUAT_STR_H
#include "string.h"

void luat_str_tohexwithsep(const char* str, size_t len, char* separator, size_t len_j, char* buff);
void luat_str_tohex(const char* str, size_t len, char* buff);
void luat_str_fromhex(const char* str, size_t len, char* buff);

int luat_str_base64_encode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );
int luat_str_base64_decode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen );

int luat_str_base32_decode(const uint8_t *encoded, uint8_t *result, int bufSize);
int luat_str_base32_encode(const uint8_t *data, int length, uint8_t *result,int bufSize);

#endif
