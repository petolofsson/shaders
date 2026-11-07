"""Fixed-work affine motion reference: two guides, six moment updates, no features."""
import numpy as np

GRID_X=24
GRID_Y=16
LEVELS=(16,8)
ITERATIONS=3
REGULARIZATION=1e-4
MAX_STEP=6.
MAX_DISPLACEMENT=19.

def det3(A):
    return np.dot(A[0],np.cross(A[1],A[2]))

def inverse3(A):
    columns=np.stack((np.cross(A[1],A[2]),np.cross(A[2],A[0]),np.cross(A[0],A[1])),axis=1)
    return columns/np.maximum(det3(A),np.asarray(1e-20,dtype=A.dtype))

def solve6(normal,rhs):
    """Two 3x3 inverses and a Schur complement; directly expressible in HLSL."""
    normalizer=np.maximum(np.trace(normal)/6,np.asarray(1e-8,dtype=normal.dtype))
    A=normal/normalizer+np.eye(6,dtype=normal.dtype)*REGULARIZATION
    b=rhs/normalizer
    upper=A[:3,:3];cross=A[:3,3:];lower=A[3:,3:]
    inv_upper=inverse3(upper)
    schur=lower-cross.T@inv_upper@cross
    y=inverse3(schur)@(b[3:]-cross.T@inv_upper@b[:3])
    x=inv_upper@(b[:3]-cross@y)
    quality=det3(upper)*det3(schur)
    return np.concatenate((x,y)),float(quality)

def guide(image,scale):
    h,w=image.shape
    assert h%scale==0 and w%scale==0
    return image.reshape(h//scale,scale,w//scale,scale).mean(axis=(1,3))

def sample(image,x,y):
    h,w=image.shape
    inside=(x>=0)&(y>=0)&(x<w-1)&(y<h-1)
    x=np.clip(x,0,w-1);y=np.clip(y,0,h-1)
    x0=np.floor(x).astype(int);y0=np.floor(y).astype(int)
    x1=np.minimum(x0+1,w-1);y1=np.minimum(y0+1,h-1)
    tx=x-x0;ty=y-y0
    value=(1-ty)*((1-tx)*image[y0,x0]+tx*image[y0,x1])+ty*((1-tx)*image[y1,x0]+tx*image[y1,x1])
    return value,inside

def affine_matrix(parameters,width,height):
    q=np.array([[2/width,0,1/width-1],[0,2/height,1/height-1],[0,0,1.]])
    H=np.eye(3);H[:2]+=parameters@q
    return H

def fit(current,history,precision=np.float64):
    h,w=current.shape
    yy,xx=np.meshgrid((np.arange(GRID_Y)+.5)*h/GRID_Y-.5,
                      (np.arange(GRID_X)+.5)*w/GRID_X-.5,indexing='ij')
    x,y=xx.ravel().astype(precision),yy.ravel().astype(precision)
    q=np.column_stack(((2*x+1)/w-1,(2*y+1)/h-1,np.ones_like(x))).astype(precision)
    parameters=np.zeros((2,3),dtype=precision)
    corners=np.array([[-1.,-1.,1],[1,-1,1],[-1,1,1],[1,1,1]],dtype=precision)
    records=[]
    for scale in LEVELS:
        a=guide(current,scale).astype(precision);b=guide(history,scale).astype(precision)
        cx,cy=(x+.5)/scale-.5,(y+.5)/scale-.5
        reference,_=sample(a,cx,cy)
        for _ in range(ITERATIONS):
            delta=q@parameters.T
            sx,sy=(x+delta[:,0]+.5)/scale-.5,(y+delta[:,1]+.5)/scale-.5
            value,inside=sample(b,sx,sy)
            plus_x,_=sample(b,sx+1,sy);minus_x,_=sample(b,sx-1,sy)
            plus_y,_=sample(b,sx,sy+1);minus_y,_=sample(b,sx,sy-1)
            gx=(plus_x-minus_x)/(2*scale);gy=(plus_y-minus_y)/(2*scale)
            residual=value-reference
            J=np.column_stack((gx[:,None]*q,gy[:,None]*q)).astype(precision)
            weight=(inside/np.sqrt(1+(residual/2)**2)).astype(precision)
            normal=(J.T@(J*weight[:,None]))/len(x)
            rhs=-(J.T@(weight*residual))/len(x)
            update,quality=solve6(normal,rhs)
            step=update.reshape(2,3)
            maximum=float(np.linalg.norm(corners@step.T,axis=1).max())
            step*=min(1.,MAX_STEP/max(maximum,1e-20))
            parameters+=step
            records.append({'scale':scale,'quality':quality,'trace':float(np.trace(normal)),
                            'rms_before':float(np.sqrt(np.sum(inside*residual**2)/max(inside.sum(),1))),
                            'uncapped_step_pixels':maximum})
    delta=q@parameters.T
    value,inside=sample(b,(x+delta[:,0]+.5)/scale-.5,(y+delta[:,1]+.5)/scale-.5)
    rms=float(np.sqrt(np.sum(inside*(value-reference)**2)/max(inside.sum(),1)))
    displacement=float(np.linalg.norm(corners@parameters.T,axis=1).max())
    H=affine_matrix(parameters,w,h)
    valid=bool(np.isfinite(H).all() and records[-1]['quality']>1e-6 and records[-1]['trace']>1e-6
               and rms<=2 and displacement<=MAX_DISPLACEMENT and inside.mean()>=.75)
    return H,{'valid':valid,'rms':rms,'max_corner_displacement':displacement,
              'normal_quality':records[-1]['quality'],'normal_trace':records[-1]['trace'],
              'grid':[GRID_X,GRID_Y],'updates':len(records),'records':records,'homography':H.tolist()}

def compose(index,history_index,pairs):
    H=np.eye(3);valid=True
    for i in range(index,history_index,-1):
        step,info=pairs(i)
        H=step@H
        valid=valid and info['valid']
    return H,valid

def supported_correction(source,estimate,count,forward):
    """Ablation: preserve the weighted mean while fading unsupported enhancement."""
    def smooth(a,b,value):
        t=np.clip((value-a)/(b-a),0,1)
        return t*t*(3-2*t)
    baseline=forward(source)
    support=smooth(1,4,count)
    gate=smooth(4,12,source)*(1-smooth(64,96,source))*support
    missing=estimate-forward(estimate)
    pivot=float(np.sum(gate*missing)/max(gate.sum(),1e-20))
    delta=.5*gate*(missing-pivot)
    scale=min(1,2/max(abs(delta).max(),1e-20))
    positive=delta>0;negative=delta<0
    if positive.any():scale=min(scale,float(np.min((255-baseline[positive])/delta[positive])))
    if negative.any():scale=min(scale,float(np.min(baseline[negative]/-delta[negative])))
    delta*=max(scale,0)
    return baseline+delta,{'mean_code_change':float(delta.mean()),'max_code_change':float(abs(delta).max()),
                           'budget_scale':float(scale),'mean_support':float(support.mean())}
