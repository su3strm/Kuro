# Kuro - FPS Optimizer for Windows 10 / 11

Kuro is a PC optimizer built mainly for **low-end office laptops** (Intel/AMD integrated graphics, 8 GB RAM), and it also works for gaming laptops and desktops. It scans your hardware, marks the tweaks that suit your PC, and applies them with one click. Every change is backed up and can be switched off again.

## Quick start

1. Extract the whole zip to a normal folder, e.g. `C:\Kuro` (do not run it from inside the zip).
2. Double-click **`Launch Kuro.bat`** and click **Yes** when Windows asks for administrator permission.
3. Wait for the scan (10-20 s), then press **Apply all recommended** on the Dashboard.
4. Restart the PC once so that every tweak takes effect.

> Windows SmartScreen or your antivirus may warn about the app because it is new and unsigned and it changes system settings. That is normal for optimizers. Every line of code is in `Kuro.ps1` if you want to read it.

### Optional: make a real Kuro.exe
Double-click **`Build-EXE.bat`**. It downloads the free *PS2EXE* module and creates `Kuro.exe` with the cat icon. Keep the exe next to the `data` and `assets` folders. `Launch Kuro.bat` uses the exe automatically when it exists.

## What's inside

| Page | What it does |
|---|---|
| **Dashboard** | "% Optimized" score, top recommendations for *your* PC, live CPU / RAM / GPU usage, hardware summary, shortcuts |
| **Optimizations** | 45 registry, power, network, storage, Roblox and quality-of-life tweaks, with filter chips, search and "Recommended only" |
| **Debloat** | 41 tweaks: remove pre-installed apps, disable telemetry, background apps and unneeded services |
| **Game Boost** (PRO) | One click before you play: Best-performance power mode, closes OneDrive/Widgets/Phone Link (browsers optional), frees RAM, gives games High CPU priority, re-applies Roblox flags after updates. Turning it off restores everything |
| **PC Scanner** | CPU, GPU (real video memory), RAM (speed, modules, single-channel detection), storage type, display Hz, battery/power plan, device profile, gaming score, realistic FPS expectations, personal advice |
| **Tools** | Restore point, clean temp files, free RAM, flush DNS, startup apps, graphics settings, driver download page, save report, open backup folder, revert everything |
| **Premium** | Redeem a one-time code (`CCH-XXXX-XXXX-XXXX`) |
| **Support** | Join the Kuro Discord, report a bug (your PC info is copied for you), buy Premium codes, About |
| **Support** | Join the Kuro Discord, report a bug (your PC info is copied for you), buy Premium codes, About |
| **Colours, Vibes & Settings** | 10 accent colours plus a custom hex colour, 6 background themes, anime mascots and lo-fi music (each can be switched off), safety switches, optional license server |

### How recommendations work
The scanner gives your PC tags such as *Laptop, Integrated graphics, 8 GB RAM or less, SSD, Hybrid P/E-core CPU, Modern Standby, Windows 11, Roblox installed*. Each tweak lists which tags it suits and which it should avoid, so every card shows one of these labels:
- **Recommended for your PC** (green) - included in "Apply all recommended"
- **Optional** (grey) - safe, but only useful in some situations
- **Not recommended for your PC** (red) - e.g. core-parking tweaks on Intel 12th-gen hybrid CPUs, or Ultimate Performance on Modern Standby laptops

### Safety
- The first change of each day creates a **System Restore point** (you can switch this off in Settings).
- Before any registry value, service or power setting is changed, the original is saved to `C:\ProgramData\Kuro\backup.json`. Switching a tweak off restores the exact original value.
- Medium-risk tweaks ask for confirmation first.
- **Tools > Revert everything** undoes every tweak Kuro applied.
- Kuro never disables Windows Defender, Windows Update, the firewall or CPU security mitigations.

## Vibes
Kuro comes with six original anime mascots (**Kuro**, **Momo**, **Yuki**, **Sakura**, **Mint** and **Cola**) and four original lo-fi tracks (**Cola Cafe**, **Midnight Mint**, **Sakura Rain** and **Neon Drive**), all made for Kuro and free of copyright claims. The default look is pastel pink. Kuro can give spoken voicelines and tips (toggle in Vibes), a first-run tutorial walks new users through the app, finishing a task plays an anime effect, and the loading spinner is a rainbow ring - every bit of it optional. There's also an offline **Ask Kuro** helper on the Support page for common questions.
- Turn either one off in **Colours, Vibes & Settings**. You can also choose a mascot or Random, a track or Shuffle, and the volume.
- Use the music pill in the title bar to play or pause, and the arrow next to it to skip to the next track.
- By default the music pauses on its own while a game is running and resumes when you close the game.
- Click the mascot on the Dashboard for a new tip.
- Click the round profile picture at the bottom of the sidebar to change it. You can pick a character, the cat logo or any picture from your PC.

