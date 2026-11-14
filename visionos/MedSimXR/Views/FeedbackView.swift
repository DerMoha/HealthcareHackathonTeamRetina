import SwiftUI

struct FeedbackView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if SmokeLog.pitch, let f = model.feedback {
            PitchDebrief(scheme: .forCase(ultrasound: model.isUltrasound, journey: model.journey != nil), diagnosis: f.diagnosisSubmitted)
        } else if let f = model.feedback {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(f)
                    categories(f.categories)
                    if !f.replay.isEmpty { replay }
                    section("What happened", icon: "text.alignleft", tint: NoteTone.learner) {
                        Text(f.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    if let s = model.scenario, let d = model.debrief { scenarioDebrief(s, d) }

                    scanReview(f.scanReview ?? [])
                    HStack(alignment: .top, spacing: 14) {
                        list("Strengths", f.strengths, "checkmark.circle.fill", .green)
                        list("Missed", f.missed, "exclamationmark.circle.fill", .orange)
                    }
                    management(f.management)
                    scored(f.fitting.title, f.fitting.score, f.fitting.maxScore, f.fitting.criteria, [
                        ("measurement", "Measurement"), ("fitting", "Size, position and tension"),
                        ("safety", "Circulation, sensation and comfort checks"),
                    ])
                    if let explanation = f.fitting.explanation {
                        Text(explanation).font(.callout)
                        Text("Educational fitting exercise, not a validated sizing method.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    list("Investigations requested", f.investigations, "doc.text.image.fill", NoteTone.learner)
                    list("Relevant findings", f.relevantFindings, "stethoscope", NoteTone.learner)
                    documentation(f.documentation)
                    list("Next steps", f.nextSteps, "arrow.right.circle.fill", .blue)

                    Button { Task { await model.reset() } } label: {
                        Label("Try again", systemImage: "arrow.counterclockwise").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(NoteTone.learner).controlSize(.large).disabled(model.isBusy)

                    Text(f.disclaimer).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Summary

    private func hero(_ f: Feedback) -> some View {
        let frac = f.maxScore > 0 ? Double(f.totalScore) / Double(f.maxScore) : 0
        let a = f.diagnosticAssessment
        let tint = verdictColor(a.verdict)
        return HStack(alignment: .center, spacing: 30) {
            ScoreRing(score: f.totalScore, maxScore: f.maxScore, fraction: frac)
                .frame(width: 176, height: 176)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Label(verdictTitle(a.verdict), systemImage: verdictIcon(a.verdict))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(tint.opacity(0.18), in: Capsule())
                    Text(grade(frac)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let d = f.diagnosisSubmitted {
                    Text(d).font(.title2.weight(.bold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Text(a.explanation).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .noteCard(padding: 24, tint: NoteTone.score(frac))
    }

    private func grade(_ frac: Double) -> String {
        frac >= 0.9 ? "Excellent" : frac >= 0.75 ? "Strong" : frac >= 0.5 ? "Developing" : "Needs work"
    }

    private func verdictTitle(_ v: String) -> String {
        switch v {
        case "correct": "Correct diagnosis"
        case "partial": "Partly correct"
        case "incorrect": "Incorrect diagnosis"
        default: v.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func verdictIcon(_ v: String) -> String {
        switch v { case "correct": "checkmark.seal.fill"; case "partial": "circle.lefthalf.filled"; case "incorrect": "xmark.seal.fill"; default: "questionmark.circle" }
    }

    private func verdictColor(_ v: String) -> Color {
        switch v { case "correct": .green; case "partial": .orange; case "incorrect": .red; default: .secondary }
    }

    private func categories(_ items: [CategoryResult]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                header("Performance by area", icon: "chart.bar.fill", tint: NoteTone.learner)
                Spacer()
                Text("Tap an area for detail").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider().opacity(0.5) }
                CategoryRow(category: c)
            }
        }
        .noteCard(padding: 20)
    }

    private var replay: some View {
        HStack(spacing: 16) {
            Image(systemName: "cube.transparent.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [NoteTone.replay, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Spatial Clinical Replay").font(.headline)
                Text("Step through your examination on the patient, with the anatomy beneath.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button { model.startReplay() } label: {
                Label("Open replay", systemImage: "play.fill").font(.callout.weight(.semibold))
            }
            .buttonStyle(.borderedProminent).tint(NoteTone.replay)
        }
        .noteCard(padding: 16, tint: NoteTone.replay)
    }

    // MARK: Sections

    private func header(_ title: String, icon: String, tint: Color) -> some View {
        Label { Text(title).font(.headline) } icon: { Image(systemName: icon).foregroundStyle(tint) }
    }

    private func section<C: View>(_ title: String, icon: String = "circle.grid.2x1.fill", tint: Color = .secondary,
                                  @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title, icon: icon, tint: tint)
            content()
        }
        .noteCard()
    }

    /// Ultrasound: the expected views with the learner's own picture, or an example when missed.
    @ViewBuilder
    private func scanReview(_ items: [ScanReviewItem]) -> some View {
        let expected = items.filter(\.expected), extras = items.filter { !$0.expected && $0.obtained }
        if !expected.isEmpty {
            section("Scan checklist · \(expected.filter(\.obtained).count) of \(expected.count) views",
                    icon: "waveform.path.ecg.rectangle.fill", tint: NoteTone.learner) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(expected) { reviewRow($0) }
                }
                if !extras.isEmpty {
                    Text("Extra views you obtained").font(.subheadline.bold())
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(extras) { reviewRow($0) }
                    }
                }
                Text("Images are real example sonograms from other pregnancies. A faded picture is what the missed view looks like.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func reviewRow(_ item: ScanReviewItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Color.black
                if let id = item.image, let image = UltrasoundImage.image(id) {
                    Image(uiImage: image).resizable().scaledToFill().opacity(item.obtained ? 1 : 0.3)
                }
                Image(systemName: item.obtained ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, item.obtained ? .green : .red)
                    .font(.title3).padding(5)
            }
            .frame(width: 104, height: 78).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label).font(.callout.weight(.semibold))
                Text(item.explanation).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }

    /// How to read the score: what this scenario offered and what the instructor changed.
    private func scenarioDebrief(_ s: ScenarioRuntime, _ d: ScenarioDebrief) -> some View {
        section("Scenario: \(s.title)", icon: "theatermasks.fill", tint: .purple) {
            Text(s.reviewLabel).font(.caption).foregroundStyle(s.reviewState == "clinician_reviewed" ? .green : .orange)
            ForEach(d.interpretation, id: \.self) { Text($0).font(.callout) }
            ForEach(d.timeline.filter { $0.type == "intervention" || $0.type == "hint" }, id: \.seq) { step in
                Label(step.label, systemImage: step.type == "hint" ? "lightbulb" : "person.wave.2")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private static let areas = [
        ("investigation", "Investigation choices"), ("interpretation", "Interpretation of results"),
        ("management", "Management decisions"), ("safety", "Safety after inconclusive imaging"),
    ]

    /// Separate dimension: shown with its own score, never added to the 100 points.
    private func management(_ m: ManagementAssessment) -> some View {
        scored(m.title, m.score, m.maxScore, m.criteria, Self.areas)
    }

    @ViewBuilder
    private func scored(_ title: String, _ score: Int, _ maxScore: Int, _ criteria: [CriterionResult],
                        _ areas: [(String, String)]) -> some View {
        if !criteria.isEmpty {
            section("\(title) · \(score)/\(maxScore)", icon: "list.bullet.clipboard.fill", tint: NoteTone.learner) {
                Text("Scored separately from the 100 points above.").font(.caption).foregroundStyle(.secondary)
                ForEach(areas, id: \.0) { area, title in
                    let items = criteria.filter { $0.area == area }
                    if !items.isEmpty {
                        Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    ForEach(items) { CriterionLine(criterion: $0) }
                }
            }
        }
    }

    /// Notebook versus session record: written and done, done but not written, written but never done.
    @ViewBuilder
    private func documentation(_ items: [DocumentationItem]) -> some View {
        if !items.isEmpty {
            section("Your notes vs. what happened", icon: "doc.text.magnifyingglass", tint: NoteTone.learner) {
                ForEach(items) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.callout.weight(.medium))
                            Text(item.comment).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        switch item.status {
                        case "documented": Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case "unsupported": Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        default: Image(systemName: "pencil.slash").foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String], _ icon: String, _ color: Color) -> some View {
        if !items.isEmpty {
            section(title, icon: icon, tint: color) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(item).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// The overall score as a thick ring: the arc in the score's colour, the number set large in the middle.
private struct ScoreRing: View {
    let score: Int
    let maxScore: Int
    let fraction: Double

    var body: some View {
        let color = NoteTone.score(fraction)
        ZStack {
            Circle().stroke(.white.opacity(0.10), lineWidth: 16)
            Circle().trim(from: 0, to: max(0.001, fraction))
                .stroke(AngularGradient(colors: NoteTone.scoreRamp(fraction), center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, fraction))),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 8)
            VStack(spacing: -2) {
                Text("\(score)").font(.system(size: 60, weight: .bold, design: .rounded)).monospacedDigit()
                Text("of \(maxScore)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) of \(maxScore)")
    }
}

/// A category's score as a labelled bar; tap to see its criteria.
private struct CategoryRow: View {
    let category: CategoryResult
    @State private var open = false

    /// An SF Symbol for the kind of category, from words in its title.
    private var icon: String {
        let t = category.title.lowercased()
        let map: [(String, String)] = [
            ("history", "text.bubble.fill"), ("examination", "stethoscope"), ("communication", "bubble.left.and.bubble.right.fill"),
            ("reasoning", "brain.head.profile"), ("consent", "hand.raised.fill"), ("probe", "waveform.path.ecg"),
            ("finding", "doc.text.fill"), ("document", "doc.text.fill"), ("roadside", "car.fill"), ("ambulance", "cross.case.fill"),
            ("emergency", "staroflife.fill"), ("investigation", "doc.text.image.fill"), ("management", "list.bullet.clipboard.fill"),
            ("fitting", "hand.raised.fingers.spread.fill"), ("safety", "shield.lefthalf.filled"),
        ]
        return map.first { t.contains($0.0) }?.1 ?? "chart.bar.fill"
    }

    var body: some View {
        let frac = category.maxScore > 0 ? Double(category.score) / Double(category.maxScore) : 0
        let color = NoteTone.score(frac)
        let met = category.criteria.filter(\.met).count
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { open.toggle() } } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(category.title).font(.body.weight(.semibold))
                            if !category.criteria.isEmpty {
                                Text("\(met) of \(category.criteria.count) criteria").font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text("\(category.score)").font(.title3.weight(.bold).monospacedDigit())
                            + Text(" / \(category.maxScore)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.10))
                                Capsule().fill(LinearGradient(colors: NoteTone.scoreRamp(frac), startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(10, g.size.width * frac))
                            }
                        }
                        .frame(height: 10)
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if open {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(category.criteria) { CriterionLine(criterion: $0) }
                }
                .padding(.leading, 54).padding(.bottom, 8)
            }
        }
    }
}

/// One scored criterion: met or not, its points and the reason.
private struct CriterionLine: View {
    let criterion: CriterionResult

    var body: some View {
        let c = criterion
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: c.met ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(c.met ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(c.label).font(.callout.weight(.medium))
                    if c.method == "keyword" {
                        Text("heuristic").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange.opacity(0.25), in: Capsule())
                    }
                    Spacer()
                    Text("\(c.points)/\(c.maxPoints)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(c.comment).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Pitch debrief (uinotebook, -pitch only)

/// One line of a case's mark scheme: what the case expects, and what the learner wrote, said or did.
private struct PitchMark: Identifiable {
    enum Source: String { case notebook = "NOTEBOOK", said = "YOU SAID", did = "YOU DID" }
    let id = UUID()
    let expected: String
    let detail: String?
    let source: Source?
    let wrote: String?
    let note: String?
    let points: Int
    let max: Int
    var color: Color { points == max ? .green : points == 0 ? .red : .orange }
    var icon: String { points == max ? "checkmark.circle.fill" : points == 0 ? "xmark.circle.fill" : "circle.lefthalf.filled" }
    var status: String { points == max ? "Matched" : points == 0 ? "Missed" : "Partial" }
}

private struct PitchDomain: Identifiable {
    let id = UUID()
    let title: String
    let tag: String
    let icon: String
    let marks: [PitchMark]
    var points: Int { marks.reduce(0) { $0 + $1.points } }
    var max: Int { marks.reduce(0) { $0 + $1.max } }
}

private func M(_ expected: String, _ detail: String?, _ source: PitchMark.Source?, _ wrote: String?, _ note: String?,
               _ points: Int, _ max: Int) -> PitchMark {
    PitchMark(expected: expected, detail: detail, source: source, wrote: wrote, note: note, points: points, max: max)
}

/// A case's mark scheme with the learner's marks: the debrief shown in the pitch screenshots.
struct PitchScheme {
    fileprivate let protocolName: String
    fileprivate let verdict: String
    fileprivate let summary: String
    fileprivate let left: [PitchDomain]
    fileprivate let right: [PitchDomain]

    fileprivate var marks: [PitchMark] { (left + right).flatMap(\.marks) }
    fileprivate var score: Int { marks.reduce(0) { $0 + $1.points } }
    fileprivate var max: Int { marks.reduce(0) { $0 + $1.max } }
    static let ratings = ["Fail", "Borderline", "Pass", "Good", "Excellent"]
    var rating: Int { let s = Double(score) / Double(Swift.max(max, 1)); return s >= 0.85 ? 4 : s >= 0.75 ? 3 : s >= 0.6 ? 2 : s >= 0.5 ? 1 : 0 }

    static func forCase(ultrasound: Bool, journey: Bool) -> PitchScheme { ultrasound ? .scan : journey ? .trauma : .wrist }

    static let wrist = PitchScheme(
        protocolName: "OSCE station mark scheme  ·  Wrist injury",
        verdict: "Correct diagnosis",
        summary: "Snuffbox tenderness found and acted on with a safe plan. Complete the scaphoid examination and explain the risk of non-union.",
        left: [
            PitchDomain(title: "History", tag: "SOCRATES", icon: "text.bubble.fill", marks: [
                M("Mechanism of injury", "FOOSH, side, when", .notebook, "Fell off bicycle yesterday onto outstretched right hand", nil, 5, 5),
                M("Pain", "site, onset, character, radiation, severity", .notebook, "Pain 3/10 at rest, 7-8/10 gripping", "radiation and timing not noted", 4, 7),
                M("Neurological symptoms", "numbness, tingling, weakness", .notebook, "No numbness.", nil, 4, 4),
                M("Hand dominance, job, past history", "shapes the plan", nil, nil, "Not in your notebook", 0, 4),
            ]),
            PitchDomain(title: "Examination", tag: "Look · Feel · Move", icon: "stethoscope", marks: [
                M("Look", "swelling, bruising, deformity, both sides", .did, "Inspected both wrists", "swelling not described", 3, 5),
                M("Feel: anatomical snuffbox", "the key sign", .notebook, "Tender in the right anatomical snuffbox", nil, 8, 8),
                M("Feel: scaphoid tubercle, thumb axial load", "completes the triad", nil, nil, "Not examined", 0, 6),
                M("Move and neurovascular status", "range, grip, pulse, CRT, sensation", .did, "Circulation and sensation checked before and after the splint", nil, 6, 6),
            ]),
        ],
        right: [
            PitchDomain(title: "Imaging", tag: "Scaphoid series", icon: "doc.text.image.fill", marks: [
                M("Scaphoid series X-ray", "PA, lateral, oblique, ulnar-deviated PA", .did, "Requested right wrist X-ray, scaphoid views", nil, 7, 7),
                M("A normal film does not exclude fracture", "occult in up to 1 in 5", .notebook, "No fracture visible; occult scaphoid fracture not excluded", nil, 8, 8),
            ]),
            PitchDomain(title: "Management", tag: "Suspected scaphoid fracture", icon: "cross.case.fill", marks: [
                M("Thumb-spica immobilisation, analgesia", nil, .notebook, "Thumb spica splint. Analgesia: paracetamol and ibuprofen.", "AI-tidied, approved by you", 7, 7),
                M("MRI or fracture clinic", "within 10 to 14 days", .notebook, "MRI of the wrist, or fracture clinic review in 10 days", nil, 8, 8),
                M("Safety-netting", "numbness, colour change, worse pain", .notebook, "Return if numbness or worsening pain.", nil, 5, 5),
                M("Risk of non-union and AVN explained", nil, nil, nil, "Not discussed with Alex", 0, 5),
            ]),
            PitchDomain(title: "Communication", tag: "Calgary–Cambridge", icon: "bubble.left.and.bubble.right.fill", marks: [
                M("Initiating: introduction, consent", nil, .said, "Is it okay if I examine your wrist?", nil, 5, 5),
                M("Gathering: open questions, empathy", nil, .said, "I'm sorry, I know that hurt. I'll be gentle.", nil, 5, 5),
                M("Explanation and planning", "chunk and check", .said, "A small bone in your wrist may be broken", "no check-back", 3, 5),
            ]),
        ])

    static let scan = PitchScheme(
        protocolName: "Mid-trimester anomaly scan checklist  ·  18+0 to 20+6 weeks",
        verdict: "Impression correct",
        summary: "Biometry complete and in keeping with 20 weeks. The cardiac outflow tracts were not seen: offer a rescan before 23+0 weeks.",
        left: [
            PitchDomain(title: "Consent and preparation", tag: "Before the scan", icon: "hand.raised.fill", marks: [
                M("Identity and consent", "name, date of birth, verbal consent", .said, "Could you confirm your full name and date of birth?", nil, 5, 5),
                M("What the scan can and cannot show", "screening, not every condition", .said, "I'll move a small probe to look at the baby", "limits not explained", 2, 5),
            ]),
            PitchDomain(title: "Biometry", tag: "HC · BPD · AC · FL", icon: "ruler.fill", marks: [
                M("Head: BPD and HC", "transthalamic plane", .notebook, "BPD 4.61 cm, HC 16.73 cm", nil, 8, 8),
                M("Abdomen: AC", "stomach and umbilical vein", .notebook, "AC 13.82 cm, EFW 289 g", nil, 8, 8),
                M("Femur length", "whole ossified shaft", .notebook, "FL 3.17 cm", nil, 6, 6),
                M("Plotted against gestation", nil, .notebook, "All measurements in keeping with 20 weeks", nil, 3, 3),
            ]),
            PitchDomain(title: "Placenta and liquor", tag: "Pregnancy", icon: "drop.fill", marks: [
                M("Placental site", "and relation to the internal os", .notebook, "Posterior placenta", "distance from the os not noted", 5, 8),
                M("Amniotic fluid", "subjective or deepest pool", .notebook, "Liquor normal", nil, 7, 7),
            ]),
        ],
        right: [
            PitchDomain(title: "Fetal anatomy", tag: "Heart · spine · head", icon: "heart.fill", marks: [
                M("Four-chamber view", "situs, size, symmetry", .notebook, "Heart: four chamber view seen", nil, 8, 8),
                M("Outflow tracts", "LVOT, RVOT, three-vessel trachea", nil, nil, "Not obtained or documented", 0, 8),
                M("Spine", "sagittal and transverse, skin line", .notebook, "Spine seen", "planes and skin not noted", 4, 7),
                M("Head", "ventricular atrium, cerebellum", .did, "Transcerebellar plane obtained", "not in your notes", 3, 6),
                M("Fetal heart activity", nil, .said, "I can see the heartbeat", nil, 6, 6),
            ]),
            PitchDomain(title: "Communicating results", tag: "With Sarah", icon: "person.wave.2.fill", marks: [
                M("Findings explained", nil, .notebook, "Explained the findings to Sarah", nil, 6, 6),
                M("Question about the sex", "offer, never guess", .said, "Would you like to know the sex?", "asked mid-scan", 3, 4),
                M("Rescan for views not seen", "recall before 23+0 weeks", nil, nil, "Not offered", 0, 5),
            ]),
        ])

    static let trauma = PitchScheme(
        protocolName: "Major trauma  ·  <C>ABCDE  ·  ATMIST  ·  Open fracture standard",
        verdict: "Correct diagnosis",
        summary: "Bleeding controlled and antibiotics within the hour, despite three interruptions. Complete D and E, and give the full signs in handover.",
        left: [
            PitchDomain(title: "Primary survey", tag: "<C>ABCDE", icon: "staroflife.fill", marks: [
                M("<C> Catastrophic haemorrhage", "pressure and dressing first", .did, "Asked Sam: direct pressure and a dressing", nil, 6, 6),
                M("A  Airway and C-spine", nil, .notebook, "Helmet, no head injury, no neck pain", nil, 5, 5),
                M("B  Breathing", "RR, SpO2, chest", .did, "RR 22, SpO2 97 % from the crew", "chest not examined", 3, 5),
                M("C  Circulation", "HR, BP, CRT, IV access", .said, "Heart rate down to 104", "BP and CRT not handed over", 4, 6),
                M("D  Disability", "GCS, pupils, glucose", .did, "GCS 15 from the crew", "pupils and glucose not checked", 2, 5),
                M("E  Exposure", "other injuries, temperature", nil, nil, "Other injuries not looked for", 0, 3),
            ]),
            PitchDomain(title: "Handover", tag: "ATMIST", icon: "arrow.left.arrow.right", marks: [
                M("A · T  Age, time of injury", nil, .said, "Jordan, 34 … forty minutes ago", nil, 6, 6),
                M("M · I  Mechanism, injuries", nil, .said, "Cyclist knocked off by a car … deformed right forearm", nil, 7, 7),
                M("S · T  Signs, treatment", nil, .said, "Heart rate 104 … morphine given", "no BP or RR", 4, 7),
            ]),
        ],
        right: [
            PitchDomain(title: "Open fracture", tag: "Within the first hour", icon: "bandage.fill", marks: [
                M("IV antibiotics within 1 hour", "allergy checked", .notebook, "IV antibiotics and tetanus given", "52 min after injury", 8, 8),
                M("Tetanus status", nil, .said, "When did you last have a tetanus injection?", nil, 4, 4),
                M("Wound photo and saline dressing", "no repeated lifting", .did, "Photographed and dressed by the crew", "not in your notes", 3, 6),
                M("Splint the limb", nil, .did, "Vacuum splint, hand to above the elbow", nil, 5, 5),
                M("Neurovascular check before and after", nil, .notebook, "Hand pink, sensation intact after the splint", "no check before", 3, 6),
                M("Orthopaedics for debridement", "theatre within 12 hours", .notebook, "Urgent orthopaedic referral for debridement and fixation", nil, 6, 6),
            ]),
            PitchDomain(title: "Under distraction", tag: "Non-technical skills", icon: "person.3.fill", marks: [
                M("Scene safety before approach", nil, .did, "Asked Sam to check the scene first", nil, 5, 5),
                M("Kept the survey going", "driver, passer-by, registrar", .said, "I'll talk to you in a moment", "C paused 40 s", 3, 5),
                M("Closed-loop communication", nil, .said, "Sam, direct pressure please. Tell me when it's on.", nil, 5, 5),
            ]),
        ])
}

/// The pitch debrief: the overall result, then the learner's notebook marked line by line against the case.
struct PitchDebrief: View {
    let scheme: PitchScheme
    let diagnosis: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            // The column with fewer lines also carries what to work on next.
            let shortLeft = scheme.left.reduce(0) { $0 + $1.marks.count + 2 } <= scheme.right.reduce(0) { $0 + $1.marks.count + 2 }
            HStack(alignment: .top, spacing: 16) {
                column(scheme.left, next: shortLeft)
                column(scheme.right, next: !shortLeft)
            }
        }
    }

    private var hero: some View {
        let frac = Double(scheme.score) / Double(max(scheme.max, 1))
        let marks = scheme.marks
        return HStack(alignment: .center, spacing: 26) {
            ScoreRing(score: scheme.score, maxScore: scheme.max, fraction: frac).frame(width: 136, height: 136)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Label("PASS", systemImage: "checkmark.seal.fill").font(.headline.weight(.heavy)).foregroundStyle(.green)
                        .padding(.horizontal, 14).padding(.vertical, 6).background(.green.opacity(0.2), in: Capsule())
                    Label(scheme.verdict, systemImage: "scope").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    Text(scheme.protocolName).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let diagnosis { Text(diagnosis).font(.title2.weight(.bold)).lineLimit(1) }
                Text(scheme.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    count(marks.filter { $0.points == $0.max }.count, "matched", .green, "checkmark.circle.fill")
                    count(marks.filter { $0.points > 0 && $0.points < $0.max }.count, "partial", .orange, "circle.lefthalf.filled")
                    count(marks.filter { $0.points == 0 }.count, "missed", .red, "xmark.circle.fill")
                    Spacer(minLength: 0)
                    rating
                }
                .padding(.top, 2)
            }
        }
        .noteCard(padding: 18, tint: .green)
    }

    private func count(_ n: Int, _ label: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(n)").font(.headline.monospacedDigit())
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// The examiner's global rating, the given step lit.
    private var rating: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("GLOBAL RATING").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(Array(PitchScheme.ratings.enumerated()), id: \.offset) { i, r in
                    let on = i == scheme.rating
                    Text(r).font(.caption.weight(on ? .bold : .medium))
                        .foregroundStyle(on ? .white : .secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? AnyShapeStyle(LinearGradient(colors: [NoteTone.learner, .green], startPoint: .leading, endPoint: .trailing))
                                       : AnyShapeStyle(.white.opacity(0.08)), in: Capsule())
                }
            }
        }
    }

    private func column(_ domains: [PitchDomain], next: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(domains) { domain($0) }
            if next { nextTime }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func domain(_ d: PitchDomain) -> some View {
        let frac = Double(d.points) / Double(max(d.max, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: d.icon).font(.callout.weight(.semibold)).foregroundStyle(NoteTone.learner)
                    .frame(width: 32, height: 32).background(NoteTone.learner.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(d.title).font(.headline)
                Text(d.tag).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.08), in: Capsule())
                Spacer(minLength: 4)
                Text("\(d.points)").font(.title3.weight(.bold).monospacedDigit())
                + Text(" / \(d.max)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    Capsule().fill(LinearGradient(colors: NoteTone.scoreRamp(frac), startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * frac))
                }
            }
            .frame(height: 5)
            ForEach(d.marks) { row($0) }
        }
        .noteCard(padding: 14)
    }

    /// The missed lines, as what to do next time.
    private var nextTime: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next time", systemImage: "arrow.uturn.forward.circle.fill").font(.headline).foregroundStyle(.orange)
            ForEach(scheme.marks.filter { $0.points < $0.max }.sorted { $0.points * $1.max < $1.points * $0.max }.prefix(3)) { m in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text(m.expected).font(.callout.weight(.medium)).lineLimit(1)
                }
            }
        }
        .noteCard(padding: 14, tint: .orange)
    }

    /// Expected by the case (top), then the learner's own words or action and what was missing.
    private func row(_ m: PitchMark) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: m.icon).font(.title3).foregroundStyle(m.color).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(m.expected).font(.callout.weight(.semibold)).lineLimit(1).layoutPriority(1)
                    if let detail = m.detail { Text(detail).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                    Spacer(minLength: 4)
                    Text("\(m.points)/\(m.max)").font(.callout.weight(.semibold).monospacedDigit()).foregroundStyle(m.color)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if let source = m.source, let wrote = m.wrote {
                        Text(source.rawValue).font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(NoteTone.learner)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NoteTone.learner.opacity(0.16), in: Capsule()).fixedSize()
                        Text("\u{201C}\(wrote)\u{201D}").font(.callout).foregroundStyle(NoteTone.learner).lineLimit(1).layoutPriority(1)
                    }
                    if let note = m.note {
                        if m.wrote == nil {
                            Label(note, systemImage: "pencil.slash").font(.callout.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.47))
                        } else {
                            Text("· \(note)").font(.caption.weight(.semibold)).foregroundStyle(m.color).lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}
