--[[
@module  hmeta_app
@summary hmeta应用功能模块
@version 1.0
@date    2026.08.14
@author  沈园园
@usage
本文件为hmeta应用功能模块，核心业务逻辑为：
1、获取模组名称；
2、获取模组硬件版本号；
3、获取原始芯片型号；
4、获取模组muid；
5、获取模组识别id；

本文件没有对外接口，直接在main.lua中require "hmeta_app"就可以加载运行；
]]

-- hmeta任务主函数
local function hmeta_task_func()
    sys.wait(1000)      -- 等待系统稳定，1000ms

    -- [1/5] 获取模组名称
    log.info("hmeta_app", "===== [1/5] 获取模组名称 =====")
    -- 打印模组名称，如Air724UG
    log.info("hmeta", hmeta.model())
    sys.wait(500)       -- 步骤间隔，500ms

    -- [2/5] 获取模组硬件版本号
    log.info("hmeta_app", "===== [2/5] 获取模组硬件版本号 =====")
    -- 打印模组硬件版本号，如A11
    log.info("hmeta", hmeta.hwver())
    sys.wait(500)       -- 步骤间隔，500ms

    -- [3/5] 获取原始芯片型号
    log.info("hmeta_app", "===== [3/5] 获取原始芯片型号 =====")
    -- 打印原始芯片型号，如8910
    log.info("hmeta", hmeta.chip())
    sys.wait(500)       -- 步骤间隔，500ms

    -- [4/5] 获取模组muid
    log.info("hmeta_app", "===== [4/5] 获取模组muid =====")
    -- 打印模组muid，32字节的字符串，如果不支持，会返回空字符串
    log.info("hmeta", hmeta.muid())
    sys.wait(500)       -- 步骤间隔，500ms

    -- [5/5] 获取模组识别id
    log.info("hmeta_app", "===== [5/5] 获取模组识别id =====")
    -- 打印模组识别id，4G模组即为IMEI
    log.info("hmeta", hmeta.devid())
    sys.wait(500)       -- 步骤间隔，500ms

    log.info("hmeta_app", "===== [演示完毕] =====")

    -- 循环演示，每隔3秒获取一次模组信息
    while true do
        -- 打印模组名称、硬件版本号、原始芯片型号
        log.info("hmeta", hmeta.model(), hmeta.hwver(), hmeta.chip())
        -- 打印模组muid（模组唯一标识，32字节字符串）
        log.info("hmeta", "muid:", hmeta.muid())
        -- 打印模组识别id（4G模组即为IMEI）
        log.info("hmeta", "devid:", hmeta.devid())
        sys.wait(3000)  -- 每隔三秒钟获取一次模组信息
    end
end

-- 创建一个task，并且运行task的主函数hmeta_task_func
sys.taskInit(hmeta_task_func)
