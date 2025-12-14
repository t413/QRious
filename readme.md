# QRious, QR Code generation for OpenTX / EdgeTx

[![Top Language](https://img.shields.io/github/languages/top/t413/QRious?style=flat-square)](https://github.com/t413/QRious)
[![GitHub Repo stars](https://img.shields.io/github/stars/t413/QRious?style=flat-square)](https://github.com/t413/QRious/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/t413/QRious?style=flat-square)](https://github.com/t413/QRious/network/members)
[![GitHub issues](https://img.shields.io/github/issues/t413/QRious?style=flat-square)](https://github.com/t413/QRious/issues)
[![Last commit](https://img.shields.io/github/last-commit/t413/QRious?style=flat-square)](https://github.com/t413/QRious/commits/main)
[![Users Total](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Finvites%2FDqJNftD7Hw%3Fwith_counts%3Dtrue&query=%24.approximate_member_count&logo=discord&logoColor=white&label=Users&color=5865F2&style=flat-square)](https://3d.t413.com/go/discord?ref=gh-omni)
[![Users Online](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Finvites%2FDqJNftD7Hw%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&label=Online&color=5865F2&style=flat-square)](https://3d.t413.com/go/discord?ref=gh-omni)

Your drone / plane gone down in a field and it's hard to find?

## Just scan the QR, open maps, walk right to it!

![scan example](https://t413.com/p/2021-qrious/qrious_demo.gif)

## Three ways to use it

1. **Widget** (on color screen radios like the TX16X)
   - Highly customizable! Colors, transparency, update rate, link type.
1. **Telemetry page** (on b/w radios like the X-Lite)
   - Can run alongside BF/iNav/Ardu scripts. Meticulously developed for low memory usage.
   - gets GPS updates in the background, renders QR code when needed
1. **System Tool** _(not the recommended use-case, requires telem link when opened)_

## Features

- Quick and easy way to find your model.. use your phone!
- Works with your inbuilt telemetry data stream
- Built to support several different mapping methods:
  * QR-code native `geo:` data that opens in your phone's native map app
  * google specific link for opening in google maps specifically
  * CoMaps link for opening in the free open source [CoMaps App](https://comaps.app) for offline mapping
  * GURU maps link for opening in [Guru Maps](https://gurumaps.app) for offline mapping
- Works from the command line (`lua qrPos.lua 'data'`) .. great for testing!

_Join my [Discord](https://3d.t413.com/go/discord?ref=gh-qrious) and say hi and talk shop!_

## Installation & Usage

Installs just like any other opentx/edgetx lua script! Just copy three files.

- Download the code ([direct link to zip](https://github.com/t413/QRious/archive/refs/heads/main.zip))
- Copy to SD Card for your EdgeTx/OpenTx radio
  * Copy `SCRIPTS/TELEMETRY/qrPos.lua` - *with the same path*
  * Copy `SCRIPTS/TOOLS/qrPos.lua` - *with the same path* (will make it available in system->tools)
  * Copy `WIDGETS/qrPos/` folder to sd-card
    - _only needed for color screen radios_
- Alternatively, for my fellow mac/linux terminal nerds:
  * Copy with `rsync -av ~/Downloads/QRious-main/src/ /Volumes/DISK_IMG/` (changing source and dest paths with tab-complete)
- Add as a telemetry widget on your radio (model edit, last page)


### Widget setup on color screen radio:
<p align="center">
  <img src="https://t413.com/p/2021-qrious/qrious_demo_colorscreen.gif" width="400" alt="widget setup example">
</p>

### Telemetry-page set up on b/w radio
<p align="center">
  <img src="https://t413.com/p/2021-qrious/qrious_demo_lite.gif" width="400" alt="telem page setup example">
</p>


## Widget Configuration / EdgeTx Version

On color display radios you can modify settings (see the gif!) Some features require EdgeTx 2.11+ ([github](https://github.com/EdgeTX/edgetx/releases))!
- Dropdown picker for which link-type you'd like. (On old versions you'll just see a simple switch)
- More options! Older versions are limited to 5. Transparency is the #6 option.


## Key Technical Achievements

- **Fully Reentrant Architecture**: 800+ lines of QR generation split into 11 incremental stages that pause/resume across execution cycles without blocking radio telemetry
- **CPU Load Monitoring**: Each stage checks `getUsage()` and yields at 40-80% thresholds to keep the radio responsive
- **Crazy-optimized for low memory**:
  * Bit-packed arrays for massive memory savings over Lua arrays
  * Static lookups are stored as strings for big memory savings over Lua arrays
- **Two ways of rendering!**
  * Full color / transparency BMP file creation! Allows Widgets to work with high-speed rendering they require. Also non-blocking reentrant code.
  * Direct rendering for tool view or telemetry page on black and white radios. Also non-blocking and draws over multiple iterations.
- **Works alongside** other memory-hog scripts like the iNav script! Run both!
- **Aggressive Memory Management**: Clears buffers (`eccbuf`, `genpoly`, `framask`) immediately after use with strategic `collectgarbage()` calls for these RAM-constrained microcontrollers
- **Multi-Platform Testing**: Runs on OpenTX/EdgeTX hardware, simulators, and command-line with ASCII QR output


## Testing / Development

This is actually runable from lua on the command line!

Install a `lua` runtime like [LuaJIT](https://luajit.org/download.html), here using homebrew on macOS:

```bash
brew install LuaJIT # or: sudo apt install luajit2
```

Run the script with a `geo:` link:

```bash
lua src/SCRIPTS/TELEMETRY/qrPos.lua "geo:37.87133,-122.31750"
```

This prints debug information about the generation process and the QR code as ASCII to the console. Example output of that command is in the screeshot above.

