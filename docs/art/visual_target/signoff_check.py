#!/usr/bin/env python3
"""PetalWild visual sign-off checker (image side). Free, local: PIL + numpy.
usage: python3 signoff_check.py <capture_dir> [--spec signoff_spec.json]
Reads CAM_*.png plus the optional scene_audit.json written by signoff_capture.gd; prints PASS/FAIL per camera and
writes <capture_dir>/signoff_report.json. Exit code 1 if any camera fails."""
import sys, json, os, glob, argparse, numpy as np
from PIL import Image
def to_lab(rgb):
    c=rgb/255.0; c=np.where(c>0.04045,((c+0.055)/1.055)**2.4,c/12.92)
    M=np.array([[0.4124,0.3576,0.1805],[0.2126,0.7152,0.0722],[0.0193,0.1192,0.9505]])
    xyz=c@M.T/np.array([0.95047,1.0,1.08883])
    f=np.where(xyz>0.008856,np.cbrt(xyz),7.787*xyz+16/116)
    return np.stack([116*f[...,1]-16,500*(f[...,0]-f[...,1]),200*(f[...,1]-f[...,2])],-1)
def hex2rgb(h): h=h.lstrip('#'); return np.array([int(h[i:i+2],16) for i in (0,2,4)],float)
def flat_ground_score(rgb_lower):
    """Placeholder-ground detector: share of the lower half covered by its two most common colours after a
    32-colour median-cut. Checker (two tones) or flat untextured ground scores high (> ~0.45); textured,
    lit painterly ground spreads over many colours (< ~0.35)."""
    q=Image.fromarray(rgb_lower.astype('uint8')).quantize(32,method=Image.Quantize.MEDIANCUT)
    cnt=sorted((c for c,_ in q.getcolors(64)),reverse=True); return float(sum(cnt[:2])/sum(cnt))
def check(png,spec,audit):
    im=Image.open(png).convert('RGB'); im.thumbnail((640,640)); a=np.asarray(im).astype(float)
    lab=to_lab(a.reshape(-1,3)); res={'file':png,'fails':[],'metrics':{}}
    g=spec['global']; m=res['metrics']
    m['clip_white_pct']=float(((a>=250).all(-1)).mean()*100); m['crush_black_pct']=float(((a<=6).all(-1)).mean()*100)
    m['mean_chroma']=float(np.hypot(lab[:,1],lab[:,2]).mean())
    lower=np.asarray(im.crop((0,im.height//2,im.width,im.height)).resize((256,128))).astype(float)
    m['flat_ground_score']=flat_ground_score(lower)
    if m['clip_white_pct']>g['max_clip_white_pct']: res['fails'].append(f"clipped white {m['clip_white_pct']:.2f}%")
    if m['crush_black_pct']>g['max_crush_black_pct']: res['fails'].append(f"crushed black {m['crush_black_pct']:.2f}%")
    if m['mean_chroma']<g['min_mean_chroma']: res['fails'].append(f"too grey: chroma {m['mean_chroma']:.1f}")
    if m['flat_ground_score']>g['max_flat_ground_score']: res['fails'].append(f"flat or checker ground: top-2 colours cover {m['flat_ground_score']:.2f} of lower half")
    cam=os.path.splitext(os.path.basename(png))[0]; cs=spec['cameras'].get(cam,{})
    hits={}
    for h in cs.get('must_hit',[]):
        d=np.linalg.norm(lab-to_lab(hex2rgb(h)[None])[0],axis=1); hits[h]=float((d<g['delta_e']).mean()*100)
    m['must_hit_pct']=hits; n_ok=sum(v>=g['min_hit_pct'] for v in hits.values())
    if hits and n_ok<cs.get('min_hits',len(hits)): res['fails'].append(f"palette: {n_ok}/{len(hits)} target hexes present (need {cs.get('min_hits')})")
    for h in g['forbid']+cs.get('forbid',[]):
        d=np.linalg.norm(lab-to_lab(hex2rgb(h)[None])[0],axis=1); p=float((d<6).mean()*100)
        if p>g['max_forbid_pct']: res['fails'].append(f"forbidden colour {h} covers {p:.1f}%")
    if audit:
        per=audit.get(cam,{}); scene=audit.get('scene',{})
        for k in ('placeholders','checker_textures','spike_meshes'):
            v=scene.get(k,[])+per.get(k,[])
            if v: res['fails'].append(f"{k}: {len(v)} e.g. {v[:3]}")
        if per.get('label_overlaps'): res['fails'].append(f"label_overlaps: {per['label_overlaps'][:3]}")
    res['pass']=not res['fails']; return res
if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('dir'); ap.add_argument('--spec',default=os.path.join(os.path.dirname(os.path.abspath(__file__)),'signoff_spec.json'))
    A=ap.parse_args(); spec=json.load(open(A.spec))
    ap_=os.path.join(A.dir,'scene_audit.json'); audit=json.load(open(ap_)) if os.path.exists(ap_) else None
    out=[check(p,spec,audit) for p in sorted(glob.glob(os.path.join(A.dir,'*.png')))]
    for cam,v in (audit or {}).items():
        if isinstance(v,dict) and v.get('error'): out.append({'file':cam+'.png','fails':[v['error']],'metrics':{},'pass':False})
    for cam in spec['cameras']:
        if not any(os.path.basename(r['file']).startswith(cam) for r in out): out.append({'file':cam+'.png','fails':['not captured'],'metrics':{},'pass':False})
    for r in out: print(('PASS ' if r['pass'] else 'FAIL ')+os.path.basename(r['file'])+('' if r['pass'] else '  <- '+'; '.join(r['fails'])))
    json.dump(out,open(os.path.join(A.dir,'signoff_report.json'),'w'),indent=1)
    sys.exit(0 if all(r['pass'] for r in out) else 1)
