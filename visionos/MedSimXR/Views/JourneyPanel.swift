import SwiftUI

/// Journey cases: where the encounter is, who is there, what the team can be asked to do, and
/// the move to the next place. Shown in the control window and in the notebook's Team tab.
/// Every button calls the same model method the voice agent's `request_team_action` tool uses.
struct JourneyPanel: View {
    @Environment(AppModel.self) private var model
    /// Compact: the small session palette. Full: the notebook page, with the team log.
    var compact = false

    var body: some View {
        if let journey = model.journey, let stage = model.currentStage {
            VStack(alignment: .leading, spacing: 14) {
                header(stage, journey: journey)
                if !compact {
                    Text(stage.brief).font(.callout).foregroundStyle(.primary.opacity(0.9))
                }
                team(journey)
                Text("ASK THE TEAM").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(stage.actions) { action in actionButton(action, journey: journey) }
                }
                if let last = model.teamLog.last, compact { logRow(last) }
                moveButton
                if !compact { log }
            }
            .padding(compact ? 16 : 0)
            .background {
                if compact { RoundedRectangle(cornerRadius: 20).fill(.regularMaterial) }
            }
        }
    }

    private func header(_ stage: JourneyStage, journey: JourneyInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(journey.stages.indices, id: \.self) { i in
                    Capsule().fill(i <= model.stageIndex ? Color.teal : Color.white.opacity(0.18))
                        .frame(height: 4)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("STAGE \(model.stageIndex + 1) OF \(journey.stages.count)")
                    .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(.teal)
                Spacer()
            }
            Text(stage.label).font(.title3.weight(.semibold))
            Label(stage.setting, systemImage: "location.fill").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func team(_ journey: JourneyInfo) -> some View {
        HStack(spacing: 14) {
            ForEach(model.teamPresent) { member in
                HStack(spacing: 8) {
                    SpeakerBadge(name: member.name, tint: journey.tint(member), size: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(member.name).font(.caption.weight(.semibold))
                        Text(member.role).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionButton(_ action: JourneyAction, journey: JourneyInfo) -> some View {
        let member = journey.member(action.member)
        let done = model.teamLog.contains { $0.actionId == action.id && $0.done }
        return Button { Task { await model.requestTeamAction(action.id) } } label: {
            HStack(spacing: 10) {
                SpeakerBadge(name: member?.name ?? action.member, tint: member.map(journey.tint) ?? .gray, size: 24)
                Text(action.label).font(.callout)
                Spacer(minLength: 4)
                Text(member?.name ?? action.member).font(.caption).foregroundStyle(.secondary)
                Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(done ? Color.green : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        .disabled(model.phase != .running || model.isBusy || model.journeyBusy)
    }

    @ViewBuilder
    private var moveButton: some View {
        if let next = model.nextStage {
            Button { Task { await model.advanceStage() } } label: {
                Label("Move on: \(next.label)", systemImage: "arrow.right.circle.fill")
                    .font(.callout.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.teal)
            .disabled(model.phase != .running || model.isBusy || model.journeyBusy)
        } else {
            Label("Last stop. Write your assessment and plan in the notebook.", systemImage: "flag.checkered")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// What the team did, newest first: observations, treatments, and requests they could not do yet.
    private var log: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEAM LOG").font(.caption.weight(.semibold)).tracking(1.2).foregroundStyle(.secondary).padding(.top, 4)
            if model.teamLog.isEmpty {
                Text("Nothing asked yet.").foregroundStyle(.tertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.teamLog.reversed()) { logRow($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func logRow(_ r: TeamActionResult) -> some View {
        let place = model.journey?.stages.first { $0.id == r.stageId }?.label ?? r.stageId
        return HStack(alignment: .top, spacing: 10) {
            SpeakerBadge(name: r.member.name, tint: model.journey?.tint(r.member) ?? .gray, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: r.done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(r.done ? .green : .orange)
                    Text(r.label).font(.caption.bold())
                    Spacer(minLength: 4)
                    Text(place).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(r.result ?? r.response).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 12))
    }
}

/// Who is speaking: initials in a role-coloured disc. Shared by the journey panel and the pitch subtitles.
struct SpeakerBadge: View {
    var name: String
    var tint: Color
    var size: CGFloat = 30
    /// Shown instead of initials (the learner's stethoscope).
    var symbol: String?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: max(1, size / 30))
            if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold))
            } else {
                Text(Self.initials(name)).font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(separator: " ").filter { !["Dr", "Dr."].contains($0) }
        return String(words.prefix(2).compactMap(\.first)).uppercased()
    }
}

extension JourneyInfo {
    /// One colour per crew member, in team order; never teal (the learner) or orange (the patient).
    func tint(_ member: JourneyMember) -> Color {
        let palette: [Color] = [Color(red: 0.32, green: 0.56, blue: 1), Color(red: 0.7, green: 0.45, blue: 1),
                                Color(red: 1, green: 0.4, blue: 0.62), Color(red: 0.35, green: 0.82, blue: 0.5)]
        return palette[(team.firstIndex { $0.id == member.id } ?? 0) % palette.count]
    }
}
