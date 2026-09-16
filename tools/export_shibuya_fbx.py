"""Read the supplied FBX in a separate background Blender, leaving the open scene alone."""
import bpy
import json
import numpy as np
from pathlib import Path

ROOT = Path(__file__).resolve().parent / 'source_slices'
ROOT.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=r'C:\Users\anubh\Downloads\Shibuya.fbx')
arrays, rows = {}, []
for i, obj in enumerate(o for o in bpy.context.scene.objects if o.type == 'MESH'):
    mesh = obj.data
    mesh.calc_loop_triangles()
    vertices = np.array([tuple(obj.matrix_world @ v.co) for v in mesh.vertices], dtype=np.float64)
    faces = np.array([tuple(t.vertices) for t in mesh.loop_triangles], dtype=np.int32)
    arrays[f'v{i}'], arrays[f'f{i}'] = vertices, faces
    rows.append(dict(index=i, name=obj.name, vertices=len(vertices), triangles=len(faces),
                     minimum=vertices.min(axis=0).tolist(), maximum=vertices.max(axis=0).tolist()))
np.savez_compressed(ROOT / 'fbx_raw.npz', **arrays)
(ROOT / 'fbx_summary.json').write_text(json.dumps(rows, indent=2))
print('SOURCE_EXPORT', json.dumps(rows))
