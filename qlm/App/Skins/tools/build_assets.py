from pathlib import Path
import base64, io, json, math, re, shutil, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

ROOT = Path(__file__).resolve().parents[1]
S = 2
STATES = ['normal', 'hover', 'pressed', 'selected', 'selected-hover', 'selected-pressed', 'disabled', 'selected-disabled']
MANIFEST = {'version': 1, 'coordinate_system': 'top-left, logical points', 'scales': [1, 2], 'skins': {}}
FONT = '/System/Library/Fonts/Supplemental/Arial.ttf'
MONO = '/System/Library/Fonts/Menlo.ttc'

def data_uri(im):
    buf = io.BytesIO(); im.save(buf, format='PNG')
    return 'data:image/png;base64,' + base64.b64encode(buf.getvalue()).decode()

def svg(w, h, content, defs=''):
    return f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs>{defs}</defs>{content}</svg>'

def grad(name, first, last, diagonal=False):
    return f'<linearGradient id="{name}" x1="0" y1="0" x2="{1 if diagonal else 0}" y2="1">' + f'<stop stop-color="{first}"/><stop offset="1" stop-color="{last}"/></linearGradient>'

def embedded(im, x, y, w, h, extra=''):
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" preserveAspectRatio="none" xlink:href="{data_uri(im)}" {extra}/>'

def alpha_cleanup(im, cutoff=8):
    a = np.array(im.convert('RGBA'))
    a[:, :, 3] = np.where(a[:, :, 3] < cutoff, 0, a[:, :, 3])
    a[a[:, :, 3] == 0, :3] = 0
    return Image.fromarray(a)

def alpha_tight(im, threshold=16):
    box = im.getchannel('A').point(lambda a: 255 if a > threshold else 0).getbbox()
    return im.crop(box), box

def rounded_mask(size, box, radius):
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius, fill=255)
    return mask

def brightness(im, value):
    result = ImageEnhance.Brightness(im.convert('RGB')).enhance(value).convert('RGBA')
    result.putalpha(im.getchannel('A')); return result

def tint(im, color, opacity):
    colored = Image.new('RGB', im.size, color)
    result = Image.blend(im.convert('RGB'), colored, opacity).convert('RGBA')
    result.putalpha(im.getchannel('A')); return result

def write_asset(skin, name, size, source, *, caps=None, pivot=None, note=None):
    w, h = size
    entry = {'size_points': [w, h], 'files': {}, 'source': f'masters/{name}.svg' if isinstance(source, str) else f'masters/{name}.png'}
    if caps: entry['cap_insets'] = dict(zip(['top','left','bottom','right'], caps))
    if pivot: entry['pivot_points'] = list(pivot)
    if note: entry['note'] = note
    entry['asset_catalog_name'] = f'QLM{skin.replace("-", " ").title().replace(" ", "")}_{name}'
    folder = ROOT / skin
    for sub in ['png', 'masters']: (folder/sub).mkdir(parents=True, exist_ok=True)
    master = folder/entry['source']
    if isinstance(source, str): master.write_text(source)
    else: source.save(master)
    aset = ROOT/'QLMSkins.xcassets'/f'{entry["asset_catalog_name"]}.imageset'
    aset.mkdir(parents=True, exist_ok=True)
    catalog=[]
    for scale in [1, 2]:
        file = f'{name}{"@2x" if scale==2 else ""}.png'
        target = folder/'png'/file
        if isinstance(source,str):
            subprocess.run(['rsvg-convert', '-w', str(w*scale), '-h', str(h*scale), '-o', str(target), str(master)],check=True)
        else:
            source.resize((w*scale,h*scale),Image.Resampling.LANCZOS).save(target)
        im=Image.open(target).convert('RGBA')
        im.save(target)
        shutil.copy2(target, aset/file)
        catalog.append({'idiom':'mac','filename':file,'scale':f'{scale}x'})
        entry['files'][f'{scale}x']=f'png/{file}'
    (aset/'Contents.json').write_text(json.dumps({'images':catalog,'info':{'version':1,'author':'qlm'}},indent=2)+'\n')
    MANIFEST['skins'][skin]['assets'][name]=entry

