import Foundation

/// 内置滤镜枚举，驱动 FilterEngine 内的 CIFilter 链路。
enum FilterKind: String, CaseIterable, Sendable {
    case original
    case vivid
    case natural
    case mono
    case cinema
    case portra
    case cool
    case warm
    case vintage
    case faded
    case pink
    case tokyo
}

struct FilterPreset: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let kind: FilterKind

    static let original = FilterPreset(id: "original", displayName: "原图", kind: .original)

    static let all: [FilterPreset] = [
        .original,
        .init(id: "vivid",   displayName: "鲜亮", kind: .vivid),
        .init(id: "natural", displayName: "自然", kind: .natural),
        .init(id: "mono",    displayName: "黑白", kind: .mono),
        .init(id: "cinema",  displayName: "电影", kind: .cinema),
        .init(id: "portra",  displayName: "胶片", kind: .portra),
        .init(id: "cool",    displayName: "冷调", kind: .cool),
        .init(id: "warm",    displayName: "暖调", kind: .warm),
        .init(id: "vintage", displayName: "复古", kind: .vintage),
        .init(id: "faded",   displayName: "褪色", kind: .faded),
        .init(id: "pink",    displayName: "粉调", kind: .pink),
        .init(id: "tokyo",   displayName: "东京", kind: .tokyo),
    ]
}
