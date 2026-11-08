#!/usr/bin/env python3
"""Offline BDRAR shadow-mask review on local still images, CPU only.

The network and checkpoint are supplied explicitly from an inspected local
checkout. This script never downloads models, opens a display or uses a GPU.
"""
import argparse
import hashlib
import html
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUTS = (
    'gamespecific/gzw/analysis/reference/Screenshot_20260516_101035.png',
    'gamespecific/gzw/analysis/reference/autof_20260515_133058.png',
    'gamespecific/gzw/analysis/reference/autof_20260515_133444.png',
    'gamespecific/arc_raiders/analysis/reference/autof_20260515_205938.png',
    'gamespecific/arc_raiders/analysis/reference/autof_20260515_210448.png',
)
MEAN = np.array([.485, .456, .406], dtype=np.float32)
STD = np.array([.229, .224, .225], dtype=np.float32)

def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def prepare(image, short_side):
    w, h = image.size
    if min(w, h) == 0:
        raise ValueError('empty image')
    # torchvision Resize(int): preserve aspect ratio, scale the short side.
    size = (short_side, int(h * short_side / w)) if w <= h else (int(w * short_side / h), short_side)
    resized = image.resize(size, Image.Resampling.BILINEAR)
    x = np.asarray(resized, dtype=np.float32) / 255.0
    return np.transpose((x - MEAN) / STD, (2, 0, 1)).copy(), size

def overlay(image, probability):
    rgb = np.asarray(image, dtype=np.float32)
    alpha = np.clip(probability, 0, 1)[..., None] * .55
    red = np.array([255, 45, 45], dtype=np.float32)
    return Image.fromarray(np.round(rgb * (1 - alpha) + red * alpha).astype(np.uint8))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vendor', required=True, type=Path, help='local, inspected BDRAR source directory')
    parser.add_argument('--weights', required=True, type=Path, help='local BDRAR state-dict checkpoint')
    parser.add_argument('--output', required=True, type=Path, help='new output directory')
    parser.add_argument('--short-side', type=int, default=416)
    parser.add_argument('--threads', type=int, default=4)
    parser.add_argument('images', nargs='*', type=Path, help='input images; defaults to five game references')
    args = parser.parse_args()
    if args.short_side < 64 or args.threads < 1:
        parser.error('short-side must be >= 64 and threads must be >= 1')
    vendor, weights, output = args.vendor.resolve(), args.weights.resolve(), args.output.resolve()
    if not (vendor / 'model.py').is_file() or not weights.is_file():
        parser.error('local vendor/model.py and checkpoint must exist')
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        parser.error('output directory must be new or empty; preserved results are never overwritten')
    images = [p.resolve() for p in args.images] if args.images else [ROOT / p for p in DEFAULT_INPUTS]
    missing = [str(p) for p in images if not p.is_file()]
    if missing:
        parser.error('missing input files: ' + ', '.join(missing))
    try:
        import torch
        import torch.nn.functional as F
    except ImportError as exc:
        parser.error(f'CPU PyTorch is required: {exc}')
    torch.set_num_threads(args.threads)
    sys.path.insert(0, str(vendor))
    from model import BDRAR
    model = BDRAR().cpu().eval()
    state = torch.load(weights, map_location='cpu', weights_only=True)
    model.load_state_dict(state, strict=True)
    output.mkdir(parents=True, exist_ok=True)
    code_files = [vendor / 'model.py', vendor / 'resnext/__init__.py',
                  vendor / 'resnext/resnext101_regular.py', vendor / 'resnext/resnext_101_32x4d_.py']
    report = {'model': 'BDRAR (ECCV 2018), raw sigmoid without CRF',
              'model_source': 'https://github.com/zijundeng/BDRAR',
              'checkpoint': str(weights), 'checkpoint_sha256': digest(weights),
              'code_sha256': {str(p): digest(p) for p in code_files},
              'tester_sha256': digest(Path(__file__)), 'torch_version': str(torch.__version__),
              'device': 'cpu', 'short_side': args.short_side, 'threads': args.threads,
              'preprocessing': 'RGB, bilinear short-side resize, ImageNet mean/std',
              'postprocessing': 'sigmoid model output, bilinear float resize; no CRF, no per-image normalization',
              'threshold_for_preview_only': .5, 'cases': []}
    for idx, path in enumerate(images):
        with Image.open(path) as original:
            image = original.convert('RGB')
        x, model_size = prepare(image, args.short_side)
        with torch.inference_mode():
            tensor = torch.from_numpy(x).unsqueeze(0)
            prediction = model(tensor)
            if prediction.ndim != 4 or prediction.shape[:2] != (1, 1):
                raise ValueError(f'unexpected model output shape {tuple(prediction.shape)}')
            probability = F.interpolate(prediction, size=(image.height, image.width), mode='bilinear', align_corners=False)
            probability = probability.squeeze(0).squeeze(0).numpy()
        if not np.isfinite(probability).all() or probability.min() < -1e-6 or probability.max() > 1 + 1e-6:
            raise ValueError(f'invalid shadow probabilities for {path}')
        probability = np.clip(probability, 0, 1).astype(np.float32)
        prefix = f'{idx:02d}_{path.stem}'
        names = {kind: f'{prefix}_{suffix}' for kind, suffix in
                 [('source', 'source.png'), ('raw', 'probability.npy'), ('mask', 'probability.png'),
                  ('binary', 'threshold_050.png'), ('overlay', 'overlay.png')]}
        image.save(output / names['source'])
        np.save(output / names['raw'], probability)
        Image.fromarray(np.round(probability * 255).astype(np.uint8)).save(output / names['mask'])
        Image.fromarray((probability >= .5).astype(np.uint8) * 255).save(output / names['binary'])
        overlay(image, probability).save(output / names['overlay'])
        report['cases'].append({'source': str(path), 'source_sha256': digest(path),
                                'source_size': list(image.size), 'model_input_size': list(model_size),
                                'probability_min': float(probability.min()), 'probability_max': float(probability.max()),
                                'outputs': {k: {'path': v, 'sha256': digest(output / v)} for k, v in names.items()}})
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(f'Processed {path.name}', flush=True)
    cards = []
    for case in report['cases']:
        label = html.escape(Path(case['source']).name)
        f = case['outputs']
        cards.append(f'<section><h2>{label}</h2><p>Input · raw probability · red probability overlay · threshold 0.5</p>'
                     + ''.join(f'<figure><figcaption>{html.escape(k)}</figcaption><img loading="lazy" src="{html.escape(f[k]["path"])}" alt="{label}: {html.escape(k)}"></figure>' for k in ('source', 'mask', 'overlay', 'binary'))
                     + '</section>')
    page = ('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
            '<title>Offline shadow detector review</title><style>body{background:#181a1d;color:#eee;font:16px system-ui;margin:2rem}'
            'section{border-top:1px solid #555}figure{display:inline-block;width:48%;margin:1% 1% 1% 0;vertical-align:top}'
            'img{width:100%}figcaption{margin:.4rem 0}</style><h1>Offline BDRAR shadow detector</h1>'
            '<p>Brighter mask and stronger red mean higher model output. The 0.5 threshold is only a preview, not a calibrated decision. '
            'This model was trained on photographs; masks may miss game shadows or flag dark materials. '
            'Input is resized and individual frames have no temporal stability guarantee.</p>' + ''.join(cards))
    (output / 'review.html').write_text(page)

if __name__ == '__main__':
    main()
