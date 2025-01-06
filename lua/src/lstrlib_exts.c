/*
@module  string
@summary 字符串操作函数
@tag LUAT_USE_GPIO
@demo    string
*/
#include "luat_base.h"
#include "luat_mem.h"
#include "lua.h"
#include "lauxlib.h"

#define LUAT_LOG_TAG "str"
#include "luat_log.h"

/* }====================================================== */
#define IsHex(c)      (((c >= 'a') && (c <= 'f')) || ((c >= 'A') && (c <= 'F')))
#define IsDigit(c)        ((c >= '0') && (c <= '9'))

static const unsigned char hexchars[] = "0123456789ABCDEF";
void luat_str_tohexwithsep(const char* str, size_t len, const char* separator, size_t len_j, char* buff) {
  for (size_t i = 0; i < len; i++)
  {
    char ch = *(str+i);
    buff[i*(2+len_j)] = hexchars[(unsigned char)ch >> 4];
    buff[i*(2+len_j)+1] = hexchars[(unsigned char)ch & 0xF];
    for (size_t j = 0; j < len_j; j++){
      buff[i*(2+len_j)+2+j] = separator[j];
    }
  }
}

void luat_str_tohex(const char* str, size_t len, char* buff) {
  luat_str_tohexwithsep(str, len, NULL, 0, buff);
}

void luat_str_fromhex(const char* str, size_t len, char* buff) {
  for (size_t i = 0; i < len/2; i++)
  {
    char a = *(str + i*2);
    char b = *(str + i*2 + 1);
    //printf("%d %c %c\r\n", i, a, b);
    a = (a <= '9') ? a - '0' : (a & 0x7) + 9;
    b = (b <= '9') ? b - '0' : (b & 0x7) + 9;
    buff[i] = (a << 4) + b;
  }
}

size_t luat_str_fromhex_ex(const char* str, size_t len, char* buff) {
	size_t out_len = 0;
	uint8_t temp = 0;
	uint8_t is_full = 0;
	uint8_t a;
	for(size_t i = 0; i < len; i++)
	{
		a = str[i];
		if (IsDigit(a)||IsHex(a))
		{
			if (is_full)
			{
				temp = (temp << 4) + ((a <= '9') ? a - '0' : (a & 0x7) + 9);
				buff[out_len] = (char)temp;
				out_len++;
				temp = 0;
				is_full = 0;
			}
			else
			{
				temp = ((a <= '9') ? a - '0' : (a & 0x7) + 9);
				is_full = 1;
			}
		}
		else
		{
			temp = 0;
			is_full = 0;
		}
	}
	return out_len;
}

/*
将字符串转成HEX
@api string.toHex(str, separator)
@string 需要转换的字符串
@string 分隔符, 默认为""
@return string HEX字符串
@return number HEX字符串的长度
@usage
string.toHex("\1\2\3") --> "010203" 6
string.toHex("123abc") --> "313233616263" 12
string.toHex("123abc", " ") --> "31 32 33 61 62 63 " 12
*/
int l_str_toHex (lua_State *L) {
  size_t len;
  const char *str = luaL_checklstring(L, 1, &len);
  size_t len_j;
  const char *separator = luaL_optlstring(L, 2, "", &len_j);
  luaL_Buffer buff;
  luaL_buffinitsize(L, &buff, (2+len_j)*len);
  luat_str_tohexwithsep(str, len, separator, len_j, buff.b);
  buff.n = len * (2 + len_j);
  luaL_pushresult(&buff);
  lua_pushinteger(L, len*2);
  return 2;
}

/*
将HEX转成字符串
@api string.fromHex(hex)
@string hex,16进制组成的串
@return string 字符串
@usage
string.fromHex("010203")       -->  "\1\2\3"
string.fromHex("313233616263") -->  "123abc"
*/
int l_str_fromHex (lua_State *L) {
  size_t len;
  const char *str = luaL_checklstring(L, 1, &len);
  luaL_Buffer buff;
  luaL_buffinitsize(L, &buff, len / 2);
//  luat_str_fromhex((char*)str, len, buff.b);
//  buff.n = len / 2;
  buff.n = luat_str_fromhex_ex(str, len, buff.b);
  luaL_pushresult(&buff);
  return 1;
}

