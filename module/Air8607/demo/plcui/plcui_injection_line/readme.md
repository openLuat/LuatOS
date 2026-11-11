# 注塑产线状态监管 HMI（plcui）

注塑产线（3 台注塑机 + 桁架机械手 + 传送带 + 辅机群）的状态监管、控制、记录界面，
使用 **PLCUI**（XML + 图片 + Lua）实现，目标机型
**Air8607（Air1603）+ 10 寸 RGB 1024×600 + GT911 电容触摸**，同一份代码也可在 PC 模拟器里预览。

| 页面 | 内容 | 关键组件 |
| --- | --- | --- |
| `ov` 产线总览 | 3 台注塑机 + 机械手 + 传送带动态场景、辅机区（干燥/储料/冷却塔/冷水机/模温机/包装/粉碎/回用）、KPI 看板（产量/节拍/合格率/OEE/周期）、报警横幅；传送带光点流动动画（8 帧轮播，停机定格） | image + label |
| `mc` 注塑机监控 | 机台选择、工艺阶段条（6 阶段整条多态帧实时推进）、6 区温度 / 4 路压力条形（10 档共享帧）、温度/压力趋势曲线、锁模力/位置/速度/螺杆、报警表 | chart ×2 + image |
| `ctl` 控制台 | 启动/停止/暂停/复位、自动/半自动/手动模式、安全状态、6 点动键、单机控制表（10 台设备开关）、班次管理、DO/AO 输出监控、故障诊断 | image（按钮两态）+ label |
| `pr` 参数设定 | 8 区温度 + 8 项压力/时间参数（16 个可编辑输入框、数字键盘、范围校验）、配方管理（4 配方）、修改历史 | textarea + keyboard |
| `rc` 生产记录 | 班次产量表、运行统计（今日产量/运行/停机/MTBF）、报警与操作记录、确认/翻页 | table + label |

## 目录结构

```
plcui_injection_line/
├── code/                 源码目录（PC 模拟器直接用这个，真机烧录也是这一份）
│   ├── main.lua              业务模拟引擎 + 页面刷新 + 事件处理
│   ├── tp_app.lua / exd_air8607_rgb.lua   触摸（GT911）与显示初始化库
│   └── res/                  main.xml + 164 张素材（图片与 XML 必须同目录）
├── web/                  设计源文件（HTML/CSS/JS，1024×600 固定画布，浏览器可直接交互预览）
│   ├── index/mc/ctl/pr/rc.html  5 个页面，元素带 data-type/data-id/data-handler 标记
│   ├── theme.css             深色工控主题
│   ├── app.js                浏览器版模拟引擎（与 main.lua 业务逻辑对齐）
│   └── img/lib/              SVG 素材（来自 PLC_SVG 图库 + 手绘设备图）
├── tools/
│   ├── export_assets.py  HTML -> 背景 JPG + 按钮/开关状态图 + 动画帧 + main.xml
│   ├── check_xml.py      main.xml 结构/资源/事件/命名长度自检
│   └── setup_dirs.py     工程初始化（建目录 + 从 PLC_SVG 复制素材）
└── run_windows.bat       PC 模拟器增量编译 + 运行（SDL 版 plcui）
```

## 运行

### PC 模拟器

plcui 依赖 SDL2，只有 GUI 版模拟器包含它：

```bat
run_windows.bat          :: 增量编译并运行
run_windows.bat full     :: 全量重编
run_windows.bat run      :: 跳过编译直接运行
```

### Air8607 真机

1. 固件需开启：`LUAT_USE_PLCUI`、`LUAT_USE_PLCUI_LUATOS`、`LUAT_USE_HZFONT`
   （含内置 TTF，界面中文全部走 hzfont），建议同时开 `LUAT_USE_PSRAM`。
2. **部署**：把 `code/` 内容烧到模块 `/luadb` 分区，其中
   `code/res/` 下的 `main.xml` 与全部图片要**平铺**到 `/luadb` 根
   （脚本与 XML/图片同层）：

   ```
   /luadb/main.lua
   /luadb/tp_app.lua
   /luadb/exd_air8607_rgb.lua
   /luadb/main.xml
   /luadb/*.png  *.jpg        ← code/res/ 的图片平铺上来
   ```

   可用合宙量产工具/脚本打包烧录，内容以 `code/` 为准。

3. 触摸走 `tp_app.lua`（i2c1 + GT911，20kHz），显示走
   `exd_air8607_rgb.lua`（display 后端失败自动降级 lcd 后端）。

## 重新导出（修改界面后）

界面设计源是 `web/*.html`（浏览器打开即可交互预览，数据会动态模拟）。
改动 HTML 后按下面顺序重新生成 PLCUI 工程文件：

```bash
python tools/export_assets.py     # 重新截图导出资源 + 生成 code/res/main.xml
python tools/check_xml.py         # 自检（命名 <= 23 字节、资源/控件上限、事件交叉检查）
```

导出脚本做的事：

1. Playwright 固定 1024×600 视口逐页截图：隐藏动态组件后整页出 **背景 JPG**；
   参数输入框只清空文字保留边框（plcui 的 textarea 无背景属性）。
2. 按钮/开关/机台选择/导航逐态裁剪 **状态图**（normal/pressed/checked）。
3. 工艺阶段条按 7 种进度态整条裁 **anim_phase_0..6**；
   温压条形按 10 档填充裁共享帧 `bar230_g/y/o_*`、`bar170_g/o_*`；
   传送带光点帧 `anim_belt_0..7` 由 PIL 几何作图（透明叠加，不动背景）。
4. 按 `.plc` 元素的 `data-*` 元数据生成 `main.xml`（5 page，entry=ov）。

## 素材来源

- `web/img/lib/`：20 个来自 `C:\Users\luat\Desktop\PLC_SVG` 图库（短名化复制），
  6 个手绘设备 SVG（注塑机/机械手/传送带/模具/粉碎机/包装，HMI 工控风格）。
- 纯色背景直接用 CSS 铺色，不生成背景切图；切图仅用于按钮/开关/动画等多态元素。

## 约束（Air8607 PLCUI 限制）

- 组件 id 与资源名 **<= 23 字节**，页面内 id 唯一（check_xml.py 强制）。
- 每页 **<= 512 控件**，全局 **<= 256 资源**：当前 180 控件 / 164 资源。
- 单张图 **<= 1KB**（小按钮/动画帧）、背景 JPG 约 40~130KB/张。
- 隐藏组件用 `visibility="hidden"`，不用 `x="-1000"`（出图边缘会留亮斑）。
- plcui 没有移动组件 API，产线"流动"效果全部走定时 `set_src` 帧轮播。
