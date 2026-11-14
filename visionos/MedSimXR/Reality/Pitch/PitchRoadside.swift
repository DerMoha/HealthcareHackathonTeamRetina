import RealityKit
import UIKit

/// Pitch dressing: the roadside (road trauma rt-01..03). A photographic street (Poly Haven HDRI as
/// backdrop and light), the crashed car, the bicycle, the ambulance and police, a cordon, debris, a
/// crowd of bystanders and the crew (PitchCrowd, built by `people`). `forest`: the same case on a forest
/// trail (mountain-bike crash, hikers; EnvironmentSet.Kind.forest, `-pitchEnv forest` in the pitch shots).
/// Night keeps the procedural place.
@MainActor
enum PitchRoadside {
    static func build(into set: Entity, seat: Float, night: Bool, forest: Bool, avatarRoot: Entity) -> Bool {
        guard !night else { return false }
        let eye = avatarRoot.convert(position: [0, 1.6, 0], from: nil) // the simulator camera: world origin, eye height
        SmokeLog.mark("pitch roadside eye=\(eye) forest=\(forest)")
        backdrop(set, image: forest ? "roadside_forest_backdrop.jpg" : "roadside_backdrop.jpg", center: eye,
                 yaw: forest ? forestYaw : streetYaw)
        PitchKit.light(avatarRoot, hdri: forest ? "roadside_forest_ibl" : "roadside_ibl", intensity: 0.4,
                       yaw: forest ? forestYaw : streetYaw)
        responseBag(set, seat: seat)
        monitor(set, at: [0.4, 0, 0.34])
        if forest { trail(set) } else { street(set) }
        if SmokeLog.pitch { chip(set, forest ? "Hikers 3  ·  Distraction high" : "Crowd 4  ·  Distraction high") } // pitch caption, not part of the place
        return true
    }

    // MARK: - People

    /// The crew with the patient (journey member ids): Sam kneels at his right side, Lena bends in at his left.
    static let crew: [String: SIMD3<Float>] = ["sam": [-0.8, 0, -0.06], "lena": [0.82, 0, 0.08]]
    /// Crew who kneel here (their caption hangs lower).
    static let kneeling: Set<String> = ["sam"]

    /// An onlooker: where they stand and how they look (PitchCrowd.person arguments).
    private struct Onlooker {
        var gender: PitchCrowd.Gender, outfit: String, at: SIMD3<Float>, pose: PitchCrowd.BakedPose
        var hair: UIColor? = nil, skin: UIColor? = nil
    }

    /// Onlookers in the order they join as the crowd grows (Studio crowdedness 0 / 2 / 4). The last one
    /// of the default crowd stands where a Studio bystander goes (`speakerSpot`) and steps aside for them.
    private static func onlookers(forest: Bool) -> (all: [Onlooker], standard: Int) {
        let darkSkin = UIColor(red: 0.62, green: 0.48, blue: 0.4, alpha: 1)
        if forest {
            return ([Onlooker(gender: .m, outfit: "hiker_m", at: [1.6, 0, -2.0], pose: .standWorried, hair: UIColor(white: 0.25, alpha: 1)),
                     Onlooker(gender: .f, outfit: "hiker_f", at: [-0.6, 0, -3.1], pose: .phoneFilming,
                              hair: UIColor(red: 0.9, green: 0.75, blue: 0.5, alpha: 1)),
                     Onlooker(gender: .m, outfit: "driver", at: [2.1, 0, -1.6], pose: .armsCrossed, skin: darkSkin),
                     Onlooker(gender: .m, outfit: "bystander_m", at: [-2.2, 0, -2.3], pose: .standRelaxed,
                              hair: UIColor(red: 0.35, green: 0.22, blue: 0.14, alpha: 1))], 3)
        }
        return ([Onlooker(gender: .f, outfit: "bystander_f", at: [-0.55, 0, -3.3], pose: .standWorried,
                          hair: UIColor(red: 0.35, green: 0.22, blue: 0.14, alpha: 1)),
                 Onlooker(gender: .m, outfit: "bystander_m", at: [-2.25, 0, -1.55], pose: .phoneFilming,
                          hair: UIColor(red: 1.0, green: 0.85, blue: 0.6, alpha: 1)),
                 Onlooker(gender: .f, outfit: "bystander_f2", at: [2.0, 0, -1.3], pose: .armsCrossed,
                          hair: UIColor(white: 0.2, alpha: 1), skin: darkSkin),
                 Onlooker(gender: .m, outfit: "driver", at: [0.5, 0, -2.7], pose: .pointing,
                          hair: UIColor(white: 0.25, alpha: 1), skin: UIColor(red: 0.8, green: 0.68, blue: 0.58, alpha: 1)),
                 Onlooker(gender: .m, outfit: "hiker_m", at: [-1.7, 0, -4.4], pose: .standWorried, hair: UIColor(white: 0.3, alpha: 1))], 4)
    }

    /// Where a Studio bystander stands: the spot of the default crowd's last onlooker (the driver in the street).
    static func speakerSpot(forest: Bool) -> SIMD3<Float> {
        let o = onlookers(forest: forest)
        return o.all[o.standard - 1].at
    }

