import SwiftUI

/// Pitch-only Vision Pro Studio (`-pitch -pitchStudio`, `pitch_shots.sh --case studio`): the community
/// marketplace, a download to the headset, the scenario's mix-and-match configuration and the library
/// with the scenario ready to play. All content is staged data; nothing here runs in the normal app.
struct PitchStudioWindow: View {
    static let on = SmokeLog.pitch && ProcessInfo.processInfo.arguments.contains("-pitchStudio")

    enum Page { case marketplace, detail, library }
    @State private var tab = 0
    @State private var page = Page.marketplace
    @State private var progress: Double? = nil
    private let hold = AppConfig.launchArgument("-pitchHold")

    var body: some View {
        TabView(selection: $tab) {
            Tab("Marketplace", systemImage: "storefront", value: 0) { content }
            Tab("Library", systemImage: "square.stack.3d.down.right", value: 1) { content }
            Tab("Studio AI", systemImage: "wand.and.stars", value: 2) { content }
            Tab("Cohorts", systemImage: "person.3", value: 3) { content }
        }
        .frame(minWidth: 1280, minHeight: 820)
        .task { await run() }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .marketplace: PSMarketplace(progress: progress)
        case .detail: PSDetail(s: PSData.featured)
        case .library: PSLibrary()
        }
    }

    private func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    private func shot(_ name: String) async {
        await pause(2.5)
        SmokeLog.mark("STEP \(name)")
        if hold == name {
            SmokeLog.mark("HOLD \(name)")
            while true { await pause(3600) }
        }
        await pause(2.5)
    }

    private func run() async {
        await pause(4)
        await shot("vp-01-marketplace")
        progress = 0.68
        await shot("vp-02-download")
        progress = nil
        page = .detail
        await shot("vp-03-scenario-detail")
        tab = 1
        page = .library
        await shot("vp-04-library-ready")
        SmokeLog.mark("DONE")
    }
}

// MARK: - Data

struct PSScenario: Identifiable {
    var id: String { title }
    let title: String
    let patient: String
    let cover: String
    let author: String
    let institution: String
    let rating: Double
    let reviews: Int
    let downloads: String
    let environment: String
    let crowd: String
    let distraction: String
    let difficulty: String
    let protocolName: String
    let size: String
    var stages: [String] = []
}

enum PSData {
    static let featured = PSScenario(
        title: "Rush hour: cyclist versus car", patient: "Jordan, 34 · open forearm fracture", cover: "rt-01-roadside",
        author: "Dr Priya Raman", institution: "St Aldhelm's Teaching Hospital · Emergency Medicine",
        rating: 4.9, reviews: 312, downloads: "2.4k", environment: "Roadside → Ambulance → Resus", crowd: "Busy · 6 bystanders",
        distraction: "High", difficulty: "Advanced", protocolName: "ABCDE + ATMIST", size: "1.2 GB",
        stages: ["Roadside", "Ambulance", "Resus"])
    static let wrist = PSScenario(
        title: "Fell off the bike: the painful wrist", patient: "Alex, 28 · snuffbox tenderness", cover: "wrist-02-conversation",
        author: "Dr Tomás Ortega", institution: "Northfield Medical School", rating: 4.8, reviews: 540, downloads: "5.1k",
        environment: "Outpatient clinic", crowd: "Quiet", distraction: "Low", difficulty: "Foundation", protocolName: "OSCE mark scheme",
        size: "640 MB")
    static let scan = PSScenario(
        title: "The 20-week anomaly scan", patient: "Sarah, 31 · G1P0, 20+2 weeks", cover: "us-02-head-bpd",
        author: "Helen Achebe", institution: "Riverside Women's Hospital · Sonography", rating: 4.9, reviews: 268, downloads: "1.8k",
        environment: "Antenatal scan room", crowd: "Partner present", distraction: "Medium", difficulty: "Intermediate",
        protocolName: "Mid-trimester checklist", size: "880 MB")
    static let handover = PSScenario(
        title: "Blue-light transfer and pre-alert", patient: "Jordan, 34 · en route to the ED", cover: "rt-04-ambulance",
        author: "Sam Whitlock", institution: "Coastal University · Paramedic Science", rating: 4.7, reviews: 129, downloads: "960",
        environment: "Ambulance", crowd: "Crew of 2", distraction: "High", difficulty: "Intermediate", protocolName: "ATMIST handover",
        size: "720 MB")
    static let resus = PSScenario(
        title: "Open fracture in resus", patient: "Jordan, 34 · trauma team activation", cover: "rt-05-resus",
        author: "Dr Lena Fischer", institution: "Eastgate Trauma Centre", rating: 4.8, reviews: 201, downloads: "1.3k",
        environment: "Resus bay", crowd: "Trauma team of 5", distraction: "High", difficulty: "Advanced", protocolName: "ABCDE primary survey",
        size: "910 MB")
    static let fitting = PSScenario(
        title: "Measure and fit the thumb splint", patient: "Alex, 28 · orthotics lab", cover: "wrist-05-orthotics-lab",
        author: "Mira Lindqvist", institution: "Northfield Orthotics Programme", rating: 4.6, reviews: 88, downloads: "740",
        environment: "Orthotics lab", crowd: "Quiet", distraction: "Low", difficulty: "Foundation", protocolName: "Fitting checklist",
        size: "590 MB")
}