/*
按照指定分隔符分割字符串
@api string.split(str, delimiter, keepEmtry)
@string 输入字符串
@string 分隔符,可选,默认 ","
@bool 是否保留空白片段,默认为false,不保留. 2023.4.11之后的固件可用
@return table 分割后的字符串表
@usage
local tmp = string.split("123,233333,122")
log.info("tmp", json.encode(tmp))
local tmp = ("123,456,789"):split(',') --> {'123','456','789'}
log.info("tmp", json.encode(tmp))

-- 保留空片段, 2023.4.11之后的固件可用
local str = "/tmp//def/1234/"
local tmp = str:split("/", true) 
log.info("str.split", #tmp, json.encode(tmp))
*/
int l_str_split (lua_State *L) {
  size_t len = 0;
  int keepEmtry = 0;
  const char *str = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_newtable(L);
    return 1;
  }

  size_t dlen = 0;
  const char *delimiters = luaL_optlstring(L, 2, ",", &dlen);
  if (dlen < 1) {
    delimiters = ",";
    dlen = 1;
  }
  if (lua_isboolean(L, 3) && lua_toboolean(L, 3)) {
    keepEmtry = 1;
  }
  lua_newtable(L);
  int prev = -1;
  size_t count = 1;
  for (size_t i = 0; i < len; i++)
  {
    // LLOGD("d[%s] [%.*s] %d", delimiters, dlen, str+i, dlen);
    if (!memcmp(delimiters, str+i, dlen)) {
      // LLOGD("match %d %i %d",prev, i, keepEmtry);
      if ((prev+1) != i || (keepEmtry)) {
        lua_pushinteger(L, count);
        lua_pushlstring(L, str + prev + 1, i - prev - 1);
        // LLOGD("add %d [%.*s]", count, i - prev, str+prev);
        lua_settable(L, -3);
        count += 1;
      }
      i += (dlen - 1);
      prev = i;
      if (i == len - 1 && keepEmtry) {
        lua_pushinteger(L, count);
        lua_pushlstring(L, "", 0);
        lua_settable(L, -3);
        break;
      }
    }
    else {
      if (i == len - 1) {
        // 最后一个字符了
        lua_pushinteger(L, count);
        lua_pushlstring(L, str + prev + 1, len - prev - 1);
        lua_settable(L, -3);
      }
    }
  }
  return 1;
}

/*
返回字符串tonumber的转义字符串(用来支持超过31位整数的转换)
@api string.toValue(str)
@string 输入字符串
@return string 转换后的二进制字符串
@return number 转换了多少个字符
@usage
string.toValue("123456") --> "\1\2\3\4\5\6"  6
string.toValue("123abc") --> "\1\2\3\a\b\c"  6
*/
int l_str_toValue (lua_State *L) {
  size_t len = 0,i;
  const char *s = luaL_checklstring(L, 1, &len);
  if(len == 0)//没字符串
  {
    lua_pushlstring(L,NULL,0);
    lua_pushinteger(L,0);
    return 2;
  }
  luaL_Buffer buff;
  luaL_buffinitsize(L, &buff, len);
  char * stemp;
  for(i=0;i<len;i++)
  {
    stemp = (char *)s + i;
    luaL_addchar(&buff, (*stemp>'9'? *stemp+9 : *stemp) & 0x0f);
  }
  luaL_pushresult(&buff);
  lua_pushinteger(L,len);
  return 2;
}

