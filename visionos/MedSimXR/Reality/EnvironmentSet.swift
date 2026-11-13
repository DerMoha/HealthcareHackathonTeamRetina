import AVFoundation
import RealityKit
import UIKit

/// The place the encounter happens in, built in code (no art assets): a clinic room, an antenatal
/// scan room, a roadside, the back of an ambulance or a resus bay, each with a sound loop.
/// It lives in avatar space (patient at the origin facing +Z, wearer about 1.7 m in front), so it moves
/// with the patient when the learner re-centres. Purely decorative: nothing here is collidable, and
/// no screen shows clinical values.
@MainActor
final class EnvironmentSet {
    enum Kind: String, Equatable {
        case clinic, antenatal, roadside, roadsideNight, ambulance, traumaBay

        /// First text that names a place wins, so pass the most specific first (journey stage, Studio
        /// environment, case setting). Nothing recognised: the clinic room.
        static func resolve(_ texts: [String?], night: Bool = false) -> Kind {
            for case let text? in texts {
                let t = text.lowercased()
                if t.contains("road") { return night ? .roadsideNight : .roadside }
                if t.contains("ambulance") { return .ambulance }
                if t.contains("trauma") || t.contains("emergency") || t.contains("resus") { return .traumaBay }
                if t.contains("antenatal") || t.contains("obstetric") || t.contains("maternity") { return .antenatal }
                if t.contains("clinic") || t.contains("surgery") || t.contains("practice") { return .clinic }
            }
            return .clinic
        }

        /// Places with their own seat for the patient (instead of the clinic stool).
        var bringsSeat: Bool { self != .clinic && self != .antenatal }
    }

    let root = Entity()
    private(set) var kind: Kind?
    private var seat: Float = 0
    private var ambience: AVAudioPlayer?
    private var blinkers: [Task<Void, Never>] = []

    func install(on avatar: PatientAvatar) {
        root.name = "environment_set"
        avatar.root.addChild(root)
    }

    /// `seat`: the patient's seat height (avatar space), for the places that bring their own seat.
    func show(_ kind: Kind, seat: Float) {
        guard kind != self.kind || seat != self.seat else { return }
        let sound = kind != self.kind
        self.kind = kind; self.seat = seat
        blinkers.forEach { $0.cancel() }; blinkers = []
        Array(root.children).forEach { $0.removeFromParent() }
        let set = Entity()
        switch kind {
        case .clinic: buildClinic(set, antenatal: false)
        case .antenatal: buildClinic(set, antenatal: true)
        case .roadside: buildRoadside(set, night: false)
        case .roadsideNight: buildRoadside(set, night: true)
        case .ambulance: buildAmbulance(set)
        case .traumaBay: buildTraumaBay(set)
        }
        if kind.bringsSeat { buildSeat(set, kind) }
        root.addChild(set)
        if sound { playAmbience(kind) }
        SmokeLog.mark("environment set=\(kind.rawValue) parts=\(set.children.count) sound=\(ambience?.isPlaying ?? false)")
    }

    func stop() {
        ambience?.stop(); ambience = nil
        blinkers.forEach { $0.cancel() }; blinkers = []
        kind = nil // the next show() rebuilds and restarts the sound
    }