// MARK: - Pieces

func psCover(_ name: String) -> Image {
    Image(uiImage: UIImage(named: "vpstudio_cover_\(name).jpg") ?? UIImage())
}

struct PSCoverImage: View {
    let name: String
    var height: CGFloat
    var body: some View {
        Color.black.frame(height: height)
            .overlay { psCover(name).resizable().scaledToFill() }
            .clipped()
    }
}

struct PSTag: View {
    let icon: String
    let text: String
    let color: Color
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
    }
}

struct PSTags: View {
    let s: PSScenario
    var all = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PSTag(icon: "mappin.and.ellipse", text: s.environment, color: .cyan)
                PSTag(icon: "person.3.fill", text: s.crowd, color: .purple)
            }
            HStack(spacing: 6) {
                PSTag(icon: "bolt.fill", text: "Distraction \(s.distraction.lowercased())", color: .pink)
                PSTag(icon: "chart.bar.fill", text: s.difficulty, color: .yellow)
                if all { PSTag(icon: "checklist", text: s.protocolName, color: .green) }
            }
            if !all { PSTag(icon: "checklist", text: s.protocolName, color: .green) }
        }
    }
}

struct PSAuthor: View {
    let s: PSScenario
    var body: some View {
        HStack(spacing: 10) {
            Text(s.author.split(separator: " ").suffix(2).compactMap(\.first).map(String.init).joined())
                .font(.caption.bold())
                .frame(width: 32, height: 32)
                .background(.indigo.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(s.author).font(.subheadline.weight(.semibold))
                    Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                }
                Text(s.institution).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct PSRating: View {
    let s: PSScenario
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
                Text(String(format: "%.1f", s.rating)).bold()
                Text("(\(s.reviews))").foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle")
                Text(s.downloads)
            }.foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

struct PSDownloadButton: View {
    var progress: Double? = nil
    var size = "1.2 GB"
    var body: some View {
        if let p = progress {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: p).stroke(.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Image(systemName: "stop.fill").font(.system(size: 9))
                }
                .frame(width: 28, height: 28)
                Text("\(Int(p * 100))%").font(.headline.monospacedDigit())
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.teal.opacity(0.2), in: Capsule())
        } else {
            Button {} label: { Label("Download · \(size)", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(.borderedProminent).tint(.teal)
        }
    }
}

// MARK: - Marketplace

struct PSMarketplace: View {
    var progress: Double?
    private let cats = ["All", "Emergency", "Trauma", "Obstetrics", "Orthopaedics", "Primary care", "Made with Studio AI"]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Marketplace").font(.largeTitle.bold())
                            Text("Scenarios built by educators worldwide. Download to your Vision Pro and play.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Search 1,240 scenarios", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .frame(width: 300, alignment: .leading)
                            .background(.thinMaterial, in: Capsule())
                    }
                    HStack(spacing: 8) {
                        ForEach(cats, id: \.self) { c in
                            Text(c).font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(c == "All" ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.thinMaterial), in: Capsule())
                                .foregroundStyle(c == "All" ? .black : .primary)
                        }
                    }
                    featured
                    Text("Top rated this week").font(.title2.bold()).padding(.top, 4)
                    HStack(alignment: .top, spacing: 16) {
                        PSCard(s: PSData.wrist)
                        PSCard(s: PSData.scan)
                        PSCard(s: PSData.handover)
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 26)
            }
            if let progress { PSDownloadSheet(progress: progress) }
        }
    }

    private var featured: some View {
        let s = PSData.featured
        return HStack(spacing: 0) {
            PSCoverImage(name: s.cover, height: 270).frame(width: 480)
                .overlay(alignment: .topLeading) {
                    Label("Featured", systemImage: "sparkles").font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.orange, in: Capsule()).padding(14)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text("3-STAGE TRAUMA JOURNEY").font(.caption.weight(.heavy)).foregroundStyle(.orange).tracking(1)
                Text(s.title).font(.title.bold())
                Text(s.patient).foregroundStyle(.secondary)
                PSAuthor(s: s)
                PSRating(s: s)
                PSTags(s: s, all: true)
                Spacer(minLength: 0)
                HStack {
                    PSDownloadButton(progress: progress, size: s.size)
                    Button {} label: { Label("Preview", systemImage: "eye") }.buttonStyle(.bordered)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 270)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
}

struct PSCard: View {
    let s: PSScenario
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PSCoverImage(name: s.cover, height: 170)
            VStack(alignment: .leading, spacing: 9) {
                Text(s.title).font(.title3.bold()).lineLimit(1)
                Text(s.patient).font(.subheadline).foregroundStyle(.secondary)
                PSAuthor(s: s)
                PSRating(s: s)
                PSTags(s: s)
                PSDownloadButton(size: s.size).padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

/// Download to the headset: what the package contains and how far it is.
struct PSDownloadSheet: View {
    let progress: Double
    private let parts: [(String, String, String, Double)] = [
        ("map", "Roadside environment", "Street, HDRI sky, crash scene props · 420 MB", 1),
        ("person.3.fill", "Crowd and bystanders", "6 voiced bystanders, partner on the phone · 96 MB", 1),
        ("person.crop.circle", "Patient persona", "Jordan, 34 · voice, pain reactions, history · 58 MB", 1),
        ("cross.case.fill", "Ambulance and resus bay", "Crew of 2, trauma team of 5 · 610 MB", 0.42),
        ("checklist", "Mark scheme", "ABCDE primary survey + ATMIST handover · 24 items", 0),
    ]

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.45))
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    PSCoverImage(name: PSData.featured.cover, height: 110).frame(width: 196)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Downloading to Vision Pro").font(.caption.weight(.heavy)).foregroundStyle(.teal).tracking(1)
                        Text(PSData.featured.title).font(.title2.bold())
                        Text("Dr Priya Raman · St Aldhelm's Teaching Hospital").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(Int(progress * 100))%").font(.system(size: 40, weight: .bold).monospacedDigit())
                        Spacer()
                        Text("816 MB of 1.2 GB · about 20 s left").foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress).tint(.teal).scaleEffect(y: 2)
                }
                VStack(spacing: 10) {
                    ForEach(parts, id: \.1) { icon, title, sub, p in
                        HStack(spacing: 14) {
                            Image(systemName: icon).font(.title3).frame(width: 34).foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title).font(.headline)
                                Text(sub).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p >= 1 {
                                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                            } else if p > 0 {
                                Text("\(Int(p * 100))%").font(.headline.monospacedDigit()).foregroundStyle(.teal)
                            } else {
                                Text("Queued").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Text("Plays fully on the headset once downloaded, offline included.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(width: 600)
            .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 32))
        }
    }
}

