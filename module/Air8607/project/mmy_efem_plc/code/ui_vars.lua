--[[
@module  ui_vars
@summary 界面变量绑定表（组件 <- 变量），按页分组
@version 1.0.0
@date    2026.11.20
@usage
PLCUI 的 label 运行时只能改文本（没有 set_color），绑定表里只出现 text。
曲线由 ui_app.chart_tick 用 chart:add_point 追加，不在这里绑定。
对外接口 1 个：ui_vars.bind_list(page)。
]]

local ui_vars = {}

ui_vars.PAGES = {
    -- 总览：时钟 / 吞吐 / 机械手 / 事件流 / 流转终点
    overview = {
        { id = "tp_clock", var = "clock" },
        { id = "kp_wph",   var = "kp_wph" },
        { id = "kp_ut",    var = "kp_ut" },
        { id = "kp_ok",    var = "kp_ok" },
        { id = "rb_v0",    var = "rb_v0" },
        { id = "rb_v1",    var = "rb_v1" },
        { id = "rb_v2",    var = "rb_v2" },
        { id = "rb_v3",    var = "rb_v3" },
        { id = "fl_to",    var = "fl_to" },
        { id = "ev_t0",    var = "ev_t0" },
        { id = "ev_x0",    var = "ev_x0" },
        { id = "ev_t1",    var = "ev_t1" },
        { id = "ev_x1",    var = "ev_x1" },
        { id = "ev_t2",    var = "ev_t2" },
        { id = "ev_x2",    var = "ev_x2" },
    },

    -- 时序：甘特与占用率是定值，只刷时钟
    timing = {
        { id = "tp_clock", var = "clock" },
    },

    -- 曲线：只有四张图
    curve = {
        { id = "tp_clock", var = "clock" },
    },

    -- 点位：AO 给定、诊断行、诊断表
    io = {
        { id = "tp_clock", var = "clock" },
        { id = "ao_v0",    var = "ao_v0" },
        { id = "ao_v1",    var = "ao_v1" },
        { id = "ao_v2",    var = "ao_v2" },
        { id = "dg_l1",    var = "dg_l1" },
    },

    -- 系统：背光、运行、维护计数
    sys = {
        { id = "tp_clock", var = "clock" },
        { id = "br_v",     var = "br_v" },
        { id = "rd_v0",    var = "rd_v0" },
        { id = "rd_v1",    var = "rd_v1" },
        { id = "rd_v2",    var = "rd_v2" },
        { id = "rd_v3",    var = "rd_v3" },
        { id = "mt_v0",    var = "mt_v0" },
        { id = "mt_v1",    var = "mt_v1" },
        { id = "mt_v2",    var = "mt_v2" },
        { id = "mt_v3",    var = "mt_v3" },
    },
}

function ui_vars.bind_list(page)
    return ui_vars.PAGES[page] or {}
end

return ui_vars
