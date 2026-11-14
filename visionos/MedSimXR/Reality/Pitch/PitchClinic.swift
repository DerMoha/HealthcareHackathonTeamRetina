import RealityKit
import UIKit

/// Pitch dressing: a bright fracture / outpatient clinic room (wrist case), lit by the hospital_room HDRI.
/// Avatar space: patient at the origin facing +Z, wearer at +Z looking at -Z; +X is the wearer's right.
/// The orthotics tray (OrthoticsLab, about [-0.58, 0.95, 0.55]) stays where it is, so nothing is built there.
@MainActor
enum PitchClinic {
    nonisolated static let w: Float = 3.6, back: Float = -4.2, front: Float = 3.5, h: Float = 2.8

    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        shell(set)
        window(set)
        couchBay(set)
        sinkWall(set)
        desk(set)
        posters(set)
        ceilingLights(set)
        patientStool(set, seat: seat, avatarRoot: avatarRoot)
        PitchKit.place("clinic_plant", in: set, at: [3.15, 0, -2.75], yaw: 0.4, fit: 1.25)
        PitchKit.place("clinic_plant2", in: set, at: [-3.15, 0, -0.3], yaw: 0.2, fit: 1.0)
        PitchKit.place("clinic_wheelchair", in: set, at: [2.55, 0, -1.2], yaw: -2.2, fit: 1.05)
        PitchKit.place("clinic_clock", in: set, at: [-0.15, 2.2, back + 0.02], fit: 0.32, shadow: false)
        PitchKit.light(avatarRoot, hdri: "clinic_ibl", intensity: 0.9)
        // The floor opts out of the HDRI so the key light's shadows (patient, furniture) land on it.
        if let floor = set.findEntity(named: "clinic_floor") { PitchKit.showShadows(on: floor) }
        PitchKit.sun(set, from: [0.8, 3.2, 1.6], to: [0, 0, -0.6], intensity: 4200, color: UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1))
        // Ceiling fittings and the curtain would throw hard blocks onto the floor and walls.
        noShadows(set)
        return true
    }

    // MARK: Room

    private static func shell(_ e: Entity) {
        let floor = plane(e, [2 * w, front - back], PitchKit.material("clinic_floor", tiling: [2 * w / 1.6, (front - back) / 1.6], roughness: 0.8),
                          at: [0, 0, (front + back) / 2], horizontal: true)
        floor.name = "clinic_floor"
        var tiles = PitchKit.material("clinic_ceiling", tiling: [2 * w / 1.2, (front - back) / 1.2])
        // White 600 mm tiles in a grey grid (the texture's own albedo is beige), its relief kept.
        if let grid = ceilingGrid() { tiles.baseColor = .init(texture: .init(grid)) }
        let ceil = plane(e, [2 * w, front - back], tiles, at: [0, h, (front + back) / 2], horizontal: true)
        ceil.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        // Back, right, front walls; the left wall is built around the window.
        wall(e, width: 2 * w, at: [0, 0, back], yaw: 0)
        wall(e, width: front - back, at: [w, 0, (front + back) / 2], yaw: -.pi / 2)
        wall(e, width: 2 * w, at: [0, 0, front], yaw: .pi)
        // Wall protection: coved skirting, a pale PVC crash band with a maple handrail on top.
        let skirt = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.62, alpha: 1), roughness: 0.6)
        let band = PitchKit.material("clinic_plastic", tint: UIColor(red: 0.86, green: 0.9, blue: 0.9, alpha: 1), roughness: 0.5)
        let rail = PitchKit.material("clinic_maple", tiling: [6, 1], roughness: 0.6)
        for (p, s) in [(SIMD3<Float>(0, 0, back + 0.01), SIMD3<Float>(2 * w, 0, 0.02)),
                       (SIMD3<Float>(-w + 0.01, 0, (front + back) / 2), SIMD3<Float>(0.02, 0, front - back)),
                       (SIMD3<Float>(w - 0.01, 0, (front + back) / 2), SIMD3<Float>(0.02, 0, front - back))] {
            box(e, s + [0, 0.1, 0], skirt, at: p + [0, 0.05, 0])
            box(e, s + [0, 0.2, 0], band, at: p + [0, 0.84, 0])
            let along = s.x > 0.1 // back wall runs along x, side walls along z
            box(e, along ? [s.x, 0.05, 0.06] : [0.06, 0.05, s.z], rail,
                at: p + (along ? [0, 0.97, 0.03] : [p.x < 0 ? 0.03 : -0.03, 0.97, 0]))
        }
    }

    /// Painted wall: a plane `width` wide, full height, standing on `at` and facing `yaw`.
    private static func wall(_ e: Entity, width: Float, height: Float = h, at p: SIMD3<Float>, yaw: Float, y0: Float = 0) {
        // Fresh paint over the plaster's relief: keep its normal/roughness, drop its beige albedo.
        var m = PitchKit.material("clinic_wall", tiling: [width / 1.5, height / 1.5], roughness: 0.9)
        m.baseColor = .init(tint: paint)
        let q = plane(e, [width, height], m, at: p + [0, y0 + height / 2, 0])
        q.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }

    private static let paint = UIColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1)

    // MARK: Window (left wall), real exterior photo behind it

    private static func window(_ e: Entity) {
        let z0: Float = -2.75, z1: Float = -0.55, y0: Float = 0.95, y1: Float = 2.25
        let x = -w
        wall(e, width: z0 - back, at: [x, 0, (back + z0) / 2], yaw: .pi / 2)
        wall(e, width: front - z1, at: [x, 0, (z1 + front) / 2], yaw: .pi / 2)
        wall(e, width: z1 - z0, height: y0, at: [x, 0, (z0 + z1) / 2], yaw: .pi / 2)
        wall(e, width: z1 - z0, height: h - y1, at: [x, 0, (z0 + z1) / 2], yaw: .pi / 2, y0: y1)
        // The view, a little outside so it has depth.
        var view = UnlitMaterial()
        if let t = PitchKit.texture("clinic_window_view.jpg") { view.color = .init(tint: UIColor(white: 0.97, alpha: 1), texture: .init(t)) }
        let v = plane(e, [3.6, 2.25], view, at: [x - 0.9, 1.45, (z0 + z1) / 2])
        v.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        // Frame, reveals, mullion and sill in white powder-coat.
        let white = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.97, alpha: 1), roughness: 0.4)
        let d: Float = 0.18, cz = (z0 + z1) / 2, cy = (y0 + y1) / 2
        box(e, [d, 0.06, z1 - z0 + 0.12], white, at: [x - d / 2 + 0.02, y1 + 0.03, cz])
        box(e, [d, 0.06, z1 - z0 + 0.12], white, at: [x - d / 2 + 0.02, y0 - 0.03, cz])
        for z in [z0 - 0.03, z1 + 0.03] { box(e, [d, y1 - y0, 0.06], white, at: [x - d / 2 + 0.02, cy, z]) }
        box(e, [0.06, y1 - y0, 0.05], white, at: [x - d + 0.05, cy, cz])
        box(e, [0.05, 0.05, z1 - z0], white, at: [x - d + 0.05, y0 + 0.45, cz])
        box(e, [0.26, 0.03, z1 - z0 + 0.2], white, at: [x + 0.08, y0 - 0.015, cz]) // sill
        // Roller blind a third of the way down.
        let blind = PitchKit.material("clinic_fabric", tiling: [2, 1], tint: UIColor(white: 0.98, alpha: 1), roughness: 0.9)
        box(e, [0.06, 0.08, z1 - z0 + 0.1], white, at: [x + 0.06, y1 + 0.1, cz])
        let b = plane(e, [z1 - z0, 0.26], blind, at: [x + 0.04, y1 - 0.11, cz])
        b.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        box(e, [0.02, 0.025, z1 - z0], white, at: [x + 0.04, y1 - 0.25, cz])
    }

    // MARK: Examination couch with privacy curtain (back left)

    private static func couchBay(_ e: Entity) {
        let cx: Float = -2.45, cz = back + 0.45, top: Float = 0.68
        let base = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.93, alpha: 1), roughness: 0.5)
        let vinyl = PitchKit.material("clinic_vinyl", tiling: [3, 1], tint: UIColor(red: 0.2, green: 0.3, blue: 0.42, alpha: 1), roughness: 0.7)
        let steel = PitchKit.material("clinic_steel", tiling: [2, 2], roughness: 0.6)
        box(e, [1.5, 0.08, 0.5], steel, at: [cx, 0.04, cz])               // wheeled chassis
        box(e, [0.5, top - 0.18, 0.36], base, at: [cx, (top - 0.08) / 2 + 0.04, cz]) // lift column
        box(e, [1.86, 0.06, 0.62], steel, at: [cx + 0.03, top - 0.09, cz])
        box(e, [1.3, 0.09, 0.64], vinyl, at: [cx + 0.3, top - 0.02, cz])  // seat/leg section
        let backrest = box(e, [0.62, 0.09, 0.64], vinyl, at: [cx - 0.62, top + 0.1, cz])
        backrest.orientation = simd_quatf(angle: -0.45, axis: [0, 0, 1])
        let paper = PitchKit.material("clinic_plastic", tint: .white, roughness: 0.9)
        box(e, [1.25, 0.004, 0.5], paper, at: [cx + 0.3, top + 0.027, cz])
        cylinder(e, height: 0.52, radius: 0.06, paper, at: [cx + 0.98, top - 0.02, cz], axis: [1, 0, 0])
        for dx: Float in [-0.68, 0.68] { for dz: Float in [-0.2, 0.2] {
            cylinder(e, height: 0.05, radius: 0.035, PitchKit.material("clinic_plastic", tint: UIColor(white: 0.2, alpha: 1)), at: [cx + dx, 0.035, cz + dz], axis: [0, 0, 1])
        } }
        PitchKit.contactShadow(e, at: [cx, 0, cz], size: [1.8, 0.6], opacity: 0.6)
        // Two-step stool in front of the couch.
        let grey = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.55, alpha: 1), roughness: 0.6)
        box(e, [0.5, 0.11, 0.38], grey, at: [cx + 0.4, 0.055, cz + 0.55])
        box(e, [0.5, 0.11, 0.19], grey, at: [cx + 0.4, 0.165, cz + 0.455])
        PitchKit.contactShadow(e, at: [cx + 0.4, 0, cz + 0.55], size: [0.5, 0.38])
        // Ceiling curtain track (an L round the bay) and the curtain gathered at the back wall.
        let track = PitchKit.material("clinic_steel", tint: UIColor(white: 0.9, alpha: 1), roughness: 0.4)
        let tx: Float = -1.35, tz: Float = -2.55
        box(e, [0.04, 0.03, tz - back], track, at: [tx, h - 0.06, (tz + back) / 2])
        box(e, [w - abs(tx) + 0.02, 0.03, 0.04], track, at: [(tx - w) / 2, h - 0.06, tz])
        for z in stride(from: back + 0.4, to: tz, by: 0.6) { box(e, [0.015, 0.06, 0.015], track, at: [tx, h - 0.03, z]) }
        let fabric = PitchKit.material("clinic_fabric", tiling: [3, 4], tint: UIColor(red: 0.72, green: 0.87, blue: 0.88, alpha: 1), roughness: 0.95)
        let mesh = UIColor(white: 0.97, alpha: 1)
        let c = curtain(width: 0.95, height: 2.2, pleats: 9, depth: 0.07, material: fabric)
        c.position = [tx, 0.32, back + 0.6]
        c.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0])
        e.addChild(c)
        let top2 = curtain(width: 0.95, height: 0.24, pleats: 9, depth: 0.05, material: PitchKit.material("clinic_fabric", tiling: [3, 0.5], tint: mesh))
        top2.position = [tx, 2.52, back + 0.6]
        top2.orientation = c.orientation
        e.addChild(top2)
    }

    // MARK: Hand-wash station, dispensers, sharps (back wall, right of centre)

    private static func sinkWall(_ e: Entity) {
        let sx: Float = 1.25, z = back
        let cab = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.95, alpha: 1), roughness: 0.45)
        let top = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.82, alpha: 1), roughness: 0.35)
        let steel = PitchKit.material("clinic_steel", tiling: [1, 1], roughness: 0.35)
        box(e, [1.3, 0.82, 0.58], cab, at: [sx, 0.47, z + 0.3])
        box(e, [1.3, 0.06, 0.58], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.35, alpha: 1)), at: [sx, 0.03, z + 0.29]) // plinth
        for dx: Float in [-0.325, 0.325] { box(e, [0.005, 0.7, 0.005], top, at: [sx + dx, 0.5, z + 0.592]) } // door gaps
        for dx: Float in [-0.06, 0.06] { box(e, [0.012, 0.14, 0.02], steel, at: [sx + dx, 0.72, z + 0.6]) } // handles
        box(e, [1.34, 0.04, 0.62], top, at: [sx, 0.9, z + 0.31])
        box(e, [0.5, 0.012, 0.38], steel, at: [sx, 0.921, z + 0.33])     // basin rim
        box(e, [0.42, 0.003, 0.3], PitchKit.material("clinic_steel", tint: UIColor(white: 0.55, alpha: 1), roughness: 0.3), at: [sx, 0.928, z + 0.33])
        cylinder(e, height: 0.3, radius: 0.016, steel, at: [sx, 1.07, z + 0.1])
        cylinder(e, height: 0.2, radius: 0.012, steel, at: [sx, 1.21, z + 0.2], axis: [0, 0, 1])
        cylinder(e, height: 0.04, radius: 0.012, steel, at: [sx, 1.19, z + 0.3])
        cylinder(e, height: 0.2, radius: 0.008, steel, at: [sx + 0.1, 1.0, z + 0.1], axis: [1, 0, 0]) // elbow lever
        // Tiled splashback.
        let tiles = plane(e, [1.34, 0.62], PitchKit.material("clinic_splash", tiling: [2, 1], roughness: 0.5), at: [sx, 1.23, z + 0.006])
        tiles.name = "splash"
        // Soap (left) and alcohol gel (right) dispensers, paper towels on top.
        dispenser(e, at: [sx - 0.42, 1.3, z], window: UIColor(red: 0.3, green: 0.62, blue: 0.95, alpha: 1), label: "Soap")
        dispenser(e, at: [sx + 0.42, 1.3, z], window: UIColor(red: 0.35, green: 0.78, blue: 0.5, alpha: 1), label: "Hand rub")
        box(e, [0.32, 0.36, 0.12], cab, at: [sx, 1.78, z + 0.06])
        box(e, [0.22, 0.01, 0.02], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.3, alpha: 1)), at: [sx, 1.61, z + 0.115])
        box(e, [0.18, 0.06, 0.003], PitchKit.material("clinic_plastic", tint: .white), at: [sx, 1.585, z + 0.115]) // towel tab
        // Glove dispenser: three boxes, S / M / L.
        let rack = PitchKit.material("clinic_steel", tint: UIColor(white: 0.85, alpha: 1), roughness: 0.4)
        let gx: Float = 2.25
        box(e, [0.29, 0.45, 0.01], rack, at: [gx, 1.42, z + 0.005])
        for (i, size) in ["S", "M", "L"].enumerated() {
            let y = 1.26 + Float(i) * 0.145
            box(e, [0.26, 0.12, 0.13], PitchKit.material("clinic_plastic", tint: .white, roughness: 0.6), at: [gx, y, z + 0.075])
            label(e, gloveBox(size), size: [0.26, 0.12], at: [gx, y, z + 0.141])
        }
        // Sharps bin on its wall bracket: yellow body, orange lid.
        let bx: Float = 2.25
        box(e, [0.2, 0.02, 0.18], rack, at: [bx, 0.98, z + 0.09])
        box(e, [0.2, 0.26, 0.17], PitchKit.material("clinic_plastic", tint: UIColor(red: 1, green: 0.82, blue: 0.1, alpha: 1), roughness: 0.45), at: [bx, 1.12, z + 0.095])
        box(e, [0.21, 0.05, 0.18], PitchKit.material("clinic_plastic", tint: UIColor(red: 0.97, green: 0.47, blue: 0.08, alpha: 1), roughness: 0.4), at: [bx, 1.275, z + 0.095])
        label(e, sharpsLabel(), size: [0.15, 0.11], at: [bx, 1.11, z + 0.181])
        // Clinical waste pedal bin (orange lid) and general waste (black lid) under the dispensers.
        for (x, lid) in [(Float(0.38), UIColor(red: 0.97, green: 0.5, blue: 0.1, alpha: 1)), (Float(0.0), UIColor(white: 0.15, alpha: 1))] {
            cylinder(e, height: 0.42, radius: 0.15, PitchKit.material("clinic_steel", tint: UIColor(white: 0.95, alpha: 1), roughness: 0.4), at: [x, 0.21, z + 0.2])
            cylinder(e, height: 0.03, radius: 0.155, PitchKit.material("clinic_plastic", tint: lid, roughness: 0.4), at: [x, 0.435, z + 0.2])
            PitchKit.contactShadow(e, at: [x, 0, z + 0.2], size: [0.3, 0.3])
        }
        PitchKit.contactShadow(e, at: [sx, 0, z + 0.3], size: [1.3, 0.55], opacity: 0.55)
    }

    private static func dispenser(_ e: Entity, at p: SIMD3<Float>, window: UIColor, label text: String) {
        box(e, [0.11, 0.22, 0.1], PitchKit.material("clinic_plastic", tint: .white, roughness: 0.35), at: p + [0, 0, 0.05])
        box(e, [0.07, 0.07, 0.005], PitchKit.material("clinic_plastic", tint: window, roughness: 0.2), at: p + [0, 0.03, 0.1])
        box(e, [0.08, 0.03, 0.03], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.85, alpha: 1)), at: p + [0, -0.085, 0.09])
        label(e, tag(text), size: [0.09, 0.03], at: p + [0, -0.04, 0.101])
    }

    // MARK: Clinician's desk (back right corner)

    private static func desk(_ e: Entity) {
        let dx: Float = 3.0, dz = back + 0.4
        let maple = PitchKit.material("clinic_maple", tiling: [2, 1], roughness: 0.7)
        let frame = PitchKit.material("clinic_steel", tint: UIColor(white: 0.92, alpha: 1), roughness: 0.4)
        box(e, [1.2, 0.03, 0.72], maple, at: [dx, 0.735, dz])
        for x: Float in [-0.56, 0.56] {
            box(e, [0.04, 0.72, 0.04], frame, at: [dx + x, 0.36, dz + 0.31])
            box(e, [0.04, 0.72, 0.04], frame, at: [dx + x, 0.36, dz - 0.31])
        }
        box(e, [0.42, 0.6, 0.6], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.9, alpha: 1), roughness: 0.5), at: [dx + 0.3, 0.38, dz]) // pedestal
        PitchKit.contactShadow(e, at: [dx, 0, dz], size: [1.2, 0.7])
        // Monitor showing the PACS viewer with a wrist film.
        let black = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.08, alpha: 1), roughness: 0.4)
        box(e, [0.2, 0.012, 0.16], black, at: [dx - 0.15, 0.756, dz - 0.18])
        box(e, [0.04, 0.24, 0.03], black, at: [dx - 0.15, 0.87, dz - 0.21])
        box(e, [0.6, 0.36, 0.025], black, at: [dx - 0.15, 1.1, dz - 0.19])
        var screen = UnlitMaterial()
        if let t = monitorScreen() { screen.color = .init(texture: .init(t)) }
        plane(e, [0.58, 0.34], screen, at: [dx - 0.15, 1.1, dz - 0.176])
        box(e, [0.44, 0.015, 0.14], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.9, alpha: 1), roughness: 0.5), at: [dx - 0.15, 0.758, dz + 0.08]) // keyboard
        box(e, [0.06, 0.02, 0.1], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.9, alpha: 1)), at: [dx + 0.2, 0.76, dz + 0.1])
        box(e, [0.21, 0.01, 0.3], PitchKit.material("clinic_plastic", tint: UIColor(white: 0.98, alpha: 1)), at: [dx + 0.38, 0.755, dz + 0.02]) // notes
        // Clinician's swivel chair, pulled out.
        swivel(e, at: [dx - 0.2, 0, dz + 0.75], seat: 0.48, yaw: 0.35, back: true,
               cushion: PitchKit.material("clinic_fabric", tiling: [1, 1], tint: UIColor(white: 0.3, alpha: 1), roughness: 0.95))
    }

    // MARK: Posters (back wall, above the patient's head in the shot)

    private static func posters(_ e: Entity) {
        posterFrame(e, scaphoidPoster(), size: [0.6, 0.85], at: [-0.75, 1.55, back])
        posterFrame(e, painPoster(), size: [0.6, 0.42], at: [0.2, 1.75, back])
        posterFrame(e, hygienePoster(), size: [0.42, 0.6], at: [2.55, 1.6, back])
        // Room sign by the curtain bay.
        label(e, roomSign(), size: [0.36, 0.12], at: [-1.6, 2.05, back + 0.006])
    }

    private static func posterFrame(_ e: Entity, _ tex: TextureResource?, size: SIMD2<Float>, at p: SIMD3<Float>) {
        box(e, [size.x + 0.03, size.y + 0.03, 0.015], PitchKit.material("clinic_steel", tint: UIColor(white: 0.85, alpha: 1), roughness: 0.4), at: p + [0, 0, 0.008])
        var m = PhysicallyBasedMaterial()
        if let tex { m.baseColor = .init(texture: .init(tex)) }
        m.roughness = 0.35
        plane(e, size, m, at: p + [0, 0, 0.017])
    }

    // MARK: Ceiling LED panels

    private static func ceilingLights(_ e: Entity) {
        let frame = PitchKit.material("clinic_steel", tint: UIColor(white: 0.95, alpha: 1), roughness: 0.4)
        let glow = UnlitMaterial(color: UIColor(red: 1, green: 0.99, blue: 0.96, alpha: 1))
        for x: Float in [-1.8, 0, 1.8] { for z: Float in [-3.0, -0.9, 1.4] {
            box(e, [0.62, 0.012, 0.62], frame, at: [x, h - 0.006, z])
            let p = plane(e, [0.58, 0.58], glow, at: [x, h - 0.0135, z], horizontal: true)
            p.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        } }
        // Fill so the patient and the floor read like a lit room, with real shadows from the main panel.
        PitchKit.spot(e, at: [0, h - 0.05, -0.9], target: [0, 0, 0.2], intensity: 6000, color: UIColor(red: 1, green: 0.97, blue: 0.92, alpha: 1), angle: 80)
    }

    // MARK: The patient's stool (encloses the avatar's own, which also shows in mixed reality)

    private static func patientStool(_ e: Entity, seat: Float, avatarRoot: Entity) {
        // The avatar's flat base disc would show through the five-star base; hide just that part.
        avatarRoot.children.filter { $0.name == "stool" && $0.position.y < 0.05 }.forEach { $0.isEnabled = false }
        swivel(e, at: [0, 0, -0.02], seat: seat, yaw: 0.3, back: false,
               cushion: PitchKit.material("clinic_vinyl", tint: UIColor(red: 0.2, green: 0.3, blue: 0.42, alpha: 1), roughness: 0.7))
    }

    /// Clinic swivel seat: chrome gas lift, five-star base on castors, round (stool) or square (chair) cushion.
    private static func swivel(_ e: Entity, at p: SIMD3<Float>, seat: Float, yaw: Float, back: Bool, cushion: PhysicallyBasedMaterial) {
        let root = Entity()
        root.position = p
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.addChild(root)
        let chrome = PitchKit.material("clinic_steel", tint: UIColor(white: 1, alpha: 1), roughness: 0.25)
        let dark = PitchKit.material("clinic_plastic", tint: UIColor(white: 0.12, alpha: 1), roughness: 0.5)
        for i in 0..<5 {
            let a = Float(i) / 5 * 2 * .pi
            let leg = box(root, [0.3, 0.035, 0.05], chrome, at: [cos(a) * 0.15, 0.075, sin(a) * 0.15])
            leg.orientation = simd_quatf(angle: -a, axis: [0, 1, 0])
            cylinder(root, height: 0.03, radius: 0.028, dark, at: [cos(a) * 0.29, 0.03, sin(a) * 0.29], axis: [0, 0, 1])
        }
        cylinder(root, height: 0.06, radius: 0.045, chrome, at: [0, 0.08, 0])
        cylinder(root, height: seat - 0.15, radius: 0.032, chrome, at: [0, 0.08 + (seat - 0.15) / 2, 0])
        if back {
            box(root, [0.48, 0.07, 0.46], cushion, at: [0, seat - 0.035, 0])
            box(root, [0.46, 0.5, 0.06], cushion, at: [0, seat + 0.38, 0.24])
            box(root, [0.05, 0.3, 0.04], dark, at: [0, seat + 0.1, 0.25])
        } else {
            cylinder(root, height: 0.03, radius: 0.16, dark, at: [0, seat - 0.085, 0])
            cylinder(root, height: 0.078, radius: 0.207, cushion, at: [0, seat - 0.036, 0])
        }
        PitchKit.contactShadow(e, at: p, size: [0.45, 0.45], opacity: 0.6)
    }

    private static func noShadows(_ e: Entity) {
        for c in e.children {
            if c is ModelEntity, c.name == "curtain" || c.visualBounds(relativeTo: nil).min.y > 2.3 {
                c.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            noShadows(c)
        }
    }

    // MARK: Geometry helpers

    @discardableResult
    private static func box(_ e: Entity, _ s: SIMD3<Float>, _ m: RealityKit.Material, at p: SIMD3<Float>) -> ModelEntity {
        let b = ModelEntity(mesh: .generateBox(size: s), materials: [m])
        b.position = p
        e.addChild(b)
        return b
    }

    @discardableResult
    private static func cylinder(_ e: Entity, height: Float, radius: Float, _ m: RealityKit.Material, at p: SIMD3<Float>, axis: SIMD3<Float> = [0, 1, 0]) -> ModelEntity {
        let c = ModelEntity(mesh: .generateCylinder(height: height, radius: radius), materials: [m])
        c.position = p
        if axis != [0, 1, 0] { c.orientation = simd_quatf(from: [0, 1, 0], to: axis) }
        e.addChild(c)
        return c
    }

    /// Vertical plane facing +Z (or a floor plane facing +Y when `horizontal`).
    @discardableResult
    private static func plane(_ e: Entity, _ s: SIMD2<Float>, _ m: RealityKit.Material, at p: SIMD3<Float>, horizontal: Bool = false) -> ModelEntity {
        let q = ModelEntity(mesh: horizontal ? .generatePlane(width: s.x, depth: s.y) : .generatePlane(width: s.x, height: s.y), materials: [m])
        q.position = p
        e.addChild(q)
        return q
    }

    private static func label(_ e: Entity, _ t: TextureResource?, size: SIMD2<Float>, at p: SIMD3<Float>) {
        var m = PhysicallyBasedMaterial()
        if let t { m.baseColor = .init(texture: .init(t)) }
        m.roughness = 0.5
        plane(e, size, m, at: p)
    }

    /// A pleated curtain: a sine-folded sheet `width` along +X, hanging from y = height down to 0.
    private static func curtain(width: Float, height: Float, pleats: Int, depth: Float, material: PhysicallyBasedMaterial) -> Entity {
        let n = pleats * 8
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for i in 0...n {
            let u = Float(i) / Float(n), a = u * Float(pleats) * 2 * .pi
            let z = sin(a) * depth / 2, dz = cos(a) * depth / 2 * Float(pleats) * 2 * .pi / width
            let normal = simd_normalize(SIMD3<Float>(-dz, 0, 1))
            for v: Float in [0, 1] {
                pos.append([u * width - width / 2, v * height, z]); nor.append(normal); uv.append([u, v])
            }
        }
        for i in 0..<UInt32(n) {
            let a = i * 2
            idx += [a, a + 2, a + 1, a + 1, a + 2, a + 3]
        }
        var d = MeshDescriptor(name: "curtain")
        d.positions = MeshBuffer(pos); d.normals = MeshBuffer(nor); d.textureCoordinates = MeshBuffer(uv)
        d.primitives = .triangles(idx)
        var m = material
        m.faceCulling = .none
        guard let mesh = try? MeshResource.generate(from: [d]) else { return Entity() }
        let c = ModelEntity(mesh: mesh, materials: [m])
        c.name = "curtain"
        return c
    }

    // MARK: Printed graphics (drawn once per build)

    private static func draw(_ px: CGSize, _ body: (CGContext, CGSize) -> Void) -> TextureResource? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let img = UIGraphicsImageRenderer(size: px, format: format).image { body($0.cgContext, px) }
        guard let cg = img.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .color))
    }

    private static func text(_ s: String, _ r: CGRect, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor = .black, align: NSTextAlignment = .left) {
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = .byWordWrapping
        (s as NSString).draw(in: r, withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p])
    }

    private static let navy = UIColor(red: 0.08, green: 0.2, blue: 0.38, alpha: 1)

    private static func scaphoidPoster() -> TextureResource? {
        draw(CGSize(width: 720, height: 1020)) { c, s in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: s))
            navy.setFill(); c.fill(CGRect(x: 0, y: 0, width: s.width, height: 300))
            text("FRACTURE CLINIC", CGRect(x: 50, y: 40, width: 620, height: 40), size: 28, weight: .semibold, color: UIColor(white: 1, alpha: 0.7))
            text("Wrist pain after a fall?", CGRect(x: 50, y: 85, width: 620, height: 200), size: 66, weight: .bold, color: .white)
            text("Snuffbox tenderness after a fall on the outstretched hand: treat as a scaphoid fracture until proven otherwise.",
                 CGRect(x: 50, y: 335, width: 620, height: 220), size: 34, weight: .semibold, color: navy)
            let steps = [("1", "Examine", "Snuffbox, scaphoid tubercle, thumb telescoping"),
                         ("2", "X-ray", "PA, lateral and scaphoid views"),
                         ("3", "Normal film?", "Splint and re-image: MRI or review in 10-14 days")]
            for (i, st) in steps.enumerated() {
                let y = 580 + CGFloat(i) * 135
                UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1).setFill()
                c.fillEllipse(in: CGRect(x: 50, y: y, width: 70, height: 70))
                text(st.0, CGRect(x: 50, y: y + 10, width: 70, height: 60), size: 40, weight: .bold, color: .white, align: .center)
                text(st.1, CGRect(x: 145, y: y - 2, width: 530, height: 44), size: 34, weight: .bold, color: navy)
                text(st.2, CGRect(x: 145, y: y + 42, width: 530, height: 80), size: 27, color: UIColor(white: 0.3, alpha: 1))
            }
        }
    }

    private static func painPoster() -> TextureResource? {
        draw(CGSize(width: 960, height: 672)) { c, s in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: s))
            text("How much does it hurt?", CGRect(x: 50, y: 40, width: 860, height: 80), size: 62, weight: .bold, color: navy)
            text("Point to a number: 0 is no pain, 10 is the worst pain you can imagine.", CGRect(x: 50, y: 125, width: 860, height: 90), size: 32, color: UIColor(white: 0.3, alpha: 1))
            let cell = (s.width - 100) / 11
            for i in 0...10 {
                let t = CGFloat(i) / 10
                UIColor(hue: 0.33 * (1 - t), saturation: 0.75, brightness: 0.9, alpha: 1).setFill()
                c.fill(CGRect(x: 50 + CGFloat(i) * cell, y: 260, width: cell - 6, height: 200))
                text("\(i)", CGRect(x: 50 + CGFloat(i) * cell, y: 320, width: cell - 6, height: 80), size: 58, weight: .bold, color: .white, align: .center)
            }
            for (x, w) in [(CGFloat(50), "None"), (CGFloat(50 + 4 * cell), "Moderate"), (CGFloat(50 + 9 * cell), "Worst")] {
                text(w, CGRect(x: x, y: 480, width: 300, height: 50), size: 32, weight: .semibold, color: navy)
            }
            text("Tell us if your pain changes", CGRect(x: 50, y: 570, width: 860, height: 50), size: 30, weight: .medium, color: UIColor(white: 0.45, alpha: 1))
        }
    }

    private static func hygienePoster() -> TextureResource? {
        draw(CGSize(width: 600, height: 860)) { c, s in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: s))
            let green = UIColor(red: 0.12, green: 0.55, blue: 0.4, alpha: 1)
            green.setFill(); c.fill(CGRect(x: 0, y: 0, width: s.width, height: 230))
            text("Clean hands", CGRect(x: 40, y: 40, width: 520, height: 80), size: 60, weight: .bold, color: .white)
            text("Your 5 moments for hand hygiene", CGRect(x: 40, y: 120, width: 520, height: 90), size: 32, weight: .medium, color: .white)
            let items = ["Before touching a patient", "Before a clean or aseptic procedure", "After body fluid exposure risk",
                         "After touching a patient", "After touching patient surroundings"]
            for (i, t) in items.enumerated() {
                let y = 265 + CGFloat(i) * 115
                green.setFill(); c.fillEllipse(in: CGRect(x: 40, y: y, width: 64, height: 64))
                text("\(i + 1)", CGRect(x: 40, y: y + 9, width: 64, height: 50), size: 36, weight: .bold, color: .white, align: .center)
                text(t, CGRect(x: 125, y: y, width: 440, height: 100), size: 32, weight: .medium, color: UIColor(white: 0.2, alpha: 1))
            }
        }
    }

    /// 1.2 m of suspended ceiling: 2 x 2 tiles and their T-bar grid.
    private static func ceilingGrid() -> TextureResource? {
        draw(CGSize(width: 512, height: 512)) { c, s in
            UIColor(white: 0.97, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: s))
            UIColor(white: 0.74, alpha: 1).setFill()
            for k in [CGFloat(0), 253, 507] { c.fill(CGRect(x: k, y: 0, width: 5, height: 512)); c.fill(CGRect(x: 0, y: k, width: 512, height: 5)) }
        }
    }

    private static func roomSign() -> TextureResource? {
        draw(CGSize(width: 720, height: 240)) { c, s in
            navy.setFill(); c.fill(CGRect(origin: .zero, size: s))
            text("Fracture Clinic", CGRect(x: 40, y: 40, width: 640, height: 90), size: 72, weight: .bold, color: .white)
            text("Consulting Room 3", CGRect(x: 40, y: 135, width: 640, height: 70), size: 46, weight: .medium, color: UIColor(white: 1, alpha: 0.75))
        }
    }

    private static func gloveBox(_ size: String) -> TextureResource? {
        draw(CGSize(width: 520, height: 240)) { c, s in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.3, green: 0.4, blue: 0.85, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: s.width, height: 60))
            text("NITRILE  EXAMINATION GLOVES", CGRect(x: 20, y: 14, width: 480, height: 40), size: 28, weight: .bold, color: .white)
            UIColor(white: 0.15, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 120, y: 95, width: 260, height: 90))
            UIColor(red: 0.55, green: 0.65, blue: 0.95, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 170, y: 115, width: 160, height: 50))
            text(size, CGRect(x: 410, y: 90, width: 100, height: 110), size: 90, weight: .heavy, color: UIColor(red: 0.3, green: 0.4, blue: 0.85, alpha: 1), align: .center)
        }
    }

    private static func sharpsLabel() -> TextureResource? {
        draw(CGSize(width: 300, height: 220)) { c, s in
            UIColor(red: 1, green: 0.82, blue: 0.1, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: s))
            UIColor.black.setStroke(); c.setLineWidth(6); c.stroke(CGRect(x: 10, y: 10, width: 280, height: 200))
            text("SHARPS", CGRect(x: 10, y: 30, width: 280, height: 70), size: 58, weight: .heavy, align: .center)
            text("Do not fill above the line", CGRect(x: 20, y: 110, width: 260, height: 90), size: 30, weight: .semibold, align: .center)
        }
    }

    private static func tag(_ s: String) -> TextureResource? {
        draw(CGSize(width: 300, height: 100)) { c, sz in
            UIColor.white.setFill(); c.fill(CGRect(origin: .zero, size: sz))
            text(s, CGRect(x: 0, y: 22, width: 300, height: 70), size: 46, weight: .semibold, color: UIColor(white: 0.3, alpha: 1), align: .center)
        }
    }

    /// The desk monitor: an imaging viewer with the patient's PA wrist film and a worklist.
    private static func monitorScreen() -> TextureResource? {
        let xray: UIImage? = Bundle.main.url(forResource: "wrist_xray_pa", withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
        return draw(CGSize(width: 1160, height: 680)) { c, s in
            UIColor(red: 0.08, green: 0.1, blue: 0.13, alpha: 1).setFill(); c.fill(CGRect(origin: .zero, size: s))
            UIColor(red: 0.13, green: 0.16, blue: 0.2, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: s.width, height: 56))
            text("Imaging  ·  Fracture Clinic", CGRect(x: 24, y: 12, width: 600, height: 40), size: 28, weight: .semibold, color: .white)
            text("R wrist PA", CGRect(x: 900, y: 12, width: 240, height: 40), size: 26, color: UIColor(white: 0.7, alpha: 1), align: .right)
            UIColor.black.setFill(); c.fill(CGRect(x: 24, y: 76, width: 620, height: 580))
            if let xray {
                let r = AVMakeRect(xray.size, in: CGRect(x: 24, y: 76, width: 620, height: 580)); xray.draw(in: r)
            }
            let rows = [("09:00", "Wrist, FOOSH", true), ("09:20", "Ankle sprain", false), ("09:40", "Clavicle review", false),
                        ("10:00", "Distal radius, cast check", false), ("10:20", "Scaphoid review", false), ("10:40", "Hand, boxer's #", false)]
            text("Today", CGRect(x: 670, y: 80, width: 460, height: 40), size: 28, weight: .bold, color: .white)
            for (i, r) in rows.enumerated() {
                let y = 130 + CGFloat(i) * 78
                (r.2 ? UIColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1) : UIColor(red: 0.14, green: 0.17, blue: 0.21, alpha: 1)).setFill()
                c.fill(CGRect(x: 670, y: y, width: 466, height: 66))
                text(r.0, CGRect(x: 686, y: y + 16, width: 100, height: 40), size: 26, weight: .semibold, color: .white)
                text(r.1, CGRect(x: 790, y: y + 16, width: 340, height: 40), size: 26, color: UIColor(white: 0.9, alpha: 1))
            }
        }
    }

    private static func AVMakeRect(_ size: CGSize, in r: CGRect) -> CGRect {
        let k = min(r.width / size.width, r.height / size.height)
        let w = size.width * k, hh = size.height * k
        return CGRect(x: r.midX - w / 2, y: r.midY - hh / 2, width: w, height: hh)
    }
}
