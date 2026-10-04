# The Trial of Psyche

An isometric puzzle about seeing and trusting, from Apuleius' *Cupid and Psyche*
(Metamorphoses IV–VI). In the dark, what looks joined *is* joined. The lamp
shows the truth — and breaks the paths you walk on.

Odin + raylib 6. Italian and English.

## Build and run

```bash
./build.sh            # debug build and run
./build.sh release    # optimised build in build/trial-of-psyche
./build.sh test       # headless tests
./build.sh check assets/levels/level_01.txt   # level analysis
```

Needs the Odin compiler (`odin` in PATH); raylib comes with Odin's vendor collection.

## Controls

Click: walk · Q / E or arrows: turn the palace · Space / L / right click: lamp ·
R: restart · Esc: pause · F11: fullscreen · F3: debug overlay

## Layout

```
src/
  main.odin        app: window, screens, settings, frame loop
  shots.odin       scripted screenshots (--shots DIR)
  iso/             isometric grid math
  level/           level file parser
  palace/          walk graph, illusions, visibility, path finding
  game/            rules: lamp, oil, walking, turning, seal, endings
  render/          3D palace, figures, sky, clouds, glows, particles
  ui/              fonts, widgets, HUD, menus
  audio/           procedural sound and music
  i18n/            every visible string, per language
  settings/        player options file
  fx/              easing, RNG, particle pools
  content/         embedded assets (levels, shaders, fonts)
assets/            levels, GLSL shaders, fonts
tests/             headless tests
tools/level_check/ level analysis
```

## Credits

Pieces modelled after Kenney's *Isometric Prototype Tiles* (CC0).
Font: Noto Serif (SIL Open Font License, see `assets/fonts/OFL.txt`).
