# 05 · Architect（专业模式增量设计）

## 1. 数据流（在 02-Architect 基础上叠加）

```
┌─────────────────────────────────────────────────────────────┐
│ Pro UI（SwiftUI）                                           │
│ ProPanel ─ ISOWheel / ShutterWheel / EVSlider / FocusSlider │
│ LensZoomBar ─ 0.5×/1×/2×/3×                                 │
│ HistogramView ─ 顶部右                                       │
│ LevelView ─ 顶部居中                                         │
└──────┬──────────────────────────────────┬──────────────────┘
       │ intents (debounced)              │ read state
       ▼                                  │
┌─────────────────────────────┐           │
│ CameraViewModel             │           │
│  + pro: ProSettings         │◄──────────┘
│  + caps: DeviceCapabilities │
│  + lockState: AEAFLock      │
│  + histogram: HistogramData │
│  + level: LevelReading      │
└──────┬──────────────────────┘
       │ async
       ▼
┌─────────────────────────────┐     ┌─────────────────────────┐
│ CameraService (actor)       │     │ LevelSensor (@MainActor)│
│  setExposureMode(.custom…)  │     │  CMMotionManager 10 Hz  │
│  setISO / setShutter        │     └─────────────────────────┘
│  setLensPosition            │
│  setExposureBias            │     ┌─────────────────────────┐
│  setZoomStop(_:smooth:)     │     │ HistogramSampler        │
│  lockAEAF() / unlock()      │◄────│  vImage on video queue  │
│  publish caps               │     │  ≤ 6 Hz                 │
└─────────────────────────────┘     └─────────────────────────┘
```

## 2. 新增 / 修改

### 2.1 新增模型 `Models/ProControls.swift`

```swift
enum ExposureMode: Sendable { case auto, manual }
enum FocusMode:    Sendable { case auto, manual }

struct ProSettings: Sendable, Equatable {
    var exposureMode: ExposureMode = .auto
    var focusMode:    FocusMode    = .auto
    var iso:               Float = 100
    var shutterSeconds:    Double = 1.0/60.0
    var exposureBiasEV:    Float = 0
    var lensPosition:      Float = 0.5    // 0..1
    var lockedAEAF:        Bool  = false
}

struct DeviceCapabilities: Sendable, Equatable {
    var minISO: Float = 22
    var maxISO: Float = 3200
    var minShutter: Double = 1.0/8000
    var maxShutter: Double = 1.0/2.0      // 强制截到 0.5s 上限，避免预览卡顿
    var minBiasEV: Float = -2
    var maxBiasEV: Float = 2
    var maxZoom: CGFloat = 1
    var lensStops: [LensZoomStop] = []
    var supportsCustomExposure = false
    var supportsManualFocus    = false
}

struct LensZoomStop: Hashable, Sendable, Identifiable {
    let label: String     // "0.5×" / "1×" / "2×" / "3×"
    let factor: CGFloat   // 实际 videoZoomFactor
    var id: String { label }
}
```

### 2.2 修改模型 `Models/CameraMode.swift`

新增 case：

```swift
enum CameraMode { case beauty, photo, filter, pro }
```

### 2.3 修改 `Camera/CameraService.swift`

新增方法（全部 actor-isolated）：

```swift
func setExposureMode(_ mode: ExposureMode)
func setISO(_ iso: Float)
func setShutter(seconds: Double)
func setExposureBias(_ ev: Float)
func setFocusMode(_ mode: FocusMode)
func setLensPosition(_ pos: Float)
func setZoomStop(_ stop: LensZoomStop, smooth: Bool)
func lockAEAF() -> Bool       // 返回成功与否
func unlockAEAF()
func capabilities() -> DeviceCapabilities
```

新增非阻塞通知：每次 `configureSession` 完成后更新 `capabilitiesCache`（`@unchecked Sendable` final class with NSLock），ViewModel 在切镜头后异步 `await caps()` 同步到 UI。

### 2.4 新增 `Camera/Histogram.swift`

```swift
struct HistogramBins: Sendable, Equatable {
    var luma: [UInt32]   // 64 bins，归一化前
    var maxBin: UInt32
}
final class HistogramSampler: @unchecked Sendable {
    func submit(_ pixelBuffer: CVPixelBuffer)   // 限频 + 降采样 + vImage
    var latest: HistogramBins?                  // 锁保护
}
```

性能要点：
- 每 6 帧采样一次 → ≤ 5 Hz
- 降采样到 128×128（`vImageScale_ARGB8888`）
- `vImageHistogramCalculation_ARGB8888` → 4×256，再合并成 64-bin Luma
- 单缓冲区静态分配，整段 0 alloc

