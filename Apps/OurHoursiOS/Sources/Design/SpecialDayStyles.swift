import OurHoursCore
import SwiftUI

extension AnniversaryMarkStyle {
    var symbolName: String? {
        switch self {
        case .heart: "heart.fill"
        case .sparkles: "sparkles"
        case .infinity: "infinity"
        case .star: "star.fill"
        case .crown: "crown.fill"
        case .none: nil
        }
    }

    var tintColor: Color {
        switch self {
        case .heart: Color(red: 0.73, green: 0.36, blue: 0.53)
        case .sparkles: Color(red: 0.66, green: 0.45, blue: 0.23)
        case .infinity: Color(red: 0.52, green: 0.40, blue: 0.73)
        case .star: Color(red: 0.71, green: 0.48, blue: 0.23)
        case .crown: Color(red: 0.62, green: 0.40, blue: 0.27)
        case .none: FoamTheme.ink.opacity(0.60)
        }
    }
}

extension BirthdayMarkStyle {
    var symbolName: String? {
        switch self {
        case .cake: "birthday.cake.fill"
        case .balloon: "balloon.fill"
        case .gift: "gift.fill"
        case .popper: "party.popper.fill"
        case .crown: "crown.fill"
        case .none: nil
        }
    }

    var defaultTintColor: Color {
        switch self {
        case .cake: Color(red: 0.73, green: 0.36, blue: 0.53)
        case .balloon: Color(red: 0.39, green: 0.51, blue: 0.74)
        case .gift: Color(red: 0.52, green: 0.40, blue: 0.73)
        case .popper: Color(red: 0.73, green: 0.40, blue: 0.34)
        case .crown: Color(red: 0.62, green: 0.40, blue: 0.27)
        case .none: FoamTheme.ink.opacity(0.60)
        }
    }

    func tintColor(for bubbleColor: BubbleColorTheme?) -> Color {
        guard let bubbleColor, bubbleColor != .clear else { return defaultTintColor }
        return bubbleColor.symbolTintColor
    }
}

private extension BubbleColorTheme {
    var symbolTintColor: Color {
        switch self {
        case .clear: FoamTheme.ink
        case .skyBlue: Color(red: 0.24, green: 0.49, blue: 0.74)
        case .sakuraPink: Color(red: 0.74, green: 0.34, blue: 0.52)
        case .lavender: Color(red: 0.50, green: 0.38, blue: 0.73)
        case .mint: Color(red: 0.20, green: 0.54, blue: 0.43)
        case .honeyYellow: Color(red: 0.68, green: 0.45, blue: 0.14)
        case .coral: Color(red: 0.76, green: 0.33, blue: 0.28)
        }
    }
}

extension SeasonalDayKind {
    var symbolName: String {
        switch self {
        case .valentinesDay: "heart.circle.fill"
        case .whiteDay: "gift.fill"
        case .christmas: "tree.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .valentinesDay: Color(red: 0.71, green: 0.34, blue: 0.46)
        case .whiteDay: Color(red: 0.31, green: 0.52, blue: 0.72)
        case .christmas: Color(red: 0.28, green: 0.54, blue: 0.45)
        }
    }
}

struct ResolvedSpecialDayBadge: Identifiable, Equatable {
    let id: String
    let symbolName: String
    let tint: Color
    let title: String
}

enum SpecialDayBadgeResolver {
    static func badges(
        for events: [SpecialDayEvent],
        anniversaryStyle: AnniversaryMarkStyle,
        myBirthdayStyle: BirthdayMarkStyle,
        partnerBirthdayStyle: BirthdayMarkStyle,
        localBubbleColor: BubbleColorTheme,
        partnerBubbleColor: BubbleColorTheme?,
        partnerDisplayName: String
    ) -> [ResolvedSpecialDayBadge] {
        events.compactMap { event in
            let id = event.id
            switch event {
            case .anniversary(let years):
                guard let symbolName = anniversaryStyle.symbolName else { return nil }
                return ResolvedSpecialDayBadge(
                    id: id,
                    symbolName: symbolName,
                    tint: anniversaryStyle.tintColor,
                    title: years == 0 ? "付き合った日" : "記念日（\(years)周年）"
                )
            case .myBirthday:
                guard let symbolName = myBirthdayStyle.symbolName else { return nil }
                return ResolvedSpecialDayBadge(
                    id: id,
                    symbolName: symbolName,
                    tint: myBirthdayStyle.tintColor(for: localBubbleColor),
                    title: "自分の誕生日"
                )
            case .partnerBirthday:
                guard let symbolName = partnerBirthdayStyle.symbolName else { return nil }
                let name = partnerDisplayName.isEmpty || partnerDisplayName == "パートナー"
                    ? "相手" : partnerDisplayName
                return ResolvedSpecialDayBadge(
                    id: id,
                    symbolName: symbolName,
                    tint: partnerBirthdayStyle.tintColor(for: partnerBubbleColor),
                    title: "\(name)の誕生日"
                )
            case .seasonal(let kind):
                return ResolvedSpecialDayBadge(
                    id: id,
                    symbolName: kind.symbolName,
                    tint: kind.tintColor,
                    title: kind.displayName
                )
            }
        }
    }

    @MainActor
    static func badges(for events: [SpecialDayEvent], model: AppModel) -> [ResolvedSpecialDayBadge] {
        guard !events.isEmpty else { return [] }
        return badges(
            for: events,
            anniversaryStyle: model.anniversaryMarkStyle,
            myBirthdayStyle: model.myBirthdayMarkStyle,
            partnerBirthdayStyle: model.partnerBirthdayMarkStyle,
            localBubbleColor: model.localBubbleColor,
            partnerBubbleColor: model.partnerBubbleColor,
            partnerDisplayName: model.partnerNickname
        )
    }
}

struct SpecialDayPillsRow: View {
    let badges: [ResolvedSpecialDayBadge]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { pills }
                .fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 6) { pills }
        }
        .frame(maxWidth: .infinity)
    }

    private var pills: some View {
        ForEach(badges) { badge in
            Label {
                Text(badge.title)
                    .font(FoamFont.bold(13, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: badge.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(badge.tint)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.68), in: Capsule())
            .overlay { Capsule().strokeBorder(.white, lineWidth: 1) }
        }
    }
}
