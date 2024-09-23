/*
@module  io
@summary io操作(扩展)
@version 1.0
@date    2020.07.03
@tag LUAT_USE_GPIO
@demo    fs
@usage
-- io模块是lua原生模块,LuatOS增加了一些API
-- 请配合os模块一起使用

-- 只读模式, 打开文件
local fd = io.open("/xxx.txt", "rb")
-- 读写默认,打开文件
local fd = io.open("/xxx.txt", "wb")
-- 写入文件,且截断为0字节
local fd = io.open("/xxx.txt", "wb+")
-- 追加模式
local fd = io.open("/xxx.txt", "a")

-- 若文件打开成功, fd不为nil,否则就是失败了
-- 注意, 刷机时所添加的文件, 均在 /luadb 目录下, 只读
if fd then
  -- 读取指定字节数,如果数据不足,就只返回实际长度的数据
  local data = fd:read(12)
  -- 按行读取
  local line = fd:read("*l")
  -- 全部读取
  local line = fd:read("*a")

  -- 数据写入, 仅w或a模式可调用
  -- 数据需要是字符串, lua的字符串是带长度的,可以包含任何二进制数据
  fd:write("xxxx") 
  -- 以下是写入0x12, 0x13
  fd:write(string.char(0x12, 0x13))

  -- 移动句柄,绝对坐标
  fd:seek(1024, io.SEEK_SET)
  -- 移动句柄,相对坐标
  fd:seek(1024, io.SEEK_CUR)
  -- 移动句柄,反向绝对坐标,从文件结尾往文件头部算
  fd:seek(124, io.SEEK_END)

  -- 执行完操作后,一定要关掉文件
  fd:close()
end
*/

#define liolib_c
#define LUA_LIB

#include "lprefix.h"


#include <ctype.h>
#include <errno.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lua.h"

#include "lauxlib.h"
#include "lualib.h"




/*
** Change this macro to accept other modes for 'fopen' besides
** the standard ones.
*/
#if !defined(l_checkmode)

/* accepted extensions to 'mode' in 'fopen' */
#if !defined(L_MODEEXT)
#define L_MODEEXT	"b"
#endif

/* Check whether 'mode' matches '[rwa]%+?[L_MODEEXT]*' */
static int l_checkmode (const char *mode) {
  return (*mode != '\0' && strchr("rwa", *(mode++)) != NULL &&
         (*mode != '+' || (++mode, 1)) &&  /* skip if char is '+' */
         (strspn(mode, L_MODEEXT) == strlen(mode)));  /* check extensions */
}

#endif

/*
** {======================================================
** l_popen spawns a new process connected to the current
** one through the file streams.
** =======================================================
*/

#if !defined(l_popen)		/* { */

#if defined(LUA_USE_POSIX)	/* { */

#define l_popen(L,c,m)		(fflush(NULL), popen(c,m))
#define l_pclose(L,file)	(pclose(file))

#elif defined(LUA_USE_WINDOWS)	/* }{ */

#define l_popen(L,c,m)		(_popen(c,m))
#define l_pclose(L,file)	(_pclose(file))

#else				/* }{ */

/* ISO C definitions */
#define l_popen(L,c,m)  \
	  ((void)((void)c, m), \
	  luaL_error(L, "'popen' not supported"), \
	  (FILE*)0)
#define l_pclose(L,file)		((void)L, (void)file, -1)

#endif				/* } */

#endif				/* } */

/* }====================================================== */


#if !defined(l_getc)		/* { */

// #if defined(LUA_USE_POSIX)
// #define l_getc(f)		getc_unlocked(f)
// #define l_lockfile(f)		flockfile(f)
// #define l_unlockfile(f)		funlockfile(f)
// #else
int luat_fs_getc(FILE* stream);
#define l_getc(f)		luat_fs_getc(f)
#define l_lockfile(f)		((void)0)
#define l_unlockfile(f)		((void)0)
// #endif

#endif				/* } */


/*
** {======================================================
** l_fseek: configuration for longer offsets
** =======================================================
*/

#if !defined(l_fseek)		/* { */

#if defined(LUA_USE_POSIX)	/* { */

#include <sys/types.h>

#define l_fseek(f,o,w)		fseeko(f,o,w)
#define l_ftell(f)		ftello(f)
#define l_seeknum		off_t

#elif defined(LUA_USE_WINDOWS) && !defined(_CRTIMP_TYPEINFO) \
   && defined(_MSC_VER) && (_MSC_VER >= 1400)	/* }{ */

/* Windows (but not DDK) and Visual C++ 2005 or higher */
#define l_fseek(f,o,w)		_fseeki64(f,o,w)
#define l_ftell(f)		_ftelli64(f)
#define l_seeknum		__int64

#else				/* }{ */

/* ISO C definitions */
#define l_fseek(f,o,w)		fseek(f,o,w)
#define l_ftell(f)		ftell(f)
#define l_seeknum		long

