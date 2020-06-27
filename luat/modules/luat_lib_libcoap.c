/*
@module  socket
@summary socket操作库
@version 1.0
@data    2020.03.30
*/
#include "luat_base.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "luat.libcoap"
#include "luat_log.h"


typedef struct libcoap_header
{
    unsigned int tokenLen: 4 ;
    unsigned int type    : 2 ; // 0 - CON, 1 - NON, 2 - ACK, 3 - RST
    unsigned int version : 2 ;
    uint8_t code;
    uint16_t     msgid;
}libcoap_header_t;

typedef struct libcoap_opt_header
{
    unsigned int opt_len   : 4 ;
    unsigned int opt_delta : 4 ;
}libcoap_opt_header_t;

typedef struct luat_lib_libcoap
{
    libcoap_header_t header;
    char token[9];
    size_t optSize;
    size_t dataSize;
    char opt[256];
    char data[512 - 128];
}luat_lib_libcoap_t;

static uint16_t c_msgid = 1;

#define LUAT_COAP_HANDLE "COAP*"

//-----------------------------------------------------------------
static void addopt(luat_lib_libcoap_t* _coap, uint8_t opt_type, const char* value, size_t len) {
    if (_coap->optSize > 0) { // 检查需要之前的opt

    }
    int cur_opt = opt_type;

    // LLOGD("opt type=%d value len=%d", opt_type, len);
    // LLOGD("opt optSize cur=%d", _coap->optSize);
    _coap->opt[_coap->optSize] = (cur_opt << 4) + (len & 0xF);
    for (size_t i = 0; i < len; i++)
    {
        _coap->opt[_coap->optSize + 1 + i] = *(value + i);
    }
    
    // LLOGD("opt opt first=%d", _coap->opt[_coap->optSize]);
    // char* opt_ptr = _coap->opt;
    // opt_ptr +=  _coap->optSize + 1;
    // memcpy(opt_ptr, value, len);
    _coap->optSize += len + 1;

    
}

// libcoap.new(libcoap.GET, "time", {}, nil)
static int l_libcoap_new(lua_State* L) {
    luat_lib_libcoap_t* _coap;

    // 生成coap结构体
    _coap = (luat_lib_libcoap_t*)lua_newuserdata(L, sizeof(luat_lib_libcoap_t));
    if (_coap == NULL)
    {
        return 0;
    }

    memset(_coap, 0, sizeof(luat_lib_libcoap_t));
    _coap->header.version = 0x01;
    _coap->header.tokenLen = 0;
    _coap->header.msgid = c_msgid ++; // 设置msgid
    luaL_setmetatable(L, LUAT_COAP_HANDLE);

    // 然后根据用户参数设置

    // 首先,是code, 第1参数
    _coap->header.code = luaL_checkinteger(L, 1);

    // 肯定要设置URI的吧, 第2参数
    size_t len = 0;
    const char* uri = luaL_checklstring(L, 2, &len);
    addopt(_coap, 11, uri, len); // Uri-Path = 11

    // 设置其他OPT, 第3参数
    // TODO 是个table吧

    // 最后是data, 第4参数
    if (lua_isstring(L, 4)) {
        const char* payload = luaL_checklstring(L, 4, &len);
        if (len > 512) {
            LLOGE("data limit to 512 bytes");
            lua_pushstring(L, "data limit to 512 bytes");
            lua_error(L);
        }
        _coap->dataSize = len;
        memcpy(_coap->data, payload, len);
    }

    return 1;
}

static int l_libcoap_parse(lua_State* L) {
    size_t len;
    const char* buff = luaL_checklstring(L, 1, &len);
    if (len < 4) {
        return 0; // 最起码得有4个字节呀
    }
    libcoap_header_t *header = (libcoap_header_t *)buff; // 把头部搞一下
    if (header->version != 0x01) {
        LLOGW("bad coap version");
        return 0;
    }
    luat_lib_libcoap_t* _coap;

    // 生成coap结构体
    _coap = (luat_lib_libcoap_t*)lua_newuserdata(L, sizeof(luat_lib_libcoap_t));
    if (_coap == NULL)
    {
        LLOGE("out of memory at libcoap.parse");
        return 0;
    }
    memset(_coap, 0, sizeof(luat_lib_libcoap_t));
    memcpy(_coap, buff, 4);
    luaL_setmetatable(L, LUAT_COAP_HANDLE);
    int idx = 4;

    // 分析一下token
    if (_coap->header.tokenLen > 0) {
        memcpy(_coap->token, buff+len, _coap->header.tokenLen);
        idx += _coap->header.tokenLen;
    }
    // 准备一下指针
    char* ptr = (char*)buff;
    ptr += 4; // 跳过头部
    ptr += _coap->header.tokenLen;

    // 分析opt
    if (idx < len) {
        while (idx < len && *ptr != 0xFF) {
            libcoap_opt_header_t *opt_header = (libcoap_opt_header_t *)ptr;
            if (opt_header->opt_delta == 0xF)
                break;
            LLOGD("found opt %d %d", opt_header->opt_delta, opt_header->opt_len);
            ptr += opt_header->opt_len + 1;
            idx += opt_header->opt_len + 1;
            _coap->optSize += opt_header->opt_len + 1;
        }
        LLOGD("opt size=%d", _coap->optSize);
        memcpy(_coap->opt, ptr - _coap->optSize, _coap->optSize);
    }
    

    // 分析一下data
    if (idx < len) {
        _coap->dataSize = len - idx - 1;
        LLOGD("data size=%d", _coap->dataSize);
        memcpy(_coap->data, ptr+1, _coap->dataSize);
    }

    return 1;
}

