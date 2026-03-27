-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "miniz_test"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    log.info("test", "开始测试 miniz.unzip 功能")
    
    -- 测试文件路径
    local zip_file = "/luadb/csdk.zip"
    local target_dir = "/ram/"
    
    -- 确保测试文件存在
    if not io.exists(zip_file) then
        log.error("test", "测试ZIP文件不存在:", zip_file)
        os.exit(1)
        return
    end
    
    log.info("test", "解压文件:", zip_file, "到目录:", target_dir)
    
    -- 调用 unzip 函数
    local success = miniz.unzip(zip_file, target_dir)
    
    if success then
        log.info("test", "解压成功！")
        -- 看看/ram/csdk.lua是否存在
        if io.exists(target_dir .. "csdk.lua") then
            log.info("test", "解压后的文件 csdk.lua 存在！")
            -- 检测文件大小
            local file_size = io.fileSize(target_dir .. "csdk.lua")
            log.info("test", "csdk.lua 文件大小:", file_size, "字节")
        else
            log.error("test", "解压后的文件 csdk.lua 不存在！")
        end

        -- 列出解压后的文件
        local ok, files = io.lsdir(target_dir)
        if files then
            log.info("test", "解压后的文件列表:")
            for i, file in pairs(files) do
                log.info("test", "-", i, json.encode(file))
            end
            os.exit(0)
        else
            log.info("test", "无法列出解压后的文件")
            os.exit(2)
        end
    else
        log.error("test", "解压失败！")
        os.exit(1)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!