import json,sys,numpy as np
from pathlib import Path
sys.path.insert(0,'tools/temporal_course');from summarize import pooled
base=Path('captures/shadow_bounded_motion_20261106');new=Path('captures/shadow_boundary_check_20261106')
def load(p):return json.loads(p.read_text())['frames']
a=load(base/'fullframe_all/report.json');b=load(new/'dense/report.json');assert len(a)==len(b)==320
summary={}
for phase in ['stationary','camera_motion','occlusion','lighting','cut']:
 summary[phase]={}
 for name,rows in [('before',a),('after',b)]:
  r=[x for x in rows if x['phase']==phase];accepted=sum(g['rgb_accept_fraction']*x['source_noise']['count'] for x in r for g in x['geometry']);bad=sum(g['rgb_accepted_without_visible_correspondence'] for x in r for g in x['geometry']);supports=np.array([x['checks']['rgb']['mean_support'] for x in r]);summary[phase][name]={'frames':len(r),'unsupported_fraction':bad/accepted if accepted else 0,'support':float(supports.mean()),'support_step_p99':float(np.quantile(abs(np.diff(supports)),.99)),'source_rmse':pooled(r,'source_rgb_estimate_error'),'brightness_ratio':pooled(r,'rgb_brightness_error')/pooled(r,'baseline_error'),'gap_gain':{s:float(np.mean([x['material_gaps_16px_alignment_only'][s]['gap_gain_percent'] for x in r])) for s in ['1','2']}}
for name,p in [('before',base/'fullframe_fixed/report.json'),('after',new/'fixed/report.json')]:
 rows=[x for x in load(p) if x['phase']=='camera_motion'];summary.setdefault('surface_fixed_camera',{})[name]={'brightness_ratio':pooled(rows,'rgb_brightness_error')/pooled(rows,'baseline_error'),'support':float(np.mean([x['checks']['rgb']['mean_support'] for x in rows]))}
(new/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
