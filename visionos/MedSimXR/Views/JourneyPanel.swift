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
            VStack(alignment: .leading, spacing: 10) {
                header(stage, count: journey.stages.count)
                if !compact {
                    Text(stage.brief).font(.callout)
                }
                Text("Team here: " + model.teamPresent.map { "\($0.name) (\($0.role))" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Ask the team").font(.subheadline.bold())
                ForEach(stage.actions) { action in
                    Button { Task { await model.requestTeamAction(action.id) } } label: {
                        Label("\(journey.member(action.member)?.name ?? action.member): \(action.label)",
                              systemImage: "person.wave.2.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.phase != .running || model.isBusy || model.journeyBusy)
                }
                if let last = model.teamLog.last, compact { logRow(last) }
                moveButton
                if !compact { log }
            }
            .padding(compact ? 14 : 0)
            .background {
                if compact { RoundedRectangle(cornerRadius: 16).fill(.regularMaterial) }
            }
        }
    }

    private func header(_ stage: JourneyStage, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "location.fill").foregroundStyle(.teal)
                Text("Stage \(model.stageIndex + 1) of \(count) · \(stage.label)").font(.headline)
                Spacer()
            }
            Text(stage.setting).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var moveButton: some View {
        if let next = model.nextStage {
            Button { Task { await model.advanceStage() } } label: {
                Label("Move on: \(next.label)", systemImage: "arrow.right.circle.fill").frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Team log").font(.subheadline.bold()).padding(.top, 4)
            if model.teamLog.isEmpty {
                Text("Nothing asked yet.").foregroundStyle(.tertiary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.teamLog.reversed()) { logRow($0) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func logRow(_ r: TeamActionResult) -> some View {
        let place = model.journey?.stages.first { $0.id == r.stageId }?.label ?? r.stageId
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.done ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(r.done ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(r.member.name) · \(r.label)").font(.caption.bold())
                Text(r.result ?? r.response).font(.caption)
                Text(place).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
