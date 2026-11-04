from pathlib import Path
from PIL import Image
import json

root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'manifest.json').read_text())
results={'skins':{},'failures':[]}
for skin,data in manifest['skins'].items():
    count=0
    for name,asset in data['assets'].items():
        for scale,path in asset['files'].items():
            factor=int(scale[:-1]);im=Image.open(root/skin/path)
            expected=tuple(v*factor for v in asset['size_points'])
            if im.size!=expected:results['failures'].append(f'{skin}/{name}/{scale}: dimensions')
            if im.mode!='RGBA':results['failures'].append(f'{skin}/{name}/{scale}: missing alpha')
            catalog=root/'QLMSkins.xcassets'/(asset['asset_catalog_name']+'.imageset')
            c=json.loads((catalog/'Contents.json').read_text())
            record=[r for r in c['images'] if r['scale']==scale]
            if not record or not (catalog/record[0]['filename']).exists():results['failures'].append(f'{skin}/{name}/{scale}: catalog')
            count+=1
        source=root/skin/asset['source']
        if source.suffix=='.svg' and '<text' in source.read_text():results['failures'].append(f'{skin}/{name}: text in asset')
    for name in ['knob-pointer','knob-shadow','knob-body-normal','knob-body-hover','knob-body-pressed','knob-body-disabled']:
        if data['assets'][name].get('pivot_points')!=[72,72]:results['failures'].append(f'{skin}/{name}: pivot')
    buttons=[a['size_points'] for n,a in data['assets'].items() if n.startswith('button-')]
    if any(v!=[174,40] for v in buttons):results['failures'].append(f'{skin}: state canvas differs')
    results['skins'][skin]={'asset_count':len(data['assets']),'png_count':count,'state_canvas_points':[174,40],'knob_pivot_points':[72,72]}
results['passed']=not results['failures']
(root/'validation.json').write_text(json.dumps(results,indent=2)+'\n')
print(json.dumps(results,indent=2))
raise SystemExit(0 if results['passed'] else 1)