#endif				/* } */

#endif				/* } */

/* }====================================================== */


#define IO_PREFIX	"_IO_"
#define IOPREF_LEN	(sizeof(IO_PREFIX)/sizeof(char) - 1)
#define IO_INPUT	(IO_PREFIX "input")
#define IO_OUTPUT	(IO_PREFIX "output")


typedef luaL_Stream LStream;


#define tolstream(L)	((LStream *)luaL_checkudata(L, 1, LUA_FILEHANDLE))

#define isclosed(p)	((p)->closef == NULL)

#include "luat_fs.h"
#define LUAT_LOG_TAG "io"
#include "luat_log.h"

#undef fopen
#undef fclose
#undef fread
#undef fseek
#undef feof
#undef ferror
#undef fwrite

#define fopen   luat_fs_fopen
#define fclose  luat_fs_fclose
#define fread   luat_fs_fread
#define fseek   luat_fs_fseek
#define ferror  luat_fs_ferror
#define feof    luat_fs_feof
#define fwrite  luat_fs_fwrite
#define ftell   luat_fs_ftell


static int io_type (lua_State *L) {
  LStream *p;
  luaL_checkany(L, 1);
  p = (LStream *)luaL_testudata(L, 1, LUA_FILEHANDLE);
  if (p == NULL)
    lua_pushnil(L);  /* not a file */
  else if (isclosed(p))
    lua_pushliteral(L, "closed file");
  else
    lua_pushliteral(L, "file");
  return 1;
}


static int f_tostring (lua_State *L) {
  LStream *p = tolstream(L);
  if (isclosed(p))
    lua_pushliteral(L, "file (closed)");
  else
    lua_pushfstring(L, "file (%p)", p->f);
  return 1;
}


static FILE *tofile (lua_State *L) {
  LStream *p = tolstream(L);
  if (isclosed(p))
    luaL_error(L, "attempt to use a closed file");
  lua_assert(p->f);
  return p->f;
}


/*
** When creating file handles, always creates a 'closed' file handle
** before opening the actual file; so, if there is a memory error, the
** handle is in a consistent state.
*/
static LStream *newprefile (lua_State *L) {
  LStream *p = (LStream *)lua_newuserdata(L, sizeof(LStream));
  p->closef = NULL;  /* mark file handle as 'closed' */
  luaL_setmetatable(L, LUA_FILEHANDLE);
  return p;
}


/*
** Calls the 'close' function from a file handle. The 'volatile' avoids
** a bug in some versions of the Clang compiler (e.g., clang 3.0 for
** 32 bits).
*/
static int aux_close (lua_State *L) {
  LStream *p = tolstream(L);
  volatile lua_CFunction cf = p->closef;
  p->closef = NULL;  /* mark stream as closed */
  return (*cf)(L);  /* close it */
}


static int f_close (lua_State *L) {
  tofile(L);  /* make sure argument is an open stream */
  return aux_close(L);
}

#ifdef LUA_USE_WINDOWS
static int io_close (lua_State *L) {
  if (lua_isnone(L, 1))  /* no argument? */
    lua_getfield(L, LUA_REGISTRYINDEX, IO_OUTPUT);  /* use standard output */
  return f_close(L);
}
#endif


static int f_gc (lua_State *L) {
  LStream *p = tolstream(L);
  if (!isclosed(p) && p->f != NULL)
    aux_close(L);  /* ignore closed and incompletely open files */
  return 0;
}


/*
** function to close regular files
*/
static int io_fclose (lua_State *L) {
  LStream *p = tolstream(L);
  int res = fclose(p->f);
  return luaL_fileresult(L, (res == 0), NULL);
}


static LStream *newfile (lua_State *L) {
  LStream *p = newprefile(L);
  p->f = NULL;
  p->closef = &io_fclose;
  return p;
}

static void opencheck (lua_State *L, const char *fname, const char *mode) {
  LStream *p = newfile(L);
  p->f = fopen(fname, mode);
  if (p->f == NULL)
    luaL_error(L, "cannot open file '%s' (%d)", fname, errno);
}


static int io_open (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "r");
  LStream *p = newfile(L);
  const char *md = mode;  /* to traverse/check mode */
  luaL_argcheck(L, l_checkmode(md), 2, "invalid mode");
  p->f = fopen(filename, mode);
  return (p->f == NULL) ? luaL_fileresult(L, 0, filename) : 1;
}

#ifdef LUA_USE_WINDOWS
/*
** function to close 'popen' files
*/
static int io_pclose (lua_State *L) {
  LStream *p = tolstream(L);
  int ret = luaL_execresult(L, l_pclose(L, p->f));
  #ifdef LUAT_USE_FS_VFS
  luat_vfs_rm_fd(p->f);
  #endif
  return ret;
}


