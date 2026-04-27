--[[
@module  main
@summary 网络测速工具 - 主程序入口
@version 1.0.0
@date    2026.04.08
@author  拓毅恒
@usage
基于 Cloudflare Speedtest 端点的网络测速工具，支持下载/上传速度、延迟和抖动测试。
界面风格：NetEqualizer 对称测速风格
]]

PROJECT = "NETWORK_SPEEDTEST"
VERSION = "1.1.0"

log.info("main", PROJECT, VERSION)

require "speedtest_win"

sys.publish("OPEN_SPEEDTEST_WIN")

sys.run()
