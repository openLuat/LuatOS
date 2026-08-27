--[[
@mainpage SIP-VoLTE 音频桥接测试 Demo
@description
4G模组作为 SIP ↔ VoLTE 音频网关测试程序

配置:
- 4G模组 SIP 用户名: 1903CFC1
- 远程 SIP 客户端: 1903CFC0
- 目标手机号: 13781142418
- SIP服务器: 180.152.6.34:8910

PC模拟器运行命令:
  build\out\luatos-lua.exe test\143.sip_bridge_demo\scripts\

手动控制(PC模拟器):
  1. 启动后自动注册SIP并等待
  2. 通过 UDP 端口 15002 发送命令:
     python test_controller.py <cmd> [args]

呼出测试:
  1. SIP客户端1903CFC0 拨打 SIP 1903CFC1
  2. 4G模组自动接听 SIP
  3. 4G模组自动拨打手机 13781142418
  4. 手机接听后，音频桥接

呼入测试:
  1. 手机来电
  2. 4G模组自动拨打 SIP 1903CFC0
  3. 1903CFC0 接听 SIP
  4. 4G模组再接听手机来电
  5. 音频桥接

音频控制:
  - 通过 local_audio 参数控制是否打开本地麦克风/喇叭
  - true: 本地可以听到/说话（混音模式）
  - false: 本地静音，仅桥接两端

底层音频桥接机制:
  - voip 模块运行在 AUDIO_MODE_BRIDGE 模式，不直接控制 I2S
  - cc 库独占 I2S，负责手机端音频采集/播放
  - 底层固件在 cc 音频回调中自动完成 PCM 双向交换（C层）
  - 详见 docs/sip_voip_audio_bridge_analysis.md
]]

PROJECT = "SIP_BRIDGE_DEMO"
VERSION = "1.0.0"
PRODUCT_KEY = "SIP_BRIDGE"

-- 加载核心库
require "sys"
require "sysplus"

-- 加载音频驱动（真机初始化ES8311）
local audio_drv = nil
local exaudio = nil
local ok, result = pcall(function() return require("audio_drv") end)
if ok then
    audio_drv = result
    local ok2, result2 = pcall(function() return require("exaudio") end)
    if ok2 then
        exaudio = result2
    else
        log.warn(PROJECT, "exaudio 在 PC 上不可用")
    end
else
    log.warn(PROJECT, "audio_drv 不可用，跳过")
end

-- 加载桥接代理模块
local bridge = require("sip_bridge_agent")

-- ==================== 命令解析表 ====================

local commands = {}

commands["help"] = function()
    print("=" .. string.rep("=", 56))
    print("  SIP-VoLTE 音频桥接测试 - 命令帮助")
    print("=" .. string.rep("=", 56))
    print("  start              - 启动桥接代理(已自动启动)")
    print("  stop               - 停止桥接代理")
    print("  status             - 查看当前状态")
    print("  dial [number]      - 手动拨打手机(呼出测试)")
    print("  dial_sip [uri]     - 手动拨打 SIP 号码(呼入测试)")
    print("  answer             - 手动接听 SIP 来电")
    print("  answer_mobile      - 手动接听手机来电")
    print("  hangup             - 挂断所有通话")
    print("  audio [on|off]     - 打开/关闭本地音频")
    print("  incoming [number]  - 模拟手机来电(测试)")
    print("  auto [on|off]      - 打开/关闭手机来电自动桥接到 SIP")
    print("  mobile_auto [on|off] - 打开/关闭手机来电自动接听")
    print("  help               - 显示本帮助")
    print("=" .. string.rep("=", 56))
end

commands["status"] = function()
    local state = bridge.get_state()
    print("\n----- 当前状态 -----")
    print("  运行状态:", state.started and "已启动" or "未启动")
    print("  SIP 注册:", state.sip_registered and "已注册" or "未注册")
    print("  SIP 状态:", state.sip_state)
    print("  CC 状态:", state.cc_state)
    print("  CC 就绪:", state.cc_ready and "是" or "否")
    print("  通话中:", state.in_call and "是" or "否")
    print("  通话方向:", state.call_direction or "无")
    print("  通话时长:", state.call_duration or 0, "秒")
    print("  本地音频:", state.local_audio and "打开" or "关闭")
    print("  手机来电自动桥接:", state.auto_mobile_incoming and "打开" or "关闭")
    print("  手机来电自动接听:", state.auto_answer_mobile_incoming and "打开" or "关闭")
    print("--------------------\n")
