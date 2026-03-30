--[[
@title mGBA GBA模拟器演示
@author LuatOS Team
@date 2026.03.23
@demo mgba

这是一个运行 GBA 游戏的示例程序

使用方法：
1. 将 GBA ROM 文件放到本目录下，重命名为 game.gba
   或者在命令行参数中指定 ROM 路径
2. 运行程序即可开始游戏

默认按键映射：
  X      -> A 按钮
  Z      -> B 按钮
  Enter  -> START
  Shift  -> SELECT
  方向键 -> 方向
  A      -> L 肩键
  S      -> R 肩键
  ESC    -> 退出游戏
]]

-- 加载系统库
_G.sys = require("sys")

-- 默认 ROM 路径 (相对于脚本目录)
local DEFAULT_ROM = "/luadb/game.gba"

-- 打印帮助信息
local function print_help()
    log.info("========== mGBA 模拟器 ==========")
    log.info("按键说明:")
    log.info("  X      - A 按钮")
    log.info("  Z      - B 按钮")
    log.info("  Enter  - START")
    log.info("  Shift  - SELECT")
    log.info("  方向键 - 方向")
    log.info("  A      - L 肩键")
    log.info("  S      - R 肩键")
    log.info("  ESC    - 退出游戏")
    log.info("================================")
end

-- 主游戏任务
sys.taskInit(function()
    log.info("mGBA", "初始化模拟器...")
    sys.wait(100)  -- 等待系统稳定
    
    -- 检查 gba 模块
    if not gba then
        log.error("mGBA", "gba 模块未加载")
        log.error("mGBA", "请检查固件是否编译了 LUAT_USE_MGBA")
        return
    end
    
    -- 打印模块信息
    log.info("mGBA", string.format("KEY_A=0x%X, KEY_B=0x%X, KEY_START=0x%X", 
        gba.KEY_A, gba.KEY_B, gba.KEY_START))
    
    -- 获取 ROM 路径
    local rom_path = DEFAULT_ROM
    
    -- 检查命令行参数 (如果有)
    -- TODO: 从命令行获取 ROM 路径
    
    log.info("mGBA", "ROM 路径: " .. rom_path)
    
    -- 检查文件是否存在
    local file = io.open(rom_path, "rb")
    if not file then
        log.error("mGBA", "ROM 文件不存在: " .. rom_path)
        log.error("mGBA", "请将 GBA ROM 文件放到: " .. DEFAULT_ROM)
        log.error("mGBA", "支持格式: .gba, .gb, .gbc")
        return
    end
    file:close()
    
    -- 初始化模拟器
    log.info("mGBA", "正在初始化...")
    local ok, err = gba.init({
        scale = 2,           -- 2倍缩放 (480x320)
        audio = true,        -- 启用音频
        sample_rate = 44100, -- 采样率
        title = "LuatOS mGBA", -- 窗口标题
        fullscreen = false,  -- 窗口模式
        vsync = true         -- 启用垂直同步
    })
    
    if not ok then
        log.error("mGBA", "初始化失败: " .. tostring(err))
        return
    end
    
    log.info("mGBA", "初始化成功")
    sys.wait(100)
    
    -- 加载 ROM
    log.info("mGBA", "正在加载 ROM...")
    ok, err = gba.load(rom_path)
    if not ok then
        log.error("mGBA", "加载 ROM 失败: " .. tostring(err))
        gba.deinit()
        return
    end
    
    log.info("mGBA", "ROM 加载成功")
    sys.wait(100)
    
    -- 获取游戏信息
    local info = gba.get_info()
    if info then
        log.info("mGBA", "========== 游戏信息 ==========")
        log.info("mGBA", "标题: " .. tostring(info.title))
        log.info("mGBA", "代码: " .. tostring(info.code))
        log.info("mGBA", "平台: " .. tostring(info.platform))
        log.info("mGBA", "分辨率: " .. tostring(info.width) .. "x" .. tostring(info.height))
        log.info("mGBA", "ROM大小: " .. tostring(info.rom_size) .. " bytes")
        log.info("mGBA", "==============================")
    end

    -- 打印帮助
    print_help()

    -- 开始游戏
    log.info("mGBA", "游戏开始! 按 ESC 退出")
    log.info("mGBA", "--------------------------------")
    
    -- 运行游戏 (gba.run() 会阻塞直到用户按 ESC)
    gba.run()
    
    log.info("mGBA", "游戏结束")
    
    -- 清理资源
    gba.deinit()
    log.info("mGBA", "资源已释放")
end)

-- 启动系统
sys.run()