wood_source=(ROOT/'sources/vintage-reference.html').read_text()
wood_data=re.search(r'--wood-texture:url\(data:image/png;base64,([^)]*)',wood_source).group(1)
wood=Image.open(io.BytesIO(base64.b64decode(wood_data))).convert('RGBA')
atlas=Image.open(ROOT/'sources/walnut-components-master.png').convert('RGBA')
panel=alpha_cleanup(Image.open(ROOT/'sources/walnut-panel-master.png').convert('RGBA'))
panel,panelbox=alpha_tight(panel,16)
# The atlas cells use the same source crop for every state.
button=atlas.crop((54,172,580,294))
button=alpha_cleanup(button)
glass=alpha_cleanup(atlas.crop((658,114,1207,352)))
knob=alpha_cleanup(atlas.crop((184,510,450,776)))
km=Image.new('L',knob.size,0);ImageDraw.Draw(km).ellipse((1,1,264,264),fill=255)
knob.putalpha(Image.fromarray(np.minimum(np.array(knob.getchannel('A')),np.array(km))))
badge=alpha_cleanup(atlas.crop((764,571,1099,720)))
bm=rounded_mask(badge.size,(2,2,332,145),23)
badge.putalpha(Image.fromarray(np.minimum(np.array(badge.getchannel('A')),np.array(bm))))
osd=alpha_cleanup(atlas.crop((37,974,593,1146)))
led=alpha_cleanup(atlas.crop((879,1000,983,1107)))
for name,im in [('button',button),('display',glass),('knob',knob),('badge',badge),('osd',osd),('led',led)]:
    (ROOT/'sources/extracted').mkdir(exist_ok=True); im.save(ROOT/'sources/extracted'/f'{name}.png')

layout={
 'panel_size':[640,480], 'osd_size':[300,72],
 'layers':[
  {'asset':'panel-background','frame':[0,0,640,480]},
  {'asset':'panel-markings','frame':[0,0,640,480]},
  {'asset':'nameplate','frame':[48,27,78,38]},
  {'asset':'button-normal','frame':[48,120,174,40],'role':'setup-main'},
  {'asset':'button-normal','frame':[234,120,174,40],'role':'setup-nearfield'},
  {'asset':'button-normal','frame':[420,120,174,40],'role':'setup-full-range'},
  {'asset':'display-glass','frame':[48,184,356,132]},
  {'asset':'button-normal','frame':[48,338,174,40],'role':'mute'},
  {'asset':'button-normal','frame':[230,338,174,40],'role':'dim'},
  {'asset':'knob-shadow','frame':[436,178,144,144]},
  {'asset':'knob-ticks','frame':[420,162,176,176]},
  {'asset':'knob-body-normal','frame':[436,178,144,144]},
  {'asset':'knob-pointer','frame':[436,178,144,144],'rotation_degrees':70.2},
 ],
 'text':[
  {'text':'qlm.','frame':[48,30,78,32],'font':'Helvetica Neue','size':24,'weight':'bold-italic','alignment':'center','color':'badgeInk'},
  {'text':'6 ONLINE','frame':[529,37,70,16],'font':'Menlo','size':10,'color':'secondary'},
  {'text':'LISTENING SETUP','frame':[53,101,131,18],'font':'Helvetica Neue','size':10,'weight':'medium','color':'label'},
  {'text':'MAIN','frame':[48,130,174,19],'size':11,'alignment':'center','color':'label'},
  {'text':'NEARFIELD','frame':[234,130,174,19],'size':11,'alignment':'center','color':'label'},
  {'text':'FULL RANGE','frame':[420,130,174,19],'size':11,'alignment':'center','color':'label'},
  {'text':'MAIN','frame':[67,197,90,16],'font':'Menlo','size':10,'color':'display'},
  {'text':'LEVEL','frame':[346,197,48,16],'font':'Menlo','size':10,'color':'display'},
  {'text':'−42.0','frame':[67,219,213,65],'font':'Menlo','size':45,'color':'display'},
  {'text':'dB','frame':[216,248,34,19],'size':12,'color':'display'},
  {'text':'OUTPUT −42.0','frame':[67,279,140,15],'font':'Menlo','size':9,'color':'display'},
  {'text':'MAX −30','frame':[328,279,63,15],'font':'Menlo','size':9,'color':'display'},
  {'text':'MUTE','frame':[48,348,174,18],'size':11,'alignment':'center','color':'label'},
  {'text':'DIM −20','frame':[230,348,174,18],'size':11,'alignment':'center','color':'label'},
  {'text':'−80','frame':[430,325,40,16],'font':'Menlo','size':9,'color':'secondary'},
  {'text':'−30','frame':[554,325,40,16],'font':'Menlo','size':9,'color':'secondary'},
  {'text':'VOLUME','frame':[474,351,69,18],'size':10,'alignment':'center','color':'secondary'},
  {'text':'−','frame':[445,348,22,22],'size':16,'alignment':'center','color':'label'},
  {'text':'+','frame':[550,348,22,22],'size':16,'alignment':'center','color':'label'},
  {'text':'Monitors','frame':[66,411,94,21],'size':11,'color':'label'},
  {'text':'MAIN · ACTIVE','frame':[290,414,140,18],'font':'Menlo','size':9,'color':'secondary'},
  {'text':'Standby','frame':[550,411,64,21],'size':11,'color':'label'},
 ],
 'indicator_frames':{'online':[514,37,16,16],'setup-main':[76,131,16,16],'mute':[76,348,16,16]},
 'knob':{'minimum_db':-80,'maximum_db':-30,'step_db':0.5,'start_degrees':-135,'end_degrees':135,'reference_direction':'pointer points up at zero rotation','clockwise':True,'pivot_in_asset':[72,72],'body_must_not_rotate':True},
 'symbols':{'monitors':'slider.horizontal.3','standby':'power','volume_up':'plus','volume_down':'minus'},
 'osd':{'background':[0,0,300,72],'level':[22,18,116,38],'setup':[145,15,136,18],'status':[145,34,136,15],'track':[145,52,130,3]},
}

