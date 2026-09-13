import SwiftUI
import UIKit

struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (AvatarCrop) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var currentCanvasSide: CGFloat = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    cropCanvas(side: side)
                        .frame(width: side, height: side)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .onAppear { currentCanvasSide = side }
                        .onChange(of: side) { _, newSide in
                            currentCanvasSide = newSide
                            constrainOffset()
                        }
                }
                .aspectRatio(1, contentMode: .fit)

                VStack(spacing: 10) {
                    Label(L10n.Profile.zoom, systemImage: "plus.magnifyingglass")
                        .font(.subheadline)
                        .foregroundStyle(Color("muted-foreground"))
                    Slider(value: $zoom, in: 1...4)
                        .onChange(of: zoom) { _, _ in constrainOffset() }
                }
                .padding(.horizontal)

                Text(L10n.Profile.cropInstructions)
                    .font(.footnote)
                    .foregroundStyle(Color("muted-foreground"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color("background").ignoresSafeArea())
            .navigationTitle(L10n.Profile.cropTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Profile.choose) { onCrop(crop) }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func cropCanvas(side: CGFloat) -> some View {
        let baseSize = aspectFillSize(in: side)
        return Image(uiImage: image)
            .resizable()
            .frame(width: baseSize.width, height: baseSize.height)
            .scaleEffect(zoom)
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = constrained(
                            CGSize(
                                width: settledOffset.width + value.translation.width,
                                height: settledOffset.height + value.translation.height
                            ),
                            side: side
                        )
                    }
                    .onEnded { _ in settledOffset = offset }
            )
            .frame(width: side, height: side)
            .clipped()
            .overlay {
                Rectangle()
                    .stroke(.white, lineWidth: 2)
                    .allowsHitTesting(false)
            }
    }

    private var crop: AvatarCrop {
        let side: CGFloat = 1
        let baseSize = aspectFillSize(in: side)
        let scaledWidth = baseSize.width * zoom
        let scaledHeight = baseSize.height * zoom
        let normalizedOffset = CGSize(
            width: offset.width / max(currentCanvasSide, 1),
            height: offset.height / max(currentCanvasSide, 1)
        )
        let width = side / scaledWidth
        let height = side / scaledHeight
        return AvatarCrop(normalizedRect: CGRect(
            x: 0.5 - normalizedOffset.width / scaledWidth - width / 2,
            y: 0.5 - normalizedOffset.height / scaledHeight - height / 2,
            width: width,
            height: height
        ))
    }

    private func aspectFillSize(in side: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: side, height: side)
        }
        let scale = max(side / image.size.width, side / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func constrained(_ proposed: CGSize, side: CGFloat) -> CGSize {
        let baseSize = aspectFillSize(in: side)
        let maxX = max(0, (baseSize.width * zoom - side) / 2)
        let maxY = max(0, (baseSize.height * zoom - side) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func constrainOffset() {
        offset = constrained(offset, side: currentCanvasSide)
        settledOffset = offset
    }
}
