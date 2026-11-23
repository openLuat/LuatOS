--[[
@module  config
@summary 全工程唯一参数表。改参数只改这里，其它文件不要写死数字。
]]

local M = {}

-- ===== 串口 / 485 =====
M.uart = {
    uart_id = 1,      -- UART1 → J21（W1 唯一一路隔离 485）
    baud    = 9600,
    de_pin  = 65,     -- 485_EN1，DE：高=发送，低=接收
    pwr_pin = 64,     -- 485_EN：485 收发芯片单独供电，漏掉它串口能开但总线上没有波形

    --[[ 485 方向控制方式
      true  = 交给固件（uart.setup 第 8/9/10 参数：rs485_gpio / rs485_level / rs485_delay）。
              固件在移位寄存器真正发完之后才换向，时序比 Lua 侧估的准，首选。
      false = Lua 手动翻 GPIO。仅当固件不接受第 8 参数时才用。]]
    rs485_native = true,

    --[[ 485 发送完到切换回接收的延迟，单位 us。
         这个值**不是越大越好**：DE 多压一会儿就等于把总线攥在自己手里，
         PLC 在这段时间开始的应答会撞上自己的发送器，全部收不到 —— 表现就是 100% 超时。
         9600 下一位 104us，2000us 约两位，够让停止位出完、总线释放。
         （同板实测通过的三菱工程用的是 2000，不是官方注释里那个 20000。）]]
    rs485_delay = 2000,
}

-- ===== PLC 计算机链接（格式4）=====
M.plc = {
    enable     = true,   -- PC 模拟器只调界面时设为 false：不轮询、不刷超时日志
    station    = "00",
    pcno       = "FF",
    wait_char  = "0",   -- 帧里的"延时A"字符：0 = 不额外延时（PLC 尽快应答）
    start_addr = 100,   -- D100 起连续读
    count      = 3,     -- D100/D101 AD 值 + D102 心跳
    poll_ms    = 330,   -- 轮询周期（300–500ms 为宜）
    timeout_ms = 500,   -- 单帧超时：FX 的扫描周期 + 485 换向，250ms 太紧
    retry      = 2,     -- 超时重试次数
    crlf       = true,  -- 格式4 必须带 CR LF；格式1 则改 false + D8120=H6387

    --[[ 打印收发原始报文
         true  = 每帧两行日志：十六进制 + 控制码可读形式
                 TX 21B 05 30 30 46 46 57 52 30 44 ... | ENQ 0 0 F F W R 0 D ...
                 RX 23B 02 30 30 46 46 30 34 30 45 ... | STX 0 0 F F 0 4 0 E ...
         调试期开，稳定跑起来后建议关掉（330ms 一帧，一分钟 360 行够刷屏的）。]]
    log_frames = true,
}

-- ===== 通道定义 =====
-- warn / alarm 单位 0.1℃，默认 60.0℃ / 80.0℃
M.channels = {
    { key = "ch1", name = "通道 1", ad_index = 1, warn = 600, alarm = 800 },
    { key = "ch2", name = "通道 2", ad_index = 2, warn = 600, alarm = 800 },
}

-- ===== 换算 =====
-- AD 0~4000 对应 0~10V，0~10V 对应 0~100℃，即 1 码 = 0.025℃
M.scale = {
    ad_full = 4000,
    temp_max = 1000,     -- 温度用 0.1℃ 整数存储，满量程 1000 = 100.0℃
    fault_ad = 30000,    -- ≥ 此值表示输入过压/断线
}

M.filter_alpha = 0.25    -- 一阶滤波系数，越小越平滑
M.hyst = 10              -- 报警回差 1.0℃（0.1℃ 单位）

-- ===== 报警提示 =====
M.alarm = {
    popup            = true,    -- 新报警是否弹窗
    popup_auto_hide  = 20000,   -- 弹窗自动消失时间 ms（0 = 必须手动关）
    speech           = true,    -- 语音播报总开关
    speech_gap       = 10000,   -- 报警持续期间的重复播报间隔 ms（0 = 只播一次）
    speech_timeout   = 15000,   -- 单条播报超时 ms
}

-- 音频通路（J13 喇叭：内置 DAC → HT6873 功放）
M.audio = {
    pa_pin   = 73,    -- AUDIOPA_EN = GPIO73（高有效）
    pa_delay = 10,    -- 起播后延迟拉高 PA，防 POP
    dac_delay = 6,    -- DAC 启动前冗余时间
    vol      = 20,    -- 音量 0-100
}

-- ===== 趋势 =====
M.trend = {
    period_ms = 3000,    -- 每 3 秒落一个点
    points    = 600,     -- 600 点 × 3s = 30 分钟
    y_min     = 0,
    y_max     = 100,
}

-- ===== 屏幕 =====
M.screen = { w = 1024, h = 600 }

--[[ 板级上电时序（顺序不能乱）：{ 引脚, 电平, 之后等待 ms }
     抄自 Air8603W1 出厂板级配置 eng_8603m1_10i_v0.lua。
     重点是 { 64, 1 }：485 收发芯片由 GPIO64 单独供电，漏掉它串口能打开、
     日志一切正常，但总线上一点波形都没有 —— 现象和接错线一模一样。
     { 65, 0 } 把 DE 停在接收态。]]
M.board = {
    --[[ 外部硬件看门狗 Air153D 的喂狗脚。
         860X 板载 Air153D，PIN47 = GPIO57 经 NPN 三极管拉 WTDOG；
         不喂约 12 分钟芯片会拉复位 —— 表现是"跑着跑着自己重启"，很难查。
         固件若不带 exair153x_wdt 库，这里会降级成一条 warning。
         板子上没有这颗芯片就设 false。]]
    wdt_pin = 57,

    power_on = {
        { 12, 1 },        -- 5V_EN
        { 56, 1, 100 },   -- 9V_EN（之后等 100ms）
        { 44, 1 },        -- 12V_EN
        { 52, 1 },        -- 5VOUT_EN
        { 72, 0, 20 },    -- 网络模组 RST
        { 74, 1 },        -- SD_EN
        { 73, 0 },        -- AUDIOPA_EN 关功放（HT6873 高有效）
        { 64, 1 },        -- 485_EN，485 收发芯片供电
        { 65, 0 },        -- 485_EN1 = DE，空闲低电平（接收态）
    },
}

-- 屏与触摸（Air8603W1 + 10 寸 1024×600）
M.lcd = {
    interface = "rgb",
    w = 1024, h = 600,
    hbp = 140, hspw = 20, hfp = 160,
    vbp = 20,  vspw = 3,  vfp = 12,
    pclk_hz = 50 * 1000 * 1000,
    pin_rst = 15,        -- LCD_DISP = GPIO15
    bl_pwm_ch = 3,       -- 背光 PWM3
    bl_freq = 1000,
    bl_duty = 90,
}
M.tp = {
    -- 驱动名只能是 "gt911"。写 "tp_gt911" 会得到
    --   E/tp tp_name:tp_gt911 not found!!!
    -- 然后 tp.init 返回 nil —— 界面能显示但点不动，很容易误判成硬件问题。
    model = "gt911",
    port = 1, pin_rst = 14, pin_int = 51,
    w = 1024, h = 600,      -- 必须与屏一致，缺了会被 input 适配器以 EINVAL 静默拒绝
}

-- ===== 配色 =====
-- 单一来源：theme.lua 的 C 表（含旧命名别名 t2/dim/warn/alarm/primary…）
M.color = require("theme").C

return M
