--[[
@module  sim_identity
@summary 模拟器“真机身份”适配（PC 模拟器下以 4G 真机身份接入 AirCloud）
@version 1.0.0
@date    2026.09.11
@author  嵌入式软件设计开发代理
@usage
目标：模拟器环境使用模拟器网卡（socket.ETH0），但其余设备身份参数使用真机 4G 参数。

背景：excloud 在 rtos.bsp()=="PC" 时强制按“虚拟设备(device_type=9)”接入，
     且会忽略 setup 传入的 device_type/device_id。本模块在 PC 模拟器（且开启）时，
     用 config_app 中配置的真机参数“替换全局变量” mobile / hmeta / rtos
     （LuatOS 核心库为只读表 rotable，无法改其字段，只能整体替换全局变量；
      官方 netdrv_pc.lua 亦以 _G.mobile = {} 的方式覆盖），
     使 excloud 按“4G 设备(device_type=1，设备ID=IMEI)”接入；网络仍走模拟器网卡。

⚠️ 加载顺序：必须在 netdrv_device 之后 require。
      （netdrv_device 依赖“真实”运行环境选择模拟器网卡，判据取自 config_app.is_pc；本模块会覆盖 rtos.bsp。）

⚠️ 前提：sim_real_imei 必须为“已归属你 IoT 账号项目”的真机 IMEI，否则平台仍会返回“未进项目及白名单”。
      sim_real_muid 可选：留空/占位时按“无 MUID”处理（mobile.muid() 返回 ""）。
      IMEI 未就绪时本模块自动回退为虚拟设备路径。

本模块无对外接口，直接 require "sim_identity" 即加载运行。
]]

local config_app = require("config_app")

-- =========================================================================
-- 覆盖实现（具名函数，符合“除 main.lua 外禁止匿名函数”规范）
-- =========================================================================
local function rtos_bsp_sim()
    return config_app.sim_real_model
end

local function hmeta_model_sim()
    return config_app.sim_real_model
end

local function mobile_imei_sim()
    return config_app.sim_real_imei
end

-- 取 MUID：未配置/占位时按“无 MUID”处理，返回空字符串
local function sim_muid_value()
    local muid = config_app.sim_real_muid
    if type(muid) ~= "string" or #muid == 0 or muid:find("REPLACE") then
        return ""
    end
    return muid
end

local function mobile_muid_sim()
    return sim_muid_value()
end

-- 校验：IMEI 必填（15 位数字）；MUID 可选
local function sim_params_ready()
    local imei = config_app.sim_real_imei
    if type(imei) ~= "string" or #imei ~= 15 or not imei:match("^%d+$") then
        return false, "sim_real_imei 必须为 15 位数字"
    end
    return true
end

-- 执行覆盖：核心库为只读表(rotable)，不能改字段 → 采用“替换全局变量”方式。
-- 用代理表 + __index 转发原库的其它字段，尽量降低影响面。
-- 顺序：先 mobile/hmeta，最后 rtos（任一步失败时 rtos 仍为原库，可自动回退虚拟设备路径）。
local function apply_overrides()
    local real_hmeta = hmeta
    local real_rtos  = rtos

    -- mobile：整体替换为可写表，提供 imei / muid
    _G.mobile = {
        imei = mobile_imei_sim,
        muid = mobile_muid_sim,
    }
    -- hmeta：替换为可写表，覆盖 model，其余字段转发原库
    _G.hmeta = setmetatable({ model = hmeta_model_sim }, { __index = real_hmeta })
    -- rtos：替换为代理表，覆盖 bsp，其余字段（reboot/meminfo 等）转发原库
    _G.rtos = setmetatable({ bsp = rtos_bsp_sim }, { __index = real_rtos })
end

-- =========================================================================
-- 仅在 PC 模拟器 + 启用 + 参数就绪时覆盖；否则保持原逻辑
-- =========================================================================
if config_app.is_pc and config_app.sim_real_identity_enabled then
    local ready, reason = sim_params_ready()
    if ready then
        local ok, err = pcall(apply_overrides)
        if ok then
            if #sim_muid_value() == 0 then
                log.warn("sim_identity", "模拟器以真机(4G)身份接入（未配置 MUID，按无 MUID 处理）",
                         "imei:", config_app.sim_real_imei)
            else
                log.info("sim_identity", "模拟器以真机(4G)身份接入", "model:", config_app.sim_real_model,
                         "imei:", config_app.sim_real_imei)
            end
        else
            log.error("sim_identity", "覆盖核心接口失败，回退为虚拟设备路径", err)
        end
    else
        log.warn("sim_identity", "真机身份参数未就绪，回退为虚拟设备路径：", reason)
    end
end
