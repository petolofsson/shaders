#!/usr/bin/env python3
"""Final source/reference provenance checkpoint; no runtime launch."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[2]
TOOLS=Path(__file__).resolve().parent

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as f:
        for chunk in iter(lambda:f.read(4*1024*1024),b''):h.update(chunk)
    return h.hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--experiment',required=True,type=Path)
    args=parser.parse_args();p=args.experiment.resolve()
    assert not (p/'verification.json').exists()
    source=json.loads((p/'source/manifest.json').read_text())
    source100=json.loads((p/'rate100_source/manifest.json').read_text())
    assert source['production_before']==source['production_after']==source100['production_before']==source100['production_after']
    assert all(digest(ROOT/path)==h for path,h in source['production_before'].items())
    assert digest(p/'source/export_source_epoch.py')==source['source_files']['export.py']
    for item in (source,source100):
        client=Path(item['frames'][0]['clean']['image']).parents[1]/'client'
        for name in ('scene.js','index.html'):assert digest(client/name)==item['source_files'][name]
    old_cache=json.loads((ROOT/'captures/babylon_scene_runs/20261024_160908/motion-source/manifest.json').read_text())
    assert digest(ROOT/'tools/babylon_scene/scene.js')==old_cache['scene_sha256']
    assert digest(ROOT/'tools/babylon_scene/index.html')==old_cache['html_sha256']
    old_artifacts={}
    for folder in ('shadow_temporal_support_20261106','shadow_temporal_planar_20261106'):
        directory=ROOT/'captures'/folder;manifest=json.loads((directory/'artifact_manifest.json').read_text())
        assert all(digest(directory/name)==h for name,h in manifest.items());old_artifacts[folder]=len(manifest)
    reports={name:json.loads((p/'centered'/name/'report.json').read_text()) for name in ('clean','changing','screen_fixed','surface_fixed')}
    assert len(reports['changing']['frames'])==96
    assert all(len(reports[name]['frames'])==20 for name in ('clean','screen_fixed','surface_fixed'))
    high=json.loads((p/'rate100_changing/report.json').read_text());assert len(high['frames'])==320
    assert high['history_window_ms']==100
    assert all(max(r['history_ages_ms'])<=100.000001 for r in high['frames'])
    for report in list(reports.values())+[high,json.loads((p/'rate100_surface_fixed/report.json').read_text())]:
        assert report['production_unchanged'] and report['ground_truth_used_only_for_oracle_and_diagnostics']
        for row in report['frames']:
            for checks in row['checks'].values():assert abs(checks['mean_code_change'])<1e-12
            assert not any(row['rgb_preview_headroom_pixels'].values())
    for name,count in [('centered/changing',96),('rate100_changing',320)]:
        verification=json.loads((p/name/'video_verification.json').read_text());assert verification['decoded_frames_exact']==count
    rate=json.loads((p/'rate_comparison.json').read_text())
    assert all(v==32 for v in rate['common_time_exact_counts'].values())
    assert all(v['first_repeat_exact'] for v in rate['clock_smokes'].values())
    copies=p/'tools_snapshot';copies.mkdir()
    for path in TOOLS.iterdir():
        if path.is_file():shutil.copyfile(path,copies/path.name)
    out={'scope':'controlled source generation and CPU-reference verification only',
        'production_identities_unchanged':17,'original_course_scene_unchanged':True,
        'prior_artifact_hashes_verified':old_artifacts,
        'dense_source_updates':{'30fps':96,'100fps':320},
        'source_verification_30':json.loads((p/'source_verification.json').read_text()),
        'source_verification_100':json.loads((p/'rate100_source_verification.json').read_text()),
        'common_time_exact_RGB8_pairs_per_variant':32,
        'elapsed_time_history_ms':100,'lossless_CPU_replay_frames_verified':416,
        'failed_initial_epochs_preserved':True,'shader_candidate_adopted':False,
        'actual_game_rate_GPU_validation':False,'effectiveness_scores_changed':False,
        'diagnostic_tool_tests_passed':22,'GPU_source_runtime_complete':True}
    (p/'verification.json').write_text(json.dumps(out,indent=2)+'\n')
    manifest={str(path.relative_to(p)):digest(path) for path in sorted(p.rglob('*'))
              if path.is_file() and path.name!='artifact_manifest.json' and '__pycache__' not in path.parts}
    (p/'artifact_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps({'artifacts':len(manifest),'production_unchanged':17,'prior_artifacts':old_artifacts,
                      'dense_CPU_reference_frames':416,'real_time_candidate':False},indent=2))

if __name__=='__main__':main()
