--[[
@module  conf
@summary IMM-6 注塑六号单元，伺服注塑机 PLC 主控 - 板级与业务参数
@version 1.0
@date    2026.11.15
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51

本工程是一台虚构的伺服注塑单元的操作面板。
锁模力、注射压力、料筒温度等由 code/sim.lua 的本地工艺模型演化，不接真实控制器。
PLC 侧只做位号与扫描周期的演示，不对应任何真实固件。
]]
return {
    W = 1024,
    H = 600,

    name    = "注塑六号单元",
    brand   = "IMM-6",
    slogan  = "伺服注塑机，PLC 主控",
    version = "1.0.0",

    machine = {
        name     = "IMM-6 伺服注塑单元",
        model    = "SE-1800 / 320",
        site     = "华东精密塑料，二号车间 B 线",
        molds    = "M-2043 连接器壳体",
        clamp    = 1800,      -- 锁模力 kN
        screw    = 40,        -- 螺杆直径 mm
        shot     = 320,       -- 理论注射量 cm3
        commission = "2022.04",
    },

    plc = {
        cpu      = "CTRL-1500",
        firmware = "V3.2.7",
        rack     = "机架 0，槽位 1-6",
        cycle_ms = 3.4,       -- 标称扫描周期
    },

    backlight = {
        pwm_ch  = 3,
        freq    = 1000,
        default = 82,
        min     = 10,
    },

    -- GT911：与 factory/config/eng_8607_10i_v0.lua 对齐
    touch = {
        port    = 1,
        pin_rst = 14,
        pin_int = 51,
    },

    font = {
        size       = 16,
        cache_size = 1024,
        antialias  = 1,
    },

    sim = {
        interval_ms = 1000,   -- 采样周期（1 拍 = 1 秒机台时间）
        history     = 120,    -- 工艺曲线保留样本数
        clock_step  = 1,
    },

    anim = {
        frame_ms = 110,
        slow_ms  = 440,
    },

    -- 调试开关：帧耗时探针。定位完卡顿后改成 false，避免日志干扰
    debug = {
        profile = false,
    },

    -- ===== 成型周期分段 =====
    -- dur 单位为秒，与采样周期一致，一炮 28 秒
    stages = {
        { key = "close",   name = "合模",   short = "合模",  dur = 3.2, color = 0x58C8F0 },
        { key = "inject",  name = "注射",   short = "注射",  dur = 2.6, color = 0xFF6A3D },
        { key = "hold",    name = "保压",   short = "保压",  dur = 6.0, color = 0xFFD166 },
        { key = "cool",    name = "冷却",   short = "冷却",  dur = 9.5, color = 0x3FE0A6 },
        { key = "open",    name = "开模",   short = "开模",  dur = 2.8, color = 0xA98BFF },
        { key = "eject",   name = "顶出",   short = "顶出",  dur = 1.6, color = 0x2AA79B },
        { key = "takeout", name = "取件",   short = "取件",  dur = 2.3, color = 0x9BA8BC },
    },

    -- ===== 料筒加热区 =====
    -- set 为设定温度，lo/hi 为允许带宽，dhi 为联锁上限
    barrel = {
        { key = "z1", name = "一段", set = 240, lo = 238, hi = 243, dhi = 250 },
        { key = "z2", name = "二段", set = 238, lo = 236, hi = 241, dhi = 248 },
        { key = "z3", name = "三段", set = 232, lo = 230, hi = 235, dhi = 242 },
        { key = "z4", name = "四段", set = 226, lo = 224, hi = 229, dhi = 236 },
        { key = "z5", name = "喷嘴", set = 238, lo = 236, hi = 241, dhi = 248 },
    },

    -- ===== 工艺参数（设定值）=====
    process = {
        { key = "vinj",  name = "注射速度",  val = 52,  unit = "mm/s", max = 90,  color = 0xFF6A3D },
        { key = "phold", name = "保压压力",  val = 620, unit = "bar",  max = 1200, color = 0xFFD166 },
        { key = "thold", name = "保压时间",  val = 6.0, unit = "s",    max = 15,  color = 0xFFB13C },
        { key = "tcool", name = "冷却时间",  val = 9.5, unit = "s",    max = 25,  color = 0x3FE0A6 },
        { key = "pbak",  name = "熔胶背压",  val = 85,  unit = "bar",  max = 200, color = 0x58C8F0 },
        { key = "suck",  name = "松退量",    val = 4.0, unit = "mm",   max = 12,  color = 0xA98BFF },
        { key = "ejn",   name = "顶出次数",  val = 2,   unit = "次",   max = 5,   color = 0x2AA79B },
        { key = "flow",  name = "冷却流量",  val = 12.4, unit = "L/min", max = 20, color = 0x3FE0A6 },
    },

    -- ===== I/O 点表 =====
    -- DI 16 点
    di = {
        { tag = "I0.0", name = "启动按钮" },
        { tag = "I0.1", name = "停止按钮" },
        { tag = "I0.2", name = "安全门闭合" },
        { tag = "I0.3", name = "模具闭合到位" },
        { tag = "I0.4", name = "机械手原点" },
        { tag = "I0.5", name = "料温到达" },
        { tag = "I0.6", name = "开模到位" },
        { tag = "I0.7", name = "急停回路" },
        { tag = "I1.0", name = "顶针到位" },
        { tag = "I1.1", name = "料斗料位" },
        { tag = "I1.2", name = "模温机运行" },
        { tag = "I1.3", name = "冷却水流量" },
        { tag = "I1.4", name = "液压油位" },
        { tag = "I1.5", name = "润滑压力" },
        { tag = "I1.6", name = "安全光幕" },
        { tag = "I1.7", name = "门锁反馈" },
    },

    -- DO 16 点
    dout = {
        { tag = "Q0.0", name = "合模阀" },
        { tag = "Q0.1", name = "注射阀" },
        { tag = "Q0.2", name = "保压阀" },
        { tag = "Q0.3", name = "开模阀" },
        { tag = "Q0.4", name = "顶针阀" },
        { tag = "Q0.5", name = "熔胶马达" },
        { tag = "Q0.6", name = "机械手取件" },
        { tag = "Q0.7", name = "故障指示" },
        { tag = "Q1.0", name = "报警蜂鸣" },
        { tag = "Q1.1", name = "模温机加热" },
        { tag = "Q1.2", name = "冷却水阀" },
        { tag = "Q1.3", name = "料斗干燥" },
        { tag = "Q1.4", name = "输送带" },
        { tag = "Q1.5", name = "三色灯绿" },
        { tag = "Q1.6", name = "三色灯黄" },
        { tag = "Q1.7", name = "三色灯红" },
    },

    -- AI 8 通道
    ai = {
        { tag = "AI0", name = "注射压力", unit = "bar", max = 1600, color = 0xFF6A3D },
        { tag = "AI1", name = "模腔压力", unit = "bar", max = 1200, color = 0xFFD166 },
        { tag = "AI2", name = "锁模力",   unit = "kN",  max = 1800, color = 0x58C8F0 },
        { tag = "AI3", name = "螺杆位置", unit = "mm",  max = 100,  color = 0xA98BFF },
        { tag = "AI4", name = "熔胶背压", unit = "bar", max = 200,  color = 0x3FE0A6 },
        { tag = "AI5", name = "料筒一段", unit = "℃",  max = 260,  color = 0xFFB13C },
        { tag = "AI6", name = "模温",     unit = "℃",  max = 90,   color = 0x3FE0A6 },
        { tag = "AI7", name = "冷却水温", unit = "℃",  max = 40,   color = 0x58C8F0 },
    },

    -- AO 4 通道
    ao = {
        { tag = "AO0", name = "比例阀给定", unit = "%",   max = 100 },
        { tag = "AO1", name = "背压给定",   unit = "bar", max = 200 },
        { tag = "AO2", name = "模温给定",   unit = "℃",  max = 90 },
        { tag = "AO3", name = "顶出速度",   unit = "%",   max = 100 },
    },

    -- 背板模块
    modules = {
        { tag = "槽 1", name = "CPU CTRL-1500", note = "3.4 ms" },
        { tag = "槽 2", name = "DI 16 x 24V",   note = "16/16" },
        { tag = "槽 3", name = "DO 16 x 24V",   note = "16/18" },
        { tag = "槽 4", name = "AI 8 x 0-10V",  note = "8/8" },
        { tag = "槽 5", name = "AO 4 x 0-10V",  note = "4/4" },
        { tag = "槽 6", name = "PN 通信模块",   note = "100M" },
    },

    -- ===== 梯形图 =====
    --[[
    每条 rung 由若干 element 组成，element 的 kind：
      no   常开触点（通则闭）
      nc   常闭触点
      coil 输出线圈
      wire 导线
    var 为位号，name 为中文注释，state 为取状态的键（由 sim.ladder() 提供）
    ]]
    ladder = {
        {
            no = "M0.0", title = "运行自锁",
            note = "启动后自锁，停止或故障断开",
            rungs = {
                { kind = "no",   var = "I0.0", name = "启动" },
                { kind = "nc",   var = "I0.1", name = "停止" },
                { kind = "no",   var = "M0.6", name = "安全链" },
                { kind = "coil", var = "M0.0", name = "运行" },
            },
            branch = { var = "M0.0", name = "自锁", from = 0, to = 3 },
        },
        {
            no = "M0.1", title = "合模允许",
            note = "安全门与机械手原点双条件，缺一不合模",
            rungs = {
                { kind = "no",   var = "M0.0", name = "运行" },
                { kind = "no",   var = "I0.2", name = "安全门" },
                { kind = "no",   var = "I0.4", name = "手原点" },
                { kind = "nc",   var = "I0.3", name = "模到位" },
                { kind = "coil", var = "Q0.0", name = "合模阀" },
            },
        },
        {
            no = "M0.2", title = "注射条件",
            note = "模闭到位且料温到达，T1 延时 0.4 s",
            rungs = {
                { kind = "no",   var = "Q0.0", name = "合模阀" },
                { kind = "no",   var = "I0.3", name = "模到位" },
                { kind = "no",   var = "I0.5", name = "料温" },
                { kind = "no",   var = "T1",   name = "延时" },
                { kind = "coil", var = "Q0.1", name = "注射阀" },
            },
        },
        {
            no = "M0.3", title = "保压与冷却",
            note = "注射转保压，保压完成后进入冷却计时",
            rungs = {
                { kind = "no",   var = "Q0.1", name = "注射阀" },
                { kind = "nc",   var = "Q0.2", name = "保压阀" },
                { kind = "no",   var = "I0.3", name = "模到位" },
                { kind = "coil", var = "Q0.2", name = "保压阀" },
            },
        },
        {
            no = "M0.4", title = "开模顶出",
            note = "冷却结束开模，开模到位后顶针动作",
            rungs = {
                { kind = "no",   var = "T2",   name = "冷却完" },
                { kind = "nc",   var = "I0.6", name = "开到位" },
                { kind = "no",   var = "I0.2", name = "安全门" },
                { kind = "coil", var = "Q0.3", name = "开模阀" },
            },
        },
        {
            no = "M0.6", title = "安全链",
            note = "安全型常闭触点，闭合为正常；故障位 Q0.7 取 M0.6 的反",
            rungs = {
                { kind = "no",   var = "I0.7", name = "急停" },
                { kind = "no",   var = "I0.2", name = "安全门" },
                { kind = "no",   var = "I1.6", name = "光幕" },
                { kind = "coil", var = "M0.6", name = "安全链" },
            },
        },
    },

    -- ===== 设备体检 =====
    health = {
        { key = "oil",    name = "液压油温",   unit = "℃",   dec = 1, base = 46.2, jitter = 0.3, lo = 20, hi = 60, dhi = 70 },
        { key = "servo",  name = "伺服电流",   unit = "A",    dec = 1, base = 18.4, jitter = 0.4, lo = 0,  hi = 28, dhi = 34 },
        { key = "clean",  name = "油液污染度", unit = "级",   dec = 0, base = 7,    jitter = 0.1, lo = 0,  hi = 8,  dhi = 9 },
        { key = "water",  name = "冷却水流量", unit = "L/min", dec = 1, base = 12.4, jitter = 0.2, lo = 9,  hi = 16, dlo = 7 },
        { key = "wear",   name = "顶针磨损量", unit = "mm",   dec = 2, base = 0.18, jitter = 0.01, lo = 0, hi = 0.5, dhi = 0.8 },
        { key = "lube",   name = "润滑压力",   unit = "bar",  dec = 1, base = 32.6, jitter = 0.4, lo = 24, hi = 40, dlo = 20 },
    },

    -- ===== 演示场景 =====
    -- after = 第 n 次采样后触发；fault 段用于演示联锁停车与恢复
    scenario = {
        { after = 42,  kind = "fault", fault = "door",     text = "安全门被打开，合模回路断开，循环中止", level = "danger" },
        { after = 58,  kind = "clear", fault = "door",     text = "安全门复位，等待重新启动" },
        { after = 96,  kind = "note",  text = "模具 M-2043 已连续生产 1200 模，安排清模" },
        { after = 128, kind = "fault", fault = "overtemp", text = "料筒二段温度超上限 248 ℃，加热输出封锁", level = "danger" },
        { after = 156, kind = "clear", fault = "overtemp", text = "料筒二段温度回落至 238 ℃，联锁解除" },
        { after = 208, kind = "fault", fault = "robot",    text = "机械手未返回原点，合模条件不满足", level = "warn" },
        { after = 222, kind = "clear", fault = "robot",    text = "机械手已回原点，允许合模" },
    },
}
