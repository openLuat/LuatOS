# 车载电脑（BYD DiLink 风格车机 HMI，AirUI 实现）

把 `code/preview.html`（浏览器 1:1 设计稿，1024×600）整站复刻成 LuatOS AirUI 工程，
目标硬件与「天气预报」工程一致：**合宙 Engine-Air8603 + 10寸 1024×600 RGB 屏 + GT911 触摸**。

## 页面清单（12 个，与 preview.html 的 PAGES 一致）

| 页面 | 文件 | 内容 |
|------|------|------|
| home | page_home.lua | 五列栅格：天气卡 / APP 列表 / 空调拨盘 / 视频 / 语音 / 音乐 / 地图 |
| nav | page_nav.lua | 全宽地图（路网+路线+转向卡+语音球）+ 右侧音乐/车辆卡 + 底部 dock |
| car | page_car.lua | 六边形光环 + SUV + 纯电/混动模式胶囊 + 三张数据卡 |
| set | page_set.lua | 模式分段 / 车速 / 俯视车 / PRND / 电量 + 6 个设置标签（每个分类 6 行，带「开启/关闭」双向开关） |
| ac | page_ac.lua | 座椅角度刻度盘 / 双座椅 / 双区温度柱 / 底部 9 功能钮 + 大温度钮 |
| music | page_music.lua | dock / 标签 / 5 张主题歌单卡 / 最近播放 / 播放条，弹层含播放列表、收藏、更多歌单（8 张） |
| apps | page_apps.lua | 5×3 应用宫格（94×94），极速模式可切换（数据 4.3/180/480 ↔ 3.9/220/580） |
| task | page_task.lua | 最近任务缩略卡 + 首页缩略大图 |
| cluster | page_cluster.lua | 双速度表盘 / 油量柱 / ADAS 场景 / 电量与档位栏 |
| phone | page_phone.lua | 手机投屏壳（刘海 / 状态栏 / 地图卡 / 工具条） |
| weather | page_weather.lua | 照「天气预报」工程：英雄卡 / 9 个指标 tab（概览·降水·风速·湿度·云量·气压·紫外线·可见度·体感温度）/ `airui.chart` 面积图 + 图表↔列表 + 图例 / 7 日卡片（含天气图标，点击切日）/ 城市下拉 |
| voice | page_voice.lua | 小迪球体 / 对话气泡 / 建议词条 / 麦克风 |

页面切换：`theme.go_defer("页面名")`（exwin 先 close 旧窗再 open 新窗）。

返回栈：`theme.go()` 入栈、`theme.back_defer()` 出栈（返回上一页），`theme.topbar(root, "back")`
或各页自绘的 30×30 圆形返回键都走这条路径，不再硬编码回 `home`。

## 主题（深/浅两套）

- `theme.PALETTES = { dark = {...}, light = {...} }`，`theme.C` 为当前生效调色板；
- `theme.toggle_theme()` 就地覆写 C 的字段（不换表身份），随后 `theme.rerender_current()`
  整页重建当前页；
- 重建必须发生在 LVGL 事件回调之外：所有点击回调统一走 `theme.debounce()`
  （内部 `sys.timerStart(fn, 30)`）；
- **功能入口藏起来保证视觉与设计稿一致**：点击顶栏头像 = 深/浅主题切换；
- 页面禁止硬编码主题相关颜色，一律使用语义色（card/line/text/sub/dim/sel/knob/
  ghost/track/hi 等）；插画类内容色（SUV 红色车身、专辑封面、地图深蓝底）不随主题换肤，
  属于内容而非 UI。

## 字号要求

全局默认 16 号（hzfont），所有 label 显式 `font_size` 且 **≥16**
（设计稿中刻度标注等 13px 小字已按要求提到 16px）。

## 从前面几个项目踩过的坑（本工程全部规避）

1. **不用任何 PNG 贴图**（单 IDAT / 图片预缩放两个实机坑），图标全部 shape 线性绘制；
2. shape 图元 >32 个整批丢弃 → `theme.shapes()` 按 30 个/批自动拆分；
3. 实心圆必须 `width >= 1`，圆心/半径取整；
4. 容器不存 `.w/.h`，坐标记录在 Lua 局部变量里；
5. exwin 先 close 后 open，`bind_root` 用 `pcall`（部分固件没有该方法）；
6. 事件回调里只改状态 / `sys.timerStart` 延迟 30ms，不做销毁与重建；
7. `airui.init` 之后才能 `font_load`；hzfont `cache_size` 只允许 128/256/512/1024/2048；
8. "半透明色叠底色"离线 `theme.blend()` 预混合成不透明色，避免逐像素 alpha 混合卡顿；
9. 容器默认可滚动，子控件务必排在边界内（所有页面坐标均按 1024×600 画好）；
10. 整卡点击的透明层必须先建，卡内可点子控件后建（后建的在上层，否则被挡住）。

## 点亮链路（main.lua，与「天气预报」工程一致）

供电轨 → `display.init("custom")` RGB 时序 → `airui.init(1024,600)` → 首帧后开背光
（PWM3 @1kHz 100%）→ `airui.font_load`（hzfont 16 号，cache 2048）→ GT911 触摸三步
（`i2c.setup` → `tp.init` → `airui.device_bind_touch`）→ `theme.go("home")`。

## 数据

全部虚拟模拟数据在 `mock.lua`（全局 `MOCK`）：天气/空调/音乐（播放进度 1.5s 推进）/
导航/车辆/设置/应用/任务/仪表/语音。页面通过 `make_page` 的 1.5s 刷新回调读 MOCK 刷新
label（`set_text/set_color`），交互只改 MOCK 状态。

## 预览

`code/preview.html` 为设计稿，浏览器打开后用 `go('页面名')`、`themeSet('dark'|'light')`
逐页比对。
