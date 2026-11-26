# AGENTS.md — 儿童房控制面板

> 作用域：`module/ui_design_framework/儿童房控制面板/`。动手前先读本文件 + 根 `AGENTS.md` +
> `module/ui_design_framework/智慧家居/AGENTS.md`（应用层 UI 铁律原文）。

## Scope

**Air1603_A10**（引擎 AIR8603M1 10 寸：JD9165BA 1024×600 + GT911，`rtos.bsp()` 报 `Air1603`；
同时兼容 Air8607 底板）上的童趣房间中控：四页（我的房间 / 灯光乐园 / 故事时间 / 星星奖励）
+ 五套动漫主题 + 每主题 5 个角色 + 顶栏键盘改名，全部数据本地模拟。
只改本目录；**不要**改 `components/airui/`、驱动、其它示例工程。

板级参数唯一出处：`module/Air1601_Air1602_Air1603_Air1604_Air1605/project/factory/config/eng_8603m_10i_v0.lua`
（LCD pin_rst=15 / 时序 140-20-160-20-3-12 @50MHz / 背光 PWM3 / TP_RST=GPIO72 / TP_INT=GPIO51 /
12V_EN=GPIO44 等电源轨）。改硬件初始化前先对照它。

## Where to Look

| 要做的事 | 看这里 |
| --- | --- |
| 视觉规格（唯一） | `docs/儿童房面板效果稿.html`（渲染图 `docs/local_artifacts/preview_draft.png`，由 `shot.py` 生成） |
| 配色 / 字号 / 圆角 / 动效 / 曲目 / 奖励格 | `code/ui_theme.lua`（↔ HTML 的 CSS 变量与 THEMES 表） |
| 角色切换 / 房间名 / 角色贴图名 | `code/ui_cast.lua` |
| 新建任何控件 | `code/ui_widget.lua`（唯一入口：card/text/text_mid/sticker/deco/halo/press/switch/chip/bar/button） |
| 改名弹层（遮罩 + 键盘） | `code/ui_keyboard.lua` |
| 页面怎么切、主题怎么重建 | `code/page_shell.lua` |
| 加数据 / 改模拟逻辑 / 名字归一化 | `code/app_state.lua` |
| 贴图缺失、TF 卡降级 | `code/assets.lua`、`code/sd_card.lua` |
| 生成/换贴图 | `docs/gen_assets.py`（拆格、单 IDAT、预缩放、`--sd` 导出、`--check` 体检） |

## 本工程专属约定

1. **`airui.screen` 只挂一个直系子容器**。它是 flex 容器，同级挂多个会被压缩（实测只剩顶栏可见）。
   `page_shell.create()` 先建 `scrollable=false` 的 MAIN，所有层再挂 MAIN。
2. **require 必须字面量，而且一行一个**。打包/烧录按静态依赖裁剪，`require(表[i])` 会漏文件；
   依赖扫描又是**按行**抓 `require "xxx"` 的，四个写在同一行会被拼成一个模块名，
   烧录报「缺少 page_room", require "page_light", … 请添加」。正确写法：

   ```lua
   local page_room = require "page_room"
   local page_light = require "page_light"
   local PAGES = { page_room, page_light }
   ```
3. **不要用 `obj:is_destroyed()`**。本固件对活着的 container 也返回 true，会把所有点击挡掉。
   用 `ui_widget.bump_epoch()` / `epoch` 判断「控件是否属于本次构建」。
4. **切页只推位置**：`set_pos(0,88)/(-1024,88)`，不 destroy、不 hide/open。只有切主题才销毁重建，
   重建前先 `KB.destroy()` + `W.clear_twinkle()` + `W.bump_epoch()`，重建后 `switch_force(keep)` 回原页。
5. **贴图必须显式 `fit = "contain"`**。`airui.image` 的 fit 默认 `center` = 不缩放只裁剪，
   w/h 成了裁剪框（72px 图标塞进 28px 胶囊会变成一块纯色）。`W.sticker` 已统一处理，别绕开它建 image。
6. **贴图命名契约**（`gen_assets.py` 产物，`check_rules.py` R9 会扫）：
   `ch_<theme>_<0..4>_big|sm`、`st_<theme>_<0..5>`、`ic_<name>`；
   写新名字必须同时改流水线，否则运行期只会静默走几何占位。
7. **中文按字符数算，不按字节**：`#s` 是字节数（一个字 3 字节），截断/计数请用
   `app_state.set_kid_name` 里的 UTF-8 首字节判断。

## Recipe：加一页

1. 新建 `code/page_xxx.lua`，导出 `M.create(root, ctx)`，`root` 是 1024×432 的整页容器，返回 `{ refresh = fn }`；
2. 在 `page_shell.lua` 的 `PAGES` / `PAGE_NAMES` / `tab_names` / `tab_icons` 各加一项（Tab 宽度 238，四等分）；
3. 坐标按效果稿的「内容区原点」算，卡片高度比槽位少 4px 留给假投影，子控件不许越界；
4. **页面必须能「迟到创建」**：切主题只重建当前页，其余页由 `M.fill_later()` 后台补（开机那次延 1.2s）。
   所以 `create()` 里只能读 `app_state` 的当前状态、结尾刷一次 `refresh()`，不能假设自己已经建好；
