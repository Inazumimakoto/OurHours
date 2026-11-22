import OurHoursCore
import SwiftUI
import UIKit

struct UserAvatarView: View {
    let image: UIImage?
    let bubbleColor: BubbleColorTheme
    let size: CGFloat
    var fallbackInitial: String? = nil

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(bubbleColor.swatchGradient)
                    .frame(width: size, height: size)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: max(3.5, size * 0.16), height: max(3.5, size * 0.16))
                            .offset(x: size * 0.20, y: size * 0.18)
                    }
                    .overlay {
                        if let fallbackInitial, !fallbackInitial.isEmpty {
                            Text(fallbackInitial)
                                .font(FoamFont.bold(max(10, size * 0.44)))
                                .foregroundStyle(FoamTheme.ink.opacity(0.82))
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: max(10, size * 0.42), weight: .semibold))
                                .foregroundStyle(FoamTheme.ink.opacity(0.55))
                        }
                    }
            }
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.92), lineWidth: max(1.2, size * 0.055))
        }
        .shadow(color: FoamTheme.ink.opacity(0.10), radius: max(1.5, size * 0.08), y: 1)
        .accessibilityHidden(true)
    }
}
