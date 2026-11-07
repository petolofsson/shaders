#!/usr/bin/env python3
"""Freeze a bounded-motion screen without treating CPU work as GPU validation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import numpy as np
from summarize import pooled
import bounded_motion as motion

ROOT=Path(__file__).resolve().parents[2]

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment',required=True,type=Path)
    args=parser.parse_args();p=args.experiment.resolve()
    assert not (p/'verification.json').exists()
    production=json.loads((ROOT/'captures/shadow_temporal_course_20261106/source/manifest.json').read_text())['production_before']
    assert all(digest(ROOT/path)==h for path,h in production.items())
    preserved={}
    for folder in ('shadow_temporal_support_20261106','shadow_temporal_planar_20261106','shadow_temporal_course_20261106'):
        directory=ROOT/'captures'/folder
        manifest=json.loads((directory/'artifact_manifest.json').read_text())
        assert all(digest(directory/name)==h for name,h in manifest.items())
        preserved[folder]=len(manifest)
    folders=['rate100_changing','rate100_clean','rate100_surface_fixed','rate30_changing','rate100_all',
             'support_gate_final','support_gate_fixed','fullframe_support','fullframe_fixed','fullframe_all']
    reports={name:json.loads((p/name/'report.json').read_text()) for name in folders}
    summary={'scope':'CPU screen; no real-time implementation, GPU cadence or performance claim','reports':{}}
    for name,report in reports.items():
        assert report['production_unchanged'] and report['ground_truth_used_only_for_oracle_and_diagnostics']
        assert report['history_window_ms']==100
        assert len(report['frames'])==(320 if name.endswith('_all') else 20)
        for row in report['frames']:
            assert max(row['history_ages_ms'])<=100.000001
            for checks in row['checks'].values():
                assert abs(checks['mean_code_change'])<1e-12 and checks['max_code_change']<=2.000000001
            assert not any(row['rgb_preview_headroom_pixels'].values())
        phases={}
        for phase in dict.fromkeys(row['phase'] for row in report['frames']):
            rows=[row for row in report['frames'] if row['phase']==phase]
            baseline=pooled(rows,'baseline_error')
            item={'frames':len(rows),'source_rmse':pooled(rows,'source_rgb_estimate_error'),
                  'clean_mismatch_rmse':pooled(rows,'source_rgb_clean_mismatch'),
                  'samples':float(np.mean([row['rgb_samples'] for row in rows])),
                  'conditional_brightness_error_ratio':pooled(rows,'rgb_brightness_error')/baseline if baseline else None}
            if report.get('support_gate'):
                item['mean_support']=float(np.mean([row['checks']['rgb']['mean_support'] for row in rows]))
                item['error_against_full_ideal_ratio']=pooled(rows,'brightness_error_against_full_ideal')/baseline if baseline else None
            if 'material_gaps_16px_alignment_only' in rows[0]:
                item['alignment_only_16px_gap_gain_percent']={surface:float(np.mean([row['material_gaps_16px_alignment_only'][surface]['gap_gain_percent'] for row in rows])) for surface in ('1','2')}
            accepted=sum(g['rgb_accept_fraction']*row['source_noise']['count'] for row in rows for g in row['geometry'])
            unsupported=sum(g['rgb_accepted_without_visible_correspondence'] for row in rows for g in row['geometry'])
            item['accepted_without_visible_correspondence_fraction']=unsupported/accepted if accepted else None
            phases[phase]=item
        summary['reports'][name]={'phases':phases,'report_sha256':digest(p/name/'report.json')}
    # No support must produce the exact baseline; full support must preserve the
    # original range/mean contract. Test with the same source-domain forward map.
    import sys
    sys.path.insert(0,str(ROOT/'captures/shadow_temporal_planar_20261106'))
    from brightness import forward
    source=np.linspace(0,255,512*384).reshape(384,512)
    baseline=forward(source)
    result,checks=motion.supported_correction(source,source,np.ones_like(source),forward)
    assert np.array_equal(result,baseline)
    result,checks=motion.supported_correction(source,source,np.ones_like(source)*4,forward)
    assert result.min()>=0 and result.max()<=255
    assert abs(checks['mean_code_change'])<1e-12 and checks['max_code_change']<=2.000000001
    numeric=json.loads((p/'numeric_checks.json').read_text())
    assert numeric['max_solve_error']<1e-8
    assert all(row['fp32_valid']==row['fp64_valid'] for row in numeric['actual_pairs'])
    assert not numeric['identity_cases']['flat']['valid'] and not numeric['identity_cases']['aperture_x']['valid']
    (p/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    snapshot=p/'tools_snapshot';snapshot.mkdir()
    for path in Path(__file__).parent.iterdir():
        if path.is_file():shutil.copyfile(path,snapshot/path.name)
    verification={'production_unchanged':production,'prior_artifacts_verified':preserved,
                  'reports':len(reports),'dense_reference_frames':640,'selected_reference_frames':160,
                  'zero_support_exact_baseline':True,'mean_SDR_two_code_contracts':True,
                  'GPU_motion_producer_tested':False,'real_time_performance_tested':False,
                  'production_adopted':False,'effectiveness_scores_changed':False,
                  'preliminary_gate_report':'rate100_support_gate retained; point/oracle error fields there used conditional ideal; use final reports'}
    (p/'verification.json').write_text(json.dumps(verification,indent=2)+'\n')
    manifest={str(path.relative_to(p)):digest(path) for path in sorted(p.rglob('*')) if path.is_file() and path.name!='artifact_manifest.json' and '__pycache__' not in path.parts}
    (p/'artifact_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'reports':len(reports),'artifacts':len(manifest),'production_unchanged':len(production),'prior_artifacts_verified':preserved},indent=2))

if __name__=='__main__':main()