5. 列布局别自己发挥：左卡到 496 / 中列到 668 或 788 / **右列一律收在 992**，列间 12px 缝
   （效果稿旧版的 492、392 会和左卡重叠 4px，真机上就是「两列粘在一起」）；
6. 数据放 `app_state.lua`，事件回调只改状态 + 调本页 `refresh()`，不要跨页刷新；
7. 跑 `python docs/check_rules.py --strict` → `python docs/verify_sim.py` 看截图。

## Recipe：加 / 换一套主题

`ui_theme.lua` 的 `P` 表加一组：

- `key/name/suffix/reward`（`suffix` 是房间名后缀，`reward` 是奖励贴纸的格号 0..5）；
- `cast`（5 个角色名，顺序 = 阵容条 5 格顺序）、`songs`（5 首 `{名称, 标签}`）；
- `c`（必须给全 `bg band1 band2 blob1-3 card card2 shadow ink ink2 ink3 pri pri2 on off track
  pink mint yellow sky white`）。

再同步 `docs/儿童房面板效果稿.html` 的 `body[data-theme=...]` 与 JS 的 `THEMES`，`M.count` 跟着改；
最后 `python docs/gen_assets.py` 生成 `<key>.webp` / `<key>_cast.webp` 对应的 60 张贴图。

## Recipe：验证一次改动

```powershell
cd docs
python check_rules.py --strict   # 静态铁律 + 贴图命名 + 字号白名单
python gen_assets.py --check     # 贴图尺寸 / 单 IDAT / 总量
python verify_sim.py             # 起模拟器点一遍，14 张截图 + 日志标记核对
```

`verify_sim.py` 会先删 `local_artifacts/logs/fskv.bin`（`--keep-kv` 可保留），所以每轮从「玩具总动员 1/5 + 小星星」开始。
以上命令的运行产物（日志 / 截图 / Twemoji 缓存 / `preview_draft.png`）统一落 `docs/local_artifacts/`，
该目录整体被 `.gitignore` 忽略：**源和工具在 `docs/` 根，产物只在 `local_artifacts/`**。

## 硬件层三个已踩过的坑

1. **板型别猜**：日志 `LuatOS@Air1603 ... bsp V1030` + `W/pins /luadb/pins_air1603.json not exist` 说明
   跑在 Air1603_A10 上。Air1603 缺 12V_EN(GPIO44) → 背光不亮；TP_RST 是 GPIO72 不是 14。
2. **`exd_jd9165ba_rgb.setup` 可能只返回 `true`**：不能 `info.backend` 直接取，
   会 `attempt to index a boolean value` 并终止启动（= 黑屏）。用 `type(info)=="table"` 兜底。
3. **`E/pwm setup ch 3` 是本固件的无条件调试日志**，`pwm.setup` 成功也会打；判断成败看返回值。

## Anti-Patterns

- ❌ `airui.button` 做热区（自带描边 + hide/open 历史问题）→ 用 `W.press`。
- ❌ 直接 `airui.image{...}` 而不传 `fit`（默认 center = 裁剪，不是缩放）。
- ❌ `border_color`、`hide()/open()/show()`（唯一例外是 `kb:show()/hide()`）、`timerLoopStart` 做帧循环、
  `timerStart(fn, 0~4)`、字号 <16。
- ❌ 一行写多个 `require`（烧录合并会把整行拼成一个模块名）。
- ❌ 文案里写 U+2212 减号 / ×÷≤≥ 等数学符号（hzfont 无字形，真机是方框，减号用 ASCII `-`，见 R12）。
- ❌ 用 `#name` 当字数截中文（一个字 3 字节）。
- ❌ 键盘不开 `preview`（textarea 离屏 → 孩子盲打）；遮罩提示写在 y>250（会被键盘压住）。
- ❌ 在事件回调里销毁自己或重建整页 → `W.defer(fn, 30)`。
- ❌ 让子控件探出父容器 1px（会画滚动条且无法关闭）。
- ❌ 全屏 1024×600 贴图（真机图片缓存 1MB，按 w*h*2 记账）。
- ❌ 把 `docs/local_artifacts/`（模拟器日志 / 截图 / Twemoji 缓存 / `preview_draft.png`）提交进仓库或云端工程：都是可再生的运行产物，该目录已整体 gitignore。
- ❌ 用 `code/xxx.lua` 的路径提交云端：云端工程是脚本区镜像，`main.lua` 必须在根、
  `code/` 内容平铺到根（`docs/submit_source.py` 已做映射，手写 payload 时别忘）。

## Related Docs

- 应用层铁律原文：`module/ui_design_framework/智慧家居/AGENTS.md`（R1–R13）
- 平台约束：`components/airui/AGENTS.md`
- 六个项目复盘（性能预算 / 踩坑总表）：`module/ui_design_framework/ktv点歌系统/docs/AirUI 六个项目复盘.md`
