import RealityKit
import UIKit
import ImageIO

/// Helpers for the pitch-only places (PitchDressing). Everything is synchronous, because
/// EnvironmentSet.show() builds the place in one go and the screenshot follows a few seconds later.
/// Assets live in Resources/Pitch/ (flattened into the bundle root) and come from
/// visionos/scripts/pitch_assets.py. Missing assets log a SMOKE line and return a fallback, never crash.
@MainActor
enum PitchKit {
    // MARK: Models

    private static var models: [String: Entity] = [:]

    /// `<name>.usdz` from the bundle, as a fresh clone (cached, so placing it many times is cheap).
    /// Loaded synchronously: blocks the main thread while it reads (fine for pitch shots).
    static func model(_ name: String) -> Entity? {
        if let m = models[name] { return m.clone(recursive: true) }
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else { return missing("\(name).usdz") }
        do {
            let m = try Entity.load(contentsOf: url) // the only synchronous loader; deprecated, still works
            models[name] = m
            return m.clone(recursive: true)
        } catch { return missing("\(name).usdz: \(error)") }
    }

    /// `model(name)` added to `parent`, scaled so its largest bounding-box edge is `fit` metres (when given),
    /// standing on `at` (its bottom at at.y), turned by `yaw` (radians, about +Y), with a soft contact
    /// shadow under it (`shadow`, for props standing on the floor or a worktop).
    @discardableResult
    static func place(_ name: String, in parent: Entity, at p: SIMD3<Float>, yaw: Float = 0, fit: Float? = nil,
                      shadow: Bool = true) -> Entity? {
        guard let m = model(name) else { return nil }
        let holder = Entity()
        holder.addChild(m)
        let b = m.visualBounds(relativeTo: holder)
        if let fit, b.extents.max() > 0 { m.scale *= fit / b.extents.max() }
        let s = m.visualBounds(relativeTo: holder)
        m.position -= [s.center.x, s.min.y, s.center.z] // centred on x/z, bottom on the floor
        holder.position = p
        holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if shadow { contactShadow(holder, at: [0, 0, 0], size: [s.extents.x, s.extents.z]) }
        parent.addChild(holder)
        return holder
    }

    // MARK: Materials

    private static var textures: [String: TextureResource] = [:]

    /// `<name>` (with extension, e.g. "clinic_poster.jpg") from the bundle as a texture.
    /// `.color` for albedo/pictures, `.raw` for data maps (normal, roughness, ...).
    static func texture(_ name: String, semantic: TextureResource.Semantic = .color) -> TextureResource? {
        let key = "\(name)#\(semantic)"
        if let t = textures[key] { return t }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let t = try? TextureResource(image: cg, options: .init(semantic: semantic)) else { return missing(name) }
        textures[key] = t
        return t
    }

    /// PBR material from `<prefix>_diff.jpg`, `_nor.jpg`, `_rough.jpg` and, when present, `_ao.jpg`, `_metal.jpg`.
    /// `tiling`: texture repeats across the mesh's 0...1 UVs (a 4 m x 9 m floor with a 1 m texture: [4, 9]).
    /// Generated boxes map the whole texture onto each face, so tile per face size.
    static func material(_ prefix: String, tiling: SIMD2<Float> = [1, 1], tint: UIColor = .white,
                         roughness: Float = 1, metallic: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let has = { (s: String) in Bundle.main.url(forResource: "\(prefix)_\(s)", withExtension: "jpg") != nil }
        if let t = texture("\(prefix)_diff.jpg") { m.baseColor = .init(tint: tint, texture: .init(t)) } else { m.baseColor = .init(tint: tint) }
        if let t = texture("\(prefix)_nor.jpg", semantic: .normal) { m.normal = .init(texture: .init(t)) }
        if let t = texture("\(prefix)_rough.jpg", semantic: .raw) { m.roughness = .init(scale: roughness, texture: .init(t)) }
        else { m.roughness = .init(floatLiteral: roughness) }
        if has("ao"), let t = texture("\(prefix)_ao.jpg", semantic: .raw) { m.ambientOcclusion = .init(texture: .init(t)) }
        if has("metal"), let t = texture("\(prefix)_metal.jpg", semantic: .raw) { m.metallic = .init(scale: 1, texture: .init(t)) }
        else { m.metallic = .init(floatLiteral: metallic) }
        m.textureCoordinateTransform = .init(scale: tiling)
        return m
    }

    // MARK: Lighting and shadows

    private static var environments: [String: EnvironmentResource] = [:]
    static let lightName = "pitch_ibl"

