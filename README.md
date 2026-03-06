# Personal mpv conf

This is my personal mpv player's configrations. Feel free to use.

# Scripts:

## Personal

### exiftool_auto_lut

Auto load lut when play SONYU s-log videos (using exiftool to detect metadata)

### hold-speed

Hold `s` to speed up playback

## 3rd-part

### autoload

playlist **autoload**.

From: mpv's [official repo](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua).

### uosc

an elegent and useful **GUI** (specific term is On Screen Controller, OSC) with some utils.

From: [tomasklaen/uosc](https://github.com/tomasklaen/uosc)


### thumbfast

show **thumbnails** on the progress bar.

From: [po5/thumbfast](https://github.com/po5/thumbfast)

### trim

Cut video without decoding/encoding

From: [aerobounce/trim.lua](https://github.com/aerobounce/trim.lua)

```
h for start position
k for end position

duble press h/k for cutting
```

### VR-reversal 360plugin

convert **VR** video to 2d video with control.

From: [dfaker/VR-reversal](https://github.com/dfaker/VR-reversal)

```bash
mpv --script=360plugin.lua --script-opts=360plugin-enabled=yes videoFile.mp4
```

```
? for help
v to toggle the main feature on or off.

y Increase resolution
h decrease resolution

i,k,j,l up,down,left,right
```

# 一些提升 quality-of-life 技巧

[TRICKS](TRICKS.md)

# Reference

- [hooke007/MPV_lazy](https://github.com/hooke007/MPV_lazy) is an easy to use one-step-install config repo, with a doc site including MPV wiki and some config tricks.