/*
  将字符串进行url编码转换
  @api string.urlEncode("123 abc")
  @string 需要转换的字符串
  @int	mode:url编码的转换标准,
  			-1:自定义标准.为-1时,才会有后面的space和str_check
  			 0:默认标准php
  			 1:RFC3986标准,和默认的相比就是' '的转换方式不一样
  			 这个参数不存在,按0:默认标准php处理
  @int	space:' '空格的处理方式
  			 0:' '转化为'+'
  			 1:' '转换为"%20"
  @string	str_check:不需要转换的字符,组成的字符串
  @return string 返回转换后的字符串
  @usage
  -- 将字符串进行url编码转换
  log.info(string.urlEncode("123 abc+/"))			-->> "123+abc%2B%2F"

  log.info(string.urlEncode("123 abc+/",1))			-->> "123%20abc%2B%2F"

  log.info(string.urlEncode("123 abc+/",-1,1,"/"))	-->> "123%20abc%2B/"
  log.info(string.urlEncode("123 abc+/",-1,0,"/"))	-->> "123+abc%2B/"
  log.info(string.urlEncode("123 abc+/",-1,0,"/ "))	-->> "123 abc%2B/"
*/
int l_str_urlEncode (lua_State *L) {
  int argc = lua_gettop(L);
  int mode = 0;		//转换模式,-1:自定义标准,0:默认标准php,1:RFC3986标准,和默认的相比就是' '的转换方式不一样
  int space = 0;	//0:' '转化为'+', 1:' '转换为"%20"
  size_t len_check = 0;
  const char *str_check = NULL;		//不需要转换的字符
  size_t len = 0;
  const char *str = luaL_checklstring(L, 1, &len);
  if(argc == 1)
  {
  	mode = 0;
  }
  else{
  	mode = luaL_checkinteger(L, 2);
  }
  if(mode == -1)
  {
  	/* 自定义模式 */
  	space = luaL_checkinteger(L, 3);
  	str_check = luaL_checklstring(L, 4, &len_check);
  }
  if(mode == 1)
  {
  	/* RFC3986 */
  	space = 1;
  	str_check = ".-_";
    len_check = 3;
  }
  luaL_Buffer buff;
  luaL_buffinitsize(L, &buff, len + 16);
  if(str_check == NULL)
  {
    str_check = ".-*_";
    len_check = 4;
  }
  for (size_t i = 0; i < len; i++)
  {
    char ch = *(str+i);
    if((ch >= 'A' && ch <= 'Z') ||
  		(ch >= 'a' && ch <= 'z') ||
  		(ch >= '0' && ch <= '9')) {
      luaL_addchar(&buff, ch);
    }
    else {
      char result = 0;
      for(size_t j = 0; j < len_check; j++)
      {
        if(ch == str_check[j])
        {
          result = 1;
          break;
        }
      }
      if(result == 1)
      {
        luaL_addchar(&buff, str[i]);
      }
      else
      {
        if(ch == ' ')
        {
          if(space == 0)
          {
            luaL_addchar(&buff, '+');
            continue;
          }
        }
        luaL_addchar(&buff, '%');
        luaL_addchar(&buff, hexchars[(unsigned char)str[i] >> 4]);
        luaL_addchar(&buff, hexchars[(unsigned char)str[i] & 0x0F]);
      }
    }
  }
  luaL_pushresult(&buff);
  return 1;
}

// ----------------------------------------------------------
//                   Base64
//-----------------------------------------------------------

static const unsigned char base64_enc_map[64] =
{
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
    'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
    'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd',
    'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
    'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '+', '/'
};

static const unsigned char base64_dec_map[128] =
{
    127, 127, 127, 127, 127, 127, 127, 127, 127, 127,
    127, 127, 127, 127, 127, 127, 127, 127, 127, 127,
    127, 127, 127, 127, 127, 127, 127, 127, 127, 127,
    127, 127, 127, 127, 127, 127, 127, 127, 127, 127,
    127, 127, 127,  62, 127, 127, 127,  63,  52,  53,
     54,  55,  56,  57,  58,  59,  60,  61, 127, 127,
    127,  64, 127, 127, 127,   0,   1,   2,   3,   4,
      5,   6,   7,   8,   9,  10,  11,  12,  13,  14,
     15,  16,  17,  18,  19,  20,  21,  22,  23,  24,
     25, 127, 127, 127, 127, 127, 127,  26,  27,  28,
     29,  30,  31,  32,  33,  34,  35,  36,  37,  38,
     39,  40,  41,  42,  43,  44,  45,  46,  47,  48,
     49,  50,  51, 127, 127, 127, 127, 127
};

#define BASE64_SIZE_T_MAX   ( (size_t) -1 ) /* SIZE_T_MAX is not standard */

/*
 * Encode a buffer into base64 format
 */
