// The player's progress: levels finished, fragments of the tale collected,
// achievements. Saved as `key = value` lines next to the settings
// (~/.config/the-trial-of-psyche/progress.cfg on Linux). Levels and fragments
// are stored by their stable id ("I.4", "I.3b"), so adding levels never breaks
// a save; unknown ids and lines are ignored.
//
// The rules here are pure (no IO, no game state): the app reports what
// happened, this package answers with the achievements it unlocked. If the
// game ever ships on Steam, these are the events to forward.
package progress

import "core:fmt"
import "core:os"
import "core:strings"

import "../content"
import "../i18n"
import "../settings"

FILE_NAME :: "progress.cfg"

#assert(content.LEVEL_COUNT <= 32)
Level_Set :: bit_set[0 ..< 32] // indices into content.LEVELS
#assert(content.FRAGMENT_COUNT <= 32)
Fragment_Set :: bit_set[0 ..< 32] // indices into content.FRAGMENTS

Achievement :: enum u8 {
	Tale_1, // every fragment of an act
	Tale_2,
	Tale_3,
	Tale_4,
	Old_Woman, // every fragment: the frame of the tale
	Trust, // the secret ending
	No_Wasted_Light, // a level finished with the lamp lit only where needed
	Wedding, // the game finished
}

Achievements :: bit_set[Achievement]

// Hidden in the Book until unlocked.
SECRET :: Achievements{.Trust}

ACHIEVEMENT_ID := [Achievement]string {
	.Tale_1          = "tale_1",
	.Tale_2          = "tale_2",
	.Tale_3          = "tale_3",
	.Tale_4          = "tale_4",
	.Old_Woman       = "old_woman",
	.Trust           = "trust",
	.No_Wasted_Light = "no_wasted_light",
	.Wedding         = "wedding",
}

ACHIEVEMENT_NAME := [Achievement]i18n.Key {
	.Tale_1          = .Ach_Tale_1,
	.Tale_2          = .Ach_Tale_2,
	.Tale_3          = .Ach_Tale_3,
	.Tale_4          = .Ach_Tale_4,
	.Old_Woman       = .Ach_Old_Woman,
	.Trust           = .Ach_Trust,
	.No_Wasted_Light = .Ach_No_Wasted_Light,
	.Wedding         = .Ach_Wedding,
}

ACHIEVEMENT_DESC := [Achievement]i18n.Key {
	.Tale_1          = .Ach_Tale_1_Desc,
	.Tale_2          = .Ach_Tale_2_Desc,
	.Tale_3          = .Ach_Tale_3_Desc,
	.Tale_4          = .Ach_Tale_4_Desc,
	.Old_Woman       = .Ach_Old_Woman_Desc,
	.Trust           = .Ach_Trust_Desc,
	.No_Wasted_Light = .Ach_No_Wasted_Light_Desc,
	.Wedding         = .Ach_Wedding_Desc,
}

@(private)
TALE := [content.Act]Maybe(Achievement) {
	.I        = .Tale_1,
	.II       = .Tale_2,
	.III      = .Tale_3,
	.IV       = .Tale_4,
	.Epilogue = nil, // its fragment counts for the old woman only
}

Progress :: struct {
	completed:    Level_Set,
	fragments:    Fragment_Set,
	achievements: Achievements,
}

// How a level was finished.
Result :: struct {
	level:     int,
	trust:     bool, // the secret ending
	lightings: int, // times the lamp was lit
	lamp_par:  int, // lightings that are enough (0: the level has no par)
}

// The story has been played to the end: the secret ending opens.
game_finished :: proc(p: Progress) -> bool {
	return .Wedding in p.achievements
}

fragment_count :: proc(p: Progress) -> int {
	return card(p.fragments)
}

// A fragment (index into content.FRAGMENTS) was picked up; returns the
// achievements it unlocked.
collect_fragment :: proc(p: ^Progress, fragment: int) -> (unlocked: Achievements) {
	p.fragments += {fragment}
	return award(p, {})
}

