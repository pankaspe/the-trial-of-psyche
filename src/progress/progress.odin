// The player's progress: levels finished, fragments of the tale collected,
// achievements. Written as `key = value` lines, then sealed (ChaCha20-Poly1305)
// into a file next to the settings (~/.config/the-trial-of-psyche/save1.sav
// on Linux), so that it can't be read or edited by hand: a file that doesn't
// open is a new game. Up to SLOTS games, one file each. The key is in the binary (and in this open source): it
// keeps casual hands out, not a determined player. Levels and fragments are
// stored by their stable id ("I.4", "I.3b"), so adding levels never breaks a
// save; unknown ids and lines are ignored.
//
// The rules here are pure (no IO, no game state): the app reports what
// happened, this package answers with the achievements it unlocked. If the
// game ever ships on Steam, these are the events to forward.
package progress

import "core:crypto"
import "core:crypto/chacha20poly1305"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

import "../content"
import "../i18n"
import "../settings"

SLOTS :: settings.SAVE_SLOTS // games kept side by side, one file each ("save1.sav" ...)
// The single save of the builds before the slots: it becomes slot 1.
OLD_FILE_NAME :: "progress.sav"
// The plain save of the builds before, read once when there is no sealed one,
// then removed.
LEGACY_FILE_NAME :: "progress.cfg"
// The last level built while saves were plain: a plain file written by hand
// can't give more than those builds could.
LEGACY_LAST_LEVEL :: "III.3"

#assert(content.LEVEL_COUNT <= 32)
Level_Set :: bit_set[0 ..< 32] // indices into content.LEVELS
#assert(content.FRAGMENT_COUNT <= 64)
Fragment_Set :: bit_set[0 ..< 64] // indices into content.FRAGMENTS

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
	resume:       Resume,
}

// Where a level of several dioramas was left: the diorama reached, played
// again from its start (0: none), and what the dioramas done before it
// carried for the lamp's achievement.
Resume :: struct {
	level:     int,
	diorama:   int,
	lightings: int,
	lamp_par:  int,
}

