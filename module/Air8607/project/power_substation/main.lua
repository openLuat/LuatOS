-- Air8607 demo: 智慧配电房电力运维监测终端
-- ui/: 智慧配电房运维监测，2D 电气主接线 + 变配电运行数据大屏
-- app/: 主流程，开机自检进度与后台任务
-- drv/: 显示驱动、触摸驱动
-- @author 江访
-- @time 2026-10-26 11:15

PROJECT = "power_substation"
VERSION = "1.0.0"

-- 加载自检进度界面
require "app_main"
