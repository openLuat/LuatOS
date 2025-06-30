# 第二层：LuatOS框架层

## 层级定位
LuatOS框架层是整个系统的核心，位于Lua虚拟机和组件库之间，负责将Lua脚本调用转换为底层硬件操作，提供统一的API接口和系统服务。

## 主要职责

### 1. Lua-C绑定
- 将Lua函数调用绑定到C函数实现
- 提供Lua与C之间的数据类型转换
- 管理Lua栈操作和内存分配

### 2. 系统服务管理
- 任务调度和协程管理
- 定时器服务
- 消息总线和事件分发
- 内存管理和垃圾回收

### 3. 硬件抽象
- 统一的硬件接口定义
- 跨平台兼容性支持
- 设备驱动管理

## 核心代码分析

### 1. 系统入口 - luat_main.c

```c
// 文件位置: luat/modules/luat_main.c
// 系统主入口函数
int luat_main_call(void) {
    int status = 0;
    int result = 0;
    
    // 创建Lua状态机
#ifdef LUAT_USE_PROFILER
    L = lua_newstate(luat_profiler_alloc, NULL);
#else
    L = lua_newstate(luat_heap_alloc, NULL);
#endif
    
    if (L == NULL) {
        l_message("lua", "cannot create state: not enough memory\n");
        goto _exit;
    }
    
    // 设置panic处理函数
    if (L) lua_atpanic(L, &panic);
    
    // 调用主程序
    lua_pushcfunction(L, &pmain);
    status = lua_pcall(L, 0, 1, 0);
    result = lua_toboolean(L, -1);
    report(L, status);
    
_exit:
    return result;
}

// 主程序逻辑
static int pmain(lua_State *L) {
    int re = -2;
    char filename[32] = {0};

    // 1. 加载内置库
    luat_openlibs(L);
    lua_gc(L, LUA_GCCOLLECT, 0);
    luat_os_print_heapinfo("loadlibs");

    // 2. 设置垃圾收集参数
    lua_gc(L, LUA_GCSETPAUSE, 90);

    // 3. 自动加载sys和sysplus库
    dolibrary(L, "sys");
    dolibrary(L, "sysplus");
    
    // 4. 查找并执行main.lua
    if (luat_search_module("main", filename) == 0) {
        re = luaL_dofile(L, filename);
    } else {
        luaL_error(L, "module '%s' not found", "main");
    }
    
    report(L, re);
    lua_pushboolean(L, re == LUA_OK);
    return 1;
}
```

### 2. 基础框架 - luat_base.c

```c
// 文件位置: luat/modules/luat_base.c
// 库注册机制
void luat_newlib(lua_State* l, const rotable_Reg* reg) {
#ifdef LUAT_CONF_DISABLE_ROTABLE
    // 标准方式注册库
    luaL_newlibtable(l, reg);
    for (; reg->name != NULL; reg++) {
        if (reg->func)
            lua_pushcclosure(l, reg->func, nup);
        else
            lua_pushinteger(l, reg->value);
        lua_setfield(l, -(nup + 2), reg->name);
    }
#else
    // 使用rotable优化内存
    rotable_newlib(l, reg);
#endif
}

// C等待接口 - 用于异步操作
uint64_t luat_pushcwait(lua_State *L) {
    if(lua_getglobal(L, "sys_cw") != LUA_TFUNCTION) {
        LLOGE("sys lib not found!");
        return 0;
    }
    c_wait_id++;
    char topic[10] = {0};
    topic[0] = 0x01; // 内部消息前缀
    memcpy(topic + 1, &c_wait_id, sizeof(uint64_t));
    lua_pushlstring(L, topic, 1 + sizeof(uint64_t));
    lua_call(L, 1, 1);
    return c_wait_id;
}

// C等待回调
int luat_cbcwait(lua_State *L, uint64_t id, int arg_num) {
    if(lua_getglobal(L, "sys_pub") != LUA_TFUNCTION)
        return 0;
    char* topic = (char*)luat_heap_malloc(1 + sizeof(uint64_t));
    topic[0] = 0x01;
    memcpy(topic + 1, &id, sizeof(uint64_t));
    lua_pushlstring(L, topic, 1 + sizeof(uint64_t));
    luat_heap_free(topic);
    lua_rotate(L, -arg_num-2, 2);
    lua_call(L, arg_num + 1, 0);
    return 1;
}
```

### 3. GPIO库实现 - luat_lib_gpio.c

