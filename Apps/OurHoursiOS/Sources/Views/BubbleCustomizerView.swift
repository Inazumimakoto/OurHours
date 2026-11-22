import OurHoursCore
import SwiftUI

struct BubbleCustomizerView: View {
    private enum TargetBubble: String, CaseIterable, Identifiable {
        case local
        case partner

        var id: String { rawValue }
    }

    var initialCategory: BubbleCustomizationCategory = .color

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var target: TargetBubble = .local
    @State private var selectedCategory: BubbleCustomizationCategory
    @State private var isExpressionRotationMode = false
    @State private var previewBounce = 0
    @State private var lockedHintMessage: String?

    init(initialCategory: BubbleCustomizationCategory = .color) {
        self.initialCategory = initialCategory
        _selectedCategory = State(initialValue: initialCategory)
    }

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private var isPaired: Bool {
        model.snapshot.isPaired
    }

    private var activeColor: BubbleColorTheme {
        if target == .partner, isPaired {
            return model.effectivePartnerBubbleColor ?? .sakuraPink
        }
        return model.localBubbleColor
    }

    private var activeExpression: BubbleExpression {
        if target == .partner, isPaired {
            return model.effectivePartnerBubbleExpression
        }
        return model.localBubbleExpression
    }

    private var activeExpressionRotation: [BubbleExpression] {
        if target == .partner, isPaired {
            return model.effectivePartnerBubbleExpressionRotation
        }
        return model.localBubbleExpressionRotation
    }

    private var activeDecorations: BubbleDecorationLoadout {
        if target == .partner, isPaired {
            return model.effectivePartnerBubbleDecorations
        }
        return model.localBubbleDecorations
    }

    private var partnerNameText: String {
        let name = model.displayPartnerName
        return name == "パートナー" ? "相手" : name
    }

