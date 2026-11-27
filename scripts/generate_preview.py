#!/usr/bin/env python3
"""Draw a UI design reference. This is NOT a screenshot of the native app.
EXIF in this composition is illustrative. Requires Pillow only.
"""
from pathlib import Path
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SCALE = 2
W, H = 1600, 1100
FONT_PATHS = ["/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
              "/System/Library/Fonts/PingFang.ttc", "/System/Library/Fonts/Helvetica.ttc"]
FONT = next((p for p in FONT_PATHS if Path(p).exists()), None)
ACCENT = "#d6bd8f"
TEXT = "#e4e5e7"
MUTED = "#818389"


@lru_cache(maxsize=64)
def font(size):
    return ImageFont.truetype(FONT, round(size * SCALE)) if FONT else ImageFont.load_default()


def main():
    image = Image.new("RGB", (W * SCALE, H * SCALE), "#0a0b0e")
    draw = ImageDraw.Draw(image)

    def rect(box, fill, radius=0, outline=None, width=1):
        box = tuple(round(x * SCALE) for x in box)
        if radius:
            draw.rounded_rectangle(box, radius=round(radius * SCALE), fill=fill, outline=outline, width=width * SCALE)
        else:
            draw.rectangle(box, fill=fill, outline=outline, width=width * SCALE)

    def text(x, y, value, size=12, color=TEXT, anchor="lt"):
        draw.text((x * SCALE, y * SCALE), value, font=font(size), fill=color, anchor=anchor)

    def line(points, color=MUTED, width=1):
        draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color, width=round(width * SCALE))

    def circle(x, y, r, fill=None, outline=None, width=1):
        draw.ellipse(((x-r)*SCALE, (y-r)*SCALE, (x+r)*SCALE, (y+r)*SCALE), fill=fill, outline=outline, width=width*SCALE)

    def icon(x, y, kind, color=MUTED):
        if kind == "left": line([(x+3, y-5), (x-2, y), (x+3, y+5)], color, 1.4)
        elif kind == "right": line([(x-3, y-5), (x+2, y), (x-3, y+5)], color, 1.4)
        elif kind == "folder":
            line([(x-8,y+6),(x-8,y-6),(x-2,y-6),(x+1,y-3),(x+8,y-3),(x+8,y+6),(x-8,y+6)],color,1.2)
        elif kind == "info":
            circle(x, y, 7, outline=color)
            circle(x, y-3.5, .7, fill=color)
            line([(x,y-1),(x,y+4)],color,1.2)
        elif kind == "dots":
            for dx in (-5, 0, 5): circle(x+dx, y, .9, fill=color)
        elif kind == "copy":
            rect((x-3,y-6,x+6,y+4),None,2,color)
            line([(x-6,y-3),(x-6,y+7),(x+3,y+7)],color)
        elif kind == "close":
            line([(x-4,y-4),(x+4,y+4)],color,1.2)
            line([(x+4,y-4),(x-4,y+4)],color,1.2)
        elif kind == "lightbox":
            rect((x-7,y-5,x+6,y+5),None,2,color)
            line([(x-4,y-8),(x+9,y-8),(x+9,y+2)],color)

    text(65, 32, "L U M A", 13, ACCENT)
    text(158, 33, "NATIVE IMAGE VIEWER", 10, MUTED)
    text(1535, 33, "Swift  /  AppKit  /  SwiftUI", 10, MUTED, "rt")

    # Window shadow and chrome.
    shadow = Image.new("RGBA", image.size)
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((62*SCALE,100*SCALE,1538*SCALE,1024*SCALE), radius=18*SCALE, fill=(0,0,0,180))
    image.paste(shadow.filter(ImageFilter.GaussianBlur(26*SCALE)), (0,0), shadow.filter(ImageFilter.GaussianBlur(26*SCALE)))
    draw = ImageDraw.Draw(image)
    rect((64, 84, 1536, 1006), "#101114", 14, "#34363c")
    rect((65, 85, 1535, 139), "#191a1d", 13)
    rect((65, 122, 1535, 140), "#191a1d")
    line([(65,140),(1535,140)],"#2a2b30")
    for x, c in [(86,"#ff6058"),(106,"#febc2e"),(126,"#29c840")]: circle(x,112,5.5,fill=c)
    text(157, 101, "Seeply", 18, TEXT)
    line([(216,104),(216,120)],"#3b3c42")
    text(234, 106, "DSC00001.JPG", 11, MUTED)
    icon(1146,112,"folder")
    line([(1173,104),(1173,120)],"#34353b")
    icon(1198,112,"left"); icon(1230,112,"right")
    line([(1257,104),(1257,120)],"#34353b")
    text(1275,105,"FIT",10,ACCENT)
    line([(1331,104),(1331,120)],"#34353b")
    icon(1355,112,"lightbox")
    rect((1380,97,1410,127),"#302c25",7)
    icon(1395,112,"info",ACCENT)
    icon(1436,112,"dots")

    # Photo area. The artwork is procedural and is included in the app's Samples.
    photo = Image.open(ROOT/"Seeply/Resources/Samples/Dune.jpg").convert("RGB")
    photo = photo.resize((996*SCALE,664*SCALE),Image.Resampling.LANCZOS)
    image.paste(photo,(302*SCALE,174*SCALE))
    draw = ImageDraw.Draw(image)
    rect((567,792,1033,825),"#252626",17)
    text(589,802,"35 mm   ·   ƒ/1.4   ·   1/250 s   ·   ISO 100",11,"#c8c7c2")

    # Floating inspector, matching the native SwiftUI component's visual language.
    rect((1199,156,1519,850),"#202125",14,"#3c3d42")
    text(1220,178,"照片資訊",14,TEXT)
    text(1220,203,"DETAILS & EXIF",8,MUTED)
    icon(1461,188,"copy"); icon(1492,188,"close")
    line([(1200,230),(1518,230)],"#33343a")
    for x,label,value in [(1218,"光圈","ƒ/1.4"),(1316,"快門","1/250"),(1414,"ISO","100")]:
        rect((x,250,x+88,324),"#2a2b2f",9)
        text(x+12,262,label,9,MUTED)
        text(x+12,285,value,16,ACCENT)
    text(1220,350,"器材",10,ACCENT)
    for y,label,value in [(378,"相機","SONY ILCE-7M4"),(411,"鏡頭","FE 35mm F1.4 GM")]:
        text(1220,y,label,11,MUTED); text(1292,y,value,11,TEXT)
    text(1220,460,"拍攝",10,ACCENT)
    for y,label,value in [(489,"焦距","35 mm"),(521,"光圈","ƒ/1.4"),(553,"快門","1/250 s"),
                          (585,"ISO","100"),(617,"曝光補償","+0.33 EV"),(649,"白平衡","自動"),
                          (681,"拍攝時間","2026-11-26  14:32")]:
        text(1220,y,label,11,MUTED); text(1292,y,value,11,TEXT)
    line([(1220,718),(1500,718)],"#33343a")
    text(1220,742,"影像與檔案",10,ACCENT)
    text(1220,773,"色彩",11,MUTED); text(1292,773,"Adobe RGB (1998)",11,TEXT)
    text(1220,805,"所有中繼資料  ›",11,MUTED)

    # Filmstrip and status.
    rect((65,874,1535,978),"#191a1d")
    line([(65,874),(1535,874)],"#2c2d32")
    names=["Coast","Dune","Ridge","Coast","Dune","Ridge","Dune"]
    start=493
    for i,name in enumerate(names):
        x=start+i*88
        if i==1: rect((x-4,889,x+76,961),None,7,ACCENT,2)
        thumb=Image.open(ROOT/f"Seeply/Resources/Samples/{name}.jpg").convert("RGB")
        thumb.thumbnail((72*SCALE,60*SCALE),Image.Resampling.LANCZOS)
        image.paste(thumb,(x*SCALE,round(925*SCALE-thumb.height/2)))
    draw=ImageDraw.Draw(image)
    text(86,986,"2 / 7",10,MUTED)
    text(160,986,"7008 × 4672",10,MUTED)
    text(1510,986,"← → 換圖",10,"#65676d","rt")
    text(65,1042,"照片優先。工具，恰到好處。",16,"#b4b2ac")
    text(1535,1051,"視覺設計參考 · 非原生執行截圖 · 拍攝資訊為示範值",11,"#666970","rt")
    destination=ROOT/"Design/Seeply-UI-Concept.png"
    destination.parent.mkdir(exist_ok=True)
    image.resize((W,H),Image.Resampling.LANCZOS).save(destination,optimize=True)
    print(destination)


if __name__=="__main__": main()