```c
// 文件位置: luat/modules/luat_lib_gpio.c
// GPIO设置函数
static int l_gpio_setup(lua_State *L) {
    luat_gpio_t conf = {0};
    
    // 参数解析
    conf.pin = luaL_checkinteger(L, 1);
    conf.mode = luaL_optinteger(L, 2, Luat_GPIO_OUTPUT);
    conf.pull = luaL_optinteger(L, 3, default_gpio_pull);
    conf.irq_type = luaL_optinteger(L, 4, 0);
    
    // 中断回调处理
    if (conf.mode == Luat_GPIO_IRQ) {
        if (lua_isfunction(L, 5)) {
            lua_pushvalue(L, 5);
            gpios[conf.pin].lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
            conf.irq_cb = l_gpio_handler;
            conf.irq_args = (void*)(long)conf.pin;
        }
    }
    
    // 调用底层GPIO设置
    int ret = luat_gpio_setup(&conf);
    lua_pushinteger(L, ret);
    return 1;
}

// GPIO中断处理函数
int l_gpio_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    int pin = msg->arg1;
    int level = msg->arg2;
    
    // 防抖处理
    if (gpios[pin].debounce_mode) {
        // 防抖逻辑...
    }
    
    // 调用Lua回调函数
    if (gpios[pin].lua_ref) {
        lua_geti(L, LUA_REGISTRYINDEX, gpios[pin].lua_ref);
        if (lua_isfunction(L, -1)) {
            lua_pushinteger(L, pin);
            lua_pushinteger(L, level);
            lua_call(L, 2, 0);
        }
    }
    return 0;
}

// GPIO库注册表
static const rotable_Reg_t reg_gpio[] = {
    { "setup",           ROREG_FUNC(l_gpio_setup) },
    { "set",             ROREG_FUNC(l_gpio_set) },
    { "get",             ROREG_FUNC(l_gpio_get) },
    { "close",           ROREG_FUNC(l_gpio_close) },
    
    // 常量定义
    { "OUTPUT",          ROREG_INT(Luat_GPIO_OUTPUT) },
    { "INPUT",           ROREG_INT(Luat_GPIO_INPUT) },
    { "IRQ",             ROREG_INT(Luat_GPIO_IRQ) },
    { "PULLUP",          ROREG_INT(Luat_GPIO_PULLUP) },
    { "PULLDOWN",        ROREG_INT(Luat_GPIO_PULLDOWN) },
    { NULL,              ROREG_INT(0) }
};

// 库初始化函数
LUAMOD_API int luaopen_gpio(lua_State *L) {
    luat_newlib2(L, reg_gpio);
    return 1;
}
```

### 4. SPI库实现 - luat_lib_spi.c

```c
// 文件位置: luat/modules/luat_lib_spi.c
// SPI设置函数
static int l_spi_setup(lua_State *L) {
    luat_spi_t spi_config = {0};
    
    // 参数解析
    spi_config.id = luaL_checkinteger(L, 1);
    spi_config.cs = luaL_optinteger(L, 2, 255);
    spi_config.CPHA = luaL_optinteger(L, 3, 0);
    spi_config.CPOL = luaL_optinteger(L, 4, 0);
    spi_config.dataw = luaL_optinteger(L, 5, 8);
    spi_config.bandrate = luaL_optinteger(L, 6, 2000000);
    spi_config.bit_dict = luaL_optinteger(L, 7, 1);
    spi_config.master = luaL_optinteger(L, 8, 1);
    spi_config.mode = luaL_optinteger(L, 9, 1);
    
    // 调用底层SPI设置
    int ret = luat_spi_setup(&spi_config);
    lua_pushinteger(L, ret);
    return 1;
}

// SPI传输函数
static int l_spi_transfer(lua_State *L) {
    int spi_id = luaL_checkinteger(L, 1);
    size_t send_len = 0;
    size_t recv_len = 0;
    const char* send_buf = NULL;
    char* recv_buf = NULL;
    
    // 发送数据处理
    if (lua_isstring(L, 2)) {
        send_buf = lua_tolstring(L, 2, &send_len);
    } else if (lua_isuserdata(L, 2)) {
        luat_zbuff_t *buff = tozbuff(L);
        send_buf = (const char*)buff->addr;
        send_len = buff->len;
    }
    
    recv_len = luaL_optinteger(L, 3, send_len);
    
    // 分配接收缓冲区
    if (recv_len > 0) {
        recv_buf = luat_heap_malloc(recv_len);
        if (recv_buf == NULL) {
            LLOGE("内存不足");
            return 0;
        }
    }
    
    // 执行SPI传输
    int ret = luat_spi_transfer(spi_id, send_buf, send_len, recv_buf, recv_len);
    
    if (recv_buf && ret >= 0) {
        lua_pushlstring(L, recv_buf, ret);
        luat_heap_free(recv_buf);
        return 1;
    }
    
    if (recv_buf) luat_heap_free(recv_buf);
    return 0;
}
```

