// Assets embedded in the executable at compile time (#load): level files,
// shaders and fonts. No file IO at runtime, nothing to lose next to the binary.
//
// The game is 20 levels in four acts and an epilogue, in Apuleius' order.
// Every level has its slot from the start; a slot without a level file is
// not built yet (the level select shows it, nobody can play it).
// To add a level: drop assets/levels/level_NN.txt (NN = slot number) and
// point the slot's `source` at it.
package content

import "../i18n"

Act :: enum u8 {
	I,
	II,
	III,
	IV,
	Epilogue,
}

// "Act I", ... "Epilogue"
ACT_LABEL := [Act]i18n.Key {
	.I        = .Act_1,
	.II       = .Act_2,
	.III      = .Act_3,
	.IV       = .Act_4,
	.Epilogue = .Act_Epilogue,
}

ACT_TITLE := [Act]i18n.Key {
	.I        = .Act_1_Title,
	.II       = .Act_2_Title,
	.III      = .Act_3_Title,
	.IV       = .Act_4_Title,
	.Epilogue = .Act_Epilogue_Title,
}

// The card shown before the first level of an act (Act I: the prologue).
ACT_CARD := [Act]i18n.Key {
	.I        = .Act_1_Card,
	.II       = .Act_2_Card,
	.III      = .Act_3_Card,
	.IV       = .Act_4_Card,
	.Epilogue = .Act_Epilogue_Card,
}

Level_Info :: struct {
	id:     string, // stable name, used in the save file: never change it
	act:    Act,
	title:  i18n.Key,
	source: string, // the level file; "" while the level is not built
}

LEVELS := [?]Level_Info {
	{"I.1", .I, .Level_I_1, #load("../../assets/levels/level_01.txt", string)},
	{"I.2", .I, .Level_I_2, #load("../../assets/levels/level_02.txt", string)},
	{"I.3", .I, .Level_I_3, #load("../../assets/levels/level_03.txt", string)},
	{"I.4", .I, .Level_I_4, #load("../../assets/levels/level_04.txt", string)},
	{"II.1", .II, .Level_II_1, #load("../../assets/levels/level_05.txt", string)},
	{"II.2", .II, .Level_II_2, #load("../../assets/levels/level_06.txt", string)},
	{"II.3", .II, .Level_II_3, #load("../../assets/levels/level_07.txt", string)},
	{"II.4", .II, .Level_II_4, #load("../../assets/levels/level_08.txt", string)},
	{"II.5", .II, .Level_II_5, #load("../../assets/levels/level_09.txt", string)},
	{"III.1", .III, .Level_III_1, ""},
	{"III.2", .III, .Level_III_2, ""},
	{"III.3", .III, .Level_III_3, ""},
	{"III.4", .III, .Level_III_4, ""},
	{"III.5", .III, .Level_III_5, ""},
	{"IV.1", .IV, .Level_IV_1, ""},
	{"IV.2", .IV, .Level_IV_2, ""},
	{"IV.3", .IV, .Level_IV_3, ""},
	{"IV.4", .IV, .Level_IV_4, ""},
	{"IV.5", .IV, .Level_IV_5, ""},
	{"E", .Epilogue, .Level_Epilogue, ""},
}

LEVEL_COUNT :: len(LEVELS)

// The fragments of the tale, in level order; a level hides one or more (its
// `fragment` lines take them in this order).
Fragment_Info :: struct {
	id:    string, // stable name, used in the save file: never change it
	level: int, // index into LEVELS
	key:   i18n.Key,
	cite:  string, // where it comes from (Metamorphoses book.chapter)
}

FRAGMENTS := [?]Fragment_Info {
	{"I.1", 0, .Fragment_01, "IV.28"},
	{"I.2", 1, .Fragment_02, "IV.28–29"},
	{"I.3", 2, .Fragment_03, "V.9"},
	{"I.3b", 2, .Fragment_03b, "V.10"},
	{"I.4", 3, .Fragment_04, "IV.32–33"},
	{"II.1", 4, .Fragment_05, "V.23"},
	{"II.2", 5, .Fragment_06, "IV.33–35"},
	{"II.3", 6, .Fragment_07, "V.28"},
	{"II.4", 7, .Fragment_08, "V.29–31"},
	{"II.5", 8, .Fragment_09, "V.31"},
	{"III.1", 9, .Fragment_10, "VI.7–8"},
	{"III.2", 10, .Fragment_11, "VI.11"},
	{"III.3", 11, .Fragment_12, "VI.11"},
	{"III.4", 12, .Fragment_13, "VI.14"},
	{"III.5", 13, .Fragment_14, "VI.16"},
	{"IV.1", 14, .Fragment_15, "VI.17"},
	{"IV.2", 15, .Fragment_16, "VI.18"},
	{"IV.3", 16, .Fragment_17, "VI.18"},
	{"IV.4", 17, .Fragment_18, "VI.20"},
	{"IV.5", 18, .Fragment_19, "VI.21"},
	{"E", 19, .Fragment_20, "VI.24–25"},
}

FRAGMENT_COUNT :: len(FRAGMENTS)

// The Book shows the fragments in the order of Apuleius' text, not of the
// levels: fragment indices, in reading order.
BOOK_ORDER := [FRAGMENT_COUNT]int{0, 1, 4, 6, 2, 3, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20}

// The fragments of a level: FRAGMENTS[first:][:count].
level_fragments :: proc(level: int) -> (first, count: int) {
	first = -1
	for f, i in FRAGMENTS {
		if f.level == level {
			if first < 0 {
				first = i
			}
			count += 1
		}
	}
	return max(first, 0), count
}

is_built :: proc(index: int) -> bool {
	return index >= 0 && index < LEVEL_COUNT && LEVELS[index].source != ""
}

// Is this the first level of its act? (its act card comes before it)
opens_act :: proc(index: int) -> bool {
	return index == 0 || LEVELS[index - 1].act != LEVELS[index].act
}

closes_act :: proc(index: int) -> bool {
	return index == LEVEL_COUNT - 1 || LEVELS[index + 1].act != LEVELS[index].act
}

FONT_SERIF :: #load("../../assets/fonts/NotoSerif-Regular.ttf")
FONT_SERIF_ITALIC :: #load("../../assets/fonts/NotoSerif-Italic.ttf")

SHADER_PALACE_VS :: #load("../../assets/shaders/palace.vs", cstring)
SHADER_PALACE_FS :: #load("../../assets/shaders/palace.fs", cstring)
SHADER_SKY_FS :: #load("../../assets/shaders/sky.fs", cstring)
SHADER_CLOUDS_FS :: #load("../../assets/shaders/clouds.fs", cstring)
SHADER_RIDGES_FS :: #load("../../assets/shaders/ridges.fs", cstring)
SHADER_POST_BRIGHT_FS :: #load("../../assets/shaders/post_bright.fs", cstring)
SHADER_POST_BLUR_FS :: #load("../../assets/shaders/post_blur.fs", cstring)
SHADER_POST_FS :: #load("../../assets/shaders/post.fs", cstring)
SHADER_VEIL_FS :: #load("../../assets/shaders/veil.fs", cstring)
