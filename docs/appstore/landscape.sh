#!/bin/bash
# Header (3840 × 1646) och sökresultat (1920 × 1280) från de råa skärmdumparna.
set -euo pipefail
cd "$(dirname "$0")"
source <(sed -n '/^phone()/,/^}/p' build.sh)
ICON=/Users/jesper/Code/Sophamtning-release/iOS/Sophamtning/Assets.xcassets/AppIcon.appiconset/AppIcon.png
TITLE_FONT=$(pwd)/tmp/Fredoka-600.ttf
TEXT_FONT=$(pwd)/tmp/Nunito-600.ttf

# Header: tre telefoner, den mittersta högst, nederkanten utanför bilden.
magick -size 3840x1646 gradient:'#1B8A52'-'#0D5530' tmp/hbg.png
phone raw/6-widget.png tmp/hp1.png 760
phone raw/1-hem.png tmp/hp2.png 820
phone raw/2-adress.png tmp/hp3.png 760
magick tmp/hbg.png \
  tmp/hp1.png -gravity north -geometry -900+260 -composite \
  tmp/hp3.png -gravity north -geometry +900+260 -composite \
  tmp/hp2.png -gravity north -geometry +0+140 -composite \
  -crop 3840x1646+0+0 +repage -alpha off -depth 8 out/header-3840x1646.png

# Sökresultat: ikon och text till vänster, två telefoner till höger.
magick -size 1920x1280 gradient:'#1B8A52'-'#0D5530' tmp/sbg.png
magick "$ICON" -resize 220x220 -alpha set \( -size 220x220 xc:none -fill white -draw "roundrectangle 0,0,219,219,50,50" \) -compose DstIn -composite tmp/icon.png
magick -background none -fill white -font "$TITLE_FONT" -pointsize 104 label:"Sophämtning" tmp/stitle.png
magick -background none -fill '#D9F2E3' -font "$TEXT_FONT" -pointsize 50 -interline-spacing 8 label:$'Se när sopkärlen töms.\nPåminnelse, Live Activity\noch widget.' tmp/stext.png
phone raw/1-hem.png tmp/sp1.png 470
phone raw/4-lasskarm.png tmp/sp2.png 470
magick tmp/sbg.png \
  tmp/icon.png -gravity northwest -geometry +130+300 -composite \
  tmp/stitle.png -gravity northwest -geometry +125+560 -composite \
  tmp/stext.png -gravity northwest -geometry +130+720 -composite \
  tmp/sp2.png -gravity northwest -geometry +1290+170 -composite \
  tmp/sp1.png -gravity northwest -geometry +880+110 -composite \
  -crop 1920x1280+0+0 +repage -alpha off -depth 8 out/sokresultat-1920x1280.png
echo klart