int luat_str_base64_encode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen )
{
    size_t i, n;
    int C1, C2, C3;
    unsigned char *p;

    if( slen == 0 )
    {
        *olen = 0;
        return( 0 );
    }

    n = slen / 3 + ( slen % 3 != 0 );

    if( n > ( BASE64_SIZE_T_MAX - 1 ) / 4 )
    {
        *olen = BASE64_SIZE_T_MAX;
        return( -1 );
    }

    n *= 4;

    if( ( dlen < n + 1 ) || ( NULL == dst ) )
    {
        *olen = n + 1;
        return( -1 );
    }

    n = ( slen / 3 ) * 3;

    for( i = 0, p = dst; i < n; i += 3 )
    {
        C1 = *src++;
        C2 = *src++;
        C3 = *src++;

        *p++ = base64_enc_map[(C1 >> 2) & 0x3F];
        *p++ = base64_enc_map[(((C1 &  3) << 4) + (C2 >> 4)) & 0x3F];
        *p++ = base64_enc_map[(((C2 & 15) << 2) + (C3 >> 6)) & 0x3F];
        *p++ = base64_enc_map[C3 & 0x3F];
    }

    if( i < slen )
    {
        C1 = *src++;
        C2 = ( ( i + 1 ) < slen ) ? *src++ : 0;

        *p++ = base64_enc_map[(C1 >> 2) & 0x3F];
        *p++ = base64_enc_map[(((C1 & 3) << 4) + (C2 >> 4)) & 0x3F];

        if( ( i + 1 ) < slen )
             *p++ = base64_enc_map[((C2 & 15) << 2) & 0x3F];
        else *p++ = '=';

        *p++ = '=';
    }

    *olen = p - dst;
    *p = 0;

    return( 0 );
}

/*
 * Decode a base64-formatted buffer
 */
#ifndef uint32_t
#define uint32_t unsigned int
#endif
int luat_str_base64_decode( unsigned char *dst, size_t dlen, size_t *olen,
                   const unsigned char *src, size_t slen )
{
    size_t i, n;
    uint32_t j, x;
    unsigned char *p;

    /* First pass: check for validity and get output length */
    for( i = n = j = 0; i < slen; i++ )
    {
        /* Skip spaces before checking for EOL */
        x = 0;
        while( i < slen && src[i] == ' ' )
        {
            ++i;
            ++x;
        }

        /* Spaces at end of buffer are OK */
        if( i == slen )
            break;

        if( ( slen - i ) >= 2 &&
            src[i] == '\r' && src[i + 1] == '\n' )
            continue;

        if( src[i] == '\n' )
            continue;

        /* Space inside a line is an error */
        if( x != 0 )
            return( -2 );

        if( src[i] == '=' && ++j > 2 )
            return( -2 );

        if( src[i] > 127 || base64_dec_map[src[i]] == 127 )
            return( -2 );

        if( base64_dec_map[src[i]] < 64 && j != 0 )
            return( -2 );

        n++;
    }

    if( n == 0 )
    {
        *olen = 0;
        return( 0 );
    }

    /* The following expression is to calculate the following formula without
     * risk of integer overflow in n:
     *     n = ( ( n * 6 ) + 7 ) >> 3;
     */
    n = ( 6 * ( n >> 3 ) ) + ( ( 6 * ( n & 0x7 ) + 7 ) >> 3 );
    n -= j;

    if( dst == NULL || dlen < n )
    {
        *olen = n;
        return( -1 );
    }

   for( j = 3, n = x = 0, p = dst; i > 0; i--, src++ )
   {
        if( *src == '\r' || *src == '\n' || *src == ' ' )
            continue;

        j -= ( base64_dec_map[*src] == 64 );
        x  = ( x << 6 ) | ( base64_dec_map[*src] & 0x3F );

        if( ++n == 4 )
        {
            n = 0;
            if( j > 0 ) *p++ = (unsigned char)( x >> 16 );
            if( j > 1 ) *p++ = (unsigned char)( x >>  8 );
            if( j > 2 ) *p++ = (unsigned char)( x       );
        }
    }

    *olen = p - dst;

    return( 0 );
}

/*
将字符串进行base64编码
@api string.toBase64(str)
@string 需要转换的字符串
@return string 解码后的字符串,如果解码失败会返回空字符串
*/
int l_str_toBase64(lua_State *L) {
  size_t len = 0;
  const char* str = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_pushstring(L, "");
    return 1;
  }
  luaL_Buffer buff = {0};
  luaL_buffinitsize(L, &buff, len * 1.5 + 1);
  size_t olen = 0;
  int re = luat_str_base64_encode((unsigned char *)buff.b, buff.size, &olen, (const unsigned char * )str, len);
  if (re == 0) {
    luaL_pushresultsize(&buff, olen);
    return 1;
  }
  // 编码失败,返回空字符串, 可能性应该是0吧
  lua_pushstring(L, "");
  return 1;
}

