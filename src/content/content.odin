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
	id:       string, // stable name, used in the save file: never change it
	act:      Act,
	title:    i18n.Key,
	fragment: i18n.Key, // the fragment of the tale hidden in the level
	cite:     string, // where the fragment comes from (Metamorphoses book.chapter)
	source:   string, // the level file; "" while the level is not built
}

LEVELS := [?]Level_Info {
	{"I.1", .I, .Level_I_1, .Fragment_01, "IV.28", #load("../../assets/levels/level_01.txt", string)},
	{"I.2", .I, .Level_I_2, .Fragment_02, "IV.28–29", #load("../../assets/levels/level_02.txt", string)},
	{"I.3", .I, .Level_I_3, .Fragment_03, "IV.30–31", #load("../../assets/levels/level_03.txt", string)},
	{"I.4", .I, .Level_I_4, .Fragment_04, "IV.32–33", #load("../../assets/levels/level_04.txt", string)},
	{"II.1", .II, .Level_II_1, .Fragment_05, "V.23", #load("../../assets/levels/level_05.txt", string)},
	{"II.2", .II, .Level_II_2, .Fragment_06, "IV.33–35", #load("../../assets/levels/level_06.txt", string)},
	{"II.3", .II, .Level_II_3, .Fragment_07, "V.28", #load("../../assets/levels/level_07.txt", string)},
	{"II.4", .II, .Level_II_4, .Fragment_08, "V.29–31", #load("../../assets/levels/level_08.txt", string)},
	{"II.5", .II, .Level_II_5, .Fragment_09, "V.31", #load("../../assets/levels/level_09.txt", string)},
	{"III.1", .III, .Level_III_1, .Fragment_10, "VI.7–8", ""},
	{"III.2", .III, .Level_III_2, .Fragment_11, "VI.11", ""},
	{"III.3", .III, .Level_III_3, .Fragment_12, "VI.11", ""},
	{"III.4", .III, .Level_III_4, .Fragment_13, "VI.14", ""},
	{"III.5", .III, .Level_III_5, .Fragment_14, "VI.16", ""},
	{"IV.1", .IV, .Level_IV_1, .Fragment_15, "VI.17", ""},
	{"IV.2", .IV, .Level_IV_2, .Fragment_16, "VI.18", ""},
	{"IV.3", .IV, .Level_IV_3, .Fragment_17, "VI.18", ""},
	{"IV.4", .IV, .Level_IV_4, .Fragment_18, "VI.20", ""},
	{"IV.5", .IV, .Level_IV_5, .Fragment_19, "VI.21", ""},
	{"E", .Epilogue, .Level_Epilogue, .Fragment_20, "VI.24–25", ""},
}

LEVEL_COUNT :: len(LEVELS)

// The Book shows the fragments in the order of Apuleius' text, not of the
// levels: level indices, in reading order.
BOOK_ORDER := [LEVEL_COUNT]int{0, 1, 2, 3, 5, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19}

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
