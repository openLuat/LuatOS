# tools/ 使用说明（PC 端工具，不烧录到设备）

这里的 `.py` / `.json` / `.csv` 全部是**电脑上的辅助文件**，用 PC 的 Python 运行，
**不会、也不能用 Luatools 烧进 Air8607**。它们的唯一作用是：在电脑上提前算好道路，
产出一个 `roadnav.lua`，再由你把这个 `.lua` 烧进设备。

需要 Python 3（Windows 装 python.org 或应用商店版即可），脚本只用标准库，无需 pip 安装。

---

## 一、换一条导航路线：只要两条命令

在本目录（`airui_map/tools/`）打开命令行：

```bat
:: 1) 联网取真实驾车道路（起点=皇宋大观南门  终点=鼎立国际城E区，WGS84）
python fetch_osrm.py 114.325115,34.796553 114.315058,34.816085

:: 2) 把道路折线生成设备用的 roadnav.lua（写到上一级 airui_map/ 目录）
python gen_roadnav.py
```

跑完会刷新 `airui_map/roadnav.lua`，然后：

1. 用 **Luatools 烧录**：只选 `airui_map/` 下的 `.lua` 文件（含新的 `roadnav.lua`）；
2. 开机即定位在新路线起点、目的地为终点，点屏幕「定位开」就沿路模拟行驶。

### 换成自己的起点 / 终点

把命令里的两组数字换掉即可，格式是 `经度,纬度`（注意是**经度在前**）：

```bat
python fetch_osrm.py 起点经度,起点纬度 终点经度,终点纬度
python gen_roadnav.py
```

数据来自 OpenStreetMap（OSRM 公共算路服务），输入输出都是 **WGS84**，
和设备地图 `input_crs="wgs84"` 一致。

### 手里只有高德/腾讯网页上拾的坐标（GCJ02 火星坐标）

加 `--crs gcj02`，脚本会自动转回 WGS84，否则直接填会偏几十~几百米：

```bat
python fetch_osrm.py 起点经度,起点纬度 终点经度,终点纬度 --crs gcj02
python gen_roadnav.py
```

> 坐标来源判断：Google Earth、OpenStreetMap、手机 GPS 记录 = WGS84，直接用；
> 高德/腾讯/百度地图网页拾取 = GCJ02（百度还要再加一层 BD09，本脚本不支持）。

---

## 二、文件清单

| 文件 | 在哪跑 | 作用 |
|---|---|---|
| `fetch_osrm.py` | 电脑，需联网 | 用 OSRM 取真实驾车道路折线，存 `osrm_raw.json` |
| `gen_roadnav.py` | 电脑，不联网 | 读 `osrm_raw.json`，生成 `../roadnav.lua` |
| `osrm_raw.json` | 中间数据 | 取路结果（可删，重新取会再生成） |
| `make_route.py` | 电脑 | 另一种方式：用 CSV 途经点手动排路线，输出 JSON |
| `route_template.csv` | 输入样例 | `make_route.py` 的点表模板 |
| `demo_route.json` / `nav_route.json` | 数据/示例 | 路线 JSON（SD 卡路线方式用，见下） |

---

## 三、整条链路里文件分别去哪

- **`.lua`**（`airui_map/` 根目录）→ 设备固件，用 **Luatools 烧进 flash**；
- **`.py` / `tools/` 里的 `.json`、`.csv`** → 只留电脑，**烧录时不要选**；
- **离线瓦片图片、`pois.json`** → 直接拷到 **TF 卡 `/sd/`**，插卡使用。

烧录时只勾 `airui_map/` 下的 `.lua`，`tools/` 整个文件夹不用管。

---

## 四、备选：用 CSV 手动排路线（不调 OSRM）

适合自己已经知道沿途要经过哪些点、或园区/厂区自定义路线：

```bat
:: 按模板编辑 route_template.csv（列：lon,lat,name[,crs]）
python make_route.py --csv route_template.csv --out my_route.json
```

`make_route.py` 默认会在相邻点之间按 80 米插值让线更平滑（`--interp 0` 可关）。
生成的 JSON 拷到 SD 卡 `/sd/map/routes/`，用屏幕「加载路线」按钮读取。

---

## 五、常见问题

- **`fetch_osrm.py` 报证书错误 / 超时**：脚本已跳过证书校验；若仍超时是网络问题，重试或换网络。
- **取到的路线先往北绕一下**：真实路网存在单行线/禁转，OSRM 按真实交规绕行，属正常。
- **生成后设备没变化**：确认重新烧录了新的 `roadnav.lua`，且没误烧 `tools/` 里的文件。
- **想改模拟车速**：目前在 `map_demo.lua` 里每帧前进 25 米（约 18km/h），改那个数字即可。
