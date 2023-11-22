/*
@module  pack
@summary 打包和解包格式串
@version 1.0
@date    2021.12.20
@video https://www.bilibili.com/video/BV1Sr4y1n7bP
@tag LUAT_USE_PACK
@usage
--[[
 '<' 设为小端编码 
 '>' 设为大端编码 
 '=' 大小端遵循本地设置 
 'z' 空字符串,0字节
 'a' size_t字符串,前4字节表达长度,然后接着是N字节的数据
 'A' 指定长度字符串, 例如A8, 代表8字节的数据
 'f' float, 4字节
 'd' double , 8字节
 'n' Lua number , 32bit固件4字节, 64bit固件8字节
 'c' char , 1字节
 'b' byte = unsigned char  , 1字节
 'h' short  , 2字节
 'H' unsigned short  , 2字节
 'i' int  , 4字节
 'I' unsigned int , 4字节
 'l' long , 8字节, 仅64bit固件能正确获取
 'L' unsigned long , 8字节, 仅64bit固件能正确获取
]]

-- 详细用法请查看demo
*/

#define	OP_ZSTRING	      'z'		/* zero-terminated string */
#define	OP_BSTRING	      'p'		/* string preceded by length byte */
#define	OP_WSTRING	      'P'		/* string preceded by length word */
#define	OP_SSTRING	      'a'		/* string preceded by length size_t */
#define	OP_STRING	      'A'		/* string */
#define	OP_FLOAT	         'f'		/* float */
#define	OP_DOUBLE	      'd'		/* double */
#define	OP_NUMBER	      'n'		/* Lua number */
#define	OP_CHAR		      'c'		/* char */
#define	OP_BYTE		      'b'		/* byte = unsigned char */
#define	OP_SHORT	         'h'		/* short */
#define	OP_USHORT	      'H'		/* unsigned short */
#define	OP_INT		      'i'		/* int */
#define	OP_UINT		      'I'		/* unsigned int */
#define	OP_LONG		      'l'		/* long */
#define	OP_ULONG	         'L'		/* unsigned long */
#define	OP_LITTLEENDIAN	'<'		/* little endian */
#define	OP_BIGENDIAN	   '>'		/* big endian */
#define	OP_NATIVE	      '='		/* native endian */

#include <ctype.h>
#include <string.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#define LUAT_LOG_TAG "pack"
#include "luat_log.h"

static void badcode(lua_State *L, int c)
{
 char s[]="bad code `?'";
 s[sizeof(s)-3]=c;
 luaL_argerror(L,1,s);
}

static int doendian(int c)
{
 int x=1;
 int e=*(char*)&x;
 if (c==OP_LITTLEENDIAN) return !e;
 if (c==OP_BIGENDIAN) return e;
 if (c==OP_NATIVE) return 0;
 return 0;
}

static void doswap(int swap, void *p, size_t n)
{
 if (swap)
 {
  char *a=p;
  int i,j;
  for (i=0, j=n-1, n=n/2; n--; i++, j--)
  {
   char t=a[i]; a[i]=a[j]; a[j]=t;
  }
 }
}

#define UNPACKNUMBER(OP,T)		\
   case OP:				\
   {					\
    T a;				\
    int m=sizeof(a);			\
    if (i+m>len) goto done;		\
    memcpy(&a,s+i,m);			\
    i+=m;				\
    doswap(swap,&a,m);			\
    lua_pushnumber(L,(lua_Number)a);	\
    ++n;				\
    break;				\
   }

#define UNPACKINT(OP,T)		\
   case OP:				\
   {					\
    T a;				\
    int m=sizeof(a);			\
    if (i+m>len) goto done;		\
    memcpy(&a,s+i,m);			\
    i+=m;				\
    doswap(swap,&a,m);			\
    lua_pushinteger(L,(lua_Integer)a);	\
    ++n;				\
    break;				\
   }

#define UNPACKINT8(OP,T)		\
   case OP:				\
   {					\
    T a;				\
    int m=sizeof(a);			\
    if (i+m>len) goto done;		\
    memcpy(&a,s+i,m);			\
    i+=m;				\
    doswap(swap,&a,m);			\
    int t = (a & 0x80)?(0xffffff00+a):a;\
    lua_pushinteger(L,(lua_Integer)t);	\
    ++n;				\
    break;				\
   }

#define UNPACKSTRING(OP,T)		\
   case OP:				\
   {					\
    T l;				\
    int m=sizeof(l);			\
    if (i+m>len) goto done;		\
    memcpy(&l,s+i,m);			\
    doswap(swap,&l,m);			\
    if (i+m+l>len) goto done;		\
    i+=m;				\
    lua_pushlstring(L,s+i,l);		\
    i+=l;				\
    ++n;				\
    break;				\
   }

