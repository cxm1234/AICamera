# 02 · Architect（架构设计）

## 1. 分层

```
┌────────────────────────────────────────────────────────────┐
│  View 层（SwiftUI）                                        │
│  CameraScreen / TopBar / BottomBar / FilterStrip /         │
│  BeautyPanel / ShutterButton / PreviewSheet …              │
└───────────────▲──────────────────────────┬─────────────────┘
                │ 读 @Observable           │ 触发 intent
                │                          ▼
┌────────────────────────────────────────────────────────────┐
│  ViewModel 层（@Observable，主线程）                        │
│  CameraViewModel：UI 状态 + 用户意图编排                   │
└───────────────▲──────────────────────────┬─────────────────┘
                │ AsyncStream<UIState>     │ async 调用
                │                          ▼
┌────────────────────────────────────────────────────────────┐
│  Service 层（actor，后台线程）                              │
│  CameraService（拍摄/会话）  PhotoLibrarySaver（写入）     │
│  HapticsManager（触感）                                    │
└───────────────▲──────────────────────────┬─────────────────┘
                │ CVPixelBuffer            │ CIImage
                │                          ▼
┌────────────────────────────────────────────────────────────┐
│  Pipeline 层（GCD 串行队列 + Metal）                        │
│  FrameProcessor → FilterEngine → BeautyEngine → 渲染       │
└────────────────────────────────────────────────────────────┘
```

## 2. 数据流

### 2.1 预览帧流（每秒 30 次）

```
AVCaptureVideoDataOutput
        │  CMSampleBuffer (BGRA, 1080p)            [video queue]
        ▼
FrameProcessor.process(_:)                          [video queue]
   1. CVPixelBuffer → CIImage（零拷贝）
   2. 应用 FilterEngine（当前滤镜 + 强度）
   3. 应用 BeautyEngine（强度 > 0 才执行）
        - 取最近一次 Vision face landmarks
        - 磨皮 / 美白 / 瘦脸 / 大眼
   4. 输出 CIImage 到 PreviewRenderer
        ▼
PreviewRenderer.draw(_:)                            [video queue]
   - CIContext.render(to: drawable.texture)         （MTKView 自动 vsync）
```

### 2.2 拍照流（用户按下快门）

```
ShutterButton.tap                                   [main]
  → HapticsManager.impact(.medium)                  [actor]
  → 快门动画                                          [main]
  → CameraService.capturePhoto()                    [actor]
       AVCapturePhotoOutput.capturePhoto(...)
  → PhotoCaptureDelegate.didFinishProcessingPhoto   [photo callback queue]
       原图 CIImage（从 photo.fileDataRepresentation 解出）
  → 同一 Pipeline 应用滤镜 + 美颜（高分辨率，单次）  [bg queue]
  → PhotoLibrarySaver.save(_:)                      [actor]
  → ViewModel.publish(.captured(thumbnail))         [main]
  → PreviewSheet 弹出
```

### 2.3 人脸检测流（独立节流）

```
FaceDetector.start(stream:)                         [bg queue]
  - 接收 FrameProcessor fork 出的低分辨率帧
  - 限频 15 Hz
  - VNDetectFaceLandmarksRequest
  - 输出 [FaceObservation]（landmarks + bounds）
  - 写入 BeautyEngine.faceCache（atomic）
```

## 3. 并发模型

| 组件 | 类型 | 线程 / 队列 |
| --- | --- | --- |
| `CameraService` | `actor` | 内部串行 |
| `FrameProcessor` | `final class`（Sendable via @unchecked + 串行队列） | `com.aicamera.video`（user-initiated） |
| `FaceDetector` | `final class` + 串行队列 | `com.aicamera.face`（utility） |
| `FilterEngine` / `BeautyEngine` | 值/类，纯函数式调用 | 调用方所在队列 |
| `PreviewRenderer` | `MTKViewDelegate` | `com.aicamera.video` |
| `CameraViewModel` | `@Observable @MainActor` | main |
| `PhotoLibrarySaver` | `actor` | 内部串行 |
| `HapticsManager` | `@MainActor` 单例 | main |

**Sendable 边界**：`CMSampleBuffer` / `CVPixelBuffer` / `CIImage` 在跨 actor 时用 `@unchecked Sendable` 包装的轻量值类型 `VideoFrame`，并在使用方立即消费、不做长期持有。

## 4. 关键模型

```swift
// 不可变值类型，安全跨 actor
struct CameraConfiguration: Sendable {
    var position: AVCaptureDevice.Position = .back
    var flashMode: AVCaptureDevice.FlashMode = .off
    var timer: ShutterTimer = .off
    var aspectRatio: AspectRatio = .ratio4x3
    var isGridVisible: Bool = false
}

struct FilterPreset: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let kind: FilterKind   // 内置枚举驱动 CIFilter 链
}

struct BeautySettings: Sendable, Equatable {
    var smoothing: Double = 0     // 0...1
    var whitening: Double = 0
    var sharpness: Double = 0
    var slimFace: Double = 0
    var bigEye:   Double = 0
    var enabled: Bool { smoothing + whitening + sharpness + slimFace + bigEye > 0.001 }
}

enum CameraMode: String, CaseIterable, Sendable { case beauty, photo, filter }

@Observable @MainActor
final class CameraViewModel {
    var configuration = CameraConfiguration()
    var beauty = BeautySettings()
    var selectedFilter: FilterPreset = .original
    var filterIntensity: Double = 1.0
    var mode: CameraMode = .photo
    var permission: PermissionState = .unknown
    var lastCaptured: CapturedPhoto?
    var error: CameraError?
    // intents
    func capture() async { ... }
    func switchCamera() async { ... }
    func setFocus(at point: CGPoint) async { ... }
    func setZoom(_ factor: CGFloat) async { ... }
}
```

