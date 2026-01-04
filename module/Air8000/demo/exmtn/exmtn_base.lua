--[[
@module  exmtn_base
@summary exmtn_base测试功能模块
@version 1.0
@date    2025.12.10
@author  马亚丹
@usage
本demo演示的功能为：使用Air8000核心板演示exmtn扩展库的基础使用。

核心逻辑：
1.初始化exmtn,并获取配置状态

2.输出日志并写入日志到运维日志文件

3.读取并打印四个运维日志文件中的内容


]]



-- 引入 exmtn 模块
local exmtn = require "exmtn"


--定义日志内容
temp_log = "\n"
for i = 1, 5 do
    temp_log = temp_log .. "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\n"
end

--定义功能函数： 初始化exmtn,获取配置状态
local function exmtn_config()
    local config = exmtn.get_config()
    log.info("获取配置状态", config)
    if config then
        log.info("当前 exmtn 的配置状态",
            "enabled:", config.enabled,
            "cur_index:", config.cur_index,
            "block_size:", config.block_size,
            "blocks_per_file:", config.blocks_per_file,
            "file_limit:", config.file_limit,
            "write_way:", config.write_way)
    end
end


--定义功能函数： 每5秒读取并打印四个运维日志文件中的内容
local function read_log()
    while true do
        sys.wait(5000)
        log.info("mtn_read", "开始读取运维日志文件...")

        -- 遍历四个运维日志文件
        for idx = 1, 4 do
            local file_path = string.format("/hzmtn%d.trc", idx)
            local file = io.open(file_path, "rb")

            if file then
                local content = file:read("*a")
                file:close()

                if content and #content > 0 then
                    -- log.info("mtn_read", string.format("文件 %s 内容:", file_path),"文件大小：",fs.fsize(file_path),content)
                    log.info("mtn_read", string.format("文件 %s 内容:", file_path), "文件大小：", fs.fsize(file_path))
                else
                    log.info("mtn_read", string.format("文件 %s 为空", file_path))
                end
            else
                log.warn("mtn_read", string.format("无法打开文件: %s", file_path))
            end
        end

        log.info("mtn_read", "运维日志文件读取完成")
    end
end

--主函数
local function exmtn_test()
    -- 初始化exmtn 设置为1个区块
    local result = exmtn.init(1, exmtn.CACHE_WRITE)
    log.info("初始化结果", result)

    if not result then
        log.info("初始化失败", result)
        return
    end
    --初始化成功读取配置状态
    exmtn_config()

    local test_count = 0
    --输出日志并写入日志到运维日志文件
    while true do
        test_count = test_count + 1

        exmtn.log("info", "test mtn info_log", test_count)
        exmtn.log("warn", "test mtn warn_log", test_count)
        exmtn.log("error", "test mtn error_log", test_count)
        exmtn.log("info", temp_log, test_count)
        --每2秒写入一次
        sys.wait(2000)
    end
end

sys.taskInit(exmtn_test)
sys.taskInit(read_log)
