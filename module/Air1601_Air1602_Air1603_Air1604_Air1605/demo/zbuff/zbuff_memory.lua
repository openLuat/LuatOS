    --[[
    @module  zbuff_memory
    @summary zbuff的内存管理模块
    @version 1.0.0
    @date    2025.08.08
    @author  王棚嶙
    @usage
    本文件为zbuff的内存管理模块，核心业务逻辑为内存管理操作,包括：
    1.缓冲区大小调整 
    2.内存块设置 
    3.数据删除
    4.内存比较 
    5.Base64编码转换功能
    本文件没有对外接口，直接在main.lua中require "zbuff_memory"就可以加载运行
    ]]
local function zbuff_memory_task_func()
    --[[内存管理操作演示@param buff zbuff对象]]
    log.info("zbuff_memory", "启动内存管理功能演示")


    -- 1. 调整缓冲区大小
    local buff = zbuff.create(1024)
    local original_size = buff:len()
    buff:resize(2048)  -- 扩容到2048字节
    log.info("zbuff_memory", "大小调整", "原始大小:", original_size, "新大小:", buff:len())
    
    -- 2. 内存块设置（类似memset）
    -- 从位置10开始设置5个字节为0xaa
    buff:set(10,0xaa,5)
    log.info("zbuff_memory", "内存设置", "位置10-14设置为0xaa")
    -- 验证设置结果
    log.info("zbuff_memory", "验证结果", "位置10:", buff[10], "应为0xaa")
    
    -- 3. 数据删除操作
    -- 写入测试数据
    buff:clear()
    buff:seek(0)
    buff:write("ABCDEFGH")
    log.info("zbuff_memory", "删除前数据", buff:toStr())
    
    -- 删除位置2开始的3个字节
    buff:del(2, 3)
    log.info("zbuff_memory", "删除操作", "删除位置2-4", "结果:", buff:toStr())
    
    -- 4. 内存比较
    local buff2 = zbuff.create(10)
    buff2:write("12345")
    
    -- 比较两个缓冲区前5字节内容
    local equal, offset = buff:isEqual(0, buff2, 0, 5)
    log.info("zbuff_memory", "内存比较", "结果:", equal, "差异位置:", offset)
    
    -- 5. Base64编码转换
    local dst = zbuff.create(buff:used() * 2)  -- 创建足够大的目标缓冲区
    
    -- 进行Base64编码
    local len = buff:toBase64(dst)
    log.info("zbuff_memory", "Base64编码", "长度:", len, "结果:", dst:toStr(0, len))

    log.info("zbuff_memory", "内存管理功能演示完成")
end
sys.taskInit(zbuff_memory_task_func)