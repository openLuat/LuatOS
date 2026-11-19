--[[
@module  ui_vars
@summary 界面变量绑定表（组件 <- 变量），按页分组，UI 只按这张表刷数
@version 1.0.0
@date    2026.11.17
@usage
本文件描述「哪个组件的文本，取 data_app.get() 里的哪个键」。
PLCUI 的 label 运行时只能改文本（没有 set_color），
所以状态色一律由「预制色块 + 显隐切换」表达，绑定表里只出现 text。
对外接口 1 个：ui_vars.bind_list(page)。
]]

local ui_vars = {}

ui_vars.PAGES = {
    -- 总览：横幅 / KPI / 拧紧轴 / 报警
    overview = {
        { id = "hd_clock", var = "clock" },
        { id = "hd_cs",    var = "hd_cs" },
        { id = "bn_t",     var = "bn_t" },
        { id = "bn_cyc",   var = "bn_cyc" },
        { id = "kp_v0",    var = "kp_v0" },
        { id = "kp_v1",    var = "kp_v1" },
        { id = "kp_v2",    var = "kp_v2" },
        { id = "kp_v3",    var = "kp_v3" },
        { id = "ax_v0",    var = "ax_v0" },
        { id = "ax_v1",    var = "ax_v1" },
        { id = "ax_v2",    var = "ax_v2" },
        { id = "ax_v3",    var = "ax_v3" },
        { id = "ax_a0",    var = "ax_a0" },
        { id = "ax_a1",    var = "ax_a1" },
        { id = "ax_a2",    var = "ax_a2" },
        { id = "ax_a3",    var = "ax_a3" },
        { id = "al_t0",    var = "al_t0" },
        { id = "al_x0",    var = "al_x0" },
        { id = "al_t1",    var = "al_t1" },
        { id = "al_x1",    var = "al_x1" },
        { id = "al_t2",    var = "al_t2" },
        { id = "al_x2",    var = "al_x2" },
    },

    -- 趋势：曲线是静态的（一条已完成的模组曲线），只刷两处读数
    trend = {
        { id = "hd_clock", var = "clock" },
        { id = "rt_note",  var = "rt_note" },
        { id = "wd_v3",    var = "wd_v3" },
        { id = "wd_v4",    var = "wd_v4" },
    },

    -- 步序：只刷状态词与标题右上的进度
    step = {
        { id = "hd_clock", var = "clock" },
        { id = "sp_note",  var = "step_note" },
        { id = "sp_s0",    var = "sp_s0" },
        { id = "sp_s1",    var = "sp_s1" },
        { id = "sp_s2",    var = "sp_s2" },
        { id = "sp_s3",    var = "sp_s3" },
        { id = "sp_s4",    var = "sp_s4" },
        { id = "sp_s5",    var = "sp_s5" },
        { id = "sp_s6",    var = "sp_s6" },
    },

    -- 点位：表格与强制态在 ui_app 里单独刷，这里只有右上角计数
    io = {
        { id = "hd_clock", var = "clock" },
        { id = "fc_note",  var = "fc_note" },
    },

    -- 系统：亮度读数与当班统计
    sys = {
        { id = "hd_clock", var = "clock" },
        { id = "br_num",   var = "br_num" },
        { id = "br_v",     var = "br_v" },
        { id = "sa_v0",    var = "sa_v0" },
        { id = "sa_v1",    var = "sa_v1" },
        { id = "sa_v2",    var = "sa_v2" },
        { id = "sa_v3",    var = "sa_v3" },
    },
}

function ui_vars.bind_list(page)
    return ui_vars.PAGES[page] or {}
end

return ui_vars
