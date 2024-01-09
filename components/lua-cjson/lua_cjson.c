/*
@module  json
@summary json生成和解析库
@version 1.0
@date    2020.02.18
@demo json
@tag LUAT_USE_CJSON
*/
/* Lua CJSON - JSON support for Lua
 *
 * Copyright (c) 2010-2012  Mark Pulford <mark@kyne.com.au>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/* Caveats:
 * - JSON "null" values are represented as lightuserdata since Lua
 *   tables cannot contain "nil". Compare with cjson.null.
 * - Invalid UTF-8 characters are not detected and will be passed
 *   untouched. If required, UTF-8 error checking should be done
 *   outside this library.
 * - Javascript comments are not part of the JSON spec, and are not
 *   currently supported.
 *
 * Note: Decoding is slower than encoding. Lua spends significant
 *       time (30%) managing tables when parsing JSON since it is
 *       difficult to know object/array sizes ahead of time.
 */

#include <assert.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <lua.h>
#include <lauxlib.h>

#include "strbuf.h"
#include "fpconv.h"
#include "printf.h"
#include "float.h"

#define MIN_OPT_LEVEL 2

#define LUAT_LOG_TAG "json"
#include "luat_log.h"

//#include <lrodefs.h>
//#include <auxmods.h>

int strncasecmp(const char *string1, const char *string2, size_t count);

static char float_fmt[12];

#ifdef LUA_USE_WINDOWS
#define snprintf _snprintf
typedef unsigned char u_char;

/*
 * This array is designed for mapping upper and lower case letter
 * together for a case independent comparison.  The mappings are
 * based upon ascii character sequences.
 */
static const u_char charmap[] = {
	'\000', '\001', '\002', '\003', '\004', '\005', '\006', '\007',
	'\010', '\011', '\012', '\013', '\014', '\015', '\016', '\017',
	'\020', '\021', '\022', '\023', '\024', '\025', '\026', '\027',
	'\030', '\031', '\032', '\033', '\034', '\035', '\036', '\037',
	'\040', '\041', '\042', '\043', '\044', '\045', '\046', '\047',
	'\050', '\051', '\052', '\053', '\054', '\055', '\056', '\057',
	'\060', '\061', '\062', '\063', '\064', '\065', '\066', '\067',
	'\070', '\071', '\072', '\073', '\074', '\075', '\076', '\077',
	'\100', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
	'\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
	'\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
	'\170', '\171', '\172', '\133', '\134', '\135', '\136', '\137',
	'\140', '\141', '\142', '\143', '\144', '\145', '\146', '\147',
	'\150', '\151', '\152', '\153', '\154', '\155', '\156', '\157',
	'\160', '\161', '\162', '\163', '\164', '\165', '\166', '\167',
	'\170', '\171', '\172', '\173', '\174', '\175', '\176', '\177',
	'\200', '\201', '\202', '\203', '\204', '\205', '\206', '\207',
	'\210', '\211', '\212', '\213', '\214', '\215', '\216', '\217',
	'\220', '\221', '\222', '\223', '\224', '\225', '\226', '\227',
	'\230', '\231', '\232', '\233', '\234', '\235', '\236', '\237',
	'\240', '\241', '\242', '\243', '\244', '\245', '\246', '\247',
	'\250', '\251', '\252', '\253', '\254', '\255', '\256', '\257',
	'\260', '\261', '\262', '\263', '\264', '\265', '\266', '\267',
	'\270', '\271', '\272', '\273', '\274', '\275', '\276', '\277',
	'\300', '\301', '\302', '\303', '\304', '\305', '\306', '\307',
	'\310', '\311', '\312', '\313', '\314', '\315', '\316', '\317',
	'\320', '\321', '\322', '\323', '\324', '\325', '\326', '\327',
	'\330', '\331', '\332', '\333', '\334', '\335', '\336', '\337',
	'\340', '\341', '\342', '\343', '\344', '\345', '\346', '\347',
	'\350', '\351', '\352', '\353', '\354', '\355', '\356', '\357',
	'\360', '\361', '\362', '\363', '\364', '\365', '\366', '\367',
	'\370', '\371', '\372', '\373', '\374', '\375', '\376', '\377',
};

int
strcasecmp(const char *s1, const char *s2)
{
	const u_char *cm = charmap;
	const u_char *us1 = (const u_char *)s1;
	const u_char *us2 = (const u_char *)s2;

	while (cm[*us1] == cm[*us2++])
		if (*us1++ == '\0')
			return (0);
	return (cm[*us1] - cm[*--us2]);
}

int
strncasecmp(const char *s1, const char *s2, size_t n)
{
	if (n != 0) {
		const u_char *cm = charmap;
		const u_char *us1 = (const u_char *)s1;
		const u_char *us2 = (const u_char *)s2;

		do {
			if (cm[*us1] != cm[*us2++])
				return (cm[*us1] - cm[*--us2]);
			if (*us1++ == '\0')
      break;
		} while (--n != 0);
  }
	return (0);
}

#endif

#define ENABLE_CJSON_GLOBAL
#define MISSING_ISINF

#ifndef CJSON_MODNAME
#define CJSON_MODNAME   "json"
#endif

#ifndef CJSON_VERSION
#define CJSON_VERSION   "2.1.0"
#endif

#ifndef assert
#define assert(x)
#endif

#if !defined(isnan)
#define isnan(x) (0)
#endif

/* Workaround for Solaris platforms missing isinf() */
#if !defined(isinf) && (defined(USE_INTERNAL_ISINF) || defined(MISSING_ISINF))
#define isinf(x) (!isnan(x) && isnan((x) - (x)))
#endif

#define DEFAULT_SPARSE_CONVERT 0
#define DEFAULT_SPARSE_RATIO 2
#define DEFAULT_SPARSE_SAFE 10
#define DEFAULT_ENCODE_MAX_DEPTH 1000
#define DEFAULT_DECODE_MAX_DEPTH 1000
#define DEFAULT_ENCODE_INVALID_NUMBERS 0
#define DEFAULT_DECODE_INVALID_NUMBERS 1
#define DEFAULT_ENCODE_KEEP_BUFFER 0
#define DEFAULT_ENCODE_NUMBER_PRECISION 7

