#ifndef LUAT_LUAC_REPORT_T
#define LUAT_LUAC_REPORT_T

typedef struct luac_data {
    size_t id; // 文件索引
    union 
    {
      char* data;
      lua_Number nnum;
      lua_Integer nint;
      lu_byte nbyte;
    };
    size_t len;
    lu_byte mark;
    lu_byte type;
    unsigned int hash;
}luac_data_t;

typedef struct luac_data_group {
  luac_data_t data[32*1024];
  size_t count;
  size_t max_len;
  size_t total_len;
  size_t uni_count; // 去重后的数量
  size_t emtrys;
} luac_data_group_t;



// 实现一个与Lua原始function平替的结构体, 用于存储函数信息
typedef struct luf_func {
  size_t id;
  lu_byte numparams;  /* number of fixed parameters */
  lu_byte is_vararg;
  lu_byte maxstacksize;  /* number of registers needed by this function */
  size_t sizeupvalues;  /* size of 'upvalues' */
  size_t sizek;  /* size of 'k' */
  size_t sizecode;
  size_t sizelineinfo;
  size_t sizep;  /* size of 'p' */
  size_t sizelocvars;
  int32_t linedefined;  /* debug information  */
  int32_t lastlinedefined;  /* debug information  */
  size_t sizeupvalues2;  /* size of 'upvalues'的名称信息 */
  luac_data_t **k; // 常量表
  luac_data_t *code; // 指令
  // int *lineinfo;  /* map from opcodes to source lines (debug information) */
  luac_data_t *lineinfo;  /* map from opcodes to source lines (debug information) */
  int *locvars;  /* 本地变量名称的数据1-起始/结束PC值 */
  luac_data_t **locvars2;  /* 本地变量名称的数据2-名称 */
  lu_byte *upvalues;  /* upvalue的stack信息 */
  luac_data_t **upvalues2;  /* upvalue的名称信息 */
  luac_data_t *source;  /* debug information */
  struct luf_func *p[1024];  /* functions defined inside the function */
}luf_func_t;

typedef struct luac_report {
  luac_data_group_t strs;
  // luac_data_group_t funcs;
  luac_data_group_t codes;
  luac_data_group_t numbers;
  luac_data_group_t upvalues;
  luac_data_group_t line_numbers;
  luf_func_t luf_funcs[1024];
  size_t func_count;
} luac_report_t;


typedef struct luac_file {
    char source_file[32];
    luac_report_t* report;
    size_t i;
    const char* ptr;
    size_t fileSize;
    
}luac_file_t;

typedef struct TIO {
    char* ptr;
    const char* begin;
}tio_t;


#endif