    /// The crew (`cast.crew`, nil = both) and the onlookers (`cast.onlookers`, nil = the default crowd);
    /// the street also has a police officer at the cordon.
    static func people(_ e: Entity, cast: PitchDressing.Cast, forest: Bool) {
        if cast.crew?.contains("sam") ?? true {
            PitchCrowd.person(.kneelWork, .m, outfit: "paramedic_m", in: e, at: crew["sam"]!, facing: [0, 0, 0.1],
                              hair: UIColor(white: 0.45, alpha: 1))
        }
        if cast.crew?.contains("lena") ?? true {
            PitchCrowd.person(.standLeanWork, .f, outfit: "paramedic_f", in: e, at: crew["lena"]!, facing: [0, 0, 0.1])
        }
        let (all, standard) = onlookers(forest: forest)
        var pool = all
        if cast.speaker { pool.remove(at: standard - 1) }
        for o in pool.prefix(max(0, cast.onlookers ?? standard)) {
            PitchCrowd.person(o.pose, o.gender, outfit: o.outfit, in: e, at: o.at, facing: [0, 0, 0], hair: o.hair, skin: o.skin)
        }
        if !forest {
            PitchCrowd.person(.standRelaxed, .m, outfit: "police", in: e, at: [-1.2, 0, -5.9], facing: [0, 0, 0],
                              hair: UIColor(white: 0.3, alpha: 1))
        }
    }

    static let streetYaw: Float = -0.4
    static let forestYaw: Float = 0

    // MARK: - Places

