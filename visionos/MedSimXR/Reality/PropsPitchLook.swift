import ImageIO
import RealityKit
import UIKit

/// Pitch-only look of the orthotics equipment (launch argument `-pitch`): a stainless dressing
/// trolley with a blue sterile drape, textured neoprene braces lying on it with printed size
/// cards, a body measuring tape and a box of gloves, lit by a hospital HDRI with contact shadows.
/// Textures come from Resources/Pitch/props_* (CC0, see assets/pitch/CREDITS-props.md) and are
/// never loaded outside pitch mode.
@MainActor
enum PropsLook {
    // MARK: Materials and light

    private static var textures: [String: TextureResource] = [:]

    private static func image(_ file: String, _ ext: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: file, withExtension: ext),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func texture(_ file: String, _ semantic: TextureResource.Semantic) -> TextureResource? {
        if let t = textures[file] { return t }
        guard let cg = image(file, "jpg"), let t = try? TextureResource(image: cg, options: .init(semantic: semantic)) else { return nil }
        textures[file] = t
        return t
    }

    /// Physically based material from a props_<set>_{albedo,normal,rough} texture set, tinted.
    static func pbr(_ set: String, tint: UIColor, tile: SIMD2<Float> = [1, 1], roughness: Float = 1, metallic: Float = 0,
                    clearcoat: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = texture("props_\(set)_albedo", .color).map { .init(tint: tint, texture: .init($0)) } ?? .init(tint: tint)
        if let n = texture("props_\(set)_normal", .normal) { m.normal = .init(texture: .init(n)) }
        m.roughness = texture("props_\(set)_rough", .raw).map { .init(scale: roughness, texture: .init($0)) } ?? .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        if clearcoat > 0 { m.clearcoat = .init(floatLiteral: clearcoat); m.clearcoatRoughness = .init(floatLiteral: 0.15) }
        m.textureCoordinateTransform.scale = tile
        m.faceCulling = .none
        return m
    }

    static func plain(_ color: UIColor, roughness: Float = 0.6, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        return m
    }

    static var steel: PhysicallyBasedMaterial { pbr("steel", tint: UIColor(white: 0.92, alpha: 1), tile: [2, 2], roughness: 0.55, metallic: 1) }

