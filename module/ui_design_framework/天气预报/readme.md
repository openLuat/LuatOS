# 天气预报大屏 · AirUI 工程（Air8603）

参考 **Windows 11 天气应用（深色版）** 设计，与 `code/preview.html`
（浏览器 1:1 预览稿）**结构 1:1 对应**：深蓝夜色底（`#141D33`）、圆角卡片
（`#1F2A47`）、蓝色强调（`#5AA7FF`）。

**双页一屏布局**（无页面滚动）：页面 1"当前天气"与页面 2"天气详细信息"
各自一屏放下，顶栏按钮互相切换，触摸滑动不翻页。
**工程零 PNG 贴图**，天气图标（太阳/月亮/云/雨/雷阵雨）全部用
shape 圆与线绘制，规避贴图相关的实机坑。

- 硬件：合宙 Air8603（Air1603 主控，RGB565 电容触摸大屏）
- 底层固件：**LuatOS-SoC_V1030_Air1603_102.soc**（需含 AirUI V1.1.6+ 与 hzfont 中文字库）
- 开发方式：LuatOS (Lua 5.3) + AirUI（基于 LVGL 9.4 封装）+ exwin 页面管理
- 数据：**虚拟模拟数据**（mock.lua，1.5 秒刷新）

## 页面结构（与 preview.html 逐段对应）

| 区块 | 内容 | 交互 |
|------|------|------|
| 固定顶栏 | 当前天气 + 时间 + 提问胶囊 + 🌙/☀️ | **月亮点按切换深/浅主题**（整页重建） |
| 当前天气 | 城市名/图标/温度大字 40 号/体感/提示语/6 项指标条 | **点城市名弹出下拉**（我的位置 + 4 城市，各带图标温度，html 同款） |
| 每小时预报 | **9 个指标 tab** + **图表/列表**切换 + 概览附加线**"体感温度"开关** | 点 tab 切图（开=叠加橙色体感曲线）；图表=日期条+曲线/柱状图；列表=横向滑动小时卡 |
| 天气详细信息 | 12 张指标卡，**带 html 同款小图形**：温度/体感迷你曲线、云量/降水深色大圆、风速罗盘、湿度迷你柱状、紫外线/AQI 珠链圆环、能见度珠条、气压曲线、太阳弧线、月相半月盘 | 随城市/日期联动刷新 |

数据与 preview.html 行为一致：**按 城市×日期 固定缓存**，切换视图/
来回切换数值不变；指标条等少数数值 1.5s 随机游走模拟实时读数。

## 文件结构（按框架统一架构要求）

```
天气预报/
├── code/             所有代码与资源文件
│   ├── main.lua          入口：屏幕点亮链路 + 字体 + 触摸 + 打开页面
│   ├── theme.lua         主题配色 / 页面工厂 / 自绘图表 / 天气图标 / 珠链圆环 / 迷你曲线
│   ├── mock.lua          虚拟天气数据（城市×日期 固定缓存 + 逐小时图标）
│   ├── page_weather.lua  双页主程序（页面1 当前天气 / 页面2 详细信息）
│   └── preview.html      浏览器 1:1 预览稿（定稿设计稿）
├── docs/             code 和 readme.md 之外的其余文件（当前为空）
└── readme.md         本文件
```

## 烧录步骤（Luatools）

