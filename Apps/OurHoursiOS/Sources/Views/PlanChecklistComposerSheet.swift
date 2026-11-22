import OurHoursCore
import SwiftUI
import UIKit

enum PlanChecklistComposerTarget {
    case persisted(planID: UUID)
    case draft(Binding<[PairPlanChecklistItem]>)
}

/// Dedicated rapid-entry sheet modeled after lifelog's shopping composer so items can be added continuously without closing the keyboard.
struct PlanChecklistComposerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let planTitle: String
    let target: PlanChecklistComposerTarget
    let initialKind: PairPlanChecklistKind

    @State private var selectedKind: PairPlanChecklistKind
    @State private var draftText = ""
    @State private var focusRequest = 0
    @State private var sessionAddedIDs: Set<UUID> = []
    @State private var lastAddedID: UUID?

    init(
        planTitle: String,
        target: PlanChecklistComposerTarget,
        initialKind: PairPlanChecklistKind = .todo
    ) {
        self.planTitle = planTitle
        self.target = target
        self.initialKind = initialKind
        _selectedKind = State(initialValue: initialKind)
    }

    private var currentItems: [PairPlanChecklistItem] {
        switch target {
        case let .persisted(planID):
            model.planEvent(id: planID)?.checklist ?? []
        case let .draft(binding):
            binding.wrappedValue
        }
    }

    private var canAdd: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let items = currentItems
        let todos = items.filter { $0.kind == .todo }
        let packings = items.filter { $0.kind == .packing }

        NavigationStack {
            ZStack {
                FoamTheme.sky(together: model.isTogetherNow)
                    .ignoresSafeArea()
                FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionCard(kind: .todo, items: todos)
                            sectionCard(kind: .packing, items: packings)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.never)
                    .onChange(of: lastAddedID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle(planTitle.isEmpty ? "やりたいこと・持ち物" : planTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerBar
            }
        }
        .preferredColorScheme(.light)
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
    }

    @ViewBuilder
    private func sectionCard(kind: PairPlanChecklistKind, items: [PairPlanChecklistItem]) -> some View {
        let tint: Color = kind == .todo ? FoamTheme.warmAccent : Color(red: 0.24, green: 0.56, blue: 0.92)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text(kind == .todo ? "やりたいこと" : "持ち物リスト")
                    .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                    .foregroundStyle(FoamTheme.ink)
                Spacer()
                Text("\(items.count)件")
                    .font(FoamFont.bold(11.5, relativeTo: .caption2))
                    .foregroundStyle(FoamTheme.ink.opacity(0.56))
            }

            if items.isEmpty {
                Text(kind == .todo ? "まだやりたいことがありません" : "まだ持ち物がありません")
                    .font(FoamFont.regular(13, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.48))
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                toggleItem(item)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(item.isDone ? tint : FoamTheme.ink.opacity(0.32))
                                    Text(item.title)
                                        .font(FoamFont.medium(14.5, relativeTo: .subheadline))
                                        .foregroundStyle(item.isDone ? FoamTheme.ink.opacity(0.46) : FoamTheme.ink)
                                        .strikethrough(item.isDone)
                                        .multilineTextAlignment(.leading)
                                    if sessionAddedIDs.contains(item.id) {
                                        Text("追加")
                                            .font(.system(size: 9.5, weight: .heavy))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(tint, in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                removeItem(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.32))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("削除")
                        }
                        .id(item.id)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            SoapBubbleSurface(
                cornerStyle: .roundedRect(22),
                prominence: .standard,
                isTogether: model.isTogetherNow,
                seed: kind == .todo ? 3.2 : 6.4,
                wobbleScale: 0.25,
                animated: false,
                milkyFillOpacity: 0.80
            )
        }
    }

    private var composerBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(PairPlanChecklistKind.allCases) { kind in
                    let isSelected = selectedKind == kind
                    let activeTint: Color = kind == .todo
                        ? FoamTheme.warmAccent
                        : Color(red: 0.24, green: 0.56, blue: 0.92)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedKind = kind
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isSelected ? "checkmark" : kind.symbolName)
                                .font(.system(size: 11, weight: .bold))
                            Text(kind.displayName)
                                .font(FoamFont.bold(12.5, relativeTo: .caption))
                        }
                        .foregroundStyle(isSelected ? .white : FoamTheme.ink.opacity(0.80))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(isSelected ? activeTint : Color.white.opacity(0.88))
                                .overlay {
                                    if !isSelected {
                                        Capsule().strokeBorder(Color.white, lineWidth: 1)
                                    }
                                }
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 8) {
                PlanRapidEntryField(
                    text: $draftText,
                    placeholder: selectedKind == .todo ? "やりたいことを入力…" : "持ち物を入力…",
                    isEnabled: true,
                    autoFocusOnAppear: true,
                    focusRequest: focusRequest,
                    onSubmit: addDraft
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.95), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white, lineWidth: 1)
                }

                Button(action: addDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            canAdd
                                ? (selectedKind == .todo ? FoamTheme.warmAccent : Color(red: 0.24, green: 0.56, blue: 0.92))
                                : FoamTheme.ink.opacity(0.28),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .accessibilityLabel("追加")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func addDraft() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            focusRequest += 1
            return
        }
        let addedID: UUID?
        switch target {
        case let .persisted(planID):
            addedID = model.appendPlanChecklistItem(planID: planID, title: trimmed, kind: selectedKind)?.id
        case let .draft(binding):
            let newItem = PairPlanChecklistItem(title: trimmed, isDone: false, kind: selectedKind)
            binding.wrappedValue.append(newItem)
            addedID = newItem.id
        }
        if let addedID {
            draftText = ""
            sessionAddedIDs.insert(addedID)
            lastAddedID = addedID
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        focusRequest += 1
    }

    private func toggleItem(_ item: PairPlanChecklistItem) {
        switch target {
        case let .persisted(planID):
            model.togglePlanChecklistItem(planID: planID, itemID: item.id)
        case let .draft(binding):
            if let idx = binding.wrappedValue.firstIndex(where: { $0.id == item.id }) {
                binding.wrappedValue[idx].isDone.toggle()
            }
        }
    }

    private func removeItem(_ item: PairPlanChecklistItem) {
        switch target {
        case let .persisted(planID):
            model.removePlanChecklistItem(planID: planID, itemID: item.id)
        case let .draft(binding):
            binding.wrappedValue.removeAll { $0.id == item.id }
        }
        sessionAddedIDs.remove(item.id)
    }
}
