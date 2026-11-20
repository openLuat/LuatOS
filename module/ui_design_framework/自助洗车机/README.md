# 净界洗车 · 自助洗车机（UI 示例）

基于 **AirUI + hzfont** 的 1024×600 自助洗车机界面，单页三段式（选方案 → 洗车中 → 完成），
支持「晨曦白 / 夜青」双主题**运行时热切换**。视觉稿对应 `docs/方案A_水光玻璃.html`。

---

## 一、测试环境（重要）

| 项目 | 说明 |
|---|---|
| **内核固件** | `LuatOS-SoC_V1032_Air1603_103.soc` |
| **硬件环境** | **Air8607 整机** |
| 屏幕 | 官方 AirLCD_1100 · 10.1 寸 1024×600 · JD9165BA（RGB 接口，免初始化 IC，只做复位 + 时序） |
| 触摸 | GT911（I2C1 轮询，`TP_RST=GPIO14` / `TP_INT=GPIO51`） |
| 背光 | PWM3，默认占空比 **100（最亮）** |
| 其它电源脚 | `SD_EN=GPIO74`（拉高）、`AUDIOPA_EN=GPIO73`（拉低） |

> 以上固件版本与硬件组合是**实测通过**的环境。换固件（尤其跨 Air1603/Air8607 分支）需重新验证：
> 显示屏后端 `display` vs `lcd`、`hzfont` 字库、`shape` 图元（`arc` / `line`）是否都在固件里。

屏幕初始化参数（`code/hardware.lua`）：

```lua
w/h        = 1024 × 600
hbp/hspw/hfp = 140 / 20 / 160
vbp/vspw/vfp = 20 / 3 / 12
bus_speed  = 50 MHz
rotation   = 0
```

---

## 二、目录结构

```
自助洗车机/
├─ code/
│  ├─ main.lua              入口：wdt → hardware.init → 建界面 → 点亮背光
│  ├─ hardware.lua          硬件初始化（上电 / 屏幕 / AirUI / 字体 / 触摸 / 背光）
│  ├─ exd_jd9165ba_rgb.lua  JD9165BA 屏幕驱动封装（display 优先，lcd 兜底）
│  ├─ tp_gt911.lua          GT911 触摸驱动
│  ├─ ui_theme.lua          调色板（晨曦白 / 夜青）+ 字号/圆角等基础令牌
│  ├─ ui_widget.lua         玻璃卡 / 文字 / 描边 / 进度条 / 圆环 / 图元 等控件封装
│  ├─ app_state.lua         套餐数据、价格计算、订单、时间格式化等业务状态
│  ├─ page_wash.lua         页面主体：三栏布局、三阶段切换、弹层、主题热切换
│  ├─ run_sim.bat           PC 模拟器一键启动（先杀旧进程再运行）
│  └─ img/
│     ├─ pkg-foam.jpg       套餐缩略图 · 泡沫
│     ├─ pkg-polish.jpg     套餐缩略图 · 镀膜
│     └─ pkg-water.jpg      套餐缩略图 · 冲洗
└─ docs/
   └─ 方案A_水光玻璃.html   视觉稿（配色 / 间距 / 圆角的唯一基准）
```

---

## 三、运行方式

### 1. 真机（Air8607 整机）

1. Luatools 新建/打开工程，脚本目录指向 `code/`；
2. 在「脚本和资源列表」中**添加目录**：
   - `code/`（8 个 `.lua`）
   - `code/img/`（3 张 jpg，会被摊平下载到 `/luadb/`）
3. 选择固件 `LuatOS-SoC_V1032_Air1603_103.soc`，下载运行。

> 图片路径按 `/luadb/pkg-water.jpg` 访问（Luatools 与 `--llt` 都会摊平，不带 `img/` 层）。

### 2. PC 模拟器

双击 `code/run_sim.bat`。它会先 `taskkill` 掉残留的 `luatos-pc-64bit.exe`，
再把最新代码拷到模拟器目录运行。

