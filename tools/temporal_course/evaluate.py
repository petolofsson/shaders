#!/usr/bin/env python3
"""Evaluate controlled temporal evidence without production or ground-truth leakage."""
import argparse
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image,ImageDraw
import geometry as g

ROOT=Path(__file__).resolve().parents[2]
ROI=(384,160,896,544)
WINDOWS={'stationary':range(12,16),'camera_motion':range(40,44),'occlusion':range(56,60),
         'lighting':range(72,76),'cut':range(80,84)}

def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def stats(error,mask):
    z=error[mask]
    return {'count':int(mask.sum()),'mean':float(z.mean()) if len(z) else None,
            'rmse':float(np.sqrt(np.mean(z*z))) if len(z) else None,
            'p99_abs':float(np.quantile(abs(z),.99)) if len(z) else None}

def material_gaps(source,baseline,result,labels,distance=16):
    answer={}
    for surface in (1,2):
        sums=np.zeros(3)
        for axis in (0,1):
            a=[slice(16,-16),slice(16,-16)];b=a.copy()
            a[axis]=slice(16,-16-distance);b[axis]=slice(16+distance,-16)
            a,b=tuple(a),tuple(b);difference=source[b]-source[a]
            use=(labels[a]==surface)&(labels[b]==surface)&(source[a]>8)&(source[b]>8)&(source[a]<100)&(source[b]<100)&(abs(difference)>.25)&(abs(difference)<8)
            sums+=np.array([use.sum(),np.sum(((baseline[b]-baseline[a])*np.sign(difference))[use]),
                           np.sum(((result[b]-result[a])*np.sign(difference))[use])])
        answer[str(surface)]={'pairs':int(sums[0]),'baseline_signed_gap':float(sums[1]/max(sums[0],1)),
                              'result_signed_gap':float(sums[2]/max(sums[0],1)),
                              'gap_gain_percent':float(100*(sums[2]/sums[1]-1)) if sums[1] else None}
    return answer

