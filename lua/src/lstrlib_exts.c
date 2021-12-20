/*
@module  string
@summary 字符串操作函数
*/
#include "luat_base.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"

#define LUAT_LOG_TAG "str"
#include "luat_log.h"

/* }====================================================== */

static unsigned char hexchars[] = "0123456789ABCDEF";
void luat_str_tohex(char* str, size_t len, char* buff) {
  for (size_t i = 0; i < len; i++)
  {
    char ch = *(str+i);
    buff[i*2] = hexchars[(unsigned char)ch >> 4];
    buff[i*2+1] = hexchars[(unsigned char)ch & 0xF];
  }
}
void luat_str_fromhex(char* str, size_t len, char* buff) {
  for (size_t i = 0; i < len/2; i++)
  {
    char a = *(str + i*2);
    char b = *(str + i*2 + 1);
    //printf("%d %c %c\r\n", i, a, b);
    a = (a <= '9') ? a - '0' : (a & 0x7) + 9;
    b = (b <= '9') ? b - '0' : (b & 0x7) + 9;
    if (a >=0 && b >= 0)
      buff[i] = (a << 4) + b;
  }
}
/*
将字符串转成HEX
@api string.toHex(str)
@string 需要转换的字符串
@return string HEX字符串
@return number HEX字符串的长度
@usage
string.toHex("\1\2\3") --> "010203" 3
string.toHex("123abc") --> "313233616263" 6
string.toHex("123abc"," ") --> "31 32 33 61 62 63 " 6
*/
int l_str_toHex (lua_State *L) {
  size_t len;
  const char *str = luaL_checklstring(L, 1, &len);
  luaL_Buffer buff;
  luaL_buffinitsize(L, &buff, 2*len);
  luat_str_tohex((char*)str, len, buff.b);
  buff.n = len * 2;
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
  luat_str_fromhex((char*)str, len, buff.b);
  buff.n = len / 2;
  luaL_pushresult(&buff);
  return 1;
}

/*
按照指定分隔符分割字符串
@api string.split(str, delimiter)
@string 输入字符串
@string 分隔符
@return table 分割后的字符串表
@usage
("123,456,789"):split(',') --> {'123','456','789'}
*/
int l_str_split (lua_State *L) {
  size_t len = 0;
  const char *tmp = luaL_checklstring(L, 1, &len);
  if (len == 0) {
    lua_newtable(L);
    return 1;
  }

  size_t dlen = 0;
  const char *delimiters = luaL_checklstring(L, 2, &dlen);
  if (dlen < 1) {
    delimiters = ",";
  }

  // 因为strtok会修改字符串, 所以需要把str临时拷贝一份
  char* str = (char*)luat_heap_malloc(len + 1);
  char* ptr = str;
  if (str == NULL) {
    lua_newtable(L);
    LLOGW("out of memory when split");
    return 1;
  }
  memset(str, 0, len + 1);
  memcpy(str, tmp, len);

  char *token;
  size_t count = 0;
  token = strtok(str, delimiters);
  lua_newtable(L);
  while( token != NULL ) {
    lua_pushnumber(L,count+1);
    lua_pushstring(L, token);
    lua_settable(L,-3);
    // printf("%s - %ld\n", token, count);
    count ++;
    token = strtok(NULL, delimiters);
  }
  luat_heap_free(ptr);
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