/*
解包字符串
@api pack.unpack( string, format, init)
@string 需解包的字符串
@string 格式化符号
@int 默认值为1，标记解包开始的位置
@return int 字符串标记的位置
@return any 第一个解包的值, 根据format值,可能有N个返回值
@usage
local _,a = pack.unpack(x,">h") --解包成short (2字节)
*/
static int l_unpack(lua_State *L) 
{
 size_t len;
 const char *s=luaL_checklstring(L,1,&len);
 const unsigned char *f= (const unsigned char*)luaL_checkstring(L,2);
 int i=luaL_optnumber(L,3,1)-1;
 int n=0;
 int swap=0;
 lua_pushnil(L);
 while (*f)
 {
  int c=*f++;
  int N=1;
  if (isdigit(*f)) 
  {
   N=0;
   while (isdigit(*f)) N=10*N+(*f++)-'0';
   if (N==0 && c==OP_STRING) { lua_pushliteral(L,""); ++n; }
  }
  while (N--) {
   if (!lua_checkstack(L, n))
    return luaL_error(L, "too many results to unpack");
   switch (c)
   {
      
      case OP_LITTLEENDIAN:
      case OP_BIGENDIAN:
      case OP_NATIVE:
      {
      swap=doendian(c);
      N=0;
      break;
      }
      case OP_STRING:
      {
      ++N;
      if (i+N>len) goto done;
      lua_pushlstring(L,s+i,N);
      i+=N;
      ++n;
      N=0;
      break;
      }
      case OP_ZSTRING:
      {
      size_t l;
      if (i>=len) goto done;
      l=strlen(s+i);
      lua_pushlstring(L,s+i,l);
      i+=l+1;
      ++n;
      break;
      }
      UNPACKSTRING(OP_BSTRING, unsigned char)
      UNPACKSTRING(OP_WSTRING, unsigned short)
      UNPACKSTRING(OP_SSTRING, size_t)
      UNPACKNUMBER(OP_NUMBER, lua_Number)
   #ifndef LUA_NUMBER_INTEGRAL   
      UNPACKNUMBER(OP_DOUBLE, double)
      UNPACKNUMBER(OP_FLOAT, float)
   #endif   
      UNPACKINT8(OP_CHAR, char)
      UNPACKINT(OP_BYTE, unsigned char)
      UNPACKINT(OP_SHORT, short)
      UNPACKINT(OP_USHORT, unsigned short)
      UNPACKINT(OP_INT, int)
      UNPACKINT(OP_UINT, unsigned int)
      UNPACKINT(OP_LONG, long)
      UNPACKINT(OP_ULONG, unsigned long)
      case ' ': case ',':
      break;
      default:
      badcode(L,c);
      break;
   }
  }
 }
done:
 lua_pushnumber(L,i+1);
 lua_replace(L,-n-2);
 return n+1;
}

#define PACKNUMBER(OP,T)			\
   case OP:					\
   {						\
    T a=(T)luaL_checknumber(L,i++);		\
    doswap(swap,&a,sizeof(a));			\
    luaL_addlstring(&b,(void*)&a,sizeof(a));	\
    break;					\
   }

#define PACKINT(OP,T)			\
   case OP:					\
   {						\
    T a=(T)luaL_checkinteger(L,i++);		\
    doswap(swap,&a,sizeof(a));			\
    luaL_addlstring(&b,(void*)&a,sizeof(a));	\
    break;					\
   }

#define PACKSTRING(OP,T)			\
   case OP:					\
   {						\
    size_t l;					\
    const char *a=luaL_checklstring(L,i++,&l);	\
    T ll=(T)l;					\
    doswap(swap,&ll,sizeof(ll));		\
    luaL_addlstring(&b,(void*)&ll,sizeof(ll));	\
    luaL_addlstring(&b,a,l);			\
    break;					\
   }

/*
打包字符串的值
@api pack.pack( format, val1, val2, val3, valn )
@string format 格式化符号
@any 第一个需打包的值
@any 第二个需打包的值
@any 第二个需打包的值
@any 第n个需打包的值
@return string 一个包含所有格式化变量的字符串
@usage
local data = pack.pack('<h', crypto.crc16("MODBUS", val))
log.info("data", data, data:toHex())
*/
static int l_pack(lua_State *L)
{
 int i=2;
 const unsigned char *f=(const unsigned char*)luaL_checkstring(L,1);
 int swap=0;
 luaL_Buffer b;
 luaL_buffinit(L,&b);
 while (*f)
 {
  int c=*f++;
  int N=1;
  if (isdigit(*f)) 
  {
   N=0;
   while (isdigit(*f)) N=10*N+(*f++)-'0';
  }
  while (N--) switch (c)
  {
   case OP_LITTLEENDIAN:
   case OP_BIGENDIAN:
   case OP_NATIVE:
   {
    swap=doendian(c);
    N=0;
    break;
   }
   case OP_STRING:
   case OP_ZSTRING:
   {
    size_t l;
    const char *a=luaL_checklstring(L,i++,&l);
    luaL_addlstring(&b,a,l+(c==OP_ZSTRING));
    break;
   }
   PACKSTRING(OP_BSTRING, unsigned char)
   PACKSTRING(OP_WSTRING, unsigned short)
   PACKSTRING(OP_SSTRING, size_t)
   PACKNUMBER(OP_NUMBER, lua_Number)
#ifndef LUA_NUMBER_INTEGRAL   
   PACKNUMBER(OP_DOUBLE, double)
   PACKNUMBER(OP_FLOAT, float)
#endif
   PACKINT(OP_CHAR, char)
   PACKINT(OP_BYTE, unsigned char)
   PACKINT(OP_SHORT, short)
   PACKINT(OP_USHORT, unsigned short)
   PACKINT(OP_INT, int)
   PACKINT(OP_UINT, unsigned int)
   PACKINT(OP_LONG, long)
   PACKINT(OP_ULONG, unsigned long)
   case ' ': case ',':
    break;
   default:
    badcode(L,c);
    break;
  }
 }
 luaL_pushresult(&b);
 return 1;
}

int luat_pack(lua_State *L) {
   return l_pack(L);
}

int luat_unpack(lua_State *L) {
   return l_unpack(L);
}

#include "rotable2.h"
static const rotable_Reg_t reg_pack[] =
{
	{"pack",	   ROREG_FUNC(l_pack)},
	{"unpack",	ROREG_FUNC(l_unpack)},
	{NULL,	   ROREG_INT(0) }
};

LUAMOD_API int luaopen_pack( lua_State *L ) {
    luat_newlib2(L, reg_pack);
    return 1;
}
