import OurHoursCore
import SwiftUI

extension PairPlanIcon {
    var accentColor: Color {
        switch self {
        case .trip: Color(red: 0.25, green: 0.56, blue: 0.92)
        case .date: Color(red: 0.92, green: 0.36, blue: 0.56)
        case .gourmet: Color(red: 0.92, green: 0.52, blue: 0.24)
        case .outing: Color(red: 0.32, green: 0.72, blue: 0.54)
        case .event: Color(red: 0.58, green: 0.42, blue: 0.90)
        case .stay: Color(red: 0.36, green: 0.44, blue: 0.84)
        case .anniversary: Color(red: 0.86, green: 0.34, blue: 0.62)
        case .photo: Color(red: 0.28, green: 0.68, blue: 0.82)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .trip:
            [Color(red: 0.56, green: 0.82, blue: 1.00), Color(red: 0.34, green: 0.58, blue: 0.94)]
        case .date:
            [Color(red: 1.00, green: 0.72, blue: 0.84), Color(red: 0.92, green: 0.42, blue: 0.62)]
        case .gourmet:
            [Color(red: 1.00, green: 0.80, blue: 0.54), Color(red: 0.94, green: 0.54, blue: 0.30)]
        case .outing:
            [Color(red: 0.60, green: 0.92, blue: 0.78), Color(red: 0.28, green: 0.70, blue: 0.56)]
        case .event:
            [Color(red: 0.78, green: 0.68, blue: 1.00), Color(red: 0.54, green: 0.42, blue: 0.88)]
        case .stay:
            [Color(red: 0.66, green: 0.74, blue: 1.00), Color(red: 0.36, green: 0.44, blue: 0.84)]
        case .anniversary:
            [Color(red: 1.00, green: 0.76, blue: 0.88), Color(red: 0.86, green: 0.42, blue: 0.68)]
        case .photo:
            [Color(red: 0.62, green: 0.88, blue: 0.98), Color(red: 0.30, green: 0.66, blue: 0.82)]
        }
    }
}

struct PlanEditorRoute: Identifiable, Equatable {
    let id = UUID()
    let existingPlan: PairPlanEvent?
    let initialDate: Date
}

