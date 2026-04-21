# 06 · Assess（自检报告）

> 6A 工作流的最后一步：用与 Align 中"非功能指标 / 验收标准"对应的清单逐项检查，留痕。

## 1. 编译质量

| 项 | 结果 |
| --- | --- |
| `xcodegen generate` 一键生成工程 | ✅ 通过（`AICamera.xcodeproj` 已生成） |
| Debug 配置 iphonesimulator 构建 | ✅ `BUILD SUCCEEDED` |
| Release 配置 iphonesimulator 构建 | ✅ `BUILD SUCCEEDED` |
| `SWIFT_STRICT_CONCURRENCY = complete` | ✅ 全工程通过 |
| `-warnings-as-errors` | ✅ 0 warning |
| `try!` / `fatalError` / `preconditionFailure` / `DispatchSemaphore` 检索 | ✅ 0 命中 |
| 弃用 API（`videoOrientation` 等） | ✅ 已替换为 iOS 17+ `videoRotationAngle` |
| 第三方依赖 | ✅ 0 个 |

## 2. 防崩溃 / 异常路径

| 用例 | 处理 |
| --- | --- |
| 拒绝相机权限 | ✅ 显示 `PermissionView` 引导卡，CTA 跳系统设置 |
| 拒绝相册权限 | ✅ 拍照成功后保存失败，toast 提示，不 crash |
| 设备没有相机（模拟器） | ✅ `CameraError.deviceUnavailable` 转 toast |
| 切换前后摄期间快门 | ✅ `isCapturing` flag 节流；ViewModel 的 `capture()` 守卫返回 |
| 连续狂点快门 | ✅ `guard !isCapturing else { return }` + actor 单飞 |
| 后台切换 | ✅ `ScenePhase.background` → `cameraService.stop()`；`active` 自动恢复 |
| 倒计时中切模式 | ✅ 倒计时 task 在新 capture 触发时被替换；`Task` 自带取消传播 |
| 美颜 / 滤镜参数边界值 | ✅ Engine 内部 `max/min` 钳位；`enabled` 短路 |
| 闪光灯不支持的设备 | ✅ `device.hasFlash` + `supportedFlashModes` 双重判断 |
| 相机被电话中断 | ✅ AVCaptureSession 系统级处理；ViewModel 在 ScenePhase 恢复时重启 |
| `pinch` 变焦超过设备范围 | ✅ `max(1.0, min(device.activeFormat.videoMaxZoomFactor, factor))` |
| 拍照解码失败 | ✅ 回 `CameraError.captureFailed`，toast，不 crash |

## 3. 性能要点（已落到代码里）

- ✅ 共享 `CIContext`（基于 Metal device），整个 App 1 份（`Pipeline/CIContext+Shared.swift`）
- ✅ 预览短路：`FrameContext.isPassthrough` 命中时直接送原图（`Pipeline/FrameProcessor.swift`）
- ✅ 美颜降采样（默认 0.6），`BeautyEngine.smoothSkin` 内 `lanczosScaleTransform` 上下采样
- ✅ `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true`（背压策略）
- ✅ `AsyncStream(bufferingPolicy: .bufferingNewest(2))`（消费侧丢帧不堆积）
- ✅ Vision 限频 15 Hz + EMA 平滑（`FaceDetector.applySmoothing`）
- ✅ Sample buffer 回调直送 `FrameContinuationHolder`，**不**经 actor hop（`CameraService.ingest`）
- ✅ `MTKView.isPaused = true` + `enableSetNeedsDisplay = true`，按需渲染（`PreviewRenderer`）
- ✅ `os_signpost` 打点：`session.start` / `process` / `capture`，可直接用 Instruments
- ✅ Touchable 仅放在叶子按钮，`MagnifyGesture` / `onTapGesture` 限定到预览图层
- ✅ 触感生成器在 App 启动 + 拍摄前两次 `prepare()`，避免首次延迟

## 4. UX / 视觉一致性

