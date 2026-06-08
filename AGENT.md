# AGENT.md — NetMeter 编码规范

## 项目概述

NetMeter 是一个 macOS 菜单栏网速监控工具，**7×24 小时常驻运行**。
用户每天与它交互的时间极短（扫一眼数字），但它每秒都在后台工作。
因此：**性能至上、省电优先**是本项目的第一原则。

## 核心原则

### 1. 性能至上

- **菜单栏是门面** — 更新频率受 Timer 驱动，必须避免 SwiftUI `withObservationTracking` 高频闭环
- **采样在后台** — `getifaddrs` 等系统调用必须在 `DispatchQueue.global(qos: .utility)` 或 `Task.detached` 中执行，**绝不在主线程**
- **减少 @Published 通知** — 仅在值真正变化时写入，避免 SwiftUI 无意义重渲染
- **等宽布局防抖** — 菜单栏标签宽度采用"加宽立即生效、收窄延迟执行"策略，减少左右抖动
- **避免不必要的对象创建** — NSAttributedString 测宽等结果应缓存，不要在 Timer 回调中反复创建

### 2. 省电优先

- **自适应采样** — 连续 N 次无流量后自动降低采样频率（最高 8 秒），有流量时立即恢复
- **最小化唤醒** — Timer tolerance 设为 `interval * 0.5`（50%），允许系统合并多个定时器唤醒
- **RunLoop 模式用 `.default`** — 不要用 `.common`；`.common` 包含 `.eventTracking` 会阻止 App Nap coalescing，是菜单栏应用能耗偏高的主因
- **休眠/灭屏停止采样** — 订阅 `NSWorkspace.willSleepNotification` / `screensDidSleepNotification` 取消采样 Task，订阅 `didWakeNotification` / `screensDidWakeNotification` 重启；实现在 `NetworkSpeedMonitor.setupSleepObservers()`
- **无 UI 时不渲染** — 菜单关闭时停止不必要的刷新；About 窗口关闭后立即释放
- **不要轮询** — 用 `NWPathMonitor` 监听网络变化，不要定时检查网络状态

### 3. 线程安全

- `NetworkSpeedMonitor` 通过 `NSLock` 保护共享状态
- `InterfaceMonitor` 的 `@Published` 属性仅在主线程写入
- 跨线程回调使用 `[weak self]` 避免循环引用
- 标记 `@unchecked Sendable` 时必须有明确的同步机制

## 编码风格

### 命名
- `PascalCase`：类型、枚举 case
- `camelCase`：属性、方法、变量
- 前缀 `_` 仅用于 lock 保护的 backing store（如 `_sampleIntervalSeconds`）

### Swift 特性
- 优先使用 `async/await`，避免 Combine（除非用于 @Published 订阅）
- 使用 `nonisolated` 标注不依赖 actor 的纯函数
- 结构体优先于类（除非需要引用语义或 @Published）
- 枚举用于命名空间（如 `InterfaceCounterSampler`、`SpeedFormatter`）

### UI
- SwiftUI 用于 About 页等低频界面
- 菜单栏使用纯 AppKit（`NSStatusItem` + `NSStackView`），避免 `NSHostingView` 持续合成
- 字体使用 `monospacedDigitSystemFont` 保证数字等宽对齐

### 注释
- 代码自解释为主，不写显而易见的注释
- 仅在**为什么**不明显时添加注释（如回绕处理、防抖策略、平台限制）
- 文件头注释说明该文件的职责

## 架构

```
NetMeterApp.swift              — App 入口，MenuBarExtra 替代方案
MenuBarStatusController.swift  — 菜单栏 UI（AppKit），菜单构建与事件处理
NetworkSpeedMonitor.swift      — 采样调度中枢，管理 Task 循环与展示状态
InterfaceMonitor.swift         — NWPathMonitor 监听默认路由，维护可用接口
InterfaceCounterSampling.swift — getifaddrs 快照与差分计算（纯函数）
MenuBarSpeedPresentation.swift — 菜单栏定宽速率文案生成
SpeedFormatter.swift           — 主窗口用格式化
ContentView.swift              — 主窗口（Preview 用）
AboutView.swift                — 关于页
```

### 数据流

```
getifaddrs (内核)
  → InterfaceCounterSampler.snapshotTotals()
    → deltaBytes() 计算增量
      → SpeedDisplayState (主线程 @Published)
        → MenuBarSpeedLines (格式化)
          → NSTextField (菜单栏显示)
```

## 测试

- 使用 `@testable import` 测试 internal API
- 性能测试用 `measure {}` 验证采样和差分计算开销
- 边界值测试：32 位回绕、零流量、负值钳位、单位切换阈值

## Git 提交

格式：`type: 简短描述`

类型：
- `feat` — 新功能
- `fix` — 修复
- `refactor` — 重构（不改变行为）
- `perf` — 性能优化
- `ci` — CI/CD
- `chore` — 杂项

## 发布流程

1. 提交所有变更
2. 打 tag：`git tag vX.Y.Z`
3. `git push origin main && git push origin vX.Y.Z`
4. GitHub Actions 自动从 tag 名读取版本号，构建 arm64 + x86_64 并发布 Release

> `project.pbxproj` 中的版本号**不需要**手动修改；CI 通过 `MARKETING_VERSION="${GITHUB_REF_NAME#v}"` 在构建时注入。