static int io_popen (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "r");
  LStream *p = newprefile(L);
  p->f = l_popen(L, filename, mode);
  p->closef = &io_pclose;
  #ifdef LUAT_USE_FS_VFS
  if (p->f) {
    FILE* tmp = luat_vfs_add_fd(p->f, NULL);
    if (tmp == NULL) {
      l_pclose(L, p->f);
      p->f = NULL;
      p->closef = NULL;
    }
    else {
      //printf("replace p->f %p => %p\n", p->f, tmp);
      p->f = tmp;
    }
  }
  #endif
  return (p->f == NULL) ? luaL_fileresult(L, 0, filename) : 1;
}

static int io_tmpfile (lua_State *L) {
  LStream *p = newfile(L);
  p->f = tmpfile();
  return (p->f == NULL) ? luaL_fileresult(L, 0, NULL) : 1;
}


static FILE *getiofile (lua_State *L, const char *findex) {
  LStream *p;
  lua_getfield(L, LUA_REGISTRYINDEX, findex);
  p = (LStream *)lua_touserdata(L, -1);
  if (isclosed(p))
    luaL_error(L, "standard %s file is closed", findex + IOPREF_LEN);
  return p->f;
}


static int g_iofile (lua_State *L, const char *f, const char *mode) {
  if (!lua_isnoneornil(L, 1)) {
    const char *filename = lua_tostring(L, 1);
    if (filename)
      opencheck(L, filename, mode);
    else {
      tofile(L);  /* check that it's a valid file handle */
      lua_pushvalue(L, 1);
    }
    lua_setfield(L, LUA_REGISTRYINDEX, f);
  }
  /* return current value */
  lua_getfield(L, LUA_REGISTRYINDEX, f);
  return 1;
}


static int io_input (lua_State *L) {
  return g_iofile(L, IO_INPUT, "r");
}


static int io_output (lua_State *L) {
  return g_iofile(L, IO_OUTPUT, "w");
}

#endif

static int io_readline (lua_State *L);


/*
** maximum number of arguments to 'f:lines'/'io.lines' (it + 3 must fit
** in the limit for upvalues of a closure)
*/
#define MAXARGLINE	250

static void aux_lines (lua_State *L, int toclose) {
  int n = lua_gettop(L) - 1;  /* number of arguments to read */
  luaL_argcheck(L, n <= MAXARGLINE, MAXARGLINE + 2, "too many arguments");
  lua_pushinteger(L, n);  /* number of arguments to read */
  lua_pushboolean(L, toclose);  /* close/not close file when finished */
  lua_rotate(L, 2, 2);  /* move 'n' and 'toclose' to their positions */
  lua_pushcclosure(L, io_readline, 3 + n);
}


static int f_lines (lua_State *L) {
  tofile(L);  /* check that it's a valid file handle */
  aux_lines(L, 0);
  return 1;
}

// static void opencheck (lua_State *L, const char *fname, const char *mode) {
//   LStream *p = newfile(L);
//   p->f = fopen(fname, mode);
//   if (p->f == NULL)
//     luaL_error(L, "cannot open file '%s' (%s)", fname, strerror(errno));
// }

static int io_lines (lua_State *L) {
  int toclose;
  if (lua_isnone(L, 1)) lua_pushnil(L);  /* at least one argument */
  if (lua_isnil(L, 1)) {  /* no file name? */
    lua_getfield(L, LUA_REGISTRYINDEX, IO_INPUT);  /* get default input */
    lua_replace(L, 1);  /* put it at index 1 */
    tofile(L);  /* check that it's a valid file handle */
    toclose = 0;  /* do not close it after iteration */
  }
  else {  /* open a new file */
    const char *filename = luaL_checkstring(L, 1);
    opencheck(L, filename, "r");
    lua_replace(L, 1);  /* put file at index 1 */
    toclose = 1;  /* close it after iteration */
  }
  aux_lines(L, toclose);
  return 1;
}


/*
** {======================================================
** READ
** =======================================================
*/


/* maximum length of a numeral */
#if !defined (L_MAXLENNUM)
#define L_MAXLENNUM     200
#endif


/* auxiliary structure used by 'read_number' */
typedef struct {
  FILE *f;  /* file being read */
  int c;  /* current character (look ahead) */
  int n;  /* number of elements in buffer 'buff' */
  char buff[L_MAXLENNUM + 1];  /* +1 for ending '\0' */
} RN;


/*
** Add current char to buffer (if not out of space) and read next one
*/
// static int nextc (RN *rn) {
//   if (rn->n >= L_MAXLENNUM) {  /* buffer overflow? */
//     rn->buff[0] = '\0';  /* invalidate result */
//     return 0;  /* fail */
//   }
//   else {
//     rn->buff[rn->n++] = rn->c;  /* save current char */
//     rn->c = l_getc(rn->f);  /* read next one */
//     return 1;
//   }
// }


/*
** Accept current char if it is in 'set' (of size 2)
*/
// static int test2 (RN *rn, const char *set) {
//   if (rn->c == set[0] || rn->c == set[1])
//     return nextc(rn);
//   else return 0;
// }


