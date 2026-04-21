# 04 · Align（专业模式增量）

> 在初版 MVP 之上加一个 **Pro 模式**，把"专业相机用户最高频用到的 8 项能力"补齐。
> 严格遵循上一轮约束：iOS 17+、SwiftUI + Swift Concurrency、0 第三方依赖、`SWIFT_STRICT_CONCURRENCY = complete` + `-warnings-as-errors`。

## 1. 范围（Scope）

### 1.1 In-Scope（本迭代必做）

1. **新模式 `Pro`**：与 `beauty / photo / filter` 平级，进入后底部面板换成专业控件。
2. **手动曝光**
   - 切换 `Auto / Manual`
   - 手动模式下：拨盘式 ISO（设备 `activeFormat.minISO` ~ `maxISO`） + 拨盘式快门时间（`minExposureDuration` ~ `maxExposureDuration`，最长不超过 `1/2 s`，避免预览卡顿）
   - 自动模式下：EV 曝光补偿（±2 EV，0.1 步进）
3. **手动对焦**
   - 切换 `AF / MF`
   - MF 时通过滑块调节 `lensPosition`（0 ~ 1，0=最近）
4. **AE/AF 锁定**
   - 长按预览 0.6s 触发，左上角显示"AE/AF LOCK"标签
   - 再次长按或切换镜头解除
5. **多镜头变焦快速切换**
   - 自动检测设备实际焦距倍率（`virtualDeviceSwitchOverVideoZoomFactors`），构造 `[0.5×, 1×, 2×, 3×]` 的可用子集
   - 横向 4 个胶囊按钮，点击平滑变焦
6. **实时直方图**
   - 256-bin RGB + Luma，每 6 帧采样 1 次（≈5 Hz），降采样到 128×128 计算
   - 顶部右侧固定显示，70×40pt 卡片
7. **水平仪**
   - `CMMotionManager.deviceMotion`，10 Hz
   - 中心十字 + 角度文本（pitch、roll）；roll 水平差 < 1° 时变绿
8. **设备能力面板**：当前镜头、有效焦距、ISO/快门当前值、EV 当前值；只读，便于专业用户实时确认。

### 1.2 Out-of-Scope（显式不做）

- ProRAW / DNG（涉及完整重构 photo settings 与文件格式，留下个迭代）
- 手动白平衡（K + Tint 双轴，UI 复杂度高）
- 包围曝光（AEB），3 张连拍
- 焦点峰值（Focus Peaking，需要 Sobel/CIEdges + 性能调校）
- Live Photo / 慢动作 / 4K60
- 直方图选择（仅显示 RGB 复合，不分通道开关）

## 2. 平台与限制

- 仅在 **真机** 上完整可用：模拟器不暴露 `device.activeFormat`、`isExposureModeSupported(.custom)`、`CMDeviceMotion`，UI 会优雅降级。
- 镜头能力探测：使用 `AVCaptureDevice.DiscoverySession` 查 `builtInTripleCamera` / `builtInDualCamera` / `builtInUltraWideCamera`，根据可见硬件构造可用倍率集合。
- 当 device 不支持 `.custom` 曝光（极个别设备/状态），UI 屏蔽 ISO/Shutter 拨盘并提示"当前镜头不支持手动曝光"。

## 3. 非功能指标（增量）

| 指标 | 目标 |
| --- | --- |
| Pro 面板首次出现 | ≤ 50 ms |
| 手动 ISO/快门拨盘拖动 → 实际生效 | ≤ 50 ms（合并节流） |
| 切换 0.5×/1×/2×/3× | ≤ 250 ms 平滑斜率（`videoZoomFactor` ramping） |
| 直方图采样 | ≤ 1.5 ms / 帧（128×128 8-bin/通道） |
| 水平仪计算 | ≤ 0.2 ms / tick |
| 总主线程占用（开 Pro 全功能 + 滤镜） | 帧 ≤ 10 ms |

## 4. 验收（Done 标准）

- [ ] Mode 选择器多出 `Pro` 标签
- [ ] 进入 Pro：底部出现 `Auto/Manual` 切换 + ISO/Shutter 拨盘 + EV 滑杆 + AF/MF 切换 + 对焦距离滑杆
- [ ] 顶部右上角出现直方图卡片，顶部居中出现水平仪
- [ ] 多镜头条出现于预览底部，点击 1×→2× 看到平滑过渡
- [ ] 长按预览 0.6s → 出现 "AE/AF LOCK" 标识
- [ ] 切前后摄、切镜头、切 mode 时，所有 Pro 状态合法重置（不携带越界值）
- [ ] 模拟器能编译运行（Pro 控件保持可见但显示 "device unavailable"）
- [ ] 真机连续切 manual ↔ auto 与 ISO/Shutter 拖动 30s 不卡顿、不漂移、不崩溃
- [ ] `xcodebuild Debug + Release` 全绿、`-warnings-as-errors` 0 命中

## 5. 风险与对策

| 风险 | 对策 |
| --- | --- |
| 手动曝光下用户拖动过快 → device.lock 串行竞争 | actor 内只串行 `setExposureModeCustom`；UI 使用 60 Hz throttle |
| 多镜头切换在低端机有黑帧 | 用 `ramp(toVideoZoomFactor: withRate:)` 而非瞬切；保留上一帧（已存在的 MTKView 短路） |
| `CMMotionManager` 单例化 | 全局唯一，`@MainActor` 持有；进入 Pro 启动、退出 Pro 停止 |
| 直方图阻塞 video queue | 限频 ≤6 Hz、降采样到 128 边长、计算用 `vImageHistogramCalculation_ARGB8888` |
| 模拟器无相机 | UI 不崩溃，控件 disabled，文案兜底 |
