#!/usr/bin/env python3
"""Verify rendered source, physical pixel centers and controlled RGB fixtures."""
import argparse
import json
import hashlib
from pathlib import Path
import numpy as np
from PIL import Image
import geometry as g

ROOT=Path(__file__).resolve().parents[2]

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--inputs',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();assert not args.output.exists()
    source=json.loads((args.source/'manifest.json').read_text());inputs=json.loads((args.inputs/'manifest.json').read_text())
    count=len(source.get('source_times_seconds',source['frames']))
    assert source['status']=='complete' and len(source['frames'])==count
    assert source['production_before']==source['production_after']
    assert all(digest(ROOT/p)==h for p,h in source['production_before'].items())
    assert digest(args.source/'manifest.json')==inputs['source_manifest_sha256']
    expected=list(range(count)) if source.get('source_clock')=='timestamped_index' else list(range(0,192,2))
    assert [f['clean']['frame'] for f in source['frames']]==expected
    assert source['first_repeat']['scene_sha256']==source['frames'][0]['clean']['scene_sha256']
    phases={};visible_calibrations=0;occluded=[]
    for index,pair in enumerate(source['frames']):
        for variant in ('clean','surface'):assert digest(pair[variant]['image'])==pair[variant]['sha256']
        assert pair['clean']['pose']['viewProjection']==pair['surface']['pose']['viewProjection']
        assert pair['clean']['pose']['objects']==pair['surface']['pose']['objects']
        rgb=np.asarray(Image.open(pair['clean']['image']).convert('RGB'))
        ids=g.labels(np.asarray(Image.open(pair['surface']['image']).convert('RGB')))
        assert np.all(ids[:-4]<=8)
        phase=pair['clean']['pose']['phase'];phases.setdefault(phase,[]).append(pair['clean']['scene_sha256'])
        for obj in pair['clean']['pose']['objects']:
            if obj['id'] not in (6,7,8):continue
            x,y=np.rint(np.asarray(obj['corners'])[:,:2].mean(axis=0)).astype(int)
            if ids[y,x]!=obj['id']:
                occluded.append({'index':index,'surface':obj['id'],'observed_owner':int(ids[y,x])});continue
            assert np.all(rgb[y,x]=={6:0,7:3,8:8}[obj['id']]);visible_calibrations+=1
        for variant in inputs['variants']:
            record=inputs['frames'][index]['images'][variant];assert digest(record['path'])==record['sha256']
            noisy=np.asarray(Image.open(record['path']).convert('RGB'))
            assert np.array_equal(noisy[-4:],rgb[-4:])
    assert len(set(phases['stationary']))==1
    assert all(len(set(v))==len(v) for k,v in phases.items() if k!='stationary')
    # Independent physical-center and zero-weight visibility controls.
    h,w=6,8;labels=np.ones((h,w),dtype=np.uint8);labels[:,4:]=2
    quad=np.array([[0.,0.],[8,0],[8,6],[0,6]])
    pose={'objects':[{'id':i,'corners':np.column_stack((quad,np.zeros(4))).tolist()} for i in (1,2)]}
    sx,sy,supported,_=g.oracle_maps(pose,pose,labels,labels,(0,0))
    yy,xx=np.indices((h,w));assert abs(sx-xx).max()<1e-11 and abs(sy-yy).max()<1e-11
    assert supported[1:-1,3].all() # Other-surface taps with zero weight must not reject.
    prior={'objects':[{'id':i,'corners':np.column_stack((quad*np.array([2,1])+np.array([1.25,0]),np.zeros(4))).tolist()} for i in (1,2)]}
    sx,sy,_,_=g.oracle_maps(pose,prior,labels,labels,(0,0))
    center_error=float(abs(sx-(2*xx+1.75)).max());assert center_error<1e-11
    # Actual shader texture projection versus RGB8 source, independent of the matcher.
    prediction=[]
    times=np.array(source.get('source_times_seconds',[f['clean']['frame']/60 for f in source['frames']]))
    selected=sorted(set(min(count-1,int(np.searchsorted(times,t))) for t in (0,40/30,56/30,72/30,80/30,times[-1])))
    for index in selected:
        pair=source['frames'][index]
        rgb=np.asarray(Image.open(pair['clean']['image']).convert('RGB'))
        ids=g.labels(np.asarray(Image.open(pair['surface']['image']).convert('RGB')))
        yy,xx=np.indices(ids.shape)
        for obj in pair['clean']['pose']['objects']:
            if obj['id'] not in (1,2):continue
            use=(ids==obj['id'])&(xx%8==0)&(yy%8==0)
            H=g.fit(np.asarray(obj['corners'])[:,:2],np.array([[0.,0.],[1,0],[1,1],[0,1]]))
            uv=g.project(np.column_stack((xx[use]+.5,yy[use]+.5)),H)
            texture=np.asarray(Image.open(args.source/'client/assets'/f'{obj["asset"]}.png').convert('RGB'),dtype=float)
            th,tw=texture.shape[:2];sample,valid,_=g.bilinear(texture,uv[:,0]*tw-.5,uv[:,1]*th-.5)
            expected=255*g.encode(g.decode(sample/255)*pair['clean']['pose']['lighting'])
            error=abs(expected[valid]-rgb[use][valid]);p99=float(np.quantile(error,.99))
            assert p99<.55
            prediction.append({'index':index,'surface':obj['id'],'samples':int(valid.sum()),'p99_code_error':p99})
    report={'scope':'source/fixture verification, not shader effectiveness or GPU-history phase validation',
            'production_unchanged':17,'source_pairs_verified':count,'input_rgb_images_verified':count*4,
            'visible_exact_calibration_centers':visible_calibrations,'occluded_calibration_centers':occluded,
            'phase_unique_scene_counts':{k:[len(v),len(set(v))] for k,v in phases.items()},
            'physical_center_control_max_error':center_error,'zero_weight_visibility_pass':True,
            'actual_texture_prediction':prediction,'first_repeat_exact':True}
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('actual_texture_prediction','occluded_calibration_centers')},indent=2))

if __name__=='__main__':main()
