# 01 · Align（需求对齐）

> 6A 工作流第一步：在动手前把"做什么 / 不做什么 / 做到什么程度"写清楚，避免实现阶段的来回返工。

## 1. 产品定位

打造一款 **专业级移动端相机应用**：
- UI 风格对标"美颜相机 / Beauty Cam / Meitu"，简洁、年轻、操作集中在底部一个拇指可达区。
- 同时具备"专业拍摄手感"——快门 0 延迟、参数可控、所见即所得（实时滤镜+美颜）。
- 离线可用，不依赖任何后端服务。

## 2. 平台与技术约束

| 项目 | 约束 |
| --- | --- |
| 最低系统 | iOS 17.0 |
| UI 框架 | SwiftUI（仅在 Camera 预览层使用 `UIViewRepresentable` 桥接 `MTKView`） |
| 并发模型 | Swift Concurrency（`async/await`、`actor`、`AsyncStream`、`Sendable`），全程 **不使用** `DispatchSemaphore` 跨线程阻塞 |
| 状态管理 | `@Observable`（iOS 17+），视图侧用 `@State` / `@Bindable` |
| 拍摄底层 | AVFoundation（`AVCaptureSession` + `AVCaptureVideoDataOutput` + `AVCapturePhotoOutput`） |
| 实时处理 | Core Image + Metal（`MTKView` 渲染） |
| 人脸 | Vision（`VNDetectFaceLandmarksRequest`） |
| 相册 | Photos（`PHPhotoLibrary`） |
| 工程化 | XcodeGen（`project.yml` 一键生成 `.xcodeproj`） |

## 3. 功能范围（MVP）

### 3.1 必做（In-Scope）

- **拍摄**
  - 拍照（前置 / 后置切换、闪光灯、延时 3s/5s/10s、九宫格、水平仪）
  - 点击对焦 / 长按锁定 AE/AF
  - 双指捏合变焦（包括广角/长焦切换，硬件支持时）
  - HEIF / JPEG 自动选择，写入相册
  - 快门动效 + 触感反馈
- **滤镜**
  - 内置 ≥ 12 个 LUT-style 滤镜（基于 `CIFilter` 链路实现，无需外部 LUT 资源）：
    `Original / Vivid / Natural / Mono / Cinema / Portra / Cool / Warm / Vintage / Faded / Pink / Tokyo`
  - 强度可调（0~100）
  - 横向滚动选择条，**所见即所得**（预览即最终成像）
- **美颜**
  - 磨皮（基于 `CIBilateralFilter`，按强度分级）
  - 美白（曲线 + 饱和度微调）
  - 锐化（`CIUnsharpMask`，避免过度噪点）
  - 大眼 / 瘦脸（基于 Vision 人脸关键点 + `CIBumpDistortion` 简化实现，强度可调）
  - 一键"自然/精致"预设
- **模式**
  - 拍照（首版重点）
  - 美颜（默认面板态）
  - 滤镜（默认面板态）
  - 录像入口预留（标记为 Coming Soon，不阻塞构建）
- **基础**
  - 相机权限请求与拒绝兜底页
  - 相册权限请求
  - 拍摄结果预览页（保存 / 重拍 / 分享）

### 3.2 不做（Out-of-Scope，避免范围蔓延）

- 视频录制 / 慢动作 / 延时摄影（仅预留入口）
- 云端 AI 滤镜 / 风格化（无网络依赖）
- 贴纸 / AR 道具 / 3D 妆容
- 多账号 / 登录 / 社交分享后端
- iPad 多任务 / 横屏适配（首版仅竖屏）
- iOS 26 Liquid Glass（最低支持 17，不引入 26-only API）

## 4. 非功能指标（必须量化）

| 维度 | 目标 | 测量方法 |
| --- | --- | --- |
| 冷启动到首帧 | **≤ 600 ms**（iPhone 13 及以上） | `os_signpost` 标记 `App.didFinishLaunching` → `Camera.firstFrame` |
| 快门按下到落盘 | **≤ 250 ms** | `os_signpost` `Shutter.pressed` → `Photo.saved` |
| 预览帧率 | 1080p · **30 fps 稳定**（开美颜+滤镜也不掉到 24 以下） | Instruments / 计数器 |
| 主线程阻塞 | 任意一帧 ≤ **8 ms** | Time Profiler |
| 内存峰值 | < **220 MB**（拍摄态） | Memory Graph |
| 崩溃率 | **0**（开发期 + 自测覆盖：权限拒绝、切换前后摄、连续狂点快门、相册满、低存储、被电话打断） | 手动用例清单 + `os_log` |
| 二进制体积 | < 8 MB（不含 Asset） | Build report |

## 5. 性能与稳定性原则（写进代码）

1. **零拷贝优先**：相机帧用 `CVPixelBuffer` → `CIImage`，渲染用同一 `CIContext + MTLDevice`，避免 `UIImage` 中转。
2. **快门优先级**：拍照走 `AVCapturePhotoOutput.capturePhoto(with:delegate:)`，与预览管线解耦；按下瞬间立即触发触感+动效，不等待落盘。
3. **背压**：`AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true`；处理管线串行 actor，丢帧不排队。
4. **线程隔离**：
   - `CameraService` 是 `actor`，所有 session 配置/启停只在它内部串行。
   - 渲染回调在专用 dispatch queue（不是 main），仅最终 `setNeedsDisplay()` 跳到 main。
5. **生命周期**：进入后台 `stopRunning()`，回前台再 `startRunning()`，Scene Phase 监听。
6. **失败兜底**：所有 throws 路径在 ViewModel 转成可展示的 `CameraError`，UI 层用统一 toast 呈现，绝不 `try!` / `fatalError` 在用户路径上。
7. **可观测**：关键节点全部 `os_signpost("camera", ...)`，方便 Instruments。

## 6. 验收标准（Done 的定义）

- [ ] 用 `xcodegen generate` 一键生成可在 Xcode 16+ 构建运行的工程
- [ ] iPhone 真机首启 → 同意权限 → 看到带滤镜/美颜的实时预览，整段流畅无卡顿
- [ ] 切换滤镜、调整美颜滑杆即时生效
- [ ] 拍照后照片正确写入相册，色彩与预览一致
- [ ] 拒绝权限路径有清晰引导，可跳"设置"
- [ ] 后台切回正常恢复
- [ ] 连续 10 次极速点击快门不崩溃、不卡顿
- [ ] `docs/06-Assess.md` 自检清单全部通过

## 7. 关键风险与对策

| 风险 | 对策 |
| --- | --- |
| 美颜算法在低端机掉帧 | 美颜采用"分辨率降采样 → 处理 → 上采样"两段式；强度=0 时整段管线短路 |
| 实时变形（瘦脸/大眼）在快速移动时抖动 | Vision 检测限频 15 Hz，关键点做指数滑动平均 |
| `MTKView` 与 SwiftUI 生命周期冲突 | 用 `UIViewRepresentable` 严格管理，`makeUIView` 只创建一次，`updateUIView` 不动昂贵对象 |
| 相机切换瞬间黑屏 | 切换期间冻结上一帧到一张静态贴图，切换完成淡出 |
| 第三方依赖膨胀 | **0 第三方依赖**，全部使用系统框架 |
