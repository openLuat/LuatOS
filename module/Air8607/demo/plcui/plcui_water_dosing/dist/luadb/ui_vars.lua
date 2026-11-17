--[[
@module  ui_vars
@summary 界面变量绑定表（组件 <- 变量），UI 模块只按这张表刷数，不直接碰业务变量
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件描述「哪个组件的哪个属性，取 data_app.get() 里的哪个键」。
kind：text 文本 / src 换图 / checked 选中 / disabled 禁用 / hidden 显隐 / crop 输出条裁宽。
本文件的对外接口有 1 个函数（ui_vars.bind_list）与 1 张表（BIND）。
]]

local ui_vars = {}

--[[ 状态 -> 底板资源 / 图标 / 名称 / 横幅 / 提示 ]]
ui_vars.STATE = {
    stop   = { name = "停机",     ico = "■", badge = "bdg_stop",   banner = "bn_stop",   flow = "flow_stop",   txt = "设备未上电 · 全屏只读",       hint = "当前状态：停机" },
    localm = { name = "就地手动", ico = "■", badge = "bdg_local",  banner = "bn_local",  flow = "flow_local",  txt = "现场控制中 · HMI 只读",      hint = "操作权在现场" },
    remote = { name = "远程手动", ico = "■", badge = "bdg_remote", banner = "bn_remote", flow = "flow_remote", txt = "远程手动 · 单操已解锁",      hint = "HMI 可单操" },
    auto   = { name = "自动运行", ico = "■", badge = "bdg_auto",   banner = "bn_auto",   flow = "flow_auto",   txt = "自动运行 · PID 调节中",      hint = "MV 波动 · 液位下降" },
    fault  = { name = "故障",     ico = "▲", badge = "bdg_fault",  banner = "bn_fault",  flow = "flow_fault",  txt = "故障 · 联锁跳车 · 请复位", hint = "设备已停机" },
    maint  = { name = "维护检修", ico = "■", badge = "bdg_maint",  banner = "bn_maint",  flow = "flow_maint",  txt = "维护检修 · 挂牌 · 操作锁定", hint = "禁止一切操作" },
}

ui_vars.STATE_ORDER = { "stop", "localm", "remote", "auto", "fault", "maint" }

--[[ 设备状态 -> 徽章图 / 文字 ]]
ui_vars.BADGE = {
    stop   = { src = "bd_stop",   txt = "停止" },
    run    = { src = "bd_run",    txt = "运行" },
    localm = { src = "bd_manual", txt = "就地" },
    remote = { src = "bd_run",    txt = "远程" },
    auto   = { src = "bd_auto",   txt = "自动" },
    fault  = { src = "bd_fault",  txt = "故障" },
    lock   = { src = "bd_lock",   txt = "锁定" },
    normal = { src = "bd_run",    txt = "正常" },
    low    = { src = "bd_fault",  txt = "低液位" },
}

--[[ 绑定表：单页工程，全部组件都刷 ]]
ui_vars.BIND = {
    { id = "badge_bg",   var = "badge_src",   kind = "src" },
    { id = "badge_ico",  var = "state_ico",   kind = "text" },
    { id = "badge_txt",  var = "state_name",  kind = "text" },
    { id = "banner_bg",  var = "banner_src",  kind = "src" },
    { id = "banner_ico", var = "state_ico",   kind = "text" },
    { id = "banner_txt", var = "banner_txt",  kind = "text" },
    { id = "banner_hint",var = "banner_hint", kind = "text" },

    { id = "dv_p1",      var = "p1_out",      kind = "text" },
    { id = "db_p1",      var = "p1_badge",    kind = "src" },
    { id = "db_p1_txt",  var = "p1_btxt",     kind = "text" },
    { id = "dv_p2",      var = "p2_out",      kind = "text" },
    { id = "db_p2",      var = "p2_badge",    kind = "src" },
    { id = "db_p2_txt",  var = "p2_btxt",     kind = "text" },
    { id = "db_mx",      var = "mx_badge",    kind = "src" },
    { id = "db_mx_txt",  var = "mx_btxt",     kind = "text" },
    { id = "dv_lv",      var = "level_txt",   kind = "text" },
    { id = "db_lv",      var = "lv_badge",    kind = "src" },
    { id = "db_lv_txt",  var = "lv_btxt",     kind = "text" },

    { id = "flow_svg",   var = "flow_src",    kind = "src" },
    { id = "tank_liquid",var = "level_src",   kind = "src" },
    { id = "flow_anim",  var = "flow_anim_hidden", kind = "hidden" },

    { id = "pid_pv_v",   var = "pv_txt",      kind = "text" },
    { id = "pid_mv_v",   var = "mv_txt",      kind = "text" },
    { id = "mv_bar",     var = "mv_width",    kind = "size", h = 10 },

    { id = "maint_overlay", var = "maint_hidden", kind = "hidden" },

    { id = "log_r0",     var = "log0",        kind = "text" },
    { id = "log_r1",     var = "log1",        kind = "text" },
    { id = "log_r2",     var = "log2",        kind = "text" },
    { id = "op_hint",    var = "op_hint",     kind = "text" },

    { id = "btn_p1",     var = "btn_p1_dis",  kind = "disabled" },
    { id = "btn_p2",     var = "btn_p2_dis",  kind = "disabled" },
    { id = "btn_mx",     var = "btn_mx_dis",  kind = "disabled" },
    { id = "btn_mode",   var = "btn_mode_dis", kind = "disabled" },
    { id = "btn_rst",    var = "btn_rst_dis", kind = "disabled" },
}

--[[ 状态切换键：6 个 image 的选中态 ]]
ui_vars.SWITCHES = {
    { id = "sw_stop",  state = "stop" },
    { id = "sw_local", state = "localm" },
    { id = "sw_remote",state = "remote" },
    { id = "sw_auto",  state = "auto" },
    { id = "sw_fault", state = "fault" },
    { id = "sw_maint", state = "maint" },
}

--[[ 对外：返回绑定表 ]]
function ui_vars.bind_list()
    return ui_vars.BIND
end

return ui_vars