end

commands["stop"] = function()
    bridge.stop()
    print("桥接代理已停止")
end

commands["dial"] = function(args)
    local number = args[1] or "13781142418"
    print("拨打手机:", number)
    bridge.dial_phone(number)
end

commands["dial_sip"] = function(args)
    local uri = args[1] or "sip:1903CFC0@180.152.6.34"
    print("拨打 SIP:", uri)
    bridge.dial_sip(uri)
end

commands["answer"] = function()
    print("接听 SIP 来电...")
    bridge.answer_sip()
end

commands["answer_mobile"] = function()
    print("接听手机来电...")
    bridge.answer_mobile()
end

commands["hangup"] = function()
    print("挂断所有通话...")
    bridge.hangup_all()
end

commands["audio"] = function(args)
    local mode = args[1] or "on"
    if mode == "on" or mode == "1" or mode == "true" then
        bridge.set_local_audio(true)
        print("本地音频已打开")
    else
        bridge.set_local_audio(false)
        print("本地音频已关闭")
    end
end

commands["incoming"] = function(args)
    local number = args[1] or "13800138000"
    local delay = tonumber(args[2]) or 100
    print("模拟手机来电:", number, "延迟:", delay, "ms")
    bridge.simulate_mobile_incoming(number, delay)
end

commands["auto"] = function(args)
    local mode = args[1] or "on"
    local enabled = mode == "on" or mode == "1" or mode == "true"
    bridge.set_auto_mobile_incoming(enabled)
    print("手机来电自动桥接:", enabled and "打开" or "关闭")
end

commands["mobile_auto"] = function(args)
    local mode = args[1] or "on"
    local enabled = mode == "on" or mode == "1" or mode == "true"
    bridge.set_auto_answer_mobile_incoming(enabled)
    print("手机来电自动接听:", enabled and "打开" or "关闭")
end

-- ==================== 命令处理 ====================