/*
将字符串进行base64解码
@api string.fromBase64(str)
@string 需要转换的字符串
@return string 解码后的字符串,如果解码失败会返回空字符串
*/
int l_str_fromBase64(lua_State *L) {
  size_t len = 0;
  const char* str = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_pushstring(L, "");
    return 1;
  }
  luaL_Buffer buff = {0};
  luaL_buffinitsize(L, &buff, len + 1);
  size_t olen = 0;
  int re = luat_str_base64_decode((unsigned char *)buff.b, buff.size, &olen, (const unsigned char * )str, len);
  if (re == 0) {
    luaL_pushresultsize(&buff, olen);
    return 1;
  }
  // 编码失败,返回空字符串, 可能性应该是0吧
  lua_pushstring(L, "");
  return 1;
}

////////////////////////////////////////////
////                 BASE32            /////
////////////////////////////////////////////
// Copyright 2010 Google Inc.
// Author: Markus Gutschke
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

int luat_str_base32_decode(const uint8_t *encoded, uint8_t *result, int bufSize) {
  int buffer = 0;
  int bitsLeft = 0;
  int count = 0;
  for (const uint8_t *ptr = encoded; count < bufSize && *ptr; ++ptr) {
    uint8_t ch = *ptr;
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' || ch == '-') {
      continue;
    }
    buffer <<= 5;

    // Deal with commonly mistyped characters
    if (ch == '0') {
      ch = 'O';
    } else if (ch == '1') {
      ch = 'L';
    } else if (ch == '8') {
      ch = 'B';
    }

    // Look up one base32 digit
    if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z')) {
      ch = (ch & 0x1F) - 1;
    } else if (ch >= '2' && ch <= '7') {
      ch -= '2' - 26;
    } else {
      return -1;
    }

    buffer |= ch;
    bitsLeft += 5;
    if (bitsLeft >= 8) {
      result[count++] = buffer >> (bitsLeft - 8);
      bitsLeft -= 8;
    }
  }
  if (count < bufSize) {
    result[count] = '\000';
  }
  return count;
}

int luat_str_base32_encode(const uint8_t *data, int length, uint8_t *result,
                  int bufSize) {
  if (length < 0 || length > (1 << 28)) {
    return -1;
  }
  int count = 0;
  if (length > 0) {
    int buffer = data[0];
    int next = 1;
    int bitsLeft = 8;
    while (count < bufSize && (bitsLeft > 0 || next < length)) {
      if (bitsLeft < 5) {
        if (next < length) {
          buffer <<= 8;
          buffer |= data[next++] & 0xFF;
          bitsLeft += 8;
        } else {
          int pad = 5 - bitsLeft;
          buffer <<= pad;
          bitsLeft += pad;
        }
      }
      int index = 0x1F & (buffer >> (bitsLeft - 5));
      bitsLeft -= 5;
      result[count++] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"[index];
    }
  }
  if (count < bufSize) {
    result[count] = '\000';
  }
  return count;
}

/*
将字符串进行base32编码
@api string.toBase32(str)
@string 需要转换的字符串
@return string 解码后的字符串,如果解码失败会返回0长度字符串
*/
int l_str_toBase32(lua_State *L) {
  size_t len = 0;
  const char* str = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_pushstring(L, "");
    return 1;
  }
  luaL_Buffer buff = {0};
  luaL_buffinitsize(L, &buff, len * 2);
  int rl = luat_str_base32_encode((const uint8_t * )str,len,(uint8_t *)buff.b,buff.size);
  luaL_pushresultsize(&buff, rl);
  return 1;
}

/*
将字符串进行base32解码
@api string.fromBase32(str)
@string 需要转换的字符串
@return string 解码后的字符串,如果解码失败会返回0长度字符串
*/
int l_str_fromBase32(lua_State *L) {
  size_t len = 0;
  const char* str = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_pushstring(L, "");
    return 1;
  }
  luaL_Buffer buff = {0};
  luaL_buffinitsize(L, &buff, len + 1);
  int rl = luat_str_base32_decode((const uint8_t * )str,(uint8_t *)buff.b,buff.size);
  if (rl > 0 && rl <= len + 1) {
    luaL_pushresultsize(&buff, rl);
  }
  else {
    lua_pushstring(L, "");
  }

  return 1;
}

