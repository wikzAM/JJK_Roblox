"""Offline source geometry preparation. Generated data is review-only until applied in Studio."""
from pathlib import Path
import sys, json, itertools
ROOT = Path(__file__).resolve().parent
versioned_deps = ROOT / f'python_deps_py{sys.version_info.major}{sys.version_info.minor}'
if versioned_deps.exists():
    sys.path.insert(0, str(versioned_deps))
elif sys.version_info[:2] == (3, 12):
    sys.path.insert(0, str(ROOT / 'python_deps'))
import numpy as np
from scipy.optimize import linear_sum_assignment
from scipy.spatial import cKDTree
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from shapely import LineString, Polygon, MultiLineString, union_all, polygonize_full, get_parts
DATA = ROOT / 'source_slices'

def prepare():
    raw = np.load(DATA / 'fbx_raw.npz')
    fbx = json.loads((DATA / 'fbx_summary.json').read_text())
    live = json.loads((DATA / 'live_meshes.json').read_text())
    dims = np.array([np.array(r['maximum'])-r['minimum'] for r in fbx])[:,[0,2,1]]
    live_dims = np.array([r['size'] for r in live])
    ratios = live_dims[None,:,:] / dims[:,None,:]
    costs = np.std(ratios,axis=2) / np.mean(ratios,axis=2)
    left,right = linear_sum_assignment(costs)
    src_centers = np.array([(np.array(r['maximum'])+r['minimum'])/2 for r in fbx])[:,[0,2,1]]
    dst_centers = np.array([live[j]['cf'][:3] for j in right])
    scale = float(np.median(live_dims[right]/dims))
    # Studio's imported mesh discarded some FBX extrema. Fit only complete tiles;
    # never distort each tile to its changed bbox (that would pull streets apart).
    intact = costs[left,right] < 1e-5
    assert intact.sum() >= 4, 'Insufficient intact matching source tiles'
    fits=[]
    for signs in itertools.product([-1,1],repeat=3):
        offset=np.median((dst_centers-src_centers*np.array(signs)*scale)[intact],axis=0)
        error=np.linalg.norm(src_centers*np.array(signs)*scale+offset-dst_centers,axis=1)
        fits.append((float(error[intact].max()),signs,offset))
    error,signs,offset=min(fits,key=lambda r:r[0])
    assert error < .02, f'FBX alignment is not exact: {error}'
    allv,allf=[],[]
    count=0
    for i in range(len(fbx)):
        v=raw[f'v{i}'][:,[0,2,1]]*np.array(signs)*scale+offset
        allv.append(v); allf.append(raw[f'f{i}']+count);count+=len(v)
    vertices=np.concatenate(allv);faces=np.concatenate(allf)
    samples=np.array([p for r in json.loads((DATA/'live_vertex_samples.json').read_text()) for p in r['points']])
    distances=cKDTree(vertices).query(samples)[0]
    assert np.max(distances)<.03, f'Live vertex alignment failed: {np.max(distances)} studs'
    # Global coincident-position weld only: no component size filters, no hulls.
    _,inverse=np.unique(np.round(vertices/.02).astype(np.int64),axis=0,return_inverse=True)
    e=inverse[faces]; n=int(inverse.max())+1
    graph=coo_matrix((np.ones(len(e)*3),(e.ravel(),e[:,[1,2,0]].ravel())),shape=(n,n)).tocsr()
    _,labels=connected_components(graph,directed=False)
    face_labels=labels[e[:,0]]
    triangles=vertices[faces]
    np.savez_compressed(DATA/'world_triangles.npz',triangles=triangles,component=face_labels)
    transform=dict(scale=scale,axis_order=[0,2,1],signs=signs,offset=offset.tolist(),max_intact_tile_center_error=error,intact_tiles=int(intact.sum()),
                   dimensions_relative_error=float(costs[left,right].max()),verified_vertices=len(samples),max_vertex_error=float(max(distances)),vertices=len(vertices),triangles=len(faces),components=int(face_labels.max()+1))
    (DATA/'alignment.json').write_text(json.dumps(transform,indent=2))
    print(json.dumps(transform))
    return triangles,face_labels

def sections(triangles,y,weld=.35,seam=4):
    tri=triangles[(triangles[:,:,1].min(axis=1)<y)&(triangles[:,:,1].max(axis=1)>y)]
    segments=[]
    for t in tri:
        points=[]
        for a,b in zip(t,t[[1,2,0]]):
            if (a[1]>y)!=(b[1]>y):
                p=a+(b-a)*((y-a[1])/(b[1]-a[1]));points.append(p[[0,2]])
        if len(points)==2 and np.linalg.norm(points[1]-points[0])>.001:
            segments.append(points)
    if weld and segments:
        points=np.asarray(segments).reshape(-1,2)
        pairs=cKDTree(points).query_pairs(weld,output_type='ndarray')
        graph=coo_matrix((np.ones(len(pairs)),(pairs[:,0],pairs[:,1])),shape=(len(points),len(points))).tocsr()
        count,labels=connected_components(graph,directed=False)
        sizes=np.bincount(labels)
        centers=np.stack([np.bincount(labels,weights=points[:,i])/sizes for i in range(2)],axis=1)
        segments=centers[labels].reshape(-1,2,2)
    # GEOS nodes crossings, collinear overlaps and T-junctions before polygonizing.
    lines=union_all([LineString(s) for s in segments],grid_size=.05)
    # Only short mutually nearest open endpoints can bridge source export seams.
    # Closed buildings cannot be joined by this step. Keep repair length visible.
    repairs=[]
    if seam:
        # union_all can emit empty parts at this grid size; line.coords[0] then
        # raises IndexError and kills the whole run. Seen on 6_4510_4915_-8852.
        parts=[line for line in get_parts(lines) if not line.is_empty and len(line.coords)>=2]
        endpoints=np.array([p for line in parts for p in [line.coords[0],line.coords[-1]]]
                           ) if parts else np.empty((0,2))
        unique,counts=(np.unique(endpoints,axis=0,return_counts=True)
                       if len(endpoints) else (np.empty((0,2)),np.empty(0,dtype=int)))
        loose=unique[counts==1] if len(unique) else unique
        if len(loose)>1:
            distance,neighbor=cKDTree(loose).query(loose,k=2)
            for i in range(len(loose)):
                j=neighbor[i,1]
                if i<j and neighbor[j,1]==i and distance[i,1]<=seam:
                    repairs.append(LineString([loose[i],loose[j]]))
        if repairs: lines=union_all([lines,*repairs],grid_size=.05)
    polygons,cuts,dangles,invalid=polygonize_full(list(get_parts(lines)))
    return list(get_parts(polygons)),dict(segments=len(segments),closed=len(polygons.geoms),seam_count=len(repairs),seam_length=sum(p.length for p in repairs),cut_length=cuts.length,dangle_length=dangles.length,invalid=len(invalid.geoms)),segments

if __name__=='__main__':
    triangles,labels=prepare()
    for y in [80.123,120.123,200.123,400.123,600.123]:
        polygons,stats,_=sections(triangles,y)
        stats['large']=sum(p.area>=150 for p in polygons);stats['y']=y
        print(json.dumps(stats),flush=True)