    /// Image-based light from `<hdri>.hdr` (equirect, from pitch_assets.py hdri) on `avatarRoot` and
    /// everything under it: the patient, the place, the panels' 3D content. Replaces the simulator's
    /// default environment light for that subtree. `intensity` is an exposure in stops (EV, 0 = as shot,
    /// 1 = twice as bright); `yaw` turns the HDRI so its windows/lamps fall where the place has them.
    /// PitchDressing clears it before every place is built, so each place sets its own.
    @discardableResult
    static func light(_ avatarRoot: Entity, hdri: String, intensity: Float = 0, yaw: Float = 0) -> Bool {
        guard let env = environment(hdri) else { return false }
        let ibl = Entity()
        ibl.name = lightName
        ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: intensity))
        ibl.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        avatarRoot.addChild(ibl) // not in the place: wrist-01 disables the place but keeps the patient lit
        avatarRoot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ibl))
        return true
    }

    /// Removes the light `light(_:hdri:)` added (PitchDressing calls this before each build).
    static func clearLight(_ avatarRoot: Entity) {
        avatarRoot.components.remove(ImageBasedLightReceiverComponent.self)
        avatarRoot.children.filter { $0.name == lightName }.forEach { $0.removeFromParent() }
    }

    static func environment(_ hdri: String) -> EnvironmentResource? {
        if let e = environments[hdri] { return e }
        guard let url = Bundle.main.url(forResource: hdri, withExtension: "hdr"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return missing("\(hdri).hdr") }
        do {
            let e = try EnvironmentResource(equirectangular: cg, withName: hdri)
            environments[hdri] = e
            return e
        } catch { return missing("\(hdri).hdr: \(error)") }
    }

    /// A soft dark blob on the ground under a prop (or the patient's seat): reads as contact shadow /
    /// ambient occlusion. Works everywhere, unlike GroundingShadowComponent, which draws nothing on
    /// virtual floors in the simulator. `size`: the footprint in metres (x, z); the blob is 1.5x wider.
    @discardableResult
    static func contactShadow(_ parent: Entity, at p: SIMD3<Float>, size: SIMD2<Float>, opacity: Float = 0.55) -> Entity {
        var m = UnlitMaterial(color: .black)
        m.blending = .transparent(opacity: blob.map { .init(scale: opacity, texture: .init($0)) } ?? .init(floatLiteral: opacity * 0.3))
        let e = ModelEntity(mesh: .generatePlane(width: max(size.x, 0.1) * 1.5, depth: max(size.y, 0.1) * 1.5), materials: [m])
        e.position = p + [0, 0.003, 0] // just above the floor, below anything standing on it
        e.name = "contact_shadow"
        parent.addChild(e)
        return e
    }

    /// Radial falloff as an opacity map: opaque centre, transparent rim.
    private static let blob: TextureResource? = {
        let n = 128
        var px = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let dx = (Float(x) + 0.5) / Float(n) * 2 - 1, dy = (Float(y) + 0.5) / Float(n) * 2 - 1
            let a = max(0, 1 - (dx * dx + dy * dy).squareRoot())
            px[y * n + x] = UInt8(255 * a * a * (3 - 2 * a)) // smoothstep: no visible edge
        } }
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .raw))
    }()

    /// Makes `surface` (the floor, a worktop) show real shadows from `sun`/`spot` lights. Needed under
    /// `light(_:hdri:)`: RealityKit draws no light shadows on IBL receivers, so the surface opts out of the
    /// HDRI and is lit by the scene's lights (and the system's default light) instead. Casters stay HDRI-lit.
    static func showShadows(on surface: Entity) {
        let noIBL = Entity() // a receiver target without ImageBasedLightComponent = no HDRI for this subtree
        surface.addChild(noIBL)
        surface.components.set(ImageBasedLightReceiverComponent(imageBasedLight: noIBL))
    }

    /// Sunlight (or any key light from far away) with real shadows, shining from `from` towards `to`.
    @discardableResult
    static func sun(_ parent: Entity, from: SIMD3<Float>, to: SIMD3<Float> = .zero, intensity: Float = 3000,
                    color: UIColor = .white, shadowDistance: Float = 8) -> Entity {
        let l = Entity()
        l.components.set(DirectionalLightComponent(color: color, intensity: intensity))
        l.components.set(DirectionalLightComponent.Shadow(maximumDistance: shadowDistance, depthBias: 1))
        parent.addChild(l)
        l.look(at: to, from: from, relativeTo: parent)
        return l
    }

    /// A spot light (ceiling lamp, examination light) with real shadows, aimed from `at` to `target`.
    /// `intensity` in lumen-ish RealityKit units: 20000-60000 for a room lamp.
    @discardableResult
    static func spot(_ parent: Entity, at p: SIMD3<Float>, target: SIMD3<Float>, intensity: Float = 20000,
                     color: UIColor = .white, angle: Float = 60, radius: Float = 10) -> Entity {
        let l = Entity()
        var c = SpotLightComponent(color: color, intensity: intensity, innerAngleInDegrees: angle * 0.5,
                                   outerAngleInDegrees: angle, attenuationRadius: radius)
        c.attenuationFalloffExponent = 2
        l.components.set(c)
        l.components.set(SpotLightComponent.Shadow())
        parent.addChild(l)
        l.look(at: target, from: p, relativeTo: parent)
        return l
    }

    private static func missing<T>(_ what: String) -> T? {
        SmokeLog.mark("pitch asset missing \(what)")
        return nil
    }
}