    /// What the patient sits on outside the clinic: a response case at the roadside, the stretcher in
    /// the ambulance, the trolley in resus. Across the patient's hips, just behind the origin.
    private func buildSeat(_ e: Entity, _ kind: Kind) {
        let steel = Self.mat(UIColor(white: 0.75, alpha: 1), metal: true)
        switch kind {
        case .roadside, .roadsideNight:
            box(e, [0.75, seat - 0.03, 0.42], Self.mat(UIColor(red: 0.95, green: 0.5, blue: 0.1, alpha: 1), rough: 0.5), at: [0, (seat - 0.03) / 2, -0.12])
            box(e, [0.77, 0.03, 0.44], Self.mat(UIColor(white: 0.25, alpha: 1)), at: [0, seat - 0.015, -0.12])
            box(e, [0.5, 0.04, 0.44], Self.mat(UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)), at: [0, seat * 0.6, -0.11])
        case .ambulance, .traumaBay:
            let mattress = kind == .ambulance ? UIColor(red: 0.95, green: 0.55, blue: 0.12, alpha: 1) : UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1)
            box(e, [1.9, 0.12, 0.66], Self.mat(mattress, rough: 0.6), at: [0, seat - 0.06, -0.12])
            box(e, [1.9, 0.05, 0.7], steel, at: [0, seat - 0.15, -0.12])
            box(e, [0.3, 0.1, 0.5], Self.mat(UIColor(white: 0.97, alpha: 1)), at: [-0.75, seat + 0.03, -0.12]) // pillow
            for x: Float in [-0.8, 0.8] {
                cylinder(e, height: seat - 0.18, radius: 0.025, steel, at: [x, (seat - 0.18) / 2 + 0.05, -0.12])
                sphere(e, radius: 0.05, Self.mat(UIColor(white: 0.2, alpha: 1)), at: [x, 0.05, -0.12])
            }
        case .clinic, .antenatal: break
        }
    }

    // MARK: Clinic / antenatal room

    private func buildClinic(_ e: Entity, antenatal: Bool) {
        let w: Float = 4, back: Float = -4.5, front: Float = 4.5, h: Float = 2.9
        let wall = antenatal ? UIColor(red: 0.93, green: 0.86, blue: 0.86, alpha: 1) : UIColor(red: 0.93, green: 0.92, blue: 0.87, alpha: 1)
        room(e, w: w, back: back, front: front, h: h, wall: Self.mat(wall),
             floor: Self.tex("floor_wood", fallback: .brown) { Self.drawPlanks($0, $1) },
             ceiling: Self.glow(UIColor(white: 0.78, alpha: 1)))
        // Skirting and a dado rail, so the walls read as a room and not a box.
        for (x, z, sx, sz) in [(Float(0), back + 0.04, 2 * w, Float(0.02)), (-w + 0.04, 0, 0.02, front - back), (w - 0.04, 0, 0.02, front - back)] {
            box(e, [sx, 0.1, sz], Self.mat(UIColor(white: 0.55, alpha: 1)), at: [x, 0.05, z])
            box(e, [sx, 0.04, sz], Self.mat(antenatal ? UIColor(red: 0.7, green: 0.45, blue: 0.5, alpha: 1) : UIColor(red: 0.35, green: 0.55, blue: 0.6, alpha: 1)), at: [x, 1.0, z])
        }
        ceilingLights(e, w: w, back: back, front: front, h: h, dim: antenatal)
        light(e, at: [0, h - 0.3, 0.5], intensity: antenatal ? 9000 : 16000, color: UIColor(red: 1, green: 0.96, blue: 0.9, alpha: 1))

        // Window on the left wall with a view out.
        panel(e, "window_view", size: [2.2, 1.3], at: [-w + 0.05, 1.6, -1.6], yaw: .pi / 2, unlit: true) { Self.drawWindow($0, $1) }
        box(e, [0.04, 1.42, 2.32], Self.mat(.white), at: [-w + 0.01, 1.6, -1.6]) // frame, behind the view
        // Desk with a computer, chair, in the far right corner.
        let desk = UIColor(red: 0.62, green: 0.47, blue: 0.33, alpha: 1)
        box(e, [1.6, 0.04, 0.75], Self.mat(desk), at: [2.9, 0.74, -3.8])
        for x: Float in [2.15, 3.65] { box(e, [0.04, 0.72, 0.7], Self.mat(desk), at: [x, 0.36, -3.8]) }
        box(e, [0.55, 0.36, 0.03], Self.mat(UIColor(white: 0.1, alpha: 1)), at: [2.8, 1.02, -4.0])
        panel(e, "screen_desktop", size: [0.51, 0.32], at: [2.8, 1.02, -3.98], unlit: true) { Self.drawDesktop($0, $1) }
        box(e, [0.45, 0.02, 0.15], Self.mat(UIColor(white: 0.2, alpha: 1)), at: [2.8, 0.77, -3.6])
        chair(e, at: [2.8, 0, -3.1], color: UIColor(red: 0.2, green: 0.3, blue: 0.45, alpha: 1))
        // Sink unit and mirror on the back wall, hand gel beside it.
        box(e, [1.2, 0.88, 0.55], Self.mat(UIColor(white: 0.92, alpha: 1)), at: [-2.4, 0.44, back + 0.3])
        box(e, [0.5, 0.04, 0.4], Self.mat(UIColor(white: 0.8, alpha: 1), rough: 0.2, metal: true), at: [-2.4, 0.9, back + 0.3])
        box(e, [0.6, 0.7, 0.02], Self.mat(UIColor(red: 0.75, green: 0.85, blue: 0.9, alpha: 1), rough: 0.05, metal: true), at: [-2.4, 1.55, back + 0.04])
        box(e, [0.1, 0.2, 0.08], Self.mat(.white), at: [-1.6, 1.3, back + 0.06])
        // Wall cupboards above the desk side, a door on the right wall.
        box(e, [1.4, 0.7, 0.35], Self.mat(UIColor(white: 0.88, alpha: 1)), at: [0.6, 1.95, back + 0.2])
        box(e, [0.06, 2.1, 1.0], Self.mat(UIColor(red: 0.55, green: 0.4, blue: 0.28, alpha: 1)), at: [w - 0.03, 1.05, 2.4])
        box(e, [0.06, 0.04, 0.14], Self.mat(.lightGray, rough: 0.3, metal: true), at: [w - 0.09, 1.0, 2.0])
        // Privacy curtain on a rail, pulled to the side behind the patient.
        box(e, [0.03, 0.03, 3.0], Self.mat(.lightGray, metal: true), at: [-2.0, 2.45, -1.0])
        box(e, [0.04, 2.2, 0.9], Self.mat(antenatal ? UIColor(red: 0.75, green: 0.6, blue: 0.8, alpha: 1) : UIColor(red: 0.55, green: 0.75, blue: 0.8, alpha: 1)),
            at: [-2.0, 1.33, -2.1])
        // Posters on the back wall.
        if antenatal {
            panel(e, "poster_antenatal", size: [0.6, 0.85], at: [1.9, 1.6, back + 0.04]) {
                Self.drawPoster($0, $1, title: "Your pregnancy", lines: ["Antenatal care", "Ask us anything", "Scan room 2"], tint: .systemPink)
            }
            plant(e, at: [3.4, 0, 3.6])
        } else {
            panel(e, "poster_hands", size: [0.6, 0.85], at: [1.9, 1.6, back + 0.04]) {
                Self.drawPoster($0, $1, title: "Clean hands", lines: ["save lives", "Before and after", "every patient"], tint: .systemTeal)
            }
            plant(e, at: [-3.4, 0, 3.6])
        }
        clock(e, at: [-0.4, 2.25, back + 0.04])
    }

    // MARK: Resus / trauma bay

    private func buildTraumaBay(_ e: Entity) {
        let w: Float = 4, back: Float = -4.5, front: Float = 4.5, h: Float = 3.0
        room(e, w: w, back: back, front: front, h: h, wall: Self.mat(UIColor(red: 0.8, green: 0.88, blue: 0.88, alpha: 1)),
             floor: Self.tex("floor_tiles", fallback: .lightGray) { Self.drawTiles($0, $1, a: UIColor(white: 0.82, alpha: 1), b: UIColor(white: 0.74, alpha: 1), n: 18) },
             ceiling: Self.glow(UIColor(white: 0.8, alpha: 1)))
        // Lower walls in wipeable blue, a yellow bay line on the floor.
        for (x, z, sx, sz) in [(Float(0), back + 0.04, 2 * w, Float(0.02)), (-w + 0.04, 0, 0.02, front - back), (w - 0.04, 0, 0.02, front - back)] {
            box(e, [sx, 1.1, sz], Self.mat(UIColor(red: 0.3, green: 0.5, blue: 0.65, alpha: 1)), at: [x, 0.55, z])
        }
        for (x, z, sx, sz) in [(Float(0), Float(-2.2), Float(4.4), Float(0.08)), (-2.2, -0.1, 0.08, 4.2), (2.2, -0.1, 0.08, 4.2)] {
            box(e, [sx, 0.004, sz], Self.glow(UIColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1)), at: [x, 0.002, z])
        }
        ceilingLights(e, w: w, back: back, front: front, h: h, dim: false)
        light(e, at: [0, h - 0.4, 0], intensity: 24000, color: .white)
        // Surgical lamp on a ceiling arm above the patient.
        box(e, [0.06, 0.5, 0.06], Self.mat(UIColor(white: 0.85, alpha: 1), metal: true), at: [0.5, h - 0.25, 0.3])
        box(e, [0.9, 0.05, 0.05], Self.mat(UIColor(white: 0.85, alpha: 1), metal: true), at: [0.5, h - 0.5, 0.3])
        cylinder(e, height: 0.1, radius: 0.32, Self.mat(UIColor(white: 0.9, alpha: 1)), at: [0.9, h - 0.6, 0.3])
        cylinder(e, height: 0.01, radius: 0.27, Self.glow(UIColor(red: 1, green: 0.98, blue: 0.9, alpha: 1)), at: [0.9, h - 0.656, 0.3])
        light(e, at: [0.9, h - 0.8, 0.3], intensity: 12000, color: UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), radius: 4)
        // Big wall monitor and medical gas panel on the back wall.
        box(e, [1.6, 0.95, 0.06], Self.mat(UIColor(white: 0.08, alpha: 1)), at: [0, 2.1, back + 0.05])
        panel(e, "screen_ecg", size: [1.5, 0.85], at: [0, 2.1, back + 0.085], unlit: true) { Self.drawTrace($0, $1) }
        box(e, [2.4, 0.22, 0.1], Self.mat(UIColor(white: 0.9, alpha: 1)), at: [0, 1.45, back + 0.06])
        for (i, c) in [UIColor.white, .systemGreen, .systemYellow, .white, .systemGreen].enumerated() {
            cylinder(e, height: 0.04, radius: 0.04, Self.mat(c), at: [-0.9 + Float(i) * 0.45, 1.45, back + 0.13], axis: .x)
        }
        panel(e, "sign_resus", size: [0.9, 0.3], at: [-2.6, 2.55, back + 0.05], unlit: true) { Self.drawSign($0, $1, "RESUS 2", bg: .systemRed) }
        clock(e, at: [2.6, 2.4, back + 0.05])
        // Monitor on a pole beside the head end, red crash trolley, oxygen cylinder.
        cylinder(e, height: 1.4, radius: 0.025, Self.mat(.lightGray, metal: true), at: [-1.7, 0.7, -1.3])
        box(e, [0.42, 0.32, 0.12], Self.mat(UIColor(white: 0.15, alpha: 1)), at: [-1.7, 1.5, -1.3], yaw: 0.6)
        panel(e, "screen_ecg_small", size: [0.38, 0.28], at: [-1.665, 1.5, -1.25], yaw: 0.6, unlit: true) { Self.drawTrace($0, $1) }
        trolley(e, at: [2.8, 0, -2.4], color: UIColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1), yaw: -0.4)
        cylinder(e, height: 1.0, radius: 0.09, Self.mat(UIColor(red: 0.15, green: 0.5, blue: 0.25, alpha: 1)), at: [-3.6, 0.5, -4.1])
        // Curtains closing the bay on both sides, cupboards along the back.
        for x: Float in [-3.3, 3.3] {
            box(e, [0.04, 2.3, 2.6], Self.mat(UIColor(red: 0.45, green: 0.62, blue: 0.75, alpha: 1)), at: [x, 1.35, 1.6])
            box(e, [0.03, 0.03, 4.0], Self.mat(.lightGray, metal: true), at: [x, 2.55, 1.0])
        }
        for i in 0..<2 { box(e, [0.75, 0.9, 0.5], Self.mat(UIColor(white: 0.9, alpha: 1)), at: [1.6 + Float(i) * 0.8, 0.45, back + 0.28]) }
        box(e, [1.6, 0.04, 0.55], Self.mat(UIColor(white: 0.7, alpha: 1), rough: 0.3, metal: true), at: [2.0, 0.92, back + 0.3])
    }

    // MARK: Back of the ambulance

    private func buildAmbulance(_ e: Entity) {
        // Taller than a real ambulance so the place signs above the team stay visible.
        let w: Float = 1.25, back: Float = -2.3, front: Float = 2.6, h: Float = 2.45
        room(e, w: w, back: back, front: front, h: h, wall: Self.mat(UIColor(white: 0.95, alpha: 1)),
             floor: Self.tex("floor_rubber", fallback: .darkGray) { Self.drawTiles($0, $1, a: UIColor(white: 0.3, alpha: 1), b: UIColor(white: 0.27, alpha: 1), n: 10) },
             ceiling: Self.glow(UIColor(white: 0.8, alpha: 1)))
        // Strip lights and grab rail along the ceiling.
        for x: Float in [-0.6, 0.6] { box(e, [0.14, 0.02, 3.8], Self.glow(UIColor(red: 0.95, green: 0.97, blue: 1, alpha: 1)), at: [x, h - 0.02, 0.15]) }
        cylinder(e, height: 3.6, radius: 0.018, Self.mat(UIColor(white: 0.75, alpha: 1), metal: true), at: [0.45, h - 0.18, 0.15], axis: .z)
        light(e, at: [0, h - 0.3, 0], intensity: 14000, color: .white, radius: 5)
        // Wall lockers with bins, front part of the cabin only so the team has room.
        for side: Float in [-1, 1] {
            box(e, [0.3, 0.75, 1.3], Self.mat(UIColor(white: 0.88, alpha: 1)), at: [side * (w - 0.16), 1.85, -1.55])
            for i in 0..<3 {
                box(e, [0.02, 0.18, 0.38], Self.mat([UIColor.systemBlue, .systemOrange, .systemGreen][i]),
                    at: [side * (w - 0.32), 1.65, -2.0 + Float(i) * 0.43])
            }
        }
        // Bench seat along the left wall near the doors, a seat belt stripe.
        box(e, [0.45, 0.45, 1.5], Self.mat(UIColor(red: 0.2, green: 0.3, blue: 0.55, alpha: 1)), at: [-w + 0.23, 0.23, 1.5])
        box(e, [0.08, 0.6, 1.5], Self.mat(UIColor(red: 0.2, green: 0.3, blue: 0.55, alpha: 1)), at: [-w + 0.05, 0.75, 1.5])
        // Front bulkhead: window into the cab, monitor/defibrillator, oxygen.
        panel(e, "cab_window", size: [0.8, 0.35], at: [0, 1.75, back + 0.04], unlit: true) { Self.drawCabWindow($0, $1) }
        box(e, [0.5, 0.36, 0.18], Self.mat(UIColor(white: 0.2, alpha: 1)), at: [0.75, 1.3, back + 0.12])
        panel(e, "screen_ecg_amb", size: [0.32, 0.22], at: [0.7, 1.32, back + 0.215], unlit: true) { Self.drawTrace($0, $1) }
        cylinder(e, height: 0.9, radius: 0.08, Self.mat(UIColor(red: 0.15, green: 0.5, blue: 0.25, alpha: 1)), at: [-0.95, 0.65, back + 0.15])
        // Rear doors with windows and the road falling away behind.
        box(e, [0.02, 2.0, 0.04], Self.mat(UIColor(white: 0.7, alpha: 1)), at: [0, 1.0, front - 0.05])
        for x: Float in [-0.6, 0.6] {
            panel(e, "rear_window", size: [0.6, 0.5], at: [x, 1.55, front - 0.04], yaw: .pi, unlit: true) { Self.drawRearWindow($0, $1) }
        }
        // Chevron hazard stripes at the door sill.
        panel(e, "sill_chevrons", size: [2.4, 0.12], at: [0, 0.06, front - 0.04], yaw: .pi) { Self.drawChevrons($0, $1) }
    }

    // MARK: Roadside

    private func buildRoadside(_ e: Entity, night: Bool) {
        // Sky: an inside-out sphere, darkest at the poles so its texture orientation does not matter.
        let skyTex = Self.cachedTexture(night ? "sky_night" : "sky_day", size: [64, 512]) { ctx, size in
            let top = night ? UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1) : UIColor(red: 0.3, green: 0.52, blue: 0.85, alpha: 1)
            let horizon = night ? UIColor(red: 0.12, green: 0.1, blue: 0.16, alpha: 1) : UIColor(red: 0.82, green: 0.88, blue: 0.95, alpha: 1)
            let colors = [top.cgColor, horizon.cgColor, top.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        let sky = ModelEntity(mesh: .generateSphere(radius: 60), materials: [Self.unlit(skyTex, fallback: night ? .black : .systemBlue)])
        sky.scale = [-1, 1, 1]
        e.addChild(sky)
        let grass = night ? UIColor(red: 0.06, green: 0.1, blue: 0.06, alpha: 1) : UIColor(red: 0.33, green: 0.5, blue: 0.24, alpha: 1)
        plane(e, [140, 140], Self.mat(grass), at: [0, -0.01, 0])
        // Road running away from the wearer, pavements either side.
        plane(e, [7, 140], Self.tex(night ? "asphalt_wet" : "asphalt", fallback: .darkGray) { Self.drawAsphalt($0, $1, wet: night) }, at: [0, 0, 0])
        for i in -30..<30 where i % 2 == 0 {
            plane(e, [0.14, 3], Self.glow(UIColor(white: night ? 0.6 : 0.95, alpha: 1)), at: [-1.6, 0.003, Float(i) * 3])
        }
        for side: Float in [-1, 1] {
            box(e, [0.15, 0.13, 140], Self.mat(UIColor(white: 0.6, alpha: 1)), at: [side * 3.57, 0.065, 0])
            box(e, [2.2, 0.12, 140], Self.mat(UIColor(white: night ? 0.3 : 0.62, alpha: 1)), at: [side * 4.75, 0.06, 0])
            box(e, [0.1, 0.004, 140], Self.glow(night ? UIColor(white: 0.55, alpha: 1) : .white), at: [side * 3.3, 0.003, 0])
        }
        // Street lamps along the pavement (lit at night), trees and buildings beyond.
        for i in -3...3 {
            let z = Float(i) * 11 - 2
            let side: Float = i % 2 == 0 ? 1 : -1
            cylinder(e, height: 6, radius: 0.07, Self.mat(UIColor(white: 0.35, alpha: 1), metal: true), at: [side * 4.2, 3, z])
            box(e, [1.0, 0.06, 0.12], Self.mat(UIColor(white: 0.35, alpha: 1), metal: true), at: [side * 3.75, 5.95, z])
            box(e, [0.45, 0.06, 0.22], night ? Self.glow(UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1)) : Self.mat(UIColor(white: 0.8, alpha: 1)),
                at: [side * 3.4, 5.9, z])
            if night && abs(i) <= 1 {
                light(e, at: [side * 3.4, 5.6, z], intensity: 60000, color: UIColor(red: 1, green: 0.8, blue: 0.55, alpha: 1), radius: 14)
            }
        }
        for i in 0..<16 {
            let side: Float = i % 2 == 0 ? 1 : -1
            tree(e, at: [side * (7.5 + Float(i % 3)), 0, -40 + Float(i) * 5.5], night: night)
        }
        for i in 0..<10 {
            let side: Float = i % 2 == 0 ? 1 : -1
            let height = 6 + Float((i * 7) % 5) * 2.2
            let building = UIColor(white: night ? 0.12 : 0.55 + CGFloat(i % 3) * 0.08, alpha: 1)
            box(e, [7, height, 6], Self.mat(building), at: [side * 16, height / 2, -45 + Float(i) * 10])
        }
        // Outdoors nothing else lights the lit materials: a sun by day, faint moonlight at night.
        let sun = Entity()
        sun.components.set(DirectionalLightComponent(color: night ? UIColor(red: 0.6, green: 0.7, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1),
                                                     intensity: night ? 400 : 6000))
        sun.orientation = simd_quatf(angle: -0.9, axis: [1, 0, 0]) * simd_quatf(angle: 0.5, axis: [0, 1, 0])
        e.addChild(sun)

        // The collision: a car stopped askew ahead right, a bicycle on its side, cones around.
        let crashed = car(e, at: [2.1, 0, -3.4], yaw: 0.45, color: UIColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1), lightsOn: night)
        // Bonnet pushed up, cracked windscreen, hazard lights on.
        let paint = Self.mat(UIColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1), rough: 0.25, metal: true)
        box(crashed, [1.7, 0.07, 0.95], paint, at: [0, 0.95, -1.6]).orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
        box(crashed, [1.3, 0.4, 0.03], Self.mat(UIColor(white: 0.85, alpha: 1)), at: [0.1, 1.12, -1.32])
        for x: Float in [-0.8, 0.8] { box(crashed, [0.2, 0.08, 0.12], Self.glow(.systemOrange), at: [x, 0.75, 2.17]) }
        bicycle(e, at: [-0.9, 0, -2.0], yaw: 0.9)
        // The cyclist's helmet and debris on the road.
        let helmet = ModelEntity(mesh: .generateSphere(radius: 0.14), materials: [Self.mat(UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1), rough: 0.3)])
        helmet.position = [0.3, 0.08, -1.3]; helmet.scale = [1, 0.65, 1.3]
        e.addChild(helmet)
        for (i, p) in [SIMD3<Float>(0.9, 0.01, -2.4), [1.2, 0.01, -2.8], [0.6, 0.01, -3.0], [1.5, 0.01, -2.2]].enumerated() {
            box(e, [0.12 + 0.04 * Float(i % 2), 0.015, 0.08], Self.mat(i % 2 == 0 ? UIColor(white: 0.85, alpha: 1) : .systemRed), at: p, yaw: Float(i))
        }
        for (x, z) in [(Float(-2.6), Float(-0.5)), (-2.6, 1.5), (-2.4, -3.5), (0.4, -5.6), (-1.0, -6.0)] { cone(e, at: [x, 0, z]) }
        // Police car with flashing blue lights further back, the ambulance behind the wearer.
        let police = car(e, at: [-1.9, 0, -8.5], yaw: -0.2, color: UIColor(white: 0.95, alpha: 1), lightsOn: true)
        blueLights(on: police, height: 1.5)
        ambulanceOutside(e, at: [1.6, 0, 6.2])
    }

    // MARK: Building blocks

    private func room(_ e: Entity, w: Float, back: Float, front: Float, h: Float, wall: RealityKit.Material,
                      floor: RealityKit.Material, ceiling: RealityKit.Material) {
        let depth = front - back, mid = (front + back) / 2
        plane(e, [2 * w, depth], floor, at: [0, 0, mid])
        box(e, [2 * w, h, 0.06], wall, at: [0, h / 2, back - 0.03])
        box(e, [2 * w, h, 0.06], wall, at: [0, h / 2, front + 0.03])
        box(e, [0.06, h, depth], wall, at: [-w - 0.03, h / 2, mid])
        box(e, [0.06, h, depth], wall, at: [w + 0.03, h / 2, mid])
        box(e, [2 * w, 0.06, depth], ceiling, at: [0, h + 0.03, mid])
    }

    private func ceilingLights(_ e: Entity, w: Float, back: Float, front: Float, h: Float, dim: Bool) {
        let glow = Self.glow(dim ? UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1) : UIColor(red: 0.98, green: 0.98, blue: 1, alpha: 1))
        var z = back + 1.2
        while z < front - 0.8 {
            for x in stride(from: -w + 1.2, through: w - 1.2, by: 2.4) { box(e, [0.6, 0.02, 1.2], glow, at: [x, h - 0.01, z]) }
            z += 2.6
        }
    }

    private func light(_ e: Entity, at p: SIMD3<Float>, intensity: Float, color: UIColor, radius: Float = 9) {
        let l = Entity()
        l.components.set(PointLightComponent(color: color, intensity: intensity, attenuationRadius: radius))
        l.position = p
        e.addChild(l)
    }

    private func chair(_ e: Entity, at p: SIMD3<Float>, color: UIColor) {
        box(e, [0.46, 0.06, 0.46], Self.mat(color), at: p + [0, 0.46, 0])
        box(e, [0.46, 0.45, 0.05], Self.mat(color), at: p + [0, 0.72, 0.22])
        cylinder(e, height: 0.43, radius: 0.025, Self.mat(.darkGray, metal: true), at: p + [0, 0.22, 0])
        cylinder(e, height: 0.03, radius: 0.28, Self.mat(.darkGray, metal: true), at: p + [0, 0.02, 0])
    }

    private func trolley(_ e: Entity, at p: SIMD3<Float>, color: UIColor, yaw: Float) {
        let t = Entity(); t.position = p; t.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); e.addChild(t)
        box(t, [0.75, 0.95, 0.55], Self.mat(color, rough: 0.4), at: [0, 0.55, 0])
        for i in 0..<4 { box(t, [0.7, 0.01, 0.01], Self.mat(UIColor(white: 0.2, alpha: 1)), at: [0, 0.3 + Float(i) * 0.2, 0.28]) }
        box(t, [0.8, 0.03, 0.6], Self.mat(UIColor(white: 0.2, alpha: 1)), at: [0, 1.04, 0])
        box(t, [0.32, 0.22, 0.25], Self.mat(UIColor(red: 0.95, green: 0.8, blue: 0.1, alpha: 1)), at: [0.1, 1.16, 0])
        for (x, z) in [(Float(-0.3), Float(-0.22)), (0.3, -0.22), (-0.3, 0.22), (0.3, 0.22)] {
            cylinder(t, height: 0.04, radius: 0.04, Self.mat(.black), at: [x, 0.04, z], axis: .x)
        }
    }

    private func plant(_ e: Entity, at p: SIMD3<Float>) {
        cylinder(e, height: 0.4, radius: 0.18, Self.mat(UIColor(red: 0.7, green: 0.4, blue: 0.25, alpha: 1)), at: p + [0, 0.2, 0])
        for (i, o) in [SIMD3<Float>(0, 0.7, 0), [0.12, 0.6, 0.05], [-0.1, 0.62, -0.06], [0.02, 0.85, 0.08]].enumerated() {
            sphere(e, radius: 0.2 - Float(i) * 0.02, Self.mat(UIColor(red: 0.2, green: 0.5 + CGFloat(i) * 0.05, blue: 0.22, alpha: 1)), at: p + o)
        }
    }

    private func clock(_ e: Entity, at p: SIMD3<Float>) {
        panel(e, "clock", size: [0.36, 0.36], at: p) { ctx, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 6, dy: 6)
            ctx.setFillColor(UIColor.white.cgColor); ctx.fillEllipse(in: r)
            ctx.setStrokeColor(UIColor.darkGray.cgColor); ctx.setLineWidth(10); ctx.strokeEllipse(in: r)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<12 {
                let a = CGFloat(i) * .pi / 6
                ctx.move(to: CGPoint(x: c.x + sin(a) * r.width * 0.4, y: c.y - cos(a) * r.width * 0.4))
                ctx.addLine(to: CGPoint(x: c.x + sin(a) * r.width * 0.46, y: c.y - cos(a) * r.width * 0.46))
            }
            ctx.setLineWidth(6); ctx.strokePath()
            ctx.setStrokeColor(UIColor.black.cgColor); ctx.setLineWidth(9)
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x + r.width * 0.2, y: c.y - r.width * 0.12))
            ctx.move(to: c); ctx.addLine(to: CGPoint(x: c.x - r.width * 0.05, y: c.y - r.width * 0.36))
            ctx.strokePath()
        }
    }

    @discardableResult
    private func car(_ e: Entity, at p: SIMD3<Float>, yaw: Float, color: UIColor, lightsOn: Bool) -> Entity {
        let c = Entity(); c.position = p; c.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); e.addChild(c)
        let paint = Self.mat(color, rough: 0.25, metal: true)
        box(c, [1.8, 0.62, 4.3], paint, at: [0, 0.55, 0])
        box(c, [1.62, 0.55, 2.2], Self.mat(UIColor(red: 0.1, green: 0.13, blue: 0.16, alpha: 1), rough: 0.05, metal: true), at: [0, 1.12, -0.2])
        box(c, [1.66, 0.05, 2.0], paint, at: [0, 1.41, -0.2])
        for (x, z) in [(Float(-0.86), Float(-1.35)), (0.86, -1.35), (-0.86, 1.35), (0.86, 1.35)] {
            cylinder(c, height: 0.24, radius: 0.33, Self.mat(UIColor(white: 0.08, alpha: 1)), at: [x, 0.33, z], axis: .x)
        }
        for x: Float in [-0.6, 0.6] {
            box(c, [0.35, 0.12, 0.03], lightsOn ? Self.glow(UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)) : Self.mat(.white),
                at: [x, 0.65, -2.16])
            box(c, [0.35, 0.1, 0.03], Self.glow(UIColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1)), at: [x, 0.68, 2.16])
        }
        box(c, [1.85, 0.16, 0.15], Self.mat(UIColor(white: 0.15, alpha: 1)), at: [0, 0.35, -2.18])
        return c
    }

    /// Police light bar: two halves flashing in turn.
    private func blueLights(on car: Entity, height: Float) {
        box(car, [1.2, 0.1, 0.25], Self.mat(UIColor(white: 0.2, alpha: 1)), at: [0, height - 0.02, -0.2])
        let lit = Self.glow(UIColor(red: 0.15, green: 0.35, blue: 1, alpha: 1)), off = Self.mat(UIColor(red: 0.05, green: 0.1, blue: 0.35, alpha: 1))
        var halves: [(on: Entity, off: Entity)] = []
        for x: Float in [-0.3, 0.3] {
            halves.append((box(car, [0.55, 0.12, 0.22], lit, at: [x, height + 0.06, -0.2]),
                           box(car, [0.54, 0.11, 0.21], off, at: [x, height + 0.06, -0.2])))
        }
        let glowLight = Entity()
        glowLight.components.set(PointLightComponent(color: .systemBlue, intensity: 30000, attenuationRadius: 10))
        glowLight.position = [0, height + 0.4, -0.2]
        car.addChild(glowLight)
        blinkers.append(Task { [halves] in
            var phase = 0
            while !Task.isCancelled {
                for (i, h) in halves.enumerated() { h.on.isEnabled = (phase + i) % 2 == 0; h.off.isEnabled = !h.on.isEnabled }
                glowLight.isEnabled = phase % 4 != 3
                phase += 1
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
        })
    }

    private func ambulanceOutside(_ e: Entity, at p: SIMD3<Float>) {
        let a = Entity(); a.position = p; e.addChild(a)
        let body = Self.tex("ambulance_side", fallback: .yellow) { Self.drawAmbulanceSide($0, $1) }
        box(a, [2.2, 2.3, 4.0], body, at: [0, 1.45, 0.6])
        box(a, [2.1, 1.6, 1.6], Self.mat(UIColor(red: 0.98, green: 0.85, blue: 0.1, alpha: 1), rough: 0.3), at: [0, 1.1, -2.1])
        box(a, [1.9, 0.6, 0.04], Self.mat(UIColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1), rough: 0.05, metal: true), at: [0, 1.55, -2.91])
        for (x, z) in [(Float(-1.0), Float(-1.9)), (1.0, -1.9), (-1.0, 1.6), (1.0, 1.6)] {
            cylinder(a, height: 0.28, radius: 0.38, Self.mat(UIColor(white: 0.08, alpha: 1)), at: [x, 0.38, z], axis: .x)
        }
        blueLights(on: a, height: 2.62)
    }

    private func bicycle(_ e: Entity, at p: SIMD3<Float>, yaw: Float) {
        // Lying on its side: built upright, then tipped over.
        let b = Entity(); b.position = p + [0, 0.03, 0]
        b.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        e.addChild(b)
        let tyre = Self.mat(UIColor(white: 0.08, alpha: 1)), frame = Self.mat(UIColor(red: 0.85, green: 0.1, blue: 0.15, alpha: 1), rough: 0.3, metal: true)
        for z: Float in [-0.52, 0.52] {
            cylinder(b, height: 0.035, radius: 0.34, tyre, at: [0, 0.34, z], axis: .x)
            cylinder(b, height: 0.04, radius: 0.05, Self.mat(.lightGray, metal: true), at: [0, 0.34, z], axis: .x)
        }
        box(b, [0.035, 0.035, 0.62], frame, at: [0, 0.62, 0.05])
        let down = box(b, [0.035, 0.035, 0.6], frame, at: [0, 0.48, 0.24])
        down.orientation = simd_quatf(angle: -0.75, axis: [1, 0, 0])
        box(b, [0.035, 0.42, 0.035], frame, at: [0, 0.52, -0.2])
        box(b, [0.1, 0.04, 0.22], Self.mat(.black), at: [0, 0.76, -0.22])
        box(b, [0.5, 0.03, 0.03], Self.mat(.darkGray, metal: true), at: [0, 0.82, 0.38])
    }

    private func cone(_ e: Entity, at p: SIMD3<Float>) {
        box(e, [0.34, 0.03, 0.34], Self.mat(.black), at: p + [0, 0.015, 0])
        let orange = Self.mat(UIColor(red: 1, green: 0.4, blue: 0.05, alpha: 1), rough: 0.5)
        for (i, (r, y)) in [(Float(0.13), Float(0.12)), (0.1, 0.3), (0.07, 0.46), (0.04, 0.6)].enumerated() {
            cylinder(e, height: 0.18, radius: r, i == 1 ? Self.glow(.white) : orange, at: p + [0, y, 0])
        }
    }

    private func tree(_ e: Entity, at p: SIMD3<Float>, night: Bool) {
        cylinder(e, height: 2.6, radius: 0.16, Self.mat(UIColor(red: 0.3, green: 0.2, blue: 0.12, alpha: 1)), at: p + [0, 1.3, 0])
        let leaf = Self.mat(night ? UIColor(red: 0.05, green: 0.12, blue: 0.06, alpha: 1) : UIColor(red: 0.18, green: 0.4, blue: 0.16, alpha: 1))
        sphere(e, radius: 1.5, leaf, at: p + [0, 3.4, 0])
        sphere(e, radius: 1.1, leaf, at: p + [0.6, 4.2, 0.3])
    }

    // MARK: Primitives

    @discardableResult
    private func box(_ parent: Entity, _ size: SIMD3<Float>, _ material: RealityKit.Material, at p: SIMD3<Float>, yaw: Float = 0) -> Entity {
        let m = ModelEntity(mesh: .generateBox(size: size), materials: [material])
        m.position = p
        if yaw != 0 { m.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) }
        parent.addChild(m)
        return m
    }

    private func plane(_ parent: Entity, _ size: SIMD2<Float>, _ material: RealityKit.Material, at p: SIMD3<Float>) {
        let m = ModelEntity(mesh: .generatePlane(width: size.x, depth: size.y), materials: [material])
        m.position = p
        parent.addChild(m)
    }

    private enum Axis { case x, y, z }

    private func cylinder(_ parent: Entity, height: Float, radius: Float, _ material: RealityKit.Material, at p: SIMD3<Float>, axis: Axis = .y) {
        let m = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [material])
        m.position = p
        switch axis {
        case .y: break
        case .x: m.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        case .z: m.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        }
        parent.addChild(m)
    }

    private func sphere(_ parent: Entity, radius: Float, _ material: RealityKit.Material, at p: SIMD3<Float>) {
        let m = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        m.position = p
        parent.addChild(m)
    }

    /// Upright picture facing +Z (turned by `yaw`), texture drawn once and cached by name.
    private func panel(_ parent: Entity, _ name: String, size: SIMD2<Float>, at p: SIMD3<Float>, yaw: Float = 0, unlit: Bool = false,
                       draw: (CGContext, CGSize) -> Void) {
        let px = SIMD2<Float>(512, 512 * size.y / size.x)
        let tex = Self.cachedTexture(name, size: px, draw)
        let m = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y),
                            materials: [unlit ? Self.unlit(tex, fallback: .gray) : Self.lit(tex, fallback: .gray)])
        m.position = p
        if yaw != 0 { m.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) }
        parent.addChild(m)
    }

    // MARK: Materials and textures

    private static func mat(_ c: UIColor, rough: Float = 0.85, metal: Bool = false) -> RealityKit.Material {
        SimpleMaterial(color: c, roughness: .float(rough), isMetallic: metal)
    }

    private static func glow(_ c: UIColor) -> RealityKit.Material { UnlitMaterial(color: c) }

    private static func lit(_ tex: TextureResource?, fallback: UIColor) -> RealityKit.Material {
        guard let tex else { return mat(fallback) }
        var m = SimpleMaterial()
        m.color = .init(tint: .white, texture: .init(tex))
        m.roughness = .float(0.8)
        m.metallic = .float(0)
        return m
    }

    private static func unlit(_ tex: TextureResource?, fallback: UIColor) -> RealityKit.Material {
        guard let tex else { return glow(fallback) }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(tex))
        return m
    }

    private static func tex(_ name: String, fallback: UIColor, _ draw: (CGContext, CGSize) -> Void) -> RealityKit.Material {
        lit(cachedTexture(name, size: [1024, 1024], draw), fallback: fallback)
    }

    private static var textures: [String: TextureResource] = [:]

    private static func cachedTexture(_ name: String, size: SIMD2<Float>, _ draw: (CGContext, CGSize) -> Void) -> TextureResource? {
        if let t = textures[name] { return t }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let s = CGSize(width: CGFloat(size.x), height: CGFloat(size.y))
        let image = UIGraphicsImageRenderer(size: s, format: format).image { draw($0.cgContext, s) }
        guard let cg = image.cgImage, let t = try? TextureResource(image: cg, options: .init(semantic: .color)) else { return nil }
        textures[name] = t
        return t
    }

    private static func drawTiles(_ ctx: CGContext, _ size: CGSize, a: UIColor, b: UIColor, n: Int) {
        let step = size.width / CGFloat(n)
        for i in 0..<n { for j in 0..<n {
            ctx.setFillColor(((i + j) % 2 == 0 ? a : b).cgColor)
            ctx.fill(CGRect(x: CGFloat(i) * step, y: CGFloat(j) * step, width: step, height: step))
        } }
        ctx.setStrokeColor(UIColor(white: 0.5, alpha: 0.5).cgColor); ctx.setLineWidth(2)
        for i in 0...n {
            ctx.move(to: CGPoint(x: CGFloat(i) * step, y: 0)); ctx.addLine(to: CGPoint(x: CGFloat(i) * step, y: size.height))
            ctx.move(to: CGPoint(x: 0, y: CGFloat(i) * step)); ctx.addLine(to: CGPoint(x: size.width, y: CGFloat(i) * step))
        }
        ctx.strokePath()
    }

    private static func drawPlanks(_ ctx: CGContext, _ size: CGSize) {
        var rng = SystemRandomNumberGenerator()
        let rows = 22, h = size.height / CGFloat(rows)
        for r in 0..<rows {
            var x: CGFloat = r % 2 == 0 ? 0 : -size.width / 6
            while x < size.width {
                let len = size.width / CGFloat.random(in: 2.5...4, using: &rng)
                let tone = CGFloat.random(in: 0.0...0.08, using: &rng)
                ctx.setFillColor(UIColor(red: 0.72 - tone, green: 0.56 - tone, blue: 0.4 - tone, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: CGFloat(r) * h, width: len, height: h))
                ctx.setStrokeColor(UIColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1).cgColor); ctx.setLineWidth(2)
                ctx.stroke(CGRect(x: x, y: CGFloat(r) * h, width: len, height: h))
                x += len
            }
        }
    }

    private static func drawAsphalt(_ ctx: CGContext, _ size: CGSize, wet: Bool) {
        ctx.setFillColor(UIColor(white: wet ? 0.12 : 0.24, alpha: 1).cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<9000 {
            let v = CGFloat.random(in: wet ? 0.05...0.25 : 0.15...0.38, using: &rng)
            ctx.setFillColor(UIColor(white: v, alpha: 1).cgColor)
            ctx.fill(CGRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: 3, height: 3))
        }
        if wet { // puddle sheen
            for _ in 0..<14 {
                ctx.setFillColor(UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 0.25).cgColor)
                ctx.fillEllipse(in: CGRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: 120, height: 50))
            }
        }
    }

    private static func drawWindow(_ ctx: CGContext, _ size: CGSize) {
        let colors = [UIColor(red: 0.45, green: 0.65, blue: 0.92, alpha: 1).cgColor, UIColor(red: 0.85, green: 0.92, blue: 0.98, alpha: 1).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height * 0.7), options: [.drawsAfterEndLocation])
        ctx.setFillColor(UIColor(red: 0.35, green: 0.55, blue: 0.3, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: -40, y: size.height * 0.6, width: size.width * 0.6, height: size.height * 0.7))
        ctx.fillEllipse(in: CGRect(x: size.width * 0.45, y: size.height * 0.66, width: size.width * 0.7, height: size.height * 0.6))
        ctx.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
        ctx.fill(CGRect(x: size.width / 2 - 6, y: 0, width: 12, height: size.height))
        ctx.fill(CGRect(x: 0, y: size.height / 2 - 6, width: size.width, height: 12))
    }

    private static func drawDesktop(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor(red: 0.12, green: 0.3, blue: 0.5, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 30, y: 30, width: size.width - 60, height: size.height - 60))
        ctx.setFillColor(UIColor(white: 0.75, alpha: 1).cgColor)
        for i in 0..<6 { ctx.fill(CGRect(x: 50, y: 60 + CGFloat(i) * 32, width: size.width * (i % 2 == 0 ? 0.6 : 0.4), height: 12)) }
    }

    /// A moving-looking trace with no numbers: the room must not show clinical values.
    private static func drawTrace(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor(white: 0.03, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setStrokeColor(UIColor(red: 0, green: 0.3, blue: 0.1, alpha: 1).cgColor); ctx.setLineWidth(1)
        for x in stride(from: CGFloat(0), to: size.width, by: 24) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height)) }
        for y in stride(from: CGFloat(0), to: size.height, by: 24) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y)) }
        ctx.strokePath()
        func trace(_ y0: CGFloat, _ color: UIColor, _ shape: (CGFloat) -> CGFloat) {
            ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: 0, y: y0))
            for x in stride(from: CGFloat(0), to: size.width * 0.82, by: 2) { ctx.addLine(to: CGPoint(x: x, y: y0 - shape(x))) }
            ctx.strokePath()
        }
        let h = size.height
        trace(h * 0.3, .systemGreen) { x in
            let p = x.truncatingRemainder(dividingBy: 110)
            return p > 40 && p < 46 ? h * 0.2 * (p - 40) / 6 : p >= 46 && p < 52 ? h * 0.2 - h * 0.28 * (p - 46) / 6 : p > 70 && p < 90 ? h * 0.04 * sin((p - 70) / 20 * .pi) : 0
        }
        trace(h * 0.6, .systemCyan) { x in h * 0.06 * max(0, sin(x / 110 * 2 * .pi)) }
        trace(h * 0.85, .systemYellow) { x in h * 0.04 * sin(x / 160 * 2 * .pi) }
    }

    private static func drawPoster(_ ctx: CGContext, _ size: CGSize, title: String, lines: [String], tint: UIColor) {
        ctx.setFillColor(UIColor.white.cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(tint.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.28))
        (title as NSString).draw(in: CGRect(x: 30, y: 40, width: size.width - 60, height: 120),
                                 withAttributes: [.font: UIFont.boldSystemFont(ofSize: 58), .foregroundColor: UIColor.white])
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 34, y: size.height * 0.36 + CGFloat(i) * 80),
                                    withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.darkGray])
        }
    }

    private static func drawSign(_ ctx: CGContext, _ size: CGSize, _ text: String, bg: UIColor) {
        ctx.setFillColor(bg.cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: size.height * 0.55), .foregroundColor: UIColor.white]
        let s = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2), withAttributes: attrs)
    }

    private static func drawCabWindow(_ ctx: CGContext, _ size: CGSize) {
        let colors = [UIColor(red: 0.35, green: 0.45, blue: 0.6, alpha: 1).cgColor, UIColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        ctx.setFillColor(UIColor(white: 0.1, alpha: 1).cgColor)
        ctx.fill(CGRect(x: size.width * 0.1, y: size.height * 0.45, width: size.width * 0.25, height: size.height * 0.55))
        ctx.fill(CGRect(x: size.width * 0.62, y: size.height * 0.45, width: size.width * 0.25, height: size.height * 0.55))
    }

    private static func drawRearWindow(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor(red: 0.55, green: 0.62, blue: 0.7, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(UIColor(white: 0.25, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: size.width * 0.42, y: size.height * 0.5)); ctx.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.5))
        ctx.addLine(to: CGPoint(x: size.width, y: size.height)); ctx.addLine(to: CGPoint(x: 0, y: size.height)); ctx.fillPath()
        ctx.setFillColor(UIColor(red: 0.3, green: 0.45, blue: 0.28, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: size.height * 0.42, width: size.width * 0.38, height: size.height * 0.1))
        ctx.fill(CGRect(x: size.width * 0.62, y: size.height * 0.42, width: size.width * 0.38, height: size.height * 0.1))
    }

    private static func drawChevrons(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor(red: 0.98, green: 0.85, blue: 0.1, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(UIColor.systemRed.cgColor)
        for x in stride(from: CGFloat(-size.height), to: size.width, by: size.height * 1.6) {
            ctx.move(to: CGPoint(x: x, y: size.height)); ctx.addLine(to: CGPoint(x: x + size.height * 0.8, y: 0))
            ctx.addLine(to: CGPoint(x: x + size.height * 1.6, y: 0)); ctx.addLine(to: CGPoint(x: x + size.height * 0.8, y: size.height)); ctx.fillPath()
        }
    }

    private static func drawAmbulanceSide(_ ctx: CGContext, _ size: CGSize) {
        ctx.setFillColor(UIColor(red: 0.98, green: 0.88, blue: 0.15, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: size))
        let band = size.height * 0.1, y = size.height * 0.62, cell = band
        for i in 0..<Int(size.width / cell) {
            for row in 0..<2 {
                ctx.setFillColor(((i + row) % 2 == 0 ? UIColor.systemBlue : UIColor(red: 0.98, green: 0.88, blue: 0.15, alpha: 1)).cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * cell, y: y + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
        drawSignText(ctx, CGRect(x: 0, y: size.height * 0.25, width: size.width, height: size.height * 0.2), "AMBULANCE", color: .systemGreen)
    }

    private static func drawSignText(_ ctx: CGContext, _ rect: CGRect, _ text: String, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: rect.height * 0.8), .foregroundColor: color]
        let s = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2), withAttributes: attrs)
    }

    // MARK: Sound

    private func playAmbience(_ kind: Kind) {
        ambience?.stop(); ambience = nil
        guard let player = try? AVAudioPlayer(data: Self.wav(Self.ambienceSamples(kind))) else { return }
        player.numberOfLoops = -1
        // Kept well below speech so the patient and the voice agent stay intelligible.
        player.volume = [Kind.clinic: 0.1, .antenatal: 0.08, .traumaBay: 0.18, .ambulance: 0.32, .roadside: 0.28, .roadsideNight: 0.32][kind] ?? 0.1
        player.play()
        ambience = player
    }

    /// Four seconds that loop cleanly: room tone, monitor beeps, diesel rumble, traffic or rain.
    static func ambienceSamples(_ kind: Kind) -> [Float] {
        let rate = 22_050, count = rate * 4, fade = rate / 10
        var state: UInt64 = 0x9E3779B97F4A7C15 &* UInt64(kind.rawValue.count + 1)
        var low: Float = 0, mid: Float = 0, out = [Float](repeating: 0, count: count + fade)
        for i in 0..<(count + fade) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let white = Float(Int32(truncatingIfNeeded: state >> 33)) / Float(Int32.max)
            low += 0.015 * (white - low)
            mid += 0.15 * (white - mid)
            let t = Float(i) / Float(rate)
            switch kind {
            case .clinic, .antenatal:
                out[i] = low * 2 + 0.01 * sin(2 * .pi * 100 * t)
            case .traumaBay:
                let beat = t.truncatingRemainder(dividingBy: 0.8) // a monitor tone every 0.8 s: 5 in the loop
                out[i] = low * 2 + (beat < 0.07 ? 0.18 * sin(2 * .pi * 880 * t) * sin(.pi * beat / 0.07) : 0)
            case .ambulance:
                let wobble = 0.8 + 0.2 * sin(2 * .pi * 0.5 * t)
                out[i] = (low * 6 + 0.06 * sin(2 * .pi * 45 * t) + 0.03 * sin(2 * .pi * 90 * t)) * wobble
            case .roadside:
                let passing = pow(sin(.pi * t / 4), 6) // one car going by per loop
                out[i] = low * 3 + (mid - low) * (0.15 + 0.9 * passing)
            case .roadsideNight:
                out[i] = low * 2.5 + (white - mid) * 0.35 + (mid - low) * 0.2
            }
        }
        // Cross-fade the tail into the head so the loop has no click.
        for i in 0..<fade {
            let k = Float(i) / Float(fade)
            out[i] = out[i] * k + out[count + i] * (1 - k)
        }
        out.removeLast(fade)
        let peak = out.map(abs).max() ?? 1
        return out.map { $0 / max(peak, 0.0001) * 0.9 }
    }

    private static func wav(_ samples: [Float]) -> Data {
        let rate = 22_050
        var pcm = Data(capacity: samples.count * 2)
        for s in samples {
            withUnsafeBytes(of: Int16(max(-1, min(1, s)) * 32_000).littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        wav.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36 + pcm.count)); wav.append(contentsOf: Array("WAVEfmt ".utf8))
        put(UInt32(16)); put(UInt16(1)); put(UInt16(1)); put(UInt32(rate)); put(UInt32(rate * 2)); put(UInt16(2)); put(UInt16(16))
        wav.append(contentsOf: Array("data".utf8)); put(UInt32(pcm.count))
        return wav + pcm
    }
}
