# ExifTool Auto LUT Detection Guide

This guide explains how to use the new ExifTool-based automatic LUT detection system for MPV.

## Overview

The ExifTool Auto LUT script uses `exiftool` to detect gamma information directly from video files and automatically applies appropriate LUTs. This method is more reliable than XML parsing and works with a wider variety of video files.

## Key Features

- **Primary Detection**: `Acquisition Record Group Item Value: s-log3-cine`
- **Fallback Detection**: `CaptureGammaEquation`, `TransferCharacteristics`, `Gamma`
- **Fast Switching**: Cached metadata for quick playlist navigation
- **Multiple Formats**: Supports Sony, Canon, Panasonic, DJI, and more

## Supported Gamma Types

| Gamma Type | LUT File | Description |
|------------|----------|-------------|
| `s-log3-cine` | `SLog3SGamut3.CineToLC-709.cube` | Sony S-Log3 Cine to Rec.709 |
| `s-log3` | `SLog3SGamut3.CineToLC-709.cube` | Sony S-Log3 to Rec.709 |
| `s-log2` | `SLog3SGamut3.CineToSLog2-709.cube` | Sony S-Log2 to Rec.709 |
| `v-log` | `VLog_to_V709_forV35_ver100.cube` | Panasonic V-Log to Rec.709 |
| `canon-log2` | `CinemaGamut_CanonLog2-to-Canon709_65_Ver.1.0.cube` | Canon Log2 to Rec.709 |
| `canon-log3` | `CinemaGamut_CanonLog3-to-Canon709_65_Ver.1.0.cube` | Canon Log3 to Rec.709 |
| `dji-osmo-p3` | `Neutral_Osmo_P3.cube` | DJI Osmo Pocket 3 Neutral |
| `rec709` | (none) | Rec.709 (No LUT needed) |

## Usage

### Automatic Detection
The script automatically detects gamma information when you load a video file in MPV. No manual intervention required.

### Manual Processing
Press `Ctrl+E` in MPV to manually trigger gamma detection and LUT application.

### Testing Detection
Use the provided test scripts to verify detection works with your video files:

**PowerShell (Recommended):**
```powershell
.\test_exiftool_detection.ps1 "C:\path\to\your\video.mp4"
```

**Batch:**
```cmd
test_exiftool_detection.bat "C:\path\to\your\video.mp4"
```

## Configuration

Edit `script-opts/exiftool_auto_lut.conf` to customize behavior:

```ini
enabled=yes                    # Enable/disable the script
auto_apply=yes                 # Automatically apply LUTs
show_detection=yes             # Show detection results in console
lut_base_path=~~home/lut/      # Base path for LUT files
fast_switching=yes             # Enable fast LUT switching
cache_metadata=yes             # Cache metadata for speed
exiftool_path=exiftool         # Path to exiftool executable
timeout=5                      # Timeout for exiftool execution
```

## Detection Priority

The script uses the following priority order for gamma detection:

1. **Acquisition Record Group Item Value** (most reliable for Sony cameras)
2. **CaptureGammaEquation** (alternative Sony format)
3. **TransferCharacteristics** (standard video metadata)
4. **Gamma** (basic gamma information)

## Troubleshooting

### ExifTool Not Found
Make sure `exiftool` is installed and available in your PATH:
```cmd
exiftool -ver
```

### No Detection
- Check if your video file contains metadata
- Try the test script to see what metadata is available
- Some video files may not contain gamma information

### Wrong LUT Applied
- Check the detected gamma value in the console output
- Add custom mappings to the `lut_mapping` table in the script
- Verify the LUT file exists in the `lut/` directory

## Console Output

When detection is successful, you'll see output like:
```
=== EXIFTOOL AUTO LUT ===
Video file: sample.mp4
=== METADATA DETECTED ===
Acquisition Record Group Item Value: s-log3-cine
Detected Gamma: s-log3-cine
✓ SUCCESS: Applied: Sony S-Log3 Cine to Rec.709
```

## Performance

- **Caching**: Metadata is cached to avoid repeated exiftool calls
- **Fast Switching**: Playlist navigation is optimized for speed
- **Background Processing**: Detection runs in background to avoid blocking playback

## Integration

The script is automatically loaded via `mpv.conf`:
```ini
script=scripts/exiftool_auto_lut.lua
```

The old XML-based script is disabled to avoid conflicts:
```ini
# script=scripts/sony_xml_auto_lut.lua  # Disabled in favor of exiftool detection
```