## Recording, music and network tools
- **Record screen** (Tools): captures gameplay to your `Videos\Captures` folder using the built-in Windows recorder. Press once to start, again to stop.
- **Ping and region test** (Tools): measures your real latency to major servers and your router. Note: no software can give everyone 1-5 ms ping - that depends on how far the game server physically is. The network tweaks cut jitter and spikes, not distance.
- **My music**: in Colours, Vibes & Settings pick "My music" to scan your Music, Downloads, Videos and Desktop folders and play the songs already on your PC (shuffle, skip from the title-bar player). Kuro never downloads music.
- **Game Boost** now revs an engine gauge to 100 with an original engine sound instead of confetti.

## Realistic expectations (i5-1235U, Intel Iris Xe, 8 GB RAM)
Software tweaks typically add **5-20 % FPS** and make frame times smoother. They cannot turn integrated graphics into a gaming GPU. On this kind of laptop, with low settings:
- Roblox: about 90-160 FPS in light games and 50-90 FPS in busy ones.
- Fortnite (Performance mode): about 50-80 FPS.
- Big AAA games: about 25-45 FPS at 720p low. 120 FPS is not realistic.

The things that matter most on this hardware:
1. **Plug in the charger.** On battery, FPS can drop by half.
2. **Dual-channel RAM.** If the scanner shows "UHD Graphics" instead of "Iris Xe", add a second matching RAM stick. This is the biggest upgrade you can make.
3. **In Roblox settings**, use Graphics Mode *Manual*, quality *1-3* and Maximum Frame Rate *120/144*. (The old FPS-unlocker FastFlags were blocked by Roblox in September 2025; the built-in setting is now the way to do it.)
4. **Your screen's refresh rate.** A 60 Hz laptop panel can only show 60 frames, although higher FPS still lowers input delay.

## Macros
The **Macros** page (keyboard icon) has four ready-made slots you can switch on and tune:
- **Bedwars PvP** - hold left mouse to auto-click.
- **Bedwars Build** - hold right mouse to place blocks fast.
- **Bedwars Bow** - hold Mouse 5 to draw and release the bow on a loop (set the charge time to match your bow).
- **Da Hood macro** - hold X to spam the scroll wheel (change the trigger, action and speed to match the method you use).

Click a macro to open it. Each one has a trigger (any mouse button or keyboard key), hold or toggle mode, an action (left/right click, bow, scroll up/down/both, or press a key), a speed and a randomize amount. Turn on **Macros** in the General box to start them. The tiles at the top show live clicks per second, the status and how many macros are switched on. By default they only run while Roblox is the active window, and **F8 pauses or resumes** everything. The speeds are starting points - tune them yourself. Some games do not allow macros, so use them at your own risk.

## Macro builder
Macros page > **Library** > **New macro**. In **Steps**, click a coloured block (Press key, Click, Wait, Auto-click, Type text, Key combo, Double click, Move mouse, Move by, Scroll, Wait random, Label, Hold key down, Let go of key, Mouse button down/up) to add it, or click **Record**: after a 3-second countdown, Kuro records your keys, clicks and scrolls in your game window (anything you do inside Kuro is ignored) until you click Stop. **Test** plays the macro once after 3 seconds. **Settings** sets the trigger and how it plays (once, a set number of times, while held, or on/off with each press). **Share** gives a `KURO1:` code a friend can import. F8 stops any macro that is playing. Up to 500 blocks per macro.

## Roblox graphics
A 20-step Looks vs FPS slider with Quality, Balanced, Performance and Max FPS presets. It only writes FastFlags that are on Roblox's allowlist (texture quality, anti-aliasing, graphics level, grass distance, gray sky, lighting freeze, part detail). Click **Apply to Roblox**, then restart Roblox. **Reset** removes everything the slider added. Roblox no longer lets apps change the FPS cap, so set Maximum Frame Rate in Roblox's own settings.

