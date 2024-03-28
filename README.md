# Personal mpv conf

This is my personal mpv player's configrations. Feel free to use.

## Scripts included:

### autoload

playlist **autoload**.

From: mpv's [official repo](https://github.com/mpv-player/mpv/blob/master/TOOLS/lua/autoload.lua).

### uosc

an elegent and useful **GUI** (specific term is On Screen Controller, OSC) with some utils.

From: [tomasklaen/uosc](https://github.com/tomasklaen/uosc)


### thumbfast

show **thumbnails** on the progress bar.

From: [po5/thumbfast](https://github.com/po5/thumbfast)

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

### trim

Cut video without decoding/encoding

From: [aerobounce/trim.lua](https://github.com/aerobounce/trim.lua)

```
h for start position
k for end position

duble press h/k for cutting
```

### personal miscs

-  `helpers.bash`: dvd and bd playing helpers


## Reference

- [hooke007/MPV_lazy](https://github.com/hooke007/MPV_lazy) is an easy to use one-step-install config repo, with a doc site including MPV wiki and some config tricks.