## 系统服务机制

### 1. 消息总线 - luat_msgbus.h

```c
// 消息结构定义
typedef struct rtos_msg {
    uint32_t handler;     // 消息处理函数
    uint32_t ptr;         // 消息数据指针
    uint32_t arg1;        // 参数1
    uint32_t arg2;        // 参数2
} rtos_msg_t;

// 消息发送
int luat_msgbus_put(rtos_msg_t* msg, size_t timeout);

// 消息接收
int luat_msgbus_get(rtos_msg_t* msg, size_t timeout);
```

### 2. 内存管理 - luat_mem.h

```c
// 内存分配接口
void* luat_heap_malloc(size_t len);
void luat_heap_free(void* ptr);
void* luat_heap_realloc(void* ptr, size_t len);

// 内存信息查询
void luat_meminfo_luavm(size_t* total, size_t* used, size_t* max_used);
void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used);

// Lua内存分配器
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
```

### 3. 定时器服务 - luat_timer.h

```c
// 定时器结构
typedef struct luat_timer {
    size_t id;
    size_t timeout;
    size_t repeat;
    void* os_timer;
    lua_callback_handler func;
    void* param;
} luat_timer_t;

// 定时器操作
int luat_timer_start(luat_timer_t* timer);
int luat_timer_stop(luat_timer_t* timer);
```

## 跨平台适配

### 1. 弱符号机制
```c
// 弱符号定义，允许平台重写
LUAT_WEAK int luat_gpio_setup(luat_gpio_t* gpio) {
    // 默认空实现
    return -1;
}

LUAT_WEAK int luat_spi_setup(luat_spi_t* spi) {
    // 默认空实现  
    return -1;
}
```

### 2. 条件编译
```c
// 根据平台特性条件编译
#ifdef LUAT_USE_GPIO
    {"gpio", luaopen_gpio},
#endif

#ifdef LUAT_USE_SPI
    {"spi", luaopen_spi},
#endif

#ifdef LUAT_USE_I2C
    {"i2c", luaopen_i2c},
#endif
```

### 3. 配置管理
```c
// 配置头文件 luat_conf_default.h
#ifndef LUAT_GPIO_PIN_MAX
#define LUAT_GPIO_PIN_MAX   (128)
#endif

#ifndef LUAT_SPI_DEVICE_MAX
#define LUAT_SPI_DEVICE_MAX (3)
#endif
```

## 库加载机制

### 1. 库注册表
```c
// luat_libs.h - 库注册表
static const luaL_Reg loadedlibs[] = {
    {"_G", luaopen_base},
    {LUA_TABLIBNAME, luaopen_table},
    {LUA_IOLIBNAME, luaopen_io},
    {LUA_OSLIBNAME, luaopen_os},
    {LUA_STRLIBNAME, luaopen_string},
    {LUA_MATHLIBNAME, luaopen_math},
    {LUA_UTF8LIBNAME, luaopen_utf8},
    {LUA_DBLIBNAME, luaopen_debug},
    {"rtos", luaopen_rtos},
    {"log", luaopen_log},
    {"gpio", luaopen_gpio},
    {"spi", luaopen_spi},
    // ...更多库
    {NULL, NULL}
};
```

### 2. 库初始化
```c
void luat_openlibs(lua_State *L) {
    const luaL_Reg *lib;
    
    // 加载所有注册的库
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);
    }
    
    // 自定义库初始化
#ifdef LUAT_HAS_CUSTOM_LIB_INIT
    luat_custom_init(L);
#endif
}
```

## 错误处理和调试

### 1. 错误报告
```c
static int report(lua_State *L, int status) {
    if (status != LUA_OK) {
        const char *msg = lua_tolstring(L, -1, &len);
        LLOGE("Luat: %s", msg);
        
#ifdef LUAT_USE_ERRDUMP
        luat_errdump_save_file((const uint8_t *)msg, strlen(msg));
#endif
        lua_pop(L, 1);
    }
    return status;
}
```

### 2. 内存监控
```c
void luat_os_print_heapinfo(const char* tag) {
    size_t total, used, max_used;
    luat_meminfo_luavm(&total, &used, &max_used);
    LLOGD("%s luavm %ld %ld %ld", tag, total, used, max_used);
    luat_meminfo_sys(&total, &used, &max_used);
    LLOGD("%s sys   %ld %ld %ld", tag, total, used, max_used);
}
```

LuatOS框架层作为系统的核心，承担着连接上层Lua脚本和底层硬件的重要职责，通过精心设计的架构确保了系统的稳定性、可扩展性和跨平台兼容性。 