> 模拟器带 `--noexit`，**关窗口不等于进程退出**；不杀进程会导致“改了代码但画面没变”。

判断当前跑的是不是最新代码：看日志里有没有

```
I/user.page_wash 自助洗车机界面已创建，主题 xxx 构建 20261118-1510 重建耗时 NN ms
```

`构建 2026xxxx-xxxx` 是代码里的 `BUILD_TAG`，每轮改完会更新。

---

## 四、界面与交互

单页三段式，三套面板在启动时一次性建好并常驻，切换只做「移出/移入屏幕」：

| 阶段 | 内容 |
|---|---|
| `select` | 左：3 张套餐卡 + 3 个附加服务芯片；中：实时画面 + 车牌卡 + 工序预览；右：会员余额 / 优惠券 / 明细 / 合计 / 确认支付 |
| `wash` | 左：6~7 行进度卡；中：圆环进度 + 指标卡 + 预计完成；右：4 项实时参数 + 提示 + 紧急停止 |
| `done` | 左：星级 + 标签 + 提交评价；中：完成图标 + 数据卡；右：本次小票 + 再来一次 / 返回首页 |

弹层：扫码支付（压暗蒙版 + 倒计时）、外观主题菜单、底部 toast（2.6 秒自动消失）。

---

## 五、主题与常用改动点

主题令牌集中在 `code/ui_theme.lua`，两套调色板结构完全一致：

```lua
M.dawn = { c = { ... }, glass = { ... } }
M.night = { c = { ... }, glass = { ... } }
M.f  = { display = 32, price = 26, big = 24, body = 20, sub = 18, mini = 18 }  -- 最小 18 号
M.r  = { card = 22, panel = 14, chip = 12, thumb = 12 }
```

| 想改什么 | 改哪里 |
|---|---|
| 主色 / 文字层次 | `c.pri` `c.text` `c.text_sub` `c.text_dim` |
| 面板底色 | `c.card` + `glass.card_opa`（**大面积请用不透明**，见“已知限制”） |
| 描边深浅 | `glass.hair_opa`（卡片）、`glass.hair2_opa`（内层卡）、`glass.chip_edge_opa`（芯片） |
| 背景渐变 | `glass.bg_top / bg_mid / bg_bot`（三段线性） |
| 字号 | `M.f.*`，注意改大后要给容器留宽（如「01」在 18 号时需要 30px） |
| 背光亮度 | `code/hardware.lua` 的 `BL_DUTY`，或运行期 `hardware.set_brightness(80)` |

主题切换是**热切换**：不销毁控件，按令牌名批量改色（`W.retint`），耗时约 1~5ms。

---

## 六、已知限制（LVGL/AirUI 能力边界）

1. **没有高斯模糊**：HTML 的 `backdrop-filter: blur(18px)` 无法实现，支付蒙版用纯色压暗（`#04080B` @140）近似；
2. **RGB565 下大面积半透明会偏色**：白 90% 叠浅底时 R/B 各掉一档、G 不掉，整屏会发绿，
   所以大面板一律用**不透明预混合色**，玻璃感靠 1px 描边与顶部高光表达；
3. **没有文本度量接口**：`¥126.00` 这种“小号符号 + 大号数字”无法按宽度对齐，金额保持整串同字号；
4. **`container:border` 在圆角处会画成直角**，所有圆角描边改用 `airui.shape` 的 1px 矩形描线；
   描边对象画在**外层容器**上，避免贴边时被父容器裁掉一半。
5. **hzfont 基准字号**取 18（界面最小号），其余尺寸按比例缩放；`antialias = 1`（2×2）省开销。

---

## 七、验证与调试

- 重建耗时日志：`界面已创建 … 重建耗时 NN ms`（PC 模拟器约 36~60ms）；
- 主题切换日志：`主题热切换 <mode> 改色对象 N 耗时 X ms`；
- 界面无 `destroyed airui component`、无 `E/airui` 输出即为正常；
- 洗车计时：`app_state.SPEED` 控制倍速（真机演示可调大）。