/*
** Read a sequence of (hex)digits
*/
// static int readdigits (RN *rn, int hex) {
//   int count = 0;
//   while ((hex ? isxdigit(rn->c) : isdigit(rn->c)) && nextc(rn))
//     count++;
//   return count;
// }


/*
** Read a number: first reads a valid prefix of a numeral into a buffer.
** Then it calls 'lua_stringtonumber' to check whether the format is
** correct and to convert it to a Lua number
*/
// static int read_number (lua_State *L, FILE *f) {
//   RN rn;
//   int count = 0;
//   int hex = 0;
//   char decp[2];
//   rn.f = f; rn.n = 0;
//   decp[0] = lua_getlocaledecpoint();  /* get decimal point from locale */
//   decp[1] = '.';  /* always accept a dot */
//   l_lockfile(rn.f);
//   do { rn.c = l_getc(rn.f); } while (isspace(rn.c));  /* skip spaces */
//   test2(&rn, "-+");  /* optional signal */
//   if (test2(&rn, "00")) {
//     if (test2(&rn, "xX")) hex = 1;  /* numeral is hexadecimal */
//     else count = 1;  /* count initial '0' as a valid digit */
//   }
//   count += readdigits(&rn, hex);  /* integral part */
//   if (test2(&rn, decp))  /* decimal point? */
//     count += readdigits(&rn, hex);  /* fractional part */
//   if (count > 0 && test2(&rn, (hex ? "pP" : "eE"))) {  /* exponent mark? */
//     test2(&rn, "-+");  /* exponent signal */
//     readdigits(&rn, 0);  /* exponent digits */
//   }
//   ungetc(rn.c, rn.f);  /* unread look-ahead char */
//   l_unlockfile(rn.f);
//   rn.buff[rn.n] = '\0';  /* finish string */
//   if (lua_stringtonumber(L, rn.buff))  /* is this a valid number? */
//     return 1;  /* ok */
//   else {  /* invalid format */
//    lua_pushnil(L);  /* "result" to be removed */
//    return 0;  /* read fails */
//   }
// }


static int test_eof (lua_State *L, FILE *f) {
  return feof(f);
  // int c = getc(f);
  // ungetc(c, f);  /* no-op when c == EOF */
  // lua_pushliteral(L, "");
  // return (c != EOF);
}


static int read_line (lua_State *L, FILE *f, int chop) {
  luaL_Buffer b;
  int c = '\0';
  #define READLINE_BUFF_SIZE (1024)
  luaL_buffinitsize(L, &b, READLINE_BUFF_SIZE);
  // luaL_buffinit(L, &b);
  while (c != EOF && c != '\n') {  /* repeat until end of line */
    char *buff = luaL_prepbuffsize(&b, READLINE_BUFF_SIZE);  /* preallocate buffer */
    int i = 0;
    l_lockfile(f);  /* no memory errors can happen inside the lock */
    while (i < READLINE_BUFF_SIZE && (c = l_getc(f)) != EOF && c != '\n')
      buff[i++] = c;
    l_unlockfile(f);
    luaL_addsize(&b, i);
  }
  if (!chop && c == '\n')  /* want a newline and have one? */
    luaL_addchar(&b, c);  /* add ending newline to result */
  luaL_pushresult(&b);  /* close buffer */
  /* return ok if read something (either a newline or something else) */
  return (c == '\n' || lua_rawlen(L, -1) > 0);
}


static void read_all (lua_State *L, FILE *f) {
  size_t nr;
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  do {  /* read file in chunks of LUAL_BUFFERSIZE bytes */
    char *p = luaL_prepbuffer(&b);
    nr = fread(p, sizeof(char), LUAL_BUFFERSIZE, f);
    luaL_addsize(&b, nr);
  } while (nr == LUAL_BUFFERSIZE);
  luaL_pushresult(&b);  /* close buffer */
}


static int read_chars (lua_State *L, FILE *f, size_t n) {
  size_t nr;  /* number of chars actually read */
  char *p;
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  p = luaL_prepbuffsize(&b, n);  /* prepare buffer to read whole block */
  nr = fread(p, sizeof(char), n, f);  /* try to read 'n' chars */
  luaL_addsize(&b, nr);
  luaL_pushresult(&b);  /* close buffer */
  return (nr > 0);  /* true iff read something */
}


