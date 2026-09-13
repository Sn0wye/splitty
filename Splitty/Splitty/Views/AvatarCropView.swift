import SwiftUI
import UIKit

struct AvatarCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onCrop: (AvatarCrop) -> Void

    @State private var cropRect = CGRect.zero
    @State private var settledCropRect = CGRect.zero
    @State private var currentImageRect = CGRect.zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let imageRect = aspectFitRect(in: proxy.size)

                    ZStack {
                        Color.black

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .position(x: imageRect.midX, y: imageRect.midY)

                        selectionOverlay(in: imageRect)
                    }
                    .contentShape(Rectangle())
                    .gesture(selectionGesture(in: imageRect))
                    .onAppear { updateCanvas(to: imageRect) }
                    .onChange(of: imageRect) { _, newRect in
                        updateCanvas(to: newRect)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.Profile.cropInstructions)
                    .accessibilityAdjustableAction { direction in
                        resizeSelection(direction == .increment ? 1.1 : 0.9, in: imageRect)
                    }
                }

                Text(L10n.Profile.cropInstructions)
                    .font(.footnote)
                    .foregroundStyle(Color("muted-foreground"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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

    private func selectionOverlay(in imageRect: CGRect) -> some View {
        ZStack {
            Path { path in
                path.addRect(imageRect)
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

    private func selectionGesture(in imageRect: CGRect) -> some Gesture {
        DragGesture()
            .simultaneously(with: MagnificationGesture())
            .onChanged { value in
                let translation = value.first?.translation ?? .zero
                let scale = value.second ?? 1
                let side = settledCropRect.width * scale
                let proposed = CGRect(
                    x: settledCropRect.midX + translation.width - side / 2,
                    y: settledCropRect.midY + translation.height - side / 2,
                    width: side,
                    height: side
                )
                cropRect = constrained(proposed, to: imageRect)
            }
            .onEnded { _ in
                settledCropRect = cropRect
            }
    }

    private var crop: AvatarCrop {
        guard currentImageRect.width > 0, currentImageRect.height > 0 else {
            return .fullImage
        }
        return normalizedCrop(in: currentImageRect)
    }

    private func aspectFitRect(in canvasSize: CGSize) -> CGRect {
        guard image.size.width > 0, image.size.height > 0,
              canvasSize.width > 0, canvasSize.height > 0
        else { return .zero }

        let scale = min(canvasSize.width / image.size.width, canvasSize.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: (canvasSize.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func updateCanvas(to newImageRect: CGRect) {
        guard newImageRect.width > 0, newImageRect.height > 0 else { return }

        if currentImageRect.width > 0, currentImageRect.height > 0, cropRect.width > 0 {
            let normalized = normalizedCrop(in: currentImageRect).normalizedRect
            cropRect = constrained(
                CGRect(
                    x: newImageRect.minX + normalized.minX * newImageRect.width,
                    y: newImageRect.minY + normalized.minY * newImageRect.height,
                    width: normalized.width * newImageRect.width,
                    height: normalized.height * newImageRect.height
                ),
                to: newImageRect
            )
        } else {
            let side = min(newImageRect.width, newImageRect.height) * 0.8
            cropRect = CGRect(
                x: newImageRect.midX - side / 2,
                y: newImageRect.midY - side / 2,
                width: side,
                height: side
            )
        }

        currentImageRect = newImageRect
        settledCropRect = cropRect
    }

    private func normalizedCrop(in imageRect: CGRect) -> AvatarCrop {
        AvatarCrop(normalizedRect: CGRect(
            x: (cropRect.minX - imageRect.minX) / imageRect.width,
            y: (cropRect.minY - imageRect.minY) / imageRect.height,
            width: cropRect.width / imageRect.width,
            height: cropRect.height / imageRect.height
        ))
    }

    private func constrained(_ proposed: CGRect, to imageRect: CGRect) -> CGRect {
        let maximumSide = min(imageRect.width, imageRect.height)
        let minimumSide = min(96, maximumSide)
        let side = min(max(proposed.width, minimumSide), maximumSide)
        let centerX = min(max(proposed.midX, imageRect.minX + side / 2), imageRect.maxX - side / 2)
        let centerY = min(max(proposed.midY, imageRect.minY + side / 2), imageRect.maxY - side / 2)
        return CGRect(x: centerX - side / 2, y: centerY - side / 2, width: side, height: side)
    }

    private func resizeSelection(_ scale: CGFloat, in imageRect: CGRect) {
        let side = settledCropRect.width * scale
        cropRect = constrained(
            CGRect(
                x: settledCropRect.midX - side / 2,
                y: settledCropRect.midY - side / 2,
                width: side,
                height: side
            ),
            to: imageRect
        )
        settledCropRect = cropRect
    }
}