struct PlanEventEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let existingPlan: PairPlanEvent?
    let initialDate: Date
    var onSaved: ((PairPlanEvent) -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isMultiDay: Bool
    @State private var icon: PairPlanIcon
    @State private var memo: String
    @State private var checklist: [PairPlanChecklistItem]
    @State private var newItemKind: PairPlanChecklistKind = .todo
    @State private var newChecklistTitle = ""
    @State private var checklistFocusRequest = 0
    @State private var showRapidComposer = false
    @State private var showDeleteConfirm = false

    init(
        existingPlan: PairPlanEvent? = nil,
        initialDate: Date = .now,
        onSaved: ((PairPlanEvent) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.existingPlan = existingPlan
        self.initialDate = initialDate
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        let cal = CalendarDateValue.gregorianCurrent
        if let plan = existingPlan {
            _title = State(initialValue: plan.title)
            _startDate = State(initialValue: plan.startDate(calendar: cal))
            _endDate = State(initialValue: plan.endDate(calendar: cal))
            _isMultiDay = State(initialValue: !plan.isSingleDay)
            _icon = State(initialValue: plan.icon)
            _memo = State(initialValue: plan.memo ?? "")
            _checklist = State(initialValue: plan.checklist)
        } else {
            let dayMid = CalendarDateValue(date: initialDate, calendar: cal).toDate(calendar: cal)
            _title = State(initialValue: "")
            _startDate = State(initialValue: dayMid)
            _endDate = State(initialValue: dayMid)
            _isMultiDay = State(initialValue: false)
            _icon = State(initialValue: .trip)
            _memo = State(initialValue: "")
            _checklist = State(initialValue: [])
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FoamTheme.sky(together: model.isTogetherNow)
                    .ignoresSafeArea()
                FoamAmbientBackgroundView(isTogether: model.isTogetherNow, softened: true)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        editorCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("タイトル")
                                    .font(FoamFont.bold(13, relativeTo: .caption))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.68))

                                TextField("例：箱根温泉旅行、ディズニーデート", text: $title)
                                    .font(FoamFont.bold(17, relativeTo: .headline))
                                    .foregroundStyle(FoamTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                Text("アイコン")
                                    .font(FoamFont.bold(13, relativeTo: .caption))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.68))
                                    .padding(.top, 4)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(PairPlanIcon.allCases) { candidate in
                                            let selected = icon == candidate
                                            Button {
                                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                                icon = candidate
                                            } label: {
                                                VStack(spacing: 5) {
                                                    ZStack {
                                                        Circle()
                                                            .fill(
                                                                selected
                                                                    ? LinearGradient(colors: candidate.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                                                    : LinearGradient(colors: [Color.white.opacity(0.88), Color.white.opacity(0.76)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                            )
                                                            .frame(width: 42, height: 42)
                                                        Image(systemName: candidate.symbolName)
                                                            .font(.system(size: 16, weight: .bold))
                                                            .foregroundStyle(selected ? Color.white : candidate.accentColor)
                                                    }
                                                    .overlay {
                                                        if selected {
                                                            Circle().strokeBorder(Color.white, lineWidth: 2)
                                                        }
                                                    }
                                                    Text(candidate.displayName)
                                                        .font(FoamFont.bold(11, relativeTo: .caption2))
                                                        .foregroundStyle(selected ? FoamTheme.ink : FoamTheme.ink.opacity(0.72))
                                                }
                                                .frame(width: 58, height: 66)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        editorCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Toggle(isOn: $isMultiDay) {
                                    Text("複数日（旅行・お泊まり）")
                                        .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                                        .foregroundStyle(FoamTheme.ink)
                                }
                                .tint(FoamTheme.warmAccent)

                                Divider()
                                    .overlay(FoamTheme.ink.opacity(0.08))

                                DatePicker(
                                    isMultiDay ? "はじまり" : "日付",
                                    selection: $startDate,
                                    displayedComponents: .date
                                )
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                                .font(FoamFont.bold(14.5, relativeTo: .subheadline))

                                if isMultiDay {
                                    DatePicker(
                                        "おわり",
                                        selection: $endDate,
                                        in: startDate...,
                                        displayedComponents: .date
                                    )
                                    .environment(\.locale, Locale(identifier: "ja_JP"))
                                    .font(FoamFont.bold(14.5, relativeTo: .subheadline))
                                }
                            }
                        }

                        editorCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("計画メモ・行きたいところ")
                                    .font(FoamFont.bold(13, relativeTo: .caption))
                                    .foregroundStyle(FoamTheme.ink.opacity(0.68))

                                TextField(
                                    "行きたい場所や宿のメモ、当日のおもいでなど…",
                                    text: $memo,
                                    axis: .vertical
                                )
                                .font(FoamFont.medium(14.5, relativeTo: .body))
                                .foregroundStyle(FoamTheme.ink)
                                .lineLimit(3...6)
                                .padding(12)
                                .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }

                        editorCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("やりたいこと・持ち物リスト")
                                        .font(FoamFont.bold(13, relativeTo: .caption))
                                        .foregroundStyle(FoamTheme.ink.opacity(0.68))
                                    Spacer()
                                    Button {
                                        showRapidComposer = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.system(size: 11, weight: .bold))
                                            Text("まとめて追加")
                                                .font(FoamFont.bold(11.5, relativeTo: .caption2))
                                        }
                                        .foregroundStyle(FoamTheme.warmAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.86), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }

                                checklistSubsetSection(kind: .todo)
                                Divider().overlay(FoamTheme.ink.opacity(0.08))
                                checklistSubsetSection(kind: .packing)
                                Divider().overlay(FoamTheme.ink.opacity(0.08))

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 6) {
                                        ForEach(PairPlanChecklistKind.allCases) { kind in
                                            let selected = newItemKind == kind
                                            let tint: Color = kind == .todo
                                                ? FoamTheme.warmAccent
                                                : Color(red: 0.24, green: 0.56, blue: 0.92)
                                            Button {
                                                newItemKind = kind
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: selected ? "checkmark" : kind.symbolName)
                                                        .font(.system(size: 10, weight: .bold))
                                                    Text(kind.displayName)
                                                        .font(FoamFont.bold(11.5, relativeTo: .caption2))
                                                }
                                                .foregroundStyle(selected ? .white : FoamTheme.ink.opacity(0.78))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(selected ? tint : Color.white.opacity(0.84), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Spacer(minLength: 0)
                                    }

                                    HStack(spacing: 8) {
                                        PlanRapidEntryField(
                                            text: $newChecklistTitle,
                                            placeholder: newItemKind == .todo ? "やりたいことを入力…" : "持ち物を入力…",
                                            isEnabled: true,
                                            autoFocusOnAppear: false,
                                            focusRequest: checklistFocusRequest,
                                            onSubmit: appendChecklistDraftFromKeyboard
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .frame(minHeight: 40)
                                        .background(Color.white.opacity(0.90), in: Capsule())

                                        Button {
                                            appendChecklistDraftFromKeyboard()
                                        } label: {
                                            Text("追加")
                                                .font(FoamFont.bold(12.5, relativeTo: .caption))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 13)
                                                .padding(.vertical, 9)
                                                .background(
                                                    newItemKind == .todo
                                                        ? FoamTheme.warmAccent
                                                        : Color(red: 0.24, green: 0.56, blue: 0.92),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }
                        }

                        if existingPlan != nil {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Text("この予定・アルバムを削除")
                                    .font(FoamFont.bold(14, relativeTo: .subheadline))
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(existingPlan == nil ? "予定・アルバムを追加" : "予定・アルバムを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        commitAndDismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(trimmedTitle.isEmpty)
                }
            }
            .onChange(of: startDate) { _, newStart in
                if endDate < newStart {
                    endDate = newStart
                }
            }
            .sheet(isPresented: $showRapidComposer) {
                PlanChecklistComposerSheet(
                    planTitle: trimmedTitle.isEmpty ? "予定リスト" : trimmedTitle,
                    target: .draft($checklist),
                    initialKind: newItemKind
                )
            }
            .confirmationDialog(
                "この予定・アルバムを削除しますか？\n（写真や日別メモ自体は消えません）",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("削除する", role: .destructive) {
                    if let existingPlan {
                        model.deletePlanEvent(id: existingPlan.id)
                    }
                    dismiss()
                    onDeleted?()
                }
            }
        }
        .preferredColorScheme(.light)
        .font(FoamFont.medium(16))
        .foregroundStyle(FoamTheme.ink)
    }

    @ViewBuilder
    private func checklistSubsetSection(kind: PairPlanChecklistKind) -> some View {
        let tint: Color = kind == .todo ? FoamTheme.warmAccent : Color(red: 0.24, green: 0.56, blue: 0.92)
        let matchingIndices = checklist.indices.filter { checklist[$0].kind == kind }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(kind == .todo ? "やりたいこと" : "持ち物")
                    .font(FoamFont.bold(13, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink)
                Spacer()
                Text("\(matchingIndices.count)件")
                    .font(FoamFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(FoamTheme.ink.opacity(0.52))
            }

            if matchingIndices.isEmpty {
                Text("なし")
                    .font(FoamFont.regular(12.5, relativeTo: .caption))
                    .foregroundStyle(FoamTheme.ink.opacity(0.45))
            } else {
                ForEach(matchingIndices, id: \.self) { index in
                    let item = checklist[index]
                    HStack(spacing: 10) {
                        Button {
                            checklist[index].isDone.toggle()
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(item.isDone ? tint : FoamTheme.ink.opacity(0.35))
                        }
                        .buttonStyle(.plain)

                        TextField("項目", text: $checklist[index].title)
                            .font(FoamFont.medium(14.5, relativeTo: .body))
                            .foregroundStyle(item.isDone ? FoamTheme.ink.opacity(0.50) : FoamTheme.ink)
                            .strikethrough(item.isDone)

                        Button {
                            checklist.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(FoamTheme.ink.opacity(0.32))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("削除")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                SoapBubbleSurface(
                    cornerStyle: .roundedRect(22),
                    prominence: .standard,
                    isTogether: model.isTogetherNow,
                    seed: 2.8,
                    wobbleScale: 0.25,
                    animated: false,
                    milkyFillOpacity: 0.78
                )
            }
    }

    private func appendChecklistDraftFromKeyboard() {
        let trimmed = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            checklistFocusRequest += 1
            return
        }
        checklist.append(PairPlanChecklistItem(title: trimmed, isDone: false, kind: newItemKind))
        newChecklistTitle = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        checklistFocusRequest += 1
    }

    private func commitAndDismiss() {
        guard !trimmedTitle.isEmpty else { return }
        let pendingTrimmed = newChecklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pendingTrimmed.isEmpty {
            checklist.append(PairPlanChecklistItem(title: pendingTrimmed, isDone: false, kind: newItemKind))
            newChecklistTitle = ""
        }
        let cal = CalendarDateValue.gregorianCurrent
        let startKey = EncounterCalendarAggregator.dayKey(for: startDate, calendar: cal)
        let resolvedEnd = isMultiDay ? max(startDate, endDate) : startDate
        let endKey = EncounterCalendarAggregator.dayKey(for: resolvedEnd, calendar: cal)
        if let saved = model.savePlanEvent(
            existingID: existingPlan?.id,
            title: trimmedTitle,
            startDayKey: startKey,
            endDayKey: endKey,
            icon: icon,
            memo: memo,
            checklist: checklist
        ) {
            onSaved?(saved)
        }
        dismiss()
    }
}
