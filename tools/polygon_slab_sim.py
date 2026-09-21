"""Offline replica of src/server/PolygonSlab.luau's triangulator.

The Luau builder only accepts a floor outline it can tile with native Parts and
WedgeParts, and it decides that with a backtracking ear clipper that gives up
after 2048 search states. When it gives up it raises "No exact native-size
triangulation (0.05 stud minimum; 2048 search states)", which reads like a
degenerate-geometry problem and is not: the outlines that fail have minimum edge
0.92-2.06 studs and minimum angle 47-68 degrees. They are simply too intricate
for the search budget.

This module is that same algorithm in Python, so the plan builder can ask "will
PolygonSlab accept this ring?" before emitting it, instead of discovering the
answer in Studio. It reproduces the live failures exactly: on plans_v5 it flags
fbx_poly_130_14, fbx_poly_170_2 and fbx_poly_250_79 -- precisely the three that
failed to build in the real builder.

Keep in step with PolygonSlab.luau. buildable(points) -> (ok, attempts).
"""
import math

MAIN = [(-70.816,-67.620),(-70.816,67.620),(70.816,67.620),(70.816,-67.620)]
SETBACK = [(-62.616,-20.011),(-62.672,10.861),(-69.097,10.805),(-69.127,65.921),
           (69.163,65.949),(69.023,13.722),(38.803,14.192),(38.866,-66.003),
           (-69.043,-65.953),(-69.060,-20.021)]
YAW = -2.766790
ORIGIN_X, ORIGIN_Z = 771.455, -595.699
MIN_SIZE = 0.05

def sub(a,b): return (a[0]-b[0], a[1]-b[1])
def add(a,b): return (a[0]+b[0], a[1]+b[1])
def mul(a,s): return (a[0]*s, a[1]*s)
def cross(a,b): return a[0]*b[1]-a[1]*b[0]
def dot(a,b): return a[0]*b[0]+a[1]*b[1]
def mag(a): return math.hypot(a[0],a[1])
def turn(a,b,c): return cross(sub(b,a), sub(c,a))

def tolerances(pts):
    lo=(min(p[0] for p in pts), min(p[1] for p in pts))
    hi=(max(p[0] for p in pts), max(p[1] for p in pts))
    scale=max(1.0, mag(sub(hi,lo)))
    return 1e-7*scale, 1e-7*scale*scale

def signed_area(pts):
    o=pts[0]; t=0.0
    for i,p in enumerate(pts):
        t+=cross(sub(p,o), sub(pts[(i+1)%len(pts)],o))
    return t/2

def validate(pts):
    pts=list(pts)
    leps,aeps=tolerances(pts)
    out=[]
    for p in pts:
        if not out or mag(sub(p,out[-1]))>leps: out.append(p)
    if len(out)>1 and mag(sub(out[0],out[-1]))<=leps: out.pop()
    changed=True
    while changed and len(out)>=3:
        changed=False
        for i,b in enumerate(out):
            a=out[(i-1)%len(out)]; c=out[(i+1)%len(out)]
            if abs(turn(a,b,c))<=aeps:
                out.pop(i); changed=True; break
    if signed_area(out)<0: out=out[::-1]
    return out

def in_triangle(p,a,b,c,eps):
    return turn(a,b,p)>=-eps and turn(b,c,p)>=-eps and turn(c,a,p)>=-eps