### 2.5 新增 `Camera/LevelSensor.swift`

```swift
struct LevelReading: Sendable, Equatable {
    var rollDegrees:  Double  // 左负右正
    var pitchDegrees: Double  // 上正下负
    var isLevel: Bool         // |roll| < 1
}
@MainActor
final class LevelSensor {
    private let motion = CMMotionManager()
    private(set) var current: LevelReading = .zero
    func start(onUpdate: @escaping @MainActor (LevelReading) -> Void)
    func stop()
}
```

10 Hz；进入 Pro 模式启动，退出停止。计算：

```
roll  = atan2(g.x, g.y) * 180 / π   (g 为 deviceMotion.gravity)
pitch = atan2(-g.z, hypot(g.x, g.y)) * 180 / π
```

### 2.6 新增视图

- `Views/ProPanel.swift` —— 顶层容器，根据 `ProSettings.exposureMode` 切换显示
- `Views/IsoShutterWheel.swift` —— 通用拨盘（数值 + 滑动）
- `Views/EVSlider.swift` —— ±2EV 中心吸附（0 处吸附）
- `Views/FocusDistanceSlider.swift`
- `Views/LensZoomBar.swift` —— 多镜头胶囊
- `Views/HistogramView.swift`
- `Views/LevelView.swift`
- `Views/AEAFLockBadge.swift` —— 顶部"AE/AF LOCK"标识
- `Views/ProInfoStrip.swift` —— 顶部只读小字（焦距 / ISO / 快门 / EV）

### 2.7 修改 `ViewModel/CameraViewModel.swift`

新增 state：
```swift
var pro: ProSettings = .init()
var caps: DeviceCapabilities = .init()
var histogram: HistogramBins?
var level:     LevelReading = .zero
```

新增 intents（节流，使用 60 Hz `Task { await ... }` 合并）：
```swift
func setExposureMode(_:)
func setISO(_:)
func setShutter(_:)
func setEV(_:)
func setFocusMode(_:)
func setLensPosition(_:)
func selectZoomStop(_:)
func toggleAEAFLock()
```

新增 lifecycle：
- `mode == .pro` 时 `LevelSensor.start`
- `mode != .pro` 时 stop
- 切镜头后 `await refreshCapabilities()`

### 2.8 修改 `Pipeline/FrameProcessor.swift`

- 注入 `histogramSampler: HistogramSampler?`
- `process()` 末尾 `histogramSampler?.submit(frame.pixelBuffer)`（采样器内部限频）

### 2.9 修改 `Views/CameraScreen.swift`

- 顶部右上 overlay：`HistogramView`（仅 mode == .pro 时）
- 顶部居中 overlay：`LevelView`（mode == .pro）
- 顶部左：`AEAFLockBadge`（lockedAEAF 时）
- 预览底部固定 overlay：`LensZoomBar`（仅 mode == .pro）
- 长按手势：`LongPressGesture(minimumDuration: 0.6)` → `vm.toggleAEAFLock()`

## 3. 并发与线程

| 组件 | 隔离 | 备注 |
| --- | --- | --- |
| `HistogramSampler` | `@unchecked Sendable` final class | 内部 NSLock；vImage 调用在 video queue |
| `LevelSensor` | `@MainActor` | CMMotionManager 回调走主队列 |
| `DeviceCapabilities` | `Sendable` 值类型 | actor 计算后通过 `await` 拷给 VM |
| `ProSettings` | `Sendable` 值类型 | VM 持有，actor 单向消费 |

## 4. 性能保护

1. **拨盘节流**：UI 拖动只更新 `pro.iso/shutter/lensPosition` 的 @Observable 值；`Task { await camera.setX(...) }` 合并到 actor，actor 在执行 `device.lockForConfiguration` 之间天然串行。
2. **变焦平滑**：`device.ramp(toVideoZoomFactor: stop.factor, withRate: 6.0)`，无需手动插值。
3. **直方图轻量**：64-bin Luma + 单 alloc + 限频；UI 用 `Canvas` 绘制，避免 ForEach 256 个 Rect。
4. **水平仪低频**：10 Hz；UI 仅当 |Δroll| > 0.3° 才动画。

## 5. 失败兜底

- 模拟器：`AVCaptureDevice` 为 nil → caps 为默认值 + `supportsCustomExposure = false`，UI 控件 disabled。
- 设备不支持 `.custom`：UI 自动降级为 Auto + EV。
- `lockForConfiguration` 失败：toast "镜头被占用，请稍后再试"，不 crash。
