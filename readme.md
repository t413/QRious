# QRious, QR Code generation for OpenTX / EdgeTx

[![Top Language](https://img.shields.io/github/languages/top/t413/QRious?style=flat-square)](https://github.com/t413/QRious)
[![GitHub Repo stars](https://img.shields.io/github/stars/t413/QRious?style=flat-square)](https://github.com/t413/QRious/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/t413/QRious?style=flat-square)](https://github.com/t413/QRious/network/members)
[![GitHub issues](https://img.shields.io/github/issues/t413/QRious?style=flat-square)](https://github.com/t413/QRious/issues)
[![Last commit](https://img.shields.io/github/last-commit/t413/QRious?style=flat-square)](https://github.com/t413/QRious/commits/main)
[![Users Total](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Finvites%2FDqJNftD7Hw%3Fwith_counts%3Dtrue&query=%24.approximate_member_count&logo=discord&logoColor=white&label=Users&color=5865F2&style=flat-square)](https://3d.t413.com/go/discord?ref=gh-omni)
[![Users Online](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Finvites%2FDqJNftD7Hw%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&label=Online&color=5865F2&style=flat-square)](https://3d.t413.com/go/discord?ref=gh-omni)

Your drone / plane gone down in a field and it's hard to find?

## Open this OpenTX/EdgeTX widget, scan the QR, open maps!

- Quick and easy way to find your model.. use your phone!
- Works with your inbuilt telemetry data stream
- Built to support several different mapping methods:
  * QR-code native `geo:` data that opens in your phone's native map app
  * google specific link for opening in google maps specifically
  * GURU maps link for opening in [Guru Maps](https://gurumaps.app) for offline mapping
- can be launched as a standalone script
- can be added as a telemetry widget
- Works from the command line (`lua qrPos.lua 'data'`) .. great for testing!

_Join my [Discord](https://3d.t413.com/go/discord?ref=gh-qrious) and say hi and talk shop!_

_Example running on my TBS Tango 2:_
![scan example](https://t413.com/p/2021-qrious/scan-example.jpeg)


## Installation & Usage

- Download the code ([direct link to zip](https://github.com/t413/QRious/archive/refs/heads/main.zip))
- Copy to SD Card for your EdgeTx/OpenTx radio
  * Copy `SCRIPTS/TELEMETRY/qrPos.lua` - *with the same path*
  * Copy `WIDGETS/qrPos/main.lua` - *with the same path*
- Add as a telemetry widget on your radio (model edit, last page)
- Run as a standalone script (under system menu, scripts)


## Limitations

- Uses a fair bit of RAM memory
  * as optimized as I could make it– only uses high RAM when actually generating QR code
- Some radios are hard to scan
  * OLED displays (like Tango 2) are hard to scan in daylight
  * Haven't tested color radios
- If you've _lost_ telemetry it won't work.
  * Open/EdgeTX doesn't seem to serve stale telem values.
  * so *works best as a widget* unless you're getting telemetry data

_Example running on my old Frsky X-Lite and in the terminal_
![opentx example](https://t413.com/p/2021-qrious/opentx.jpeg)

## Key Technical Achievements

- **Fully Reentrant Architecture**: 800+ lines of QR generation split into 10 incremental stages that pause/resume across execution cycles without blocking radio telemetry
- **CPU Load Monitoring**: Each stage checks `getUsage()` and yields at 40-80% thresholds to keep the radio responsive
- **Aggressive Memory Management**: Clears buffers (`eccbuf`, `genpoly`, `framask`) immediately after use with strategic `collectgarbage()` calls for RAM-constrained microcontrollers
- **Lua Array Adaptation**: Reimplemented QR algorithms for Lua's 1-indexed arrays, including Galois field arithmetic via lookup tables
- **Symmetrical Masking**: Stores only half the mask data by exploiting coordinate symmetry (`x > y` mirrors `y > x`)
- **Multi-Platform Testing**: Runs on OpenTX/EdgeTX hardware, simulators, and command-line with ASCII QR output
- **Live GPS Integration**: Generates scannable codes from real-time telemetry with multiple mapping service prefixes


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

