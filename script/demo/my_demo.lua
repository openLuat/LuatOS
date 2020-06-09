--
-- 定义了一个模板，用来设置自己环境诸如 wifi  密码等信息
-- 随便存在什么目录上，制作磁盘镜像时引入它即可
-- 需要它的 demo 脚本会用 require("my_demo") 来引用它
--
-- !!! 这只是个模板，要 copy 到你的私有目录再修改
-- 我不想在 git 库里看到你家的 wifi 密码
--
local mine = {
  wifi_ssid= "***",
  wifi_passwd = "***"
}

return mine