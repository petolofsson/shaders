#!/usr/bin/env python3
"""Export the isolated temporal course via the existing private Babylon backend."""
import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CLIENT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tools/babylon_scene'))
import run as original
import background

WIDTH,HEIGHT=1280,720

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def encode(x):
    x=np.maximum(x,0)
    return np.where(x<=.0031308,12.92*x,1.055*x**(1/2.4)-.055)

def timeline(fps,cadence,duration=3.2):
    if cadence=='constant':return [i/fps for i in range(int(np.ceil(duration*fps)))]
    times=[0.]
    rates=(80,100,110,90,105)
    while True:
        next_time=times[-1]+1/rates[(len(times)-1)%len(rates)]
        if next_time>=duration:break
        times.append(next_time)
    return times

def prepare(out,times,fps):
    client=out/'client';assets=client/'assets';assets.mkdir(parents=True)
    for name in ('index.html','scene.js'):shutil.copyfile(CLIENT/name,client/name)
    (client/'config.js').write_text('window.TEMPORAL_CONFIG='+json.dumps({'sourceTimes':times,'sourceFps':fps})+';\n')
    report={'source_files':{name:digest(CLIENT/name) for name in ('index.html','scene.js','export.py')},'inputs':{},'assets':{},'asset_source_rectangles':{}}
    parent=ROOT/'captures/shadow_dense_material_20261106'
    meta=json.loads((parent/'report.json').read_text())
    for key,asset in [('held_timber','timber'),('metal','metal')]:
        path=parent/f'{key}_0/values.npy'
        assert digest(path)==meta['cases'][key]['captures']['0']['values_sha256']
        report['inputs'][str(path.relative_to(ROOT))]=digest(path)
        rgb=np.load(path).astype(float)[:,:,0]
        rect=(96,96,416,352) if key=='held_timber' else (100,108,438,408)
        x0,y0,x1,y1=rect
        rgb=rgb[y0:y1,x0:x1]
        report['asset_source_rectangles'][asset]=list(rect)
        Image.fromarray(np.uint8(np.rint(np.clip(encode(rgb),0,1)*255))).save(assets/f'{asset}.png')
    y,x=np.indices((256,256))
    code=16+3*np.sin(2*np.pi*x/128)+2*np.cos(2*np.pi*y/96)+.6*np.sin(2*np.pi*x/4)*np.cos(2*np.pi*y/4)
    cloth=np.stack((code*1.05,code,code*.93),axis=2)
    Image.fromarray(np.uint8(np.rint(np.clip(cloth,0,255)))).save(assets/'cloth.png')
    for name,color in [('black',(0,0,0)),('near_black',(3,3,3)),('code_eight',(8,8,8)),('light',(180,160,110))]:
        Image.new('RGB',(16,16),color).save(assets/f'{name}.png')
    report['assets']={p.name:digest(p) for p in assets.glob('*.png')}
    report['production_before']={p:digest(ROOT/p) for p in meta['initial_hashes']}
    assert report['production_before']==meta['initial_hashes']
    return client,report

class Browser(background.SourceBrowser):
    def capture_mode(self,frame,mode,output):
        self.token+=1
        token=self.token
        with self.server.control_lock:self.server.controls[self.run_id]={'frame':frame,'token':token,'mode':mode}
        event=self.wait_event(self.events,self.lock,self.run_id,'pose',self.display.process,30,
                              lambda e:e.get('frame')==frame and e.get('token')==token)
        for _ in range(5):
            self.display.screenshot(output)
            rgb=background.pixels(output)
            if background.read_identity(rgb)==(frame,token):
                return {'frame':frame,'token':token,'mode':mode,'image':str(output),
                        'sha256':digest(output),'scene_sha256':background.scene_digest(rgb),'pose':event['pose']}
        raise RuntimeError('Source identity failed')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--smoke',action='store_true')
    parser.add_argument('--prepare-only',action='store_true')
    parser.add_argument('--source-fps',type=int,choices=(30,80,100,110),default=30)
    parser.add_argument('--cadence',choices=('constant','variable'),default='constant')
    args=parser.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    times=timeline(args.source_fps,args.cadence)
    client,report=prepare(out,times,args.source_fps)
    report.update(resolution=[WIDTH,HEIGHT],source_fps=args.source_fps,source_clock='timestamped_index',
                  cadence=args.cadence,source_times_seconds=times,duration_seconds=3.2,
                  config_sha256=digest(client/'config.js'),
                  frames=[],scope='isolated clean rendered source + visible-surface labels; no production shader')
    if args.prepare_only:
        report['status']='prepared'
        (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
        print(out/'manifest.json');return
    original.ensure_vendor()
    original.SCENE=client
    background.WIDTH,background.HEIGHT=WIDTH,HEIGHT
    server,events,lock=original.serve(out)
    browser=None
    poses=sorted(set(min(len(times)-1,int(np.searchsorted(times,t))) for t in (0,32/30,48/30,64/30,80/30,times[-1]))) if args.smoke else list(range(len(times)))
    try:
        with tempfile.TemporaryDirectory(prefix='temporal-course-') as temp:
            browser=Browser('temporal',server,events,lock,Path(temp),out,original.wait_event)
            for index,frame in enumerate(poses):
                pair={}
                for mode,name in [(0,'clean'),(1,'surface')]:
                    folder=out/name;folder.mkdir(exist_ok=True)
                    pair[name]=browser.capture_mode(frame,mode,folder/f'{index:04d}.png')
                report['frames'].append(pair)
                if index%8==0 or index==len(poses)-1:print(f'Temporal source {index+1}/{len(poses)} frame {frame}',flush=True)
            repeat=browser.capture_mode(poses[0],0,out/'first_repeat.png')
            assert repeat['scene_sha256']==report['frames'][0]['clean']['scene_sha256']
            report['first_repeat']=repeat
            report['status']='complete'
    except BaseException as error:
        report['status']='failed';report['failure']={'type':type(error).__name__,'message':str(error)}
        raise
    finally:
        if browser is not None:browser.close()
        server.shutdown();server.server_close()
        report['production_after']={p:digest(ROOT/p) for p in report['production_before']}
        report['production_unchanged']=report['production_after']==report['production_before']
        (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n')
        print('Manifest:',out/'manifest.json',flush=True)
    assert report['production_unchanged']

if __name__=='__main__':main()
