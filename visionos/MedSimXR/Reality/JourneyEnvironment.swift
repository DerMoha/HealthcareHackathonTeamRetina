import RealityKit
import UIKit

/// The surroundings of a journey case, drawn around the patient while the immersive space is in
/// full immersion: the road accident outdoors, the inside of the ambulance, and the emergency
/// department bay. Each brings its own seat for the patient (a low wall, the stretcher, the
/// trolley); the clinic stool is hidden. Built from plain shapes, so it needs no assets.
///
/// Avatar space: metres, Y up, origin on the floor under the patient, patient faces +Z and the
/// learner stands about 1 m in front (+Z), looking towards -Z. What the learner should see of the
/// scene (the crashed car, the road) therefore lies behind the patient, at -Z.
@MainActor
final class JourneyEnvironment {
    let root = Entity()
    private var built: String?

    func install(on avatar: PatientAvatar) {
        root.name = "journey_environment"
        avatar.root.addChild(root)
    }

    /// `kind`: the journey stage id (`scene`, `ambulance`, `hospital`); nil removes everything.
    /// Unknown ids fall back by position: first stage outdoors, last in hospital, others in the vehicle.
    func build(_ stageId: String?, index: Int, count: Int, seatHeight: Float) {
        let kind: String? = stageId.map { id in
            ["scene", "ambulance", "hospital"].contains(id) ? id : index == 0 ? "scene" : index == count - 1 ? "hospital" : "ambulance"
        }
        let key = kind.map { "\($0)@\(seatHeight)" }
        guard key != built else { return }
        built = key
        Array(root.children).forEach { $0.removeFromParent() }
        switch kind {
        case "scene": roadside(seat: seatHeight)
        case "ambulance": ambulanceInterior(seat: seatHeight)
        case "hospital": hospitalBay(seat: seatHeight)
        default: break
        }
        SmokeLog.mark("environment kind=\(kind ?? "none") seat=\(seatHeight) parts=\(Self.count(root))")
    }

    private static func count(_ e: Entity) -> Int { e.children.reduce(0) { $0 + 1 + count($1) } }

    // MARK: Roadside

    private func roadside(seat: Float) {
        sky(UIColor(red: 0.6, green: 0.76, blue: 0.94, alpha: 1))
        sun(intensity: 3500)
        let asphalt = UIColor(white: 0.17, alpha: 1), paving = UIColor(white: 0.6, alpha: 1)
        let white = UIColor(white: 0.95, alpha: 1)

        // Ground: grass far out, pavement under the patient and the learner, the road behind the patient.
        plane([200, 200], UIColor(red: 0.32, green: 0.47, blue: 0.24, alpha: 1), [0, -0.02, 0])
        plane([140, 9], paving, [0, 0.001, 2.6])            // z -1.9 ... 7.1
        box([140, 0.13, 0.25], UIColor(white: 0.72, alpha: 1), [0, 0.065, -1.95])  // kerb
        plane([140, 8], asphalt, [0, 0.002, -6])             // road, z -10 ... -2
        plane([140, 3], paving, [0, 0.001, -11.5])           // far pavement
        box([140, 0.13, 0.25], UIColor(white: 0.72, alpha: 1), [0, 0.065, -10.05])
        for x in stride(from: -48, through: 48, by: 4) {     // centre line
            plane([2, 0.12], white, [Float(x), 0.004, -6])
        }
        plane([140, 0.1], white, [0, 0.004, -2.3])
        plane([140, 0.1], white, [0, 0.004, -9.7])

        // The patient sits on a low brick wall at the edge of the pavement.
        let brick = UIColor(red: 0.58, green: 0.27, blue: 0.19, alpha: 1)
        box([1.3, seat - 0.05, 0.4], brick, [0, (seat - 0.05) / 2, -0.12], r: 0.01)
        box([1.36, 0.05, 0.46], UIColor(white: 0.74, alpha: 1), [0, seat - 0.025, -0.12], r: 0.01)

        // The accident: a car that hit the cyclist, his bicycle and helmet in the road, debris, cones.
        let car = car(UIColor(red: 0.62, green: 0.08, blue: 0.08, alpha: 1), at: [2.4, 0, -5.4], yaw: 0.42, crumpled: true)
        for z: Float in [0.8, -0.8] { glow(box([0.12, 0.08, 0.2], .systemOrange, [2.06, 0.75, z], to: car)) }   // hazard lights
        bicycle(at: [-0.8, 0, -3.4], yaw: 0.6)
        let helmet = add(.generateSphere(radius: 0.14), UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1), [0.3, 0.08, -2.7])
        helmet.scale = [1, 0.65, 1.3]
        for (i, p) in [SIMD3<Float>(0.9, 0.01, -3.9), [1.2, 0.01, -4.3], [0.6, 0.01, -4.6], [1.6, 0.01, -3.6]].enumerated() {
            box([0.12 + 0.04 * Float(i % 2), 0.015, 0.08], i % 2 == 0 ? UIColor(white: 0.85, alpha: 1) : .systemRed, p, yaw: Float(i))
        }
        for x: Float in [-3.2, -1.9, 4.6, 5.9] { cone(at: [x, 0, -2.7]) }
        for p: SIMD3<Float> in [[0.2, 0, -7.4], [4.6, 0, -7.6]] { cone(at: p) }