def preview(rgb,baseline_code,target):
    linear=.9925*g.decode(rgb.astype(float)/255)+.0025
    y=linear@g.W
    gain=g.decode(np.clip(target/255,0,1))/np.maximum(y,1e-20)
    limited=np.minimum(gain,1/np.maximum(linear.max(axis=2),1e-20))
    result=linear*limited[...,None]
    return np.uint8(np.rint(np.clip(g.encode(result),0,1)*255)),int((limited<gain-1e-12).sum())

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs',required=True,type=Path)
    parser.add_argument('--output',required=True,type=Path)
    parser.add_argument('--variant',required=True,choices=['clean','changing','screen_fixed','surface_fixed'])
    parser.add_argument('--targets',choices=['all','windows','matched-30'],default='windows')
    parser.add_argument('--history-ms',type=float,default=100.)
    parser.add_argument('--motion-method',choices=['features','bounded'],default='features')
    parser.add_argument('--support-gate',action='store_true')
    parser.add_argument('--boundary-check',action='store_true',help='Require an additional 9x9 residual RMS check.')
    parser.add_argument('--motion-domain',choices=['roi','full-frame'],default='roi')
    parser.add_argument('--model-directory',type=Path,default=ROOT/'captures/shadow_temporal_planar_20261106')
    args=parser.parse_args()
    sys.path.insert(0,str(args.model_directory.resolve()))
    import model as motion
    import refine
    from brightness import correction,forward
    inputs=json.loads((args.inputs/'manifest.json').read_text())
    source=Path(inputs['source']);meta=json.loads((source/'manifest.json').read_text())
    assert digest(source/'manifest.json')==inputs['source_manifest_sha256']
    assert meta['status']=='complete' and meta['production_unchanged']
    assert all(digest(ROOT/p)==h for p,h in meta['production_before'].items())
    frozen=json.loads((args.model_directory/'artifact_manifest.json').read_text())
    for p in ('model.py','refine.py','brightness.py'):assert digest(args.model_directory/p)==frozen[p]
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    frames_out=out/'frames';frames_out.mkdir()
    x0,y0,x1,y1=ROI
    @lru_cache(maxsize=12)
    def load(index):
        entry=inputs['frames'][index];pair=meta['frames'][index]
        clean_path=Path(entry['images']['clean']['path']);noisy_path=Path(entry['images'][args.variant]['path'])
        surface=Path(pair['surface']['image'])
        assert digest(clean_path)==entry['images']['clean']['sha256']
        assert digest(noisy_path)==entry['images'][args.variant]['sha256']
        assert digest(surface)==pair['surface']['sha256']
        clean=np.asarray(Image.open(clean_path).convert('RGB').crop(ROI))
        rgb=np.asarray(Image.open(noisy_path).convert('RGB').crop(ROI))
        labels=g.labels(np.asarray(Image.open(surface).convert('RGB').crop(ROI)))
        s=g.code_y(clean);observed=g.code_y(rgb)
        return s,observed,observed-s,labels,pair['clean']['pose'],rgb
    import bounded_motion
    @lru_cache(maxsize=32)
    def adjacent(index):
        if args.motion_domain=='full-frame':
            def frame(i):
                entry=inputs['frames'][i]['images'][args.variant]
                assert digest(entry['path'])==entry['sha256']
                return g.code_y(np.asarray(Image.open(entry['path']).convert('RGB')))
            H,info=bounded_motion.fit(frame(index),frame(index-1))
            offset=np.array([[1.,0,x0],[0,1.,y0],[0,0,1.]])
            H=np.linalg.inv(offset)@H@offset
            return H,info
        return bounded_motion.fit(load(index)[1],load(index-1)[1])
    def bounded_estimate(indices,data):
        current=data[-1][1];total=current.copy();signal=data[-1][0].copy()
        npart=data[-1][2].copy();count=np.ones_like(current);details=[]
        for i,index in enumerate(indices[:-1]):
            H,valid=bounded_motion.compose(indices[-1],index,adjacent)
            info={'valid':valid,'homography':H.tolist(),'adjacent_links':indices[-1]-index,
                  'links':[adjacent(j)[1] for j in range(indices[-1],index,-1)]}
            accept=np.zeros_like(current,dtype=bool)
            if valid:
                sample,inside=motion.warp(data[i][1],H);residual=sample-current
                accept=inside&(np.sqrt(np.maximum(motion.box(residual*residual,3),0))<=2)&(abs(residual)<=3)
                if args.boundary_check:
                    accept &= np.sqrt(np.maximum(motion.box(residual*residual,9),0))<=2
                s,_=motion.warp(data[i][0],H);n,_=motion.warp(data[i][2],H)
                total+=accept*sample;signal+=accept*s;npart+=accept*n;count+=accept
            details.append((info,accept))
        return total/count,signal/count,npart/count,count,details
    times=np.array([f.get('source_time_seconds',f['route_frame']/60) for f in inputs['frames']])
    if args.targets=='all':targets=list(range(len(times)))
    elif args.targets=='matched-30':
        targets=sorted(set(int(np.argmin(abs(times-i/30))) for values in WINDOWS.values() for i in values))
    elif len(times)==96 and inputs.get('source_clock','legacy_route60')=='legacy_route60':
        targets=sorted({i for indices in WINDOWS.values() for i in indices})
    else:
        targets=sorted({j for t in (12/30,40/30,56/30,72/30,80/30)
                        for j in range(int(np.searchsorted(times,t)),min(len(times),int(np.searchsorted(times,t))+4))})
    report={'scope':'controlled rendered source; scalar affine benchmark, not full production grade',
            'inputs_manifest_sha256':digest(args.inputs/'manifest.json'),'variant':args.variant,'roi':ROI,
            'model_hashes':{p:digest(args.model_directory/p) for p in ('model.py','refine.py','brightness.py')},
            'ground_truth_used_only_for_oracle_and_diagnostics':True,'frames':[]}
    report['history_window_ms']=args.history_ms
    report['motion_method']=args.motion_method
    report['support_gate']=args.support_gate
    report['boundary_check']=args.boundary_check
    report['motion_domain']=args.motion_domain
    if args.motion_method=='bounded':report['bounded_motion_sha256']=digest(Path(bounded_motion.__file__))
    report['source_fps']=inputs['source_fps']
    report['source_times_seconds']=times.tolist()
    for number,index in enumerate(targets):
        desired=times[index]-np.array([1.,2/3,1/3,0])*args.history_ms/1000
        # Four observations over elapsed time, not four adjacent high-rate frames.
        indices=sorted(set(min(range(index+1),key=lambda i:abs(times[i]-t)) for t in desired if t>=times[0]-1e-9))
        if index not in indices:indices.append(index)
        data=[load(i) for i in indices]
        clean=[x[0] for x in data];observed=[x[1] for x in data];noise=[x[2] for x in data]
        current=clean[-1];current_ids=data[-1][3]
        mask=np.zeros_like(current,dtype=bool);mask[8:-8,8:-8]=True
        mask&=(current>8)&(current<100)&(current_ids>0)&(current_ids<=8)
        if args.motion_method=='bounded':
            estimated,signal,npart,count,details=bounded_estimate(indices,data)
        else:
            estimated,signal,npart,count,details=refine.estimate(observed,clean,noise,local=False)
        assert abs(estimated-signal-npart).max()<1e-10
        oracle=observed[-1].copy();oracle_signal=clean[-1].copy();oracle_noise=noise[-1].copy()
        oracle_count=np.ones_like(current);geometry=[]
        for i in range(len(data)-1):
            sx,sy,visible,context=g.oracle_maps(data[-1][4],data[i][4],current_ids,data[i][3],ROI[:2])
            sample,_,_=g.bilinear(observed[i],sx,sy)
            clean_sample,_,_=g.bilinear(clean[i],sx,sy);noise_sample,_,_=g.bilinear(noise[i],sx,sy)
            residual=sample-observed[-1]
            accept=visible&(np.sqrt(np.maximum(motion.box(residual*residual,3),0))<=2)&(abs(residual)<=3)
            oracle+=accept*sample;oracle_signal+=accept*clean_sample;oracle_noise+=accept*noise_sample;oracle_count+=accept
            info,predicted_accept=details[i]
            geometric={'history_index':indices[i],'oracle_visible_fraction':float(visible[mask].mean()),
                       'oracle_accept_fraction':float(accept[mask].mean()),'rgb_accept_fraction':float(predicted_accept[mask].mean()),
                       'rgb_accepted_without_visible_correspondence':int((predicted_accept&mask&~visible).sum())}
            if info.get('valid') and 'homography' in info:
                yy,xx=np.indices(current.shape)
                points=np.column_stack((xx.ravel(),yy.ravel()))
                p=g.project(points,np.array(info['homography'])).reshape(*current.shape,2)
                error=np.hypot(p[...,0]-sx,p[...,1]-sy)
                geometric['accepted_endpoint_error']=stats(error,predicted_accept&visible&mask)
            geometry.append(geometric)
        oracle/=oracle_count;oracle_signal/=oracle_count;oracle_noise/=oracle_count
        assert abs(oracle-oracle_signal-oracle_noise).max()<1e-10
        ideal,ideal_checks=correction(current,current)
        point,point_checks=correction(observed[-1],observed[-1])
        rgb_result,rgb_checks=correction(observed[-1],estimated)
        full_ideal=ideal.copy()
        if args.support_gate:
            assert args.motion_method=='bounded'
            rgb_result,rgb_checks=bounded_motion.supported_correction(observed[-1],estimated,count,forward)
            ideal,ideal_checks=bounded_motion.supported_correction(current,current,count,forward)
            signal_result,_=bounded_motion.supported_correction(current,signal,count,forward)
        else:
            signal_result,_=correction(current,signal)
        oracle_result,oracle_checks=correction(observed[-1],oracle)
        baseline=forward(observed[-1]);clean_baseline=forward(current)
        entry={'index':index,'route_frame':meta['frames'][index]['clean']['frame'],
               'source_time_seconds':float(times[index]),'history_indices':indices,
               'history_ages_ms':[float(1000*(times[index]-times[i])) for i in indices],
               'phase':data[-1][4]['phase'],'source_noise':stats(noise[-1],mask),
               'source_rgb_estimate_error':stats(estimated-current,mask),'source_oracle_error':stats(oracle-current,mask),
               'source_rgb_clean_mismatch':stats(signal-current,mask),'source_oracle_clean_mismatch':stats(oracle_signal-current,mask),
               'rgb_samples':float(count[mask].mean()),'oracle_samples':float(oracle_count[mask].mean()),
               'baseline_error':stats(baseline-clean_baseline,mask),'point_error':stats(point-full_ideal,mask),
               'rgb_brightness_error':stats(rgb_result-ideal,mask),'oracle_brightness_error':stats(oracle_result-full_ideal,mask),
               'brightness_error_against_full_ideal':stats(rgb_result-full_ideal,mask),
               'conditional_ideal_strength_rmse':stats(ideal-forward(current),mask),
               'material_gaps_16px_alignment_only':material_gaps(current,clean_baseline,signal_result,current_ids),
               'checks':{'ideal':ideal_checks,'point':point_checks,'rgb':rgb_checks,'oracle':oracle_checks},
               'geometry':geometry}
        for key,value in entry['checks'].items():assert abs(value['mean_code_change'])<1e-12
        # Ordinary source/reference replay: every changing-noise source state is evaluated.
        sheet=Image.new('RGB',(4*(x1-x0),y1-y0+24));draw=ImageDraw.Draw(sheet)
        caps={}
        for k,(name,target) in enumerate([('affine baseline',baseline),('point residual',point),('RGB temporal',rgb_result),('known geometry',oracle_result)]):
            image,capped=preview(data[-1][5],baseline,target);caps[name]=capped
            sheet.paste(Image.fromarray(image),(k*(x1-x0),24));draw.text((k*(x1-x0)+3,5),f'{name} | {index} {entry["phase"]}',fill='white')
        sheet.save(frames_out/f'{number:04d}.png');entry['rgb_preview_headroom_pixels']=caps
        if index in (0,15,40,43,56,59,72,75,80,83,95):
            for name,value in [('current_source',observed[-1]),('baseline',baseline),('rgb_estimate',estimated),('oracle_estimate',oracle),('rgb_brightness',rgb_result),('oracle_brightness',oracle_result)]:
                np.save(out/f'{index:04d}_{name}.npy',value)
        report['frames'].append(entry)
        (out/'report.partial.json').write_text(json.dumps(report,indent=2)+'\n')
        if number%4==0 or number==len(targets)-1:
            print(args.variant,index,entry['phase'],{'rgb_samples':round(entry['rgb_samples'],2),
                'oracle_samples':round(entry['oracle_samples'],2),'rgb_source_rmse':round(entry['source_rgb_estimate_error']['rmse'],3),
                'oracle_source_rmse':round(entry['source_oracle_error']['rmse'],3)},flush=True)
    report['production_unchanged']=all(digest(ROOT/p)==h for p,h in meta['production_before'].items())
    assert report['production_unchanged']
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')

if __name__=='__main__':main()