static int g_read (lua_State *L, FILE *f, int first) {
  int nargs = lua_gettop(L) - 1;
  int success;
  int n;
  //clearerr(f);
  if (nargs == 0) {  /* no arguments? */
    success = read_line(L, f, 1);
    n = first+1;  /* to return 1 result */
  }
  else {  /* ensure stack space for all results and for auxlib's buffer */
    luaL_checkstack(L, nargs+LUA_MINSTACK, "too many arguments");
    success = 1;
    for (n = first; nargs-- && success; n++) {
      if (lua_type(L, n) == LUA_TNUMBER) {
        size_t l = (size_t)luaL_checkinteger(L, n);
        success = (l == 0) ? test_eof(L, f) : read_chars(L, f, l);
      }
      else {
        const char *p = luaL_checkstring(L, n);
        if (*p == '*') p++;  /* skip optional '*' (for compatibility) */
        switch (*p) {
          // case 'n':  /* number */
          //   success = read_number(L, f);
          //   break;
          case 'l':  /* line */
            success = read_line(L, f, 1);
            break;
          case 'L':  /* line with end-of-line */
            success = read_line(L, f, 0);
            break;
          case 'a':  /* file */
            read_all(L, f);  /* read entire file */
            success = 1; /* always success */
            break;
          default:
            return luaL_argerror(L, n, "invalid format");
        }
      }
    }
  }
  if (ferror(f))
    return luaL_fileresult(L, 0, NULL);
  if (!success) {
    lua_pop(L, 1);  /* remove last result */
    lua_pushnil(L);  /* push nil instead */
  }
  return n - first;
}

#ifdef LUA_USE_WINDOWS
static int io_read (lua_State *L) {
  return g_read(L, getiofile(L, IO_INPUT), 1);
}
#endif


static int f_read (lua_State *L) {
  return g_read(L, tofile(L), 2);
}


static int io_readline (lua_State *L) {
  LStream *p = (LStream *)lua_touserdata(L, lua_upvalueindex(1));
  int i;
  int n = (int)lua_tointeger(L, lua_upvalueindex(2));
  if (isclosed(p))  /* file is already closed? */
    return luaL_error(L, "file is already closed");
  lua_settop(L , 1);
  luaL_checkstack(L, n, "too many arguments");
  for (i = 1; i <= n; i++)  /* push arguments to 'g_read' */
    lua_pushvalue(L, lua_upvalueindex(3 + i));
  n = g_read(L, p->f, 2);  /* 'n' is number of results */
  lua_assert(n > 0);  /* should return at least a nil */
  if (lua_toboolean(L, -n))  /* read at least one value? */
    return n;  /* return them */
  else {  /* first result is nil: EOF or error */
    if (n > 1) {  /* is there error information? */
      /* 2nd result is error message */
      return luaL_error(L, "%s", lua_tostring(L, -n + 1));
    }
    if (lua_toboolean(L, lua_upvalueindex(3))) {  /* generator created file? */
      lua_settop(L, 0);
      lua_pushvalue(L, lua_upvalueindex(1));
      aux_close(L);  /* close it */
    }
    return 0;
  }
}

/* }====================================================== */


static int g_write (lua_State *L, FILE *f, int arg) {
  int nargs = lua_gettop(L) - arg;
  int status = 1;
  for (; nargs--; arg++) {
    // if (lua_type(L, arg) == LUA_TNUMBER) {
    //   /* optimization: could be done exactly as for strings */
    //   int len = lua_isinteger(L, arg)
    //             ? fprintf(f, LUA_INTEGER_FMT,
    //                          (LUAI_UACINT)lua_tointeger(L, arg))
    //             : fprintf(f, LUA_NUMBER_FMT,
    //                          (LUAI_UACNUMBER)lua_tonumber(L, arg));
    //   status = status && (len > 0);
    // }
    // else {
      size_t l;
      const char *s = luaL_checklstring(L, arg, &l);
      status = status && (fwrite(s, sizeof(char), l, f) == l);
    // }
  }
  if (status) return 1;  /* file handle already on stack top */
  else return luaL_fileresult(L, status, NULL);
}

#ifdef LUA_USE_WINDOWS
static int io_write (lua_State *L) {
  return g_write(L, getiofile(L, IO_OUTPUT), 1);
}
#endif


static int f_write (lua_State *L) {
  FILE *f = tofile(L);
  lua_pushvalue(L, 1);  /* push file at the stack top (to be returned) */
  return g_write(L, f, 2);
}


static int f_seek (lua_State *L) {
  static const int mode[] = {SEEK_SET, SEEK_CUR, SEEK_END};
  static const char *const modenames[] = {"set", "cur", "end", NULL};
  FILE *f = tofile(L);
  int op = luaL_checkoption(L, 2, "cur", modenames);
  lua_Integer p3 = luaL_optinteger(L, 3, 0);
  l_seeknum offset = (l_seeknum)p3;
  luaL_argcheck(L, (lua_Integer)offset == p3, 3,
                  "not an integer in proper range");
  op = l_fseek(f, offset, mode[op]);
  if (op)
    return luaL_fileresult(L, 0, NULL);  /* error */
  else {
    lua_pushinteger(L, (lua_Integer)l_ftell(f));
    return 1;
  }
}


