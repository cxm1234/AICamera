# 03 · Atomize（任务原子化）

> 把架构落到一个个"小到无歧义、可独立产出"的原子任务。每个任务列出：输出文件 / 关键 API / 验收点。

## T01 · 工程脚手架
- 输出：`project.yml`、`AICamera/Resources/Info.plist`、`Assets.xcassets/AppIcon.appiconset/Contents.json`、`README.md`
- 验收：`xcodegen generate && open AICamera.xcodeproj` 可打开；Bundle Id `com.aicamera.app`；最低 iOS 17.0；声明 `NSCameraUsageDescription` / `NSPhotoLibraryAddUsageDescription` / `NSMicrophoneUsageDescription`。

## T02 · 主题与图标
- 输出：`Theme/Theme.swift`、`Theme/SFIcons.swift`
- 验收：色板、字号、圆角、SF Symbols 名都集中可改。

## T03 · 模型层
- 输出：`Models/*.swift`（6 个文件）
- 验收：全部 `Sendable`；枚举提供 `displayName` 用于 UI。

## T04 · 共享 CIContext
- 输出：`Pipeline/CIContext+Shared.swift`
- 验收：单例 + Metal device 复用；提供 `render(_:to:)` helper。

## T05 · FilterEngine
- 输出：`Pipeline/FilterEngine.swift`
- 验收：12 个内置滤镜；`apply(image:preset:intensity:)` 纯函数；缓存最近一次 CIFilter；strength=0 不做事。

## T06 · BeautyEngine
- 输出：`Pipeline/BeautyEngine.swift`
- 验收：磨皮 / 美白 / 锐化 / 大眼 / 瘦脸；`enabled == false` 时立即 return；降采样路径。

## T07 · FaceDetector
- 输出：`Pipeline/FaceDetector.swift`
- 验收：限频 15 Hz；指数滑动平均；线程安全的 `latest` 读取。

## T08 · FrameProcessor
- 输出：`Pipeline/FrameProcessor.swift`、`Camera/VideoFrame.swift`
- 验收：串行队列；零拷贝；调用 FilterEngine + BeautyEngine；输出 `CIImage` 给 PreviewRenderer；同时 fork 低分辨率帧给 FaceDetector。

## T09 · 权限封装
- 输出：`Camera/CameraPermissions.swift`
- 验收：`requestCamera() async -> PermissionState`；`requestPhotoAdd() async -> PermissionState`；处理 4 种状态。

## T10 · CameraService
- 输出：`Camera/CameraService.swift`
- 验收：`actor`；`bootstrap()` 预热；`start()` / `stop()`；`switchCamera()`；`setFocus(point:)` / `setZoom(_:)`；`setFlash(_:)`；`capturePhoto() async throws -> CapturedPhoto`；通过 `AsyncStream<VideoFrame>` 输出预览帧。

## T11 · Metal 预览
- 输出：`Camera/CameraPreviewView.swift`、`Camera/PreviewRenderer.swift`
- 验收：`UIViewRepresentable` 包 `MTKView`；`PreviewRenderer` 是 `MTKViewDelegate`；正确处理屏幕方向与 aspect-fit。

## T12 · 存储与触感
- 输出：`Storage/PhotoLibrarySaver.swift`、`Storage/HapticsManager.swift`
- 验收：HEIF 优先，回退 JPEG；保存到自定义相册（"AI Camera"）；触感按场景分级。

## T13 · ViewModel
- 输出：`ViewModel/CameraViewModel.swift`
- 验收：`@Observable @MainActor`；编排上述 actor；暴露纯 UI 状态；`bind(to: CameraService)` 启动预览订阅；错误转 `CameraError`。

## T14 · UI 主屏
- 输出：`Views/CameraScreen.swift`、`Views/PreviewLayer.swift`、`Views/TopBar.swift`、`Views/BottomBar.swift`、`Views/ModeSelector.swift`、`Views/ShutterButton.swift`、`Views/FilterStrip.swift`、`Views/BeautyPanel.swift`、`Views/BeautySlider.swift`、`Views/FocusIndicator.swift`、`Views/PhotoPreviewSheet.swift`、`Views/PermissionView.swift`、`Views/ToastView.swift`
- 验收：全屏黑底；底部胶囊模式条；快门按压缩放 0.92；滑杆带触感；网格/水平仪可切换；权限拒绝显示引导卡。

## T15 · App 入口
- 输出：`App/AICameraApp.swift`、`App/AppRoot.swift`
- 验收：`@main`；ScenePhase 切换控制 session；锁竖屏。

## T16 · 自检
- 输出：`docs/06-Assess.md`
- 验收：每条手工自检用例 ✅ / ❌。

---

总计：约 35 个 Swift 源文件 + 项目配置 + 文档。**0 第三方依赖**。