#ifdef DISABLE_INVALID_NUMBERS
#undef DEFAULT_DECODE_INVALID_NUMBERS
#define DEFAULT_DECODE_INVALID_NUMBERS 0
#endif

typedef enum {
    T_OBJ_BEGIN,
    T_OBJ_END,
    T_ARR_BEGIN,
    T_ARR_END,
    T_STRING,
    T_NUMBER,
    T_INTEGER,
    T_BOOLEAN,
    T_NULL,
    T_COLON,
    T_COMMA,
    T_END,
    T_WHITESPACE,
    T_ERROR,
    T_UNKNOWN
} json_token_type_t;

static const char *json_token_type_name[] = {
    "T_OBJ_BEGIN",
    "T_OBJ_END",
    "T_ARR_BEGIN",
    "T_ARR_END",
    "T_STRING",
    "T_NUMBER",
    "T_INTEGER",
    "T_BOOLEAN",
    "T_NULL",
    "T_COLON",
    "T_COMMA",
    "T_END",
    "T_WHITESPACE",
    "T_ERROR",
    "T_UNKNOWN",
    NULL
};

// typedef struct {
//     //json_token_type_t ch2token[256];
//     //char escape2char[256];  /* Decoding */

//     /* encode_buf is only allocated and used when
//      * encode_keep_buffer is set */
//     //strbuf_t encode_buf;

//     //int encode_sparse_convert;
//     //int encode_sparse_ratio;
//     //int encode_sparse_safe;
//     //int encode_max_depth;
//     //int encode_invalid_numbers;     /* 2 => Encode as "null" */
//     //int encode_number_precision;
//     //int encode_keep_buffer;

//     //int decode_invalid_numbers;
//     //int decode_max_depth;
// } json_config_t;

typedef struct {
    const char *data;
    const char *ptr;
    strbuf_t *tmp;    /* Temporary storage for strings */
    //json_config_t *cfg;
    int current_depth;
} json_parse_t;

typedef struct {
    json_token_type_t type;
    int index;
    union {
        const char *string;
        lua_Number number;
        lua_Integer lint;
        int boolean;
    } value;
    int string_len;
} json_token_t;

// static const char *char2escape[256] = {
//     "\\u0000", "\\u0001", "\\u0002", "\\u0003",
//     "\\u0004", "\\u0005", "\\u0006", "\\u0007",
//     "\\b", "\\t", "\\n", "\\u000b",
//     "\\f", "\\r", "\\u000e", "\\u000f",
//     "\\u0010", "\\u0011", "\\u0012", "\\u0013",
//     "\\u0014", "\\u0015", "\\u0016", "\\u0017",
//     "\\u0018", "\\u0019", "\\u001a", "\\u001b",
//     "\\u001c", "\\u001d", "\\u001e", "\\u001f",
//     NULL, NULL, "\\\"", NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, "\\/",
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, "\\\\", NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, "\\u007f",
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
//     NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
// };

static const char*  char2escape(unsigned char c) {
    switch (c)
    {
    case 0x00: return "\\u0000";
    case 0x01: return "\\u0001";
    case 0x02: return "\\u0002";
    case 0x03: return "\\u0003";
    case 0x04: return "\\u0004";
    case 0x05: return "\\u0005";
    case 0x06: return "\\u0006";
    case 0x07: return "\\u0007";
    case 0x08: return "\\b";
    case 0x09: return "\\t";
    case 0x0a: return "\\n";
    case 0x0b: return "\\u000b";
    case 0x0c: return "\\f";
    case 0x0d: return "\\r";
    case 0x0e: return "\\u000e";
    case 0x0f: return "\\u000f";

    case 0x10: return "\\u0010";
    case 0x11: return "\\u0011";
    case 0x12: return "\\u0012";
    case 0x13: return "\\u0013";
    case 0x14: return "\\u0014";
    case 0x15: return "\\u0015";
    case 0x16: return "\\u0016";
    case 0x17: return "\\u0017";
    case 0x18: return "\\u0018";
    case 0x19: return "\\u0019";
    case 0x1a: return "\\u001a";
    case 0x1b: return "\\u001b";
    case 0x1c: return "\\u001c";
    case 0x1d: return "\\u001d";
    case 0x1e: return "\\u001e";
    case 0x1f: return "\\u001f";
    case '\"': return "\\\"";
    case '/' : return "\\/";
    case '\\': return "\\\\";
    case 0x7f: return "\\u007f";

    default:
        return NULL;
    }
}

//-----------------------------------------------

static json_token_type_t ch2token(int ch) {
    switch (ch)
    {
    /* Set tokens that require no further processing */
    case '{': return T_OBJ_BEGIN;
    case '}': return T_OBJ_END;
    case '[': return T_ARR_BEGIN;
    case ']': return T_ARR_END;
    case ',': return T_COMMA;
    case ':': return T_COLON;
    case '\0': return T_END;
    case ' ': return T_WHITESPACE;
    case '\t': return T_WHITESPACE;
    case '\n': return T_WHITESPACE;
    case '\r': return T_WHITESPACE;

    /* Update characters that require further processing */
    case 'f': return T_UNKNOWN;     /* false? */
    case 'i': return T_UNKNOWN;     /* inf, ininity? */
    case 'I': return T_UNKNOWN;
    case 'n': return T_UNKNOWN;     /* null, nan? */
    case 'N': return T_UNKNOWN;
    case 't': return T_UNKNOWN;     /* true? */
    case '"': return T_UNKNOWN;     /* string? */
    case '+': return T_UNKNOWN;     /* number? */
    case '-': return T_UNKNOWN;
    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
        return T_UNKNOWN;
    default:
        return T_ERROR;
    }
}

