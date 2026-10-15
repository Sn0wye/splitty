import SwiftUI
import UIKit

struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (AvatarCrop) -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var imageOffset = CGSize.zero
    @State private var settledImageOffset = CGSize.zero
    @State private var currentCropSide: CGFloat = 0

    private let maximumZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let cropSide = max(0, min(proxy.size.width, proxy.size.height) - 32)
                    let cropRect = CGRect(
                        x: (proxy.size.width - cropSide) / 2,
                        y: (proxy.size.height - cropSide) / 2,
                        width: cropSide,
                        height: cropSide
                    )
                    let imageSize = displayedImageSize(for: cropSide, zoom: zoom)

                    ZStack {
                        Color.black

                        Image(uiImage: image)
                            .resizable()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .position(
                                x: proxy.size.width / 2 + imageOffset.width,
                                y: proxy.size.height / 2 + imageOffset.height
                            )

                        selectionOverlay(in: proxy.size, cropRect: cropRect)

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: cropSide, height: cropSide)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .gesture(imageGesture(cropSide: cropSide))
                    }
                    .clipped()
                    .onAppear { updateCropSide(to: cropSide) }
                    .onChange(of: cropSide) { _, newSide in
                        updateCropSide(to: newSide)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Profile.cropTitle)
                    .accessibilityAdjustableAction { direction in
                        adjustZoom(direction == .increment ? 1.1 : 0.9, cropSide: cropSide)
                    }
                }

                Button {
                    resetImagePosition()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color("foreground"))
                        .frame(width: 44, height: 44)
                        .background(Color("card"), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Profile.startOver)
            }
            .padding(.bottom)
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

    private func selectionOverlay(in canvasSize: CGSize, cropRect: CGRect) -> some View {
        ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRect(cropRect)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(.white, lineWidth: 2)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1)
                .frame(width: max(0, cropRect.width - 8), height: max(0, cropRect.height - 8))
                .position(x: cropRect.midX, y: cropRect.midY)
        }
        .allowsHitTesting(false)
    }

    private func imageGesture(cropSide: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .simultaneously(with: MagnifyGesture())
            .onChanged { value in
                let translation = value.first?.translation ?? .zero
                let rawZoom = settledZoom * (value.second?.magnification ?? 1)
                let displayedZoom = AvatarCropMotion.rubberBand(
                    rawZoom,
                    in: 1...maximumZoom,
                    dimension: maximumZoom / 2
                )
                let rawOffset = offset(
                    zoomingTo: displayedZoom,
                    anchor: value.second.map { anchorPoint($0.startAnchor, cropSide: cropSide) },
                    translation: translation
                )

                zoom = displayedZoom
                imageOffset = rubberBanded(rawOffset, cropSide: cropSide, zoom: displayedZoom)
            }
            .onEnded { value in
                let translation = value.first?.translation ?? .zero
                let velocity = value.first?.velocity ?? .zero
                let rawZoom = settledZoom * (value.second?.magnification ?? 1)
                let displayedZoom = AvatarCropMotion.rubberBand(
                    rawZoom,
                    in: 1...maximumZoom,
                    dimension: maximumZoom / 2
                )
                let targetZoom = min(max(displayedZoom, 1), maximumZoom)
                let anchor = value.second.map { anchorPoint($0.startAnchor, cropSide: cropSide) }
                let projected = offset(
                    zoomingTo: targetZoom,
                    anchor: anchor,
                    translation: CGSize(
                        width: translation.width + AvatarCropMotion.projectedDistance(velocity.width),
                        height: translation.height + AvatarCropMotion.projectedDistance(velocity.height)
                    )
                )
                let targetOffset = constrained(projected, cropSide: cropSide, zoom: targetZoom)

                settledZoom = targetZoom
                settledImageOffset = targetOffset
                withAnimation(.spring(response: 0.4, dampingFraction: 1)) {
                    zoom = targetZoom
                    imageOffset = targetOffset
                }
            }
    }

    /// The pinch's start point relative to the crop square's centre, in points.
    private func anchorPoint(_ anchor: UnitPoint, cropSide: CGFloat) -> CGPoint {
        CGPoint(x: (anchor.x - 0.5) * cropSide, y: (anchor.y - 0.5) * cropSide)
    }

    /// The image offset after zooming from `settledZoom` to `newZoom` about `anchor`, so the
    /// point first under the fingers stays under them, and then moving by `translation`.
    private func offset(zoomingTo newZoom: CGFloat, anchor: CGPoint?, translation: CGSize) -> CGSize {
        let anchor = anchor ?? .zero
        let scale = settledZoom > 0 ? newZoom / settledZoom : 1
        return CGSize(
            width: anchor.x + translation.width - (anchor.x - settledImageOffset.width) * scale,
            height: anchor.y + translation.height - (anchor.y - settledImageOffset.height) * scale
        )
    }

    private var crop: AvatarCrop {
        guard currentCropSide > 0 else { return .fullImage }

        let imageSize = displayedImageSize(for: currentCropSide, zoom: zoom)
        guard imageSize.width > 0, imageSize.height > 0 else { return .fullImage }

        let width = currentCropSide / imageSize.width
        let height = currentCropSide / imageSize.height
        return AvatarCrop(normalizedRect: CGRect(
            x: 0.5 - imageOffset.width / imageSize.width - width / 2,
            y: 0.5 - imageOffset.height / imageSize.height - height / 2,
            width: width,
            height: height
        ))
    }

    private func displayedImageSize(for cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0, cropSide > 0 else { return .zero }

        let fillScale = max(cropSide / image.size.width, cropSide / image.size.height)
        return CGSize(
            width: image.size.width * fillScale * zoom,
            height: image.size.height * fillScale * zoom
        )
    }

    private func constrained(_ proposed: CGSize, cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        let imageSize = displayedImageSize(for: cropSide, zoom: zoom)
        let maximumX = max(0, (imageSize.width - cropSide) / 2)
        let maximumY = max(0, (imageSize.height - cropSide) / 2)
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func rubberBanded(_ proposed: CGSize, cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        let imageSize = displayedImageSize(for: cropSide, zoom: zoom)
        let maximumX = max(0, (imageSize.width - cropSide) / 2)
        let maximumY = max(0, (imageSize.height - cropSide) / 2)
        return CGSize(
            width: AvatarCropMotion.rubberBand(proposed.width, in: -maximumX...maximumX, dimension: cropSide),
            height: AvatarCropMotion.rubberBand(proposed.height, in: -maximumY...maximumY, dimension: cropSide)
        )
    }

    private func updateCropSide(to newSide: CGFloat) {
        guard newSide > 0 else { return }

        if currentCropSide > 0 {
            let scale = newSide / currentCropSide
            let scaledOffset = CGSize(
                width: imageOffset.width * scale,
                height: imageOffset.height * scale
            )
            imageOffset = constrained(scaledOffset, cropSide: newSide, zoom: zoom)
            settledImageOffset = imageOffset
        }

        currentCropSide = newSide
    }

    private func adjustZoom(_ scale: CGFloat, cropSide: CGFloat) {
        zoom = min(max(zoom * scale, 1), maximumZoom)
        imageOffset = constrained(imageOffset, cropSide: cropSide, zoom: zoom)
        settledZoom = zoom
        settledImageOffset = imageOffset
    }

    private func resetImagePosition() {
        zoom = 1
        settledZoom = 1
        imageOffset = .zero
        settledImageOffset = .zero
    }
}

/// The crop screen's gesture physics, matching the feel of Photos and scroll views.
enum AvatarCropMotion {
    /// UIScrollView's normal deceleration rate.
    static let decelerationRate: CGFloat = 0.998

    /// Resists a value pulled past `bounds`: the overshoot grows ever more slowly and
    /// never passes `dimension`.
    static func rubberBand(_ value: CGFloat, in bounds: ClosedRange<CGFloat>, dimension: CGFloat) -> CGFloat {
        if value < bounds.lowerBound {
            return bounds.lowerBound - resisted(bounds.lowerBound - value, dimension: dimension)
        }
        if value > bounds.upperBound {
            return bounds.upperBound + resisted(value - bounds.upperBound, dimension: dimension)
        }
        return value
    }

    /// How far a flick at `velocity` points per second would carry before stopping.
    static func projectedDistance(_ velocity: CGFloat) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    private static func resisted(_ overshoot: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return overshoot * dimension * 0.55 / (dimension + 0.55 * overshoot)
    }
}
