#!/usr/bin/env python3
"""Scope-aware summary of the controlled CPU reference and selected material gaps."""
import argparse
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
import geometry as g

ROOT=Path(__file__).resolve().parents[2]

def pooled(rows,key):
    total=sum(r[key]['count'] for r in rows)
    return float(np.sqrt(sum(r[key]['rmse']**2*r[key]['count'] for r in rows)/total)) if total else None

def gaps(source,result,ids,surface,distance=4):
    values=[]
    for axis in (0,1):
        a=[slice(8,-8),slice(8,-8)];b=a.copy()
        a[axis]=slice(8,-8-distance);b[axis]=slice(8+distance,-8)
        a,b=tuple(a),tuple(b);ds=source[b]-source[a]
        valid=(ids[a]==surface)&(ids[b]==surface)&(source[a]>8)&(source[b]>8)&(source[a]<100)&(source[b]<100)&(abs(ds)>.25)&(abs(ds)<8)
        values.extend(((result[b]-result[a])*np.sign(ds))[valid])
    return {'count':len(values),'mean_signed_gap':float(np.mean(values)) if values else None}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment',required=True,type=Path)
    args=parser.parse_args();base=args.experiment
    assert not (base/'summary.json').exists()
    reports={name:json.loads((base/'centered'/name/'report.json').read_text()) for name in ('clean','changing','screen_fixed','surface_fixed')}
    changing=reports['changing']
    phases={name:{phase:[] for phase in ('stationary','camera_motion','occlusion','lighting','cut')} for name in reports}
    # Compare the identical selected four-frame windows, not changing/all versus other/windows.
    indices={r['index'] for r in reports['clean']['frames']}
    for name,report in reports.items():
        for row in report['frames']:
            if row['index'] in indices:phases[name][row['phase']].append(row)
    summary={'scope':'same 20 controlled target updates across variants; overlaps are not independent samples',
             'variants':{},'selected_material_gaps':{}}
    for name,groups in phases.items():
        output={}
        for phase,rows in groups.items():
            baseline=pooled(rows,'baseline_error');point=pooled(rows,'point_error');rgb=pooled(rows,'rgb_brightness_error');oracle=pooled(rows,'oracle_brightness_error')
            geometry=[x for row in rows for x in row['geometry']]
            accepted=sum(round(x['rgb_accept_fraction']*row['source_noise']['count']) for row in rows for x in row['geometry'])
            unsupported=sum(x['rgb_accepted_without_visible_correspondence'] for x in geometry)
            output[phase]={'frames':len(rows),'source_noise_rmse':pooled(rows,'source_noise'),
                'source_rgb_rmse':pooled(rows,'source_rgb_estimate_error'),'source_oracle_rmse':pooled(rows,'source_oracle_error'),
                'clean_rgb_mismatch_rmse':pooled(rows,'source_rgb_clean_mismatch'),
                'rgb_mean_samples':float(np.mean([r['rgb_samples'] for r in rows])),
                'oracle_mean_samples':float(np.mean([r['oracle_samples'] for r in rows])),
                'baseline_error':baseline,'point_error':point,'rgb_brightness_error':rgb,'oracle_brightness_error':oracle,
                'rgb_error_ratio_to_baseline':rgb/baseline if baseline and baseline>1e-12 else None,
                'point_error_ratio_to_baseline':point/baseline if baseline and baseline>1e-12 else None,
                'rgb_accepted_without_supported_known_correspondence_fraction':unsupported/accepted if accepted else None}
        summary['variants'][name]=output
    # Selected independent source-side gap populations, same-surface pairs only.
    inputs=json.loads((base/'inputs_centered/manifest.json').read_text())
    source=json.loads((base/'source/manifest.json').read_text())
    roi=tuple(changing['roi'])
    sys.path.insert(0,str(ROOT/'captures/shadow_temporal_planar_20261106'))
    from brightness import correction,forward
    for index in (15,40,43,56,59,72,75,80,83,95):
        folder=base/'centered/changing'
        clean=g.code_y(np.asarray(Image.open(inputs['frames'][index]['images']['clean']['path']).convert('RGB').crop(roi)))
        ids=g.labels(np.asarray(Image.open(source['frames'][index]['surface']['image']).convert('RGB').crop(roi)))
        baseline=np.load(folder/f'{index:04d}_baseline.npy')
        predicted=np.load(folder/f'{index:04d}_rgb_brightness.npy')
        known=np.load(folder/f'{index:04d}_oracle_brightness.npy')
        ideal,_=correction(clean,clean)
        clean_base=forward(clean)
        entry={}
        for key,surface in [('timber',1),('metal',2)]:
            metrics={name:gaps(clean,image,ids,surface) for name,image in [('clean_baseline',clean_base),('ideal_clean',ideal),('noisy_baseline',baseline),('rgb_temporal',predicted),('oracle_temporal',known)]}
            if metrics['clean_baseline']['count']:
                metrics['rgb_noisy_gap_gain_percent']=100*(metrics['rgb_temporal']['mean_signed_gap']/metrics['noisy_baseline']['mean_signed_gap']-1)
                metrics['ideal_clean_gap_gain_percent']=100*(metrics['ideal_clean']['mean_signed_gap']/metrics['clean_baseline']['mean_signed_gap']-1)
            entry[key]=metrics
        summary['selected_material_gaps'][str(index)]=entry
    summary['changing_complete_sequence_frames']=len(changing['frames'])
    summary['production_unchanged']=all(r['production_unchanged'] for r in reports.values())
    assert summary['production_unchanged']
    (base/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary['variants'],indent=2))

if __name__=='__main__':main()