    /// Image-based light from the hospital-room HDRI; lives in the tray so it is in the scene.
    static let light: Entity = {
        let e = Entity()
        e.name = "props_ibl"
        if let cg = image("props_hospital_room_1k", "exr"),
           let env = try? EnvironmentResource(equirectangular: cg, withName: "props_ibl") {
            e.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.6))
        }
        return e
    }()

    /// Every model under `root` takes the HDRI light and casts a soft contact shadow.
    static func dress(_ root: Entity, shadows: Bool = true) {
        if root is ModelEntity {
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: light))
            if shadows { root.components.set(GroundingShadowComponent(castsShadow: true)) }
        }
        root.children.forEach { dress($0, shadows: shadows) }
    }

    @discardableResult
    private static func model(_ parent: Entity, _ mesh: MeshResource, _ material: any Material, at p: SIMD3<Float> = .zero,
                              rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> ModelEntity {
        let m = ModelEntity(mesh: mesh, materials: [material])
        m.position = p
        m.orientation = rotation
        parent.addChild(m)
        return m
    }

    private static func print(_ string: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> Entity {
        let mesh = MeshResource.generateText(string, extrusionDepth: 0.0003, font: .systemFont(ofSize: size, weight: weight))
        let e = ModelEntity(mesh: mesh, materials: [plain(color, roughness: 0.5)])
        e.position = [-mesh.bounds.extents.x / 2 - mesh.bounds.min.x, -mesh.bounds.extents.y / 2 - mesh.bounds.min.y, 0]
        let holder = Entity()
        holder.addChild(e)
        return holder
    }

    // MARK: Trolley

    /// Two-tier stainless dressing trolley under the tray: rimmed top at the tray's surface
    /// (y = 0.006 in tray space), legs to the floor `height` below, a lower shelf, castors,
    /// the blue drape, and a few consumables.
    static func trolley(width: Float, depth: Float, height: Float) -> Entity {
        let e = Entity()
        e.name = "props_trolley"
        let steel = Self.steel
        let top: Float = 0.006
        model(e, .generateBox(size: [width, 0.01, depth], cornerRadius: 0.004), steel, at: [0, top - 0.005, 0])
        // tray rim
        for (size, p) in [([width, 0.022, 0.006], [0, top + 0.011, depth / 2 - 0.003]), ([width, 0.022, 0.006], [0, top + 0.011, -depth / 2 + 0.003]),
                          ([0.006, 0.022, depth], [width / 2 - 0.003, top + 0.011, 0]), ([0.006, 0.022, depth], [-width / 2 + 0.003, top + 0.011, 0])] as [(SIMD3<Float>, SIMD3<Float>)] {
            model(e, .generateBox(size: size, cornerRadius: 0.0025), steel, at: p)
        }
        // legs, lower shelf, castors
        let legX = width / 2 - 0.03, legZ = depth / 2 - 0.03, legTop = top - 0.01, castor: Float = 0.075
        let legLength = height + legTop - castor
        for x in [-legX, legX] {
            for z in [-legZ, legZ] {
                model(e, .generateCylinder(height: legLength, radius: 0.0125), steel, at: [x, legTop - legLength / 2, z])
                model(e, .generateBox(size: [0.03, 0.012, 0.04], cornerRadius: 0.003), steel, at: [x, -height + castor - 0.006, z])
                model(e, .generateCylinder(height: 0.022, radius: 0.03), plain(UIColor(white: 0.12, alpha: 1), roughness: 0.75),
                      at: [x, -height + 0.03, z + 0.012], rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
                model(e, .generateCylinder(height: 0.024, radius: 0.011), steel, at: [x, -height + 0.03, z + 0.012],
                      rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
            }
        }
        let shelfY = -height + 0.26
        model(e, .generateBox(size: [width - 0.02, 0.008, depth - 0.02], cornerRadius: 0.003), steel, at: [0, shelfY, 0])
        for z in [-depth / 2 + 0.015, depth / 2 - 0.015] {
            model(e, .generateBox(size: [width - 0.02, 0.018, 0.005], cornerRadius: 0.002), steel, at: [0, shelfY + 0.012, z])
        }
        // push handle at the wearer's end
        model(e, .generateCylinder(height: depth - 0.04, radius: 0.011), steel, at: [-width / 2 - 0.05, top + 0.09, 0],
              rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        for z in [-depth / 2 + 0.03, depth / 2 - 0.03] {
            model(e, .generateBox(size: [0.06, 0.012, 0.012], cornerRadius: 0.004), steel, at: [-width / 2 - 0.025, top + 0.02, z])
            model(e, .generateCylinder(height: 0.08, radius: 0.0085), steel, at: [-width / 2 - 0.05, top + 0.05, z])
        }

        // blue sterile drape, slightly off-square with a turned-back corner
        let drape = pbr("drape", tint: UIColor(red: 0.42, green: 0.66, blue: 0.86, alpha: 1), tile: [1.6, 1], roughness: 0.95)
        model(e, .generateBox(size: [width - 0.05, 0.0012, depth - 0.05]), drape, at: [0.004, top + 0.0008, 0.002],
              rotation: simd_quatf(angle: 0.012, axis: [0, 1, 0]))
        model(e, .generateBox(size: [0.09, 0.0012, 0.09]), drape, at: [width / 2 - 0.07, top + 0.0024, -depth / 2 + 0.07],
              rotation: simd_quatf(angle: .pi / 4, axis: [0, 1, 0]))

        // consumables: gloves at the back of the top, towels and a glove box below
        e.addChild(gloveBox(at: [width / 2 - 0.15, top + 0.0012, -depth / 2 + 0.085], yaw: -0.08))
        e.addChild(stockinette(at: [-width / 2 + 0.12, top + 0.03, -depth / 2 + 0.07]))
        e.addChild(gloveBox(at: [-0.1, shelfY + 0.004, 0.02], yaw: 0.15))
        let towel = pbr("drape", tint: UIColor(white: 0.93, alpha: 1), tile: [1, 1], roughness: 1)
        for i in 0..<3 {
            model(e, .generateBox(size: [0.24, 0.018, 0.17], cornerRadius: 0.008), towel, at: [0.17, shelfY + 0.013 + Float(i) * 0.019, -0.02],
                  rotation: simd_quatf(angle: Float(i) * 0.04 - 0.04, axis: [0, 1, 0]))
        }
        dress(e)
        return e
    }

    private static var packaging: [String: TextureResource] = [:]

    /// Printed carton side: white board, a coloured band, product text. Generic, no brand.
    private static func carton(_ key: String, title: String, subtitle: String, band: UIColor) -> PhysicallyBasedMaterial {
        if packaging[key] == nil {
            let size = CGSize(width: 512, height: 256)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                band.setFill(); ctx.fill(CGRect(x: 0, y: 170, width: 512, height: 86))
                let t = NSAttributedString(string: title, attributes: [.font: UIFont.systemFont(ofSize: 50, weight: .heavy), .foregroundColor: UIColor(white: 0.12, alpha: 1)])
                t.draw(at: CGPoint(x: 30, y: 40))
                let s = NSAttributedString(string: subtitle, attributes: [.font: UIFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: UIColor(white: 0.35, alpha: 1)])
                s.draw(at: CGPoint(x: 32, y: 108))
                let w = NSAttributedString(string: "100 pcs  ·  powder-free  ·  latex-free", attributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.white])
                w.draw(at: CGPoint(x: 32, y: 196))
            }
            packaging[key] = img.cgImage.flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
        }
        var m = plain(.white, roughness: 0.55)
        if let t = packaging[key] { m.baseColor = .init(tint: .white, texture: .init(t)) }
        return m
    }

    private static func gloveBox(at p: SIMD3<Float>, yaw: Float) -> Entity {
        let e = Entity()
        e.position = p
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let blue = UIColor(red: 0.20, green: 0.42, blue: 0.80, alpha: 1)
        let side = carton("gloves", title: "NITRILE", subtitle: "Examination gloves  ·  M", band: blue)
        let board = plain(UIColor(white: 0.96, alpha: 1), roughness: 0.6)
        // printed front and back, plain board elsewhere
        model(e, .generateBox(size: [0.235, 0.065, 0.118], cornerRadius: 0.002), board, at: [0, 0.0325, 0])
        model(e, .generatePlane(width: 0.233, height: 0.063), side, at: [0, 0.0325, 0.0592])
        model(e, .generatePlane(width: 0.08, height: 0.02, cornerRadius: 0.01), plain(UIColor(white: 0.25, alpha: 1)), at: [0, 0.0652, 0],
              rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        // a glove poking out of the slot
        let nitrile = pbr("strap", tint: UIColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1), tile: [4, 4], roughness: 0.55)
        for (i, o) in [SIMD3<Float>(-0.012, 0.072, 0.002), [0.01, 0.075, -0.004], [0.0, 0.08, 0.004]].enumerated() {
            let tuft = model(e, .generateSphere(radius: 0.017), nitrile, at: o)
            tuft.scale = [1.2, 0.55 + Float(i) * 0.08, 0.7]
        }
        return e
    }

    /// Roll of tubular cotton stockinette, worn under a support.
    private static func stockinette(at p: SIMD3<Float>) -> Entity {
        let e = Entity()
        e.position = p
        let cotton = pbr("strap", tint: UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1), tile: [6, 2], roughness: 1)
        model(e, .generateCylinder(height: 0.07, radius: 0.03), cotton, rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        model(e, .generateCylinder(height: 0.071, radius: 0.011), plain(UIColor(red: 0.62, green: 0.5, blue: 0.36, alpha: 1), roughness: 0.9),
              rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
        return e
    }

    // MARK: Items

    /// Lying pose for a brace on the drape: axis across the tray at an angle, open back up so the lining and strap ends show,
    /// thumb opening towards the wearer.
    static func braceRest(yaw: Float) -> simd_quatf {
        simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
    }

    /// Neoprene thumb-spica wrist brace: textured shell with a lighter lining, bound edges,
    /// three hook-and-loop straps with steel D-rings, a palmar stay and a woven size label.
    static func brace(radius r: Float, size: String) -> Entity {
        let e = Entity()
        let a = r * 0.9, b = r * 1.12, gap: Float = 0.42
        let shell = pbr("neoprene", tint: UIColor(red: 0.58, green: 0.60, blue: 0.63, alpha: 1), tile: [5, 3], roughness: 0.95)
        let lining = pbr("neoprene", tint: UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1), tile: [5, 3], roughness: 1)
        let binding = pbr("strap", tint: UIColor(white: 0.10, alpha: 1), tile: [8, 1], roughness: 0.8)
        let strap = pbr("strap", tint: UIColor(white: 0.13, alpha: 1), tile: [6, 1], roughness: 0.85)
        let ring = Self.steel
        let profile = OrthoticsLab.braceProfile
        model(e, OrthoticsLab.tube(profile, a: a, b: b, arc: gap...(2 * .pi - gap), segments: 48), shell)
        model(e, OrthoticsLab.tube(profile.map { ($0.y, $0.s * 0.975) }, a: a, b: b, arc: gap...(2 * .pi - gap), segments: 48), lining)
        for y in [profile.first!.y, profile.last!.y] {
            let s = OrthoticsLab.scale(at: y)
            model(e, OrthoticsLab.tube([(y - 0.003, s * 1.012), (y + 0.003, s * 1.012)], a: a, b: b, arc: gap...(2 * .pi - gap), segments: 48), binding)
        }
        for y in [Float(-0.062), -0.022, 0.05] {
            let s = OrthoticsLab.scale(at: y)
            model(e, OrthoticsLab.tube([(y - 0.011, s * 1.03), (y + 0.011, s * 1.03)], a: a, b: b, arc: 0.15...(2 * .pi - 0.15), segments: 48), strap)
            // strap end crossing the opening, folded through a D-ring
            model(e, .generateBox(size: [0.003, 0.024, 0.026], cornerRadius: 0.0012), ring, at: [(a + 0.0045) * s, y, b * s * 0.22])
            model(e, .generateBox(size: [0.0025, 0.021, 0.03], cornerRadius: 0.001), strap, at: [(a + 0.0055) * s, y, -b * s * 0.05])
        }
        // palmar stay pocket and the woven size label on it
        model(e, .generateBox(size: [0.005, 0.13, 0.022], cornerRadius: 0.0024), binding, at: [-(a * 1.06 + 0.002), -0.008, 0])
        let label = Entity()
        label.position = [0, -0.045, b * OrthoticsLab.scale(at: -0.045) + 0.0025]
        label.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        model(label, .generateBox(size: [0.03, 0.016, 0.0008], cornerRadius: 0.002), plain(UIColor(white: 0.95, alpha: 1), roughness: 0.8))
        let text = print(size, size: 0.011, weight: .heavy, color: UIColor(white: 0.12, alpha: 1))
        text.position.z = 0.0005
        label.addChild(text)
        e.addChild(label)
        // thumb opening: bound edge and the dark hole
        let y: Float = 0.04
        let hole = model(e, OrthoticsLab.tube([(-0.004, 1), (0.004, 1)], a: 0.016, b: 0.016), binding, at: [0, y, b * OrthoticsLab.scale(at: y) + 0.002])
        hole.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        let disc = model(e, .generateCylinder(height: 0.003, radius: 0.0155), plain(UIColor(white: 0.03, alpha: 1), roughness: 1),
                         at: [0, y, b * OrthoticsLab.scale(at: y) - 0.001])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        dress(e)
        return e
    }

    /// Body measuring tape: round white case with a teal grip ring, chrome button, tape pulled out to +X.
    static func tapeMeasure() -> Entity {
        let e = Entity()
        let plastic = pbr("plastic", tint: UIColor(white: 0.97, alpha: 1), tile: [1, 1], roughness: 0.45, clearcoat: 0.4)
        let grip = pbr("plastic", tint: UIColor(red: 0.05, green: 0.55, blue: 0.60, alpha: 1), tile: [1, 1], roughness: 0.8)
        model(e, .generateCylinder(height: 0.024, radius: 0.032), plastic)
        model(e, .generateCylinder(height: 0.012, radius: 0.0335), grip)
        model(e, .generateCylinder(height: 0.026, radius: 0.011), Self.steel)
        model(e, .generateBox(size: [0.012, 0.016, 0.024], cornerRadius: 0.003), plastic, at: [0.031, -0.002, 0])
        let strip = SpatialMeasurementTool.strip(length: 0.11, width: 0.014)
        strip.position = [0.036, -0.0105, 0]
        strip.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 0, 1])
        e.addChild(strip)
        model(e, .generateBox(size: [0.004, 0.006, 0.018], cornerRadius: 0.001),
              pbr("steel", tint: UIColor(red: 0.85, green: 0.7, blue: 0.4, alpha: 1), roughness: 0.4, metallic: 1), at: [0.148, -0.0085, 0])
        dress(e)
        return e
    }

    /// Printed tent card standing in front of each support: size letter and wrist range.
    static func sizeCard(size: String, range: String) -> Entity {
        let e = Entity()
        let card = Entity()
        card.orientation = simd_quatf(angle: -0.95, axis: [1, 0, 0]) // leaning back, readable from above
        card.position = [0, 0.017, 0]
        e.addChild(card)
        model(card, .generateBox(size: [0.085, 0.042, 0.0012], cornerRadius: 0.003), plain(UIColor(white: 0.98, alpha: 1), roughness: 0.7))
        model(card, .generateBox(size: [0.085, 0.006, 0.0013]), plain(UIColor(red: 0.05, green: 0.55, blue: 0.60, alpha: 1), roughness: 0.6), at: [0, -0.018, 0.0001])
        let letter = print(size, size: 0.022, weight: .heavy, color: UIColor(white: 0.1, alpha: 1))
        letter.position = [-0.026, 0.002, 0.0008]
        card.addChild(letter)
        let line1 = print("Wrist", size: 0.0062, weight: .semibold, color: UIColor(white: 0.4, alpha: 1))
        line1.position = [0.012, 0.0075, 0.0008]
        card.addChild(line1)
        let line2 = print(range, size: 0.0082, weight: .bold, color: UIColor(white: 0.12, alpha: 1))
        line2.position = [0.012, -0.003, 0.0008]
        card.addChild(line2)
        dress(e)
        return e
    }
}
