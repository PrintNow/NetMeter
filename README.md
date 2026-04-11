# NetMeter

macOS 菜单栏网速显示（基于 nettop 采样）。

## 从源码运行 / 构建

- 需要 **Xcode**（与工程 `MACOSX_DEPLOYMENT_TARGET` 匹配的 SDK）。
- 用 Xcode 打开 `NetMeter.xcodeproj`，选择 `NetMeter` scheme 运行即可。

### Debug 构建与 Spotlight

Xcode **Debug** 配置已将中间产物与 `.app` 输出到仓库内的 **`.derived.noindex/`**（通过 `SYMROOT` / `OBJROOT`）。目录名以 **`.noindex` 结尾时，系统 Spotlight 通常不会索引其中内容**，这样日常按 ⌘Space 搜索时不容易蹦出 DerivedData 里的调试版 NetMeter。

- **Release** 仍走默认 DerivedData（或由 `scripts/package-release.sh` 自带的 `-derivedDataPath` 决定），不受影响。
- 若你以前在本机用旧配置编译过，`~/Library/Developer/Xcode/DerivedData/NetMeter-*` 里可能还留着旧产物，可在 Xcode **Settings → Locations → Derived Data** 里删掉对应文件夹，或整包删除该 `NetMeter-*` 目录，避免历史副本仍被搜到。
- 若希望**全局**不再索引所有 Xcode 产物，可在 **系统设置 → Siri 与 Spotlight → Spotlight 隐私…** 中添加 `~/Library/Developer/Xcode/DerivedData`。

### 自动化打包（版本号来自 git tag）

```bash
# 需先有 v* 标签，例如 v1.0.0
./scripts/package-release.sh
```

产物在 `dist/`，文件名为 `NetMeter-<版本>-b<提交数>.zip`。详见脚本内注释。

## 无 Apple 开发者证书时：首次打开与隔离属性

本仓库默认使用 **本机临时签名**（`Sign to Run Locally`），**未做** Apple 公证（Notarization）。若你从网盘、GitHub Releases 等**下载 zip** 解压，macOS 会给 App 打上 **`com.apple.quarantine`（隔离）** 标记，可能出现：

- 提示「无法打开，因为来自身份不明的开发者」
- 或「已损坏，无法打开」（部分情况下实为 Gatekeeper 拦截）

可在解压后对 **`.app` 所在路径**执行下面命令，**递归清除扩展属性**（含隔离标记），再双击打开：

```bash
xattr -cr /路径/到/NetMeter.app
```

示例（假设已解压到「下载」文件夹）：

```bash
xattr -cr ~/Downloads/NetMeter.app
```

说明：

- `-c`：清除该路径上的扩展属性  
- `-r`：递归处理 `.app` 包内文件  

若你**只想去掉隔离**而保留其它 xattr，也可以用：

```bash
xattr -dr com.apple.quarantine /路径/到/NetMeter.app
```

仍被拦截时，可到 **系统设置 → 隐私与安全性**，在尝试打开一次后会出现 **「仍要打开」**，按提示操作即可。

> **安全提示**：`xattr -cr` 会去掉该目录下所有扩展属性，请只对**你信任来源**的 App 使用；从不可信渠道下载的软件不要盲目执行。

## 许可证

若仓库内另有 `LICENSE` 文件，以该文件为准。
