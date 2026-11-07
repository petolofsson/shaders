#!/usr/bin/env python3
"""Build exact matched RGB8 noise variants from the rendered clean source."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
import numpy as np
from PIL import Image
import geometry as g

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def blur(image):
    for _ in range(16):
        for axis in (0,1):image=(np.roll(image,1,axis)+2*image+np.roll(image,-1,axis))/4
    return image/image.std()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args();source=args.source.resolve();out=args.output.resolve()
    manifest=json.loads((source/'manifest.json').read_text())
    assert manifest['status']=='complete' and len(manifest['frames'])>=4
    out.mkdir(parents=True,exist_ok=False)
    height,width=manifest['resolution'][1],manifest['resolution'][0]
    screen=blur(np.random.default_rng(6110611).normal(size=(height,width)))
    surfaces={key:blur(np.random.default_rng(6110700+key).normal(size=(256,256))) for key in range(1,9)}
    report={'scope':'RGB8 source fixtures; common code-channel perturbation, clipped/rounded before evaluation',
            'source_manifest_sha256':digest(source/'manifest.json'),'source':str(source),
            'source_fps':manifest['source_fps'],'source_clock':manifest.get('source_clock','legacy_route60'),
            'variants':['clean','changing','screen_fixed','surface_fixed'],'frames':[],
            'noise_model':'unit nominal code std; sixteen-binomial-blur grain; no per-frame grain normalization'}
    yy,xx=np.indices((height,width))
    for index,pair in enumerate(manifest['frames']):
        clean_path=Path(pair['clean']['image']);surface_path=Path(pair['surface']['image'])
        assert digest(clean_path)==pair['clean']['sha256'] and digest(surface_path)==pair['surface']['sha256']
        rgb=np.asarray(Image.open(clean_path).convert('RGB'))
        ids=g.labels(np.asarray(Image.open(surface_path).convert('RGB')))
        assert np.all(ids[:-4]<255)
        visible=(ids>0)&(ids<=8);visible[-4:]=False
        surface=np.zeros((height,width))
        for key,obj in g.object_map(pair['clean']['pose']).items():
            use=visible&(ids==key)
            if not use.any():continue
            H=g.fit(np.asarray(obj['corners'])[:,:2],np.array([[0.,0.],[255,0],[255,255],[0,255]]))
            uv=g.project(np.column_stack((xx[use]+.5,yy[use]+.5)),H)
            values,_,_=g.bilinear(surfaces[key],uv[:,0],uv[:,1]);surface[use]=values
        time=pair['clean']['pose'].get('sourceTimeSeconds',pair['clean']['frame']/60)
        reference_index=round(time*30)
        # Share independent noise at exact common 30-fps times across rate runs.
        # Extra high-rate updates receive distinct seeds; no duplicated noise frames.
        noise_seed=6111000+(reference_index if abs(time*30-reference_index)<1e-8 else 10000000+index)
        fields={'changing':np.random.default_rng(noise_seed).normal(size=(height,width)),
                'screen_fixed':screen,'surface_fixed':surface}
        entry={'index':index,'route_frame':pair['clean']['frame'],'source_time_seconds':time,'changing_noise_seed':noise_seed,'phase':pair['clean']['pose']['phase'],'images':{}}
        for variant in report['variants']:
            folder=out/variant;folder.mkdir(exist_ok=True);path=folder/f'{index:04d}.png'
            if variant=='clean':shutil.copyfile(clean_path,path)
            else:
                n=fields[variant]*visible
                noisy=np.uint8(np.rint(np.clip(rgb.astype(float)+n[...,None],0,255)))
                assert np.array_equal(noisy[-4:],rgb[-4:])
                Image.fromarray(noisy).save(path)
            entry['images'][variant]={'path':str(path),'sha256':digest(path)}
        report['frames'].append(entry)
        if index%16==0 or index==len(manifest['frames'])-1:print(f'Matched RGB source variants {index+1}/{len(manifest["frames"])}',flush=True)
    (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(out/'manifest.json')

if __name__=='__main__':main()