#ifdef LUA_USE_WINDOWS
static int f_setvbuf (lua_State *L) {
  static const int mode[] = {_IONBF, _IOFBF, _IOLBF};
  static const char *const modenames[] = {"no", "full", "line", NULL};
  FILE *f = tofile(L);
  int op = luaL_checkoption(L, 2, NULL, modenames);
  lua_Integer sz = luaL_optinteger(L, 3, LUAL_BUFFERSIZE);
  int res = setvbuf(f, NULL, mode[op], (size_t)sz);
  return luaL_fileresult(L, res == 0, NULL);
}

static int io_flush (lua_State *L) {
  return luaL_fileresult(L, fflush(getiofile(L, IO_OUTPUT)) == 0, NULL);
}
#endif


static int f_flush (lua_State *L) {
#ifdef LUA_USE_WINDOWS
  return luaL_fileresult(L, fflush(tofile(L)) == 0, NULL);
#else
  return 0;
#endif
}

#include "luat_mem.h"

/*
判断文件是否存在
@api io.exists(path)
@string 文件路径
@return bool 存在返回true,否则返回false
@usage
log.info("io", "file exists", io.exists("/boottime"))
 */
static int io_exists (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  FILE* f = fopen(filename, "r");
  lua_pushboolean(L,f != NULL);
  if(f!=NULL)
    fclose(f);
  return 1;
}

/*
获取文件大小
@api io.fileSize(path)
@string 文件路径
@return int 文件数据,若文件不存在会返回nil
@usage
local fsize = io.fileSize("/bootime")
if fsize and fsize > 1024 then
  log.info("io", "file size", fsize)
end
 */
static int io_fileSize (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  FILE* f = fopen(filename, "rb");
  if(f == NULL) {
    lua_pushinteger(L, 0);
  }
  else {
    fseek(f, 0, SEEK_END);
    lua_pushinteger(L,ftell(f));
    fclose(f);
  }
  return 1;
}

/**
读取整个文件,请注意内存消耗
@api io.readFile(path, mode, offset, len)
@string 文件路径
@string 读取模式, 默认 "rb"
@int    起始位置,默认0
@int    读取长度,默认整个文件
@return string 文件数据,若文件不存在会返回nil
@usage
local data = io.readFile("/bootime")
-- 注意: offset和len参数是 2023.6.6添加的
-- 读取abc.txt, 先跳过128字节, 然后读取512字节数据
local data = io.readFile("/abc.txt", "rb", 128, 512)
 */
static int io_readFile (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "rb");
  int offset = luaL_optinteger(L, 3, 0);
  int rlen   = luaL_optinteger(L, 4, 1 << 30);
  FILE* f = fopen(filename, mode);
  if(f == NULL)
    return 0;
  char buff[512];
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  int ret = 0;
  if (offset > 0) {
    luat_fs_fseek(f, offset, SEEK_SET);
  }
  while (rlen > 0) {
    if (rlen > 512)
      ret = fread(buff, 1, 512, f);
    else
      ret = fread(buff, 1, rlen, f);
    if (ret < 1)
      break;
    luaL_addlstring(&b, (const char*)buff, ret);
    rlen -= ret;
  }
  fclose(f);
  luaL_pushresult(&b);
  return 1;
}

/**
将数据写入文件
@api io.writeFile(path, data)
@string 文件路径
@string 数据
@return boolean 成功返回true, 否则返回false
@usage
io.writeFile("/bootime", "1")
 */
static int io_writeFile (lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  size_t len;
  const char *data = luaL_checklstring(L, 2, &len);
  const char *mode = luaL_optstring(L, 3, "wb+");
  FILE* f = fopen(filename, mode);
  if(f == NULL)
    return 0;
  fwrite(data, 1 , len, f);
  fclose(f);
  lua_pushboolean(L,1);
  return 1;
}

#ifdef LUAT_USE_ZBUFF
#include "luat_zbuff.h"
/*
读取文件并填充到zbuff内,但不移动指针位置
@api io.fill(buff, offset, len)
@userdata zbuff实体
@int 写入的位置,默认是0
@int 写入的长度,默认是zbuff的len减去offset
@return boolean 成功返回true,否则返回false
@return int 返回实际读取到的长度，如果小于0也说明是读取失败了
@usage
local buff = zbuff.create(1024)
local f = io.open("/sd/test.txt")
if f then
  f:fill(buff)
end
*/
static int f_fill(lua_State *L) {
  FILE* f = tofile(L);
  luat_zbuff_t* buff;
  int offset;
  int len;
  if (!lua_isuserdata(L, 2)) {
    return 0;
  }
  if (f == NULL)
    return 0;
  buff = luaL_checkudata(L, 2, LUAT_ZBUFF_TYPE);
  if (lua_isinteger(L, 3)) {
    offset = luaL_checkinteger(L, 3);
  }
  else {
    offset = 0;
  }
  if (lua_isinteger(L, 4)) {
    len = luaL_checkinteger(L, 4);
    if (len > buff->len)
      len = buff->len;
    if (offset + len > buff->len)
      len = len - offset;
  }
  else {
    len = buff->len - offset;
  }
  len = fread(buff->addr + offset, 1, len, f);
  lua_pushboolean(L, len >= 0 ? 1 : 0);
  lua_pushinteger(L, len);
  return 2;
}
#endif

