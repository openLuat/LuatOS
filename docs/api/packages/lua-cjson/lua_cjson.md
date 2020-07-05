---
title: lua_cjson
path: lua-cjson/lua_cjson.c
module: json json操作库
---
--------------------------------------------------
# ch2token

```c
static json_token_type_t ch2token(int ch)
```


## 参数表

Name | Type | Description
-----|------|--------------
**ch**|`int`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`json_token_type_t`| *无*


--------------------------------------------------
# escape2char

```c
static char escape2char(unsigned char c)
```


## 参数表

Name | Type | Description
-----|------|--------------
**c**|`char`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`char`| *无*


--------------------------------------------------
# lua_array_length

```c
static int lua_array_length(lua_State *l, strbuf_t *json)
```

json_append_string args:
- lua_State
- JSON strbuf
- String (Lua stack index)
 *
Returns nothing. Doesn't remove string from Lua stack */
static void json_append_string(lua_State *l, strbuf_t *json, int lindex)
{
    const char *escstr;
    int i;
    const char *str;
    size_t len;

    str = lua_tolstring(l, lindex, &len);

Worst case is len * 6 (all unicode escapes).
This buffer is reused constantly for small strings
If there are any excess pages, they won't be hit anyway.
This gains ~5% speedup. */
    strbuf_ensure_empty_length(json, len * 6 + 2);

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

Find the size of the array on the top of the Lua stack
-1   object (not a pure array)
>=0  elements in array

## 参数表

Name | Type | Description
-----|------|--------------
**l**|`lua_State*`| *无*
**json**|`strbuf_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# json_append_unicode_escape

```c
static int json_append_unicode_escape(json_parse_t *json)
```

===== DECODING ===== */

static void json_process_value(lua_State *l, json_parse_t *json,
                               json_token_t *token);

static int hexdigit2int(char hex)
{
    if ('0' <= hex  && hex <= '9')
        return hex - '0';

Force lowercase */
    hex |= 0x20;
    if ('a' <= hex && hex <= 'f')
        return 10 + hex - 'a';

    return -1;
}

static int decode_hex4(const char *hex)
{
    int digit[4];
    int i;

Convert ASCII hex digit to numeric digit
Note: this returns an error for invalid hex digits, including
     NULL */
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

Converts a Unicode codepoint to UTF-8.
Returns UTF-8 string length, and up to 4 bytes in *utf8 */
static int codepoint_to_utf8(char *utf8, int codepoint)
{
0xxxxxxx */
    if (codepoint <= 0x7F) {
        utf8[0] = codepoint;
        return 1;
    }

110xxxxx 10xxxxxx */
    if (codepoint <= 0x7FF) {
        utf8[0] = (codepoint >> 6) | 0xC0;
        utf8[1] = (codepoint & 0x3F) | 0x80;
        return 2;
    }

1110xxxx 10xxxxxx 10xxxxxx */
    if (codepoint <= 0xFFFF) {
        utf8[0] = (codepoint >> 12) | 0xE0;
        utf8[1] = ((codepoint >> 6) & 0x3F) | 0x80;
        utf8[2] = (codepoint & 0x3F) | 0x80;
        return 3;
    }

11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
    if (codepoint <= 0x1FFFFF) {
        utf8[0] = (codepoint >> 18) | 0xF0;
        utf8[1] = ((codepoint >> 12) & 0x3F) | 0x80;
        utf8[2] = ((codepoint >> 6) & 0x3F) | 0x80;
        utf8[3] = (codepoint & 0x3F) | 0x80;
        return 4;
    }

    return 0;
}


Called when index pointing to beginning of UTF-16 code escape: \uXXXX
\u is guaranteed to exist, but the remaining hex characters may be
missing.
Translate to UTF-8 and append to temporary token string.
Must advance index to the next character to be processed.
Returns: 0   success
        -1  error

## 参数表

Name | Type | Description
-----|------|--------------
**json**|`json_parse_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# json_is_invalid_number

```c
static int json_is_invalid_number(json_parse_t *json)
```

JSON numbers should take the following form:
    -?(0|[1-9]|[1-9][0-9]+)(.[0-9]+)?([eE][-+]?[0-9]+)?
 *
json_next_number_token() uses strtod() which allows other forms:
- numbers starting with '+'
- NaN, -NaN, infinity, -infinity
- hexadecimal numbers
- numbers with leading zeros
 *
json_is_invalid_number() detects "numbers" which may pass strtod()'s
error checking, but should not be allowed with strict JSON.
 *
json_is_invalid_number() may pass numbers which cause strtod()
to generate an error.

## 参数表

Name | Type | Description
-----|------|--------------
**json**|`json_parse_t*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# json_next_token

```c
static void json_next_token(json_parse_t *json, json_token_t *token)
```

Fills in the token struct.
T_STRING will return a pointer to the json_parse_t temporary string
T_ERROR will leave the json->ptr pointer at the error.

## 参数表

Name | Type | Description
-----|------|--------------
**json**|`json_parse_t*`| *无*
**token**|`json_token_t*`| *无*

## 返回值

> *无返回值*


--------------------------------------------------
# l_json_encode_safe

```c
static int l_json_encode_safe(lua_State *L)
```

将对象序列化为json字符串
@api json.encode
@param obj 需要序列化的对象
@return str 序列化后的json字符串, 失败的话返回nil
@return err 序列化失败的报错信息
@usage json.encode(obj)

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


--------------------------------------------------
# l_json_decode_safe

```c
static int l_json_decode_safe(lua_State *L)
```

将字符串反序列化为对象
@api json.decode
@param str 需要反序列化的json字符串
@return obj 反序列化后的对象(通常是table), 失败的话返回nil
@return result 成功返回1,否则返回0
@return err 反序列化失败的报错信息
@usage json.decode("[1,2,3,4,5,6]")

## 参数表

Name | Type | Description
-----|------|--------------
**L**|`lua_State*`| *无*

## 返回值

No. | Type | Description
----|------|--------------
1 |`int`| *无*