## Greeting banner
When Kuro opens, a banner at the top greets you based on your PC's clock and calendar: time of day plus the season (for example "A late worm in the cold night" on a winter night, with a reminder to get to bed). Late at night it reminds you again every 90 minutes. No location or internet is used. Both can be turned off in Settings.

## Kuro community numbers
The Dashboard shows how many people use Kuro (active today and online now), how many use Premium, and how many Premium codes have been bought. To be counted, Kuro sends an anonymous check-in every 15 minutes: a hashed install id that cannot be traced back to your PC, whether Premium is on, and the Kuro version. No names, IP addresses or PC details are stored. Turn it off in Settings ("Count this PC in the live user numbers"); you still see the numbers.

## Premium
Premium-only: PRO tweaks, Game Boost, one-click optimize with PRO tweaks, and stream proof. On the Free plan these show a lock card with an Unlock Premium button. When a code is redeemed (or Premium is restored by logging in) a "Thanks for buying Premium" banner drops in at the top of the window.

## Game Bar (Alt+K)
Kuro notices which game is in front (Roblox, Fortnite, Valorant, CS2, Minecraft and more) and, per game, can switch on Game Boost, the crosshair and macros, then switch them off when the game closes. Set this up on the Game Bar page. Press **Alt+K** in-game for the Game Bar: CPU, RAM, time in game, record, boost, crosshair, macros, stream proof, music, and Roblox graphics presets.

## Stream proof (Premium)
Game Bar page or Settings. Hides Kuro's windows (main window, Game Bar, crosshair) from screenshots, OBS, Discord screen share and Windows recordings while you still see them. Needs Windows 10 version 2004 or newer (older versions show a black box instead). It only hides Kuro, not other apps, and cameras or capture cards still see your screen.

## Cursor and crosshair
Stack up to 8 shapes (dot, ring, square, plus, X, split, diamond, triangle, bar, arrow, oval, star, arc) with size, thickness, roundness, gap, mirror, rotate, offset, colour, outline and glow. **Show on screen** draws it over the game (windowed or borderless). **Save as Roblox cursor** writes it into Roblox's cursor files (originals are backed up and restored with one click, and it is re-applied after Roblox updates).

## Ping
Network throttling off, Nagle's delay off, a QoS rule that tags Roblox traffic as urgent (only matters if your router honours it), and a DNS finder that tests Cloudflare, Google, Quad9, OpenDNS and AdGuard against your current DNS. DNS speeds up joining and loading, not in-game ping. Everything has an undo or restore.

## Loading screen
Kuro opens with a loading ring that fills while it scans your PC, then plays a short chime when it is ready. Rescan PC shows the same screen. Turn the chime off in Colours, Vibes & Settings > Welcome chime.

## Auto-update
Kuro checks for a new version at start-up and every 3 hours. It downloads only changed files, verifies each one, and installs them when you restart (it offers "Restart now"). If any file fails, nothing is installed and it retries later. Missing or damaged files are repaired the same way. Coming from ColaCatHub? Your settings, Premium and tweak backups are copied over automatically.

## Support and Premium
Join the Kuro Discord to report bugs, get help or buy a Premium code: https://discord.gg/t65frAtq5
On the **Support** page, **Report a bug** copies a ready-made report (version, PC specs and recent log lines) to your clipboard. Paste it into the Discord.

## Premium codes
- The app checks its own code on launch. If the script has been **edited to force Premium**, it quietly drops back to the Free tier and locks the paid tweaks. It never deletes or changes anything on the user's PC as a result.
- For the strongest protection, hand out the compiled **Kuro.exe** (Build-EXE.bat) and turn on the license server, so Premium is confirmed online per PC.
- Each code works **once** and is locked to the PC that redeems it.
- The app only contains SHA-256 hashes of the codes, so the codes cannot be read out of the app.
- Codes that leak can be blocked: add them to `data\revoked.txt` in the next version you share.

