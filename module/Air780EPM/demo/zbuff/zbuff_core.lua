 --[[
    @module  zbuff_core
    @summary zbuff的基础操作模块
    @version 1.0.0
    @date    2025.08.08
    @author  王棚嶙
    @usage
    本文件为zbuff的基础操作模块，包含zbuff最常用的基础功能：

    1. 缓冲区创建与初始化
    2. 基础功能操作（读写）
    3. 指针控制
    4. 元信息查询
    5. 高效数据查询（query接口）
    本文件没有对外接口，直接在main.lua中require "zbuff_core"就可以加载运行
    ]]
    
       
local function zbuff_core_task_func()
    log.info("zbuff_core", "启动核心功能演示")
    
    -- 创建1024字节的缓冲区
    local buff = zbuff.create(1024)
    log.info("zbuff_core", "缓冲区创建", "长度:", buff:len()) -- 打印缓冲区长度
    -- === 缓冲区创建与初始化演示 ===
    log.info("zbuff_core", "=== 缓冲区创建与初始化演示 ===")
    buff[0] = 0xAE -- 通过索引直接访问和修改数据（索引从0开始）
    log.info("zbuff_core", "索引访问示例", "buff[0] =", buff[0])


    
    -- === 基础读写操作演示 ===
    log.info("zbuff_core", "=== 基础IO操作演示 ===")
    --此处的读写操作只作为演示，具体的读取数据看后续的buff:query接口
    --buff：write()中的参数可以是任意类型，zbuff会自动进行类型转换，写入buff的数据，string时为一个参数，number时可为多个参数

    buff:write("123")
    log.info("zbuff_core", "写入字符串", "123")
    buff:write(0x12, 0x13, 0x13, 0x33)
    log.info("zbuff_core", "写入数值", "0x12, 0x13, 0x13, 0x33")
    
    buff:seek(5, zbuff.SEEK_CUR)
    log.info("zbuff_core", "指针当前位置", "向后移动5字节","当前位置:", buff:used())
    
    buff:seek(0)
    log.info("zbuff_core", "指针移动", "重置到开头")
    
    local data = buff:read(3)
    log.info("zbuff_core", "读取数据", "长度3:",data)
   
    

    -- === 缓冲区清除操作 ===
    log.info("zbuff_core", "=== 缓冲区清除操作 ===")
    buff:clear()
    log.info("zbuff_core", "清除操作", "全部清零")
    
    buff:clear(0xA5)
    log.info("zbuff_core", "清除操作", "填充0xA5")
    


    -- === 元信息查询 ===
    log.info("zbuff_core", "=== 元信息查询 ===")
    local len = buff:len()
    log.info("zbuff_core", "元信息", "总长度:", len)
    
    local used = buff:used()
    log.info("zbuff_core", "元信息", "已使用:", used)
    


    -- === 高效数据查询 ===
    log.info("zbuff_core", "=== 高效数据查询 ===")
    buff:clear()
    buff:seek(0)
    buff:write(0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC)
    
    local all_data = buff:query(0, 6)
    log.info("zbuff_core", "query查询", "全部数据:" ,all_data:toHex())
     -- 查询部分数据并转换格式,查询1,2，4,8字节的时候会自动根据后续参数进行转换（大端序、无符号）
    -- 参数：起始位置0，长度4，大端序，无符号，非浮点
    local part_data = buff:query(0, 4, true, false, false)
    log.info("zbuff_core", "query查询", "大端序格式:", part_data)
    
    log.info("zbuff_core", "核心功能演示完成")
end

sys.taskInit(zbuff_core_task_func)