    private static func street(_ set: Entity) {
        // The car that hit him, stopped askew, hazards on, windscreen cracked.
        let crashed = car(set, at: [2.3, 0, -3.5], yaw: -0.65, paint: UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1), plate: "KD19 RFX")
        damage(crashed)
        bicycle(set, at: [-1.05, 0, -1.85], yaw: 0.5, frame: UIColor(red: 0.05, green: 0.45, blue: 0.55, alpha: 1))
        helmet(set, at: [-0.35, 0, -1.25], yaw: 1.1)
        debris(set, around: [1.3, 0, -2.4])
        bottle(set, at: [0.55, 0, -1.6])
        // Ambulance with its back doors towards us, a police car further up the road.
        ambulance(set, at: [-3.3, 0, -7.4], yaw: .pi + 0.25)
        let police = car(set, at: [3.9, 0, -9.5], yaw: 2.1, paint: UIColor(white: 0.93, alpha: 1), plate: "PL24 KTR")
        policeLivery(police)
        for p: SIMD3<Float> in [[-2.4, 0, -3.6], [-1.3, 0, -4.4], [0.1, 0, -4.9], [1.3, 0, -5.6], [3.2, 0, -2.0], [3.5, 0, -0.4]] {
            cone(set, at: p)
        }
        tape(set, [[-2.6, 0, -4.8], [-0.4, 0, -5.6], [1.8, 0, -6.2], [3.4, 0, -5.4]])
    }

    private static func trail(_ set: Entity) {
        bicycle(set, at: [-1.05, 0, -1.85], yaw: 0.5, frame: UIColor(red: 0.85, green: 0.35, blue: 0.08, alpha: 1), mtb: true)
        helmet(set, at: [-0.35, 0, -1.25], yaw: 1.1)
        bottle(set, at: [0.55, 0, -1.6])
    }

    // MARK: - Backdrop

    /// The HDRI's photo on an inside-out sphere centred on the camera: a backplate that lines up with
    /// the light. Equirect: u = 0.5 straight ahead (-Z), u grows to the right.
    private static func backdrop(_ set: Entity, image: String, center: SIMD3<Float>, yaw: Float) {
        guard let tex = PitchKit.texture(image) else { return }
        let rows = 48, cols = 96, radius: Float = 45
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for i in 0...rows {
            let theta = Float.pi * Float(i) / Float(rows)
            for j in 0...cols {
                let u = Float(j) / Float(cols)
                let phi = 2 * Float.pi * u + yaw
                pos.append([-sin(phi) * sin(theta) * radius, cos(theta) * radius, cos(phi) * sin(theta) * radius])
                uv.append([u, 1 - Float(i) / Float(rows)])
            }
        }
        for i in 0..<rows { for j in 0..<cols {
            let a = UInt32(i * (cols + 1) + j), c = a + UInt32(cols + 1)
            idx += [a, a + 1, c, a + 1, c + 1, c]
        } }
        var d = MeshDescriptor(name: "pitch_backdrop")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        guard let mesh = try? MeshResource.generate(from: [d]) else { return }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: .init(tex))
        m.faceCulling = .none
        let sky = ModelEntity(mesh: mesh, materials: [m])
        sky.position = center
        set.addChild(sky)
    }

    // MARK: - Vehicles

    private static func paint(_ c: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.metallic = 0.45; m.roughness = 0.32
        m.clearcoat = .init(floatLiteral: 1); m.clearcoatRoughness = .init(floatLiteral: 0.08)
        return m
    }

    private static func pbr(_ c: UIColor, rough: Float = 0.8, metal: Float = 0, opacity: Float = 1) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough); m.metallic = .init(floatLiteral: metal)
        if opacity < 1 { m.blending = .transparent(opacity: .init(floatLiteral: opacity)) }
        return m
    }

    private static let glass = pbr(UIColor(red: 0.16, green: 0.19, blue: 0.22, alpha: 1), rough: 0.08, metal: 0.9)
    private static let rubber = pbr(UIColor(white: 0.05, alpha: 1), rough: 0.9)
    private static let trim = pbr(UIColor(white: 0.12, alpha: 1), rough: 0.6)
    private static let chrome = pbr(UIColor(white: 0.75, alpha: 1), rough: 0.25, metal: 1)

    @discardableResult
    private static func box(_ p: Entity, _ size: SIMD3<Float>, _ m: RealityKit.Material, at: SIMD3<Float>, corner: Float = 0,
                            rot: simd_quatf? = nil) -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: corner), materials: [m])
        e.position = at
        if let rot { e.orientation = rot }
        p.addChild(e)
        return e
    }

    private static func glow(_ c: UIColor) -> UnlitMaterial { UnlitMaterial(color: c) }

    private static func wheel(_ p: Entity, at: SIMD3<Float>, radius: Float, width: Float) {
        let tyre = ModelEntity(mesh: .generateCylinder(height: width, radius: radius), materials: [rubber])
        tyre.position = at
        tyre.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        p.addChild(tyre)
        let rim = ModelEntity(mesh: .generateCylinder(height: width + 0.01, radius: radius * 0.62), materials: [chrome])
        rim.position = at
        rim.orientation = tyre.orientation
        p.addChild(rim)
    }

    /// A generic hatchback, front towards local +Z.
    @discardableResult
    private static func car(_ set: Entity, at: SIMD3<Float>, yaw: Float, paint c: UIColor, plate: String) -> Entity {
        let e = Entity()
        let body = paint(c)
        box(e, [1.78, 0.58, 4.15], body, at: [0, 0.56, 0], corner: 0.16)
        box(e, [1.7, 0.16, 1.1], body, at: [0, 0.84, 1.45], corner: 0.07)                       // bonnet
        box(e, [1.58, 0.52, 2.75], glass, at: [0, 1.08, -0.62], corner: 0.2)                     // glasshouse
        box(e, [1.52, 0.06, 2.25], body, at: [0, 1.34, -0.72], corner: 0.03)                      // roof
        for x: Float in [-0.79, 0.79] { box(e, [0.04, 0.5, 0.08], body, at: [x, 1.08, 0.66], rot: .init(angle: -0.45, axis: [1, 0, 0])) } // A-pillars
        for z: Float in [-2.06, 2.06] { box(e, [1.82, 0.2, 0.16], trim, at: [0, 0.4, z], corner: 0.06) } // bumpers
        for (x, z) in [(Float(-0.8), Float(1.3)), (0.8, 1.3), (-0.8, -1.3), (0.8, -1.3)] { wheel(e, at: [x, 0.31, z], radius: 0.31, width: 0.22) }
        for x: Float in [-0.6, 0.6] {
            box(e, [0.36, 0.1, 0.03], glow(UIColor(white: 0.95, alpha: 1)), at: [x, 0.72, 2.08], corner: 0.01)    // headlights
            box(e, [0.3, 0.12, 0.03], glow(UIColor(red: 0.75, green: 0.02, blue: 0.02, alpha: 1)), at: [x, 0.78, -2.08], corner: 0.01)
        }
        for (x, z) in [(Float(-0.84), Float(2.05)), (0.84, 2.05), (-0.84, -2.05), (0.84, -2.05)] {
            box(e, [0.12, 0.07, 0.05], glow(UIColor(red: 1, green: 0.55, blue: 0.05, alpha: 1)), at: [x, 0.72, z]) // hazards on
        }
        for x: Float in [-0.9, 0.9] { box(e, [0.05, 0.11, 0.18], body, at: [x, 0.95, 0.55]) }    // mirrors
        for z: Float in [2.09, -2.09] {
            let plateTex = RoadsidePaint.texture("plate_\(plate)_\(z > 0)", size: [520, 112]) { ctx, s in
                ctx.setFillColor((z > 0 ? UIColor.white : UIColor(red: 1, green: 0.82, blue: 0.1, alpha: 1)).cgColor)
                ctx.fill(CGRect(origin: .zero, size: s))
                RoadsidePaint.text(ctx, plate, in: CGRect(origin: .zero, size: s), size: 82, weight: .heavy, color: .black)
            }
            let pl = ModelEntity(mesh: .generatePlane(width: 0.52, height: 0.11), materials: [RoadsidePaint.lit(plateTex)])
            pl.position = [0, 0.44, z + (z > 0 ? 0.08 : -0.08)]
            if z < 0 { pl.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0]) }
            e.addChild(pl)
        }
        PitchKit.contactShadow(e, at: .zero, size: [1.6, 3.9], opacity: 0.75)
        e.position = at
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        set.addChild(e)
        return e
    }

    /// Cracked windscreen, dented bonnet edge, the bumper hanging off.
    private static func damage(_ car: Entity) {
        let crack = RoadsidePaint.mask("windscreen_crack", size: [512, 256]) { ctx, s in
            ctx.setStrokeColor(UIColor.white.cgColor)
            let c = CGPoint(x: s.width * 0.3, y: s.height * 0.45)
            var rng = SystemRandomNumberGenerator()
            for i in 0..<22 {
                let a = CGFloat(i) / 22 * 2 * .pi + CGFloat.random(in: -0.1...0.1, using: &rng)
                ctx.setLineWidth(CGFloat.random(in: 1.5...3.5, using: &rng))
                var p = c
                ctx.move(to: p)
                for _ in 0..<5 {
                    p = CGPoint(x: p.x + cos(a) * 34 + .random(in: -10...10, using: &rng), y: p.y + sin(a) * 34 + .random(in: -10...10, using: &rng))
                    ctx.addLine(to: p)
                }
                ctx.strokePath()
            }
            for r in [18.0, 40.0, 70.0] as [CGFloat] {
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r * 0.8, width: r * 2, height: r * 1.6))
            }
            ctx.setFillColor(UIColor(white: 1, alpha: 0.6).cgColor)
            ctx.fillEllipse(in: CGRect(x: c.x - 14, y: c.y - 12, width: 28, height: 24))
        }
        var m = UnlitMaterial(color: UIColor(white: 0.92, alpha: 1))
        m.blending = .transparent(opacity: .init(scale: 0.9, texture: crack.map { .init($0) }))
        m.faceCulling = .none
        let screen = ModelEntity(mesh: .generatePlane(width: 1.4, height: 0.62), materials: [m])
        screen.position = [0, 1.08, 0.74]
        screen.orientation = simd_quatf(angle: -0.45, axis: [1, 0, 0])
        car.addChild(screen)
        box(car, [0.8, 0.16, 0.12], trim, at: [-0.45, 0.24, 2.1], corner: 0.05, rot: .init(angle: 0.35, axis: [0, 0, 1])) // bumper hanging
    }

    private static func policeLivery(_ car: Entity) {
        let check = RoadsidePaint.texture("police_check", size: [512, 64]) { ctx, s in
            for i in 0..<16 { for r in 0..<2 {
                let yellow = (i + r) % 2 == 0
                ctx.setFillColor((yellow ? UIColor(red: 0.95, green: 0.85, blue: 0.05, alpha: 1) : UIColor(red: 0.05, green: 0.2, blue: 0.65, alpha: 1)).cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * 32, y: CGFloat(r) * 32, width: 32, height: 32))
            } }
        }
        for x: Float in [-0.895, 0.895] {
            let band = ModelEntity(mesh: .generatePlane(width: 4.0, height: 0.22), materials: [RoadsidePaint.lit(check)])
            band.position = [x, 0.62, 0]
            band.orientation = simd_quatf(angle: x > 0 ? .pi / 2 : -.pi / 2, axis: [0, 1, 0])
            car.addChild(band)
        }
        box(car, [1.2, 0.1, 0.28], trim, at: [0, 1.42, -0.3], corner: 0.03)
        for x: Float in [-0.4, 0.4] { box(car, [0.36, 0.09, 0.26], glow(UIColor(red: 0.1, green: 0.35, blue: 1, alpha: 1)), at: [x, 1.49, -0.3], corner: 0.02) }
    }

    /// A generic box ambulance (no livery): white, high-visibility check band, blue lights; front +Z.
    private static func ambulance(_ set: Entity, at: SIMD3<Float>, yaw: Float) {
        let e = Entity()
        let white = paint(UIColor(white: 0.95, alpha: 1))
        box(e, [2.15, 2.15, 3.9], white, at: [0, 1.48, -0.65], corner: 0.1)       // box body
        box(e, [2.0, 1.1, 1.95], white, at: [0, 0.95, 2.25], corner: 0.16)        // cab
        box(e, [1.9, 0.72, 1.2], glass, at: [0, 1.8, 1.95], corner: 0.14)         // cab windows
        box(e, [1.92, 0.08, 1.3], white, at: [0, 2.18, 1.9], corner: 0.03)
        for z: Float in [-2.62, 3.2] { box(e, [2.1, 0.24, 0.14], trim, at: [0, 0.48, z], corner: 0.05) }
        for (x, z) in [(Float(-0.98), Float(-1.6)), (0.98, -1.6), (-0.98, 2.35), (0.98, 2.35)] { wheel(e, at: [x, 0.38, z], radius: 0.38, width: 0.26) }
        let check = RoadsidePaint.texture("amb_check", size: [512, 64]) { ctx, s in
            for i in 0..<16 { for r in 0..<2 {
                let yellow = (i + r) % 2 == 0
                ctx.setFillColor((yellow ? UIColor(red: 0.95, green: 0.88, blue: 0.05, alpha: 1) : UIColor(red: 0.1, green: 0.55, blue: 0.2, alpha: 1)).cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * 32, y: CGFloat(r) * 32, width: 32, height: 32))
            } }
        }
        for x: Float in [-1.08, 1.08] {
            let band = ModelEntity(mesh: .generatePlane(width: 5.6, height: 0.4), materials: [RoadsidePaint.lit(check)])
            band.position = [x, 1.0, 0.25]
            band.orientation = simd_quatf(angle: x > 0 ? .pi / 2 : -.pi / 2, axis: [0, 1, 0])
            e.addChild(band)
        }
        // Rear doors: chevrons, a seam, AMBULANCE across the top.
        let rear = RoadsidePaint.texture("amb_rear", size: [512, 512]) { ctx, s in
            ctx.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 300, width: s.width, height: 212))
            for i in -6..<12 {
                ctx.setFillColor((i % 2 == 0 ? UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1) : UIColor(red: 0.98, green: 0.85, blue: 0.05, alpha: 1)).cgColor)
                let x = CGFloat(i) * 60
                ctx.move(to: CGPoint(x: x, y: 512)); ctx.addLine(to: CGPoint(x: x + 256, y: 300)); ctx.addLine(to: CGPoint(x: x + 316, y: 300))
                ctx.addLine(to: CGPoint(x: x + 60, y: 512)); ctx.fillPath()
            }
            ctx.restoreGState()
            ctx.setFillColor(UIColor(white: 0.55, alpha: 1).cgColor); ctx.fill(CGRect(x: 254, y: 0, width: 4, height: 512))
            RoadsidePaint.text(ctx, "AMBULANCE", in: CGRect(x: 0, y: 40, width: s.width, height: 90), size: 72, weight: .black,
                            color: UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1))
            for x in [200.0, 300.0] as [CGFloat] { ctx.setFillColor(UIColor(white: 0.3, alpha: 1).cgColor); ctx.fill(CGRect(x: x, y: 230, width: 14, height: 40)) }
        }
        let back = ModelEntity(mesh: .generatePlane(width: 2.0, height: 2.0), materials: [RoadsidePaint.lit(rear)])
        back.position = [0, 1.48, -2.61]
        back.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        e.addChild(back)
        let blue = glow(UIColor(red: 0.1, green: 0.4, blue: 1, alpha: 1))
        for (x, z) in [(Float(-0.95), Float(-2.5)), (0.95, -2.5), (-0.95, 1.2), (0.95, 1.2)] { box(e, [0.22, 0.13, 0.16], blue, at: [x, 2.6, z], corner: 0.03) }
        box(e, [1.4, 0.1, 0.25], trim, at: [0, 2.26, 2.3], corner: 0.03)
        for x: Float in [-0.45, 0.45] { box(e, [0.42, 0.09, 0.22], blue, at: [x, 2.33, 2.3], corner: 0.02) }
        for x: Float in [-0.75, 0.75] { box(e, [0.18, 0.12, 0.03], glow(UIColor(red: 0.8, green: 0.03, blue: 0.03, alpha: 1)), at: [x, 0.75, -2.63]) }
        PitchKit.contactShadow(e, at: [0, 0, 0.25], size: [2.0, 5.8], opacity: 0.75)
        e.position = at
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        set.addChild(e)
    }

    // MARK: - Props

    private static func tube(_ p: Entity, _ a: SIMD3<Float>, _ b: SIMD3<Float>, radius: Float, _ m: RealityKit.Material) {
        let d = b - a, len = simd_length(d)
        guard len > 0.001 else { return }
        let e = ModelEntity(mesh: .generateCylinder(height: len, radius: radius), materials: [m])
        e.position = (a + b) / 2
        e.orientation = simd_quatf(from: [0, 1, 0], to: d / len)
        p.addChild(e)
    }

    /// The bicycle on its side, the front wheel buckled. Built side-on (x forward, y up), then laid down.
    private static func bicycle(_ set: Entity, at: SIMD3<Float>, yaw: Float, frame color: UIColor, mtb: Bool = false) {
        let bike = Entity()
        let frame = paint(color)
        let r: Float = mtb ? 0.36 : 0.34
        let rear = SIMD3<Float>(0, r, 0), front = SIMD3<Float>(1.06, r, 0)
        let bb = SIMD3<Float>(0.42, 0.29, 0), seatTop = SIMD3<Float>(0.3, 0.82, 0)
        let headTop = SIMD3<Float>(0.93, 0.84, 0), headBottom = SIMD3<Float>(0.97, 0.7, 0)
        let t: Float = mtb ? 0.022 : 0.016
        for (a, b) in [(bb, seatTop), (bb, headBottom), (seatTop, headTop), (headTop, headBottom)] { tube(bike, a, b, radius: t, frame) }
        for z: Float in [-0.05, 0.05] {
            tube(bike, bb + [0, 0, z], rear + [0, 0, z], radius: 0.01, frame)
            tube(bike, seatTop + [0, 0, z * 0.5], rear + [0, 0, z], radius: 0.01, frame)
            tube(bike, headBottom + [0, 0, z * 0.5], front + [0.02, 0, z], radius: 0.012, mtb ? trim : chrome)
        }
        tube(bike, headTop, headTop + [-0.04, 0.08, 0], radius: 0.014, trim)
        tube(bike, headTop + [-0.04, 0.08, -0.3], headTop + [-0.04, 0.08, 0.3], radius: 0.012, mtb ? trim : chrome) // bars
        box(bike, [0.26, 0.05, 0.12], trim, at: seatTop + [-0.02, 0.07, 0], corner: 0.02)      // saddle
        tube(bike, seatTop, seatTop + [-0.02, 0.06, 0], radius: 0.012, chrome)
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.1), materials: [chrome]) // chainring
        ring.position = bb + [0, 0, 0.06]; ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        bike.addChild(ring)
        tube(bike, bb + [0, 0, 0.07], bb + [0.1, -0.12, 0.07], radius: 0.01, chrome)          // crank, pedal
        box(bike, [0.1, 0.02, 0.08], trim, at: bb + [0.1, -0.12, 0.1])
        for (c, buckled) in [(rear, false), (front, true)] {
            let w = Entity()
            let tyre = ModelEntity(mesh: torus(r, mtb ? 0.028 : 0.017), materials: [rubber])
            let rim = ModelEntity(mesh: torus(r - (mtb ? 0.03 : 0.02), 0.009), materials: [chrome])
            w.addChild(tyre); w.addChild(rim)
            for i in 0..<16 {
                let a = Float(i) / 16 * 2 * .pi
                tube(w, [0, 0, 0], [cos(a) * (r - 0.03), 0, sin(a) * (r - 0.03)], radius: 0.0018, chrome)
            }
            if buckled { w.scale = [1, 1, 0.82]; w.orientation = simd_quatf(angle: 0.15, axis: [1, 0, 0]) } // taco'd front wheel
            let axle = Entity()
            axle.addChild(w)
            axle.position = c
            axle.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) // wheel plane = the bike's side
            bike.addChild(axle)
        }
        let holder = Entity()
        holder.addChild(bike)
        bike.orientation = simd_quatf(angle: -1.38, axis: [1, 0, 0]) // lying on its side, resting on bar and pedal
        let b = bike.visualBounds(relativeTo: holder)
        bike.position -= [b.center.x, b.min.y, b.center.z]
        PitchKit.contactShadow(holder, at: .zero, size: [b.extents.x * 0.9, b.extents.z * 0.8], opacity: 0.5)
        holder.position = at
        holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        set.addChild(holder)
    }

    private static func helmet(_ set: Entity, at: SIMD3<Float>, yaw: Float) {
        let shell = paint(UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
        var profile: [SIMD2<Float>] = []
        for i in 0...10 { let a = Float(i) / 10 * .pi / 2; profile.append([cos(a) * 0.13, sin(a) * 0.12]) }
        let h = ModelEntity(mesh: lathe(profile), materials: [shell])
        h.scale = [1, 1, 1.3]
        let stripe = ModelEntity(mesh: .generateBox(size: [0.03, 0.125, 0.32], cornerRadius: 0.01), materials: [pbr(UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1), rough: 0.4)])
        stripe.position = [0, 0.02, 0]
        let e = Entity(); e.addChild(h); e.addChild(stripe)
        e.position = at + [0, 0.005, 0]
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: 0.5, axis: [0, 0, 1]) // tipped over
        PitchKit.contactShadow(set, at: at, size: [0.28, 0.34], opacity: 0.45)
        set.addChild(e)
    }

    private static func bottle(_ set: Entity, at: SIMD3<Float>) {
        let b = ModelEntity(mesh: .generateCylinder(height: 0.22, radius: 0.036), materials: [pbr(UIColor(red: 0.1, green: 0.5, blue: 0.85, alpha: 1), rough: 0.35)])
        b.position = at + [0, 0.036, 0]
        b.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) * simd_quatf(angle: 0.6, axis: [1, 0, 0])
        set.addChild(b)
    }

    private static func debris(_ set: Entity, around c: SIMD3<Float>) {
        var rng = RoadsideRandom(seed: 11)
        let shard = pbr(UIColor(red: 0.85, green: 0.92, blue: 0.95, alpha: 1), rough: 0.05, metal: 0.2, opacity: 0.75)
        for _ in 0..<40 {
            let p = c + [Float.random(in: -0.7...0.6, using: &rng), 0.004, Float.random(in: -0.5...0.5, using: &rng)]
            box(set, [Float.random(in: 0.015...0.05, using: &rng), 0.004, Float.random(in: 0.012...0.04, using: &rng)], shard, at: p,
                rot: .init(angle: Float.random(in: 0...6, using: &rng), axis: [0, 1, 0]))
        }
        let plastic = [trim, pbr(UIColor(red: 1, green: 0.5, blue: 0.05, alpha: 1), rough: 0.3, opacity: 0.85), pbr(UIColor(red: 0.42, green: 0.45, blue: 0.5, alpha: 1), rough: 0.35)]
        for i in 0..<9 {
            let p = c + [Float.random(in: -0.9...0.5, using: &rng), 0.01, Float.random(in: -0.6...0.6, using: &rng)]
            box(set, [Float.random(in: 0.06...0.18, using: &rng), 0.015, Float.random(in: 0.04...0.1, using: &rng)], plastic[i % 3], at: p,
                rot: .init(angle: Float.random(in: 0...6, using: &rng), axis: [0, 1, 0]))
        }
    }

    private static func cone(_ set: Entity, at: SIMD3<Float>) {
        let tex = RoadsidePaint.texture("cone_bands", size: [16, 256]) { ctx, s in
            ctx.setFillColor(UIColor(red: 1, green: 0.38, blue: 0.05, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            ctx.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
            ctx.fill(CGRect(x: 0, y: 70, width: 16, height: 34)); ctx.fill(CGRect(x: 0, y: 130, width: 16, height: 28))
        }
        var m = RoadsidePaint.lit(tex)
        m.roughness = 0.45
        let body = ModelEntity(mesh: lathe([[0.14, 0.03], [0.1, 0.25], [0.03, 0.7], [0.018, 0.72], [0, 0.72]]), materials: [m])
        let e = Entity(); e.addChild(body)
        box(e, [0.38, 0.03, 0.38], pbr(UIColor(white: 0.08, alpha: 1), rough: 0.9), at: [0, 0.015, 0], corner: 0.01)
        PitchKit.contactShadow(e, at: .zero, size: [0.36, 0.36], opacity: 0.55)
        e.position = at
        set.addChild(e)
    }

    /// POLICE LINE tape between posts at waist height.
    private static func tape(_ set: Entity, _ posts: [SIMD3<Float>]) {
        let tex = RoadsidePaint.texture("tape", size: [512, 48]) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.98, green: 0.85, blue: 0.05, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            RoadsidePaint.text(ctx, "POLICE LINE  DO NOT CROSS", in: CGRect(origin: .zero, size: s), size: 30, weight: .black, color: .black)
        }
        let post = pbr(UIColor(white: 0.1, alpha: 1), rough: 0.5)
        for p in posts {
            tube(set, p, p + [0, 1.0, 0], radius: 0.025, post)
            box(set, [0.3, 0.04, 0.3], post, at: p + [0, 0.02, 0], corner: 0.01)
        }
        for (a, b) in zip(posts, posts.dropFirst()) {
            let d = b - a, len = simd_length(d)
            var m = RoadsidePaint.lit(tex)
            m.faceCulling = .none
            m.textureCoordinateTransform = .init(scale: [len / 1.6, 1])
            let strip = ModelEntity(mesh: .generatePlane(width: len, height: 0.07), materials: [m])
            strip.position = (a + b) / 2 + [0, 0.92, 0]
            strip.orientation = simd_quatf(angle: atan2(-d.z, d.x), axis: [0, 1, 0])
            set.addChild(strip)
        }
    }

    /// The paramedic response bag the patient sits on, an open kit bag beside it.
    private static func responseBag(_ set: Entity, seat: Float) {
        let fabric = pbr(UIColor(red: 0.12, green: 0.36, blue: 0.2, alpha: 1), rough: 0.92)
        let h = max(seat - 0.02, 0.2)
        box(set, [0.62, h, 0.42], fabric, at: [0, h / 2, -0.1], corner: 0.06)
        let reflect = pbr(UIColor(white: 0.82, alpha: 1), rough: 0.3, metal: 0.4)
        for y in [h * 0.3, h * 0.72] { box(set, [0.625, 0.035, 0.425], reflect, at: [0, y, -0.1], corner: 0.01) }
        box(set, [0.12, 0.08, 0.02], pbr(.white, rough: 0.5), at: [0, h * 0.5, 0.115])          // label patch
        PitchKit.contactShadow(set, at: [0, 0, -0.1], size: [0.62, 0.45], opacity: 0.65)
        // Open red kit bag on the ground to the patient's left: dressings and gloves.
        let kit = Entity()
        let red = pbr(UIColor(red: 0.72, green: 0.08, blue: 0.08, alpha: 1), rough: 0.9)
        box(kit, [0.5, 0.24, 0.32], red, at: [0, 0.12, 0], corner: 0.04)
        for (i, x) in [Float(-0.15), -0.03, 0.09].enumerated() {
            box(kit, [0.1, 0.03, 0.14], pbr(i == 1 ? UIColor(red: 0.3, green: 0.55, blue: 0.95, alpha: 1) : .white, rough: 0.7), at: [x, 0.25, 0.02])
        }
        PitchKit.contactShadow(kit, at: .zero, size: [0.5, 0.32], opacity: 0.6)
        kit.position = [-0.45, 0, 0.42]
        kit.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0])
        set.addChild(kit)
    }

    /// The crew's monitor on the ground, screen tilted up: the first set of observations.
    private static func monitor(_ set: Entity, at: SIMD3<Float>) {
        let e = Entity()
        box(e, [0.34, 0.27, 0.17], pbr(UIColor(white: 0.18, alpha: 1), rough: 0.6), at: [0, 0.135, 0], corner: 0.03)
        box(e, [0.36, 0.05, 0.19], pbr(UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1), rough: 0.5), at: [0, 0.025, 0], corner: 0.02)
        let screen = RoadsidePaint.texture("monitor_obs", size: [480, 300]) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            func trace(_ y: CGFloat, _ c: UIColor, _ f: (CGFloat) -> CGFloat) {
                ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(3)
                ctx.move(to: CGPoint(x: 10, y: y))
                for x in stride(from: CGFloat(10), through: 300, by: 2) { ctx.addLine(to: CGPoint(x: x, y: y - f(x))) }
                ctx.strokePath()
            }
            trace(70, .green) { x in let p = x.truncatingRemainder(dividingBy: 54); return p > 20 && p < 26 ? (p < 23 ? 45 : -15) : 0 }
            trace(160, .cyan) { x in 14 * sin(x / 9) }
            trace(240, .yellow) { x in 10 * sin(x / 14) }
            func value(_ t: String, _ y: CGFloat, _ c: UIColor, _ size: CGFloat = 54) {
                RoadsidePaint.text(ctx, t, in: CGRect(x: 300, y: y, width: 175, height: size + 8), size: size, weight: .bold, color: c, align: .right)
            }
            value("112", 22, .green); value("97", 112, .cyan); value("124/78", 200, .white, 40)
        }
        let sc = ModelEntity(mesh: .generatePlane(width: 0.28, height: 0.175), materials: [RoadsidePaint.unlit(screen)])
        sc.position = [0, 0.16, 0.088]
        e.addChild(sc)
        PitchKit.contactShadow(e, at: .zero, size: [0.34, 0.2], opacity: 0.6)
        e.position = at
        e.orientation = simd_quatf(angle: 0.55, axis: [0, 1, 0]) * simd_quatf(angle: -0.35, axis: [1, 0, 0])
        set.addChild(e)
    }

    /// "Crowd 4 · Distraction high" next to the stage banner (ScenarioStage's sign at y 2.3, z -0.6;
    /// on the trail that sign itself says "On the trail").
    private static func chip(_ set: Entity, _ text: String) {
        let size = CGSize(width: 900, height: 110)
        let color = RoadsidePaint.texture("chip_\(text)", size: [900, 110]) { ctx, s in
            ctx.setFillColor(UIColor(red: 0.13, green: 0.12, blue: 0.16, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            ctx.setFillColor(UIColor(red: 0.98, green: 0.45, blue: 0.7, alpha: 1).cgColor)
            for i in 0..<3 { ctx.fillEllipse(in: CGRect(x: 52 + CGFloat(i) * 26, y: 40 + CGFloat(i % 2) * 6, width: 22, height: 22)) }
            RoadsidePaint.text(ctx, text, in: CGRect(x: 150, y: 0, width: s.width - 180, height: s.height), size: 54, weight: .semibold, color: .white, align: .left)
        }
        let mask = RoadsidePaint.mask("chip_mask", size: [900, 110]) { ctx, s in
            ctx.setFillColor(UIColor(white: 1, alpha: 1).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: s).insetBy(dx: 2, dy: 2), cornerRadius: 53).cgPath); ctx.fillPath()
        }
        var m = UnlitMaterial()
        m.color = .init(tint: .white, texture: color.map { .init($0) })
        m.blending = .transparent(opacity: .init(scale: 0.88, texture: mask.map { .init($0) }))
        let w: Float = 0.6
        let e = ModelEntity(mesh: .generatePlane(width: w, height: w * Float(size.height / size.width)), materials: [m])
        e.position = [0, 2.42, -0.6]
        set.addChild(e)
    }

    // MARK: - Meshes

    /// Revolves `profile` (r, y) about +Y.
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 40) -> MeshResource {
        let n = profile.count
        var pos: [SIMD3<Float>] = [], nor: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        let top = profile.map(\.y).max() ?? 1, bottom = profile.map(\.y).min() ?? 0
        for i in 0..<n {
            let t = profile[min(i + 1, n - 1)] - profile[max(i - 1, 0)]
            let n2 = simd_normalize(SIMD2<Float>(t.y, -t.x))
            for j in 0...segments {
                let a = Float(j) / Float(segments) * 2 * .pi
                pos.append([profile[i].x * cos(a), profile[i].y, profile[i].x * sin(a)])
                nor.append([n2.x * cos(a), n2.y, n2.x * sin(a)])
                uv.append([Float(j) / Float(segments), (profile[i].y - bottom) / max(top - bottom, 0.0001)])
            }
        }
        for i in 0..<(n - 1) { for j in 0..<segments {
            let a = UInt32(i * (segments + 1) + j), c = a + UInt32(segments + 1)
            idx += [a, c, a + 1, a + 1, c, c + 1]
        } }
        var d = MeshDescriptor(name: "lathe")
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return (try? MeshResource.generate(from: [d])) ?? .generateSphere(radius: 0.01)
    }

    /// Ring of radius `big`, tube radius `small`, in the XZ plane.
    static func torus(_ big: Float, _ small: Float) -> MeshResource {
        lathe((0...16).map { i in let a = Float(i) / 16 * 2 * .pi; return [big + small * cos(a), small * sin(a)] }, segments: 48)
    }
}