        // The ambulance that came for him, and a police car closing the lane.
        ambulanceVehicle(at: [-5.6, 0, -4.6], yaw: 0)
        let police = car(UIColor(white: 0.96, alpha: 1), at: [8.6, 0, -7.6], yaw: .pi, crumpled: false)
        box([4.14, 0.16, 1.84], UIColor(red: 0.1, green: 0.25, blue: 0.8, alpha: 1), [0, 0.62, 0], to: police)   // blue band
        for z: Float in [0.3, -0.3] { glow(box([0.3, 0.1, 0.25], z > 0 ? .systemBlue : .systemRed, [-0.25, 1.53, z], to: police)) }

        // Street: lamps and trees on the pavement, houses on both sides.
        for x: Float in [-9, 4.2, 15] { lamp(at: [x, 0, -1.6]) }
        for x: Float in [-4.2, 6.5, -11, 11.5] { tree(at: [x, 0, 2.6]) }
        street(facadeZ: -13.2, facing: 1)
        street(facadeZ: 8.6, facing: -1)
    }

    // MARK: Ambulance

    private func ambulanceInterior(seat: Float) {
        sky(UIColor(white: 0.06, alpha: 1))
        sun(intensity: 700)
        pointLight(at: [0, 1.95, 0.4], intensity: 26000)
        let wall = UIColor(white: 0.92, alpha: 1), steel = UIColor(white: 0.75, alpha: 1)
        let (h, zb, zf): (Float, Float, Float) = (2.1, -2.1, 2.9)
        let mid = (zb + zf) / 2, len = zf - zb
        plane([2.3, len], UIColor(red: 0.42, green: 0.48, blue: 0.5, alpha: 1), [0, 0.003, mid])
        box([0.06, h, len], wall, [-1.18, h / 2, mid])
        box([0.06, h, len], wall, [1.18, h / 2, mid])
        box([2.42, 0.06, len], wall, [0, h, mid])
        box([2.42, h, 0.06], wall, [0, h / 2, zb])
        box([2.42, h, 0.06], UIColor(white: 0.85, alpha: 1), [0, h / 2, zf])                 // rear doors
        for x: Float in [-0.45, 0.45] {
            glow(box([0.6, 0.45, 0.02], UIColor(red: 0.7, green: 0.82, blue: 0.95, alpha: 1), [x, 1.45, zf - 0.04]))  // windows
        }
        box([0.03, 1.9, 0.02], UIColor(white: 0.5, alpha: 1), [0, 0.95, zf - 0.04])          // door gap
        // battenburg strip inside the doors, so the vehicle reads as an ambulance
        for i in 0..<8 { box([0.29, 0.14, 0.02], i % 2 == 0 ? .systemYellow : .systemGreen, [-1.02 + Float(i) * 0.29, 0.9, zf - 0.04]) }

        // Stretcher the patient sits on, across the vehicle.
        box([1.9, 0.12, 0.62], UIColor(red: 0.95, green: 0.55, blue: 0.12, alpha: 1), [0, seat - 0.06, -0.12], r: 0.03)
        box([1.8, 0.05, 0.55], steel, [0, seat - 0.2, -0.12], metal: true)
        box([0.3, 0.1, 0.5], UIColor(white: 0.97, alpha: 1), [-0.75, seat + 0.03, -0.12], r: 0.04)  // pillow
        for x: Float in [-0.8, 0.8] {
            add(.generateCylinder(height: seat - 0.2, radius: 0.025), steel, [x, (seat - 0.2) / 2, -0.12], metal: true)
        }
        // Cabinets, bench, oxygen, monitor, ceiling lights and the grab rail.
        box([0.42, 0.95, 1.9], UIColor(white: 0.86, alpha: 1), [-0.94, 1.45, 1.55], r: 0.02)
        for z: Float in [0.95, 1.55, 2.15] { box([0.02, 0.04, 0.3], steel, [-0.72, 1.45, z]) }
        box([0.46, 0.45, 1.6], UIColor(white: 0.8, alpha: 1), [0.93, 0.23, 1.75])
        box([0.44, 0.08, 1.58], UIColor(red: 0.85, green: 0.45, blue: 0.1, alpha: 1), [0.93, 0.49, 1.75], r: 0.02)
        add(.generateCylinder(height: 0.9, radius: 0.09), UIColor(red: 0.1, green: 0.5, blue: 0.25, alpha: 1), [1.0, 0.45, -1.7], metal: true)
        add(.generateCylinder(height: 0.08, radius: 0.09), white, [1.0, 0.94, -1.7])
        monitor(at: [0.55, 1.45, zb + 0.07], facing: 0, text: "HR 104  BP 120/76  SpO2 98%")
        for z: Float in [-1.2, 0.6, 2.2] { glow(box([0.9, 0.02, 0.25], UIColor(white: 1, alpha: 1), [0, h - 0.035, z])) }
        add(.generateCylinder(height: len - 0.3, radius: 0.02), .systemYellow, [0.55, h - 0.18, mid],
            tilt: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]), metal: true)
    }

    // MARK: Emergency department

    private func hospitalBay(seat: Float) {
        sky(UIColor(white: 0.85, alpha: 1))
        sun(intensity: 1600)
        pointLight(at: [0, 2.8, 0.2], intensity: 40000)
        let paleGreen = UIColor(red: 0.78, green: 0.88, blue: 0.83, alpha: 1), white = UIColor(white: 0.97, alpha: 1)
        let steel = UIColor(white: 0.75, alpha: 1)
        plane([7, 7], UIColor(red: 0.7, green: 0.76, blue: 0.8, alpha: 1), [0, 0.003, 0.5])
        box([7, 3, 0.1], paleGreen, [0, 1.5, -2.6])
        box([0.1, 3, 7], paleGreen, [-3.5, 1.5, 0.5])
        box([0.1, 3, 7], paleGreen, [3.5, 1.5, 0.5])
        box([7, 0.05, 7], white, [0, 3, 0.5])
        for z: Float in [-1.5, 0.8, 3] { glow(box([1.2, 0.02, 0.6], white, [0, 2.97, z])) }
        // Medical gas panel and a sign above the bed.
        box([1.8, 0.28, 0.08], white, [0, 1.55, -2.52])
        for (i, c) in [UIColor.systemGreen, .white, .systemYellow, .systemBlue].enumerated() {
            add(.generateCylinder(height: 0.04, radius: 0.035), c, [-0.6 + Float(i) * 0.4, 1.55, -2.46],
                tilt: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        }
        glow(text("RESUS 2", size: 0.16, color: UIColor(red: 0.1, green: 0.3, blue: 0.55, alpha: 1), at: [0, 2.2, -2.54]))

        // Trolley the patient sits on.
        box([1.9, 0.14, 0.72], UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1), [0, seat - 0.07, -0.12], r: 0.04)
        box([1.95, 0.06, 0.76], steel, [0, seat - 0.17, -0.12], metal: true)
        box([0.6, 0.06, 0.5], steel, [0, 0.12, -0.12], metal: true)
        for x: Float in [-0.85, 0.85] {
            add(.generateCylinder(height: seat - 0.2, radius: 0.03), steel, [x, (seat - 0.2) / 2 + 0.03, -0.12], metal: true)
            add(.generateSphere(radius: 0.05), UIColor(white: 0.2, alpha: 1), [x, 0.05, -0.12])
        }
        // Monitor on a stand, drip stand with a bag, resuscitation trolley, curtain, clock.
        add(.generateCylinder(height: 1.5, radius: 0.025), steel, [-1.6, 0.75, -1.7], metal: true)
        monitor(at: [-1.6, 1.6, -1.65], facing: 0.4, text: "HR 96  BP 122/78  SpO2 98%")
        add(.generateCylinder(height: 2.0, radius: 0.015), steel, [1.2, 1.0, -1.5], metal: true)
        box([0.16, 0.24, 0.04], UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), [1.2, 1.85, -1.48], r: 0.02)
        box([0.65, 1.0, 0.5], UIColor(red: 0.75, green: 0.12, blue: 0.12, alpha: 1), [-2.8, 0.5, -1.9], r: 0.02)
        for y: Float in [0.3, 0.55, 0.8] { box([0.6, 0.02, 0.02], UIColor(white: 0.9, alpha: 1), [-2.8, y, -1.64]) }
        for i in 0..<14 {
            box([0.04, 2.3, 0.3], i % 2 == 0 ? UIColor(red: 0.45, green: 0.62, blue: 0.82, alpha: 1)
                                              : UIColor(red: 0.4, green: 0.56, blue: 0.76, alpha: 1),
                [2.6 + Float(i % 2) * 0.05, 1.3, -2.4 + Float(i) * 0.28])
        }
        add(.generateCylinder(height: 0.03, radius: 0.18), white, [1.6, 2.35, -2.54], tilt: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
    }

    // MARK: Props

    @discardableResult
    private func car(_ color: UIColor, at p: SIMD3<Float>, yaw: Float, crumpled: Bool) -> Entity {
        let g = group(p, yaw)
        let dark = UIColor(white: 0.08, alpha: 1)
        box([4.1, 0.62, 1.8], color, [0, 0.62, 0], r: 0.12, metal: true, to: g)
        box([2.1, 0.52, 1.62], color, [-0.25, 1.18, 0], r: 0.12, metal: true, to: g)
        box([2.14, 0.36, 1.66], dark, [-0.25, 1.2, 0], r: 0.08, to: g)                         // windows
        if crumpled { // bonnet pushed up and the windscreen cracked
            box([0.95, 0.07, 1.7], color, [1.55, 1.0, 0], tilt: simd_quatf(angle: 0.35, axis: [0, 0, 1]), metal: true, to: g)
            box([0.03, 0.4, 1.3], UIColor(white: 0.85, alpha: 1), [0.82, 1.22, 0.1], to: g)
        }
        for (x, z): (Float, Float) in [(1.3, 0.86), (1.3, -0.86), (-1.3, 0.86), (-1.3, -0.86)] {
            add(.generateCylinder(height: 0.24, radius: 0.33), dark, [x, 0.33, z], tilt: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]), to: g)
        }
        for z: Float in [0.6, -0.6] { glow(box([0.04, 0.12, 0.3], UIColor(white: 1, alpha: 1), [2.05, 0.7, z], to: g)) }
        return g
    }

    private func ambulanceVehicle(at p: SIMD3<Float>, yaw: Float) {
        let g = group(p, yaw)
        let white = UIColor(white: 0.97, alpha: 1), dark = UIColor(white: 0.08, alpha: 1)
        box([4.2, 2.3, 2.1], white, [-0.6, 1.5, 0], r: 0.08, to: g)
        box([1.4, 1.5, 2.0], white, [2.2, 1.1, 0], r: 0.1, to: g)
        box([0.05, 0.6, 1.8], dark, [2.91, 1.45, 0], to: g)
        for i in 0..<12 {
            let x = -2.45 + Float(i) * 0.47
            box([0.47, 0.42, 2.16], i % 2 == 0 ? .systemYellow : .systemGreen, [x, 1.0, 0], to: g)
        }
        for (x, z): (Float, Float) in [(-2.3, 0.7), (-2.3, -0.7), (1.8, 0.6), (1.8, -0.6)] {
            glow(box([0.25, 0.12, 0.25], .systemBlue, [x, x < 0 ? 2.71 : 1.91, z], to: g))
        }
        for (x, z): (Float, Float) in [(1.9, 0.95), (1.9, -0.95), (-1.7, 0.95), (-1.7, -0.95)] {
            add(.generateCylinder(height: 0.26, radius: 0.38), dark, [x, 0.38, z], tilt: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]), to: g)
        }
        glow(text("AMBULANCE", size: 0.28, color: UIColor(red: 0.05, green: 0.4, blue: 0.15, alpha: 1), at: [-0.6, 1.95, 1.09], to: g))
        let back = Entity() // the far side reads correctly from the other side of the vehicle
        back.position = [-0.6, 1.95, -1.09]
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        g.addChild(back)
        glow(text("AMBULANCE", size: 0.28, color: UIColor(red: 0.05, green: 0.4, blue: 0.15, alpha: 1), at: [0, 0, 0], to: back))
    }

    private func bicycle(at p: SIMD3<Float>, yaw: Float) {
        let g = group(p, yaw)
        let dark = UIColor(white: 0.1, alpha: 1), frame = UIColor(red: 0.1, green: 0.55, blue: 0.75, alpha: 1)
        for x: Float in [-0.52, 0.52] { // lying on its side: the wheels are flat on the road
            add(.generateCylinder(height: 0.035, radius: 0.34), dark, [x, 0.02, 0], to: g)
            add(.generateCylinder(height: 0.045, radius: 0.27), UIColor(white: 0.3, alpha: 1), [x, 0.024, 0], to: g)
            add(.generateCylinder(height: 0.06, radius: 0.04), UIColor(white: 0.7, alpha: 1), [x, 0.03, 0], metal: true, to: g)
        }
        box([1.0, 0.035, 0.04], frame, [0, 0.06, 0.06], to: g)
        box([0.62, 0.035, 0.04], frame, [0.12, 0.06, -0.12], yaw: 0.65, to: g)
        box([0.04, 0.035, 0.52], UIColor(white: 0.6, alpha: 1), [0.48, 0.07, 0.05], metal: true, to: g)   // handlebar
        box([0.22, 0.05, 0.1], dark, [-0.3, 0.07, -0.2], to: g)                                           // saddle
    }

    private func cone(at p: SIMD3<Float>) {
        add(.generateBox(size: [0.34, 0.03, 0.34]), UIColor(white: 0.1, alpha: 1), p + [0, 0.015, 0])
        add(.generateCone(height: 0.5, radius: 0.13), .systemOrange, p + [0, 0.28, 0])
        add(.generateCylinder(height: 0.06, radius: 0.085), UIColor(white: 0.95, alpha: 1), p + [0, 0.33, 0])
    }

    private func lamp(at p: SIMD3<Float>) {
        let grey = UIColor(white: 0.4, alpha: 1)
        add(.generateCylinder(height: 6, radius: 0.07), grey, p + [0, 3, 0], metal: true)
        box([0.08, 0.08, 1.4], grey, p + [0, 6, -0.65], metal: true)
        glow(box([0.25, 0.08, 0.45], UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), p + [0, 5.94, -1.3]))
    }

    private func tree(at p: SIMD3<Float>) {
        add(.generateCylinder(height: 2.4, radius: 0.13), UIColor(red: 0.35, green: 0.23, blue: 0.13, alpha: 1), p + [0, 1.2, 0])
        add(.generateSphere(radius: 1.2), UIColor(red: 0.2, green: 0.45, blue: 0.2, alpha: 1), p + [0, 3.2, 0])
        add(.generateSphere(radius: 0.8), UIColor(red: 0.24, green: 0.5, blue: 0.22, alpha: 1), p + [0.6, 2.8, 0.3])
    }

    /// A row of houses with windows on the side that faces the road (`facing` +1: +Z, -1: -Z).
    private func street(facadeZ: Float, facing: Float) {
        let heights: [Float] = [8, 12, 9, 15, 7, 11, 17, 10, 13, 9]
        let colors = [UIColor(red: 0.82, green: 0.76, blue: 0.64, alpha: 1), UIColor(red: 0.6, green: 0.35, blue: 0.28, alpha: 1),
                      UIColor(white: 0.7, alpha: 1), UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1)]
        let glass = UIColor(red: 0.25, green: 0.33, blue: 0.42, alpha: 1)
        for (i, h) in heights.enumerated() {
            let x = -45 + Float(i) * 10, depth: Float = 8
            box([9, h, depth], colors[i % colors.count], [x, h / 2, facadeZ - facing * depth / 2])
            for row in stride(from: Float(1.8), to: h - 1, by: 3) {
                for col in [-3.0, -1.0, 1.0, 3.0] as [Float] {
                    box([1.1, 1.3, 0.06], glass, [x + col, row, facadeZ + facing * 0.02], metal: true)
                }
            }
            box([1.2, 2.2, 0.06], UIColor(red: 0.3, green: 0.2, blue: 0.12, alpha: 1), [x + 2, 1.1, facadeZ + facing * 0.03])
        }
    }

    private func monitor(at p: SIMD3<Float>, facing yaw: Float, text label: String) {
        let g = group(p, yaw)
        box([0.5, 0.36, 0.1], UIColor(white: 0.2, alpha: 1), [0, 0, 0], r: 0.02, to: g)
        glow(box([0.44, 0.28, 0.01], UIColor(white: 0.02, alpha: 1), [0, 0.01, 0.052], to: g))
        for (i, y) in [Float(0.06), -0.02].enumerated() {
            glow(box([0.38, 0.008, 0.004], i == 0 ? .systemGreen : .systemYellow, [0, y, 0.06], to: g))
        }
        glow(text(label, size: 0.022, color: .systemGreen, at: [0, -0.1, 0.06], to: g))
    }

    // MARK: Building blocks

    private func sky(_ color: UIColor) {
        var m = UnlitMaterial(color: color)
        m.faceCulling = .none // seen from inside
        let dome = ModelEntity(mesh: .generateSphere(radius: 90), materials: [m])
        root.addChild(dome)
    }

    private func sun(intensity: Float) {
        let light = Entity()
        light.components.set(DirectionalLightComponent(color: .white, intensity: intensity))
        light.components.set(DirectionalLightComponent.Shadow())
        root.addChild(light)
        light.look(at: [0, 0, 0], from: [3, 8, 5], relativeTo: root)
    }

    private func pointLight(at p: SIMD3<Float>, intensity: Float) {
        let light = Entity()
        light.components.set(PointLightComponent(color: .white, intensity: intensity, attenuationRadius: 7))
        light.position = p
        root.addChild(light)
    }

    private func group(_ p: SIMD3<Float>, _ yaw: Float) -> Entity {
        let g = Entity()
        g.position = p
        g.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        root.addChild(g)
        return g
    }

    @discardableResult
    private func add(_ mesh: MeshResource, _ color: UIColor, _ p: SIMD3<Float>, yaw: Float = 0, tilt: simd_quatf? = nil,
                     metal: Bool = false, to parent: Entity? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, roughness: .float(metal ? 0.35 : 0.85), isMetallic: metal)])
        e.position = p
        e.orientation = tilt ?? simd_quatf(angle: yaw, axis: [0, 1, 0])
        (parent ?? root).addChild(e)
        return e
    }

    @discardableResult
    private func box(_ size: SIMD3<Float>, _ color: UIColor, _ p: SIMD3<Float>, yaw: Float = 0, tilt: simd_quatf? = nil,
                     r: Float = 0, metal: Bool = false, to parent: Entity? = nil) -> ModelEntity {
        add(.generateBox(size: size, cornerRadius: r), color, p, yaw: yaw, tilt: tilt, metal: metal, to: parent)
    }

    private func plane(_ size: SIMD2<Float>, _ color: UIColor, _ p: SIMD3<Float>) {
        add(.generatePlane(width: size.x, depth: size.y), color, p)
    }

    /// Makes a part self-lit (lamps, screens, warning lights): it keeps its colour in any light.
    private func glow(_ e: ModelEntity) {
        guard var model = e.model, let simple = model.materials.first as? SimpleMaterial else { return }
        model.materials = [UnlitMaterial(color: simple.color.tint)]
        e.model = model
    }

    @discardableResult
    private func text(_ string: String, size: CGFloat, color: UIColor, at p: SIMD3<Float>, to parent: Entity? = nil) -> ModelEntity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.004, font: .boldSystemFont(ofSize: size))
        let model = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
        model.position = p + [-mesh.bounds.extents.x / 2 - mesh.bounds.min.x, 0, 0]
        (parent ?? root).addChild(model)
        return model
    }
}
