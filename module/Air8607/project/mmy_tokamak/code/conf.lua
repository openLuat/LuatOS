--[[
@module  conf
@summary HELIOS-1 逐日一号，聚变放电控制台 - 板级与业务参数
@version 1.0
@date    2026.11.12
@board   Air8607（Air1603）+ 10.1寸 RGB 1024x600 + GT911 电容触摸 + PWM3 背光

硬件引脚与 factory/config/eng_8607_10i_v0.lua 对齐：
  LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
  背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst=14 pin_int=51

本工程是一台虚构的紧凑型托卡马克实验装置的中控大屏。
所有物理量由 code/sim.lua 的本地模型演化，不接真实传感器。
]]
return {
    W = 1024,
    H = 600,

    name    = "逐日一号",
    brand   = "HELIOS-1",
    slogan  = "紧凑型托卡马克，聚变放电控制中枢",
    version = "1.0.0",

    machine = {
        name     = "HELIOS-1 紧凑型托卡马克",
        site     = "合肥，聚变科学中心 B 区",
        campaign = "C-07 高约束模式实验",
        shots    = 1284,       -- 当前炮号
        R0       = 1.85,       -- 大半径 m
        a        = 0.58,       -- 小半径 m
        Bt       = 3.50,       -- 环向磁场 T
        Ip_max   = 2.00,       -- 最大等离子体电流 MA
        volume   = 22.6,       -- 等离子体体积 m3
        commission = "2021.09",
        wall     = "钨偏滤器 + 铍第一壁",
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
        interval_ms = 1000,   -- 采样周期
        history     = 60,     -- 每条曲线保留样本数
        clock_step  = 30,     -- 每采样推进的“装置秒”
    },

    anim = {
        frame_ms     = 110,   -- 等离子体 / 粒子动画帧
        slow_ms      = 440,   -- 辉光 / 流程慢刷新帧
        spectrum_cols = 26,
        spectrum_rows = 6,
    },

    -- 调试开关：帧耗时探针。定位完卡顿后改成 false，避免日志干扰
    debug = {
        profile = true,
    },

    -- ===== 放电时序 =====
    -- dur 单位为采样次数（1 次 = 1 秒演示时间）
    phases = {
        { key = "pump",     name = "抽真空",  short = "抽气", dur = 6,  color = 0x5C6885 },
        { key = "preion",   name = "预电离",  short = "预电离", dur = 4, color = 0x9B7BFF },
        { key = "ramp",     name = "电流爬升", short = "爬升", dur = 10, color = 0x53E0FF },
        { key = "flat",     name = "平顶",    short = "平顶", dur = 10, color = 0x45E0A8 },
        { key = "heat",     name = "辅助加热", short = "加热", dur = 16, color = 0xFF5E9E },
        { key = "rampdown", name = "电流下降", short = "下降", dur = 7,  color = 0xFFC24B },
        { key = "cooldown", name = "冷却复位", short = "复位", dur = 7,  color = 0x3B4A6B },
    },

    -- ===== 辅助加热系统 =====
    heating = {
        { key = "nbi",  name = "中性束 NBI",  short = "NBI",  max = 12, base = 8.0, unit = "MW", color = 0xFF8A5E },
        { key = "ecrh", name = "电子回旋 ECRH", short = "ECRH", max = 6,  base = 4.0, unit = "MW", color = 0x53E0FF },
        { key = "icrh", name = "离子回旋 ICRH", short = "ICRH", max = 6,  base = 3.0, unit = "MW", color = 0x9B7BFF },
    },

    -- ===== 子系统 =====
    subsystems = {
        { key = "tf",     name = "环向场电源", icon = "bolt",   note = "12.4 kA",   on = true },
        { key = "pf",     name = "极向场电源", icon = "magnet", note = "6 组线圈",  on = true },
        { key = "nbi",    name = "中性束注入", icon = "beam",   note = "8.0 MW",    on = true },
        { key = "ecrh",   name = "电子回旋",   icon = "wave",   note = "4.0 MW",    on = true },
        { key = "icrh",   name = "离子回旋",   icon = "wave",   note = "3.0 MW",    on = true },
        { key = "cryo",   name = "低温系统",   icon = "snow",   note = "4.35 K",    on = true },
        { key = "vacuum", name = "真空泵组",   icon = "pump",   note = "3.2e-6 Pa", on = true },
        { key = "div",    name = "偏滤器水冷", icon = "drop",   note = "96 ℃",      on = true },
    },

    -- ===== 磁约束参数（演示基准值）=====
    magnetic = {
        kappa  = 1.72,   -- 拉长比
        delta  = 0.42,   -- 三角形变
        q95    = 3.60,   -- 95% 安全因子
        betaN  = 2.40,   -- 归一化比压
        energy = 18.6,   -- 储能 MJ
        li     = 0.92,   -- 内感
        zeff   = 1.80,   -- 有效电荷数
        ngw    = 0.85,   -- 密度极限比
    },

    -- 极向场线圈：pos = 截面上的相对位置（见 ui_magnetic）
    pf_coils = {
        { key = "P1", name = "P1", base =  8.4, pos = "lt" },
        { key = "P2", name = "P2", base = -3.2, pos = "lm" },
        { key = "P3", name = "P3", base =  5.6, pos = "lb" },
        { key = "P4", name = "P4", base =  2.1, pos = "rt" },
        { key = "P5", name = "P5", base = -6.8, pos = "rm" },
        { key = "P6", name = "P6", base =  4.2, pos = "rb" },
    },

    cryo = {
        he_inventory = 82,     -- 液氦储量 %
        t_4k   = 4.35,         -- 4.5 K 冷屏
        t_80k  = 78.0,         -- 80 K 冷屏
        t_supp = 296.0,        -- 室温支撑
        t_cold = 12.0,         -- 冷泵冷头
        p_loop = 4.20,         -- 氦回路压力 bar
        flow   = 128,          -- 冷却水流量 m3/h
        compressor = 82,       -- 压缩机负荷 %
    },

    vacuum = {
        p_vessel = 3.2e-6,     -- 真空室压力 Pa
        p_nbi    = 1.8e-5,     -- 中性束注入器真空 Pa
        leak     = 1.2e-9,     -- 漏率 Pa m3/s
        rga = {                -- 残余气体成分（相对丰度）
            { name = "H2",  val = 46, color = 0x53E0FF },
            { name = "H2O", val = 28, color = 0x9B7BFF },
            { name = "CO",  val = 12, color = 0xFF8A5E },
            { name = "CH4", val = 9,  color = 0xFFC24B },
            { name = "N2",  val = 5,  color = 0x5C6885 },
        },
    },

    -- ===== 设备体检 =====
    -- lo/hi 为关注区间，dhi 为报警上限
    health = {
        { key = "tf_temp",  name = "环向场线圈温度", unit = "℃",   dec = 1, base = 62.0,  jitter = 0.4, lo = 20, hi = 85,  dhi = 95 },
        { key = "valve_p",  name = "低温阀箱压力",   unit = "bar",  dec = 2, base = 4.20,  jitter = 0.02, lo = 3.4, hi = 5.2, dhi = 6.0 },
        { key = "water",    name = "冷却水流量",     unit = "m3/h", dec = 0, base = 128,   jitter = 1.1, lo = 90, hi = 150, dlo = 70 },
        { key = "nbi_vac",  name = "中性束真空",     unit = "e-5 Pa", dec = 2, base = 1.80, jitter = 0.03, lo = 0.8, hi = 3.2, dhi = 4.5 },
        { key = "div_temp", name = "偏滤器水温",     unit = "℃",   dec = 1, base = 96.0,  jitter = 0.6, lo = 40, hi = 120, dhi = 140 },
        { key = "pf",       name = "电网功率因数",   unit = "",     dec = 2, base = 0.98,  jitter = 0.004, lo = 0.92, hi = 1.00 },
    },

    -- ===== 演示事件注入 =====
    -- after = 第 n 次采样后触发；一炮 60 拍，事件刻意跨炮分布，让演示有起伏也有恢复
    events = {
        { after = 26,  text = "ELM 爆发，偏滤器热负荷瞬时 8.4 MW/m2", level = "warn" },
        { after = 88,  text = "密度接近 Greenwald 极限 0.92，注气阀自动关小", level = "warn" },
        { after = 100, text = "1 号中性束弧流异常，自动降功率至 5.2 MW", level = "danger", device = "nbi", off = true },
        { after = 155, text = "4.5 K 回路压力波动，低温系统自动补偿完成", level = "warn" },
        { after = 176, text = "1 号中性束检修完成，恢复 8 MW 注入", level = "ok", device = "nbi", on = true },
        { after = 236, text = "偏滤器水温回落至 96 ℃，水冷回路稳定", level = "ok" },
    },
}