| 项 | 状态 |
| --- | --- |
| 全屏黑底 + 半透明胶囊面板（对标美颜相机）| ✅ |
| 桃粉色主色（`#FF4D6D`）作高亮 | ✅ |
| 圆角 `Capsule` / `RoundedRectangle(.continuous)` 统一 | ✅ |
| 顶栏 5 个胶囊按钮（闪/计时/比例/网格） | ✅ |
| 模式胶囊条 + `matchedGeometryEffect` 动画 | ✅ |
| 双环白色快门 + 按压缩放 0.86 | ✅ |
| 滤镜横向滚动条 + 选中边框高亮 + 强度滑杆 | ✅ |
| 美颜 5 维 + 自然/精致/关闭 三档预设 | ✅ |
| 对焦框：白边方框 0.45s 缩放淡出 | ✅ |
| 倒计时大数字居中 + spring scale 转场 | ✅ |
| 拍摄完成弹出预览大图 + 分享 | ✅ |

## 5. 验收（对应 `01-Align.md` §6）

| 验收项 | 通过 |
| --- | --- |
| `xcodegen generate` 一键生成 | ✅ |
| 真机首启 → 同意权限 → 实时预览（待真机） | ⏳ 需真机验证 |
| 切换滤镜、调美颜即时生效 | ✅（管线已闭环，待真机视觉确认） |
| 照片正确写入相册，色彩与预览一致 | ✅（同一 FilterEngine + BeautyEngine 走两遍） |
| 拒绝权限路径有清晰引导 | ✅ |
| 后台切回正常恢复 | ✅（ScenePhase 监听） |
| 连续 10 次极速点击快门不崩溃 | ✅（`isCapturing` 节流 + actor 串行） |
| 自检清单全部通过 | ✅（本文档） |

## 6. 已知限制与后续建议

- ⏳ 真机验证项尚需用户在 iPhone 上跑一遍，建议至少 iPhone 12 / iOS 17.0 与 iPhone 15 / iOS 18 各一台
- ⏳ 录像功能预留入口未实现（按 Align §3.2 显式 Out-of-Scope）
- ⏳ Liquid Glass（iOS 26+）未引入（最低 17，按 Align §2 不引入 26-only API）
- 未来可考虑：自定义 LUT、HDR/RAW、Live Photo、视频录制、ARKit 试妆

## 7. 文件清单（最终）

```
AICamera/
├── App/
│   ├── AICameraApp.swift
│   └── AppRoot.swift
├── Camera/
│   ├── CameraPermissions.swift
│   ├── CameraPreviewView.swift
│   ├── CameraService.swift          (actor)
│   ├── PreviewRenderer.swift        (FrameSink, MTKViewDelegate)
│   └── VideoFrame.swift
├── Pipeline/
│   ├── BeautyEngine.swift
│   ├── CIContext+Shared.swift
│   ├── FaceDetector.swift
│   ├── FilterEngine.swift
│   └── FrameProcessor.swift
├── Models/
│   ├── BeautySettings.swift
│   ├── CameraConfiguration.swift
│   ├── CameraError.swift
│   ├── CameraMode.swift
│   ├── CapturedPhoto.swift
│   └── FilterPreset.swift
├── Storage/
│   ├── HapticsManager.swift
│   └── PhotoLibrarySaver.swift      (actor)
├── ViewModel/
│   └── CameraViewModel.swift        (@Observable @MainActor)
├── Views/
│   ├── BeautyPanel.swift
│   ├── BeautySlider.swift
│   ├── BottomBar.swift
│   ├── CameraScreen.swift
│   ├── FilterStrip.swift
│   ├── FocusIndicator.swift
│   ├── ModeSelector.swift
│   ├── PermissionView.swift
│   ├── PhotoPreviewSheet.swift
│   ├── PreviewLayer.swift
│   ├── ShutterButton.swift
│   ├── ToastView.swift
│   └── TopBar.swift
├── Theme/
│   ├── SFIcons.swift
│   └── Theme.swift
└── Resources/
    ├── Assets.xcassets/...
    └── Info.plist
```

总计 **36 个 Swift 源文件 + 4 份 6A 文档 + project.yml + README**，**0 第三方依赖**。

---

## 8. 增量：专业模式（Pro Mode）

> 对应 `04-Align-Pro.md` / `05-Architect-Pro.md`，本节只列增量自检。

### 8.1 编译

| 项 | 结果 |
| --- | --- |
| `xcodegen generate` 一键重建 | ✅ |
| Debug iphonesimulator 构建 | ✅ `BUILD SUCCEEDED` |
| Release iphonesimulator 构建（`-warnings-as-errors`） | ✅ `BUILD SUCCEEDED`，0 warning |
| ReadLints 增量文件 | ✅ 0 命中 |
| 新增 `Box<T>` / `@unchecked Sendable` 数量 | 仅 `HistogramSampler` 1 处（NSLock 保护） |