static int io_mkfs (lua_State *L);
static int io_mkdir (lua_State *L);
static int io_rmdir (lua_State *L);
static int io_lsdir (lua_State *L);
static int io_lsmount (lua_State *L);

/*
** functions for 'io' library
*/
#include "rotable2.h"
static const rotable_Reg_t iolib[] = {
  {"open", ROREG_FUNC(io_open)},
#ifdef LUA_USE_WINDOWS
  {"popen", ROREG_FUNC(io_popen)},
  {"read", ROREG_FUNC(io_read)},
  {"tmpfile", ROREG_FUNC(io_tmpfile)},
  {"write", ROREG_FUNC(io_write)},
  {"close", ROREG_FUNC(io_close)},
  {"flush", ROREG_FUNC(io_flush)},
  {"input", ROREG_FUNC(io_input)},
  {"output", ROREG_FUNC(io_output)},
#endif
  {"type", ROREG_FUNC(io_type)},
  {"exists", ROREG_FUNC(io_exists)},
  {"fileSize", ROREG_FUNC(io_fileSize)},
  {"readFile", ROREG_FUNC(io_readFile)},
  {"writeFile", ROREG_FUNC(io_writeFile)},
  {"lines", ROREG_FUNC(io_lines)},
  {"mkdir",     ROREG_FUNC(io_mkdir)},
  {"rmdir",     ROREG_FUNC(io_rmdir)},
  {"lsdir",     ROREG_FUNC(io_lsdir)},
  {"mkfs",      ROREG_FUNC(io_mkfs)},
  {"lsmount",   ROREG_FUNC(io_lsmount)},

  {"FILE",      ROREG_INT(0)},
  {"DIR",       ROREG_INT(1)},
  {NULL, ROREG_INT(0) }
};


/*
** methods for file handles
*/
static const luaL_Reg flib[] = {
  {"close", f_close},
  {"flush", f_flush},
  {"lines", f_lines},
  {"read", f_read},
  {"seek", f_seek},
#ifdef LUA_USE_WINDOWS
 {"setvbuf", f_setvbuf},
#endif
  {"write", f_write},
#ifdef LUAT_USE_ZBUFF
  {"fill", f_fill},
#endif
  {"__gc", f_gc},
  {"__tostring", f_tostring},
  {NULL, NULL}
};

static int luat_io_meta_index(lua_State *L) {
    if (lua_isstring(L, 2)) {
        const char* keyname = luaL_checkstring(L, 2);
        //printf("zbuff keyname = %s\n", keyname);
        int i = 0;
        while (1) {
            if (flib[i].name == NULL) break;
            if (!strcmp(keyname, flib[i].name)) {
                lua_pushcfunction(L, flib[i].func);
                return 1;
            }
            i++;
        }
    }
    return 0;
}


static void createmeta (lua_State *L) {
  luaL_newmetatable(L, LUA_FILEHANDLE);  /* create metatable for file handles */
  //lua_pushvalue(L, -1);  /* push metatable */
  lua_pushcfunction(L, luat_io_meta_index);
  lua_setfield(L, -2, "__index");  /* metatable.__index = metatable */
  //luaL_setfuncs(L, flib, 0);  /* add file methods to new metatable */
  lua_pop(L, 1);  /* pop new metatable */
  //lua_pushvalue(L, -1);
  //lua_newtable( L );
  //rotable_newidx( L, flib);
  //lua_setfield( L, -2, "__index" );
  //lua_setmetatable( L, -2 );
  //lua_pop(L, 1);
}


/*
** function to (not) close the standard files stdin, stdout, and stderr
*/
// static int io_noclose (lua_State *L) {
//   LStream *p = tolstream(L);
//   p->closef = &io_noclose;  /* keep file opened */
//   lua_pushnil(L);
//   lua_pushliteral(L, "cannot close standard file");
//   return 2;
// }


// static void createstdfile (lua_State *L, FILE *f, const char *k,
//                            const char *fname) {
//   LStream *p = newprefile(L);
//   p->f = f;
//   p->closef = &io_noclose;
//   if (k != NULL) {
//     lua_pushvalue(L, -1);
//     lua_setfield(L, LUA_REGISTRYINDEX, k);  /* add file to registry */
//   }
//   lua_setfield(L, -2, fname);  /* add file to module */
// }


LUAMOD_API int luaopen_io (lua_State *L) {
  luat_newlib2(L, iolib);  /* new module */
  createmeta(L);
  /* create (and set) default files */
  //createstdfile(L, stdin, IO_INPUT, "stdin");
  //createstdfile(L, stdout, IO_OUTPUT, "stdout");
  //createstdfile(L, stderr, NULL, "stderr");
  return 1;
}