# --- PolygonSlab.trianglePieces, returning wedge BOX corner sets (local XZ) ---
def triangle_pieces(tri, eps, allow_split=True):
    """Return list of boxes; each box = list of 4 local XZ corners of the WedgePart's
    full Size box (the rectangle spanned by the two legs)."""
    # right-triangle case
    for i in range(3):
        r=tri[i]; u=sub(tri[(i+1)%3],r); v=sub(tri[(i+2)%3],r)
        rt=min(eps, mag(u)*mag(v)*1e-7)
        if abs(dot(u,v))<=rt and mag(u)>=MIN_SIZE and mag(v)>=MIN_SIZE:
            return [[r, add(r,u), add(r,v), add(add(r,u),v)]], 0
    best=None
    for i in range(3):
        a,b,c=tri[i],tri[(i+1)%3],tri[(i+2)%3]
        edge=sub(c,b); depth=mag(edge)
        if depth==0: continue
        back=mul(edge,1.0/depth)
        left=dot(sub(a,b),back)
        altitude=sub(sub(a,b), mul(back,left))
        height=mag(altitude)
        margin=min(height,left,depth-left)
        if margin>=MIN_SIZE and (best is None or margin>best['margin']):
            best=dict(a=a,b=b,c=c,depth=depth,back=back,left=left,alt=altitude,height=height,margin=margin)
    if best:
        a,b,c=best['a'],best['b'],best['c']
        foot=add(b, mul(best['back'], best['left']))
        # wedge 1: legs foot->a (altitude) and foot->b ; box corners
        box1=[foot, a, b, add(a, sub(b,foot))]
        box2=[foot, a, c, add(a, sub(c,foot))]
        return [box1,box2], 0
    if allow_split:
        a,b,c=tri
        ab=mag(sub(a,b)); ac=mag(sub(a,c)); bc=mag(sub(b,c))
        per=ab+ac+bc
        radius=abs(turn(a,b,c))/per
        if radius>=MIN_SIZE:
            center=add(a, add(mul(sub(b,a), ac/per), mul(sub(c,a), ab/per)))
            out=[]
            for i in range(3):
                r=triangle_pieces([center,tri[i],tri[(i+1)%3]], eps, False)
                if r is None: return None
                out.extend(r[0])
            return out,1
    return None

def triangulate(points, eps, limit=None):
    cache={}
    failed=set()
    attempts=[0]
    if limit is None:
        limit=2048 if len(points)<=64 else 512
    def pieces_for(a,b,c):
        key=(a,b,c)
        if key not in cache:
            r=triangle_pieces([points[a],points[b],points[c]], eps, True)
            cache[key]= r if r else False
        return cache[key]
    def solve(indices):
        attempts[0]+=1
        if attempts[0]>limit: return None
        key=tuple(indices)
        if key in failed: return None
        if len(indices)==3:
            a,b,c=indices
            if turn(points[a],points[b],points[c])<=eps: failed.add(key); return None
            p=pieces_for(a,b,c)
            if not p: failed.add(key); return None
            return list(p[0])
        ears=[]
        for i,b in enumerate(indices):
            a=indices[(i-1)%len(indices)]; c=indices[(i+1)%len(indices)]
            area=turn(points[a],points[b],points[c])
            if area>eps:
                blocked=False
                for j in indices:
                    if j not in (a,b,c) and in_triangle(points[j],points[a],points[b],points[c],eps):
                        blocked=True; break
                if not blocked:
                    p=pieces_for(a,b,c)
                    if p: ears.append((i,a,b,c,area,p))
        ears.sort(key=lambda e: (len(e[5][0]), -e[4], e[0]))
        for (i,a,b,c,area,p) in ears:
            rem=list(indices); rem.pop(i)
            res=solve(rem)
            if res is not None:
                res.extend(p[0])
                return res
            if attempts[0]>=limit: break
        failed.add(key)
        return None
    res=solve(list(range(len(points))))
    assert res is not None, "no triangulation"
    return res, attempts[0]

def is_rectangle(pts, eps):
    if len(pts)!=4: return False
    for i in range(4):
        a,b,c=pts[i],pts[(i+1)%4],pts[(i+2)%4]
        if abs(dot(sub(b,a),sub(c,b)))>eps: return False
    return True

def world_aabb(local_pts):
    cy, sy = math.cos(YAW), math.sin(YAW)
    xs=[]; zs=[]
    for (x,z) in local_pts:
        # CFrame.Angles(0,yaw,0): world = origin + R*(x,0,z)
        wx = ORIGIN_X + cy*x + sy*z
        wz = ORIGIN_Z - sy*x + cy*z
        xs.append(wx); zs.append(wz)
    return min(xs),max(xs),min(zs),max(zs)



def buildable(points, eps=None, limit=None):
    """Would PolygonSlab.Build accept this ring? (ok, search states used)

    `limit` caps the backtracking search. The Luau original allows 2048 states,
    but this replica is pure Python and roughly two orders slower, so running the
    full budget on every ring that cannot be tiled stalls a whole batch. A lower
    cap only ever turns a slow "yes" into a "no", and the caller's response to a
    "no" is to simplify one step -- a small, bounded loss of fidelity rather than
    a wrong answer.
    """
    try:
        pts = validate(points)
    except Exception:
        return False, 0
    if eps is None:
        _, eps = tolerances(pts)
    if is_rectangle(pts, eps):
        return True, 0
    try:
        _, attempts = triangulate(pts, eps, limit=limit)
        return True, attempts
    except AssertionError:
        return False, -1