static char escape2char(unsigned char c) {
    switch (c) {
    case '"': return '"';
    case '\\':return '\\';
    case '/': return '/';
    case 'b': return '\b';
    case 't': return '\t';
    case 'n': return '\n';
    case 'f': return '\f';
    case 'r': return '\r';
    case 'u': return 'u';          /* Unicode parsing required */
    default:
        return 0;
    }
}

#if defined(DISABLE_INVALID_NUMBERS) && !defined(USE_INTERNAL_FPCONV)
void json_verify_invalid_number_setting(lua_State *l, int *setting)
{
    if (*setting == 1) {
        *setting = 0;
        luaL_error(l, "Infinity, NaN, and/or hexadecimal numbers are not supported.");
    }
}
#else
#define json_verify_invalid_number_setting(l, s)    do { } while(0)
#endif

/* ===== ENCODING ===== */

static void json_encode_exception(lua_State *l, strbuf_t *json, int lindex,
                                  const char *reason)
{
    //if (!cfg->encode_keep_buffer)
        strbuf_free(json);
    luaL_error(l, "Cannot serialise %s: %s",
                  lua_typename(l, lua_type(l, lindex)), reason);
}

/* json_append_string args:
 * - lua_State
 * - JSON strbuf
 * - String (Lua stack index)
 *
 * Returns nothing. Doesn't remove string from Lua stack */
static void json_append_string(lua_State *l, strbuf_t *json, int lindex)
{
    const char *escstr = NULL;
    size_t i = 0;
    const char *str = NULL;
    size_t len = 0;

    str = lua_tolstring(l, lindex, &len);

    /* Worst case is len * 6 (all unicode escapes).
     * This buffer is reused constantly for small strings
     * If there are any excess pages, they won't be hit anyway.
     * This gains ~5% speedup. */
    strbuf_ensure_empty_length(json, len * 6 + 2);
    if (json->is_err)
        return;

    strbuf_append_char_unsafe(json, '\"');
    for (i = 0; i < len; i++) {
        escstr = char2escape((unsigned char)str[i]);
        if (escstr)
            strbuf_append_string(json, escstr);
        else
            strbuf_append_char_unsafe(json, str[i]);
    }
    strbuf_append_char_unsafe(json, '\"');
}

/* Find the size of the array on the top of the Lua stack
 * -1   object (not a pure array)
 * >=0  elements in array
 */
static int lua_array_length(lua_State *l, strbuf_t *json)
{
    double k;
    int max;
    int items;

    max = 0;
    items = 0;

    lua_pushnil(l);
    /* table, startkey */
    while (lua_next(l, -2) != 0) {
        /* table, key, value */
        if (lua_type(l, -2) == LUA_TNUMBER &&
            (k = lua_tonumber(l, -2))) {
            /* Integer >= 1 ? */
            if (floor(k) == k && k >= 1) {
                if (k > max)
                    max = k;
                items++;
                lua_pop(l, 1);
                continue;
            }
        }

        /* Must not be an array (non integer key) */
        lua_pop(l, 2);
        return -1;
    }

    /* Encode excessively sparse arrays as objects (if enabled) */
    if (DEFAULT_SPARSE_RATIO > 0 &&
        max > items * DEFAULT_SPARSE_RATIO &&
        max > DEFAULT_SPARSE_SAFE) {
        if (!DEFAULT_SPARSE_CONVERT)
            json_encode_exception(l, json, -1, "excessively sparse array");

        return -1;
    }

    return max;
}

static void json_check_encode_depth(lua_State *l,
                                    int current_depth, strbuf_t *json)
{
    /* Ensure there are enough slots free to traverse a table (key,
     * value) and push a string for a potential error message.
     *
     * Unlike "decode", the key and value are still on the stack when
     * lua_checkstack() is called.  Hence an extra slot for luaL_error()
     * below is required just in case the next check to lua_checkstack()
     * fails.
     *
     * While this won't cause a crash due to the EXTRA_STACK reserve
     * slots, it would still be an improper use of the API. */
    if (current_depth <= DEFAULT_ENCODE_MAX_DEPTH && lua_checkstack(l, 3))
        return;

    //if (!cfg->encode_keep_buffer)
        strbuf_free(json);

    luaL_error(l, "Cannot serialise, excessive nesting (%d)",
               current_depth);
}

static void json_append_data(lua_State *l,
                             int current_depth, strbuf_t *json);

/* json_append_array args:
 * - lua_State
 * - JSON strbuf
 * - Size of passwd Lua array (top of stack) */
static void json_append_array(lua_State *l, int current_depth,
                              strbuf_t *json, int array_length)
{
    int comma, i;

    strbuf_append_char(json, '[');

    comma = 0;
    for (i = 1; i <= array_length; i++) {
        if (comma)
            strbuf_append_char(json, ',');
        else
            comma = 1;

        lua_rawgeti(l, -1, i);
        json_append_data(l, current_depth, json);
        lua_pop(l, 1);
    }

    strbuf_append_char(json, ']');
}

// typedef struct {
//      char encode_number_precision_mode;     /*浮点数转化模式 默认为'g',可配置为'f' */
//      unsigned char encode_number_precision; /*浮点数转化精度 默认为7,可配置为0~14 */
// } json_easy_config_t;

// static json_easy_config_t json_easy_config = {'g',DEFAULT_ENCODE_NUMBER_PRECISION};