/*
判断字符串前缀
@api string.startsWith(str, prefix)
@string 需要检查的字符串
@string 前缀字符串
@return bool 真为true, 假为false
@usage
local str = "abc"
log.info("str", str:startsWith("a"))
log.info("str", str:startsWith("b"))
*/
int l_str_startsWith(lua_State *L) {
  size_t str_len = 0;
  size_t prefix_len = 0;
  const char* str = luaL_checklstring(L, 1, &str_len);
  const char* prefix = luaL_checklstring(L, 2, &prefix_len);

  if (str_len < prefix_len) {
    lua_pushboolean(L, 0);
  }
  else if (memcmp(str, prefix, prefix_len) == 0) {
    lua_pushboolean(L, 1);
  }
  else {
    lua_pushboolean(L, 0);
  }
  return 1;
}

/*
判断字符串后缀
@api string.endsWith(str, suffix)
@string 需要检查的字符串
@string 后缀字符串
@return bool 真为true, 假为false
@usage
local str = "abc"
log.info("str", str:endsWith("c"))
log.info("str", str:endsWith("b"))
*/
int l_str_endsWith(lua_State *L) {
  size_t str_len = 0;
  size_t suffix_len = 0;
  const char* str = luaL_checklstring(L, 1, &str_len);
  const char* suffix = luaL_checklstring(L, 2, &suffix_len);

  // LLOGD("%s %d : %s %d", str, str_len, suffix, suffix_len);

  if (str_len < suffix_len) {
    lua_pushboolean(L, 0);
  }
  else if (memcmp(str + (str_len - suffix_len), suffix, suffix_len) == 0) {
    lua_pushboolean(L, 1);
  }
  else {
    lua_pushboolean(L, 0);
  }
  return 1;
}

#include "lstate.h"

int l_str_strs(lua_State *L) {
  for (size_t i = 0; i < STRCACHE_N; i++)
  {
    TString **p = G(L)->strcache[i];
    for (size_t j = 0; j < STRCACHE_M; j++) {
      if (p[j]->tt == LUA_TSHRSTR)
        LLOGD(">> %s", getstr(p[j]));
    }
  }
  return 0;
}

int l_str_trim_impl(lua_State *L, int ltrim, int rtrim) {
  size_t str_len = 0;
  const char* str = luaL_checklstring(L, 1, &str_len);
  if (str_len == 0) {
    lua_pushvalue(L, 1);
    return 1;
  }
  int begin = 0;
  int end = str_len;
  if (ltrim) {
    for (; begin <= end; begin++)
    {
      //LLOGD("ltrim %02X %d %d", str[begin], begin, end);
      if(str[begin] != ' '  && 
         str[begin] != '\t' && 
         str[begin] != '\n' && 
         str[begin] != '\r')
      {
        break;
      }
    }
  }
  if (rtrim) {
    for (; begin < end; end--)
    {
      //LLOGD("rtrim %02X %d %d", str[end], begin, end);
      if(str[end - 1] != ' '  && 
         str[end - 1] != '\t' &&  
         str[end - 1] != '\n' &&  
         str[end - 1] != '\r')
      {
        break;
      }
    }
  }
  if (begin == end) {
    lua_pushliteral(L, "");
  }
  else {
    lua_pushlstring(L, str + begin, end - begin);
  }
  return 1;
}

/*
裁剪字符串,去除头尾的空格
@api string.trim(str, ltrim, rtrim)
@string 需要处理的字符串
@bool 清理前缀,默认为true
@bool 清理后缀,默认为true
@return string 清理后的字符串
@usage
local str = "\r\nabc\r\n"
log.info("str", string.trim(str)) -- 打印 "abc"
log.info("str", str:trim())       -- 打印 "abc"
log.info("str", #string.trim(str, false, true)) -- 仅裁剪后缀,所以长度是5
*/
int l_str_trim(lua_State *L) {
  int ltrim = 1;
  int rtrim = 1;
  if (lua_isboolean(L, 2))
    ltrim = lua_toboolean(L, 2);
  if (lua_isboolean(L, 3))
    rtrim = lua_toboolean(L, 3);

  return l_str_trim_impl(L, ltrim, rtrim);
}
