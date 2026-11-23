--[[
@module  ui_vars
@summary 界面变量绑定表（组件 <- 变量）
@version 1.0.0
@date    2026.11.22
@usage
单页界面，绑定表只有一张。曲线与库位格不在这里绑定：
库位格由 ui_app 用 set_hidden 控制，作业标记用 set_pos 移动。
对外接口 1 个：ui_vars.bind_list()。
]]

local ui_vars = {}

ui_vars.BIND = {
    { id = "h_clock", var = "clock" },
    { id = "h_stock", var = "h_stock" },
    { id = "st_in",   var = "st_in" },
    { id = "st_out",  var = "st_out" },
    { id = "st_task", var = "st_task" },
    { id = "st_avg",  var = "st_avg" },
    { id = "st_use",  var = "st_use" },
    { id = "t_cnt",   var = "t_cnt" },
    { id = "t_no0",   var = "t_no0" },
    { id = "t_op0",   var = "t_op0" },
    { id = "t_lo0",   var = "t_lo0" },
    { id = "t_st0",   var = "t_st0" },
    { id = "t_no1",   var = "t_no1" },
    { id = "t_op1",   var = "t_op1" },
    { id = "t_lo1",   var = "t_lo1" },
    { id = "t_st1",   var = "t_st1" },
    { id = "t_no2",   var = "t_no2" },
    { id = "t_op2",   var = "t_op2" },
    { id = "t_lo2",   var = "t_lo2" },
    { id = "t_st2",   var = "t_st2" },
    { id = "t_no3",   var = "t_no3" },
    { id = "t_op3",   var = "t_op3" },
    { id = "t_lo3",   var = "t_lo3" },
    { id = "t_st3",   var = "t_st3" },
    { id = "t_no4",   var = "t_no4" },
    { id = "t_op4",   var = "t_op4" },
    { id = "t_lo4",   var = "t_lo4" },
    { id = "t_st4",   var = "t_st4" },
}

function ui_vars.bind_list() return ui_vars.BIND end

return ui_vars
