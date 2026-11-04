from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, zipfile, hashlib
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'manifest.json').read_text())
font=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf',20)
qa=root/'qa';qa.mkdir(exist_ok=True)
for skin in manifest['skins']:
    names=['button-normal','button-selected','button-disabled','nameplate','display-glass','knob-body-normal','knob-pointer','led-on','osd-background']
    sheet=Image.new('RGB',(1200,len(names)*175),'#bdbdbd');d=ImageDraw.Draw(sheet)
    for i,name in enumerate(names):
        y=i*175
        d.rectangle((0,y,599,y+174),fill='#f3f3f3');d.rectangle((600,y,1199,y+174),fill='#151515')
        for x,color in [(20,'#303030'),(620,'#e0e0e0')]:d.text((x,y+10),name,font=font,fill=color)
        im=Image.open(root/skin/'png'/(name+'@2x.png')).convert('RGBA');im.thumbnail((500,120),Image.Resampling.LANCZOS)
        for x in [35,635]:sheet.paste(im,(x,y+43),im)
    sheet.save(qa/(skin+'-alpha-check.png'))
comparison=Image.new('RGB',(1320,660),'#22251f')
d=ImageDraw.Draw(comparison)
for i,skin in enumerate(manifest['skins']):
    x=20+i*650
    d.text((x,18),skin.replace('-',' ').title(),font=font,fill='#eee6cf')
    panel=Image.open(root/skin/'preview-textless@2x.png').convert('RGBA').resize((630,473),Image.Resampling.LANCZOS)
    comparison.paste(panel,(x,60),panel)
    osd=Image.open(root/skin/'png/osd-background@2x.png').convert('RGBA').resize((300,72),Image.Resampling.LANCZOS)
    comparison.paste(osd,(x+165,560),osd)
comparison.save(root/'textless-skins-preview.jpg',quality=94)
# Use separate skin catalogs; their asset names remain unique when combined.
common=['README.txt','manifest.json','validation.json']
for skin,data in manifest['skins'].items():
    target=root.parent/(skin+'-assets.zip')
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
        for p in sorted((root/skin).rglob('*')):
            if p.is_file():z.write(p,p.relative_to(root))
        z.write(root/'QLMSkins.xcassets/Contents.json','QLMSkins.xcassets/Contents.json')
        for asset in data['assets'].values():
            for p in sorted((root/'QLMSkins.xcassets'/(asset['asset_catalog_name']+'.imageset')).iterdir()):z.write(p,p.relative_to(root))
        for p in (root/'appkit').iterdir():z.write(p,p.relative_to(root))
        z.writestr('manifest.json',json.dumps({**manifest,'skins':{skin:data}},indent=2)+'\n')
        readme='This is the '+skin+'-only archive. The shared guide below describes the complete kit.\nThe rebuild tools and source references are in the complete bundle.\n\n'+(root/'README.txt').read_text()
        z.writestr('README.txt',readme)
        z.write(root/'validation.json','validation.json')
        z.write(qa/(skin+'-alpha-check.png'),'qa/alpha-check.png')
    print(target.name,target.stat().st_size)
checksums={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*.png')) if 'qa/catalog' not in str(p)}
(root/'checksums.json').write_text(json.dumps(checksums,indent=2)+'\n')
target=root.parent/'qlm-skin-assets-complete.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=7) as z:
    for p in sorted(root.rglob('*')):
        if p.is_file() and 'qa/catalog' not in str(p):z.write(p,p.relative_to(root))
print(target.name,target.stat().st_size)