/*
格式化文件系统,需指定挂载点
@api io.mkfs(path)
@string 挂载点
@return bool 成功与否
@return int 底层返回值
@usage
local ret, errio = io.mkfs("/sd")
log.info("fs", "mkfs", ret, errio)
*/
static int io_mkfs (lua_State *L) {
  luat_fs_conf_t conf = {0};
  conf.mount_point = (char*)luaL_checkstring(L, 1);
  int ret = luat_fs_mkfs(&conf);
  lua_pushboolean(L, ret == 0 ? 1 : 0);
  lua_pushinteger(L, ret);
  return 2;
}

/*
创建文件夹
@api io.mkdir(path)
@string 需要建立的目录路径
@return bool 成功与否
@return int 底层返回值
@usage
local ret, errio = io.mkdir("/data/")
log.info("fs", "mkdir", ret, errio)
*/
static int io_mkdir (lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  int ret = luat_fs_mkdir(path);
  lua_pushboolean(L, ret == 0 ? 1 : 0);
  lua_pushinteger(L, ret);
  return 2;
}

/*
删除文件夹
@api io.rmdir(path)
@string 需要移除的目录路径
@return bool 成功与否
@return int 底层返回值
@usage
local ret, errio = io.rmdir("/data/")
log.info("fs", "rmdir", ret, errio)
*/
static int io_rmdir (lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  int ret = luat_fs_rmdir(path);
  lua_pushboolean(L, ret == 0 ? 1 : 0);
  lua_pushinteger(L, ret);
  return 2;
}

/*
列出目录下的文件
@api io.lsdir(path, len, offset)
@string 需要枚举的目录路径
@int 最大长度, 默认10, 最高50
@int 偏移量, 默认0, 当目录文件很多时分页查询用
@return bool 成功与否
@return int 底层返回值
@usage
local ret, data = io.lsdir("/data/", 10, 0)
if ret then
  log.info("fs", "lsdir", json.encode(data))
else
  log.info("fs", "lsdir", "fail", ret, data)
end
*/
static int io_lsdir (lua_State *L) {
  const char* path = luaL_checkstring(L, 1);
  int len = luaL_optinteger(L, 2, 10);
  int offset = luaL_optinteger(L, 3, 0);

  if (len < 0) {
    len = 10;
  } else if (len > 100) {
    len = 100;
  }
  if (offset < 0)
    offset = 0;

  luat_fs_dirent_t* ents = luat_heap_malloc(sizeof(luat_fs_dirent_t) * len);
  if (ents == NULL) {
    LLOGE("out of memory when malloc luat_fs_dirent_t");
    return 0;
  }
  int ret = luat_fs_lsdir(path, ents, offset, len);
  //LLOGD("luat_fs_lsdir ret %d", ret);
  if (ret == 0) {
    luat_heap_free(ents);
    lua_pushboolean(L, 1);
    lua_newtable(L);
    return 2;
  }
  else if (ret > 0) {
    lua_pushboolean(L, 1);
    lua_createtable(L, ret, 0);

    for (size_t i = 0; i < ret; i++)
    {
      lua_createtable(L, 0, 3);
      lua_pushinteger(L, ents[i].d_type);
      lua_setfield(L, -2, "type");
      lua_pushstring(L, ents[i].d_name);
      lua_setfield(L, -2, "name");
      lua_pushinteger(L, ents[i].d_size);
      lua_setfield(L, -2, "size");
      lua_seti(L, -2, i + 1);
    }
    luat_heap_free(ents);
    return 2;
  }
  else {
    luat_heap_free(ents);
    lua_pushboolean(L, 0);
    lua_pushinteger(L, ret);
    return 2;
  }

  return 0;
}


/*
列出所有挂载点
@api io.lsmount()
@return table 挂载点列表
@usage
local data = io.lsmount()
log.info("fs", "lsmount", json.encode(data))
*/
#ifdef LUAT_USE_FS_VFS
luat_vfs_t* luat_vfs_self(void);
#endif
static int io_lsmount (lua_State *L) {
    lua_newtable(L);
#ifdef LUAT_USE_FS_VFS
    luat_vfs_t* vfs = luat_vfs_self();
    for (size_t j = 0; j < LUAT_VFS_FILESYSTEM_MOUNT_MAX; j++) {
        if (vfs->mounted[j].ok == 0)
            continue;
        lua_newtable(L);
        lua_pushstring(L, vfs->mounted[j].prefix);
        lua_setfield(L, -2, "path");
        lua_pushstring(L, vfs->mounted[j].fs->name);
        lua_setfield(L, -2, "fs");
        lua_seti(L, -2, j+1);
    }
#else
    lua_newtable(L);
    lua_pushliteral(L, "");
    lua_setfield(L, -2, "path");
    lua_pushliteral(L, "posix");
    lua_setfield(L, -2, "fs");
    lua_seti(L, -2, 1);
#endif
    return 1;
}