for skin in ['vintage','retro']:
    real=skin=='retro'
    palette={'label':'#dfd4b9' if not real else '#efe1bd','secondary':'#bdb39c' if not real else '#cabd9e','display':'#ec9179' if not real else '#ff702c','badgeInk':'#34352b','focus':'#f4c57b','panel':'#34342d' if not real else '#332d26'}
    MANIFEST['skins'][skin]={'assets':{},'palette':palette,'layout':layout,'source_kind':'raster material assets with deterministic state transforms' if real else 'vector reconstruction of the original HTML design'}
    wood_def='<pattern id="wood" width="20" height="480" patternUnits="userSpaceOnUse">'+embedded(wood,0,0,20,480)+'</pattern>'
    wood_horizontal=wood.rotate(90,expand=True)
    if real:
        write_asset(skin,'panel-background',(640,480),panel,caps=(22,32,48,32),note='Fixed-size use preferred. Caps preserve wood cheeks and base rail when stretched.')
    else:
        d=wood_def+grad('face','#3d3c33','#30322b',True)+grad('edge','#ffffff33','#00000066')
        body='<rect x="0.5" y="0.5" width="639" height="479" rx="3" fill="#352c20" stroke="#795c40"/>'
        body+='<rect x="16" y="5" width="608" height="451" fill="url(#face)" stroke="#29291f"/>'
        body+=embedded(wood_horizontal,1,457,638,22)
        body+='<path d="M16 6H624M16 455H624" stroke="#a2835a" stroke-opacity=".6"/>'
        for x in [0,624]:
            body+=f'<rect x="{x}" y="0" width="16" height="480" fill="url(#wood)"/><rect x="{x}" y="0" width="16" height="480" fill="url(#edge)"/>'
        for x in [29,611]:
            body+=f'<circle cx="{x}" cy="16" r="2.8" fill="#33372b" stroke="#777660" stroke-width=".7"/><path d="M{x-1.5} 17.5l3 -3" stroke="#151b10"/>'
        write_asset(skin,'panel-background',(640,480),svg(640,480,body,d),caps=(22,24,30,24))
    marks='<g fill="none" stroke="'+palette['label']+'" stroke-opacity=".8" stroke-width=".8">'
    marks+='<path d="M48 86H594M184 110H595Q600 110 600 115V166Q600 172 594 172H46Q40 172 40 166V116Q40 110 46 110H50"/>'
    marks+='<rect x="40" y="330" width="372" height="56" rx="5"/><path d="M48 400H594"/></g>'
    write_asset(skin,'panel-markings',(640,480),svg(640,480,marks),note='No text. Gap in setup frame is reserved for the native label.')
    if real:
        write_asset(skin,'display-glass',(356,132),glass,caps=(12,12,12,12),note='Source crop is 549×238 pixels. 2x normalization resamples it; use at the specified point size.')
        write_asset(skin,'nameplate',(78,38),badge,caps=(8,8,8,8))
        write_asset(skin,'osd-background',(300,72),osd,caps=(12,14,12,14))
    else:
        dg=grad('ruby','#40251d','#211b13',True)
        glass_svg=svg(356,132,'<rect x=".5" y=".5" width="355" height="131" rx="2" fill="#25251c" stroke="#65563f"/><rect x="3" y="3" width="350" height="126" fill="url(#ruby)" stroke="#161c12" stroke-width="2"/><path d="M4 129H352" stroke="#a48c5b" stroke-opacity=".25"/>',dg)
        write_asset(skin,'display-glass',(356,132),glass_svg,caps=(6,6,6,6))
        bd=grad('ivory','#e8dfc9','#bbb194')
        write_asset(skin,'nameplate',(78,38),svg(78,38,'<rect x="2" y="4" width="74" height="33" rx="3" fill="#000" opacity=".25"/><rect x="1" y="1" width="76" height="33" rx="3" fill="url(#ivory)" stroke="#a59a7c"/><path d="M5 2H73" stroke="#f7f0db"/>',bd),caps=(6,6,7,6))
        ob=embedded(wood_horizontal,0,0,300,72)+'<rect x="5" y="5" width="290" height="62" fill="#302b21" stroke="#5c4330"/>'
        write_asset(skin,'osd-background',(300,72),svg(300,72,ob),caps=(8,9,8,9))
    for state in STATES:
        selected=state.startswith('selected')
        hover='hover' in state
        pressed='pressed' in state
        disabled='disabled' in state
        if real:
            # Use a shared crop and transform inside a fixed canvas.
            b=button.copy()
            if selected:b=tint(b,'#9e6440',.12)
            if hover:b=brightness(b,1.10)
            if pressed:b=brightness(b,.81)
            if disabled:
                b=tint(b,'#55524b',.48)
                b.putalpha(b.getchannel('A').point(lambda a:round(a*.5)))
            canvas=Image.new('RGBA',(348,80))
            resized=b.resize((344,74 if not pressed else 70),Image.Resampling.LANCZOS)
            canvas.alpha_composite(resized,(2,2 if not pressed else 6))
            write_asset(skin,'button-'+state,(174,40),canvas,caps=(9,12,10,12))
        else:
            top,bottom=('#4c4536','#353022') if selected else ('#383d31','#252b20')
            if hover:top,bottom=('#625441','#453d2b') if selected else ('#484d40','#30372a')
            if pressed:top,bottom=('#322d22','#494030') if selected else ('#252b21','#383f30')
            d=grad('button',top,bottom)
            y=4 if pressed else 2
            alpha=.45 if disabled else 1
            b=f'<g opacity="{alpha}"><rect x="2" y="{y+3}" width="170" height="33" rx="2" fill="#000" opacity=".27"/><rect x="2" y="{y}" width="170" height="33" rx="2" fill="url(#button)" stroke="#171d12" stroke-width="1.2"/>'
            b+=f'<path d="M5 {y+1}H169" stroke="#a4a589" stroke-opacity="{.12 if pressed else .27}"/></g>'
            write_asset(skin,'button-'+state,(174,40),svg(174,40,b,d),caps=(8,8,9,8))
    focus=svg(174,40,'<rect x=".8" y=".8" width="172.4" height="38.4" rx="4" fill="none" stroke="'+palette['focus']+'" stroke-width="1.5"/>')
    write_asset(skin,'button-focus-ring',(174,40),focus,caps=(8,8,8,8),note='Overlay any enabled state. Do not replace its base artwork.')
    shadowdefs='<radialGradient id="shadow"><stop stop-color="#000" stop-opacity=".42"/><stop offset=".75" stop-color="#000" stop-opacity=".24"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>'
    write_asset(skin,'knob-shadow',(144,144),svg(144,144,'<ellipse cx="74" cy="79" rx="65" ry="63" fill="url(#shadow)"/>',shadowdefs),pivot=(72,72))
    for state in ['normal','hover','pressed','disabled']:
        if real:
            b=knob.copy()
            if state=='hover':b=brightness(b,1.08)
            if state=='pressed':b=brightness(b,.91)
            if state=='disabled':b.putalpha(b.getchannel('A').point(lambda a:round(a*.45)))
            c=Image.new('RGBA',(288,288));c.alpha_composite(b.resize((224,224),Image.Resampling.LANCZOS),(32,32))
            write_asset(skin,'knob-body-'+state,(144,144),c,pivot=(72,72))
        else:
            first,last=('#494c40','#2c3325')
            if state=='hover':first,last=('#55594a','#353d2b')
            if state=='pressed':first,last=('#3d4234','#262e20')
            alpha=.45 if state=='disabled' else 1
            d=grad('knob',first,last,True)
            c=f'<g opacity="{alpha}"><circle cx="72" cy="72" r="48" fill="url(#knob)" stroke="#1d2617"/><path d="M30 53A45 45 0 0 1 109 45" fill="none" stroke="#c5c0a1" stroke-opacity=".13"/></g>'
            write_asset(skin,'knob-body-'+state,(144,144),svg(144,144,c,d),pivot=(72,72))
    for name,opacity in [('knob-pointer',1),('knob-pointer-disabled',.4)]:
        top=31 if real else 34
        pointer=f'<path d="M72 {top}V53" stroke="#e8e0c6" stroke-width="{2.1 if real else 1.6}" stroke-linecap="round" opacity="{opacity}"/>'
        write_asset(skin,name,(144,144),svg(144,144,pointer),pivot=(72,72),note='Rotate this layer only. Clockwise angle in top-left coordinates. Body and shadow stay fixed.')
    ticks=''
    for i in range(11):
        angle=math.radians(-135+i*27)
        r0,r1=73,78 if i%5==0 else 77
        x0,y0=88+math.sin(angle)*r0,88-math.cos(angle)*r0
        x1,y1=88+math.sin(angle)*r1,88-math.cos(angle)*r1
        ticks+=f'<path d="M{x0:.3f} {y0:.3f}L{x1:.3f} {y1:.3f}"/>'
    write_asset(skin,'knob-ticks',(176,176),svg(176,176,'<g stroke="'+palette['label']+'" stroke-width=".9" opacity=".85">'+ticks+'</g>'),pivot=(88,88))
    write_asset(skin,'knob-focus-ring',(144,144),svg(144,144,'<circle cx="72" cy="72" r="61" fill="none" stroke="'+palette['focus']+'" stroke-width="1.2"/>'),pivot=(72,72))
    for state in ['on','off','disabled']:
        if real and state=='on':
            write_asset(skin,'led-'+state,(16,16),led)
        else:
            color=('#ef7654' if not real else '#e96840') if state=='on' else '#53463a'
            d=grad('lens',('#ffbf91' if state=='on' else '#796956'),color,True)
            content=''
            if state=='on':
                content+='<circle cx="8" cy="8" r="7" fill="#dd4b20" opacity=".08"/><circle cx="8" cy="8" r="4.5" fill="#e66a30" opacity=".18"/>'
            content+='<g opacity="'+('.4' if state=='disabled' else '1')+'"><circle cx="8" cy="8" r="2.6" fill="url(#lens)" stroke="#1c1812" stroke-width=".6"/><circle cx="7.3" cy="7.2" r=".6" fill="#ffe4bb" opacity=".5"/></g>'
            write_asset(skin,'led-'+state,(16,16),svg(16,16,content,d))
    for name,opacity in [('osd-track',.25),('osd-fill',1)]:
        write_asset(skin,name,(130,3),svg(130,3,f'<rect width="130" height="3" rx="1.5" fill="{palette["display"]}" opacity="{opacity}"/>'),caps=(1,2,1,2))
    write_asset(skin,'display-disabled-overlay',(356,132),svg(356,132,'<rect x="3" y="3" width="350" height="126" rx="2" fill="#11150e" opacity=".45"/>'))
    write_asset(skin,'osd-disabled-overlay',(300,72),svg(300,72,'<rect x="5" y="5" width="290" height="62" rx="2" fill="#11150e" opacity=".45"/>'))
    (ROOT/skin/'layout.json').write_text(json.dumps({'palette':palette,**layout},indent=2)+'\n')

