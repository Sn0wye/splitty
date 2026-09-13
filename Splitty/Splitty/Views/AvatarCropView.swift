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
            .simultaneously(with: MagnificationGesture())
            .onChanged { value in
                let translation = value.first?.translation ?? .zero
                let magnification = value.second ?? 1
                let proposedZoom = min(max(settledZoom * magnification, 1), maximumZoom)
                let proposedOffset = CGSize(
                    width: settledImageOffset.width + translation.width,
                    height: settledImageOffset.height + translation.height
                )

                zoom = proposedZoom
                imageOffset = constrained(proposedOffset, cropSide: cropSide, zoom: proposedZoom)
            }
            .onEnded { _ in
                settledZoom = zoom
                settledImageOffset = imageOffset
            }
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
