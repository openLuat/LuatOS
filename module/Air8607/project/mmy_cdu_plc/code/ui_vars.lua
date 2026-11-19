--[[
@module  ui_vars
@summary 界面变量绑定表（组件 <- 变量），按页分组
@version 1.0.0
@date    2026.11.18
@usage
PLCUI 的 label 运行时只能改文本（没有 set_color），所以绑定表里只出现 text。
曲线不在这里绑定，由 ui_app.chart_tick 用 chart:add_point 追加。
对外接口 1 个：ui_vars.bind_list(page)。
]]

local ui_vars = {}

ui_vars.PAGES = {
    -- 总览：状态条 / 机组实时 / 泵组 / 双回路温度 / 报警
    overview = {
        { id = "hd_clock", var = "clock" },
        { id = "hd_cs",    var = "hd_cs" },
        { id = "bn_q",     var = "bn_q" },
        { id = "bn_cop",   var = "bn_cop" },
        { id = "bn_dt",    var = "bn_dt" },
        { id = "kp_v0",    var = "kp_v0" },
        { id = "kp_v1",    var = "kp_v1" },
        { id = "kp_v2",    var = "kp_v2" },
        { id = "kp_v3",    var = "kp_v3" },
        { id = "pm_fv0",   var = "pm_fv0" },
        { id = "pm_fv1",   var = "pm_fv1" },
        { id = "pm_cv0",   var = "pm_cv0" },
        { id = "pm_cv1",   var = "pm_cv1" },
        { id = "t_s1",     var = "t_s1" },
        { id = "t_r1",     var = "t_r1" },
        { id = "t_s2",     var = "t_s2" },
        { id = "t_r2",     var = "t_r2" },
        { id = "p1_t",     var = "p1_t" },
        { id = "al_t0",    var = "al_t0" },
        { id = "al_x0",    var = "al_x0" },
        { id = "al_t1",    var = "al_t1" },
        { id = "al_x1",    var = "al_x1" },
        { id = "al_t2",    var = "al_t2" },
        { id = "al_x2",    var = "al_x2" },
    },

    -- 回路：两侧参数 + 能效 + 补水
    loop = {
        { id = "hd_clock", var = "clock" },
        { id = "a_v0",     var = "a_v0" },
        { id = "a_v1",     var = "a_v1" },
        { id = "a_v2",     var = "a_v2" },
        { id = "a_v3",     var = "a_v3" },
        { id = "bb_v0",    var = "bb_v0" },
        { id = "bb_v1",    var = "bb_v1" },
        { id = "bb_v2",    var = "bb_v2" },
        { id = "bb_v3",    var = "bb_v3" },
        { id = "ef_v0",    var = "ef_v0" },
        { id = "ef_v1",    var = "ef_v1" },
        { id = "ef_v2",    var = "ef_v2" },
        { id = "mu_v0",    var = "mu_v0" },
        { id = "mu_v1",    var = "mu_v1" },
        { id = "mu_v2",    var = "mu_v2" },
    },

    -- 趋势：曲线由 chart_tick 追加，这里只有时钟
    trend = {
        { id = "hd_clock", var = "clock" },
    },

    -- 点位：AO 给定与强制计数；表格在 ui_app 里刷
    io = {
        { id = "hd_clock", var = "clock" },
        { id = "ao_v0",    var = "ao_v0" },
        { id = "ao_v1",    var = "ao_v1" },
        { id = "ao_v2",    var = "ao_v2" },
        { id = "fc_note",  var = "fc_note" },
    },

    -- 系统：背光、能效统计、运行诊断
    sys = {
        { id = "hd_clock", var = "clock" },
        { id = "br_num",   var = "br_num" },
        { id = "en_v0",    var = "en_v0" },
        { id = "en_v1",    var = "en_v1" },
        { id = "en_v2",    var = "en_v2" },
        { id = "en_v3",    var = "en_v3" },
        { id = "rd_v0",    var = "rd_v0" },
        { id = "rd_v1",    var = "rd_v1" },
        { id = "rd_v2",    var = "rd_v2" },
        { id = "rd_v3",    var = "rd_v3" },
    },
}

function ui_vars.bind_list(page)
    return ui_vars.PAGES[page] or {}
end

return ui_vars
