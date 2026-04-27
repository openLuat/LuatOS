--[[
@module  hmeta_app
@summary hmeta_app应用功能模块 
@version 1.0
@date    2025.10.20
@author  沈园园
@usage
本文件为hmeta应用功能模块，核心业务逻辑为：
1、获取模块相关信息包括获取模组名称，硬件版本号，原始芯片型号；

本文件没有对外接口，直接在main.lua中require "hmeta_app"就可以加载运行；
]]


local function hmeta_task_func()
    while true do
        -- 打印模组名称，硬件版本号，原始芯片型号
        log.info("hmeta", hmeta.model(), hmeta.hwver(), hmeta.chip())
        sys.wait(3000)
    end
end

--创建一个task，并且运行task的主函数hmeta_task_func
sys.taskInit(hmeta_task_func)