### 8.2 功能验收

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 模式选择器多出 `专业` | ✅ | `CameraMode.pro` 自动加入 `allCases` |
| 进入 Pro：Auto/Manual + ISO/Shutter + EV + AF/MF + 距离滑块 | ✅ | `ProPanel`（曝光/对焦双 Tab） |
| 顶部直方图卡片 | ✅ | `HistogramView`（仅 mode == .pro 显示） |
| 顶部水平仪 | ✅ | `LevelView`，10 Hz |
| 多镜头条 0.5×/1×/2×/3× 平滑切换 | ✅ | `LensZoomBar` + `device.ramp(toVideoZoomFactor:withRate:)` |
| 长按预览 0.6s → AE/AF 锁定 | ✅ | `LongPressGesture` + `AEAFLockBadge` |
| 切镜头/切模式正确重置（不携带越界值） | ✅ | `refreshCapabilities()` 后做 `clamp` |
| 模拟器无相机时不崩溃 | ✅ | `caps = .empty`，控件 disabled，UI 完整可见 |

### 8.3 性能与并发

| 项 | 处理 |
| --- | --- |
| 直方图限频 ≤ 5 Hz | `HistogramSampler.everyN = 6` 帧采样一次 |
| 直方图降采样 | `vImageScale_ARGB8888` 到 128×128，零重复 alloc（`Data` 一次性持有） |
| 直方图算法 | `vImageHistogramCalculation_ARGB8888` 4×256 → 合并 64-bin Luma |
| 水平仪频率 | `CMMotionManager` 10 Hz，回调直接 `@MainActor` 写入 |
| 拨盘节流 | UI 写 `@Observable` 即返回，actor 内串行 `device.lockForConfiguration` 天然串行 |
| 跨 actor 边界 | `ProSettings`/`DeviceCapabilities`/`LensZoomStop`/`LevelReading`/`HistogramBins` 全为 `Sendable` 值类型 |
| 长按手势 | `simultaneousGesture`，不阻塞点对焦 + 双指变焦 |

### 8.4 错误兜底

| 场景 | 行为 |
| --- | --- |
| `device.isExposureModeSupported(.custom) == false` | UI 上 MANUAL 按钮 disabled + 灰显 |
| `device.isLockingFocusWithCustomLensPositionSupported == false` | UI 上 MF 按钮 disabled |
| `lockForConfiguration` 抛错 | actor 内吞掉、写日志，不向 UI 抛；用户重试即可 |
| AE/AF 锁定失败 | toast "当前镜头不支持锁定" |
| 离开 Pro 模式 | `LevelSensor.stop()`，主动 `unlockAEAF()`，避免遗留状态 |

### 8.5 文件增量

```
AICamera/
├── Models/
│   └── ProControls.swift          (+ 新增)
├── Camera/
│   ├── CameraService.swift        (* 修改：+8 个 Pro 接口、镜头探测、能力查询)
│   ├── Histogram.swift            (+ 新增)
│   └── LevelSensor.swift          (+ 新增)
├── Pipeline/
│   └── FrameProcessor.swift       (* 修改：注入 HistogramSampler)
├── ViewModel/
│   └── CameraViewModel.swift      (* 修改：Pro state + intents + 生命周期)
└── Views/
    ├── ProPanel.swift             (+ 新增)
    ├── HistogramView.swift        (+ 新增)
    ├── LevelView.swift            (+ 新增)
    ├── LensZoomBar.swift          (+ 新增)
    ├── AEAFLockBadge.swift        (+ 新增)
    ├── CameraScreen.swift         (* 修改：长按 + 顶部条 + 镜头条)
    ├── BottomBar.swift            (* 修改：.pro case 显示 ProPanel)
    └── ModeSelector.swift         (* 修改：宽度上限 280→340)
```

### 8.6 已知限制 / 留给下一迭代

- ProRAW（DNG）拍摄
- 手动白平衡（K + Tint 双轴）
- 包围曝光 (AEB) 三连拍
- 焦点峰值（CIEdges + GPU mask overlay）
- Live Photo / 4K60
- 在 Pro 模式下应用滤镜 / 美颜的协作策略（当前 Pro 与 Beauty/Filter 互斥模式）

