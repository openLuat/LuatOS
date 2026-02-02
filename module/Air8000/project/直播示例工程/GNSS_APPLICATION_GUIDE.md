# LuatOS GNSS 应用架构指南

## 目录
1. [项目概述](#项目概述)
2. [GNSS核心架构](#gnss核心架构)
3. [震动检测模块](#震动检测模块)
4. [GNSS开关逻辑](#gnss开关逻辑)
5. [AGPS辅助定位](#agps辅助定位)
6. [低功耗模式](#低功耗模式)
7. [轨迹补偿模块](#轨迹补偿模块)
8. [数据上传机制](#数据上传机制)
9. [功耗管理](#功耗管理)
10. [技术亮点](#技术亮点)

---

## 项目概述

### 背景
上一讲，我们介绍了GNSS的一些理论知识，这一讲，我们根据一个实际项目，将里面的内容，抽象成一个有主要功能的演示demo，本demo 融合了exgnss库和vibration库，针对静止/运动条件下的GNSS定位做了一定优化，能够实现在尽可能的情况下，降低定位器的功耗，并减少静态漂移导致的轨迹不准等问题。

### 核心功能
- **智能定位**: 根据运动状态自动开启/关闭GNSS，平衡定位精度与功耗
- **AGPS辅助定位**: 通过exgnss内置AGPS实现快速定位（10秒内定位）
- **低功耗模式**: 支持GNSS低功耗模式，定时定位上传
- **震动检测**: 基于exvib传感器，精确识别静止/运动状态
- **轨迹补偿**: 基于速度航向平滑算法，减少定位漂移
- **JT808协议**: 完整实现JT808协议，与平台通信
- **多服务器管理**: 统一管理多个服务器实例

---

## GNSS核心架构

### 1. 直接使用exgnss接口

项目直接使用`exgnss`扩展库接口，无需手动管理电源和串口，更加简洁高效。

#### exgnss应用模式

`exgnss`提供了三种应用模式，分别适用于不同场景：

**exgnss.DEFAULT模式**
- 打开GNSS后，需要手动调用`exgnss.close()`关闭
- 适用于需要长时间持续定位的场景
- 本项目主定位流程使用此模式

**exgnss.TIMERORSUC模式**
- 打开GNSS后，在规定时间内定位成功自动关闭
- 如果到时间仍未定位，也会自动关闭
- 适用于低功耗定时定位场景（如GNSS低功耗模式）

**exgnss.TIMER模式**
- 打开GNSS后，无论是否定位成功，到时间后自动关闭
- 定位成功不会自动关闭，需等到时间到期

#### 引用计数机制

exgnss通过`tag`参数实现引用计数，确保GNSS资源不会被误关闭。

**设计理念**:
- GNSS作为共享资源，采用tag引用计数方式管理
- 不同模块使用不同的tag标签（如`common_app`、`gnsslowpower`）
- 只有所有tag都关闭时，GNSS才会被真正关闭
- 使用`exgnss.is_active()`检查GNSS状态

#### exgnss初始化配置
```lua
local gnssOpts = {
    gnssmode = 1,           -- 1为卫星全定位(GPS+北斗)，2为单北斗
    agps_enable = true,     -- 是否使用AGPS
    debug = true,           -- 是否输出调试信息
    uart = 2,               -- 使用的串口
    uartbaud = 115200,      -- 串口波特率
    bind = 1,               -- 绑定uart端口进行GNSS数据读取
    hz = 1,                -- 定位频率，1Hz=1秒/次
}
exgnss.setup(gnssOpts)
```

#### 核心API

**打开GNSS (DEFAULT模式)**
```lua
-- DEFAULT模式: 打开GNSS后需要手动关闭
if not exgnss.is_active(exgnss.DEFAULT, {tag = "common_app"}) then
    exgnss.open(exgnss.DEFAULT, {tag = "common_app"})
    -- exgnss会自动管理串口、电源等配置
end
```

**关闭GNSS**
```lua
-- 关闭GNSS
if exgnss.is_active(exgnss.DEFAULT, {tag = "common_app"}) then
    exgnss.close(exgnss.DEFAULT, {tag = "common_app"})
    -- exgnss会自动关闭电源和串口
end
```

**检查GNSS状态**
```lua
-- 检查GNSS是否打开
local isOpen = exgnss.is_active(exgnss.DEFAULT, {tag = "common_app"})

-- 检查定位状态
local isFixed = exgnss.is_fix()
```

#### 事件驱动
```lua
-- 订阅GNSS状态变化
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- "FIXED":  定位成功
    -- "LOSE":   定位丢失
    -- "CLOSE":  GNSS关闭(仅exgnss有效)
    if event == "FIXED" then
        -- 定位成功:1pps常亮
        isFix = true
    elseif event == "LOSE" then
        -- 定位丢失:1pps闪烁
        isFix = false
    elseif event == "CLOSE" then
        -- GNSS已关闭
        isFix = false
    end
end)
```

#### exgnss与原libgnss的区别

| 特性 | libgnss | exgnss |
|------|---------|--------|
| 管理方式 | 手动管理电源和串口 | 自动管理GNSS应用生命周期 |
| 应用模式 | 无 | DEFAULT/TIMERORSUC/TIMER三种 |
| 状态查询 | 手动维护isOpen变量 | 通过is_active()接口查询 |
| 关闭事件 | 无 | 发布"CLOSE"事件 |
| 回调支持 | 无 | 支持定位成功/超时回调 |
| 引用计数 | 手动实现 | 基于tag的引用计数 |
| 当前使用 | 用于数据解析和状态查询 | 用于GNSS生命周期管理 |

---

## 震动检测模块

### 2. 震动检测模块 (vibration.lua)

#### 传感器配置
- **芯片**: DA221加速度传感器
- **库**: exvib库
- **中断脚**: WAKEUP2 (双边沿触发)
- **检测精度**: 4g量程

#### 状态判断逻辑

**运动状态判断** (静止→运动)
```lua
-- 静止状态下，5秒内有2次以上震动则认为开始运动
if not isRun and recentVibrationCount >= 2 then
    isRun = true
    sys.publish("SYS_STATUS_RUN")  -- 发布运动事件
end
```

**静止状态判断** (运动→静止)
```lua
-- 运动状态下，8秒内振动次数小于3次则认为回到静止
if isRun and vibrationCount < 3 then
    isRun = false
    -- 不发布事件，通过manage.isRun()检测
end
```

#### 有效震动检测
```lua
-- 10秒内触发5次以上 = 有效震动
if timeDiff < 10 then
    effectiveVibrationFlag = true
    sys.publish("EFFECTIVE_VIBRATION")
    -- 30分钟冷却期
end
```

#### 关键参数
| 参数 | 值 | 说明 |
|------|-----|------|
| 静止→运动判定 | 5秒内2次震动 | 快速响应运动 |
| 运动→静止判定 | 8秒内<3次震动 | 延迟确认，避免误判 |
| 有效震动判定 | 10秒内5次震动 | 检测有效运动事件 |
| 防抖时间 | 100ms | GPIO去抖动 |
| 震动历史窗口 | 20次 | 用于运动检测 |
| 有效震动冷却期 | 30分钟 | 防止频繁触发 |

---

## GNSS开关逻辑

### 3. GNSS自动开关机制 (common.lua)

#### 状态机设计

**状态流转图**
```
CAPTURE(捕获) → TRACKING(追踪) → STATIC_GNSS(GNSS静止)
     ↑_____________←______________________________|
                  ↓ (首次捕获失败且静止)
            STATIC_LBS(LBS静止)
```

#### CAPTURE模式 (定位捕获)
```lua
if mode == "CAPTURE" then
    wlan.scan()  -- 扫描WiFi，用于辅助定位
    exgnss.open(exgnss.DEFAULT, {tag = "common_app"})
    while true do
        srvs.dataSend()
        if exgnss.is_fix() then
            mode = "TRACKING"  -- 定位成功，进入追踪
            break
        end
        result = sys.waitUntil("GNSS_STATE", 30 * 1000)
        if result == "FIXED" then
            mode = "TRACKING"
            break
        end
        -- 首次捕获最多尝试10次，之后最多尝试4次
        -- 如果4次未定位且当前静止，切换到LBS定位模式
        if times >= (firstCapture and 10 or 4) then
            firstCapture = false
            if not manage.isRun() then
                mode = "STATIC_LBS"  -- 切换到LBS静止模式
                break
            end
            times = 0  -- 继续尝试定位
        end
    end
end
```

#### TRACKING模式 (运动追踪)
```lua
if mode == "TRACKING" then
    manage.wake("READ_GNSS_DATA")
    sys.wait(2000)  -- 等待2秒，确保读到NMEA数据
    srvs.dataSend()
    manage.sleep("READ_GNSS_DATA")

    while true do
        -- 检查定位状态
        if not exgnss.is_fix() then
            mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
            break
        end

        manage.wake("READ_GNSS_DATA")
        result = sys.waitUntil("GNSS_STATE", 3000)  -- 等待3秒
        if result == "LOSE" then
            manage.sleep("READ_GNSS_DATA")
            mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
            break
        end

        -- 处理数据上传
        if fastUpload then
            -- 快速上传模式：立即上传
            srvs.dataSend()
        else
            -- 正常模式：缓存数据，每30次上传一次(约5分钟)
            if #dataCache > 60 then
                -- 缓存超过60条，删除最旧的
                local item = table.remove(dataCache, 1)
                item:free()
            end
            local item = zbuff.create(200)
            item:copy(nil, common.monitorRecord())
            table.insert(dataCache, item)
            waitUploadTimes = waitUploadTimes + 1

            -- 每30次上传一次
            if waitUploadTimes >= 30 then
                uploadCache()
            end
        end

        manage.sleep("READ_GNSS_DATA")
        result = sys.waitUntil("GNSS_STATE", 7000)  -- 等待7秒

        if result == "LOSE" then
            mode = "CAPTURE"  -- 定位丢失，切换到捕获模式
            break
        end

        -- 检测到静止，关闭GNSS进入STATIC_GNSS模式
        if not manage.isRun() then
            mode = "STATIC_GNSS"
            break
        end
    end
end
```

#### STATIC模式 (静止状态)
```lua
if mode == "STATIC_LBS" then
    manage.sleep("READ_GNSS_DATA")
    exgnss.close(exgnss.DEFAULT, {tag = "common_app"})
    lastGPSLocation.lat = 0
    lastGPSLocation.lng = 0
    while not manage.isRun() do
        srvs.dataSend()  -- 定期上传数据
        if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
            mode = "CAPTURE"  -- 检测到运动,重新捕获
            break
        end
    end
end

if mode == "STATIC_GNSS" then
    manage.sleep("READ_GNSS_DATA")
    exgnss.close(exgnss.DEFAULT, {tag = "common_app"})
    while not manage.isRun() do
        log.info("common", "STATIC_GNSS循环, isRun:", manage.isRun())
        srvs.dataSend()
        if sys.waitUntil("SYS_STATUS_RUN", 20 * 60 * 1000) then
            mode = "CAPTURE"
            break
        end
        sys.wait(5000)  -- 等待5秒,避免频繁调用
    end
end
```

#### 关键优化点

1. **轨迹补偿集成**
   - TRACKING模式中自动调用trackCompensate.compensate()
   - 平滑航向、速度，处理拐点
   - 减少GPS漂移导致的轨迹抖动

2. **事件发布优化**
   - 只在静止→运动时发布 `SYS_STATUS_RUN`
   - 运动→静止不发布事件，避免误触发

3. **超时保护**
   - 20分钟未检测到运动，自动切换到CAPTURE
   - 避免长时间静止后无法唤醒

---

## AGPS辅助定位

### 4. AGPS实现

**注意**: AGPS功能已集成到exgnss库中,通过配置`agps_enable = true`即可启用,无需手动实现AGPS逻辑。

#### exgnss初始化时启用AGPS
```lua
local gnssOpts = {
    gnssmode = 1,           -- 1为卫星全定位(GPS+北斗)，2为单北斗
    agps_enable = true,     -- 启用AGPS
    debug = true,           -- 是否输出调试信息
    hz = 1,               -- 定位频率1Hz
}
exgnss.setup(gnssOpts)
```

#### exgnss内置AGPS优势
- **自动管理**: exgnss自动处理基站定位、星历下载、时间同步等
- **无需手动编码**: 不需要手动调用lbsLoc2、http.request等
- **统一接口**: 所有AGPS相关操作通过exgnss统一管理
- **引用计数**: AGPS操作使用独立tag,不影响主应用

---

## 低功耗模式对比

### 5.1 GNSS低功耗模式与普通GNSS模式对比

#### 核心差异

**1. 应用模式不同**

| 特性 | 普通GNSS模式 | GNSS低功耗模式 |
|------|-------------|---------------|
| exgnss模式 | DEFAULT模式 | TIMERORSUC模式 |
| 关闭方式 | 手动调用close() | 定位成功或超时后自动关闭 |
| 定位策略 | 运动时持续定位，静止时关闭 | 固定间隔（60秒）定时定位 |
| tag标识 | "common_app" | "gnsslowpower" |

**普通GNSS模式** (common.lua)
```lua
-- DEFAULT模式: 打开GNSS后需要手动关闭
if not exgnss.is_active(exgnss.DEFAULT, {tag = "common_app"}) then
    exgnss.open(exgnss.DEFAULT, {tag = "common_app"})
end
-- 使用完毕后手动关闭
if exgnss.is_active(exgnss.DEFAULT, {tag = "common_app"}) then
    exgnss.close(exgnss.DEFAULT, {tag = "common_app"})
end
```

**GNSS低功耗模式** (gnssLowPower.lua)
```lua
-- TIMERORSUC模式: 定位成功或超时后自动关闭
exgnss.open(exgnss.TIMERORSUC, {
    tag = "gnsslowpower",                    -- 独立tag，不影响主应用
    val = _G.GNSS_LOWPOWER_INTERVAL or 60,   -- 60秒间隔
    cb = lowpower_callback                   -- 定位回调
})
```

**2. 定位策略不同**

**普通GNSS模式**
- 运动时：GNSS常开，每秒定位（1Hz）
- 静止时：关闭GNSS，降低功耗
- 根据震动状态动态开关（4种状态机模式）

**GNSS低功耗模式**
- 无论运动/静止，按固定间隔（60秒）定位
- 每次定位后自动关闭GNSS
- 适用于后台监控场景

**3. 数据流向不同**

| 特性 | 普通GNSS模式 | GNSS低功耗模式 |
|------|-------------|---------------|
| 上传目标 | 多个服务器（srvs统一管理） | 仅测试服务器（auxServer） |
| 数据内容 | 位置+WiFi+LBS+里程+电量等 | 仅位置信息 |
| 本地缓存 | 否 | 保存到/hxxtloc文件 |

**普通GNSS模式数据流**
```
common.monitorRecord() → srvs.dataSend() → 多个服务器
```

**GNSS低功耗模式数据流**
```
lowpower_callback() → auxServer.dataSend() → 测试服务器
                  ↓
               io.writeFile("/hxxtloc", locData)
```

**4. 使用场景对比**

| 场景 | 使用模式 | 定位频率 | 上传频率 | 说明 |
|------|---------|---------|---------|------|
| 学生正常运动 | 普通GNSS模式 | 每秒 | 5分钟一次 | 实时追踪，平衡功耗 |
| 学生放学回家 | 普通GNSS模式+快速上传 | 每秒 | 3秒一次 | 密集追踪，确保安全 |
| 夜间休眠 | GNSS低功耗模式 | 60秒一次 | 60秒一次 | 后台保活，最低功耗 |
| 长期静止 | GNSS低功耗模式 | 60秒一次 | 60秒一次 | 节省电量，定期保活 |

**5. 功耗对比**

| 模式 | 运动状态 | 静止状态 | 平均功耗 |
|------|---------|---------|---------|
| 普通GNSS模式 | GNSS常开，功耗较高 | GNSS关闭，功耗低 | 中等 |
| GNSS低功耗模式 | 每60秒开启几秒，大部分时间关闭 | 每60秒开启几秒，大部分时间关闭 | 最低 |

**6. 协同工作机制**

两种模式可以**同时运行**，互不影响：

```lua
-- 普通GNSS模式（common.lua）
exgnss.open(exgnss.DEFAULT, {tag = "common_app"})

-- GNSS低功耗模式（gnssLowPower.lua）
exgnss.open(exgnss.TIMERORSUC, {tag = "gnsslowpower", val = 60, cb = lowpower_callback})

-- 引用计数机制：
-- 两个tag都关闭时，GNSS才会真正关闭
-- 可以分别独立控制
```

**7. 配置开关**

通过 `cfg.lua` 控制GNSS低功耗模式是否启用：

```lua
-- cfg.lua
_G.GNSS_LOWPOWER_ENABLE = fskv.get("gnssLowPowerEnable") or false
```

**8. 总结**

两种模式是**互补关系**：

- **普通GNSS模式**：提供实时追踪，适合运动状态，定位精度高，功耗中等
- **GNSS低功耗模式**：提供后台保活，适合休眠状态，功耗最低，定位频率低

根据实际场景灵活选择，或同时启用两种模式，实现最优的功耗与定位精度平衡。

---

## 低功耗模式

### 5.2 GNSS低功耗模式实现细节 (gnssLowPower.lua)

#### 模式特性
- **定时定位**: 按配置间隔（如60秒）开启GNSS定位
- **自动关闭**: 定位成功或超时后自动关闭
- **独立tag**: 使用独立tag不影响主应用
- **集成AGPS**: 每次定位都执行AGPS加速

#### 初始化流程
```lua
function gnssLowPower.init()
    -- 加载AGPS配置
    local gnssOpts = {
        gnssmode = 1,        -- GPS+北斗
        agps_enable = true,   -- 启用AGPS
        hz = 1,             -- 1Hz定位频率
    }
    exgnss.setup(gnssOpts)
end
```

#### 定位回调
```lua
local function lowpower_callback(tag)
    local rmc = exgnss.rmc(0)
    if not rmc or not rmc.lat then
        return  -- 定位无效
    end

    -- 保存位置到缓存
    local locData = json.encode({lat = rmc.lat, lng = rmc.lng, time = os.time()})
    io.writeFile("/hxxtloc", locData)

    -- 上传到测试服务器
    auxServer.dataSend(nil)  -- nil表示自动调用common.monitorRecord()
end
```

#### 定时器设置
```lua
exgnss.open(exgnss.TIMERORSUC, {
    tag = "gnsslowpower",
    val = _G.GNSS_LOWPOWER_INTERVAL or 60,  -- 定位间隔(秒)
    cb = lowpower_callback
})
```

---

## 轨迹补偿模块

### 6. GNSS轨迹拐点补偿 (trackCompensate.lua)

#### 模块功能
- **航向平滑**: 根据历史航向数据进行加权平均，减少航向跳变
- **速度平滑**: 过滤速度突变，防止轨迹偏离实际路网
- **距离阈值过滤**: 过滤超出合理范围的漂移点
- **拐点检测**: 检测急转弯点并优化轨迹

#### 配置参数
```lua
local config = {
    distanceThreshold = 50,          -- 距离阈值（米），超过此距离认为漂移
    speedChangeThreshold = 5,        -- 速度突变阈值（km/h）
    courseChangeThreshold = 30,       -- 航向跳变阈值（度）
    enableCornerCompensate = true,    -- 是否启用拐点补偿
    minTurnRadius = 10,              -- 最小转弯半径（米）
}
```

#### 主补偿函数
```lua
local resultLat, resultLng, resultCourse, resultSpeed =
    trackCompensate.compensate(lat, lng, course, speed)
```

#### 关键算法

**1. 距离计算（Haversine公式）**
```lua
local function calculateDistance(lat1, lng1, lat2, lng2)
    local R = 6371000  -- 地球半径（米）
    -- 使用Haversine公式计算两点间距离
    -- ...
end
```

**2. 航向平滑**
```lua
-- 使用三角函数处理360度跳变
local sumSin = sumSin + math.sin(math.rad(c))
local sumCos = sumCos + math.cos(math.rad(c))
avgCourse = math.deg(math.atan2(sumSin, sumCos))
avgCourse = (avgCourse + 360) % 360
```

**3. 拐点补偿**
```lua
-- 检测急转弯（角度变化>90度）
if angleDiff > 90 and config.enableCornerCompensate then
    -- 沿当前航向预估位置
    estimatedLat = lat + (distance / 6371000) * math.cos(math.rad(bearing2))
    estimatedLng = lng + (distance / 6371000) * math.sin(math.rad(bearing2))
end
```

#### 集成方式
在`common.lua`的TRACKING模式中自动调用：
```lua
-- 轨迹补偿：平滑航向、速度，处理拐点
local compensatedLat, compensatedLng, compensatedCourse, compensatedSpeed =
    trackCompensate.compensate(lat, lng, course, speed)
if compensatedLat and compensatedLng then
    lat = compensatedLat
    lng = compensatedLng
    course = compensatedCourse
    speed = compensatedSpeed
end
```

#### 模式特性
- **定时定位**: 按配置间隔(如60秒)开启GNSS定位
- **仅上传测试服务器**: 不影响其他服务器数据流
- **集成AGPS**: 每次定位都执行AGPS加速

#### 初始化流程
```lua
function gnssLowPower.init()
    -- 加载AGPS配置
    local gnssotps = {
        gnssmode = 1,        -- GPS+北斗
        agps_enable = true,   -- 启用AGPS
        hz = 1,             -- 1Hz定位频率
    }
    exgnss.setup(gnssotps)
end
```

#### 定位回调
```lua
local function lowpower_callback(tag)
    local rmc = exgnss.rmc(0)
    if not rmc or not rmc.lat then
        return  -- 定位无效
    end
    
    -- 保存位置到缓存
    local locData = json.encode({lat = rmc.lat, lng = rmc.lng, time = os.time()})
    io.writeFile("/hxxtloc", locData)
    
    -- 上传到测试服务器
    auxServer.dataSend(nil)  -- nil表示自动调用common.monitorRecord()
end
```

#### 定时器设置
```lua
exgnss.open(exgnss.TIMERORSUC, {
    tag = "lowpower",
    val = _G.GNSS_LOWPOWER_INTERVAL or 60,  -- 定位间隔(秒)
    cb = lowpower_callback
})
```

---

## 数据上传机制

### 7. 数据上传频率说明

#### TRACKING模式（运动追踪）上传频率

**正常模式上传**
- 每3秒获取一次GNSS数据并缓存（`sys.waitUntil("GNSS_STATE", 3000)`）
- 每次循环等待7秒（`sys.waitUntil("GNSS_STATE", 7000)`）
- 每采集30次数据后批量上传一次（`waitUploadTimes >= 30`）
- **上传间隔：30次 × 10秒 = 300秒（5分钟）**

**快速上传模式**
- 每3秒上传一次定位数据
- 立即上传，不等待缓存
- 通过`common.setfastUpload(time)`触发

#### 进入/退出快速上传模式

通过调用 `common.setfastUpload(time)` 函数：

```lua
-- 进入快速上传模式，持续10分钟
common.setfastUpload(10)

-- 退出快速上传模式
common.setfastUpload(0)
```

**参数说明：**
- `time > 0`：进入快速上传模式，持续指定分钟数
- `time == 0`：退出快速上传模式

**触发方式：**
1. 服务器远程控制：测试服务器发送指令触发
```lua
-- auxServer.lua 中接收服务器指令
common.setfastUpload(interval, timeout)
```

2. 本地代码调用：在业务逻辑中根据需要调用

**注意事项：**
- 只有在`TRACKING`（跟踪）模式下才有效
- 进入快速上传模式时会立即上传一次数据
- 超时后自动退出快速上传模式，恢复正常的5分钟上传间隔
- 同时会触发`mreport.send()`和发布`SYS_STATUS_RUN`事件

---

## 数据包格式

### 8. JT808定位数据包

#### 定位数据包格式
```lua
function common.monitorRecord()
    -- 基础定位信息（0x0200）
    local tTime = os.date("*t", os.time())
    local status = 0x02  -- 定位有效位
    local lat, lng = lastGPSLocation.lat, lastGPSLocation.lng

    local baseInfo = jt808.makeLocatBaseInfoMsg(0, status, lat, lng, altitude, speed, course, tTime)

    -- 扩展信息
    baseInfo = baseInfo .. api.NumToBigBin(0x65, 1) .. satelliteInfo()  -- 卫星信号强度
    baseInfo = baseInfo .. api.NumToBigBin(0x01, 1) .. mileageInfo()  -- 里程
    baseInfo = baseInfo .. api.NumToBigBin(0x04, 1) .. chargeInfo()   -- 充电状态和电量
    baseInfo = baseInfo .. api.NumToBigBin(0x2B, 1) .. voltageInfo()  -- 电池电压
    baseInfo = baseInfo .. api.NumToBigBin(0x30, 1) .. signalInfo()   -- 信号强度
    baseInfo = baseInfo .. api.NumToBigBin(0x31, 1) .. satelliteCountInfo()  -- 卫星个数
    baseInfo = baseInfo .. api.NumToBigBin(0x5F, 1) .. crashLevelInfo()  -- 崩溃日志
    baseInfo = baseInfo .. api.NumToBigBin(0x64, 1) .. gnssModeInfo()  -- GNSS工作模式
    baseInfo = baseInfo .. wifiInfo()  -- WiFi信息
    baseInfo = baseInfo .. lbsInfo()   -- 基站信息
    baseInfo = baseInfo .. versionInfo()  -- 软件版本号

    return baseInfo
end
```

#### 附件ID说明
| 附件ID | 说明 | 长度 |
|--------|------|------|
| 0x01 | 里程 | 4字节 |
| 0x04 | 充电状态、电量百分比 | 2字节 |
| 0x2B | 电池电压 | 4字节 |
| 0x30 | 信号强度 | 1字节 |
| 0x31 | 卫星个数 | 1字节 |
| 0x54 | WiFi信息 | 可变 |
| 0x5D | 基站信息 | 可变 |
| 0x5F | 崩溃日志级别 | 8字节 |
| 0x64 | GNSS工作模式 | 1字节 |
| 0x65 | 卫星信号强度 | 可变 |
| 0x66 | 软件版本号 | 4字节 |
| 0x67 | GNSS软件版本号 | 2字节 |

---

## 功耗管理

### 9. 设备功耗管理 (manage.lua)

#### 引用计数机制
```lua
-- 模块休眠tag管理表（引用计数）
local tags = {}

-- 唤醒模块
function manage.wake(tag)
    tags[tag] = 1  -- 增加唤醒计数
    pm.request(pm.IDLE)  -- 请求IDLE模式
end

-- 休眠模块
function manage.sleep(tag)
    tags[tag] = 0  -- 减少唤醒计数
    -- 检查是否所有tag都已休眠
    for k, v in pairs(tags) do
        if v > 0 then  -- 还有唤醒的tag，不能休眠
            return
        end
    end
    pm.request(pm.LIGHT)  -- 请求LIGHT模式（低功耗）
end
```

#### 唤醒/休眠标签
| 标签名 | 说明 | 触发场景 |
|--------|------|----------|
| READ_GNSS_DATA | GNSS数据读取 | 读取NMEA数据前唤醒，读取后休眠 |
| charge | 充电状态 | 检测到充电时唤醒，充电结束休眠 |

#### 电源按键控制
```lua
-- 长按3秒触发关机，松开取消
gpio.setup(46, pwrkeyCb, gpio.PULLUP, gpio.BOTH)

local function pwrkeyCb()
    if gpio.get(46) == 1 then
        -- 按键松开：取消关机定时器
        if sys.timerIsActive(manage.powerOff) then
            sys.timerStop(manage.powerOff)
        end
    else
        -- 按键按下：启动3秒关机定时器
        sys.timerStart(manage.powerOff, 3000)
    end
end
```

#### 定位数据包格式
```lua
function common.monitorRecord()
    -- 基础定位信息
    local tTime = os.date("*t", os.time())
    local status = 0x02  -- 定位有效位
    local lat, lng = lastGPSLocation.lat, lastGPSLocation.lng
    
    local baseInfo = jt808.makeLocatBaseInfoMsg(0, status, lat, lng, altitude, speed, course, tTime)
    
    -- 扩展信息
    baseInfo = baseInfo .. satelliteInfo()  -- 0x65 卫星信号强度
    baseInfo = baseInfo .. mileageInfo()  -- 0x01 里程
    baseInfo = baseInfo .. chargeInfo()   -- 0x04 充电状态和电量
    baseInfo = baseInfo .. voltageInfo()  -- 0x2B 电池电压
    baseInfo = baseInfo .. signalInfo()   -- 0x30 信号强度
    baseInfo = baseInfo .. wifiInfo()     -- 0x54 WiFi信息
    baseInfo = baseInfo .. lbsInfo()      -- 0x5D 基站信息
    
    return baseInfo
end
```

#### 上传流程
```lua
-- auxServer.lua
if #dataQueue > 0 then
    local item = dataQueue[1]
    local pTxBuf = jt808.positionPackage(lastTxMsgSn, simID, item:query())
    lastTxMsgID = 0x0200
    
    result = libnet.tx(d1Name, 15000, netc, pTxBuf)
    if result then
        item:free()
        table.remove(dataQueue, 1)
    end
end
```

---

## 技术亮点

### 1. 智能功耗管理
- **动态开关**: 根据运动状态自动控制GNSS
- **低功耗模式**: 常规模式与GNSS低功耗模式灵活切换
- **引用计数**: 使用manage.wake/sleep和exgnss的tag机制
- **exgnss集成**: 统一管理GNSS应用生命周期

### 2. 快速定位技术
- **AGPS加速**: 基站定位 + 星历下载 → 10秒内定位
- **热启动**: 保存星历和位置，减少冷启动时间
- **智能切换**: GNSS定位失败自动降级到LBS定位

### 3. 震动检测优化
- **自适应阈值**: 不同场景采用不同的判定阈值
- **防抖设计**: GPIO防抖（100ms）+ 时间窗口去噪
- **有效震动**: 区分无效震动和真实运动

### 4. 轨迹补偿算法
- **航向平滑**: 使用三角函数处理360度跳变
- **速度平滑**: 过滤速度突变
- **距离过滤**: 过滤超出阈值（50米）的漂移点
- **拐点优化**: 检测急转弯并优化轨迹

### 5. 事件驱动架构
- **解耦设计**: 模块间通过事件通信
- **异步处理**: 避免阻塞主流程
- **状态机**: 清晰的状态流转逻辑（4种模式）
- **exgnss事件**: 支持GNSS关闭事件，更完善的状态管理

### 6. 数据完整性
- **多源定位**: GNSS + LBS + WiFi
- **轨迹补偿**: 减少静态漂移
- **数据缓存**: 本地保存最后位置
- **重传机制**: 失败重传，确保数据不丢失

### 7. 多服务器管理
- **统一接口**: srvs模块统一管理多个服务器
- **数据分发**: 一次调用发送到所有服务器
- **状态查询**: 任意一个服务器连接即返回true

---

## 总结

本GNSS应用架构通过智能震动检测、AGPS辅助定位、轨迹补偿、多级低功耗管理等技术，实现了定位精度与功耗的完美平衡。

**核心价值**:
- ✅ 定位速度快: AGPS 10秒内定位
- ✅ 功耗低: 静止时自动关闭GNSS，降低功耗
- ✅ 准确性高: 多源定位融合 + 轨迹补偿
- ✅ 用户体验好: 自动开关，无感知
- ✅ 可扩展性: 多服务器管理，灵活配置

**适用场景**:
- 学生卡、宠物追踪器
- 车辆定位、物流追踪
- 资产管理、设备租赁

---

## 模块列表

| 模块名 | 文件 | 功能说明 |
|--------|------|----------|
| common | common.lua | GNSS定位状态机、位置数据打包 |
| vibration | vibration.lua | 震动检测、静止/运动状态判断 |
| trackCompensate | trackCompensate.lua | 轨迹补偿、航向速度平滑 |
| manage | manage.lua | 功耗管理、唤醒/休眠控制 |
| charge | charge.lua | 电池电量监测、充电状态检测 |
| auxServer | auxServer.lua | 测试服务器、JT808协议通信 |
| srvs | srvs.lua | 多服务器统一管理 |
| jt808 | jt808.lua | JT808协议实现 |
| netWork | netWork.lua | 网络状态监控 |
| mreport | mreport.lua | 遥测数据上报 |
| cfg | cfg.lua | 配置管理、fskv存储 |
| bootup | bootup.lua | 系统启动、模块加载 |
| main | main.lua | 主程序入口 |
| ledTask | ledTask.lua | LED指示灯控制 |
| mdebug | mdebug.lua | 调试工具、内存监控 |
| api | api.lua | 工具函数库、数据转换 |

---

*文档编写日期: 2026-02-02*
*最后更新: 已迁移至exgnss接口*
*LuatOS版本: V2022*
*芯片型号: Air8000*
*GNSS接口: exgnss扩展库*