local function process_command(line)
    if not line or #line == 0 then
        return
    end
    line = line:match("^%s*(.-)%s*$")
    if #line == 0 then
        return
    end
    
    local parts = {}
    for part in line:gmatch("%S+") do
        parts[#parts + 1] = part
    end
    
    local cmd = parts[1]
    local args = {}
    for i = 2, #parts do
        args[#args + 1] = parts[i]
    end
    
    local handler = commands[cmd]
    if handler then
        local ok, err = pcall(handler, args)
        if not ok then
            print("命令执行错误:", err)
        end
    else
        print("未知命令:", cmd, "输入 'help' 查看帮助")
    end
end

-- ==================== UDP 命令监听 ====================

local function start_udp_cmd_listener()
    local cmd_port = 15002
    local cmd_sock = nil
    
    if socket and socket.udp then
        cmd_sock = socket.udp()
        if cmd_sock then
            cmd_sock:bind("127.0.0.1", cmd_port)
            log.info(PROJECT, "UDP 命令监听:", "127.0.0.1:" .. cmd_port)
            
            sys.taskInit(function()
                while true do
                    local data, ip, port = cmd_sock:recv(1024)
                    if data and #data > 0 then
                        data = data:match("^%s*(.-)%s*$")
                        log.info(PROJECT, "UDP命令:", data, "来自", ip .. ":" .. port)
                        process_command(data)
                        
                        -- 发送状态回显
                        local state = bridge.get_state()
                        local resp = string.format(
                            "SIP:%s CC:%s Call:%s Audio:%s AutoBridge:%s AutoAnswer:%s Dir:%s",
                            state.sip_state,
                            state.cc_state,
                            state.in_call and "yes" or "no",
                            state.local_audio and "on" or "off",
                            state.auto_mobile_incoming and "on" or "off",
                            state.auto_answer_mobile_incoming and "on" or "off",
                            state.call_direction or "-"
                        )
                        cmd_sock:send(resp, ip, port)
                    end
                    sys.wait(50)
                end
            end)
            return true
        end
    end
    return false
end

-- ==================== 启动流程 ====================

sys.taskInit(function()
    -- 等待网络就绪
    sys.waitUntil("IP_READY", 10000)
    bridge.set_local_audio(false)
    print("  → 本地音频已关闭")
    
    log.info(PROJECT, "=" .. string.rep("=", 50))
    log.info(PROJECT, "SIP-VoLTE 音频桥接 Demo 启动中...")
    log.info(PROJECT, "=" .. string.rep("=", 50))
    
    -- 初始化音频（真机）
    if audio_drv and audio_drv.init then
        local audio_ok = audio_drv.init()
        if audio_ok then
            log.info(PROJECT, "音频初始化成功")
        else
            log.warn(PROJECT, "音频初始化失败或跳过（PC模拟器）")
        end
    end
    
    -- 启动桥接代理
    local ok = bridge.start()
    if ok then
        log.info(PROJECT, "桥接代理启动成功!")
        log.info(PROJECT, "SIP 用户:", "1903CFC1")
        log.info(PROJECT, "远程 SIP:", "1903CFC0")
        log.info(PROJECT, "目标手机:", "13781142418")
        log.info(PROJECT, "=" .. string.rep("=", 50))
    else
        log.error(PROJECT, "桥接代理启动失败!")
    end
    
    
    -- ========== PC模拟器 ==========
    if rtos.bsp() == "PC" then
        -- 启动 UDP 命令监听
        start_udp_cmd_listener()
    
        -- 启动定时状态打印
        sys.timerLoopStart(function()
            local state = bridge.get_state()
            log.info(PROJECT, "心跳:", 
                "SIP=" .. state.sip_state,
                "CC=" .. state.cc_state,
                "Call=" .. (state.in_call and "Y" or "N"),
                "Dir=" .. (state.call_direction or "-"),
                "Dur=" .. state.call_duration .. "s"
            )
        end, 10000)
        
        -- 延迟显示帮助信息
        sys.timerStart(function()
            print("\n")
            commands["help"]()
            print("\n  [提示] 使用 python test_controller.py <cmd> 进行控制\n")
        end, 3000)

        -- ========== 自动测试流程 ==========
        sys.taskInit(function()
            sys.wait(8000)  -- 等系统启动
            print("\n===== [自动测试] 开始 =====\n")
            
            -- 测试1: 呼出场景
            -- 模拟 SIP 来电（1903CFC0 拨打 1903CFC1）
            print("[测试1] 呼出场景：模拟 SIP 来电...")
            print("  → 1903CFC0 拨打 SIP 1903CFC1")
            print("  → 4G模组应自动接听 SIP")
            print("  → 4G模组应自动拨打手机 13781142418")
            -- 注：在 PC 模拟器上，cc_stub 可能无法模拟完整的通话流程
            -- 但可以验证状态机转换
            
            -- 手动触发 dial 测试
            print("\n[手动测试] 拨打手机...")
            bridge.dial_phone("13781142418")
            sys.wait(2000)
            commands["status"]()
            sys.wait(2000)
            
            print("\n[手动测试] 挂断...")
            bridge.hangup_all()
            sys.wait(1000)
            commands["status"]()
            sys.wait(2000)
            
            -- 测试2: 呼入场景
            print("\n[测试2] 呼入场景：模拟手机来电...")
            bridge.simulate_mobile_incoming("13800138000", 100)
            sys.wait(2000)
            commands["status"]()
            sys.wait(2000)
            
            print("\n[测试3] 音频控制测试...")
            bridge.set_local_audio(false)
            print("  → 本地音频已关闭")
            sys.wait(1000)
            bridge.set_local_audio(true)
            print("  → 本地音频已打开")
            sys.wait(1000)
            
            print("\n===== [自动测试] 完成 =====\n")
            print("  请使用 UDP 命令进行手动测试:")
            print("  python test_controller.py status")
            print("  python test_controller.py dial")
            print("  python test_controller.py hangup")
            print("  python test_controller.py incoming")
            print("  python test_controller.py audio off")
            print("  python test_controller.py audio on")
        end)
    end
end)

-- 监听系统事件
sys.subscribe("IP_READY", function()
    log.info(PROJECT, "网络已就绪")
end)

sys.subscribe("IP_LOSE", function()
    log.warn(PROJECT, "网络已断开")
end)

-- ==================== 程序入口 ====================
sys.run()