// MARK: - Scenario detail

struct PSDetail: View {
    let s: PSScenario

    private let mix: [(String, String, String, String, Color)] = [
        ("mappin.and.ellipse", "Environment", "Urban roadside", "then ambulance, then resus bay", .cyan),
        ("person.3.fill", "Crowd", "Busy · 6 bystanders", "a witness, the driver, a filming passer-by", .purple),
        ("bolt.fill", "Distraction", "High", "partner on the phone, traffic, sirens", .pink),
        ("cloud.drizzle.fill", "Time and weather", "17:40 · light rain", "rush hour, wet road, low sun", .blue),
        ("person.crop.circle.fill", "Patient persona", "Jordan, 34, cyclist", "frightened, in pain, penicillin allergy", .orange),
        ("cross.case.fill", "Team", "2 paramedics, trauma team", "they ask, question and wait for you", .mint),
        ("chart.bar.fill", "Difficulty", "Advanced", "no prompts, deteriorates if missed", .yellow),
        ("checklist", "Assessment protocol", "ABCDE + ATMIST", "24 items, compared to your notebook", .green),
    ]
    private let marks = [
        "Scene safe, catastrophic haemorrhage controlled",
        "Airway and C-spine assessed, breathing and circulation observed",
        "Neurovascular status checked before and after splinting",
        "Analgesia given, allergy asked before antibiotics",
        "ATMIST pre-alert and handover to the trauma team",
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                PSCoverImage(name: s.cover, height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
                Text(s.title).font(.title.bold())
                PSAuthor(s: s)
                PSRating(s: s)
                Text("A cyclist is knocked off by a car at rush hour. Make the scene safe, stop the bleeding and assess Jordan while bystanders crowd in, then hand over in the ambulance and in resus.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label("Downloaded", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                    Spacer()
                    Button {} label: { Label("Remix in Studio", systemImage: "slider.horizontal.3") }.buttonStyle(.bordered)
                    Button {} label: { Label("Play", systemImage: "play.fill").font(.headline).padding(.horizontal, 10) }
                        .buttonStyle(.borderedProminent).tint(.teal)
                }
                Text("JOURNEY").font(.caption.weight(.heavy)).foregroundStyle(.secondary).tracking(1).padding(.top, 4)
                HStack(spacing: 8) {
                    ForEach(Array(zip(["rt-01-roadside", "rt-04-ambulance", "rt-05-resus"], s.stages).enumerated()), id: \.offset) { i, st in
                        VStack(alignment: .leading, spacing: 4) {
                            PSCoverImage(name: st.0, height: 72).clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("\(i + 1) · \(st.1)").font(.caption.weight(.semibold))
                        }
                        if i < 2 { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    }
                }
            }
            .frame(width: 470)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Scenario mix").font(.title2.bold())
                    Spacer()
                    PSTag(icon: "wand.and.stars", text: "Authored with Studio AI", color: .indigo)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(mix, id: \.1) { icon, k, v, sub, c in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon).font(.title3).foregroundStyle(c)
                                .frame(width: 40, height: 40).background(c.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(k.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                Text(v).font(.headline).lineLimit(1)
                                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("How you are scored").font(.headline)
                        Spacer()
                        Text("24 items · pass 18").font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    }
                    ForEach(marks, id: \.self) { m in
                        Label(m, systemImage: "checkmark.square").font(.callout)
                    }
                }
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 26)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Library

struct PSLibrary: View {
    var body: some View {
        let s = PSData.featured
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Library").font(.largeTitle.bold())
                        Text("On this Vision Pro · 4 scenarios · 3.5 GB").foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(["All", "Downloaded", "Assigned", "Mine"], id: \.self) { t in
                            Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 7)
                                .background(t == "All" ? AnyShapeStyle(.white.opacity(0.25)) : AnyShapeStyle(.clear), in: Capsule())
                        }
                    }
                    .padding(4).background(.thinMaterial, in: Capsule())
                }
                HStack(spacing: 0) {
                    PSCoverImage(name: s.cover, height: 290).frame(width: 516)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Ready to play", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(.green)
                            .padding(.horizontal, 12).padding(.vertical, 6).background(.green.opacity(0.2), in: Capsule())
                        Text(s.title).font(.title.bold())
                        Text("Community scenario · downloaded just now · \(s.size) · plays offline")
                            .font(.subheadline).foregroundStyle(.secondary)
                        PSAuthor(s: s)
                        PSTags(s: s, all: true)
                        Spacer(minLength: 0)
                        HStack(spacing: 12) {
                            Button {} label: {
                                Label("Play", systemImage: "play.fill").font(.title3.bold()).padding(.horizontal, 22).padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent).tint(.teal)
                            Text("about 25 min · 3 stages").foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 290)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 28))

                Text("Also on this headset").font(.title2.bold()).padding(.top, 4)
                HStack(spacing: 16) {
                    row(PSData.wrist, "Played · 86%", "checkmark.seal.fill", .green)
                    row(PSData.scan, "Assigned · due Friday", "calendar", .orange)
                    row(PSData.resus, "Update available", "arrow.triangle.2.circlepath", .blue)
                }
            }
            .padding(.horizontal, 32).padding(.vertical, 26)
        }
    }

    private func row(_ s: PSScenario, _ status: String, _ icon: String, _ c: Color) -> some View {
        HStack(spacing: 12) {
            PSCoverImage(name: s.cover, height: 76).frame(width: 120).clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(s.title).font(.headline).lineLimit(2)
                Label(status, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(c)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.teal)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