## 5. UI 结构（对标美颜相机）

```
CameraScreen (ZStack)
├── PreviewLayer（全屏，Metal 视图，aspect-fit 黑边）
├── 顶部 TopBar（半透明）
│     ├── 闪光灯  ├── 倒计时  ├── 比例  ├── 网格  ├── 设置
├── 焦点指示 FocusIndicator（按需出现）
├── 底部容器（半透明圆角，阴影上浮）
│     ├── 上：FilterStrip（mode == .filter）/ BeautyPanel（mode == .beauty）
│     ├── 中：ModeSelector（横向胶囊，beauty / photo / filter）
│     └── 下：HStack
│           ├── 左：相册缩略图按钮
│           ├── 中：ShutterButton（80pt 双环 + 按压缩放 0.92）
│           └── 右：切换前后摄
└── 全屏 Sheet：PhotoPreviewSheet
```

视觉规范：
- 背景纯黑 `#0A0A0A`，前景 `Color.white.opacity(0.92)`
- 主按钮强调色 `#FF4D6D`（与美颜相机一致的桃粉色）
- 圆角统一 `RoundedRectangle(cornerRadius: 16, style: .continuous)`
- 字体 `.system(.subheadline, design: .rounded, weight: .semibold)`
- 触感：滑杆每 10 档 `.selection`；快门 `.medium`；切镜头 `.soft`

## 6. 性能策略落地

1. **预览短路**：`BeautySettings.enabled == false && filter == .original` 时，`FrameProcessor` 直接把原 `CVPixelBuffer` 走 `CIImage(cvPixelBuffer:)` 渲染，跳过所有 `CIFilter`。
2. **降采样美颜**：磨皮在 1/2 分辨率执行，再 `CILanczosScaleTransform` 上采，CPU 占用直降 ~60%。
3. **Filter 缓存**：`FilterEngine` 内部按 `(kind, intensity)` 缓存最后一组 `CIFilter` 实例，避免每帧 alloc。
4. **CIContext 单例**：全局一个 `CIContext(mtlDevice:)`，禁用 `kCIContextCacheIntermediates` 避免内存膨胀。
5. **Vision 节流**：`CADisplayLink`-style 用时间戳判断，距上次 < 66ms 直接 drop。
6. **首帧加速**：`CameraService.bootstrap()` 在 App 启动时 `Task.detached` 预热（创建 session、查询 device），用户 push 到 `CameraScreen` 时 `startRunning()` 立即出图。

## 7. 错误与权限

```
PermissionState: notDetermined / denied / restricted / authorized
CameraError:    .denied / .deviceUnavailable / .configurationFailed
                / .captureFailed(Error) / .saveFailed(Error)
```

- `denied` → 全屏引导卡片，CTA 跳 `UIApplication.openSettingsURLString`
- 其他 `CameraError` → 顶部 toast（自动消失 2s）+ `os_log`，不 alert 打断流程

## 8. 文件结构

```
AICamera/
├── App/
│   ├── AICameraApp.swift          // @main
│   └── AppRoot.swift              // ScenePhase 监听 + 注入
├── Camera/
│   ├── CameraService.swift        // actor，AVCaptureSession 编排
│   ├── CameraPermissions.swift    // AVCapture/Photos 权限封装
│   ├── CameraPreviewView.swift    // UIViewRepresentable + MTKView
│   ├── PreviewRenderer.swift      // MTKViewDelegate
│   └── VideoFrame.swift           // 跨 actor 的 Sendable 包装
├── Pipeline/
│   ├── FrameProcessor.swift
│   ├── FilterEngine.swift
│   ├── BeautyEngine.swift
│   ├── FaceDetector.swift
│   └── CIContext+Shared.swift
├── Models/
│   ├── CameraConfiguration.swift
│   ├── BeautySettings.swift
│   ├── FilterPreset.swift
│   ├── CameraMode.swift
│   ├── CapturedPhoto.swift
│   └── CameraError.swift
├── Storage/
│   ├── PhotoLibrarySaver.swift
│   └── HapticsManager.swift
├── ViewModel/
│   └── CameraViewModel.swift
├── Views/
│   ├── CameraScreen.swift
│   ├── PreviewLayer.swift
│   ├── TopBar.swift
│   ├── ModeSelector.swift
│   ├── ShutterButton.swift
│   ├── BottomBar.swift
│   ├── FilterStrip.swift
│   ├── BeautyPanel.swift
│   ├── BeautySlider.swift
│   ├── FocusIndicator.swift
│   ├── PhotoPreviewSheet.swift
│   ├── PermissionView.swift
│   └── ToastView.swift
├── Theme/
│   ├── Theme.swift
│   └── SFIcons.swift
└── Resources/
    ├── Info.plist
    └── Assets.xcassets/
```
