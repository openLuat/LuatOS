# 饮料灌装产线中控屏（plcui）

按参考设计稿 1:1 复刻的 6 屏工控界面，使用 **PLCUI**（XML + 图片 + Lua）实现，目标机型
**Air8607（Air1603）+ 10 寸 RGB 1024×600 + GT911 电容触摸**，同一份代码也可在 PC 模拟器里预览。

| 页面 | 内容 | 关键组件 |
| --- | --- | --- |
| `overview` | 产线总览：8 台设备状态、6 个功能入口、启停/急停/一键报警；传送带光点流动动画（8 帧轮播）、电源开关（亮/暗两态） | image + label |
| `realtime` | 实时数据监控：设备节拍、4 条曲线趋势、4 个仪表、现场照片 | chart ×2 + label |
| `assets` | 设备运行管理：设备树、14 行设备表、设备详情、维护建议 | label + image（状态胶囊） |
| `params` | 工艺参数配置：10 个可编辑参数、权限/锁、工艺流程图 | textarea + keyboard |
| `report` | 产量统计报表：产量柱状图、合格率折线、不良品原因表 | chart ×2 + table |
| `alarm` | 故障报警记录：报警列表（分级配色）、选中详情、操作条 | label + image |

## 目录结构

```
plcui_beverage_line/
├── code/                 源码目录（PC 模拟器直接用这个）
│   ├── main.lua 等           脚本：main.lua + exd_air8607_rgb.lua + tp_app.lua
│   └── res/                  main.xml + 155 张素材（图片与 XML 必须同目录）
├── dist/                 make_flash_pack.py 生成的烧录包
│   └── luadb/                烧到 /luadb（脚本 + main.xml + 图片，同层平铺）
├── web/                  设计源文件（HTML/CSS，1024×600 固定画布）
│   ├── theme.css         工业风主题（面板/仪表/按钮/状态胶囊）
│   ├── *.html            6 个页面，元素带 data-type/data-id/data-handler 标记
│   └── img/              现场照片
├── tools/
│   ├── export_assets.py  HTML -> 背景图 + 按钮状态图 + main.xml
│   ├── check_xml.py      main.xml 结构/资源/事件/命名长度自检
│   ├── preview.py        离线合成 6 页效果图（不启动模拟器也能校对排版）
│   ├── make_flash_pack.py  打包 dist/luadb 烧录目录（全部平铺进 /luadb）
│   └── asset_map.txt     资源短名 -> 设计稿来源
├── preview/              离线预览结果
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
2. **部署**（脚本 + `main.xml` + 图片全部烧进 `/luadb`，同层平铺）：

   ```bash
   python tools/make_flash_pack.py    # 生成 dist/luadb/
   ```

   | 目录 | 内容 | 烧到 |
   | --- | --- | --- |
   | `dist/luadb/` | 3 个 lua + `main.xml` + 155 张 png/jpg，**同层平铺**（约 1.2 MB） | `/luadb` |

   plcui 的 `src` 只接受**相对于 XML 目录**的裸文件名（不允许 `/` 开头、`..` 或子目录），
   所以 `main.xml` 必须和图片放在同一目录：打包时把 `code/res/` 的内容平铺进
   `/luadb`（luadb 不保留子目录）。`main.lua` 会依次探测
   `/luadb/main.xml`、`/res/main.xml`、`/main.xml`，
   找到哪个就用哪个；PC 模拟器直接给 `code/` 目录，romfs 平铺后同样走 `/luadb` 分支。
3. 板级初始化已在 `main.lua` 内完成：PWM3 背光（GPIO13）、LCD 供电 GPIO17、
   DISP GPIO15、RGB 1024×600 时序、GT911（I2C1，RST 14，INT 51），
   触摸通过 `plcui.device_bind_touch(tp.init(...))` 绑定。
4. 兼容旧固件：`plcui.init` 先按新版 `plcui.init({width=,height=})` 调用，失败再退回
   旧版 `plcui.init(w, h)`。若日志提示 `E_DISPLAY_BUSY`／平台初始化失败，
   说明固件的 plcui 版本过旧，请重新编译固件或模拟器。

## 交互一览

- 总览页右侧 6 个入口进入各页；各子页左上角 `◀ 产线总览` 返回。
- 第一页：刷新数据（重置曲线相位）、导出曲线、报警确认。
- 第二页：设备树选择（联动设备详情与提示）、设备名/设备组切换、启动/停止/复位/维修记录、工程师权限。
- 第三页：点击参数值弹出数字键盘，校验范围后写入；修改权限、参数锁、保存/漂移还原/恢复默认/修改日志。
- 第四页：报表类型切换、导出 Excel/PDF/打印/邮件推送。
- 第五页：全部/紧急/警告/提示筛选、设备过滤、报警确认、复位、导出、声音与弹窗开关。
- 第六页：权限登录、启动/暂停产线、急停、一键报警。
- 每秒刷新：时钟、设备节拍、仪表值、趋势曲线（`chart:add_point`）、产量与合格率。

## 修改界面

界面**只改 `web/*.html`**，然后重新导出，不要手改 `main.xml`：

```bash
python tools/export_assets.py     # 重新生成 code/res/main.xml 与全部图片
python tools/check_xml.py         # 结构自检（未知属性会导致整份 XML 加载失败）
python tools/preview.py           # 离线合成效果图到 preview/
```

约定：需要被 plcui 控制的元素加 `class="plc"` 与 `data-type`（label/textarea/image/chart/table/keyboard），
`data-id` 即 XML 的 id；按钮再加 `data-states="normal,pressed"`/`normal,checked` 与 `data-handler`；
公共图片用 `data-asset="chip_run"` 复用同一个资源，`data-asset="blank"` 表示透明热区。

### 命名规范（重要）

**图片文件名、资源 id、组件 id 都不得超过 23 字节**（Air8607 luadb/VFS 限制）。导出脚本据此自动命名：

```
<页面短码>_<组件短名>_<状态首字母>.<扩展名>
  页面短码  ov rt as pa rp al
  状态      n=normal  p=pressed  c=checked  d=disabled
例如  as_chip_run_n.png   背景  bg_ov.jpg / bg_rt.jpg ...
```

`data-id` 同时是组件 id，所以组件 id 也要短（`btn_start` 而不是 `btn_line_start`）。
`tools/asset_map.txt` 记录了「资源短名 → 设计稿里的页面/组件/状态」，需要找某个 png 对应哪个按钮时查它。
超长时 `export_assets.py` 会直接报错退出，`check_xml.py` 也会把超长的文件名/id 列出来。

## 已知限制

- plcui 的 `table` 单元格不支持逐格配色，所以设备表/报警表把状态列做成了独立 label 或状态胶囊图片。
- plcui 的 `chart` 是 LVGL 原生折线/柱状图，没有设计稿里的渐变面积填充；刻度与图例文字烘焙在背景图里。
- 图片按组件尺寸导出（1024×600 背景为基线 JPEG），背景中不烘焙任何会变的数字；数字全部由 label 动态绘制，
  因此浏览器字体与真机 hzfont 的字形会有极细微差异。
- 参考资料中的产线照片用 AI 生成的工业场景替代，布局与尺寸保持一致。