// A level was finished; returns the achievements it unlocked.
complete_level :: proc(p: ^Progress, r: Result) -> (unlocked: Achievements) {
	p.completed += {r.level}
	earned: Achievements
	if r.trust {
		earned += {.Trust}
	}
	if r.lamp_par > 0 && r.lightings <= r.lamp_par {
		earned += {.No_Wasted_Light}
	}
	if r.level == content.LEVEL_COUNT - 1 {
		earned += {.Wedding}
	}
	return award(p, earned)
}

// Add `earned` plus everything the collected fragments now justify.
@(private)
award :: proc(p: ^Progress, earned: Achievements) -> (unlocked: Achievements) {
	all := earned
	for act in content.Act {
		a, has := TALE[act].?
		if !has {
			continue
		}
		complete := true
		for f, i in content.FRAGMENTS {
			if content.LEVELS[f.level].act == act && i not_in p.fragments {
				complete = false
			}
		}
		if complete {
			all += {a}
		}
	}
	if card(p.fragments) == content.FRAGMENT_COUNT {
		all += {.Old_Woman}
	}
	unlocked = all - p.achievements
	p.achievements += all
	return
}

// A level can be played when it is built and every built level before it
// has been finished.
is_unlocked :: proc(p: Progress, index: int) -> bool {
	if !content.is_built(index) {
		return false
	}
	for i in 0 ..< index {
		if content.is_built(i) && i not_in p.completed {
			return false
		}
	}
	return true
}

// Where "Enter the palace" leads: the first level still to finish, else the
// last built one.
current_level :: proc(p: Progress) -> int {
	last := 0
	for i in 0 ..< content.LEVEL_COUNT {
		if !content.is_built(i) {
			continue
		}
		if i not_in p.completed {
			return i
		}
		last = i
	}
	return last
}

// --- file ---------------------------------------------------------------------------

load :: proc() -> Progress {
	p: Progress
	path := settings.config_file(FILE_NAME)
	if path == "" {
		return p
	}
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil {
		return p
	}
	parse(string(data), &p)
	return p
}

save :: proc(p: Progress) -> bool {
	return settings.write_config_file(FILE_NAME, serialize(p, context.temp_allocator))
}

serialize :: proc(p: Progress, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintln(&b, "# The Trial of Psyche - progress")
	levels :: proc(b: ^strings.Builder, key: string, set: Level_Set) {
		fmt.sbprintf(b, "%s =", key)
		for info, i in content.LEVELS {
			if i in set {
				fmt.sbprintf(b, " %s", info.id)
			}
		}
		fmt.sbprintln(b)
	}
	levels(&b, "completed", p.completed)
	fmt.sbprint(&b, "fragments =")
	for f, i in content.FRAGMENTS {
		if i in p.fragments {
			fmt.sbprintf(&b, " %s", f.id)
		}
	}
	fmt.sbprintln(&b)
	fmt.sbprint(&b, "achievements =")
	for a in p.achievements {
		fmt.sbprintf(&b, " %s", ACHIEVEMENT_ID[a])
	}
	fmt.sbprintln(&b)
	return strings.to_string(b)
}

// Read `key = value` lines into p; unknown keys, levels and achievements are ignored.
parse :: proc(text: string, p: ^Progress) {
	rest := text
	for raw in strings.split_lines_iterator(&rest) {
		line := strings.trim_space(raw)
		if line == "" || line[0] == '#' {
			continue
		}
		eq := strings.index_byte(line, '=')
		if eq < 0 {
			continue
		}
		key := strings.trim_space(line[:eq])
		values := line[eq + 1:]
		for word in strings.fields_iterator(&values) {
			switch key {
			case "completed":
				for info, i in content.LEVELS {
					if info.id == word {
						p.completed += {i}
					}
				}
			case "fragments":
				for f, i in content.FRAGMENTS {
					if f.id == word {
						p.fragments += {i}
					}
				}
			case "achievements":
				for id, a in ACHIEVEMENT_ID {
					if id == word {
						p.achievements += {a}
					}
				}
			}
		}
	}
}