// The diorama level `index` starts from: the one reached, else its first.
resume_at :: proc(p: Progress, index: int) -> int {
	return p.resume.level == index ? p.resume.diorama : 0
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
// achievements it unlocked and whether it is new to the Book.
collect_fragment :: proc(p: ^Progress, fragment: int) -> (unlocked: Achievements, new_page: bool) {
	new_page = fragment not_in p.fragments
	p.fragments += {fragment}
	return award(p, {}), new_page
}

// How many of an act's fragments are in the Book, out of how many.
act_fragments :: proc(p: Progress, act: content.Act) -> (found, total: int) {
	for f, i in content.FRAGMENTS {
		if content.LEVELS[f.level].act == act {
			total += 1
			if i in p.fragments {
				found += 1
			}
		}
	}
	return
}

// How many of a level's fragments are in the Book.
level_fragments :: proc(p: Progress, level: int) -> (found: int) {
	first, n := content.level_fragments(level)
	for k in 0 ..< n {
		found += int(first + k in p.fragments)
	}
	return
}

// A level was finished; returns the achievements it unlocked.
complete_level :: proc(p: ^Progress, r: Result) -> (unlocked: Achievements) {
	p.completed += {r.level}
	if p.resume.level == r.level {
		p.resume = {}
	}
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
		if found, total := act_fragments(p^, act); found == total {
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

// The file of a slot (1 ..= SLOTS), in the temp allocator.
slot_file :: proc(slot: int) -> string {
	return fmt.tprintf("save%d.sav", slot)
}

// The saves of the builds before move into slot 1, once: the single sealed
// save, or else the plain one (capped, see parse_legacy).
migrate :: proc() {
	first := settings.config_file(slot_file(1))
	if first == "" || os.exists(first) {
		return
	}
	if old := settings.config_file(OLD_FILE_NAME); os.exists(old) {
		os.rename(old, first)
		return
	}
	legacy := settings.config_file(LEGACY_FILE_NAME)
	if data, err := os.read_entire_file_from_path(legacy, context.temp_allocator); err == nil {
		p: Progress
		parse_legacy(string(data), &p)
		if save(p, 1) {
			os.remove(legacy)
		}
	}
}

// A slot's game; `used` is false when the slot is empty (or its file does not open).
load :: proc(slot: int) -> (p: Progress, used: bool) {
	path := settings.config_file(slot_file(slot))
	if path == "" {
		return
	}
	if data, err := os.read_entire_file_from_path(path, context.temp_allocator); err == nil {
		if text, ok := unseal(data, context.temp_allocator); ok {
			parse(text, &p)
			used = true
		}
	}
	return
}

// What the list of games shows of a slot: its game and when it was last saved.
Slot_Info :: struct {
	used:  bool,
	prog:  Progress,
	saved: time.Time,
}

peek :: proc(slot: int) -> (info: Slot_Info) {
	info.prog, info.used = load(slot)
	if info.used {
		if fi, err := os.stat(settings.config_file(slot_file(slot)), context.temp_allocator); err == nil {
			info.saved = fi.modification_time
		}
	}
	return
}

// The slot's game is gone for good.
erase :: proc(slot: int) {
	if path := settings.config_file(slot_file(slot)); path != "" {
		os.remove(path)
	}
}

// Write a slot's save and read it back: what is on disk must open to the same
// text (a save that does not is written again, once). Built in the heap, not
// in the frame's scratch memory.
save :: proc(p: Progress, slot: int) -> bool {
	heap := runtime.heap_allocator()
	text := serialize(p, heap)
	defer delete(text, heap)
	name := slot_file(slot)
	for _ in 0 ..< 2 {
		sealed := seal(text, heap)
		written := settings.write_config_file(name, string(sealed))
		delete(sealed, heap)
		if !written {
			return false
		}
		data, err := os.read_entire_file_from_path(settings.config_file(name), heap)
		if err != nil {
			continue
		}
		back, ok := unseal(data, heap)
		same := ok && back == text
		delete(data, heap)
		if ok {
			delete(back, heap)
		}
		if same {
			return true
		}
	}
	return false
}

// A plain save, kept only as far as the builds that wrote one could go.
parse_legacy :: proc(text: string, p: ^Progress) {
	parse(text, p)
	last := 0
	for info, i in content.LEVELS {
		if info.id == LEGACY_LAST_LEVEL {
			last = i
		}
	}
	for i in last + 1 ..< content.LEVEL_COUNT {
		p.completed -= {i}
	}
	for f, i in content.FRAGMENTS {
		if f.level > last {
			p.fragments -= {i}
		}
	}
	p.achievements &= {.Tale_1, .Tale_2, .No_Wasted_Light}
}

// --- sealing ------------------------------------------------------------------------

@(private)
MAGIC :: "PSY1"

@(private)
KEY := [chacha20poly1305.KEY_SIZE]byte {
	0x3c, 0x9a, 0x51, 0xe7, 0x08, 0xd4, 0x6b, 0x2f, 0xa1, 0x77, 0xc5, 0x13, 0x8e, 0x40, 0xf9, 0x26,
	0x5d, 0xb2, 0x0e, 0x94, 0x6a, 0xc8, 0x31, 0x7f, 0xe3, 0x15, 0x9c, 0x48, 0xd7, 0x62, 0xab, 0x04,
}

// MAGIC, a random nonce, the tag, then the text encrypted; MAGIC is authenticated too.
// The portable ChaCha20: the SIMD one gets the second 64-byte block wrong in
// debug builds (it wrote saves that open to garbage, and read good ones so).
seal :: proc(text: string, allocator := context.allocator) -> []byte {
	N :: chacha20poly1305.IV_SIZE
	T :: chacha20poly1305.TAG_SIZE
	out := make([]byte, len(MAGIC) + N + T + len(text), allocator)
	copy(out, MAGIC)
	nonce := out[len(MAGIC):][:N]
	tag := out[len(MAGIC) + N:][:T]
	body := out[len(MAGIC) + N + T:]
	crypto.rand_bytes(nonce)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init(&ctx, KEY[:], .Portable)
	chacha20poly1305.seal(&ctx, body, tag, nonce, transmute([]byte)string(MAGIC), transmute([]byte)text)
	return out
}

// The text sealed in data; ok is false when the file was edited, cut or isn't a save.
unseal :: proc(data: []byte, allocator := context.allocator) -> (text: string, ok: bool) {
	N :: chacha20poly1305.IV_SIZE
	T :: chacha20poly1305.TAG_SIZE
	if len(data) < len(MAGIC) + N + T || string(data[:len(MAGIC)]) != MAGIC {
		return "", false
	}
	nonce := data[len(MAGIC):][:N]
	tag := data[len(MAGIC) + N:][:T]
	body := data[len(MAGIC) + N + T:]
	out := make([]byte, len(body), allocator)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init(&ctx, KEY[:], .Portable)
	if !chacha20poly1305.open(&ctx, out, nonce, transmute([]byte)string(MAGIC), body, tag) {
		delete(out, allocator)
		return "", false
	}
	return string(out), true
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
	if r := p.resume; r.diorama > 0 {
		fmt.sbprintfln(&b, "resume = %s %d %d %d", content.LEVELS[r.level].id, r.diorama, r.lightings, r.lamp_par)
	}
	return strings.to_string(b)
}

// Read `key = value` lines into p; unknown keys, levels and achievements are ignored.
parse :: proc(text: string, p: ^Progress) {
	rest := text
	for key, line in settings.config_entries(&rest) {
		if key == "resume" {
			parse_resume(line, p)
			continue
		}
		values := line
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

// "III.5 2 3 3": the level's id, the diorama reached, the lightings and the
// lamp's par carried; anything else is ignored.
@(private)
parse_resume :: proc(line: string, p: ^Progress) {
	words := strings.fields(line, context.temp_allocator)
	if len(words) != 4 {
		return
	}
	r: Resume
	ok1, ok2, ok3: bool
	r.diorama, ok1 = strconv.parse_int(words[1])
	r.lightings, ok2 = strconv.parse_int(words[2])
	r.lamp_par, ok3 = strconv.parse_int(words[3])
	if !ok1 || !ok2 || !ok3 || r.diorama <= 0 {
		return
	}
	for info, i in content.LEVELS {
		if info.id == words[0] {
			r.level = i
			p.resume = r
		}
	}
}
