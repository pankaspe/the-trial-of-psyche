// Assets embedded in the executable at compile time (#load): level files,
// shaders and fonts. No file IO at runtime, nothing to lose next to the binary.
// To add a level: drop the file in assets/levels/ and add an entry to LEVELS.
package content

import "../i18n"

Level_Info :: struct {
	title:  i18n.Key,
	source: string,
}

LEVELS := [?]Level_Info {
	{.Level_1, #load("../../assets/levels/level_01.txt", string)},
}

FONT_SERIF :: #load("../../assets/fonts/NotoSerif-Regular.ttf")
FONT_SERIF_ITALIC :: #load("../../assets/fonts/NotoSerif-Italic.ttf")

SHADER_PALACE_VS :: #load("../../assets/shaders/palace.vs", cstring)
SHADER_PALACE_FS :: #load("../../assets/shaders/palace.fs", cstring)
SHADER_SKY_FS :: #load("../../assets/shaders/sky.fs", cstring)
SHADER_CLOUDS_FS :: #load("../../assets/shaders/clouds.fs", cstring)