## Files and uninstall
- App data: `C:\ProgramData\Kuro\` (settings, backups, license, log)
- To uninstall: run **Tools > Revert everything**, close the app, then delete the Kuro folder and `C:\ProgramData\Kuro`.

## Full tweak list
| # | Page | Category | Tweak | Plan | Risk | Restart |
|---|---|---|---|---|---|---|
| 1 | Optimizations | FPS & Latency | Enable Windows Game Mode | Free | Low |  |
| 2 | Optimizations | FPS & Latency | Disable Game DVR Background Recording | Free | Low |  |
| 3 | Optimizations | FPS & Latency | Prioritize Games in the Multimedia Scheduler | PRO | Low |  |
| 4 | Optimizations | FPS & Latency | Foreground CPU Priority Boost | PRO | Low |  |
| 5 | Optimizations | FPS & Latency | Hardware-Accelerated GPU Scheduling | Free | Low | Yes |
| 6 | Optimizations | FPS & Latency | Disable Fullscreen Optimizations (Global) | PRO | Medium |  |
| 7 | Optimizations | FPS & Latency | Disable Mouse Acceleration | Free | Low |  |
| 8 | Optimizations | FPS & Latency | Disable Windows Power Throttling | Free | Low |  |
| 9 | Optimizations | FPS & Latency | Global Timer Resolution Requests | PRO | Low | Yes |
| 10 | Optimizations | FPS & Latency | Disable Multiplane Overlay (MPO) | PRO | Medium | Yes |
| 11 | Optimizations | FPS & Latency | Optimizations for Windowed Games | Free | Low |  |
| 12 | Optimizations | FPS & Latency | Visual Effects: Best Performance | Free | Low |  |
| 13 | Optimizations | FPS & Latency | Disable Transparency Effects | Free | Low |  |
| 14 | Optimizations | FPS & Latency | Keep Windows Kernel in RAM | PRO | Low | Yes |
| 15 | Optimizations | Power | Windows Power Mode: Best Performance | Free | Low |  |
| 16 | Optimizations | Power | Aggressive CPU Boost (on charger) | PRO | Low |  |
| 17 | Optimizations | Power | Ultimate Performance Power Plan | PRO | Medium |  |
| 18 | Optimizations | Power | Disable CPU Core Parking (on charger) | PRO | Low |  |
| 19 | Optimizations | Power | Disable USB Selective Suspend (on charger) | Free | Low |  |
| 20 | Optimizations | Power | Disable PCIe Link Power Saving (on charger) | PRO | Low |  |
| 21 | Optimizations | Power | Never Spin Down the Hard Drive (on charger) | Free | Low |  |
| 22 | Optimizations | Power | Disable Hibernation | Free | Low |  |
| 23 | Optimizations | Network & Ping | Remove Network Throttling | Free | Low |  |
| 24 | Optimizations | Network & Ping | Remove Reserved Bandwidth Limit | Free | Low |  |
| 25 | Optimizations | Network & Ping | Disable Nagle's Algorithm (TCP No Delay) | PRO | Low |  |
| 26 | Optimizations | Network & Ping | Stop Windows Update Peer-to-Peer Uploads | Free | Low |  |
| 27 | Optimizations | Network & Ping | Wi-Fi Adapter Maximum Performance (on charger) | Free | Low |  |
| 28 | Optimizations | Network & Ping | Prefer IPv4 over IPv6 | PRO | Low | Yes |
| 29 | Optimizations | Memory & Storage | Disable NTFS Last-Access Timestamps | Free | Low |  |
| 30 | Optimizations | Memory & Storage | Disable 8.3 Short File Names | PRO | Low |  |
| 31 | Optimizations | Memory & Storage | Disable SysMain (Superfetch) | Free | Medium |  |
| 32 | Optimizations | Memory & Storage | Disable Search Indexing | Free | Medium |  |
| 33 | Optimizations | Memory & Storage | System-Managed Page File | Free | Low |  |
| 34 | Optimizations | Memory & Storage | Enable Storage Sense Auto-Cleanup | Free | Low |  |
| 35 | Optimizations | Roblox & Games | Roblox: Low-End Graphics Pack | Free | Low |  |
| 36 | Optimizations | Roblox & Games | Roblox: Ultra-Low Render Mode | PRO | Low |  |
| 37 | Optimizations | Roblox & Games | Roblox: High-Performance GPU + Fullscreen Fix | Free | Low |  |
| 38 | Optimizations | Roblox & Games | Disable Game Bar Popups and Controller Button | Free | Low |  |
| 39 | Optimizations | Quality of Life | Instant Menus | Free | Low |  |
| 40 | Optimizations | Quality of Life | Remove Startup App Delay | Free | Low |  |
| 41 | Optimizations | Quality of Life | Disable Sticky Keys Popup | Free | Low |  |
| 42 | Optimizations | Quality of Life | Show File Extensions | Free | Low |  |
| 43 | Optimizations | Quality of Life | Classic Right-Click Menu | Free | Low |  |
| 44 | Optimizations | Quality of Life | Disable Fast Startup | Free | Low |  |
| 45 | Optimizations | Quality of Life | Show Detailed Startup Messages | Free | Low |  |
| 46 | Debloat | Privacy & Telemetry | Disable Windows Telemetry | Free | Low |  |
| 47 | Debloat | Privacy & Telemetry | Disable Advertising ID | Free | Low |  |
| 48 | Debloat | Privacy & Telemetry | Disable Tailored Experiences | Free | Low |  |
| 49 | Debloat | Privacy & Telemetry | Disable Activity History | Free | Low |  |
| 50 | Debloat | Privacy & Telemetry | Disable Tips, Suggestions and Auto-Installed Apps | Free | Low |  |
| 51 | Debloat | Privacy & Telemetry | Disable Bing Web Results in Start | Free | Low |  |
| 52 | Debloat | Privacy & Telemetry | Disable Copilot | Free | Low |  |
| 53 | Debloat | Privacy & Telemetry | Disable Recall Snapshots | Free | Low |  |
| 54 | Debloat | Privacy & Telemetry | Disable Cortana | Free | Low |  |
| 55 | Debloat | Privacy & Telemetry | Disable Feedback Prompts | Free | Low |  |
| 56 | Debloat | Privacy & Telemetry | Disable Windows Error Reporting | Free | Low |  |
| 57 | Debloat | Privacy & Telemetry | Disable CEIP and App Inventory | PRO | Low |  |
| 58 | Debloat | Privacy & Telemetry | Disable Typing and Inking Data Collection | PRO | Low |  |
| 59 | Debloat | Background & Startup | Disable Background Store Apps | Free | Low |  |
| 60 | Debloat | Background & Startup | Disable Widgets and News Feed | Free | Low |  |
| 61 | Debloat | Background & Startup | Stop Edge Running in the Background | Free | Low |  |
| 62 | Debloat | Background & Startup | Stop Chrome and Brave Running in the Background | Free | Low |  |
| 63 | Debloat | Background & Startup | Stop OneDrive Starting with Windows | Free | Medium |  |
| 64 | Debloat | Background & Startup | Stop Teams Starting with Windows | Free | Low |  |
| 65 | Debloat | Services | Disable Fax and Retail Demo Services | Free | Low |  |
| 66 | Debloat | Services | Disable Downloaded Maps Manager | Free | Low |  |
| 67 | Debloat | Services | Disable Insider and Phone Services | Free | Low |  |
| 68 | Debloat | Services | Disable Xbox Services | Free | Medium |  |
| 69 | Debloat | Services | Disable Print Spooler | Free | Medium |  |
| 70 | Debloat | Services | Disable Remote Registry | PRO | Low |  |
| 71 | Debloat | Apps | Remove Bing News and Weather | Free | Low |  |
| 72 | Debloat | Apps | Remove Solitaire and Pre-installed Games | Free | Low |  |
| 73 | Debloat | Apps | Remove Clipchamp | Free | Low |  |
| 74 | Debloat | Apps | Remove "Microsoft 365 (Office)" Hub App | Free | Low |  |
| 75 | Debloat | Apps | Remove Get Help, Tips and Feedback Hub | Free | Low |  |
| 76 | Debloat | Apps | Remove Teams Chat (Personal) | Free | Low |  |
| 77 | Debloat | Apps | Remove Cortana App | Free | Low |  |
| 78 | Debloat | Apps | Remove 3D and Mixed Reality Apps | Free | Low |  |
| 79 | Debloat | Apps | Remove People and Maps | Free | Low |  |
| 80 | Debloat | Apps | Remove To Do and Power Automate | PRO | Low |  |
| 81 | Debloat | Apps | Remove Skype and Old Mail and Calendar | PRO | Low |  |
| 82 | Debloat | Apps | Remove Copilot App | PRO | Low |  |
| 83 | Debloat | Apps | Remove Dev Home and Family | PRO | Low |  |
| 84 | Debloat | Apps | Remove Phone Link | PRO | Low |  |
| 85 | Debloat | Apps | Remove Media Player and Movies and TV | PRO | Medium |  |
| 86 | Debloat | Apps | Remove Xbox Apps | PRO | Medium |  |