    var body: some View {
        let progress = model.bubbleUnlockProgress()
        let totalRewards = BubbleUnlockCatalog.nonStarterItems.count
        let unlockedRewards = progress.unlockedNonStarterItems.count

        ZStack {
            FoamTheme.sky(together: model.isTogetherNow)
                .ignoresSafeArea()
            FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                headerBar
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                if isPaired {
                    targetPicker
                        .padding(.horizontal, 18)
                }

                previewStage(progress: progress, unlockedRewards: unlockedRewards, totalRewards: totalRewards)
                    .padding(.horizontal, 18)

                if let lockedHintMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(FoamTheme.warmAccent)
                        Text(lockedHintMessage)
                            .font(FoamFont.bold(12, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 18)
                    .transition(.opacity)
                }

                categoryStrip

                if selectedCategory == .expression {
                    expressionRotationControls
                        .padding(.horizontal, 18)
                } else if selectedCategory == .mole {
                    HStack(spacing: 5) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(FoamTheme.warmAccent)
                        Text("ほくろは複数まとめて付けられます（\(activeDecorations.moles.count)個選択中）")
                            .font(FoamFont.bold(11.5, relativeTo: .caption))
                            .foregroundStyle(FoamTheme.ink.opacity(0.78))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                }

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 10) {
                        ForEach(BubbleUnlockCatalog.items(in: selectedCategory)) { item in
                            itemCard(item: item, progress: progress)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
        }
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
        .preferredColorScheme(.light)
        .onAppear {
            isExpressionRotationMode = activeExpressionRotation.count >= 2
        }
        .onChange(of: target) { _, _ in
            isExpressionRotationMode = activeExpressionRotation.count >= 2
        }
        .onChange(of: selectedCategory) { _, _ in
            lockedHintMessage = nil
        }
        .onDisappear {
            model.markBubbleUnlocksSeen()
        }
    }

    private var headerBar: some View {
        ZStack {
            Text("シャボン玉きせかえ")
                .font(FoamFont.bold(20, relativeTo: .title3))
                .foregroundStyle(FoamTheme.ink)
            HStack {
                Spacer()
                FoamRoundIconButton(size: 40, accessibilityLabel: "閉じる") {
                    dismiss()
                } icon: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FoamTheme.ink.opacity(0.82))
                }
            }
        }
    }

    private var targetPicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                targetButton(title: "じぶん", value: .local)
                targetButton(title: "\(partnerNameText)（表示のみ）", value: .partner)
            }
            .padding(4)
            .background(Color.white.opacity(0.55), in: Capsule())

            if target == .partner {
                HStack(spacing: 8) {
                    Text("この端末の表示だけアレンジできます")
                        .font(FoamFont.regular(11.5, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.ink.opacity(0.68))
                    if !model.partnerDisplayOverride.isEmpty {
                        Button("相手の設定に戻す") {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            model.clearPartnerDisplayOverride()
                            isExpressionRotationMode = activeExpressionRotation.count >= 2
                        }
                        .font(FoamFont.bold(11.5, relativeTo: .caption))
                        .foregroundStyle(FoamTheme.warmAccent)
                    }
                }
            }
        }
    }

    private func targetButton(title: String, value: TargetBubble) -> some View {
        let active = target == value
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                target = value
                lockedHintMessage = nil
            }
        } label: {
            Text(title)
                .font(FoamFont.bold(12.5, relativeTo: .caption))
                .foregroundStyle(active ? .white : FoamTheme.ink.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(active ? FoamTheme.ink : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func previewStage(
        progress: BubbleUnlockProgress,
        unlockedRewards: Int,
        totalRewards: Int
    ) -> some View {
        VStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                if !reduceMotion {
                    previewBounce += 1
                }
            } label: {
                MascotBubbleAvatar(
                    color: activeColor,
                    expression: activeExpression,
                    expressionRotationPool: activeExpressionRotation,
                    isFastPreviewRotation: true,
                    decorations: activeDecorations,
                    size: 136,
                    animated: !reduceMotion,
                    isTogether: model.isTogetherNow
                )
                .keyframeAnimator(initialValue: CGFloat(1), trigger: previewBounce) { content, scale in
                    content.scaleEffect(x: 2 - scale, y: scale)
                } keyframes: { _ in
                    SpringKeyframe(0.86, duration: 0.12)
                    SpringKeyframe(1, duration: 0.42, spring: .bouncy)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("シャボン玉のプレビュー")

            HStack(spacing: 8) {
                progressChip(
                    icon: "clock.fill",
                    text: "累計 \(FoamTheme.duration(progress.cumulativeSeconds)) / 1,095時間"
                )
                progressChip(
                    icon: "calendar",
                    text: "\(progress.effectiveDays)日目 / 365日"
                )
                progressChip(
                    icon: "sparkles",
                    text: "解放 \(unlockedRewards)/\(totalRewards)"
                )
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(26),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: 3.7,
                wobbleScale: 0.35,
                animated: false
            )
        }
    }

    private func progressChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(FoamTheme.warmAccent)
            Text(text)
                .font(FoamFont.bold(11, relativeTo: .caption2))
                .foregroundStyle(FoamTheme.ink.opacity(0.84))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.72), in: Capsule())
    }

    private var expressionRotationControls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                        isExpressionRotationMode = false
                        setRotationPool([])
                    }
                } label: {
                    Text("1つに固定")
                        .font(FoamFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(!isExpressionRotationMode ? .white : FoamTheme.ink.opacity(0.78))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(!isExpressionRotationMode ? FoamTheme.ink : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                        isExpressionRotationMode = true
                        if activeExpressionRotation.isEmpty {
                            setRotationPool([activeExpression])
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("ランダムローテ")
                            .font(FoamFont.bold(12, relativeTo: .caption))
                    }
                    .foregroundStyle(isExpressionRotationMode ? .white : FoamTheme.ink.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isExpressionRotationMode ? FoamTheme.ink : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(Color.white.opacity(0.60), in: Capsule())

            if isExpressionRotationMode {
                let count = activeExpressionRotation.count
                let hint = count >= 2
                    ? "選んだ \(count) 個の表情がランダムな間隔で切り替わります"
                    : "あと \(max(1, 2 - count)) 個以上選ぶとローテーションが始まります"
                Text(hint)
                    .font(FoamFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(count >= 2 ? FoamTheme.warmAccent : FoamTheme.ink.opacity(0.70))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var categoryStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(BubbleCustomizationCategory.allCases) { category in
                        let selected = selectedCategory == category
                        let hasNew = categoryHasUnseenItems(category)
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: category.symbolName)
                                    .font(.system(size: 11, weight: .bold))
                                Text(category.displayName)
                                    .font(FoamFont.bold(12, relativeTo: .caption))
                                if hasNew {
                                    Circle()
                                        .fill(FoamTheme.warmAccent)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .foregroundStyle(selected ? .white : FoamTheme.ink.opacity(0.82))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(selected ? FoamTheme.ink : Color.white.opacity(0.86))
                                    .overlay {
                                        if !selected {
                                            Capsule().strokeBorder(Color.white, lineWidth: 1)
                                        }
                                    }
                            )
                        }
                        .buttonStyle(.plain)
                        .id(category)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(selectedCategory, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func itemCard(item: BubbleUnlockItem, progress: BubbleUnlockProgress) -> some View {
        let unlocked = progress.isUnlocked(item)
        let selected = isItemSelected(item)
        let isNew = unlocked && model.unseenUnlockedItemIDs.contains(item.id)
        let displayTitle = (!unlocked && item.requirement.isSecret) ? "？？？" : item.title

        Button {
            if unlocked {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                lockedHintMessage = nil
                applyItem(item)
            } else {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                let rem = progress.remainingText(for: item.requirement) ?? ""
                if item.requirement.isSecret || item.requirement.isEvent {
                    lockedHintMessage = rem
                } else {
                    lockedHintMessage = "「\(item.title)」は \(item.requirement.requirementLabel) で解放（\(rem)）"
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    miniPreview(for: item)
                        .opacity(unlocked ? 1.0 : 0.28)
                        .saturation(unlocked ? 1.0 : 0.35)

                    if !unlocked {
                        let lockSymbol = if item.requirement.isSecret {
                            "questionmark.circle.fill"
                        } else if item.requirement.isEvent {
                            "sparkles"
                        } else {
                            "lock.fill"
                        }
                        Image(systemName: lockSymbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(FoamTheme.ink.opacity(0.82))
                            .padding(6)
                            .background(Color.white.opacity(0.88), in: Circle())
                    }
                }
                .frame(height: 62)

                Text(displayTitle)
                    .font(FoamFont.bold(11.5, relativeTo: .caption))
                    .foregroundStyle(unlocked ? FoamTheme.ink : FoamTheme.ink.opacity(0.60))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if unlocked {
                    let activeStatusText: String = {
                        if selected {
                            if case .expression = item.payload, isExpressionRotationMode {
                                return "ローテ中"
                            }
                            return "着用中"
                        }
                        return item.requirement == .starter ? "きほん" : item.requirement.requirementLabel
                    }()
                    Text(activeStatusText)
                        .font(FoamFont.medium(10, relativeTo: .caption2))
                        .foregroundStyle(selected ? FoamTheme.warmAccent : FoamTheme.ink.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else if item.requirement.isEvent {
                    Text(item.requirement.requirementLabel)
                        .font(FoamFont.bold(9.5, relativeTo: .caption2))
                        .foregroundStyle(FoamTheme.warmAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                } else {
                    VStack(spacing: 3) {
                        Text(item.requirement.requirementLabel)
                            .font(FoamFont.bold(9.5, relativeTo: .caption2))
                            .foregroundStyle(FoamTheme.warmAccent)
                            .lineLimit(1)

                        GeometryReader { geo in
                            let fraction = progress.progressFraction(for: item.requirement)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(FoamTheme.ink.opacity(0.10))
                                Capsule()
                                    .fill(FoamTheme.warmAccent.opacity(0.82))
                                    .frame(width: max(0, geo.size.width * fraction))
                            }
                        }
                        .frame(height: 4)
                        .padding(.horizontal, 6)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.94) : Color.white.opacity(unlocked ? 0.72 : 0.45))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        selected ? FoamTheme.warmAccent : Color.white.opacity(unlocked ? 0.9 : 0.55),
                        lineWidth: selected ? 2.2 : 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isNew {
                    Text("NEW")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(FoamTheme.warmAccent, in: Capsule())
                        .padding(5)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FoamTheme.warmAccent, .white)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayTitle)\(selected ? "、選択中" : "")\(unlocked ? "" : "、ロック中")")
    }

    @ViewBuilder
    private func miniPreview(for item: BubbleUnlockItem) -> some View {
        switch item.payload {
        case let .color(color):
            MascotBubbleAvatar(
                color: color,
                expression: activeExpression == .classic ? .smile : activeExpression,
                decorations: .none,
                size: 50,
                animated: false
            )
        case let .expression(expr):
            MascotBubbleAvatar(
                color: activeColor,
                expression: expr,
                decorations: .none,
                size: 50,
                animated: false
            )
        case let .ears(ears):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(ears: ears),
                size: 46,
                animated: false
            )
        case let .headwear(headwear):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(headwear: headwear),
                size: 46,
                animated: false
            )
        case let .outfit(outfit):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(outfit: outfit),
                size: 46,
                animated: false
            )
        case let .eyebrows(brows):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(eyebrows: brows),
                size: 50,
                animated: false
            )
        case let .facialHair(hair):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(facialHair: hair),
                size: 50,
                animated: false
            )
        case let .eyewear(glasses):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(eyewear: glasses),
                size: 50,
                animated: false
            )
        case let .mole(mole):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(moles: mole == .none ? [] : [mole]),
                size: 50,
                animated: false
            )
        case let .makeup(makeup):
            MascotBubbleAvatar(
                color: activeColor,
                expression: .smile,
                decorations: BubbleDecorationLoadout(makeup: makeup),
                size: 50,
                animated: false
            )
        }
    }

    private func categoryHasUnseenItems(_ category: BubbleCustomizationCategory) -> Bool {
        guard !model.unseenUnlockedItemIDs.isEmpty else { return false }
        return BubbleUnlockCatalog.items(in: category).contains { model.unseenUnlockedItemIDs.contains($0.id) }
    }

    private func isItemSelected(_ item: BubbleUnlockItem) -> Bool {
        switch item.payload {
        case let .color(color):
            return activeColor == color
        case let .expression(expr):
            if isExpressionRotationMode {
                return activeExpressionRotation.contains(expr)
            }
            return activeExpression == expr
        case let .ears(ears):
            return activeDecorations.ears == ears
        case let .headwear(headwear):
            return activeDecorations.headwear == headwear
        case let .outfit(outfit):
            return activeDecorations.outfit == outfit
        case let .eyebrows(brows):
            return activeDecorations.eyebrows == brows
        case let .facialHair(hair):
            return activeDecorations.facialHair == hair
        case let .eyewear(glasses):
            return activeDecorations.eyewear == glasses
        case let .mole(mole):
            if mole == .none {
                return activeDecorations.moles.isEmpty
            }
            return activeDecorations.moles.contains(mole)
        case let .makeup(makeup):
            return activeDecorations.makeup == makeup
        }
    }

    private func setRotationPool(_ pool: [BubbleExpression]) {
        if target == .partner, isPaired {
            var override = model.partnerDisplayOverride
            override.expressionRotationPool = pool
            model.setPartnerDisplayOverride(override)
        } else {
            model.setLocalBubbleExpressionRotation(pool)
        }
    }

    private func applyItem(_ item: BubbleUnlockItem) {
        if case let .expression(expr) = item.payload {
            if isExpressionRotationMode {
                var pool = activeExpressionRotation
                if let idx = pool.firstIndex(of: expr) {
                    if pool.count > 1 {
                        pool.remove(at: idx)
                    }
                } else {
                    pool.append(expr)
                }
                setRotationPool(pool)
                return
            } else {
                setRotationPool([])
            }
        }

        if target == .partner, isPaired {
            var override = model.partnerDisplayOverride
            var decorations = override.decorations ?? model.effectivePartnerBubbleDecorations
            switch item.payload {
            case let .color(color):
                override.color = color
            case let .expression(expr):
                override.expression = expr
                override.expressionRotationPool = []
            case let .ears(ears):
                decorations.ears = ears
                override.decorations = decorations
            case let .headwear(headwear):
                decorations.headwear = headwear
                override.decorations = decorations
            case let .outfit(outfit):
                decorations.outfit = outfit
                override.decorations = decorations
            case let .eyebrows(brows):
                decorations.eyebrows = brows
                override.decorations = decorations
            case let .facialHair(hair):
                decorations.facialHair = hair
                override.decorations = decorations
            case let .eyewear(glasses):
                decorations.eyewear = glasses
                override.decorations = decorations
            case let .mole(mole):
                decorations.toggleMole(mole)
                override.decorations = decorations
            case let .makeup(makeup):
                decorations.makeup = makeup
                override.decorations = decorations
            }
            model.setPartnerDisplayOverride(override)
            return
        }

        var decorations = model.localBubbleDecorations
        switch item.payload {
        case let .color(color):
            model.setLocalBubbleColor(color)
        case let .expression(expr):
            model.setLocalBubbleExpression(expr)
        case let .ears(ears):
            decorations.ears = ears
            model.setLocalBubbleDecorations(decorations)
        case let .headwear(headwear):
            decorations.headwear = headwear
            model.setLocalBubbleDecorations(decorations)
        case let .outfit(outfit):
            decorations.outfit = outfit
            model.setLocalBubbleDecorations(decorations)
        case let .eyebrows(brows):
            decorations.eyebrows = brows
            model.setLocalBubbleDecorations(decorations)
        case let .facialHair(hair):
            decorations.facialHair = hair
            model.setLocalBubbleDecorations(decorations)
        case let .eyewear(glasses):
            decorations.eyewear = glasses
            model.setLocalBubbleDecorations(decorations)
        case let .mole(mole):
            decorations.toggleMole(mole)
            model.setLocalBubbleDecorations(decorations)
        case let .makeup(makeup):
            decorations.makeup = makeup
            model.setLocalBubbleDecorations(decorations)
        }
    }
}
