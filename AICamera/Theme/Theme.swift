import SwiftUI

/// 集中管理颜色 / 字体 / 圆角 / 间距，避免硬编码散落各处。
enum Theme {
    enum Color {
        static let background      = SwiftUI.Color(red: 0.04, green: 0.04, blue: 0.05)
        static let surface         = SwiftUI.Color.black.opacity(0.55)
        static let surfaceStrong   = SwiftUI.Color.black.opacity(0.78)
        static let primary         = SwiftUI.Color(red: 1.0,  green: 0.302, blue: 0.427) // #FF4D6D
        static let primaryMuted    = SwiftUI.Color(red: 1.0,  green: 0.302, blue: 0.427).opacity(0.18)
        static let onSurface       = SwiftUI.Color.white.opacity(0.92)
        static let onSurfaceMuted  = SwiftUI.Color.white.opacity(0.55)
        static let separator       = SwiftUI.Color.white.opacity(0.10)
    }

    enum Radius {
        static let card: CGFloat   = 22
        static let chip: CGFloat   = 18
        static let pill: CGFloat   = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Font {
        static let label      = SwiftUI.Font.system(.footnote, design: .rounded, weight: .semibold)
        static let chip       = SwiftUI.Font.system(.subheadline, design: .rounded, weight: .semibold)
        static let title      = SwiftUI.Font.system(.title3, design: .rounded, weight: .bold)
        static let captionTab = SwiftUI.Font.system(size: 13, weight: .semibold, design: .rounded)
    }

    enum Animation {
        static let snappy: SwiftUI.Animation = .interpolatingSpring(stiffness: 380, damping: 28)
        static let press: SwiftUI.Animation  = .interpolatingSpring(stiffness: 600, damping: 22)
        static let fade: SwiftUI.Animation   = .easeOut(duration: 0.18)
    }
}
