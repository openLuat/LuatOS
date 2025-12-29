# eink墨水屏演示系统

## 一、功能模块介绍

## 一、功能模块介绍

### 1.1 核心主程序模块

1. **main.lua** - 主程序入口，负责系统初始化和任务调度
2. **ui_main.lua** - 用户界面主控模块，管理页面切换和事件分发

### 1.2 显示页面模块

1. **home_page.lua** - 主页模块，提供应用入口和导航功能
2. **eink_page.lua** - eink核心库演示模块
3. **time_page.lua** - 时间显示演示模块

### 1.3 驱动模块

1. **eink_drv.lua** - eink显示驱动模块，基于eink核心库
2. **key_drv.lua** - 按键驱动模块，管理切换键(GPIO8)和确认键(GPIO5)

## 二、按键功能说明

### 2.1 按键消息

- **"KEY_EVENT"** - 按键事件消息，包含按键类型和状态
  - 切换键(GPIO8)事件：`switch_down`（按下）、`switch_up`（释放）
  - 确认键(GPIO5)事件：`confirm_down`（按下）、`confirm_up`（释放）

### 2.2 按键功能定义

- **主页页面**：
  - 切换键(GPIO8)：切换选项（eink演示 ↔ 时间显示）
  - 确认键(GPIO5)：确认进入选中的页面

- **eink演示页面**：
  - 确认键(GPIO5)：返回主页
  - 切换键(GPIO8)：无功能

- **时间显示页面**：
  - 切换键(GPIO8)：切换时间显示格式（共6种格式）
  - 确认键(GPIO5)：返回主页

## 三、显示效果

<table>
<tr>
<td>主页<br/></td><td>eink库图像页面<br/></td><td>更新时间页面<br/></td></tr>
<tr>
<td rowspan="2">
<img src="https://docs.openluat.com/cdn/image/Air780EHM_homepage.jpg" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/Air780EHM_einkpage.jpg" width="80" /><br/></td><td>
<img src="https://docs.openluat.com/cdn/image/Air780EHM_eink显示时间.jpg" width="80" /><br/></td></tr>
</table>

## 四、硬件接线配置

### 4.1 物料清单

- Air8101核心板 × 1
- 微雪1.54寸墨水屏 × 1 [demo所使用的墨水屏购买链接](https://e.tb.cn/h.7VUl8PgFVWhwLJS?tk=e3FVfDz34Ki)
- 母对母杜邦线 × 8
- TYPE-C 数据线 × 1
- Air8101核心板和微雪1.54寸墨水屏的硬件接线方式为

  - Air8101 核心板通过 TYPE-C USB 口供电（核心板背面的功耗测试开关拨到 OFF 一端），此种供电方式下，vbat 引脚为 3.3V，可以直接给微雪1.54寸墨水屏供电；
  - 为了演示方便，所以 Air8101 核心板上电后直接通过vbat引脚给微雪1.54寸墨水屏供电；
  - 客户在设计实际项目时，一般来说，需要通过一个 GPIO 来控制 LDO 给配件板供电，这样可以灵活地控制配件板的供电，可以使项目的整体功耗降到最低；

### 4.2 接线方式

|Air8101核心板| 墨水屏引脚 |
|------------|-----------|
| 75/GPIO28  | BUSY      |
| 10/GPIO7   | RST       |
| 75/GPIO28  | DC        |
| 68/GPIO12  | CS        |
| 65/GPIO2   | SCK       |
| 76/GPIO4   | DIN       |
| vbat       | VCC       |
| gnd        | GND       |

#### 4.2.3 接线图

![](https://docs.openLuat.com/cdn/image/Air8101_eink接线图.jpg)

## 五、演示软件环境

### 5.1 开发工具

- [Luatools下载调试工具](https://docs.openluat.com/air8101/luatos/common/download/) - 固件烧录和代码调试

### 5.2 内核固件

- [点击下载Air8101系列最新版本内核固件](https://docs.openluat.com/air8101/luatos/firmware/)，demo所使用的是LuatOS-SoC_V2002_Air8101 1号固件
  

## 六、演示操作步骤

### 6.1 硬件准备

1. 按照接线表连接eink屏幕
2. 确保电源连接正确，通过TYPE-C USB口供电
3. 确保所有连接正确无误

### 6.2 软件配置

在`main.lua`中选择加载对应的驱动模块：

```lua
-- 加载eink显示驱动管理功能模块
require "eink_drv"

-- 加载按键驱动管理功能模块
require "key_drv"

-- 加载eink核心库实现的用户界面功能模块
-- 实现多页面切换、按键事件分发和界面渲染功能
-- 包含主页、eink演示页和时间显示页
require "ui_main"

```

### 6.3 软件烧录

1. 使用Luatools烧录最新内核固件
2. 下载并烧录本项目所有脚本文件
3. 设备自动重启后开始运行

### 6.4 功能测试

#### 主页操作

1. 设备启动后显示主页
2. 使用切换键(GPIO8)在两个选项间切换
3. 使用确认键(GPIO5)进入选中的页面

#### eink演示页面

1. 查看基本图形绘制示例
2. 查看文本显示效果
3. 查看二维码和电池图标
4. 按确认键(GPIO5)返回主页

#### 时间显示页面

1. 查看当前时间显示
2. 使用切换键(GPIO8)切换不同的时间格式
3. 按确认键(GPIO5)返回主页

### 6.5 预期效果

- **主页**：清晰显示两个选项，选中状态明显
- **eink演示页面**：图形绘制清晰，布局合理
- **时间显示页面**：时间格式切换流畅
- **按键交互**：响应及时准确，页面切换正常

## 七、故障排除

1. **屏幕不显示**：检查SPI接线，确认电源供电
2. **按键无响应**：确认GPIO配置正确
3. **时间显示异常**：检查系统时间设置
4. **页面切换异常**：检查内存使用情况，适当调整刷新间隔

## 八、注意事项

1. eink屏幕刷新较慢，请勿频繁切换页面
2. 按键操作后请等待屏幕刷新完成
3. 长时间运行请确保电源稳定
4. 避免在高温高湿环境下使用

## 九、拓展使用

本demo内所演示的图形显示接口均可在eink核心库内找到，更丰富和详细的使用说明可以点击进入[eink核心库](https://docs.openluat.com/osapi/core/eink/)