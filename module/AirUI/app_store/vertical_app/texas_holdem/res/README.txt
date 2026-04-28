纸牌图片资源说明（德州扑克）

一、文件命名（52 张牌 + 可选）
  点数 + 花色小写字母 + .png
  花色：c=梅花  d=方块  h=红桃  s=黑桃
  点数：2～9 为数字；10 为 10；j、q、k、a 表示 J、Q、K、A

  示例：2c.png、10h.png、as.png

二、可选
  back.png        牌背（电脑暗牌）
  card_empty.png  公共牌空位；不提供则显示 "--"

三、LuatOS PC 模拟器（luatos-pc + 工程目录）
  模拟器会把工程目录下文件扫进虚拟盘 /luadb/，非 lua 文件在库里的名字是「仅文件名」，
  没有 cards/ 子路径。因此请把 PNG 放在工程里任意子目录（如本目录 cards/），
  程序会按下面顺序查找（任一存在即可）：
    /luadb/cards/2c.png
    /luadb/2c.png
    /luadb/../cards/2c.png
  即：PC 上通常会命中 /luadb/文件名.png。

四、真机 / Luatools 应用沙箱
  exapp 中 /luadb/xxx 会映射到 app_dir/res/xxx。
  建议把 PNG 放在应用的 res/cards/ 下（最稳妥，命中 /luadb/cards/xxx）。
  如果你历史包里放的是 app 根目录 cards/，脚本也会尝试 /luadb/../cards/xxx 作为兜底。

五、未放置图片时
  自动使用文字牌面，不影响游戏逻辑。