1. 电脑安装 [Luatools](https://docs.openluat.com/) 及 Air8603 板载 USB 转串口驱动；
2. Type-C 数据线接 Air8603 的 **USB2** 口；
3. Luatools 中新建项目，选择 **Air1603** 对应固件（Air8603 默认固件即可）；
4. **脚本区添加：`code/` 目录下全部 `.lua` 文件**（本工程无 img 目录），
   并勾选 **"添加默认lib"**（exwin 是 Lua 扩展库）；
5. 烧录运行：顶栏"详细信息"进详情页、"返回"切回，点城市名/日期卡/tab 切换数据。

## 与智慧农场工程的关系

框架（main.lua 点亮链路 / exwin 切页）复用 `智慧农场/airui_farm`。
农场工程踩过的坑在本工程全部规避，另有本工程新踩/新规避的：

- **[性能] 详细信息拆成独立页面**：12 张详情卡不再挂在主页面长滚动里，
  主页面顶栏"详细信息"按钮 → `theme.open_page(2)` 切换（先 close 旧窗再
  open 新窗，见 theme.lua SWITCH_PAGE），详情页顶栏"返回"切回；
  构建器 `build_detail` 通过模块级 `build_detail_shared`/`DETAIL_PARENT`
  在两个页面间复用（页面1 首次 rebuild 时赋值，开机先开页面1 所以时序安全）；
- **[新踩] `airui.touch_subscribe` 会导致触摸失效（屏幕划不动）**：
  这版固件上订阅回调直接接管/破坏输入管线，任何情况下都不要用；
  滑动期间暂停动画的需求改用其他手段（如降低动画频率）；
- **[性能] 滑动卡顿三大来源与对策**：①全屏半透明面板（color_opacity）
  每帧逐像素 alpha 混合 → 用 `theme.blend()` 离线预混合成不透明色
  （C.card_soft / C.grid，视觉不变）；②图表渐变填充是整图逐像素混合
  → 只在概览 tab 保留（cfg.fill=false 关闭）；③hzfont 缓存过小导致
  滚动时反复栅格化 → cache_size 提到 2048（失败自动回退 1024）；
- **[新踩] 部分固件版本的 `exwin` 没有 `bind_root` 方法**：直接调用 =
  attempt to call a nil value → Lua VM exit 15 秒后重启。调用前必须
  `if exwin.bind_root then pcall(exwin.bind_root, root) end`；
- **[新踩] mock.S.view 存中文键"图表"/"列表"**：分支判断必须用同一个值，
  写成 `== "list"` 永远不命中 → 点列表只有标题高亮、主体不变；
- **[新踩] 点击回调里不要直接销毁被点控件所在子树**：rebuild 会销毁按钮
  自己所在的锚点容器，LVGL 事件回调中删自身有 use-after-free 风险，
  错误被 pcall 吞掉后表现为"点了没反应"。所有 on_click 一律
  `sys.timerStart(fn, 30)` 延迟到事件外执行，并用防抖合并连续点击；
- **[新踩] 不要读 airui 对象句柄的 `.w/.h` 字段**：句柄不暴露布局属性，
  `ca.w - 4` 得到 nil 运算错误且被 pcall 吞掉，表现为"图表区整块空白"。
  布局 rect 必须自己存 Lua 局部变量（page_weather.lua 已全部改用局部 rect）；
- **[新] 单页滚动**：`airui.container({scrollable=true})` 即 LVGL 可滚动容器
  （官方 wifi_list_win 同款），子控件超出高度自动出现拖拽滚动；
- **[新] 锚点容器模式**：动态区子控件必须挂在锚点容器下（销毁锚点=整块
  销毁），挂在 scroll 上会导致 rebuild 后控件叠加重复；
- 不用任何 PNG：规避"单 IDAT"与"贴图预缩放"两个坑，图标用 shape 绘制
  （实心圆必须 `width>=1`、圆心/半径四舍五入取整，否则图元整批消失）；
- chart 数据点数量设为实际长度（`set_point_count(#vals)`）；
  `set_values` 只收整数（降水以 0.1mm 计）；渐变填充
  `fill={enable,opa_start,opa_end}`（`fill_fade` 部分固件不生效）；
- C chart 自带 x_axis/y_axis/legend 全部禁用，刻度自绘 label，
  label 宽度给足防折行；全局字号 ≥16（大数值 22/26/40）；
- 动态区销毁重建全部 pcall + log.error(traceback) 保护；
- 回调函数 local 前置声明（页面内 `rebuild` 被多个按钮闭包引用）；
- exwin 先 close 旧栈顶再 open 新窗；核心库不 require、扩展库必须 require。

## 替换为真实数据

所有动态数值集中在页面 `return function() ... end` 的刷新回调里：
- 天气 API（`http` 拉取 JSON）→ 写入 mock 缓存或直接调 label `set_text`；
- 曲线用 `theme.set_chart(ch, 整数数组)` 推送。
