import SwiftUI
import UIKit

struct AvatarCropEditorSheet: View {
    let sourceImage: UIImage
    let onConfirm: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var gestureMagnification: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragDelta: CGSize = .zero
    @State private var quarterTurns: Int = 0
    @State private var fineDegrees: Double = 0
    @State private var gestureAngle: Angle = .zero
    @State private var isInteracting = false
    @State private var activeCropDiameter: CGFloat = 280

    private var effectiveScale: CGFloat {
        min(5.0, max(1.0, scale * gestureMagnification))
    }

    private var effectiveAngle: Angle {
        .degrees(Double(quarterTurns) * 90.0 + fineDegrees) + gestureAngle
    }

    private var effectiveOffset: CGSize {
        CGSize(width: offset.width + dragDelta.width, height: offset.height + dragDelta.height)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color.black)
                    .zIndex(10)

                GeometryReader { geo in
                    let cropDiameter = min(max(220, min(geo.size.width - 48, geo.size.height - 20)), 300)
                    let fitted = fittedSize(for: cropDiameter)

                    ZStack {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .scaleEffect(effectiveScale)
                            .rotationEffect(effectiveAngle)
                            .offset(effectiveOffset)
                            .frame(width: cropDiameter, height: cropDiameter)

                        cropMaskOverlay(diameter: cropDiameter)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(combinedGesture)
                    .onChange(of: cropDiameter, initial: true) { _, newDiameter in
                        activeCropDiameter = newDiameter
                    }
                    .onDisappear {
                        isInteracting = false
                    }
                }
                .clipped()
                .zIndex(0)
                .layoutPriority(1)

                controlsPanel
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .background(Color.black)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button("キャンセル") {
                dismiss()
            }
            .font(FoamFont.medium(15, relativeTo: .body))
            .foregroundStyle(.white.opacity(0.85))
            .frame(minHeight: 44)

            Spacer()

            Text("アイコンを調整")
                .font(FoamFont.bold(17, relativeTo: .headline))
                .foregroundStyle(.white)

            Spacer()

            Button("決定") {
                confirmCrop()
            }
            .font(FoamFont.bold(15, relativeTo: .body))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white, in: Capsule())
        }
    }

    private func cropMaskOverlay(diameter: CGFloat) -> some View {
        ZStack {
            GeometryReader { geo in
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geo.size))
                    let circleRect = CGRect(
                        x: (geo.size.width - diameter) * 0.5,
                        y: (geo.size.height - diameter) * 0.5,
                        width: diameter,
                        height: diameter
                    )
                    path.addEllipse(in: circleRect)
                }
                .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
            }

            if isInteracting {
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 1, height: diameter)
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: diameter, height: 1)
                }
                .clipShape(Circle())
                .frame(width: diameter, height: diameter)
            }

            Circle()
                .strokeBorder(Color.white, lineWidth: 2.5)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.4), radius: 4)
        }
        .allowsHitTesting(false)
    }

    private var controlsPanel: some View {
        VStack(spacing: 14) {
            Text("丸い枠の中がアイコンになります")
                .font(FoamFont.medium(12.5, relativeTo: .caption))
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Slider(value: $scale, in: 1.0...4.0)
                    .tint(.white)
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        quarterTurns = (quarterTurns + 1) % 4
                    }
                } label: {
                    Label("90°回転", systemImage: "rotate.right")
                        .font(FoamFont.bold(13, relativeTo: .caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.16), in: Capsule())
                }

                Slider(value: $fineDegrees, in: -45...45)
                    .tint(.white.opacity(0.9))

                Button("リセット") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        scale = 1.0
                        offset = .zero
                        quarterTurns = 0
                        fineDegrees = 0
                    }
                }
                .font(FoamFont.bold(12.5, relativeTo: .caption))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
    }

    private var combinedGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                isInteracting = true
                dragDelta = value.translation
            }
            .onEnded { value in
                offset = CGSize(
                    width: offset.width + value.translation.width,
                    height: offset.height + value.translation.height
                )
                dragDelta = .zero
                isInteracting = false
            }

        let magnify = MagnifyGesture()
            .onChanged { value in
                isInteracting = true
                gestureMagnification = value.magnification
            }
            .onEnded { value in
                scale = min(5.0, max(1.0, scale * value.magnification))
                gestureMagnification = 1.0
                isInteracting = false
            }

        let rotate = RotateGesture()
            .onChanged { value in
                isInteracting = true
                gestureAngle = value.rotation
            }
            .onEnded { value in
                let total = Double(quarterTurns) * 90.0 + fineDegrees + value.rotation.degrees
                let snappedQuarters = Int((total / 90.0).rounded())
                quarterTurns = ((snappedQuarters % 4) + 4) % 4
                fineDegrees = max(-45, min(45, total - Double(snappedQuarters) * 90.0))
                gestureAngle = .zero
                isInteracting = false
            }

        return drag.simultaneously(with: magnify).simultaneously(with: rotate)
    }

    private func fittedSize(for diameter: CGFloat) -> CGSize {
        let w = max(1, sourceImage.size.width)
        let h = max(1, sourceImage.size.height)
        let baseScale = max(diameter / w, diameter / h)
        return CGSize(width: w * baseScale, height: h * baseScale)
    }

    private func confirmCrop() {
        let screenDiameter = max(220, activeCropDiameter)
        let fitted = fittedSize(for: screenDiameter)
        let outputSide: CGFloat = 320
        let outRatio = outputSide / screenDiameter

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
        let rendered = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: CGSize(width: outputSide, height: outputSide)))

            let tx = outputSide * 0.5 + effectiveOffset.width * outRatio
            let ty = outputSide * 0.5 + effectiveOffset.height * outRatio
            cg.translateBy(x: tx, y: ty)
            cg.rotate(by: effectiveAngle.radians)
            cg.scaleBy(x: effectiveScale, y: effectiveScale)

            let drawW = fitted.width * outRatio
            let drawH = fitted.height * outRatio
            sourceImage.draw(in: CGRect(x: -drawW * 0.5, y: -drawH * 0.5, width: drawW, height: drawH))
        }
        if let jpegData = rendered.jpegData(compressionQuality: 0.85) {
            onConfirm(jpegData)
        }
        dismiss()
    }
}
