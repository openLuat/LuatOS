
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

log.info('read 0x20090000', mcu.x32(mcu.reg32(0x20090000))) --读取0x20090000这个地址的值
log.info('write 0x20090000', mcu.x32(mcu.reg32(0x20090000, 0xabcdef12))) --写入0xabcdef12
log.info('mod bit31 0x20090000', mcu.x32(mcu.reg32(0x20090000, 0x00000000, 0x80000000))) --修改bit31 为 0
log.info('mod bit30 0x20090000', mcu.x32(mcu.reg32(0x20090000, 0x40000000, 0x40000000))) --修改bit30 为 1

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
