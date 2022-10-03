
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "camera_video"
VERSION = "1.0.0"

--[[
这是Air105+摄像头, 通过USB传输到上位机显示图像的示例, 速率5~10fps, 不要期望太高
本demo不需要lcd屏,但lcd的代码暂不可省略

本demo需要最新固件

测试流程:
1. 先选取最新固件, 配合本demo的3个文件,3个文件都需要下载到设备,包括txt文件!!!
2. 查看日志, 若提示摄像头无数据, 检查摄像头连线,并检查是否已经下载txt文件.
3. 断开USB, 将拨动开关切换到另一端, 切勿带电操作!!!
4. 重新插入USB
5. 打开上位机, 选择正确的COM口, 然后开始读取

-- USB驱动下载 https://doc.openluat.com/wiki/21?wiki_page_id=2070
-- USB驱动与 合宙Cat.1的USB驱动是一致的

上位机下载: https://gitee.com/openLuat/luatos-soc-air105/attach_files
上位机源码: https://gitee.com/openLuat/luatos-soc-air105 C#写的, 就能用, 勿生产

]]


-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

log.style(1)
require "camera_test"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
