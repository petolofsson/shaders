#!/usr/bin/env python3
"""Compare matched physical-time windows; no render-performance inference."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image
from summarize import pooled

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment',required=True,type=Path)
    args=parser.parse_args();p=args.experiment
    assert not (p/'rate_comparison.json').exists()
    source30=json.loads((p/'source/manifest.json').read_text())
    source100=json.loads((p/'rate100_source/manifest.json').read_text())
    input30=json.loads((p/'inputs_centered/manifest.json').read_text())
    input100=json.loads((p/'rate100_inputs/manifest.json').read_text())
    common=[]
    for i in range(0,96,3):
        j=round(i/30*100)
        checks={}
        for variant in input30['variants']:
            a=np.asarray(Image.open(input30['frames'][i]['images'][variant]['path']).convert('RGB'))[:-4]
            b=np.asarray(Image.open(input100['frames'][j]['images'][variant]['path']).convert('RGB'))[:-4]
            checks[variant]=bool(np.array_equal(a,b))
        common.append({'index30':i,'index100':j,'time_seconds':i/30,'RGB8_scene_exact':checks})
    out={'scope':'offline source sampling, elapsed-history CPU reference; not achieved FPS or GPU-history validation',
         'common_time_input_checks':common,'comparisons':{},'clock_smokes':{}}
    for variant,folder100 in [('changing','rate100_changing'),('surface_fixed','rate100_surface_fixed')]:
        a=json.loads((p/'centered'/variant/'report.json').read_text())
        b=json.loads((p/folder100/'report.json').read_text())
        # Match the original 20 selected windows; the changing report also contains all updates.
        reference=json.loads((p/'centered/clean/report.json').read_text())['frames']
        a_by={r['index']:r for r in a['frames']};b_by={r['index']:r for r in b['frames']}
        times=np.array(b['source_times_seconds'])
        matches=[];comparison={}
        for reference_row in reference:
            i=reference_row['index'];j=int(np.argmin(abs(times-i/30)))
            matches.append((a_by[i],b_by[j],abs(times[j]-i/30)*1000))
        for phase in ('stationary','camera_motion','occlusion','lighting','cut'):
            rows=[x for x in matches if x[0]['phase']==phase]
            entry={}
            for rate,index in [('30',0),('100',1)]:
                selected=[r[index] for r in rows]
                baseline=pooled(selected,'baseline_error');brightness=pooled(selected,'rgb_brightness_error')
                entry[rate]={'frames':len(selected),'source_rgb_rmse':pooled(selected,'source_rgb_estimate_error'),
                    'source_oracle_rmse':pooled(selected,'source_oracle_error'),
                    'rgb_samples':float(np.mean([x['rgb_samples'] for x in selected])),
                    'brightness_error_ratio_to_baseline':brightness/baseline,
                    'history_ages_ms':[x.get('history_ages_ms',[100.,200/3,100/3,0.]) for x in selected]}
            comparison[phase]=entry
        out['comparisons'][variant]={'max_target_time_error_ms':max(x[2] for x in matches),'phases':comparison,
                                      'evaluated_frames_100':len(b['frames'])}
    for name in ('rate80_smoke','rate100_smoke','rate110_smoke','variable_smoke'):
        r=json.loads((p/name/'manifest.json').read_text());assert r['status']=='complete' and r['production_unchanged']
        times=np.array(r['source_times_seconds']);dt=np.diff(times)
        out['clock_smokes'][name]={'captured_states':len(r['frames']),'clock_states':len(times),
            'min_dt_ms':float(dt.min()*1000),'max_dt_ms':float(dt.max()*1000),
            'first_repeat_exact':r['first_repeat']['scene_sha256']==r['frames'][0]['clean']['scene_sha256']}
    out['common_time_exact_counts']={variant:sum(r['RGB8_scene_exact'][variant] for r in common) for variant in input30['variants']}
    (p/'rate_comparison.json').write_text(json.dumps(out,indent=2)+'\n')
    print(json.dumps({'common_time_exact_counts':out['common_time_exact_counts'],'comparisons':out['comparisons']},indent=2))

if __name__=='__main__':main()
