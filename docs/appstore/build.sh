#!/bin/bash
# Sätter ihop App Store-bilderna från de råa skärmdumparna.
set -euo pipefail
cd "$(dirname "$0")"
FONTS=/Users/jesper/Code/Sophamtning-release/iOS/Packages/SophamtningKit/Sources/SophamtningDesign/Resources/Fonts
# Halvfeta versioner av appens typsnitt, gjorda med fonttools varLib.instancer.
TITLE_FONT=$(pwd)/tmp/Fredoka-600.ttf
TEXT_FONT=$(pwd)/tmp/Nunito-600.ttf
mkdir -p out tmp

# Skärmdump i en telefonram: rundade hörn och en mörk kant runt om.
phone() { # in out width
  local in=$1 out=$2 w=$3
  local h=$(( w * 2868 / 1320 ))
  local r=$(( w * 110 / 1060 ))
  local b=$(( w * 22 / 1060 ))
  magick "$in" -resize ${w}x${h}! tmp/s.png
  magick -size ${w}x${h} xc:none -fill white -draw "roundrectangle 0,0,$((w-1)),$((h-1)),$r,$r" tmp/m.png
  magick tmp/s.png tmp/m.png -compose DstIn -composite tmp/sr.png
  local W=$((w + 2*b)) H=$((h + 2*b)) R=$((r + b))
  magick -size ${W}x${H} xc:none -fill '#101814' -draw "roundrectangle 0,0,$((W-1)),$((H-1)),$R,$R" tmp/bezel.png
  magick tmp/bezel.png tmp/sr.png -geometry +${b}+${b} -compose Over -composite \
    \( +clone -background black -shadow 40x40+0+30 \) +swap -background none -layers merge +repage "$out"
}

# Skärmdump för App Store, 1320 × 2868.
shot() { # nr rå titel undertext
  local nr=$1 raw=$2 title=$3 text=$4
  magick -size 1320x2868 gradient:'#1B8A52'-'#0D5530' tmp/bg.png
  magick -background none -fill white -font "$TITLE_FONT" -pointsize 110 -interline-spacing 4 \
    -gravity center label:"$title" tmp/title.png
  magick -background none -fill '#D9F2E3' -font "$TEXT_FONT" -pointsize 52 \
    -gravity center label:"$text" tmp/text.png
  phone "raw/$raw" tmp/phone.png 1000
  # Samma placering på alla bilder: två rader rubrik, en rad text och telefonen under.
  magick tmp/bg.png \
    tmp/title.png -gravity north -geometry +0+150 -composite \
    tmp/text.png -gravity north -geometry +0+470 -composite \
    tmp/phone.png -gravity north -geometry +0+620 -composite \
    -crop 1320x2868+0+0 +repage -alpha off "out/$nr.png"
}

shot 1 1-hem.png $'Se när\nkärlen töms' "Nästa tömning och vilka kärl."
shot 2 2-adress.png $'Hela schemat,\nkärl för kärl' "Med färg och ikon för varje kärl."
shot 3 3-notiser.png $'Påminnelse\nkväll och morgon' "Kvällen före, samma morgon eller båda."
shot 4 4-lasskarm.png $'Live Activity\npå låsskärmen' "Tryck Klart när kärlen står ute."
shot 5 5-morkt.png $'Flera adresser,\nljust och mörkt' "Inget konto och ingen spårning."
shot 6 6-widget.png $'Widget på\nhemskärmen' "Nästa tömning utan att öppna appen."
for f in out/*.png; do magick "$f" -depth 8 "$f"; done
echo klart
