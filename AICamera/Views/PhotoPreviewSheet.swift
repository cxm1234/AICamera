import SwiftUI

struct PhotoPreviewSheet: View {
    let photo: CapturedPhoto
    let onClose: () -> Void
    @State private var showShare = false

    var body: some View {
        ZStack {
            Theme.Color.background.ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: SFIcons.close)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Color.onSurface)
                            .frame(width: 40, height: 40)
                            .background(Theme.Color.surfaceStrong, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("已保存到相册")
                        .font(Theme.Font.chip)
                        .foregroundStyle(Theme.Color.onSurfaceMuted)
                    Spacer()
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: SFIcons.share)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Color.onSurface)
                            .frame(width: 40, height: 40)
                            .background(Theme.Color.surfaceStrong, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)

                Image(uiImage: photo.thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.Spacing.l)

                Spacer()
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [photo.thumbnail])
                .presentationDetents([.medium, .large])
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