static void json_append_number(lua_State *l,
                               strbuf_t *json, int lindex)
{
    double num = lua_tonumber(l, lindex);
    int len;

    //printf("json num = %ld, %f %ld", num, num, 100);

    if (DEFAULT_ENCODE_INVALID_NUMBERS == 0) {
        /* Prevent encoding invalid numbers */
        if (isinf(num) || isnan(num))
            json_encode_exception(l, json, lindex, "must not be NaN or Inf");
    } else if (DEFAULT_ENCODE_INVALID_NUMBERS == 1) {
        /* Encode invalid numbers, but handle "nan" separately
         * since some platforms may encode as "-nan". */
        if (isnan(num)) {
            strbuf_append_mem(json, "nan", 3);
            return;
        }
    } else {
        /* Encode invalid numbers as "null" */
        if (isinf(num) || isnan(num)) {
            strbuf_append_mem(json, "null", 4);
            return;
        }
    }

    strbuf_ensure_empty_length(json, FPCONV_G_FMT_BUFSIZE);
    if (json->is_err)
        return;
    if (lua_isinteger(l, lindex)) {
        #ifdef LUAT_CONF_VM_64bit
        len = snprintf_(strbuf_empty_ptr(json), FPCONV_G_FMT_BUFSIZE, "%lld", lua_tointeger(l, lindex));
        #else
        len = snprintf_(strbuf_empty_ptr(json), FPCONV_G_FMT_BUFSIZE, "%ld", lua_tointeger(l, lindex));
        #endif
    }
    else {
        lua_Number v = lua_tonumber(l, lindex);
        #ifdef LUAT_CONF_VM_64bit
        if (v <= DBL_EPSILON  && v >= -DBL_EPSILON) {
        #else
        if (v <= FLT_EPSILON  && v >= -FLT_EPSILON) {
        #endif
            memcpy(strbuf_empty_ptr(json), "0.0\x00", 4);
            len = 1;
        }
        else {
            len = snprintf_(strbuf_empty_ptr(json), FPCONV_G_FMT_BUFSIZE, float_fmt, v);
        }
    }
    //len = fpconv_g_fmt(strbuf_empty_ptr(json), num, DEFAULT_ENCODE_NUMBER_PRECISION);
    strbuf_extend_length(json, len);
}

static void json_append_object(lua_State *l,
                               int current_depth, strbuf_t *json)
{
    int comma, keytype;

    /* Object */
    strbuf_append_char(json, '{');

    lua_pushnil(l);
    /* table, startkey */
    comma = 0;
    while (lua_next(l, -2) != 0) {
        if (comma)
            strbuf_append_char(json, ',');
        else
            comma = 1;

        /* table, key, value */
        keytype = lua_type(l, -2);
        if (keytype == LUA_TNUMBER) {
            strbuf_append_char(json, '"');
            json_append_number(l, json, -2);
            strbuf_append_mem(json, "\":", 2);
        } else if (keytype == LUA_TSTRING) {
            json_append_string(l, json, -2);
            strbuf_append_char(json, ':');
        } else {
            json_encode_exception(l, json, -2,
                                  "table key must be a number or string");
            /* never returns */
        }

        /* table, key, value */
        json_append_data(l, current_depth, json);
        lua_pop(l, 1);
        /* table, key */
    }

    strbuf_append_char(json, '}');
}

/* Serialise Lua data into JSON string. */
static void json_append_data(lua_State *l,
                             int current_depth, strbuf_t *json)
{
    int len;

    switch (lua_type(l, -1)) {
    case LUA_TSTRING:
        json_append_string(l, json, -1);
        break;
    case LUA_TNUMBER:
        json_append_number(l, json, -1);
        break;
    case LUA_TBOOLEAN:
        if (lua_toboolean(l, -1))
            strbuf_append_mem(json, "true", 4);
        else
            strbuf_append_mem(json, "false", 5);
        break;
    case LUA_TTABLE:
        current_depth++;
        json_check_encode_depth(l, current_depth, json);
        len = lua_array_length(l, json);
        if (len > 0)
            json_append_array(l, current_depth, json, len);
        else
            json_append_object(l, current_depth, json);
        break;
    case LUA_TNIL:
        strbuf_append_mem(json, "null", 4);
        break;
    case LUA_TLIGHTUSERDATA:
        if (lua_touserdata(l, -1) == NULL) {
            strbuf_append_mem(json, "null", 4);
            break;
        }
    default:
        /* Remaining types (LUA_TFUNCTION, LUA_TUSERDATA, LUA_TTHREAD,
         * and LUA_TLIGHTUSERDATA) cannot be serialised */
        json_encode_exception(l, json, -1, "type not supported");
        /* never returns */
    }
}

static int json_encode(lua_State *l)
{
    //json_config_t *cfg = json_fetch_config(l);
    strbuf_t local_encode_buf;
    strbuf_t *encode_buf;
    char *json;
    int len;
    int ret;

    luaL_argcheck(l, lua_gettop(l) == 1, 1, "expected 1 argument");


    encode_buf = &local_encode_buf;
    ret = strbuf_init(encode_buf, 0);
    if (ret) {
        LLOGE("json encode out of memory!!!");
        return 0;
    }

    json_append_data(l, 0, encode_buf);

    // check if err
    if (local_encode_buf.is_err) {
        LLOGE("json encode failed by memory less");
        lua_pushnil(l);
    }
    else {
        json = strbuf_string(encode_buf, &len);
        lua_pushlstring(l, json, len);
    }

    strbuf_free(encode_buf);

    return 1;
}

/* ===== DECODING ===== */

static void json_process_value(lua_State *l, json_parse_t *json,
                               json_token_t *token);

static int hexdigit2int(char hex)
{
    if ('0' <= hex  && hex <= '9')
        return hex - '0';

    /* Force lowercase */
    hex |= 0x20;
    if ('a' <= hex && hex <= 'f')
        return 10 + hex - 'a';

    return -1;
}

static int decode_hex4(const char *hex)
{
    int digit[4];
    int i;

    /* Convert ASCII hex digit to numeric digit
     * Note: this returns an error for invalid hex digits, including
     *       NULL */
    for (i = 0; i < 4; i++) {
        digit[i] = hexdigit2int(hex[i]);
        if (digit[i] < 0) {
            return -1;
        }
    }

    return (digit[0] << 12) +
           (digit[1] << 8) +
           (digit[2] << 4) +
            digit[3];
}

/* Converts a Unicode codepoint to UTF-8.
 * Returns UTF-8 string length, and up to 4 bytes in *utf8 */
static int codepoint_to_utf8(char *utf8, int codepoint)
{
    /* 0xxxxxxx */
    if (codepoint <= 0x7F) {
        utf8[0] = codepoint;
        return 1;
    }

    /* 110xxxxx 10xxxxxx */
    if (codepoint <= 0x7FF) {
        utf8[0] = (codepoint >> 6) | 0xC0;
        utf8[1] = (codepoint & 0x3F) | 0x80;
        return 2;
    }

    /* 1110xxxx 10xxxxxx 10xxxxxx */
    if (codepoint <= 0xFFFF) {
        utf8[0] = (codepoint >> 12) | 0xE0;
        utf8[1] = ((codepoint >> 6) & 0x3F) | 0x80;
        utf8[2] = (codepoint & 0x3F) | 0x80;
        return 3;
    }

    /* 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
    if (codepoint <= 0x1FFFFF) {
        utf8[0] = (codepoint >> 18) | 0xF0;
        utf8[1] = ((codepoint >> 12) & 0x3F) | 0x80;
        utf8[2] = ((codepoint >> 6) & 0x3F) | 0x80;
        utf8[3] = (codepoint & 0x3F) | 0x80;
        return 4;
    }

    return 0;
}


/* Called when index pointing to beginning of UTF-16 code escape: \uXXXX
 * \u is guaranteed to exist, but the remaining hex characters may be
 * missing.
 * Translate to UTF-8 and append to temporary token string.
 * Must advance index to the next character to be processed.
 * Returns: 0   success
 *          -1  error
 */
static int json_append_unicode_escape(json_parse_t *json)
{
    char utf8[4];       /* Surrogate pairs require 4 UTF-8 bytes */
    int codepoint;
    int surrogate_low;
    int len;
    int escape_len = 6;

    /* Fetch UTF-16 code unit */
    codepoint = decode_hex4(json->ptr + 2);
    if (codepoint < 0)
        return -1;

    /* UTF-16 surrogate pairs take the following 2 byte form:
     *      11011 x yyyyyyyyyy
     * When x = 0: y is the high 10 bits of the codepoint
     *      x = 1: y is the low 10 bits of the codepoint
     *
     * Check for a surrogate pair (high or low) */
    if ((codepoint & 0xF800) == 0xD800) {
        /* Error if the 1st surrogate is not high */
        if (codepoint & 0x400)
            return -1;

        /* Ensure the next code is a unicode escape */
        if (*(json->ptr + escape_len) != '\\' ||
            *(json->ptr + escape_len + 1) != 'u') {
            return -1;
        }

        /* Fetch the next codepoint */
        surrogate_low = decode_hex4(json->ptr + 2 + escape_len);
        if (surrogate_low < 0)
            return -1;

        /* Error if the 2nd code is not a low surrogate */
        if ((surrogate_low & 0xFC00) != 0xDC00)
            return -1;

        /* Calculate Unicode codepoint */
        codepoint = (codepoint & 0x3FF) << 10;
        surrogate_low &= 0x3FF;
        codepoint = (codepoint | surrogate_low) + 0x10000;
        escape_len = 12;
    }

    /* Convert codepoint to UTF-8 */
    len = codepoint_to_utf8(utf8, codepoint);
    if (!len)
        return -1;

    /* Append bytes and advance parse index */
    strbuf_append_mem_unsafe(json->tmp, utf8, len);
    json->ptr += escape_len;

    return 0;
}

static void json_set_token_error(json_token_t *token, json_parse_t *json,
                                 const char *errtype)
{
    token->type = T_ERROR;
    token->index = json->ptr - json->data;
    token->value.string = errtype;
}

static void json_next_string_token(json_parse_t *json, json_token_t *token)
{
    //char *escape2char = json->cfg->escape2char;
    char ch;

    /* Caller must ensure a string is next */
    assert(*json->ptr == '"');

    /* Skip " */
    json->ptr++;

    /* json->tmp is the temporary strbuf used to accumulate the
     * decoded string value.
     * json->tmp is sized to handle JSON containing only a string value.
     */
    strbuf_reset(json->tmp);

    while ((ch = *json->ptr) != '"') {
        if (!ch) {
            /* Premature end of the string */
            json_set_token_error(token, json, "unexpected end of string");
            return;
        }

        /* Handle escapes */
        if (ch == '\\') {
            /* Fetch escape character */
            ch = *(json->ptr + 1);

            /* Translate escape code and append to tmp string */
            ch = escape2char((unsigned char)ch);
            if (ch == 'u') {
                if (json_append_unicode_escape(json) == 0)
                    continue;

                json_set_token_error(token, json,
                                     "invalid unicode escape code");
                return;
            }
            if (!ch) {
                json_set_token_error(token, json, "invalid escape code");
                return;
            }

            /* Skip '\' */
            json->ptr++;
        }
        /* Append normal character or translated single character
         * Unicode escapes are handled above */
        strbuf_append_char_unsafe(json->tmp, ch);
        json->ptr++;
    }
    json->ptr++;    /* Eat final quote (") */

    strbuf_ensure_null(json->tmp);

    token->type = T_STRING;
    token->value.string = strbuf_string(json->tmp, &token->string_len);
}

/* JSON numbers should take the following form:
 *      -?(0|[1-9]|[1-9][0-9]+)(.[0-9]+)?([eE][-+]?[0-9]+)?
 *
 * json_next_number_token() uses strtod() which allows other forms:
 * - numbers starting with '+'
 * - NaN, -NaN, infinity, -infinity
 * - hexadecimal numbers
 * - numbers with leading zeros
 *
 * json_is_invalid_number() detects "numbers" which may pass strtod()'s
 * error checking, but should not be allowed with strict JSON.
 *
 * json_is_invalid_number() may pass numbers which cause strtod()
 * to generate an error.
 */
static int json_is_invalid_number(json_parse_t *json)
{
    const char *p = json->ptr;

    /* Reject numbers starting with + */
    if (*p == '+')
        return 1;

    /* Skip minus sign if it exists */
    if (*p == '-')
        p++;

    /* Reject numbers starting with 0x, or leading zeros */
    if (*p == '0') {
        int ch2 = *(p + 1);

        if ((ch2 | 0x20) == 'x' ||          /* Hex */
            ('0' <= ch2 && ch2 <= '9'))     /* Leading zero */
            return 1;

        return 0;
    } else if (*p <= '9') {
        return 0;                           /* Ordinary number */
    }

    /* Reject inf/nan */
    if (!strncasecmp(p, "inf", 3))
        return 1;
    if (!strncasecmp(p, "nan", 3))
        return 1;

    /* Pass all other numbers which may still be invalid, but
     * strtod() will catch them. */
    return 0;
}

static void json_next_number_token(json_parse_t *json, json_token_t *token)
{
    char *endptr;
    unsigned len = 0;
    lua_Integer int_val = 0;
    token->type = T_NUMBER;
    token->value.number = lua_str2number(json->ptr, &endptr);
    if (json->ptr == endptr)
        json_set_token_error(token, json, "invalid number");
    else {
        // 额外尝试是否为整型
#ifndef LUAT_LIB_JSON_DECODE_INTEGER_DISABLE
        len = (endptr - json->ptr);
        if (len == 1 && (*json->ptr) == '0') {
            token->type = T_INTEGER;
            token->value.lint = 0;
        }
        else {
            for (size_t i = 0; i < len; i++)
            {
                if (json->ptr[i] == '.') {
                    int_val = -1;
                    break;
                }
            }
            if (int_val == 0) {
                int_val = 0;
                #ifdef LUAT_CONF_VM_64bit
                int_val = strtoll(json->ptr, &endptr, 0);
                #else
                int_val = strtol(json->ptr, &endptr, 0);
                #endif
                if (int_val != 0) {
                    token->type = T_INTEGER;
                    token->value.lint = int_val;
                }
            }
        }
#endif
        json->ptr = endptr;     /* Skip the processed number */
    }

    return;
}

/* Fills in the token struct.
 * T_STRING will return a pointer to the json_parse_t temporary string
 * T_ERROR will leave the json->ptr pointer at the error.
 */
static void json_next_token(json_parse_t *json, json_token_t *token)
{
    //const json_token_type_t *ch2token = json->cfg->ch2token;
    int ch;

    /* Eat whitespace. */
    while (1) {
        ch = (unsigned char)*(json->ptr);
        token->type = ch2token(ch);
        if (token->type != T_WHITESPACE)
            break;
        json->ptr++;
    }

    /* Store location of new token. Required when throwing errors
     * for unexpected tokens (syntax errors). */
    token->index = json->ptr - json->data;

    /* Don't advance the pointer for an error or the end */
    if (token->type == T_ERROR) {
        json_set_token_error(token, json, "invalid token");
        return;
    }

    if (token->type == T_END) {
        return;
    }

    /* Found a known single character token, advance index and return */
    if (token->type != T_UNKNOWN) {
        json->ptr++;
        return;
    }

    /* Process characters which triggered T_UNKNOWN
     *
     * Must use strncmp() to match the front of the JSON string.
     * JSON identifier must be lowercase.
     * When strict_numbers if disabled, either case is allowed for
     * Infinity/NaN (since we are no longer following the spec..) */
    if (ch == '"') {
        json_next_string_token(json, token);
        return;
    } else if (ch == '-' || ('0' <= ch && ch <= '9')) {
        if (!DEFAULT_ENCODE_INVALID_NUMBERS && json_is_invalid_number(json)) {
            json_set_token_error(token, json, "invalid number");
            return;
        }
        json_next_number_token(json, token);
        return;
    } else if (!strncmp(json->ptr, "true", 4)) {
        token->type = T_BOOLEAN;
        token->value.boolean = 1;
        json->ptr += 4;
        return;
    } else if (!strncmp(json->ptr, "false", 5)) {
        token->type = T_BOOLEAN;
        token->value.boolean = 0;
        json->ptr += 5;
        return;
    } else if (!strncmp(json->ptr, "null", 4)) {
        token->type = T_NULL;
        json->ptr += 4;
        return;
    } else if (DEFAULT_ENCODE_INVALID_NUMBERS &&
               json_is_invalid_number(json)) {
        /* When decode_invalid_numbers is enabled, only attempt to process
         * numbers we know are invalid JSON (Inf, NaN, hex)
         * This is required to generate an appropriate token error,
         * otherwise all bad tokens will register as "invalid number"
         */
        json_next_number_token(json, token);
        return;
    }

    /* Token starts with t/f/n but isn't recognised above. */
    json_set_token_error(token, json, "invalid token");
}

/* This function does not return.
 * DO NOT CALL WITH DYNAMIC MEMORY ALLOCATED.
 * The only supported exception is the temporary parser string
 * json->tmp struct.
 * json and token should exist on the stack somewhere.
 * luaL_error() will long_jmp and release the stack */
static void json_throw_parse_error(lua_State *l, json_parse_t *json,
                                   const char *exp, json_token_t *token)
{
    const char *found;

    strbuf_free(json->tmp);

    if (token->type == T_ERROR)
        found = token->value.string;
    else
        found = json_token_type_name[token->type];

    /* Note: token->index is 0 based, display starting from 1 */
    luaL_error(l, "Expected %s but found %s at character %d",
               exp, found, token->index + 1);
}

static inline void json_decode_ascend(json_parse_t *json)
{
    json->current_depth--;
}

static void json_decode_descend(lua_State *l, json_parse_t *json, int slots)
{
    json->current_depth++;

    if (json->current_depth <= DEFAULT_DECODE_MAX_DEPTH &&
        lua_checkstack(l, slots)) {
        return;
    }

    strbuf_free(json->tmp);
    luaL_error(l, "Found too many nested data structures (%d) at character %d",
        json->current_depth, json->ptr - json->data);
}

static void json_parse_object_context(lua_State *l, json_parse_t *json)
{
    json_token_t token;

    /* 3 slots required:
     * .., table, key, value */
    json_decode_descend(l, json, 3);

    lua_newtable(l);

    json_next_token(json, &token);

    /* Handle empty objects */
    if (token.type == T_OBJ_END) {
        json_decode_ascend(json);
        return;
    }

    while (1) {
        if (token.type != T_STRING)
            json_throw_parse_error(l, json, "object key string", &token);

        /* Push key */
        lua_pushlstring(l, token.value.string, token.string_len);

        json_next_token(json, &token);
        if (token.type != T_COLON)
            json_throw_parse_error(l, json, "colon", &token);

        /* Fetch value */
        json_next_token(json, &token);
        json_process_value(l, json, &token);

        /* Set key = value */
        lua_rawset(l, -3);

        json_next_token(json, &token);

        if (token.type == T_OBJ_END) {
            json_decode_ascend(json);
            return;
        }

        if (token.type != T_COMMA)
            json_throw_parse_error(l, json, "comma or object end", &token);

        json_next_token(json, &token);
    }
}

/* Handle the array context */
static void json_parse_array_context(lua_State *l, json_parse_t *json)
{
    json_token_t token;
    int i;

    /* 2 slots required:
     * .., table, value */
    json_decode_descend(l, json, 2);

    lua_newtable(l);

    json_next_token(json, &token);

    /* Handle empty arrays */
    if (token.type == T_ARR_END) {
        json_decode_ascend(json);
        return;
    }

    for (i = 1; ; i++) {
        json_process_value(l, json, &token);
        lua_rawseti(l, -2, i);            /* arr[i] = value */

        json_next_token(json, &token);

        if (token.type == T_ARR_END) {
            json_decode_ascend(json);
            return;
        }

        if (token.type != T_COMMA)
            json_throw_parse_error(l, json, "comma or array end", &token);

        json_next_token(json, &token);
    }
}

/* Handle the "value" context */
static void json_process_value(lua_State *l, json_parse_t *json,
                               json_token_t *token)
{
    switch (token->type) {
    case T_STRING:
        lua_pushlstring(l, token->value.string, token->string_len);
        break;;
    case T_NUMBER:
        lua_pushnumber(l, token->value.number);
        break;;
    case T_INTEGER:
        lua_pushinteger(l, token->value.lint);
        break;;
    case T_BOOLEAN:
        lua_pushboolean(l, token->value.boolean);
        break;;
    case T_OBJ_BEGIN:
        json_parse_object_context(l, json);
        break;;
    case T_ARR_BEGIN:
        json_parse_array_context(l, json);
        break;;
    case T_NULL:
        /* In Lua, setting "t[k] = nil" will delete k from the table.
         * Hence a NULL pointer lightuserdata object is used instead */
        lua_pushlightuserdata(l, NULL);
        break;;
    default:
        json_throw_parse_error(l, json, "value", token);
    }
}
static int json_decode(lua_State *l)
{
    json_parse_t json;
    json_token_t token;
    size_t json_len;

    luaL_argcheck(l, lua_gettop(l) == 1, 1, "expected 1 argument");

    //json.cfg = json_fetch_config(l);
    json.data = luaL_checklstring(l, 1, &json_len);
    json.current_depth = 0;
    json.ptr = json.data;

    /* Detect Unicode other than UTF-8 (see RFC 4627, Sec 3)
     *
     * CJSON can support any simple data type, hence only the first
     * character is guaranteed to be ASCII (at worst: '"'). This is
     * still enough to detect whether the wrong encoding is in use. */
    if (json_len >= 2 && (!json.data[0] || !json.data[1]))
        luaL_error(l, "JSON parser does not support UTF-16 or UTF-32");

    /* Ensure the temporary buffer can hold the entire string.
     * This means we no longer need to do length checks since the decoded
     * string must be smaller than the entire json string */
    json.tmp = strbuf_new(json_len);
    if (json.tmp == NULL) {
        LLOGE("json decode out of memory!");
        return 0;
    }

    json_next_token(&json, &token);
    json_process_value(l, &json, &token);

    /* Ensure there is no more input left */
    json_next_token(&json, &token);


    if (token.type != T_END)
        json_throw_parse_error(l, &json, "the end", &token);

    strbuf_free(json.tmp);

    return 1;
}

/* ===== INITIALISATION ===== */

#if !defined(LUA_VERSION_NUM) || LUA_VERSION_NUM < 502
/* Compatibility for Lua 5.1.
 *
 * luaL_setfuncs() is used to create a module table where the functions have
 * json_config_t as their first upvalue. Code borrowed from Lua 5.2 source. */
static void luaL_setfuncs (lua_State *l, const luaL_Reg *reg, int nup)
{
    int i;

    luaL_checkstack(l, nup, "too many upvalues");
    for (; reg->name != NULL; reg++) {  /* fill the table with given functions */
        for (i = 0; i < nup; i++)  /* copy upvalues to the top */
            lua_pushvalue(l, -nup);
        lua_pushcclosure(l, reg->func, nup);  /* closure with those upvalues */
        lua_setfield(l, -(nup + 2), reg->name);
    }
    lua_pop(l, nup);  /* remove upvalues */
}
#endif
#if 0
/* Call target function in protected mode with all supplied args.
 * Assumes target function only returns a single non-nil value.
 * Convert and return thrown errors as: nil, "error message" */
static int json_protect_conversion(lua_State *l)
{
    int err;

    /* Deliberately throw an error for invalid arguments */
    luaL_argcheck(l, lua_gettop(l) == 1, 1, "expected 1 argument");

    /* pcall() the function stored as upvalue(1) */
    lua_pushvalue(l, lua_upvalueindex(1));
    lua_insert(l, 1);
    err = lua_pcall(l, 1, 1, 0);
    if (!err)
        return 1;

    if (err == LUA_ERRRUN) {
        lua_pushnil(l);
        lua_insert(l, -2);
        return 2;
    }

    /* Since we are not using a custom error handler, the only remaining
     * errors are memory related */
    return luaL_error(l, "Memory allocation error in CJSON protected call");
}
#endif
/*
将对象序列化为json字符串
@api json.encode(obj,t)
@obj 需要序列化的对象
@string 浮点数精度和模式,这项不存在的时候,为默认值"7f",数字只支持"0~14",模式只支持"f/g"
@return string 序列化后的json字符串, 失败的话返回nil
@return string 序列化失败的报错信息
@usage
json.encode(obj)-->浮点数用%.7g的方式转换为字符串
json.encode(obj,"12f")-->浮点数用%.12f的方式转换为字符串

-- 2024.1.9 起, 默认使用7f格式化浮点数
-- 之前的版本使用 7g格式化浮动数
*/
static int l_json_encode_safe(lua_State *L) {
    // int top = lua_gettop(L);
    if (lua_isnil(L, 1)) {
        lua_pushliteral(L, "");
        return 1;
    }
    memcpy(float_fmt, "%.7f", strlen("%.7f") + 1);
    size_t len = 0;
	// int prec = 0;
    // char buff[6] = {0};
	if (lua_isstring(L, 2)) {
		const char* mode = luaL_checklstring(L, 2, &len);
        //LLOGD("json format ? %s", mode);
        if (len > 1 && len < 8 && (mode[len - 1] == 'g' || mode[len - 1] == 'f')) {
            if (mode[0] == '%') {
                memcpy(float_fmt, mode, len + 1);
            }
            else {
                memcpy(float_fmt + 2, mode, len + 1);
            }
        }
    }
    //LLOGD("float_fmt [%s]", float_fmt);
    lua_pushcfunction(L, json_encode);
    lua_pushvalue(L, 1);
    int status = lua_pcall(L, 1, 1, 0);
    if (status != LUA_OK) {
        const char* err = lua_tostring(L, -1);
        lua_pushnil(L);
        lua_pushstring(L, err);
        return 2;
    }
    return 1;
}

/*
将字符串反序列化为对象
@api json.decode(str)
@string 需要反序列化的json字符串
@return obj 反序列化后的对象(通常是table), 失败的话返回nil
@return result 成功返回1,否则返回0
@return err 反序列化失败的报错信息
@usage
json.decode("[1,2,3,4,5,6]")
*/
static int l_json_decode_safe(lua_State *L) {
    int top = lua_gettop(L);
    lua_pushcfunction(L, json_decode);
    lua_insert(L, 1);
    int status = lua_pcall(L, top, 1, 0);
    if (status != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        lua_pushnil(L);
        lua_pushboolean(L, 0);
        lua_pushstring(L, msg);
        return 3;
    }
    else {
        lua_pushinteger(L, 1);
        return 2;
    }
}

#include "rotable2.h"
static const rotable_Reg_t reg_json[] = {
        { "encode", ROREG_FUNC(l_json_encode_safe)},
        { "decode", ROREG_FUNC(l_json_decode_safe)},
        // { "encode_sparse_array", json_cfg_encode_sparse_array },
        // { "encode_max_depth", json_cfg_encode_max_depth },
        // { "decode_max_depth", json_cfg_decode_max_depth },
        // { "encode_number_precision", l_json_cfg_encode_number_precision , 0},
        // { "encode_keep_buffer", json_cfg_encode_keep_buffer },
        // { "encode_invalid_numbers", json_cfg_encode_invalid_numbers },
        // { "decode_invalid_numbers", json_cfg_decode_invalid_numbers },
        // { "new", lua_cjson_new },
        { "null",  ROREG_PTR(NULL)},
        { NULL, ROREG_INT(0)}
    };

/* Return cjson module table */
static int lua_cjson_new(lua_State *l)
{


    /* Initialise number conversions */
    //fpconv_init();

    /* cjson module table */
    //lua_newtable(l);

    /* Register functions with config data as upvalue */
    //json_create_config(l);
    //luaL_setfuncs(l, reg, 1);

    /* Set cjson.null */
    //lua_pushlightuserdata(l, NULL);
    //lua_setfield(l, -2, "null");

    // /* Set module name / version fields */
    // lua_pushliteral(l, CJSON_MODNAME);
    // lua_setfield(l, -2, "_NAME");
    // lua_pushliteral(l, CJSON_VERSION);
    // lua_setfield(l, -2, "_VERSION");

    luat_newlib2(l, reg_json);

    return 1;
}

// /* Return cjson.safe module table */
// static int lua_cjson_safe_new(lua_State *l)
// {
//     const char *func[] = { "decode", "encode", NULL };
//     int i;

//     lua_cjson_new(l);

//     /* Fix new() method */
//     lua_pushcfunction(l, lua_cjson_safe_new);
//     lua_setfield(l, -2, "new");

//     for (i = 0; func[i]; i++) {
//         lua_getfield(l, -1, func[i]);
//         lua_pushcclosure(l, json_protect_conversion, 1);
//         lua_setfield(l, -2, func[i]);
//     }

//     return 1;
// }

int luaopen_cjson(lua_State *l)
{
    memcpy(float_fmt, "%.7g", strlen("%.7g") + 1);
    lua_cjson_new(l);

// #ifdef ENABLE_CJSON_GLOBAL
//     /* Register a global "cjson" table. */
//     lua_pushvalue(l, -1);
//     lua_setglobal(l, CJSON_MODNAME);
// #endif

    /* Return cjson table */
    return 1;
}

// int luaopen_cjson_safe(lua_State *l)
// {
//     lua_cjson_safe_new(l);

//     /* Return cjson.safe table */
//     return 1;
// }

/* vi:ai et sw=4 ts=4:
 */

