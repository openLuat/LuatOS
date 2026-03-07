PROJECT = "780EPM_development_board"
VERSION = "1.0.4"

sys = require("sys")
log.style(1)


 pm.ioVol(pm.IOVOL_ALL_GPIO, 3000)--所有IO电平开到3V，适配camera

--只拍照上传给HTTP服务器，其他什么都不做

 require"camera780epm"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
