import RealityKit
import UIKit

/// Pitch dressing: the antenatal scan room (ultrasound case). A small, warm, slightly dimmed room:
/// laminate floor, plaster walls, wall monitor facing the parent, partner armchair, plant, soft lamps.
/// The scan couch comes from the avatar (restyled by `dressCouch`), the machine from UltrasoundScene.
@MainActor
enum PitchAntenatal {
    static let w: Float = 2.6, back: Float = -2.5, front: Float = 3.2, h: Float = 2.7
    static let warm = UIColor(red: 1, green: 0.9, blue: 0.78, alpha: 1)
    /// The parent-facing wall screen; mirrors the probe view (see `mirror`).
    private static weak var wallScreen: ModelEntity?

    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        let depth = front - back, mid = (front + back) / 2
        let floor = ModelEntity(mesh: .generatePlane(width: 2 * w, depth: depth),
                                materials: [PitchKit.material("antenatal_floor", tiling: [2 * w / 1.2, depth / 1.2], tint: UIColor(white: 0.9, alpha: 1))])
        floor.position = [0, 0, mid]
        set.addChild(floor)
        // Walls: textured planes facing into the room (tiled per metre so the plaster keeps its scale).
        let plaster = UIColor(red: 0.9, green: 0.87, blue: 0.82, alpha: 1)
        let accent = UIColor(red: 0.7, green: 0.78, blue: 0.78, alpha: 1) // calm sage accent wall (reads neutral under the warm lamps)
        wall(set, size: [2 * w, h], at: [0, h / 2, back], yaw: 0, tint: accent)
        wall(set, size: [2 * w, h], at: [0, h / 2, front], yaw: .pi, tint: plaster)
        wall(set, size: [depth, h], at: [-w, h / 2, mid], yaw: .pi / 2, tint: plaster)
        wall(set, size: [depth, h], at: [w, h / 2, mid], yaw: -.pi / 2, tint: plaster)
        let ceiling = ModelEntity(mesh: .generatePlane(width: 2 * w, depth: depth),
                                  materials: [Self.plaster(UIColor(red: 0.95, green: 0.91, blue: 0.85, alpha: 1), tiling: SIMD2<Float>(2 * w, depth) / 1.5)])
        ceiling.position = [0, h, mid]
        ceiling.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        set.addChild(ceiling)
        // Skirting boards.
        let skirt = solid(UIColor(white: 0.96, alpha: 1), 0.4)
        box(set, [2 * w, 0.09, 0.015], skirt, at: [0, 0.045, back + 0.008])
        for x in [-w + 0.008, w - 0.008] { box(set, [0.015, 0.09, depth], skirt, at: [x, 0.045, mid]) }
        // Left wall: a deeper sage dado below a timber rail, so the long wall is not one flat plane.
        let dado = Self.plaster(UIColor(red: 0.62, green: 0.7, blue: 0.68, alpha: 1), tiling: SIMD2<Float>(depth, 1) / 1.5)
        let lower = ModelEntity(mesh: .generatePlane(width: depth, height: 1.0), materials: [dado])
        lower.position = [-w + 0.004, 0.5, mid]
        lower.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        set.addChild(lower)
        box(set, [0.025, 0.045, depth], solid(UIColor(red: 0.55, green: 0.42, blue: 0.3, alpha: 1), 0.5), at: [-w + 0.012, 1.0, mid])

