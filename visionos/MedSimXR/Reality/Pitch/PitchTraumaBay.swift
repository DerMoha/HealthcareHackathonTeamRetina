import RealityKit
import UIKit

/// Pitch dressing: the ED resus bay (rt-05..08). Trolley with the patient at the origin, ceiling pendant
/// with gas outlets and the vitals monitor at the head end (left), PACS screen, wall suction, crash cart,
/// IV pole, PPE station, curtains, bay markings, and a resus team of three standing round the trolley.
@MainActor
enum PitchTraumaBay {
    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        let w: Float = 3.2, back: Float = -3.2, front: Float = 4.8, h: Float = 2.9

        // Floor, walls, ceiling.
        let floor = ModelEntity(mesh: .generatePlane(width: 2 * w, depth: front - back),
                                materials: [tinted("traumabay_floor", tiling: [8, 10], UIColor(red: 0.74, green: 0.77, blue: 0.78, alpha: 1), roughness: 0.6)])
        floor.position = [0, 0, (front + back) / 2]
        set.addChild(floor)
        let wallTint = UIColor(red: 0.86, green: 0.92, blue: 0.92, alpha: 1)
        wall(set, size: [2 * w, h], at: [0, h / 2, back], yaw: 0, tint: wallTint)
        wall(set, size: [front - back, h], at: [-w, h / 2, (front + back) / 2], yaw: .pi / 2, tint: wallTint)
        wall(set, size: [front - back, h], at: [w, h / 2, (front + back) / 2], yaw: -.pi / 2, tint: wallTint)
        let ceiling = ModelEntity(mesh: .generatePlane(width: 2 * w, depth: front - back), materials: [pbr(UIColor(white: 0.93, alpha: 1), 0.9)])
        ceiling.position = [0, h, (front + back) / 2]
        ceiling.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        set.addChild(ceiling)
        var panelGlow = UnlitMaterial(color: UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1))
        panelGlow.color = .init(tint: UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1))
        for x: Float in [-1.5, 1.5] { for z: Float in [-2.2, -0.4, 1.4] { box(set, [0.6, 0.02, 1.2], panelGlow, at: [x, h - 0.01, z]) } }
        // Wipe-clean lower wall panels and a bumper rail, round the three walls.
        let lower = pbr(UIColor(red: 0.42, green: 0.6, blue: 0.68, alpha: 1), 0.35)
        let rail = pbr(UIColor(white: 0.85, alpha: 1), 0.3, metal: 1)
        box(set, [2 * w, 1.0, 0.02], lower, at: [0, 0.5, back + 0.011])
        box(set, [2 * w, 0.06, 0.05], rail, at: [0, 1.02, back + 0.03])
        for x in [-w + 0.011, w - 0.011] {
            box(set, [0.02, 1.0, front - back], lower, at: [x, 0.5, (front + back) / 2])
            box(set, [0.05, 0.06, front - back], rail, at: [x + (x < 0 ? 0.02 : -0.02), 1.02, (front + back) / 2])
        }
        // Yellow bay box and a hatched keep-clear strip at the head end.
        let yellow = pbr(UIColor(red: 0.98, green: 0.78, blue: 0.08, alpha: 1), 0.55)
        for (x, z, sx, sz) in [(Float(0), Float(-1.9), Float(3.5), Float(0.07)), (0, 1.0, 3.5, 0.07), (-1.75, -0.45, 0.07, 2.97), (1.75, -0.45, 0.07, 2.97)] {
            box(set, [sx, 0.003, sz], yellow, at: [x, 0.0015, z])
        }

        // Signage above the bay.
        let sign = drawn(1200, 300) { r in
            UIColor(red: 0.07, green: 0.18, blue: 0.36, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            text("RESUS 2", at: CGPoint(x: 60, y: 40), size: 150, weight: .heavy, color: .white)
            UIColor(red: 0.98, green: 0.78, blue: 0.08, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 760, y: 70, width: 8, height: 160)).fill()
            text("MAJOR\nTRAUMA", at: CGPoint(x: 800, y: 58), size: 72, weight: .bold, color: UIColor(red: 0.98, green: 0.78, blue: 0.08, alpha: 1))
        }
        plane(set, [1.2, 0.3], sign, at: [-0.55, 2.5, back + 0.02])

        // Ceiling pendant at the head end: column with gas outlets, the vitals monitor on an arm.
        let pendantWhite = pbr(UIColor(white: 0.9, alpha: 1), 0.35)
        let px: Float = -1.25, pz: Float = -1.15
        box(set, [0.5, 0.06, 0.5], pendantWhite, at: [px, h - 0.03, pz], corner: 0.02)
        box(set, [0.3, 1.75, 0.3], pendantWhite, at: [px, h - 0.06 - 0.875, pz], corner: 0.03)
        box(set, [0.32, 0.05, 0.32], pbr(UIColor(white: 0.6, alpha: 1), 0.3, metal: 1), at: [px, 1.05, pz], corner: 0.01)
        let outlets: [(UIColor, UIColor)] = [(.white, .white), (.black, .white), (.systemYellow, .systemYellow), (.white, .systemBlue)]
        for (i, (c, ring)) in outlets.enumerated() {
            let y = 1.62 - Float(i) * 0.12
            cyl(set, 0.02, 0.035, pbr(ring, 0.4), at: [px, y, pz + 0.155], axis: .z)
            cyl(set, 0.03, 0.02, pbr(c == .white ? UIColor(white: 0.97, alpha: 1) : c, 0.4), at: [px, y, pz + 0.17], axis: .z)
        }
        for i in 0..<3 { box(set, [0.08, 0.06, 0.02], pbr(UIColor(white: 0.97, alpha: 1), 0.5), at: [px + 0.06 * Float(i - 1) * 1.5, 1.2, pz + 0.155]) }
        // O2 flowmeter with a green knob on the top outlet.
        cyl(set, 0.14, 0.022, pbr(UIColor(white: 0.95, alpha: 0.6), 0.1), at: [px + 0.09, 1.66, pz + 0.19])
        cyl(set, 0.03, 0.03, pbr(UIColor(red: 0.1, green: 0.6, blue: 0.25, alpha: 1), 0.4), at: [px + 0.09, 1.75, pz + 0.19])
        // Monitor arm and the vitals monitor turned towards the trolley.
        rod(set, from: [px + 0.15, 1.9, pz], to: [-0.85, 1.9, -0.95], radius: 0.025, rail)
        let monitorYaw: Float = 0.35
        let mon = Entity(); mon.position = [-0.8, 1.86, -0.92]; mon.orientation = simd_quatf(angle: monitorYaw, axis: [0, 1, 0]); set.addChild(mon)
        box(mon, [0.56, 0.42, 0.07], pbr(UIColor(white: 0.16, alpha: 1), 0.45), at: [0, 0, 0], corner: 0.015)
        plane(mon, [0.52, 0.365], vitals(), at: [0, 0.01, 0.036])

        // Wall suction and a second O2 point on a wall rail, left of the sign.
        box(set, [1.6, 0.08, 0.04], rail, at: [-2.2, 1.42, back + 0.03])
        cyl(set, 0.22, 0.07, pbr(UIColor(red: 0.85, green: 0.92, blue: 0.95, alpha: 0.5), 0.05), at: [-2.55, 1.22, back + 0.1])
        cyl(set, 0.03, 0.075, pbr(UIColor(red: 0.1, green: 0.35, blue: 0.7, alpha: 1), 0.4), at: [-2.55, 1.345, back + 0.1])
        box(set, [0.09, 0.14, 0.07], pendantWhite, at: [-2.3, 1.55, back + 0.06], corner: 0.01)
        cyl(set, 0.02, 0.04, pbr(UIColor(white: 0.98, alpha: 1), 0.2), at: [-2.3, 1.58, back + 0.1], axis: .z)
        cyl(set, 0.022, 0.04, pbr(.systemYellow, 0.4), at: [-2.3, 1.48, back + 0.1], axis: .z)
        rod(set, from: [-2.3, 1.48, back + 0.1], to: [-2.55, 1.36, back + 0.1], radius: 0.006, pbr(UIColor(white: 0.95, alpha: 0.7), 0.2))

        // PACS screen high on the back wall, right of the sign.
        box(set, [0.96, 0.6, 0.05], pbr(UIColor(white: 0.12, alpha: 1), 0.4), at: [1.1, 2.2, back + 0.03], corner: 0.01)
        plane(set, [0.9, 0.54], pacs(), at: [1.1, 2.2, back + 0.058])

        // PPE station on the back wall, right: gloves S/M/L, aprons, visors, hand gel.
        box(set, [0.8, 0.62, 0.12], pbr(UIColor(white: 0.96, alpha: 1), 0.4), at: [2.35, 1.45, back + 0.06], corner: 0.01)
        let ppeSign = drawn(800, 140) { r in
            UIColor(red: 0.85, green: 0.1, blue: 0.15, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            text("PPE  ·  gloves  ·  apron  ·  eye protection", at: CGPoint(x: 30, y: 36), size: 52, weight: .bold, color: .white)
        }
        plane(set, [0.8, 0.14], ppeSign, at: [2.35, 1.85, back + 0.02])
        for (i, c) in [UIColor(red: 0.45, green: 0.55, blue: 0.95, alpha: 1), UIColor(red: 0.35, green: 0.4, blue: 0.85, alpha: 1), UIColor(red: 0.55, green: 0.35, blue: 0.8, alpha: 1)].enumerated() {
            let x = 2.1 + Float(i) * 0.25
            box(set, [0.22, 0.12, 0.1], pbr(c, 0.6), at: [x, 1.65, back + 0.14], corner: 0.005)
            plane(set, [0.08, 0.06], drawn(80, 60) { _ in text(["S", "M", "L"][i], at: CGPoint(x: 24, y: 2), size: 48, weight: .heavy, color: .white) }, at: [x, 1.65, back + 0.191])
        }
        cyl(set, 0.6, 0.06, pbr(UIColor(red: 0.98, green: 0.97, blue: 0.9, alpha: 1), 0.7), at: [2.35, 1.4, back + 0.17], axis: .x) // apron roll
        for i in 0..<3 { box(set, [0.2, 0.16, 0.005], pbr(UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 0.35), 0.05), at: [2.15 + Float(i) * 0.2, 1.23, back + 0.13 + Float(i) * 0.01]) }
        box(set, [0.1, 0.2, 0.08], pbr(.white, 0.4), at: [1.75, 1.35, back + 0.05], corner: 0.01)
        box(set, [0.04, 0.04, 0.04], pbr(UIColor(red: 0.2, green: 0.5, blue: 0.85, alpha: 1), 0.4), at: [1.75, 1.23, back + 0.07])
        // Clinical waste bin, shelves with supplies in the right corner.
        PitchKit.place("traumabay_bin", in: set, at: [1.5, 0, back + 0.35], fit: 0.6)
        PitchKit.place("traumabay_shelves", in: set, at: [2.75, 0, -2.2], yaw: -.pi / 2, fit: 1.8)
        for (y, n) in [(Float(0.95), 2), (1.32, 3)] {
            for i in 0..<n { PitchKit.place("traumabay_medbox", in: set, at: [2.8, y, -2.6 + Float(i) * 0.35], yaw: -.pi / 2, fit: 0.3, shadow: false) }
        }
        PitchKit.place("traumabay_clock", in: set, at: [0.3, 2.25, back + 0.02], fit: 0.3, shadow: false)

        // Curtains on ceiling tracks either side of the bay, pleated.
        let curtain = PitchKit.material("traumabay_scrub", tiling: [2, 6], roughness: 1)
        var curtainMat = curtain; curtainMat.baseColor = .init(tint: UIColor(red: 0.55, green: 0.72, blue: 0.8, alpha: 1))
        for x: Float in [-2.7, 2.7] {
            box(set, [0.04, 0.03, 4.0], rail, at: [x, h - 0.12, -1.2])
            for i in 0..<16 {
                let z = -3.1 + Float(i) * 0.12
                if x > 0 && z > -2.5 { continue } // right side drawn back behind the shelves
                box(set, [0.012, 2.35, 0.13], curtainMat, at: [x + (i % 2 == 0 ? 0.03 : -0.03), h - 0.15 - 1.175, z], yaw: (i % 2 == 0 ? 0.45 : -0.45))
            }
        }

        // Resus trolley: patient sits on its long edge at the origin, head end raised on the left.
        trolley(set, seat: seat)

        // IV pole with a fluid bag, line running to the patient's left arm.
        ivPole(set, at: [0.95, 0, -0.75])

        // Crash cart with defibrillator, right of the trolley.
        crashCart(set, at: [1.95, 0, -1.25], yaw: -0.45)

        // Overhead examination light on a ceiling arm.
        rod(set, from: [0.6, h, -0.6], to: [0.6, h - 0.35, -0.6], radius: 0.03, pendantWhite)
        rod(set, from: [0.6, h - 0.35, -0.6], to: [0.35, h - 0.45, 0.0], radius: 0.025, pendantWhite)
        cyl(set, 0.1, 0.3, pendantWhite, at: [0.35, h - 0.52, 0.0])
        cyl(set, 0.01, 0.26, UnlitMaterial(color: UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 1)), at: [0.35, h - 0.575, 0.0])

        // Resus team: registrar at the head end (cap and mask), nurse at the IV pole, a third behind.
        staff(set, "Patient", at: [-1.15, 0, -0.45], yaw: 0.9, scrubs: UIColor(red: 0.12, green: 0.2, blue: 0.42, alpha: 1), masked: true, armsForward: true)
        staff(set, "Patient_female", at: [1.2, 0, -0.35], yaw: -1.0, scrubs: UIColor(red: 0.28, green: 0.5, blue: 0.85, alpha: 1), masked: false, armsForward: true)
        staff(set, "Patient_female", at: [0.55, 0, -1.55], yaw: -0.25, scrubs: UIColor(red: 0.5, green: 0.12, blue: 0.2, alpha: 1), masked: false, armsForward: false)

        // Light: HDRI on everything, shadows from the overhead lamp and the ceiling panels.
        PitchKit.light(avatarRoot, hdri: "traumabay_ibl", intensity: 0.4)
        PitchKit.showShadows(on: floor)
        PitchKit.spot(set, at: [0.35, h - 0.6, 0.0], target: [0, 0.5, -0.1], intensity: 40000, color: UIColor(red: 1, green: 0.98, blue: 0.93, alpha: 1), angle: 70)
        PitchKit.sun(set, from: [0.8, 3, 1.2], to: [0, 0, -0.6], intensity: 4200)
        return true
    }

    // MARK: Furniture

    private static func trolley(_ e: Entity, seat: Float) {
        let steel = pbr(UIColor(white: 0.82, alpha: 1), 0.25, metal: 1)
        let frame = pbr(UIColor(white: 0.92, alpha: 1), 0.4)
        let vinyl = pbr(UIColor(red: 0.16, green: 0.24, blue: 0.4, alpha: 1), 0.45)
        let z: Float = -0.15
        box(e, [1.95, 0.1, 0.68], vinyl, at: [0.1, seat - 0.05, z], corner: 0.04)
        box(e, [1.4, 0.012, 0.7], pbr(UIColor(white: 0.97, alpha: 1), 0.85), at: [0.3, seat + 0.002, z]) // sheet
        // Raised back rest at the head end with a pillow.
        let rest = Entity(); rest.position = [-0.55, seat, z]; rest.orientation = simd_quatf(angle: -0.95, axis: [0, 0, 1]); e.addChild(rest)
        box(rest, [0.75, 0.09, 0.66], vinyl, at: [-0.375, 0.045, 0], corner: 0.04)
        box(rest, [0.4, 0.06, 0.5], pbr(UIColor(white: 0.97, alpha: 1), 0.85), at: [-0.45, 0.11, 0], corner: 0.03)
        box(e, [2.0, 0.07, 0.72], frame, at: [0.1, seat - 0.135, z], corner: 0.02)
        // Folded side rail along the back edge.
        box(e, [1.1, 0.03, 0.03], steel, at: [0.3, seat + 0.12, z - 0.36])
        for x: Float in [-0.2, 0.8] { cyl(e, 0.12, 0.012, steel, at: [x, seat + 0.06, z - 0.36]) }
        // Column base, castors.
        box(e, [0.5, seat - 0.27, 0.25], frame, at: [0.1, (seat - 0.27) / 2 + 0.12, z], corner: 0.03)
        box(e, [1.7, 0.08, 0.55], frame, at: [0.1, 0.1, z], corner: 0.03)
        for x: Float in [-0.65, 0.85] { for dz: Float in [-0.22, 0.22] {
            cyl(e, 0.05, 0.05, pbr(UIColor(white: 0.15, alpha: 1), 0.6), at: [x, 0.05, z + dz], axis: .z)
        } }
        PitchKit.contactShadow(e, at: [0.1, 0, z], size: [1.9, 0.6], opacity: 0.6)
    }

    private static func ivPole(_ e: Entity, at p: SIMD3<Float>) {
        let steel = pbr(UIColor(white: 0.85, alpha: 1), 0.2, metal: 1)
        cyl(e, 1.95, 0.013, steel, at: p + [0, 1.0, 0])
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            rod(e, from: p + [0, 0.08, 0], to: p + [cos(a) * 0.3, 0.04, sin(a) * 0.3], radius: 0.012, steel)
            cyl(e, 0.03, 0.025, pbr(UIColor(white: 0.15, alpha: 1), 0.6), at: p + [cos(a) * 0.3, 0.025, sin(a) * 0.3])
        }
        rod(e, from: p + [-0.12, 1.95, 0], to: p + [0.12, 1.95, 0], radius: 0.008, steel)
        // Bag of 0.9% saline with a printed label, drip chamber and the giving set.
        var bagMat = PhysicallyBasedMaterial()
        bagMat.baseColor = .init(tint: UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1))
        bagMat.roughness = 0.15
        bagMat.blending = .transparent(opacity: 0.55)
        box(e, [0.15, 0.24, 0.035], bagMat, at: p + [-0.1, 1.78, 0], corner: 0.015)
        let label = drawn(300, 400) { r in
            UIColor.white.setFill(); UIBezierPath(rect: r).fill()
            text("Sodium\nChloride\n0.9%", at: CGPoint(x: 20, y: 30), size: 64, weight: .bold, color: UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1))
            text("1000 mL\nfor IV infusion", at: CGPoint(x: 20, y: 270), size: 40, weight: .medium, color: .darkGray)
        }
        plane(e, [0.1, 0.13], label, at: p + [-0.1, 1.79, 0.019])
        cyl(e, 0.07, 0.012, bagMat, at: p + [-0.1, 1.62, 0])
        rod(e, from: p + [-0.1, 1.58, 0], to: [0.2, 0.78, 0.18], radius: 0.003, pbr(UIColor(white: 0.97, alpha: 1), 0.2))
        PitchKit.contactShadow(e, at: p, size: [0.6, 0.6])
    }

    private static func crashCart(_ e: Entity, at p: SIMD3<Float>, yaw: Float) {
        let c = Entity(); c.position = p; c.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]); e.addChild(c)
        let red = pbr(UIColor(red: 0.78, green: 0.08, blue: 0.1, alpha: 1), 0.35)
        let dark = pbr(UIColor(white: 0.12, alpha: 1), 0.5)
        let steel = pbr(UIColor(white: 0.85, alpha: 1), 0.2, metal: 1)
        box(c, [0.75, 0.88, 0.55], red, at: [0, 0.55, 0], corner: 0.02)
        for i in 0..<5 {
            let y = 0.2 + Float(i) * 0.17
            box(c, [0.71, 0.006, 0.01], dark, at: [0, y, 0.276])
            rod(c, from: [-0.2, y + 0.08, 0.29], to: [0.2, y + 0.08, 0.29], radius: 0.008, steel)
        }
        box(c, [0.8, 0.04, 0.6], pbr(UIColor(white: 0.2, alpha: 1), 0.6), at: [0, 1.01, 0], corner: 0.01)
        for x: Float in [-0.3, 0.3] { for z: Float in [-0.22, 0.22] { cyl(c, 0.05, 0.045, dark, at: [x, 0.05, z], axis: .x) } }
        rod(c, from: [-0.38, 0.95, 0.3], to: [0.38, 0.95, 0.3], radius: 0.012, steel)
        // Defibrillator on top: housing, screen with a trace, pads connector.
        box(c, [0.36, 0.26, 0.28], pbr(UIColor(white: 0.25, alpha: 1), 0.5), at: [-0.12, 1.16, -0.02], corner: 0.03)
        box(c, [0.08, 0.04, 0.2], pbr(UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1), 0.5), at: [-0.12, 1.31, -0.02], corner: 0.01)
        let defib = drawn(400, 300) { r in
            UIColor.black.setFill(); UIBezierPath(rect: r).fill()
            trace(in: CGRect(x: 10, y: 60, width: 380, height: 120), color: .systemGreen, kind: 0, beats: 4)
            text("HR 104", at: CGPoint(x: 20, y: 200), size: 54, weight: .bold, color: .systemGreen)
            text("PADS", at: CGPoint(x: 260, y: 215), size: 36, weight: .bold, color: .white)
        }
        plane(c, [0.24, 0.17], defib, at: [-0.15, 1.17, 0.121])
        PitchKit.place("traumabay_medbox", in: c, at: [0.22, 1.03, 0], fit: 0.3, shadow: false)
        // O2 cylinder strapped to the side.
        cyl(c, 0.7, 0.06, pbr(UIColor(white: 0.97, alpha: 1), 0.3), at: [0.44, 0.55, 0])
        cyl(c, 0.1, 0.06, pbr(UIColor(white: 0.9, alpha: 1), 0.3, metal: 1), at: [0.44, 0.95, 0])
        PitchKit.contactShadow(c, at: [0, 0, 0], size: [0.8, 0.6])
    }

    // MARK: Team

    /// One of the bundled seated avatars, stood up (legs straightened, forearms forward) and dressed in scrubs.
    private static func staff(_ e: Entity, _ variant: String, at p: SIMD3<Float>, yaw: Float, scrubs: UIColor, masked: Bool, armsForward: Bool) {
        guard let model = PitchKit.model(variant), let mesh = skinned(model) else { return }
        let holder = Entity()
        holder.addChild(model)
        let size = model.visualBounds(relativeTo: holder).extents
        if size.z > size.y { model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) }
        let names = mesh.jointNames
        let byPath = Dictionary(names.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let parent = names.map { byPath[$0.split(separator: "/").dropLast().joined(separator: "/")] }
        let index = Dictionary(names.enumerated().map { (String($1.split(separator: "/").last ?? ""), $0) }, uniquingKeysWith: { a, _ in a })
        var joints = mesh.jointTransforms
        func world() -> [simd_float4x4] {
            var w = joints.map(\.matrix)
            for i in w.indices { if let q = parent[i] { w[i] = w[q] * w[i] } }
            return w
        }
        func xyz(_ v: SIMD4<Float>) -> SIMD3<Float> { [v.x, v.y, v.z] }
        let toHolder = mesh.transformMatrix(relativeTo: holder)
        // Turns `bone` so the segment to `child` points along `dir` (holder space: +Z forward, +X the person's left).
        func aim(_ bone: String, _ child: String, _ dir: SIMD3<Float>) {
            guard let b = index[bone], let c = index[child] else { return }
            let w = world()
            var rot = joints.map(\.rotation)
            for i in rot.indices { if let q = parent[i] { rot[i] = rot[q] * rot[i] } }
            let cur = simd_normalize(xyz(w[c].columns.3) - xyz(w[b].columns.3))
            let d = simd_normalize(xyz(toHolder.inverse * SIMD4(simd_normalize(dir), 0)))
            let parentRot = parent[b].map { rot[$0] } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            joints[b].rotation = parentRot.inverse * simd_quatf(from: cur, to: d) * rot[b]
        }
        aim("thigh_l", "calf_l", [0.06, -1, 0.02]); aim("calf_l", "foot_l", [0.0, -1, -0.03])
        aim("thigh_r", "calf_r", [-0.06, -1, 0.02]); aim("calf_r", "foot_r", [0.0, -1, -0.03])
        let fore: Float = armsForward ? 1 : 0.15 // forearms forward (working) or hanging by the sides
        aim("upperarm_l", "lowerarm_l", [0.18, -1, 0.12]); aim("lowerarm_l", "hand_l", [armsForward ? -0.15 : 0.05, -0.55, fore])
        aim("upperarm_r", "lowerarm_r", [-0.18, -1, 0.12]); aim("lowerarm_r", "hand_r", [armsForward ? 0.15 : -0.05, -0.55, fore])
        mesh.jointTransforms = joints
        let w = world()
        func at(_ name: String) -> SIMD3<Float> { index[name].map { xyz(toHolder * w[$0].columns.3) } ?? .zero }
        let pelvis = at("pelvis"), foot = min(at("foot_l").y, at("foot_r").y)
        model.position += [-pelvis.x, 0.08 - foot, -pelvis.z]
        // Scrubs instead of the casual suit (material 1 of the joined mesh), shoes stay.
        if var m = mesh.model, m.materials.count > 1 {
            var s = PitchKit.material("traumabay_scrub", tiling: [8, 8], roughness: 1)
            s.baseColor = .init(tint: scrubs)
            m.materials[1] = s
            mesh.model = m
        }
        if masked { // theatre cap and surgical mask: also keeps him from looking like the patient's twin
            let head = at("head") + [-pelvis.x, 0.08 - foot, -pelvis.z]
            let cap = ModelEntity(mesh: .generateSphere(radius: 0.105), materials: [pbr(UIColor(red: 0.2, green: 0.45, blue: 0.75, alpha: 1), 0.9)])
            cap.position = head + [0, 0.1, -0.01]; cap.scale = [1, 0.62, 1.08]
            holder.addChild(cap)
            let mask = ModelEntity(mesh: .generateBox(size: [0.15, 0.1, 0.05], cornerRadius: 0.02), materials: [pbr(UIColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1), 0.9)])
            mask.position = head + [0, -0.075, 0.085]
            holder.addChild(mask)
        }
        holder.position = p
        holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        PitchKit.contactShadow(holder, at: [0, 0, 0], size: [0.45, 0.35], opacity: 0.5)
        e.addChild(holder)
    }

    private static func skinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for c in e.children { if let f = skinned(c) { return f } }
        return nil
    }

    // MARK: Screens

    private static func vitals() -> UnlitMaterial {
        drawn(1040, 730) { r in
            UIColor.black.setFill(); UIBezierPath(rect: r).fill()
            UIColor(white: 0.18, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: r.width, height: 56)).fill()
            text("RESUS 2   JORDAN M, 34   ADULT", at: CGPoint(x: 18, y: 10), size: 32, weight: .semibold, color: .white)
            text("14:52", at: CGPoint(x: 920, y: 10), size: 32, weight: .semibold, color: .white)
            let green = UIColor(red: 0.2, green: 1, blue: 0.35, alpha: 1), cyan = UIColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
            let yellow = UIColor(red: 1, green: 0.88, blue: 0.2, alpha: 1), red = UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1)
            trace(in: CGRect(x: 10, y: 80, width: 640, height: 150), color: green, kind: 0, beats: 6)
            trace(in: CGRect(x: 10, y: 260, width: 640, height: 120), color: cyan, kind: 1, beats: 6)
            trace(in: CGRect(x: 10, y: 410, width: 640, height: 100), color: yellow, kind: 2, beats: 2)
            text("II", at: CGPoint(x: 14, y: 70), size: 26, weight: .medium, color: green)
            func value(_ label: String, _ v: String, _ unit: String, _ c: UIColor, _ y: CGFloat, _ s: CGFloat) {
                text(label, at: CGPoint(x: 680, y: y), size: 28, weight: .semibold, color: c)
                text(v, at: CGPoint(x: 680, y: y + 22), size: s, weight: .bold, color: c)
                text(unit, at: CGPoint(x: 960, y: y + 4), size: 24, weight: .medium, color: c)
            }
            value("HR", "104", "bpm", green, 70, 130)
            value("SpO2", "97", "%", cyan, 240, 110)
            value("RR", "20", "/min", yellow, 400, 90)
            UIColor(white: 0.3, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 540, width: r.width, height: 2)).fill()
            text("NIBP", at: CGPoint(x: 18, y: 556), size: 28, weight: .semibold, color: red)
            text("118/76", at: CGPoint(x: 18, y: 580), size: 110, weight: .bold, color: red)
            text("(90)", at: CGPoint(x: 400, y: 630), size: 44, weight: .semibold, color: red)
            text("TEMP", at: CGPoint(x: 680, y: 556), size: 28, weight: .semibold, color: .white)
            text("36.8", at: CGPoint(x: 680, y: 580), size: 100, weight: .bold, color: .white)
            text("°C", at: CGPoint(x: 900, y: 600), size: 36, weight: .medium, color: .white)
        }
    }

    private static func pacs() -> UnlitMaterial {
        drawn(1200, 720) { r in
            UIColor(white: 0.05, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            UIColor(white: 0.16, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: r.width, height: 60)).fill()
            text("JORDAN M · 34 · ED RESUS 2      XR FOREARM RIGHT  AP + LAT", at: CGPoint(x: 20, y: 14), size: 30, weight: .semibold, color: UIColor(white: 0.85, alpha: 1))
            let url = Bundle.main.url(forResource: "wrist_xray_pa", withExtension: "jpg", subdirectory: "Radiology")
                ?? Bundle.main.url(forResource: "wrist_xray_pa", withExtension: "jpg")
            if let url, let img = UIImage(contentsOfFile: url.path) {
                let hgt: CGFloat = 630, wid = hgt * img.size.width / img.size.height
                img.draw(in: CGRect(x: 30, y: 75, width: wid, height: hgt))
                img.draw(in: CGRect(x: 60 + wid, y: 75, width: wid, height: hgt))
            }
            text("R", at: CGPoint(x: 44, y: 84), size: 40, weight: .bold, color: .white)
            text("W 2000  L 500\n1 / 2", at: CGPoint(x: 1000, y: 640), size: 22, weight: .regular, color: UIColor(white: 0.7, alpha: 1))
        }
    }

    /// ECG (0), pleth (1) or respiration (2) trace across `rect`.
    nonisolated private static func trace(in rect: CGRect, color: UIColor, kind: Int, beats: Int) {
        let path = UIBezierPath()
        let n = 600
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n), ph = (t * CGFloat(beats)).truncatingRemainder(dividingBy: 1)
            var y: CGFloat
            switch kind {
            case 0: y = ph < 0.1 ? 0.08 * sin(ph / 0.1 * .pi) : ph < 0.16 ? 0 : ph < 0.18 ? -0.15 : ph < 0.21 ? 1 : ph < 0.24 ? -0.3 : ph < 0.3 ? 0 : ph < 0.45 ? 0.18 * sin((ph - 0.3) / 0.15 * .pi) : 0
            case 1: y = ph < 0.3 ? sin(ph / 0.3 * .pi / 2) : 0.15 * sin((ph - 0.3) / 0.15 * .pi) * (ph < 0.45 ? 1 : 0) + (1 - (ph - 0.3) / 0.7)
            default: y = 0.5 + 0.5 * sin(ph * 2 * .pi)
            }
            let pt = CGPoint(x: rect.minX + t * rect.width, y: rect.maxY - (kind == 0 ? 0.25 + 0.7 * y : 0.1 + 0.8 * y) * rect.height)
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        color.setStroke(); path.lineWidth = 4; path.lineJoinStyle = .round; path.stroke()
    }

    // MARK: Helpers

    private static func drawn(_ w: Int, _ h: Int, _ draw: (CGRect) -> Void) -> UnlitMaterial {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in draw(CGRect(x: 0, y: 0, width: w, height: h)) }
        var m = UnlitMaterial(color: .white)
        if let cg = img.cgImage, let t = try? TextureResource(image: cg, options: .init(semantic: .color)) { m.color = .init(tint: .white, texture: .init(t)) }
        return m
    }

    nonisolated private static func text(_ s: String, at p: CGPoint, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
        (s as NSString).draw(at: p, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
    }

    /// PBR set with its normal/roughness maps but a flat colour: the downloaded albedos are too grey for a resus bay.
    private static func tinted(_ prefix: String, tiling: SIMD2<Float>, _ c: UIColor, roughness: Float) -> PhysicallyBasedMaterial {
        var m = PitchKit.material(prefix, tiling: tiling, roughness: roughness)
        m.baseColor = .init(tint: c)
        return m
    }

    private static func pbr(_ c: UIColor, _ rough: Float, metal: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        let a = c.cgColor.alpha
        if a < 1 { m.blending = .transparent(opacity: .init(floatLiteral: Float(a))) }
        return m
    }

    private static func wall(_ e: Entity, size: SIMD2<Float>, at p: SIMD3<Float>, yaw: Float, tint: UIColor) {
        let m = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y),
                            materials: [tinted("traumabay_wall", tiling: [size.x / 1.5, size.y / 1.5], tint, roughness: 0.9)])
        m.position = p; m.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.addChild(m)
    }

    @discardableResult
    private static func box(_ e: Entity, _ s: SIMD3<Float>, _ m: Material, at p: SIMD3<Float>, yaw: Float = 0, corner: Float = 0) -> ModelEntity {
        let b = ModelEntity(mesh: .generateBox(size: s, cornerRadius: corner), materials: [m])
        b.position = p; b.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.addChild(b)
        return b
    }

    private enum Axis { case x, y, z }
    private static func cyl(_ e: Entity, _ h: Float, _ r: Float, _ m: Material, at p: SIMD3<Float>, axis: Axis = .y) {
        let c = ModelEntity(mesh: .generateCylinder(height: h, radius: r), materials: [m])
        c.position = p
        if axis == .x { c.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) }
        if axis == .z { c.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) }
        e.addChild(c)
    }

    private static func rod(_ e: Entity, from a: SIMD3<Float>, to b: SIMD3<Float>, radius: Float, _ m: Material) {
        let c = ModelEntity(mesh: .generateCylinder(height: simd_distance(a, b), radius: radius), materials: [m])
        c.position = (a + b) / 2
        c.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(b - a))
        e.addChild(c)
    }

    private static func plane(_ e: Entity, _ s: SIMD2<Float>, _ m: Material, at p: SIMD3<Float>) {
        let q = ModelEntity(mesh: .generatePlane(width: s.x, height: s.y), materials: [m])
        q.position = p
        e.addChild(q)
    }
}