/// Deterministic randomness, so the debris lands in the same place in every shot.
struct RoadsideRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}

/// Small CoreGraphics canvases for signs, plates, tape and screens (cached by name).
@MainActor
enum RoadsidePaint {
    private static var cache: [String: TextureResource] = [:]

    static func texture(_ name: String, size: SIMD2<Int>, semantic: TextureResource.Semantic = .color,
                        _ draw: (CGContext, CGSize) -> Void) -> TextureResource? {
        let key = "\(name)#\(semantic)"
        if let t = cache[key] { return t }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1; fmt.opaque = false
        let s = CGSize(width: size.x, height: size.y)
        let img = UIGraphicsImageRenderer(size: s, format: fmt).image { draw($0.cgContext, s) }
        guard let cg = img.cgImage, let t = try? TextureResource(image: cg, options: .init(semantic: semantic)) else { return nil }
        cache[key] = t
        return t
    }

    /// White-on-black opacity mask.
    static func mask(_ name: String, size: SIMD2<Int>, _ draw: (CGContext, CGSize) -> Void) -> TextureResource? {
        texture(name, size: size, semantic: .raw) { ctx, s in
            ctx.setFillColor(UIColor.black.cgColor); ctx.fill(CGRect(origin: .zero, size: s))
            draw(ctx, s)
        }
    }

    static func lit(_ tex: TextureResource?) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let tex { m.baseColor = .init(tint: .white, texture: .init(tex)) }
        m.roughness = 0.6
        return m
    }

    static func unlit(_ tex: TextureResource?) -> UnlitMaterial {
        var m = UnlitMaterial()
        if let tex { m.color = .init(tint: .white, texture: .init(tex)) }
        return m
    }

    nonisolated static func text(_ ctx: CGContext, _ t: String, in r: CGRect, size: CGFloat, weight: UIFont.Weight, color: UIColor,
                     align: NSTextAlignment = .center) {
        let p = NSMutableParagraphStyle(); p.alignment = align
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: p]
        let h = (t as NSString).size(withAttributes: attrs).height
        UIGraphicsPushContext(ctx)
        (t as NSString).draw(in: CGRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h), withAttributes: attrs)
        UIGraphicsPopContext()
    }
}
