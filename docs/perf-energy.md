# 性能与能耗：如何对比 NetMeter 版本

本文说明如何在 macOS 上**可重复地**观察 NetMeter 的 CPU、唤醒与能耗，便于对比优化前后或不同「数据来源」后端。

## 已知能耗优化点（v1.5.2+）

| 优化 | 说明 |
|------|------|
| RunLoop `.default` | 菜单栏 Timer 从 `.common` 改为 `.default`，允许 App Nap coalescing |
| Timer tolerance 50% | 允许系统将唤醒合并到同一 CPU 唤醒周期 |
| 休眠/灭屏停止采样 | `NSWorkspace` 通知驱动，屏关后采样 Task 取消，唤醒后自动重启 |

## Activity Monitor

1. 打开「活动监视器」，切换到 **CPU** 或 **能耗**。
2. 在搜索框输入 `NetMeter`，观察 **% CPU**、**线程**、**Idle Wake Ups**（若显示）。
3. 静置 1～2 分钟记录数值。

说明：菜单栏类应用若周期性唤醒，**能耗排名**可能靠前；应同时看 **CPU% 是否长期个位数**（Release 构建更接近真实使用）。**12hr Power 目标 < 10**（同类 Clash Verge 约 11）。

## 验证休眠行为

1. 正常运行 NetMeter
2. 关闭显示器（`pmset displaysleepnow`）或系统休眠
3. 唤醒后确认菜单栏速率显示恢复正常（首次读数为 0，第二次采样后恢复）
4. Activity Monitor 确认休眠期间 NetMeter CPU 为 0

## Instruments

1. Xcode 打开工程，**Product → Profile**（或打开 Instruments），选择 **Time Profiler**。
2. 选择进程 **NetMeter**，录制 1～3 分钟。
3. 查看 **主线程** 栈顶符号：是否大量时间落在 AppKit 布局、`NSTimer`/`CFRunLoop`、或 Swift Concurrency。

可选：使用 **Energy Log**（若当前 Xcode/SDK 提供）针对同一进程对比优化前后。

## 命令行（可选）

短时采样整机任务能耗（**需要管理员密码**）：

```bash
sudo powermetrics --samplers tasks -i 5000 -n 12
```

在输出中关注 `NetMeter` 相关任务的能耗指标（具体字段因 macOS 版本而异）。

## XCTest 性能基线

在工程根目录执行：

```bash
xcodebuild test -scheme NetMeter -destination 'platform=macOS'
```

`InterfaceCounterPerfTests` 中的 `measure` 块会记录 `snapshotTotals` 与大规模 `deltaBytes` 的耗时分布，用于回归对比（数值因机器而异，看**相对变化**即可）。
