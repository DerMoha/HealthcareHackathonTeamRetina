"""Poses for the hero renders, applied to the imported avatar armatures (rest pose = the app's pose).

Blender space: the patient faces -Y, their right is -X. Directions are in armature space,
which equals world orientation while the root is unrotated (poses are applied before placing).
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_common as H
from mathutils import Vector


def guard_right_wrist(rig, sitting_bag=False):
    """Seated, cradling the injured right wrist: right forearm held across the belly, the left
    hand supporting it from underneath just behind the wrist, shoulders a little hunched, head
    turned slightly towards the learner (who stands front-right of him)."""
    # trunk: slight forward lean and protective hunch
    H.pose_rot(rig, "spine_02", (1, 0, 0), 6)
    H.pose_rot(rig, "spine_03", (1, 0, 0), 4)
    # right arm: elbow tucked at the side, forearm across the abdomen, thumb up
    w = rig.matrix_world
    e_r = H.solve_two_bone(rig, "upperarm_r", "lowerarm_r",
                           target_world=Vector((0.0, -0.23, 0.80)), pole_world=Vector((-0.45, 0.25, 0.70)))
    H.pose_aim(rig, "lowerarm_r", (H.bone_world(rig, "lowerarm_r", tail=True) - H.bone_world(rig, "lowerarm_r")), roll=-70)
    H.pose_aim(rig, "hand_r", (0.85, -0.45, -0.25), roll=-60)
    H.curl(rig, "r", 14, 6)
    # left hand under the right wrist: wrist target just below and behind the right wrist
    wr = H.bone_world(rig, "hand_r")
    H.solve_two_bone(rig, "upperarm_l", "lowerarm_l", target_world=wr + Vector((0.07, 0.02, -0.06)),
                     pole_world=Vector((0.55, 0.25, 0.55)))
    H.pose_aim(rig, "lowerarm_l", (H.bone_world(rig, "lowerarm_l", tail=True) - H.bone_world(rig, "lowerarm_l")), roll=float(os.environ.get("LROLL", "180")))
    H.pose_aim(rig, "hand_l", (-0.85, -0.35, 0.25), roll=float(os.environ.get("HROLL", "180")))
    H.curl(rig, "l", 38, 12)
    H.pose_rot(rig, "neck_01", (1, 0, 0), -4)
    H.pose_rot(rig, "head", (0, 0, 1), -14)
    H.pose_rot(rig, "head", (1, 0, 0), -5)


if __name__ == "__main__":
    # pose preview: python hero_pose.py -> .cache/out/pose_*.png
    import bpy
    H.reset(); sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"; sc.render.resolution_x = sc.render.resolution_y = 1000
    root, rig, body = H.patient("Patient")
    guard_right_wrist(rig)
    if os.environ.get("CURLTEST"):
        H.curl(rig, "l", float(os.environ["CURLTEST"]), 0)
    H.world_hdri("hospital_room_2", 1.0)
    for name, loc in (("front", (0.5, -1.6, 1.25)), ("side", (-1.5, -0.6, 1.0)), ("top", (0.3, -0.9, 1.6)), ("hands", (0.15, -0.75, 0.95))):
        H.camera(loc, (0, -0.2, 0.85) if name != "hands" else (0.0, -0.22, 0.78), lens=50)
        H.render("pose_" + name)


def stand(rig, root, arms="down", head_turn=0.0):
    """Standing bystander from the seated rest pose: legs straight, arms down (or "phone": right
    hand raised in front of the chest), root lifted so the feet are on the ground."""
    for s, out in (("l", 0.04), ("r", -0.04)):
        H.pose_aim(rig, "thigh_" + s, (out, 0.02, -1))
        H.pose_aim(rig, "calf_" + s, (0, 0.05, -1))
        H.pose_aim(rig, "foot_" + s, (0, -1, -0.45))
    for s, out in (("l", 0.18), ("r", -0.18)):
        H.pose_aim(rig, "upperarm_" + s, (out, 0.03, -1))
        H.pose_aim(rig, "lowerarm_" + s, (out * 0.6, -0.25, -1))
    if arms == "phone":
        H.pose_aim(rig, "lowerarm_r", (0.25, -0.9, 0.55))
        H.pose_aim(rig, "hand_r", (0.2, -0.9, 0.6))
        H.curl(rig, "r", 35, 10)
    if head_turn: H.pose_rot(rig, "head", (0, 0, 1), head_turn)
    feet = min(H.bone_world(rig, "foot_" + s).z for s in "lr")
    root.location.z += 0.09 - feet
    bpy_update()


def bpy_update():
    import bpy
    bpy.context.view_layer.update()


def tint_clothes(body, rgb, mix=0.8, keys=("shirt", "suit", "casual", "sportsuit")):
    """Blends the clothing albedo towards rgb (keeps some texture detail), so a reused avatar reads as a different person."""
    for slot in body.material_slots:
        m = slot.material
        if not m or not m.node_tree or not any(k in m.name.lower() for k in keys): continue
        m = slot.material = m.copy()  # the other avatar may share this material
        nt = m.node_tree; b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        link = next((l for l in nt.links if l.to_socket == b.inputs["Base Color"]), None)
        mx = nt.nodes.new("ShaderNodeMix"); mx.data_type = "RGBA"; mx.blend_type = "MIX"
        mx.inputs["Factor"].default_value = mix; mx.inputs["B"].default_value = (*rgb, 1)
        if link:
            nt.links.new(link.from_socket, mx.inputs["A"])
        else:
            mx.inputs["A"].default_value = b.inputs["Base Color"].default_value
        nt.links.new(mx.outputs["Result"], b.inputs["Base Color"])
