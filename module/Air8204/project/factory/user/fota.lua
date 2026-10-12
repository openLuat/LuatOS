--[[
@module  fota
@summary 【已废弃】原 air_card 的 OTA 模块（libfota2 差分升级）
@version 1.0
@date    2026.09.28
@usage
本模块在本次「产测 + 出货合一」整合中已废弃，请勿再 require。

废弃原因：
  原 firmware/code/fota.lua 使用 libfota2（合宙 IoT 平台差分组件升级），
  与新引入的 update.lua（libfota3 整机成品 FOTA）构成两套并行的升级通道，
  易造成版本管理混乱。经确认，OTA 升级统一由 update.lua + libfota3 负责：
    - update.lua     : FOTA 管理模块，由 boot.lua 在开机时调用 update.init()
    - libfota3.lua   : 整机成品 FOTA 库（SHA256 校验、断点续传、结果上报）
    - 触发时机       : 开机检测一次 + 每 8 小时循环

如需查看历史实现，请参考整合前的 air_card/fota.lua（原项目目录已保留）。
]]

return {}