        // Recessed downlights (dimmed) and two warm wall sconces either side of the couch head.
        for (x, z) in [(Float(-1.2), Float(-1.4)), (1.2, -1.4), (-1.2, 1.0), (1.2, 1.0), (0, -0.2)] {
            let disc = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.07), materials: [UnlitMaterial(color: warm)])
            disc.position = [x, h - 0.004, z]
            set.addChild(disc)
        }
        for x: Float in [-0.95, 0.95] {
            box(set, [0.16, 0.3, 0.07], solid(UIColor(red: 0.62, green: 0.48, blue: 0.36, alpha: 1), 0.5), at: [x, 1.75, back + 0.04])
            box(set, [0.13, 0.26, 0.02], glowPicture("antenatal_shade", [64, 128]) { drawShade($0, $1) }, at: [x, 1.75, back + 0.085])
            // Warm wash of light on the wall around the sconce (soft radial falloff).
            let wash = ModelEntity(mesh: .generatePlane(width: 0.9, height: 1.2), materials: [washMaterial])
            wash.position = [x, 1.78, back + 0.006]
            set.addChild(wash)
            point(set, at: [x, 1.8, back + 0.3], intensity: 1200, color: warm, radius: 3)
        }
        // Framed prints on the accent wall above the couch head.
        for (i, x) in [Float(-0.32), 0.32].enumerated() {
            box(set, [0.5, 0.64, 0.03], solid(UIColor(red: 0.45, green: 0.33, blue: 0.24, alpha: 1), 0.5), at: [x, 1.85, back + 0.015])
            let art = ModelEntity(mesh: .generatePlane(width: 0.42, height: 0.56),
                                  materials: [picture(i == 0 ? "antenatal_art_a" : "antenatal_art_b", [420, 560]) { drawArt($0, $1, seed: i) }])
            art.position = [x, 1.85, back + 0.032]
            set.addChild(art)
        }

        // Clinical wall kit left of the prints: triple glove dispenser (S/M/L) and a hand-rub pump.
        box(set, [0.44, 0.27, 0.1], solid(UIColor(white: 0.92, alpha: 1), 0.4), at: [-1.0, 1.3, back + 0.05])
        for (i, x) in [Float(-1.14), -1.0, -0.86].enumerated() {
            let c = [UIColor(red: 0.45, green: 0.6, blue: 0.85, alpha: 1), UIColor(red: 0.62, green: 0.48, blue: 0.82, alpha: 1), UIColor(red: 0.4, green: 0.72, blue: 0.7, alpha: 1)][i]
            box(set, [0.125, 0.24, 0.02], solid(c, 0.6), at: [x, 1.3, back + 0.105])
            box(set, [0.07, 0.03, 0.005], solid(UIColor(white: 0.97, alpha: 1), 0.7), at: [x, 1.23, back + 0.117])
        }
        box(set, [0.11, 0.22, 0.1], solid(UIColor(white: 0.96, alpha: 1), 0.35), at: [-1.36, 1.2, back + 0.05])
        box(set, [0.06, 0.03, 0.04], solid(UIColor(red: 0.3, green: 0.6, blue: 0.72, alpha: 1), 0.4), at: [-1.36, 1.08, back + 0.08])

        // Parent's screen on a wall arm in the far right corner, turned towards the couch and partner chair.
        let tv = Entity()
        tv.position = [1.75, 1.62, back + 0.22]
        tv.orientation = simd_quatf(angle: -0.4, axis: [0, 1, 0])
        set.addChild(tv)
        box(tv, [1.12, 0.65, 0.035], gloss(UIColor(white: 0.05, alpha: 1)), at: [0, 0, 0])
        box(set, [0.08, 0.08, 0.2], solid(UIColor(white: 0.25, alpha: 1), 0.4), at: [1.75, 1.62, back + 0.1])
        let screen = ModelEntity(mesh: .generatePlane(width: 1.08, height: 0.61), materials: [standby])
        screen.position = [0, 0, 0.019]
        tv.addChild(screen)
        wallScreen = screen

        // Partner's armchair beside the couch, side table with a plant, tall plant in the far corner.
        if let chair = PitchKit.place("antenatal_armchair", in: set, at: [1.3, 0, -1.15], yaw: -1.05, fit: 0.88) {
            // The scan's near-black cushions read as holes in the dim room: re-cover them in oatmeal fabric.
            var fabric = solid(UIColor(red: 0.78, green: 0.7, blue: 0.58, alpha: 1), 0.95)
            if let n = PitchKit.texture("antenatal_vinyl_nor.jpg", semantic: .raw) { fabric.normal = .init(texture: .init(n)) }
            func recover(_ e: Entity) {
                if let m = e as? ModelEntity, var mats = m.model?.materials, mats.count > 1 { mats[1] = fabric; m.model?.materials = mats }
                e.children.forEach(recover)
            }
            recover(chair)
        }
        PitchKit.place("antenatal_sidetable", in: set, at: [2.1, 0, -1.55], yaw: -0.3, fit: 0.5)
        PitchKit.place("antenatal_plant", in: set, at: [-2.0, 0, -2.0], yaw: 0.4, fit: 1.3)
        // Cabinet with a tissue box and folded towels along the left wall, behind the machine.
        box(set, [0.5, 0.86, 1.3], solid(UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1), 0.45), at: [-w + 0.26, 0.43, -1.2])
        box(set, [0.52, 0.03, 1.32], solid(UIColor(red: 0.55, green: 0.42, blue: 0.3, alpha: 1), 0.5), at: [-w + 0.26, 0.875, -1.2])
        box(set, [0.3, 0.08, 0.36], solid(UIColor(red: 0.62, green: 0.78, blue: 0.84, alpha: 1), 0.9), at: [-w + 0.3, 0.93, -0.8])
        box(set, [0.3, 0.07, 0.36], solid(UIColor(white: 0.97, alpha: 1), 0.9), at: [-w + 0.3, 1.005, -0.8])
        box(set, [0.22, 0.1, 0.12], solid(.white, 0.6), at: [-w + 0.3, 0.94, -1.5])
        PitchKit.contactShadow(set, at: [-w + 0.26, 0, -1.2], size: [0.5, 1.3], opacity: 0.4)
        PitchKit.contactShadow(set, at: [0, 0, 0.42], size: [0.6, 1.0], opacity: 0.6) // under the couch pedestal

        PitchKit.light(avatarRoot, hdri: "antenatal_ibl", intensity: -0.3, yaw: 0)
        PitchKit.showShadows(on: floor)
        // Warm key light over the couch: casts the couch and patient shadows on the floor.
        PitchKit.spot(set, at: [0.5, h - 0.05, 0.9], target: [0, 0, -0.1], intensity: 26000, color: warm, angle: 75)
        point(set, at: [0, 2.2, 1.6], intensity: 5000, color: warm, radius: 5)
        point(set, at: [0, h - 0.5, -0.6], intensity: 2600, color: warm, radius: 2.4) // warm bounce on the ceiling
        return true
    }

    private struct Sidecar: Decodable { var couch: PatientAvatar.Couch? }
    /// The couch geometry from the pregnant model's sidecar (the avatar does not keep it).
    private static let couch: PatientAvatar.Couch? = Bundle.main.url(forResource: "Patient_pregnant", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder.medsim.decode(Sidecar.self, from: $0).couch }

    // MARK: Couch (called by UltrasoundScene once the avatar has loaded)

    /// Restyles the avatar's procedural couch as a scan couch (vinyl upholstery, white frame), lays the
    /// paper sheet over it and hangs the paper roll and a pillow at the head end. Extras go into `extras`.
    static func dressCouch(_ avatarRoot: Entity, extras: Entity) {
        var vinyl = solid(UIColor(red: 0.74, green: 0.82, blue: 0.86, alpha: 1), 0.5) // wipe-clean couch vinyl
        if let n = PitchKit.texture("antenatal_vinyl_nor.jpg", semantic: .raw) { vinyl.normal = .init(texture: .init(n)) }
        let frame = gloss(UIColor(white: 0.95, alpha: 1))
        for part in avatarRoot.children where part.name == "couch" {
            guard let m = part as? ModelEntity, let bounds = m.model?.mesh.bounds else { continue }
            // Upholstery slabs are the wide, thick ones; the rest is frame.
            let e = bounds.extents
            m.model?.materials = [e.x > 0.6 && e.y > 0.08 ? vinyl : e.x < 0.12 && e.y > 0.2 ? chrome : frame]
        }
        Array(extras.children).forEach { $0.removeFromParent() }
        guard let c = couch else { return }
        let theta = c.backRestAngleDeg * .pi / 180
        let pivot = SIMD3<Float>(c.backRestPivot[0], c.backRestPivot[1], c.backRestPivot[2])
        let along = SIMD3<Float>(0, sin(theta), -cos(theta)), normal = SIMD3<Float>(0, cos(theta), sin(theta))
        let tilt = simd_quatf(angle: theta, axis: [1, 0, 0])
        var paper = solid(UIColor(white: 0.97, alpha: 1), 0.85) // couch roll paper: white, with a crinkle normal map
        if let n = PitchKit.texture("antenatal_paper_nor.jpg", semantic: .raw) { paper.normal = .init(texture: .init(n)) }
        let sheet = c.width - 0.12
        box(extras, [sheet, 0.003, c.seatLength - 0.02], paper, at: [0, c.seatHeight + 0.002, pivot.z + c.seatLength / 2 - 0.01])
        box(extras, [sheet, 0.003, c.backRestLength], paper, at: pivot + along * (c.backRestLength / 2) + normal * 0.002, rotation: tilt)
        // Roll on two brackets at the head end, just below the back-rest top.
        let top = pivot + along * (c.backRestLength + 0.02) - normal * 0.03
        let roll = ModelEntity(mesh: .generateCylinder(height: sheet + 0.02, radius: 0.055), materials: [paper])
        roll.position = top
        roll.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        extras.addChild(roll)
        for x in [-(sheet / 2 + 0.03), sheet / 2 + 0.03] { box(extras, [0.02, 0.1, 0.05], frame, at: top + [x, 0, 0], rotation: tilt) }
        // Pillow under the head, in a pale cotton case.
        let pillow = ModelEntity(mesh: .generateBox(size: [0.46, 0.07, 0.3], cornerRadius: 0.035),
                                 materials: [solid(UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1), 0.95)])
        pillow.position = pivot + along * (c.backRestLength - 0.32) + normal * 0.04
        pillow.orientation = tilt
        extras.addChild(pillow)
        // Side rail along the patient's left, chrome.
        let rail = ModelEntity(mesh: .generateCylinder(height: 0.7, radius: 0.012), materials: [chrome])
        rail.position = [c.width / 2 + 0.02, c.seatHeight - 0.03, pivot.z + 0.5]
        rail.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        extras.addChild(rail)
    }

    // MARK: Machine extras (called by UltrasoundScene.buildCart, cart space: deck at y 0.855, front +Z)

    static func dressCart(_ cart: Entity) {
        let dark = gloss(UIColor(white: 0.08, alpha: 1), roughness: 0.3)
        let ball = ModelEntity(mesh: .generateSphere(radius: 0.021), materials: [gloss(UIColor(red: 0.2, green: 0.24, blue: 0.3, alpha: 1), roughness: 0.15)])
        ball.position = [0.19, 0.884, 0.24]
        cart.addChild(ball)
        // Touch panel between the keyboard and the monitor, tilted towards the operator.
        let touch = Entity()
        touch.position = [-0.03, 0.95, 0.16]
        touch.orientation = simd_quatf(angle: -1.0, axis: [1, 0, 0])
        cart.addChild(touch)
        box(touch, [0.3, 0.19, 0.016], dark, at: [0, 0, 0])
        let panel = ModelEntity(mesh: .generatePlane(width: 0.28, height: 0.17), materials: [glowPicture("antenatal_touch", [560, 340]) { drawTouch($0, $1) }])
        panel.position = [0, 0, 0.0085]
        touch.addChild(panel)
        box(cart, [0.04, 0.14, 0.04], dark, at: [-0.03, 0.9, 0.1])
        // Front handle, side handles, two more probes parked on the far side.
        for x: Float in [-0.2, 0.2] { box(cart, [0.02, 0.02, 0.06], chrome, at: [x, 0.86, 0.52]) }
        let bar = ModelEntity(mesh: .generateCylinder(height: 0.44, radius: 0.012), materials: [chrome])
        bar.position = [0, 0.86, 0.55]
        bar.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        cart.addChild(bar)
        for z: Float in [-0.05, 0.08] {
            box(cart, [0.07, 0.06, 0.08], solid(UIColor(red: 0.5, green: 0.52, blue: 0.56, alpha: 1), 0.4), at: [-0.29, 0.8, z])
            box(cart, [0.04, 0.1, 0.022], dark, at: [-0.29, 0.86, z])
        }
        // Monitor back housing and a slim arm.
        box(cart, [0.5, 0.36, 0.08], dark, at: [0, 1.32, -0.26])
        // Accent strip along the body's front edge.
        box(cart, [0.5, 0.025, 0.01], solid(UIColor(red: 0.25, green: 0.62, blue: 0.68, alpha: 1), 0.4), at: [0, 0.8, 0.262])
    }

    /// The parent's wall screen shows what the probe sees. shortcut: region -> image map copied from the
    /// pitch run's first pass over each region; read the engine's current image if this ever ships.
    static func mirror(region: String?) {
        let files = ["abdomen_lower": "us_head_bpd.jpg", "abdomen_upper": "us_heart_4ch.jpg", "abdomen_center": "us_overview.jpg"]
        guard let wallScreen else { return }
        guard let region, let file = files[region], let tex = PitchKit.texture(file) else {
            wallScreen.model?.materials = [standby]; wallScreen.scale = [1, 1, 1]; return
        }
        var m = UnlitMaterial()
        m.color = .init(tint: UIColor(white: 0.92, alpha: 1), texture: .init(tex))
        wallScreen.model?.materials = [m]
        // Images vary in aspect: fit inside the 16:9 screen, keep its height.
        let aspect = Float(tex.width) / Float(max(tex.height, 1))
        wallScreen.scale = [min(1, 0.61 * aspect / 1.08), 1, 1]
    }

    // MARK: Helpers

    static var chrome: PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.85, alpha: 1)); m.metallic = .init(floatLiteral: 1); m.roughness = .init(floatLiteral: 0.18)
        return m
    }

    static func solid(_ c: UIColor, _ roughness: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c); m.roughness = .init(floatLiteral: roughness)
        return m
    }

    /// Glossy moulded plastic (machine body, monitor housing): a clear coat over a satin base.
    static func gloss(_ c: UIColor, roughness: Float = 0.35) -> PhysicallyBasedMaterial {
        var m = solid(c, roughness)
        m.clearcoat = .init(floatLiteral: 0.8); m.clearcoatRoughness = .init(floatLiteral: 0.08)
        return m
    }

    /// Matt painted plaster: flat paint colour, the plaster scan only for its relief (normal map).
    private static func plaster(_ c: UIColor, tiling: SIMD2<Float>) -> PhysicallyBasedMaterial {
        var m = solid(c, 0.9)
        if let n = PitchKit.texture("antenatal_wall_nor.jpg", semantic: .raw) { m.normal = .init(texture: .init(n)) }
        m.textureCoordinateTransform = .init(scale: tiling)
        return m
    }

    private static func wall(_ parent: Entity, size: SIMD2<Float>, at p: SIMD3<Float>, yaw: Float, tint: UIColor) {
        let e = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y),
                            materials: [plaster(tint, tiling: size / 1.5)])
        e.position = p
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        parent.addChild(e)
    }

    private static func box(_ parent: Entity, _ size: SIMD3<Float>, _ material: RealityKit.Material, at p: SIMD3<Float>,
                            rotation: simd_quatf = .init(angle: 0, axis: [0, 1, 0])) {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(size.min() / 2, 0.01)), materials: [material])
        e.position = p
        e.orientation = rotation
        parent.addChild(e)
    }

    private static func point(_ parent: Entity, at p: SIMD3<Float>, intensity: Float, color: UIColor, radius: Float) {
        let l = Entity()
        l.components.set(PointLightComponent(color: color, intensity: intensity, attenuationRadius: radius))
        l.position = p
        parent.addChild(l)
    }

    private static var pictures: [String: TextureResource] = [:]

    private static func picture(_ name: String, _ px: SIMD2<Int>, _ draw: (CGContext, CGSize) -> Void) -> RealityKit.Material {
        if pictures[name] == nil {
            let size = CGSize(width: px.x, height: px.y)
            let img = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
                .image { draw($0.cgContext, size) }
            pictures[name] = img.cgImage.flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
        }
        var m = PhysicallyBasedMaterial()
        m.roughness = .init(floatLiteral: 0.7)
        if let t = pictures[name] { m.baseColor = .init(texture: .init(t)) }
        return m
    }

    private static func glowPicture(_ name: String, _ px: SIMD2<Int>, _ draw: (CGContext, CGSize) -> Void) -> RealityKit.Material {
        _ = picture(name, px, draw)
        var m = UnlitMaterial()
        if let t = pictures[name] { m.color = .init(tint: UIColor(white: 0.85, alpha: 1), texture: .init(t)) }
        return m
    }

    /// Wall screen between scans: the clinic's standby card.
    private static var standby: RealityKit.Material { glowPicture("antenatal_standby", [1080, 610]) { drawStandby($0, $1) } }

    private static var washMaterial: UnlitMaterial {
        _ = picture("antenatal_wash", [256, 256]) { ctx, size in
            let colors = [UIColor(red: 1, green: 0.85, blue: 0.62, alpha: 0.55).cgColor, UIColor(red: 1, green: 0.85, blue: 0.62, alpha: 0).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let c = CGPoint(x: size.width / 2, y: size.height * 0.45)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.width / 2, options: [])
        }
        var m = UnlitMaterial()
        if let t = pictures["antenatal_wash"] { m.color = .init(tint: .white, texture: .init(t)) }
        m.blending = .transparent(opacity: .init(floatLiteral: 1))
        return m
    }

    /// Frosted sconce shade: brightest in the middle.
    private static func drawShade(_ ctx: CGContext, _ size: CGSize) {
        let colors = [UIColor(red: 1, green: 0.95, blue: 0.82, alpha: 1).cgColor, UIColor(red: 0.95, green: 0.72, blue: 0.48, alpha: 1).cgColor] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: size.height * 0.6, options: [.drawsAfterEndLocation])
    }

    private static func drawStandby(_ ctx: CGContext, _ size: CGSize) {
        let colors = [UIColor(red: 0.07, green: 0.2, blue: 0.24, alpha: 1).cgColor, UIColor(red: 0.03, green: 0.07, blue: 0.1, alpha: 1).cgColor] as CFArray
        ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!,
                               start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        let teal = UIColor(red: 0.42, green: 0.82, blue: 0.84, alpha: 1)
        // Mark: a stylised mother-and-child curve in a ring.
        teal.setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 70, y: 110, width: 140, height: 140)); ring.lineWidth = 8; ring.stroke()
        let bump = UIBezierPath()
        bump.move(to: CGPoint(x: size.width / 2 - 20, y: 140))
        bump.addCurve(to: CGPoint(x: size.width / 2 - 10, y: 225), controlPoint1: CGPoint(x: size.width / 2 + 60, y: 150), controlPoint2: CGPoint(x: size.width / 2 + 50, y: 230))
        bump.lineWidth = 9; bump.lineCapStyle = .round; bump.stroke()
        teal.setFill()
        UIBezierPath(ovalIn: CGRect(x: size.width / 2 - 32, y: 122, width: 26, height: 26)).fill()
        func line(_ text: String, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
            let t = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            t.draw(at: CGPoint(x: (size.width - t.size().width) / 2, y: y))
        }
        line("Antenatal Ultrasound", 290, .systemFont(ofSize: 64, weight: .semibold), .white)
        line("Scan Room 2  ·  Your images will appear here", 380, .systemFont(ofSize: 34, weight: .regular), UIColor(white: 1, alpha: 0.7))
        line("Partners welcome  ·  Please ask before taking photos", 470, .systemFont(ofSize: 28, weight: .regular), teal)
    }

    /// The machine's touch panel: preset and mode buttons in the scanner's dark UI.
    private static func drawTouch(_ ctx: CGContext, _ size: CGSize) {
        UIColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        let labels = ["B-Mode", "Color", "PW", "M-Mode", "Freeze", "Measure", "OB 2nd", "Report"]
        let font = UIFont.systemFont(ofSize: 26, weight: .semibold)
        for (i, label) in labels.enumerated() {
            let col = CGFloat(i % 4), row = CGFloat(i / 4)
            let r = CGRect(x: 16 + col * 134, y: 40 + row * 140, width: 122, height: 110)
            let on = i == 0 || i == 6
            (on ? UIColor(red: 0.18, green: 0.62, blue: 0.68, alpha: 1) : UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1)).setFill()
            UIBezierPath(roundedRect: r, cornerRadius: 14).fill()
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: UIColor.white])
            let ts = text.size()
            text.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2))
        }
    }

    /// Soft abstract prints (overlapping washes of colour on paper), in the room's warm palette.
    private static func drawArt(_ ctx: CGContext, _ size: CGSize, seed: Int) {
        UIColor(red: 0.97, green: 0.95, blue: 0.9, alpha: 1).setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        let palettes: [[UIColor]] = [
            [UIColor(red: 0.85, green: 0.6, blue: 0.5, alpha: 0.55), UIColor(red: 0.95, green: 0.8, blue: 0.55, alpha: 0.6), UIColor(red: 0.55, green: 0.66, blue: 0.6, alpha: 0.5)],
            [UIColor(red: 0.55, green: 0.66, blue: 0.6, alpha: 0.55), UIColor(red: 0.88, green: 0.7, blue: 0.62, alpha: 0.55), UIColor(red: 0.96, green: 0.86, blue: 0.66, alpha: 0.6)],
        ]
        let shapes: [[CGRect]] = [
            [CGRect(x: 0.15, y: 0.18, width: 0.6, height: 0.45), CGRect(x: 0.3, y: 0.42, width: 0.55, height: 0.42), CGRect(x: 0.12, y: 0.55, width: 0.4, height: 0.3)],
            [CGRect(x: 0.2, y: 0.12, width: 0.5, height: 0.5), CGRect(x: 0.1, y: 0.45, width: 0.62, height: 0.4), CGRect(x: 0.45, y: 0.5, width: 0.42, height: 0.36)],
        ]
        for (c, r) in zip(palettes[seed % 2], shapes[seed % 2]) {
            c.setFill()
            ctx.fillEllipse(in: CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height))
        }
    }
}
