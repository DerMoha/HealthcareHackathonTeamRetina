import RealityKit
import UIKit

/// Pitch dressing: the patient compartment of a UK/EU box ambulance (rt-04), seen across the vehicle.
/// The long axis of the ambulance is X: cab bulkhead on the left (-X, the stretcher's head end), rear doors
/// on the right (+X). The wearer stands at the nearside; the wall behind the patient is the offside wall
/// with the overhead lockers, the monitor/defibrillator on its bracket, oxygen and suction, the worktop
/// with sharps bin and gloves, and the attendant's seat in the corner at the bulkhead.
@MainActor
enum PitchAmbulance {
    // Compartment box (avatar space).
    static let xF: Float = -2.1, xR: Float = 1.75, zB: Float = -0.78, zN: Float = 2.4, h: Float = 2.15

    static func build(into set: Entity, seat: Float, avatarRoot: Entity) -> Bool {
        let length = xR - xF, cx = (xF + xR) / 2, depth = zN - zB, cz = (zN + zB) / 2

        // Floor: grey non-slip safety flooring, diamond tread plate at the rear sill.
        let floor = ModelEntity(mesh: .generatePlane(width: length, depth: depth),
                                materials: [tinted("ambulance_floor", tiling: [length * 1.5, depth * 1.5], UIColor(white: 0.5, alpha: 1), roughness: 0.9)])
        floor.position = [cx, 0, cz]
        set.addChild(floor)
        let tread = ModelEntity(mesh: .generatePlane(width: 0.22, depth: depth),
                                materials: [PitchKit.material("ambulance_tread", tiling: [0.6, depth * 2.5], roughness: 0.5)])
        tread.position = [xR - 0.11, 0.002, cz]
        set.addChild(tread)

        // Walls and ceiling: white wipe-clean GRP.
        let white = UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1)
        wall(set, size: [length, h], at: [cx, h / 2, zB], yaw: 0, tint: white)                 // offside wall
        wall(set, size: [depth, h], at: [xF, h / 2, cz], yaw: .pi / 2, tint: white)            // cab bulkhead
        let ceiling = ModelEntity(mesh: .generatePlane(width: length, depth: depth), materials: [tinted("ambulance_plastic", tiling: [3, 2], white, roughness: 0.5)])
        ceiling.position = [cx, h, cz]
        ceiling.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0])
        set.addChild(ceiling)
        // Rounded coves where the walls meet the ceiling and the floor (cylinders half buried in the corner).
        let cove = pbr(white, 0.35)
        cyl(set, length, 0.09, cove, at: [cx, h, zB], axis: .x)
        cyl(set, depth, 0.09, cove, at: [xF, h, cz], axis: .z)
        let skirting = pbr(UIColor(white: 0.42, alpha: 1), 0.6)
        cyl(set, length, 0.05, skirting, at: [cx, 0, zB], axis: .x)
        cyl(set, depth, 0.05, skirting, at: [xF, 0, cz], axis: .z)

        offsideWall(set)
        bulkhead(set)
        rearDoors(set)
        ceilingFittings(set)
        stretcher(set, seat: seat)
        floorKit(set)

        // Light: HDRI for the overall white bounce, LED panels as spots with shadows on the floor.
        PitchKit.light(avatarRoot, hdri: "ambulance_ibl", intensity: 0.7)
        PitchKit.showShadows(on: floor)
        let cool = UIColor(red: 0.96, green: 0.98, blue: 1, alpha: 1)
        PitchKit.spot(set, at: [-0.6, h - 0.05, 0.1], target: [-0.4, 0, -0.1], intensity: 26000, color: cool, angle: 95)
        PitchKit.spot(set, at: [0.9, h - 0.05, 0.1], target: [0.7, 0, -0.1], intensity: 22000, color: cool, angle: 95)
        PitchKit.sun(set, from: [0.3, 3, 2.0], to: [0, 0, -0.4], intensity: 2200, color: cool)
        point(set, at: [-0.9, 1.45, zB + 0.5], intensity: 9000, radius: 2.2, color: cool) // under-locker LEDs
        point(set, at: [0.6, 1.45, zB + 0.5], intensity: 6000, radius: 2.2, color: cool)
        return true
    }

    // MARK: Offside wall

    private static func offsideWall(_ e: Entity) {
        let white = pbr(UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1), 0.3)
        let trim = pbr(UIColor(white: 0.55, alpha: 1), 0.4)
        let dark = pbr(UIColor(white: 0.12, alpha: 1), 0.5)

        // Overhead lockers along the full length: white carcass, smoked sliding fronts, bins behind, labels.
        let x0: Float = xF + 0.05, x1: Float = xR - 0.05, yb: Float = 1.6, yt: Float = h - 0.02, d: Float = 0.38
        box(e, [x1 - x0, 0.03, d], white, at: [(x0 + x1) / 2, yb + 0.015, zB + d / 2], corner: 0.01)
        box(e, [x1 - x0, 0.04, d], white, at: [(x0 + x1) / 2, yt - 0.02, zB + d / 2], corner: 0.01)
        box(e, [x1 - x0, 0.09, 0.02], white, at: [(x0 + x1) / 2, yb + 0.045, zB + d - 0.01], corner: 0.008)
        box(e, [0.02, yt - yb, d], white, at: [x0, (yb + yt) / 2, zB + d / 2])
        box(e, [0.02, yt - yb, d], white, at: [x1, (yb + yt) / 2, zB + d / 2])
        let bays: [(String, UIColor)] = [("AIRWAY", UIColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1)),
                                        ("O₂ MASKS", UIColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 1)),
                                        ("IV / CANNULAE", UIColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)),
                                        ("DRESSINGS", UIColor(red: 0.95, green: 0.7, blue: 0.1, alpha: 1)),
                                        ("SPLINTS", UIColor(red: 0.5, green: 0.3, blue: 0.75, alpha: 1)),
                                        ("OBS / BM", UIColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1))]
        let bw = (x1 - x0) / Float(bays.count)
        let rimMat = pbr(UIColor(white: 0.7, alpha: 1), 0.25, metal: 1)
        for (i, (name, c)) in bays.enumerated() {
            let x = x0 + bw * (Float(i) + 0.5)
            // Recess (dark interior) and two bins inside.
            box(e, [bw - 0.04, yt - yb - 0.12, 0.01], pbr(UIColor(white: 0.55, alpha: 1), 0.7), at: [x, (yb + yt) / 2 + 0.03, zB + 0.05])
            for k in 0..<2 {
                let bx = x + (Float(k) - 0.5) * bw * 0.46
                box(e, [bw * 0.42, 0.17, 0.26], pbr(c, 0.45), at: [bx, yb + 0.2, zB + 0.2], corner: 0.01)
                plane(e, [bw * 0.36, 0.06], label(name, c), at: [bx, yb + 0.2, zB + 0.332])
            }
            // Smoked front with a dark handle strip and the printed label below it.
            for sy: Float in [yb + 0.33, yb + 0.12] { box(e, [bw - 0.03, 0.022, 0.008], pbr(UIColor(white: 0.18, alpha: 1), 0.8), at: [x, sy, zB + d - 0.03]) }
            box(e, [bw * 0.5, 0.018, 0.012], dark, at: [x, yb + 0.1, zB + d + 0.012])
            box(e, [bw - 0.03, 0.012, 0.012], rimMat, at: [x, yt - 0.02, zB + d + 0.006])
            plane(e, [bw * 0.72, 0.055], label(name, c, onWhite: true), at: [x, yb + 0.045, zB + d + 0.002])
            box(e, [0.012, yt - yb, d + 0.01], trim, at: [x0 + bw * Float(i), (yb + yt) / 2, zB + d / 2])
        }
        // LED strip under the lockers.
        box(e, [x1 - x0 - 0.1, 0.012, 0.03], UnlitMaterial(color: UIColor(red: 0.95, green: 0.98, blue: 1, alpha: 1)), at: [(x0 + x1) / 2, yb - 0.006, zB + d - 0.06])

        // Wipe-clean lower cabinets with a worktop, dark recessed handles.
        let cab = pbr(UIColor(white: 0.9, alpha: 1), 0.35)
        let cabX0: Float = xF + 0.62, cabX1: Float = xR - 0.05, ct: Float = 0.88, cd: Float = 0.27
        box(e, [cabX1 - cabX0, ct, cd], cab, at: [(cabX0 + cabX1) / 2, ct / 2, zB + cd / 2], corner: 0.01)
        box(e, [cabX1 - cabX0 + 0.02, 0.03, cd + 0.03], pbr(UIColor(white: 0.32, alpha: 1), 0.5), at: [(cabX0 + cabX1) / 2, ct + 0.015, zB + (cd + 0.03) / 2], corner: 0.01)
        let doors = Int((cabX1 - cabX0) / 0.5)
        let dw = (cabX1 - cabX0) / Float(doors)
        for i in 0..<doors {
            let x = cabX0 + dw * (Float(i) + 0.5)
            box(e, [0.006, ct - 0.08, 0.006], trim, at: [cabX0 + dw * Float(i), ct / 2, zB + cd + 0.002])
            box(e, [dw * 0.4, 0.025, 0.01], dark, at: [x, ct - 0.1, zB + cd + 0.004], corner: 0.005)
            box(e, [dw - 0.04, 0.005, 0.006], trim, at: [x, ct * 0.5, zB + cd + 0.002])
        }
        // Grey bump rail along the wall, at worktop height above the cabinets.
        box(e, [cabX1 - cabX0, 0.05, 0.03], pbr(UIColor(white: 0.45, alpha: 1), 0.5), at: [(cabX0 + cabX1) / 2, 1.1, zB + 0.015], corner: 0.01)

        // Monitor/defibrillator on its wall bracket, turned towards the stretcher and the wearer.
        let mon = Entity(); mon.position = [-1.12, 1.38, zB + 0.2]; mon.orientation = simd_quatf(angle: 0.35, axis: [0, 1, 0]); e.addChild(mon)
        box(e, [0.2, 0.08, 0.12], pbr(UIColor(white: 0.25, alpha: 1), 0.4, metal: 0.6), at: [-1.12, 1.18, zB + 0.06], corner: 0.01)  // bracket
        box(mon, [0.46, 0.36, 0.2], pbr(UIColor(white: 0.17, alpha: 1), 0.45), at: [0, 0, 0], corner: 0.03)
        box(mon, [0.47, 0.06, 0.205], pbr(UIColor(red: 0.85, green: 0.1, blue: 0.12, alpha: 1), 0.45), at: [0, 0.16, 0], corner: 0.02)
        box(mon, [0.08, 0.3, 0.14], pbr(UIColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1), 0.45), at: [0.255, -0.01, 0], corner: 0.02) // pads/therapy side
        plane(mon, [0.33, 0.235], vitals(), at: [-0.04, -0.01, 0.101])
        for i in 0..<4 { cyl(mon, 0.012, 0.012, pbr(UIColor(white: 0.5, alpha: 1), 0.4), at: [0.17, 0.09 - Float(i) * 0.06, 0.101], axis: .z) }
        // Leads from the monitor down to the patient's chest area (dangling cables).
        let lead = pbr(UIColor(white: 0.2, alpha: 1), 0.5)
        rod(e, from: [-1.0, 1.2, zB + 0.28], to: [-0.92, 0.95, zB + 0.3], radius: 0.004, lead)
        rod(e, from: [-0.92, 0.95, zB + 0.3], to: [-0.8, 1.0, zB + 0.3], radius: 0.004, lead)

        // Oxygen and suction panel next to the bulkhead seat.
        let px: Float = -1.55
        box(e, [0.3, 0.42, 0.04], pbr(UIColor(white: 0.93, alpha: 1), 0.3), at: [px, 1.32, zB + 0.02], corner: 0.01)
        plane(e, [0.26, 0.05], sign("OXYGEN", bg: UIColor(red: 0.0, green: 0.55, blue: 0.3, alpha: 1)), at: [px, 1.49, zB + 0.042])
        for (i, ox) in [Float(-0.07), 0.07].enumerated() {
            cyl(e, 0.02, 0.032, pbr(.white, 0.3), at: [px + ox, 1.4, zB + 0.05], axis: .z)
            cyl(e, 0.022, 0.016, pbr(i == 0 ? UIColor(white: 0.97, alpha: 1) : UIColor(white: 0.1, alpha: 1), 0.3), at: [px + ox, 1.4, zB + 0.065], axis: .z)
        }
        // O2 flowmeter (clear tube, green knob) and the suction unit with its canister.
        cyl(e, 0.13, 0.018, pbr(UIColor(red: 0.9, green: 0.97, blue: 1, alpha: 0.55), 0.05), at: [px - 0.07, 1.26, zB + 0.08])
        cyl(e, 0.03, 0.022, pbr(UIColor(red: 0.1, green: 0.6, blue: 0.25, alpha: 1), 0.4), at: [px - 0.07, 1.34, zB + 0.08])
        box(e, [0.12, 0.08, 0.08], pbr(UIColor(white: 0.85, alpha: 1), 0.3), at: [px + 0.07, 1.27, zB + 0.07], corner: 0.01)
        cyl(e, 0.18, 0.055, pbr(UIColor(red: 0.85, green: 0.93, blue: 0.97, alpha: 0.5), 0.05), at: [px + 0.07, 1.14, zB + 0.1])
        cyl(e, 0.025, 0.058, pbr(UIColor(red: 0.1, green: 0.35, blue: 0.75, alpha: 1), 0.4), at: [px + 0.07, 1.24, zB + 0.1])
        rod(e, from: [px - 0.07, 1.19, zB + 0.08], to: [px - 0.18, 0.95, zB + 0.2], radius: 0.006, pbr(UIColor(red: 0.85, green: 0.95, blue: 0.9, alpha: 0.8), 0.2))

        // On the worktop: sharps bin, glove dispenser on the wall above, hand gel.
        let sx: Float = -1.38
        box(e, [0.17, 0.2, 0.13], pbr(UIColor(red: 0.98, green: 0.82, blue: 0.08, alpha: 1), 0.45), at: [sx, 0.9 + 0.1, zB + 0.12], corner: 0.01)
        box(e, [0.18, 0.04, 0.14], pbr(UIColor(red: 0.95, green: 0.4, blue: 0.08, alpha: 1), 0.45), at: [sx, 1.12, zB + 0.12], corner: 0.01)
        plane(e, [0.12, 0.08], drawn(240, 160) { r in
            UIColor(red: 0.98, green: 0.82, blue: 0.08, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            text("SHARPS", at: CGPoint(x: 18, y: 18), size: 48, weight: .heavy, color: .black)
            text("DANGER", at: CGPoint(x: 30, y: 84), size: 40, weight: .bold, color: .red)
        }, at: [sx, 0.99, zB + 0.186])
        let gloveX: Float = -0.62
        box(e, [0.44, 0.16, 0.02], pbr(UIColor(white: 0.8, alpha: 1), 0.3, metal: 0.8), at: [gloveX, 1.28, zB + 0.01], corner: 0.005)
        box(e, [0.44, 0.015, 0.11], pbr(UIColor(white: 0.8, alpha: 1), 0.3, metal: 0.8), at: [gloveX, 1.215, zB + 0.055])
        for (i, c) in [UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 1), UIColor(red: 0.45, green: 0.35, blue: 0.85, alpha: 1), UIColor(red: 0.25, green: 0.55, blue: 0.85, alpha: 1)].enumerated() {
            let x = gloveX + Float(i - 1) * 0.135
            box(e, [0.125, 0.11, 0.09], pbr(c, 0.6), at: [x, 1.28, zB + 0.065], corner: 0.005)
            plane(e, [0.06, 0.05], drawn(120, 100) { _ in text(["S", "M", "L"][i], at: CGPoint(x: 38, y: 8), size: 76, weight: .heavy, color: .white) }, at: [x, 1.28, zB + 0.111])
        }
        box(e, [0.07, 0.15, 0.06], pbr(.white, 0.35), at: [-0.95, 0.975, zB + 0.1], corner: 0.01)
        box(e, [0.04, 0.03, 0.03], pbr(UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), 0.4), at: [-0.95, 1.06, zB + 0.1])
        // Warning sticker.
        plane(e, [0.28, 0.1], drawn(560, 200) { r in
            UIColor.white.setFill(); UIBezierPath(rect: r).fill()
            UIColor(red: 0.85, green: 0.1, blue: 0.12, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: r.width, height: 60)).fill()
            text("PLEASE WEAR YOUR SEATBELT", at: CGPoint(x: 22, y: 10), size: 34, weight: .heavy, color: .white)
            text("Oxygen in use · No smoking", at: CGPoint(x: 22, y: 90), size: 38, weight: .semibold, color: .darkGray)
        }, at: [-1.75, 0.95, zB + 0.003])
    }

    // MARK: Bulkhead (head end)

    private static func bulkhead(_ e: Entity) {
        // Pass-through window into the cab, high up.
        let win = Entity(); win.position = [xF + 0.004, 1.62, -0.15]; win.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]); e.addChild(win)
        box(win, [0.62, 0.34, 0.012], pbr(UIColor(white: 0.62, alpha: 1), 0.3, metal: 0.7), at: [0, 0, 0], corner: 0.035)
        plane(win, [0.54, 0.26], cabView(), at: [0, 0, 0.006])

        // Attendant's seat in the corner, facing the rear: grey vinyl on a seat box, red 4-point harness.
        let seat = Entity(); seat.position = [xF + 0.02, 0, zB + 0.32]; seat.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]); e.addChild(seat)
        let vinyl = tinted("ambulance_vinyl", tiling: [2, 2], UIColor(red: 0.36, green: 0.4, blue: 0.46, alpha: 1), roughness: 0.6)
        let frame = pbr(UIColor(white: 0.3, alpha: 1), 0.4, metal: 0.5)
        let ch: Float = 0.37 // cushion top = the seated avatars' seat height
        box(seat, [0.48, 0.08, 0.46], vinyl, at: [0, ch - 0.04, 0.27], corner: 0.035)       // cushion
        box(seat, [0.46, 0.62, 0.09], vinyl, at: [0, ch + 0.36, 0.06], corner: 0.04)      // backrest
        box(seat, [0.3, 0.17, 0.09], vinyl, at: [0, ch + 0.82, 0.06], corner: 0.04)       // headrest
        box(seat, [0.42, ch - 0.08, 0.4], pbr(UIColor(white: 0.82, alpha: 1), 0.4), at: [0, (ch - 0.08) / 2, 0.24], corner: 0.02) // seat box
        box(seat, [0.03, 1.05, 0.05], frame, at: [-0.215, ch + 0.45, 0.0])
        box(seat, [0.03, 1.05, 0.05], frame, at: [0.215, ch + 0.45, 0.0])
        let belt = pbr(UIColor(red: 0.78, green: 0.1, blue: 0.1, alpha: 1), 0.7)
        if withEMT {
            emt(seat, at: [0, 0, 0.24])
        } else {
            let buckle: SIMD3<Float> = [0, ch + 0.16, 0.13]
            for sx: Float in [-1, 1] {
                let top: SIMD3<Float> = [sx * 0.11, ch + 0.66, 0.11]
                let strap = ModelEntity(mesh: .generateBox(size: [0.045, simd_distance(top, buckle), 0.008]), materials: [belt])
                strap.position = (top + buckle) / 2
                strap.orientation = simd_quatf(from: [0, 1, 0], to: simd_normalize(top - buckle))
                seat.addChild(strap)
                box(seat, [0.18, 0.045, 0.008], belt, at: [sx * 0.11, ch + 0.06, 0.5])
            }
            box(seat, [0.1, 0.1, 0.025], pbr(UIColor(white: 0.75, alpha: 1), 0.25, metal: 1), at: buckle + [0, 0, 0.01], corner: 0.03) // rotary buckle
        }
        // Fire extinguisher on the bulkhead beside the seat.
        cyl(e, 0.38, 0.055, pbr(UIColor(red: 0.8, green: 0.08, blue: 0.08, alpha: 1), 0.35), at: [xF + 0.07, 0.32, 0.12])
        cyl(e, 0.06, 0.02, pbr(UIColor(white: 0.15, alpha: 1), 0.4), at: [xF + 0.07, 0.54, 0.12])
        box(e, [0.02, 0.06, 0.16], pbr(UIColor(white: 0.3, alpha: 1), 0.4, metal: 0.6), at: [xF + 0.01, 0.4, 0.12])
        PitchKit.contactShadow(seat, at: [0, 0, 0.27], size: [0.5, 0.45])
    }

    // MARK: Rear doors

    private static func rearDoors(_ e: Entity) {
        let door = Entity(); door.position = [xR, 0, 0]; door.orientation = simd_quatf(angle: -.pi / 2, axis: [0, 1, 0]); e.addChild(door)
        // With yaw -pi/2 the local +X is world +Z, local +Z is world -X (into the cabin).
        let panel = tinted("ambulance_plastic", tiling: [3, 2], UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1), roughness: 0.4)
        let width = zN - zB
        let mid = (zB + zN) / 2 // local x of the door centre
        box(door, [width, h, 0.04], panel, at: [mid, h / 2, 0.02])
        // Split between the two doors, a window in each door.
        let split: Float = 0.25
        box(door, [0.03, h - 0.1, 0.02], pbr(UIColor(white: 0.25, alpha: 1), 0.5), at: [split, h / 2, 0.05])
        for wx: Float in [split - 0.52, split + 0.52] {
            box(door, [0.62, 0.56, 0.02], pbr(UIColor(white: 0.18, alpha: 1), 0.4), at: [wx, 1.45, 0.045], corner: 0.04)
            plane(door, [0.56, 0.5], rearView(), at: [wx, 1.45, 0.056])
            // Hi-vis chevrons on the lower door.
            plane(door, [0.62, 0.42], chevrons(), at: [wx, 0.32, 0.042])
        }
        // Door handles and a grab handle.
        box(door, [0.04, 0.22, 0.04], pbr(UIColor(white: 0.8, alpha: 1), 0.25, metal: 1), at: [split - 0.1, 1.05, 0.07], corner: 0.01)
        rod(door, from: [split - 0.95, 1.0, 0.09], to: [split - 0.95, 1.35, 0.09], radius: 0.014, pbr(UIColor(white: 0.85, alpha: 1), 0.2, metal: 1))
        // Sill with yellow/black hazard stripe.
        plane(door, [width, 0.06], hazard(), at: [mid, 0.035, 0.041])
    }

    // MARK: Ceiling

    private static func ceilingFittings(_ e: Entity) {
        let steel = PitchKit.material("ambulance_steel", tiling: [8, 1], roughness: 0.35)
        // Grab rail along the ceiling above the stretcher with drop brackets.
        let rz: Float = 0.35, ry: Float = h - 0.15
        rod(e, from: [xF + 0.3, ry, rz], to: [xR - 0.3, ry, rz], radius: 0.017, steel)
        for x: Float in [xF + 0.45, -0.3, 0.9] { rod(e, from: [x, h, rz], to: [x, ry, rz], radius: 0.012, steel) }
        // LED panels flush in the ceiling.
        let ledFrame = pbr(UIColor(white: 0.95, alpha: 1), 0.3)
        for x: Float in [-1.3, -0.15, 1.0] {
            box(e, [0.78, 0.012, 0.36], ledFrame, at: [x, h - 0.006, -0.05])
            box(e, [0.72, 0.014, 0.3], UnlitMaterial(color: UIColor(red: 0.97, green: 0.99, blue: 1, alpha: 1)), at: [x, h - 0.008, -0.05])
        }
        for x: Float in [-0.9, 0.6] {
            box(e, [0.6, 0.012, 0.3], ledFrame, at: [x, h - 0.006, 1.0])
            box(e, [0.55, 0.014, 0.25], UnlitMaterial(color: UIColor(red: 0.97, green: 0.99, blue: 1, alpha: 1)), at: [x, h - 0.008, 1.0])
        }
        // IV hook on the rail at the head end.
        rod(e, from: [-0.7, ry, rz], to: [-0.7, ry - 0.12, rz], radius: 0.006, steel)
        var bag = PhysicallyBasedMaterial()
        bag.baseColor = .init(tint: UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1)); bag.roughness = 0.15
        bag.blending = .transparent(opacity: 0.6)
        box(e, [0.13, 0.2, 0.03], bag, at: [-0.7, ry - 0.23, rz], corner: 0.012)
        plane(e, [0.09, 0.11], drawn(300, 360) { r in
            UIColor.white.setFill(); UIBezierPath(rect: r).fill()
            text("Sodium\nChloride\n0.9%", at: CGPoint(x: 20, y: 24), size: 62, weight: .bold, color: UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1))
            text("500 mL", at: CGPoint(x: 20, y: 270), size: 44, weight: .medium, color: .darkGray)
        }, at: [-0.7, ry - 0.22, rz + 0.016])
    }

    // MARK: Stretcher

    private static func stretcher(_ e: Entity, seat: Float) {
        let z: Float = -0.12
        let alu = PitchKit.material("ambulance_steel", tiling: [4, 1], roughness: 0.3)
        let black = pbr(UIColor(white: 0.1, alpha: 1), 0.6)
        let mattress = tinted("ambulance_vinyl", tiling: [3, 1.2], UIColor(red: 0.1, green: 0.14, blue: 0.24, alpha: 1), roughness: 0.55)
        let sheet = pbr(UIColor(white: 0.97, alpha: 1), 0.85)
        // Mattress with a sheet; raised back rest at the head end (-X) with a pillow.
        box(e, [1.9, 0.09, 0.6], mattress, at: [0.05, seat - 0.045, z], corner: 0.035)
        box(e, [1.25, 0.012, 0.62], sheet, at: [0.2, seat + 0.001, z], corner: 0.004)
        let rest = Entity(); rest.position = [-0.55, seat, z]; rest.orientation = simd_quatf(angle: -0.75, axis: [0, 0, 1]); e.addChild(rest)
        box(rest, [0.72, 0.08, 0.58], mattress, at: [-0.36, 0.04, 0], corner: 0.035)
        box(rest, [0.3, 0.06, 0.42], sheet, at: [-0.46, 0.105, 0], corner: 0.03)
        // Red cellular blanket folded at the foot end.
        let blanket = tinted("ambulance_fabric", tiling: [4, 5], UIColor(red: 0.42, green: 0.05, blue: 0.06, alpha: 1), roughness: 1)
        box(e, [0.42, 0.05, 0.6], blanket, at: [0.74, seat + 0.025, z], corner: 0.024)
        cyl(e, 0.58, 0.035, blanket, at: [0.86, seat + 0.085, z], axis: .z)
        // Aluminium frame, side rails, safety straps hanging down.
        box(e, [1.95, 0.05, 0.62], alu, at: [0.05, seat - 0.115, z], corner: 0.015)
        for dz: Float in [-0.32, 0.32] {
            rod(e, from: [-0.8, seat - 0.115, z + dz], to: [0.95, seat - 0.115, z + dz], radius: 0.016, alu)
        }
        rod(e, from: [-0.4, seat + 0.1, z - 0.32], to: [0.6, seat + 0.1, z - 0.32], radius: 0.013, alu)
        for x: Float in [-0.4, 0.6] { rod(e, from: [x, seat - 0.11, z - 0.32], to: [x, seat + 0.1, z - 0.32], radius: 0.011, alu) }
        let strap = pbr(UIColor(white: 0.08, alpha: 1), 0.8)
        box(e, [0.05, 0.2, 0.006], strap, at: [0.42, seat - 0.21, z + 0.33])
        box(e, [0.05, 0.16, 0.006], strap, at: [0.9, seat - 0.19, z + 0.33])
        box(e, [0.06, 0.04, 0.02], pbr(UIColor(white: 0.7, alpha: 1), 0.3, metal: 1), at: [0.42, seat - 0.32, z + 0.335], corner: 0.006)
        // Undercarriage: scissor legs, base frame with castors, the floor lock.
        let legTop = seat - 0.14
        for dz: Float in [-0.24, 0.24] {
            rod(e, from: [-0.6, legTop, z + dz], to: [0.6, 0.12, z + dz], radius: 0.02, alu)
            rod(e, from: [0.6, legTop, z + dz], to: [-0.6, 0.12, z + dz], radius: 0.02, alu)
        }
        box(e, [1.4, 0.04, 0.54], black, at: [0, 0.1, z], corner: 0.01)
        for x: Float in [-0.65, 0.65] { for dz: Float in [-0.24, 0.24] {
            cyl(e, 0.035, 0.05, black, at: [x, 0.05, z + dz], axis: .z)
        } }
        box(e, [0.22, 0.06, 0.2], pbr(UIColor(red: 0.95, green: 0.78, blue: 0.1, alpha: 1), 0.5), at: [0.75, 0.04, z], corner: 0.01) // floor lock
        PitchKit.contactShadow(e, at: [0, 0, z], size: [1.6, 0.6], opacity: 0.6)
    }

    // MARK: Floor kit

    private static func floorKit(_ e: Entity) {
        // Green paramedic response bag with reflective strips, by the rear doors.
        let bag = Entity(); bag.position = [1.15, 0, -0.42]; bag.orientation = simd_quatf(angle: -0.25, axis: [0, 1, 0]); e.addChild(bag)
        let green = tinted("ambulance_vinyl", tiling: [2, 1], UIColor(red: 0.12, green: 0.4, blue: 0.22, alpha: 1), roughness: 0.9)
        box(bag, [0.55, 0.3, 0.3], green, at: [0, 0.15, 0], corner: 0.05)
        let reflect = pbr(UIColor(white: 0.85, alpha: 1), 0.2, metal: 0.6)
        box(bag, [0.56, 0.035, 0.305], reflect, at: [0, 0.2, 0], corner: 0.01)
        box(bag, [0.3, 0.035, 0.12], pbr(UIColor(white: 0.1, alpha: 1), 0.7), at: [0, 0.31, 0], corner: 0.015)
        plane(bag, [0.16, 0.16], drawn(200, 200) { r in
            UIColor(red: 0.12, green: 0.42, blue: 0.22, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(x: 80, y: 30, width: 40, height: 140)).fill()
            UIBezierPath(rect: CGRect(x: 30, y: 80, width: 140, height: 40)).fill()
        }, at: [0, 0.11, 0.152])
        PitchKit.contactShadow(bag, at: .zero, size: [0.55, 0.3])
        // Portable oxygen cylinder (white shoulder, CD size) strapped against the cabinet.
        cyl(e, 0.5, 0.05, pbr(UIColor(white: 0.97, alpha: 1), 0.3), at: [-1.5, 0.25, zB + 0.33])
        cyl(e, 0.1, 0.035, pbr(UIColor(white: 0.25, alpha: 1), 0.4), at: [-1.5, 0.55, zB + 0.33])
        box(e, [0.12, 0.03, 0.02], pbr(UIColor(red: 0.1, green: 0.55, blue: 0.25, alpha: 1), 0.6), at: [-1.5, 0.38, zB + 0.38])
        PitchKit.contactShadow(e, at: [-1.5, 0, zB + 0.33], size: [0.12, 0.12])
    }

    // MARK: Crew

    /// EMT Lena in the attendant's seat (variant switch).
    static let withEMT = false

    /// The bundled seated female avatar (origin on the floor, seat 0.371 m, faces +Z) in paramedic green.
    private static func emt(_ e: Entity, at p: SIMD3<Float>) {
        guard let model = PitchKit.model("Patient_female") else { return }
        let holder = Entity()
        holder.addChild(model)
        let size = model.visualBounds(relativeTo: holder).extents
        if size.z > size.y { model.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]) }
        let b = model.visualBounds(relativeTo: holder)
        model.position.y -= b.min.y
        if let mesh = skinned(model), var m = mesh.model {
            let green = tinted("ambulance_fabric", tiling: [8, 8], UIColor(red: 0.1, green: 0.3, blue: 0.2, alpha: 1), roughness: 1)
            if m.materials.count > 1 { m.materials[1] = green }
            mesh.model = m
        }
        holder.position = p
        e.addChild(holder)
    }

    private static func skinned(_ e: Entity) -> ModelEntity? {
        if let m = e as? ModelEntity, !m.jointNames.isEmpty { return m }
        for c in e.children { if let f = skinned(c) { return f } }
        return nil
    }

    /// Opacity map for the smoked locker fronts: a light tint with two diagonal reflection streaks.
    private static let glassOpacity: TextureResource? = {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: fmt).image { _ in
            UIColor(white: 0.38, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 256, height: 256)).fill()
            UIColor(white: 0.62, alpha: 1).setFill()
            for (x, w) in [(CGFloat(40), CGFloat(34)), (110, 12)] {
                let p = UIBezierPath(); p.move(to: CGPoint(x: x + 90, y: 0)); p.addLine(to: CGPoint(x: x + 90 + w, y: 0))
                p.addLine(to: CGPoint(x: x + w, y: 256)); p.addLine(to: CGPoint(x: x, y: 256)); p.close(); p.fill()
            }
        }
        guard let cg = img.cgImage else { return nil }
        return try? TextureResource(image: cg, options: .init(semantic: .raw))
    }()

    // MARK: Screens and pictures

    private static func vitals() -> UnlitMaterial {
        drawn(1000, 712) { r in
            UIColor.black.setFill(); UIBezierPath(rect: r).fill()
            UIColor(white: 0.2, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: r.width, height: 54)).fill()
            text("ADULT   PACED OFF   ALARMS ON", at: CGPoint(x: 18, y: 10), size: 30, weight: .semibold, color: .white)
            text("17:48", at: CGPoint(x: 890, y: 10), size: 30, weight: .semibold, color: .white)
            let green = UIColor(red: 0.2, green: 1, blue: 0.35, alpha: 1), cyan = UIColor(red: 0.2, green: 0.85, blue: 1, alpha: 1)
            let yellow = UIColor(red: 1, green: 0.88, blue: 0.2, alpha: 1), red = UIColor(red: 1, green: 0.4, blue: 0.4, alpha: 1)
            trace(in: CGRect(x: 10, y: 80, width: 620, height: 150), color: green, kind: 0, beats: 7)
            trace(in: CGRect(x: 10, y: 260, width: 620, height: 110), color: cyan, kind: 1, beats: 7)
            trace(in: CGRect(x: 10, y: 400, width: 620, height: 100), color: yellow, kind: 2, beats: 2)
            text("II  x1", at: CGPoint(x: 14, y: 66), size: 24, weight: .medium, color: green)
            func value(_ label: String, _ v: String, _ unit: String, _ c: UIColor, _ y: CGFloat, _ s: CGFloat) {
                text(label, at: CGPoint(x: 660, y: y), size: 28, weight: .semibold, color: c)
                text(v, at: CGPoint(x: 660, y: y + 18), size: s, weight: .bold, color: c)
                text(unit, at: CGPoint(x: 900, y: y + 4), size: 24, weight: .medium, color: c)
            }
            value("HR", "112", "bpm", green, 66, 136)
            value("SpO₂", "97", "%", cyan, 236, 116)
            value("RR", "22", "/min", yellow, 396, 96)
            UIColor(white: 0.3, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 530, width: r.width, height: 2)).fill()
            text("NIBP  17:46", at: CGPoint(x: 18, y: 544), size: 28, weight: .semibold, color: red)
            text("124/78", at: CGPoint(x: 18, y: 566), size: 108, weight: .bold, color: red)
            text("(93)", at: CGPoint(x: 395, y: 614), size: 44, weight: .semibold, color: red)
            text("EtCO₂", at: CGPoint(x: 660, y: 544), size: 28, weight: .semibold, color: .white)
            text("4.6", at: CGPoint(x: 660, y: 566), size: 100, weight: .bold, color: .white)
            text("kPa", at: CGPoint(x: 880, y: 590), size: 30, weight: .medium, color: .white)
        }
    }

    /// The road behind at dusk through the rear windows: violet sky to orange horizon, the road falling
    /// away with its centre line, street lamps, a following car's headlights.
    private static func rearView() -> UnlitMaterial {
        drawn(560, 500) { r in
            let ctx = UIGraphicsGetCurrentContext()!
            let horizon: CGFloat = 250
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.2, green: 0.22, blue: 0.42, alpha: 1).cgColor,
                UIColor(red: 0.62, green: 0.42, blue: 0.55, alpha: 1).cgColor,
                UIColor(red: 1.0, green: 0.62, blue: 0.32, alpha: 1).cgColor] as CFArray, locations: [0, 0.65, 1])!
            ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: horizon), options: [])
            // Tree line and hedges.
            UIColor(red: 0.1, green: 0.1, blue: 0.14, alpha: 1).setFill()
            let trees = UIBezierPath(); trees.move(to: CGPoint(x: 0, y: horizon))
            for i in 0...28 { trees.addLine(to: CGPoint(x: CGFloat(i) * 20, y: horizon - 18 - CGFloat((i * 37) % 23))) }
            trees.addLine(to: CGPoint(x: r.width, y: horizon)); trees.close(); trees.fill()
            UIColor(red: 0.16, green: 0.16, blue: 0.2, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: horizon, width: r.width, height: r.height - horizon)).fill()
            // Road, centre dashes and the edge lines converging on the vanishing point.
            let vp = CGPoint(x: 290, y: horizon + 2)
            UIColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1).setFill()
            let road = UIBezierPath(); road.move(to: vp); road.addLine(to: CGPoint(x: 600, y: r.height)); road.addLine(to: CGPoint(x: -60, y: r.height)); road.close(); road.fill()
            UIColor(white: 0.85, alpha: 1).setStroke()
            for edge in [CGFloat(-40), 580] {
                let p = UIBezierPath(); p.move(to: vp); p.addLine(to: CGPoint(x: edge, y: r.height)); p.lineWidth = 4; p.stroke()
            }
            UIColor(white: 0.95, alpha: 1).setFill()
            for i in 0..<6 {
                let t0 = pow(CGFloat(i) / 6, 2), t1 = pow((CGFloat(i) + 0.45) / 6, 2)
                let y0 = vp.y + (r.height - vp.y) * t0, y1 = vp.y + (r.height - vp.y) * t1
                let w0 = 2 + 10 * t0, w1 = 2 + 10 * t1
                let dash = UIBezierPath(); dash.move(to: CGPoint(x: vp.x - w0, y: y0)); dash.addLine(to: CGPoint(x: vp.x + w0, y: y0))
                dash.addLine(to: CGPoint(x: vp.x + w1, y: y1)); dash.addLine(to: CGPoint(x: vp.x - w1, y: y1)); dash.close(); dash.fill()
            }
            // Street lamps (warm points) and a following car's headlights with glow.
            for (x, y, s) in [(CGFloat(120), CGFloat(170), CGFloat(5)), (200, 205, 4), (420, 160, 6), (360, 200, 4)] {
                UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 1).setFill(); UIBezierPath(ovalIn: CGRect(x: x - s, y: y - s, width: 2 * s, height: 2 * s)).fill()
            }
            for hx in [CGFloat(330), 372] {
                for k in 0..<4 {
                    let s = CGFloat(22 - k * 5)
                    UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 0.18 + CGFloat(k) * 0.22).setFill()
                    UIBezierPath(ovalIn: CGRect(x: hx - s, y: 300 - s * 0.6, width: 2 * s, height: 1.2 * s)).fill()
                }
            }
            // Slight tint and reflection streak of the glass.
            UIColor(white: 1, alpha: 0.06).setFill()
            let streak = UIBezierPath(); streak.move(to: CGPoint(x: 60, y: 0)); streak.addLine(to: CGPoint(x: 140, y: 0)); streak.addLine(to: CGPoint(x: 40, y: r.height)); streak.addLine(to: CGPoint(x: -40, y: r.height)); streak.close(); streak.fill()
        }
    }

    /// Through the cab pass-through: the windscreen with the road ahead at dusk, dashboard below.
    private static func cabView() -> UnlitMaterial {
        drawn(540, 260) { r in
            let ctx = UIGraphicsGetCurrentContext()!
            let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                UIColor(red: 0.25, green: 0.27, blue: 0.45, alpha: 1).cgColor,
                UIColor(red: 0.95, green: 0.6, blue: 0.35, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 150), options: [])
            UIColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 140, width: r.width, height: 120)).fill()
            UIColor(red: 0.26, green: 0.26, blue: 0.3, alpha: 1).setFill()
            let road = UIBezierPath(); road.move(to: CGPoint(x: 262, y: 142)); road.addLine(to: CGPoint(x: 278, y: 142)); road.addLine(to: CGPoint(x: 470, y: 260)); road.addLine(to: CGPoint(x: 70, y: 260)); road.close(); road.fill()
            UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1).setFill() // tail lights ahead
            UIBezierPath(ovalIn: CGRect(x: 256, y: 150, width: 9, height: 6)).fill(); UIBezierPath(ovalIn: CGRect(x: 276, y: 150, width: 9, height: 6)).fill()
            UIColor(white: 0.06, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 0, y: 225, width: r.width, height: 35)).fill() // dashboard
            UIColor(white: 0.55, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: 266, y: 0, width: 8, height: r.height)).fill() // sliding pane edge
        }
    }

    private static func chevrons() -> UnlitMaterial {
        drawn(620, 420) { r in
            UIColor(red: 0.98, green: 0.85, blue: 0.05, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            UIColor(red: 0.85, green: 0.08, blue: 0.1, alpha: 1).setFill()
            let s: CGFloat = 90
            for i in -6..<10 {
                let x = CGFloat(i) * s * 2 - 100
                let p = UIBezierPath()
                p.move(to: CGPoint(x: x, y: r.height)); p.addLine(to: CGPoint(x: x + s, y: r.height))
                p.addLine(to: CGPoint(x: x + s + r.height * 0.9, y: 0)); p.addLine(to: CGPoint(x: x + r.height * 0.9, y: 0)); p.close(); p.fill()
            }
        }
    }

    private static func hazard() -> UnlitMaterial {
        drawn(1200, 60) { r in
            UIColor(red: 0.98, green: 0.85, blue: 0.05, alpha: 1).setFill(); UIBezierPath(rect: r).fill()
            UIColor(white: 0.08, alpha: 1).setFill()
            for i in 0..<40 {
                let x = CGFloat(i) * 60
                let p = UIBezierPath(); p.move(to: CGPoint(x: x, y: 60)); p.addLine(to: CGPoint(x: x + 30, y: 60)); p.addLine(to: CGPoint(x: x + 60, y: 0)); p.addLine(to: CGPoint(x: x + 30, y: 0)); p.close(); p.fill()
            }
        }
    }

    private static func label(_ s: String, _ c: UIColor, onWhite: Bool = false) -> UnlitMaterial {
        drawn(480, 80) { r in
            (onWhite ? UIColor.white : c).setFill(); UIBezierPath(rect: r).fill()
            if onWhite { c.setFill(); UIBezierPath(rect: CGRect(x: 0, y: 0, width: 26, height: r.height)).fill() }
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 50, weight: .heavy), .foregroundColor: onWhite ? UIColor(white: 0.15, alpha: 1) : UIColor.white]
            let sz = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: CGPoint(x: (r.width - sz.width) / 2 + (onWhite ? 13 : 0), y: (r.height - sz.height) / 2), withAttributes: attrs)
        }
    }

    private static func sign(_ s: String, bg: UIColor) -> UnlitMaterial {
        drawn(520, 100) { r in
            bg.setFill(); UIBezierPath(rect: r).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 62, weight: .heavy), .foregroundColor: UIColor.white]
            let sz = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: CGPoint(x: (r.width - sz.width) / 2, y: (r.height - sz.height) / 2), withAttributes: attrs)
        }
    }

    /// ECG (0), pleth (1) or respiration (2) trace across `rect`.
    nonisolated private static func trace(in rect: CGRect, color: UIColor, kind: Int, beats: Int) {
        let path = UIBezierPath()
        let n = 700
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n), ph = (t * CGFloat(beats)).truncatingRemainder(dividingBy: 1)
            var y: CGFloat
            switch kind {
            case 0: y = ph < 0.1 ? 0.08 * sin(ph / 0.1 * .pi) : ph < 0.16 ? 0 : ph < 0.18 ? -0.15 : ph < 0.21 ? 1 : ph < 0.24 ? -0.3 : ph < 0.3 ? 0 : ph < 0.45 ? 0.18 * sin((ph - 0.3) / 0.15 * .pi) : 0
            case 1: y = ph < 0.3 ? sin(ph / 0.3 * .pi / 2) : 0.15 * sin((ph - 0.3) / 0.15 * .pi) * (ph < 0.45 ? 1 : 0) + (1 - (ph - 0.3) / 0.7)
            default: y = 0.5 + 0.5 * sin(ph * 2 * .pi)
            }
            let k: CGFloat = kind == 0 ? 0.7 : 0.8, o: CGFloat = kind == 0 ? 0.25 : 0.1
            let pt = CGPoint(x: rect.minX + t * rect.width, y: rect.maxY - (o + k * y) * rect.height)
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

    /// PBR set with its normal/roughness maps but a flat colour.
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

    private static func wall(_ e: Entity, size: SIMD2<Float>, at p: SIMD3<Float>, yaw: Float, tint: UIColor, skip: Bool = false) {
        if skip { return } // the nearside wall is behind the wearer
        let m = ModelEntity(mesh: .generatePlane(width: size.x, height: size.y),
                            materials: [tinted("ambulance_plastic", tiling: [size.x / 1.2, size.y / 1.2], tint, roughness: 0.45)])
        m.position = p; m.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        e.addChild(m)
    }

    private static func point(_ e: Entity, at p: SIMD3<Float>, intensity: Float, radius: Float, color: UIColor) {
        let l = Entity()
        l.components.set(PointLightComponent(color: color, intensity: intensity, attenuationRadius: radius))
        l.position = p
        e.addChild(l)
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
