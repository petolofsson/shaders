"""Projection/visibility helpers for diagnostics, never RGB motion-estimator inputs."""
import numpy as np

W=np.array([.2126,.7152,.0722])

def encode(x):
    x=np.maximum(x,0)
    return np.where(x<=.0031308,12.92*x,1.055*x**(1/2.4)-.055)

def decode(x):
    return np.where(x<=.04045,x/12.92,((x+.055)/1.055)**2.4)

def code_y(rgb):
    return 255*encode(decode(rgb.astype(float)/255)@W)

def project(points,H):
    z=np.column_stack((points,np.ones(len(points))))@H.T
    return z[:,:2]/z[:,2,None]

def fit(a,b):
    def norm(p):
        center=p.mean(axis=0);scale=np.sqrt(2)/np.sqrt(np.mean(np.sum((p-center)**2,axis=1)))
        T=np.array([[scale,0,-scale*center[0]],[0,scale,-scale*center[1]],[0,0,1.]])
        return project(p,T),T
    p,A=norm(np.asarray(a));q,B=norm(np.asarray(b))
    x,y=p.T;u,v=q.T;z=np.zeros_like(x);one=np.ones_like(x)
    rows=np.stack((np.column_stack((-x,-y,-one,z,z,z,u*x,u*y,u)),
                   np.column_stack((z,z,z,-x,-y,-one,v*x,v*y,v))),axis=1).reshape(-1,9)
    _,_,V=np.linalg.svd(rows,full_matrices=True)
    H=np.linalg.solve(B,V[-1].reshape(3,3))@A
    return H/H[2,2]

def labels(rgb):
    ids=np.rint(rgb[...,0].astype(float)/16).astype(np.uint8)
    valid=(abs(rgb[...,0].astype(float)-ids*16)<=1)&(rgb[...,1]<=1)&(rgb[...,2]<=1)&(ids<=8)
    return np.where(valid,ids,255).astype(np.uint8)

def bilinear(image,x,y):
    h,w=image.shape[:2]
    inside=np.isfinite(x)&np.isfinite(y)&(x>=0)&(y>=0)&(x<w-1)&(y<h-1)
    x=np.nan_to_num(np.clip(x,0,w-1));y=np.nan_to_num(np.clip(y,0,h-1))
    x0=np.floor(x).astype(int);y0=np.floor(y).astype(int)
    x1=np.minimum(x0+1,w-1);y1=np.minimum(y0+1,h-1)
    tx=x-x0;ty=y-y0
    if image.ndim==3:tx=tx[...,None];ty=ty[...,None]
    value=(1-ty)*((1-tx)*image[y0,x0]+tx*image[y0,x1])+ty*((1-tx)*image[y1,x0]+tx*image[y1,x1])
    return value,inside,(y0,x0,y1,x1)

def object_map(pose):return {o['id']:o for o in pose['objects']}

def oracle_maps(current_pose,history_pose,current_ids,history_ids,origin):
    """Known visible-surface mapping, same +/-19 range as the tested RGB model."""
    h,w=current_ids.shape
    yy,xx=np.indices((h,w))
    sx=xx.astype(float);sy=yy.astype(float)
    supported=np.zeros((h,w),dtype=bool)
    inside_context=np.zeros_like(supported)
    current,history=object_map(current_pose),object_map(history_pose)
    origin=np.asarray(origin)
    for key,obj in current.items():
        use=current_ids==key
        if not use.any():continue
        a=np.asarray(obj['corners'])[:,:2]-origin
        b=np.asarray(history[key]['corners'])[:,:2]-origin
        H=fit(a,b)
        p=project(np.column_stack((xx[use]+.5,yy[use]+.5)),H)
        sx[use],sy[use]=p[:,0]-.5,p[:,1]-.5
    _,inside,indices=bilinear(history_ids,sx,sy)
    y0,x0,y1,x1=indices
    tx=np.clip(sx,0,w-1)-x0;ty=np.clip(sy,0,h-1)-y0
    same=((history_ids[y0,x0]==current_ids)|((1-tx)*(1-ty)<=1e-6))
    same&=((history_ids[y0,x1]==current_ids)|(tx*(1-ty)<=1e-6))
    same&=((history_ids[y1,x0]==current_ids)|((1-tx)*ty<=1e-6))
    same&=((history_ids[y1,x1]==current_ids)|(tx*ty<=1e-6))
    nonbackground=(current_ids>0)&(current_ids<=8)
    in_range=(abs(sx-xx)<=19)&(abs(sy-yy)<=19)
    inside_context=inside&in_range&nonbackground
    supported=inside_context&same
    return sx,sy,supported,inside_context