(ROOT/'QLMSkins.xcassets/Contents.json').write_text(json.dumps({'info':{'version':1,'author':'qlm'}},indent=2)+'\n')
(ROOT/'manifest.json').write_text(json.dumps(MANIFEST,indent=2)+'\n')

# Assembly previews contain labels. Exported production assets contain none.
def load(skin,name):return Image.open(ROOT/skin/'png'/f'{name}@2x.png').convert('RGBA')
def font(size,mono=False):return ImageFont.truetype(MONO if mono else FONT,round(size*2))
def label(im,text,rect,size,color,align='left',mono=False):
    x,y,w,h=rect;d=ImageDraw.Draw(im);f=font(size,mono)
    box=d.textbbox((0,0),text,font=f);tw=box[2]-box[0];th=box[3]-box[1]
    px=x*2+(w*2-tw)/2 if align=='center' else x*2
    py=y*2+(h*2-th)/2-box[1]
    d.text((px,py),text,font=f,fill=color)
for skin,data in MANIFEST['skins'].items():
    p=data['palette'];preview=Image.new('RGBA',(1280,960))
    for layer in layout['layers']:
        im=load(skin,layer['asset']);x,y,w,h=layer['frame']
        if layer.get('role')=='setup-main':im=load(skin,'button-selected')
        if layer['asset']=='knob-pointer':im=im.rotate(-70.2,resample=Image.Resampling.BICUBIC)
        preview.alpha_composite(im,(x*2,y*2))
    for text in layout['text']:
        label(preview,text['text'],text['frame'],text['size'],p[text['color']],text.get('alignment','left'),text.get('font')=='Menlo')
    for role,frame in layout['indicator_frames'].items():
        x,y,w,h=frame;preview.alpha_composite(load(skin,'led-off' if role=='mute' else 'led-on'),(x*2,y*2))
    preview.save(ROOT/skin/'preview-assembled@2x.png')
    blank=Image.new('RGBA',(1280,960))
    for layer in layout['layers']:
        im=load(skin,layer['asset']);x,y,w,h=layer['frame']
        if layer['asset']=='knob-pointer':im=im.rotate(-70.2,resample=Image.Resampling.BICUBIC)
        blank.alpha_composite(im,(x*2,y*2))
    blank.save(ROOT/skin/'preview-textless@2x.png')
    preview_osd=load(skin,'osd-background')
    label(preview_osd,'−42.0',[21,17,102,38],24,p['display'],mono=True)
    label(preview_osd,'dB',[108,31,20,18],9,p['display'])
    label(preview_osd,'Main monitors',[149,13,136,18],11,p['label'])
    label(preview_osd,'qlm · Output level',[149,32,136,17],9,p['secondary'])
    preview_osd.alpha_composite(load(skin,'osd-track'),(290,104))
    preview_osd.alpha_composite(load(skin,'osd-fill').crop((0,0,198,6)),(290,104))
    preview_osd.save(ROOT/skin/'preview-osd@2x.png')
    sheet=Image.new('RGBA',(1280,1420),'#22251f')
    d=ImageDraw.Draw(sheet); d.text((40,25),skin.replace('-',' ').title(),font=font(22),fill='#eee6cf')
    small=preview.resize((768,576),Image.Resampling.LANCZOS);sheet.alpha_composite(small,(40,100))
    o=preview_osd.resize((360,86),Image.Resampling.LANCZOS);sheet.alpha_composite(o,(860,170))
    d.text((860,125),'OSD',font=font(12),fill='#ccc3ae')
    for i,state in enumerate(STATES):
        x=40+(i%4)*310;y=740+(i//4)*142
        d.text((x,y-35),state,font=font(11),fill='#ccc3ae')
        b=load(skin,'button-'+state).resize((261,60),Image.Resampling.LANCZOS);sheet.alpha_composite(b,(x,y))
    for i,name in enumerate(['knob-body-normal','knob-pointer','knob-shadow','knob-ticks']):
        x=40+i*310;y=1100
        d.text((x,y-38),name,font=font(10),fill='#ccc3ae')
        im=load(skin,name);im.thumbnail((220,220),Image.Resampling.LANCZOS);sheet.alpha_composite(im,(x,y))
    sheet.convert('RGB').save(ROOT/skin/'contact-sheet.jpg',quality=94)
print('Built',sum(len(v['assets']) for v in MANIFEST['skins'].values()),'assets; each at 1x and 2x.')
