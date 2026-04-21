import SwiftUI

struct HistogramView: View {
    let bins: HistogramBins?

    var body: some View {
        Canvas { ctx, size in
            let data = bins ?? .empty
            let count = data.luma.count
            let maxBin = max(1, data.maxBin)
            let binWidth = size.width / CGFloat(count)
            for (i, value) in data.luma.enumerated() {
                let normalized = CGFloat(value) / CGFloat(maxBin)
                let h = normalized * size.height
                let rect = CGRect(
                    x: CGFloat(i) * binWidth,
                    y: size.height - h,
                    width: max(1, binWidth - 0.5),
                    height: max(0, h)
                )
                ctx.fill(Path(rect), with: .color(.white.opacity(0.78)))
            }
        }
        .frame(width: 88, height: 44)
        .padding(6)
        .background(Theme.Color.surfaceStrong, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.Color.separator, lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }
}