//---------------------------------------------
#define tocoap(L)	((luat_lib_libcoap_t *)luaL_checkudata(L, 1, LUAT_COAP_HANDLE))

static int libcoap_msgid(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    lua_pushinteger(L, _coap->header.msgid);
    return 1;
}

static int libcoap_token(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    _coap->token[8] = 0x00; // 确保有结束符
    lua_pushstring(L, _coap->token);
    return 1;
}

static int libcoap_rawdata(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    // 开始合成数据吧
    size_t len = 0;
    char buff[512] = {0}; // 最大长度暂定512

    // 首先, 拷贝头部
    _coap->header.version = 0x01;
    _coap->header.tokenLen =  strlen(_coap->token);
    memcpy(buff, _coap, 4); // 头部固定4个字节
    len += 4;

    //LLOGD("libcoap header len=%d", len);

    // 有没有token呢?
    if (_coap->header.tokenLen > 0) {
        memcpy((char*)(buff) + len, _coap->token, _coap->header.tokenLen);
        len += _coap->header.tokenLen;
        //LLOGD("libcoap add token %ld", _coap->header.tokenLen);
    }

    // 然后处理opt
    if (_coap->optSize > 0) {
        memcpy((char*)(buff) + len, _coap->opt, _coap->optSize);
        len += _coap->optSize;
        //LLOGD("libcoap add opt %ld ,first=%d", _coap->optSize, _coap->opt[0]);
    }

    // 最后添加data
    if (_coap->dataSize > 0) {
        buff[len] = 0xFF;
        len ++;
        memcpy((char*)(buff) + len, _coap->data, _coap->dataSize);
        len += _coap->dataSize;
        //LLOGD("libcoap add data %ld", _coap->dataSize);
    }

    lua_pushlstring(L, buff, len);
    return 1;
}

static int libcoap_code(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    lua_pushinteger(L, _coap->header.code);
    return 1;
}

static int libcoap_type(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    lua_pushinteger(L, _coap->header.type);
    return 1;
}

static int libcoap_data(lua_State *L) {
    luat_lib_libcoap_t *_coap = tocoap(L);
    if (_coap == NULL) {
        LLOGE("coap sturt is NULL");
        lua_pushstring(L, "coap sturt is NULL");
        lua_error(L);
        return 0;
    }
    lua_pushlstring(L, _coap->data, _coap->dataSize);
    return 1;
}

static const luaL_Reg lib_libcoap[] = {
    {"tp",          libcoap_type},
    {"msgid",       libcoap_msgid},
    {"token",       libcoap_token},
    {"code",        libcoap_code},
    {"rawdata",     libcoap_rawdata},
    {"data",        libcoap_data},
    //{"__gc",        libcoap_gc},
    //{"__tostring",  libcoap_tostring},
    {NULL, NULL}
};


static void createmeta (lua_State *L) {
  luaL_newmetatable(L, LUAT_COAP_HANDLE);  /* create metatable for file handles */
  lua_pushvalue(L, -1);  /* push metatable */
  lua_setfield(L, -2, "__index");  /* metatable.__index = metatable */
  luaL_setfuncs(L, lib_libcoap, 0);  /* add file methods to new metatable */
  lua_pop(L, 1);  /* pop new metatable */
}


#include "rotable.h"
#define CODE(H,L) (H << 5 + L)
static const rotable_Reg reg_libcoap[] =
{
    { "new", l_libcoap_new, 0},
    { "parse", l_libcoap_parse, 0},

    // ----- 类型常量
    { "CON",        NULL,   0},
    { "NON",        NULL,   1},
    { "ACK",        NULL,   2},
    { "RST",        NULL,   3},

    // 请求类
    { "NONE",       NULL,   0},
    { "GET",        NULL,   1},
    { "POST",       NULL,   2},
    { "PUT",        NULL,   3},
    { "DELETE",     NULL,   4},

    // 响应类
    // { "Created",    NULL,   CODE(2,1)},
    // { "Deleted",    NULL,   CODE(2,2)},
    // { "Valid",      NULL,   CODE(2,3)},
    // { "Changed",    NULL,   CODE(2,4)},
    // { "Content",    NULL,   CODE(2,5)},

    // { "Bad Request",NULL,   CODE(4,0)},
    // { "Unauthorized",NULL,   CODE(4,1)},
    // { "Bad Option", NULL,   CODE(4,2)},
    // { "Forbidden",  NULL,   CODE(4,3)},
    // { "Not Found",  NULL,   CODE(4,4)},
    // { "Method Not Allowed",NULL,   CODE(4,5)},
    // { "Not Acceptable",    NULL,   CODE(4,6)},
    // { "Precondition Failed",    NULL,   CODE(4,12)},
    // { "Request Entity Too Large",    NULL,   CODE(4,13)},
    // { "Unsupported Content-Format",    NULL,   CODE(4,15)},

    // { "Internal Server Error",    NULL,   CODE(5,0)},
    // { "Not Implemented",    NULL,   CODE(5,1)},
    // { "Bad Gateway",    NULL,   CODE(5,2)},
    // { "Service Unavailable",    NULL,   CODE(5,3)},
    // { "Gateway Timeout",    NULL,   CODE(5,4)},
    // { "Proxying Not Supported",    NULL,   CODE(5,5)},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_libcoap( lua_State *L ) {
    rotable_newlib(L, reg_libcoap);
    createmeta(L);
    return 1;
}
