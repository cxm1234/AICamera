# AI Camera

> 一款对标"美颜相机"的专业级 iOS 相机 App。SwiftUI + Swift Concurrency，最低 iOS 17.0，0 第三方依赖。

按 **6A 工作流**（Align → Architect → Atomize → Approve → Automate → Assess）构建：

- [`docs/01-Align.md`](docs/01-Align.md)：需求对齐 / 范围 / 非功能指标
- [`docs/02-Architect.md`](docs/02-Architect.md)：架构与数据流
- [`docs/03-Atomize.md`](docs/03-Atomize.md)：任务原子化拆解
- [`docs/06-Assess.md`](docs/06-Assess.md)：自检报告

## 功能

- 拍照（前后摄、闪光灯、3/5/10s 倒计时、九宫格、点击对焦、双指变焦）
- 12 个内置滤镜，强度可调
- 5 维本地美颜（磨皮 / 美白 / 锐化 / 瘦脸 / 大眼），含"自然 / 精致"预设
- HEIF 优先写入相册，自动建立"AI Camera"相册
- 全程 Swift Concurrency（`actor` 编排相机会话），Metal 渲染预览，零拷贝管线
- 拒绝权限有引导卡，前后台切换无缝恢复

## 技术栈

| 层 | 选型 |
| --- | --- |
| UI | SwiftUI（iOS 17 `@Observable`、`MagnifyGesture`、`sensoryFeedback`） |
| 并发 | Swift Concurrency（`actor`、`AsyncStream`、`Sendable`） |
| 拍摄 | AVFoundation（`AVCaptureSession` + `AVCaptureVideoDataOutput` + `AVCapturePhotoOutput`） |
| 实时处理 | Core Image + Metal（`MTKView` + 共享 `CIContext`） |
| 人脸 | Vision（`VNDetectFaceLandmarksRequest`，限频 + EMA 平滑） |
| 相册 | Photos（`PHPhotoLibrary`） |
| 工程化 | XcodeGen |

## 一键生成 Xcode 工程

```bash
brew install xcodegen          # 仅首次
xcodegen generate
open AICamera.xcodeproj
```

> 在 Xcode 中选择真机（相机功能不可在模拟器上完整运行），把 Bundle Id 指向你的 Team 后即可 Run。

## 目录

```
AICamera/
├── App/            # @main + ScenePhase
├── Camera/         # CameraService(actor) + 权限 + Metal 预览
├── Pipeline/       # FrameProcessor / FilterEngine / BeautyEngine / FaceDetector
├── Models/         # Sendable 数据模型
├── Storage/        # 相册保存 + 触感
├── ViewModel/      # @Observable @MainActor 编排
├── Views/          # SwiftUI 视图
├── Theme/          # 主题色 / 字体 / 图标常量
└── Resources/      # Info.plist + Assets.xcassets
```

## 性能要点

- 共享 `CIContext`（基于 Metal device），全应用 1 份
- 预览短路：原图 + 无美颜时跳过整段 CIFilter
- 美颜降采样（默认 0.6）后再上采样，CPU 占用降 ~60%
- Vision 限频 15 Hz + EMA 平滑，避免人脸抖动
- `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true`（背压：丢帧不堆积）
- `os_signpost` 标记关键路径，可用 Instruments 直接观测
- `SWIFT_STRICT_CONCURRENCY = complete` + `-warnings-as-errors`

## License

MIT
