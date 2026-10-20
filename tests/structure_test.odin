// Game structure: acts and levels, the save file, achievements, fragments of
// the tale, the canonical and secret endings, levels that end at an exit.
package tests

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

import "../src/content"
import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/level"
import "../src/palace"
import "../src/progress"
import "../src/settings"

@(test)
acts_and_levels :: proc(t: ^testing.T) {
	testing.expect(t, content.LEVEL_COUNT == 20, "twenty levels")
	per_act: [content.Act]int
	seen_fragment: [i18n.Key]bool
	for info, i in content.LEVELS {
		per_act[info.act] += 1
		if i > 0 {
			testing.expectf(t, info.act >= content.LEVELS[i - 1].act, "%s: acts follow each other in order", info.id)
		}
		for other, j in content.LEVELS {
			testing.expectf(t, i == j || info.id != other.id, "level id %s is unique", info.id)
		}
		_, count := content.level_fragments(i)
		testing.expectf(t, count >= 1, "%s hides a fragment", info.id)
	}
	for f, i in content.FRAGMENTS {
		testing.expectf(t, !seen_fragment[f.key], "fragment %s has its own text", f.id)
		seen_fragment[f.key] = true
		if i > 0 {
			testing.expectf(t, f.level >= content.FRAGMENTS[i - 1].level, "fragment %s: in level order", f.id)
		}
		for other, j in content.FRAGMENTS {
			testing.expectf(t, i == j || f.id != other.id, "fragment id %s is unique", f.id)
		}
	}
	testing.expect(t, per_act == {.I = 4, .II = 4, .III = 5, .IV = 6, .Epilogue = 1}, "4 + 4 + 5 + 6 levels and an epilogue")
	for i in ([?]int{0, 4, 8, 13, 19}) {
		testing.expectf(t, content.opens_act(i), "level %s opens an act", content.LEVELS[i].id)
	}
	testing.expect(t, !content.opens_act(3) && content.closes_act(3), "I.4 closes Act I")

	// the Book: every fragment exactly once
	in_book: [content.FRAGMENT_COUNT]int
	for i in content.BOOK_ORDER {
		in_book[i] += 1
	}
	for n, i in in_book {
		testing.expectf(t, n == 1, "fragment %s appears once in the Book (%d)", content.FRAGMENTS[i].id, n)
	}
}

@(test)
progress_round_trip :: proc(t: ^testing.T) {
	p: progress.Progress
	p.completed = {0, 3}
	p.fragments = {3, 4, 20}
	p.achievements = {.Trust, .No_Wasted_Light}
	p.resume = {level = 12, diorama = 2, lightings = 3, lamp_par = 3}
	p.aids = {.Sense, .Endless_Oil}
	text := progress.serialize(p, context.temp_allocator)
	back: progress.Progress
	progress.parse(text, &back)
	testing.expectf(t, back == p, "progress survives a save and a load:\n%v\n%v\n%s", p, back, text)
	testing.expect(t, progress.resume_at(back, 12) == 2 && progress.resume_at(back, 11) == 0, "a level left half way goes on from the diorama reached")
	progress.complete_level(&back, {level = 12})
	testing.expect(t, back.resume == {}, "finished, it starts from its first diorama again")

	odd: progress.Progress
	progress.parse("completed = I.4 Z.9\nfragments = nothing\nachievements = trust flying\ngarbage\n", &odd)
	testing.expect(t, odd.completed == {3} && odd.fragments == {} && odd.achievements == {.Trust}, "unknown ids are ignored")
	testing.expect(t, odd.aids == progress.DIFFICULTY_AIDS[.Normal], "a game saved before the aids plays with Normal's")
	puzzle: progress.Progress
	progress.parse(progress.serialize({aids = {}}, context.temp_allocator), &puzzle)
	testing.expect(t, puzzle.aids == {}, "no aids at all is kept")
}

@(test)
progress_sealed :: proc(t: ^testing.T) {
	text := "completed = I.1 I.2\n"
	sealed := progress.seal(text, context.temp_allocator)
	testing.expect(t, strings.index(string(sealed), "I.1") < 0, "the sealed save can't be read")
	back, ok := progress.unseal(sealed, context.temp_allocator)
	testing.expect(t, ok && back == text, "a sealed save opens again")
	again := progress.seal(text, context.temp_allocator)
	testing.expect(t, string(again) != string(sealed), "each save has its own nonce")
	for at in ([]int{0, 5, len(sealed) - 1}) {
		edited := slice.clone(sealed, context.temp_allocator)
		edited[at] ~= 1
		_, opened := progress.unseal(edited, context.temp_allocator)
		testing.expectf(t, !opened, "a save edited at byte %d is refused", at)
	}
	_, cut := progress.unseal(sealed[:len(sealed) - 2], context.temp_allocator)
	testing.expect(t, !cut, "a cut save is refused")
	_, plain := progress.unseal(transmute([]byte)text, context.temp_allocator)
	testing.expect(t, !plain, "a plain file is not a save")

	old: progress.Progress
	progress.parse_legacy("completed = I.1 III.3 III.4 E\nfragments = I.1 III.3b III.4\nachievements = tale_1 trust wedding no_wasted_light\n", &old)
	testing.expect(t, old.completed == {0, 10} && old.fragments == {0, 22}, "a plain save keeps only the levels built while saves were plain")
	testing.expect(t, old.achievements == {.Tale_1, .No_Wasted_Light}, "a plain save can't finish the game")
}

@(test)
achievements :: proc(t: ^testing.T) {
	p: progress.Progress
	got: progress.Achievements
	ACT_1 :: 6 // I.3 and I.4 hide two each
	for i in 0 ..< ACT_1 - 1 {
		unlocked, _ := progress.collect_fragment(&p, i)
		got += unlocked
	}
	testing.expect(t, got == {}, "all but one fragment of Act I are not the whole act")
	found, total := progress.act_fragments(p, .I)
	testing.expect(t, found == ACT_1 - 1 && total == ACT_1, "all but one of Act I's pages in the Book")
	new_page: bool
	got, new_page = progress.collect_fragment(&p, ACT_1 - 1)
	testing.expect(t, got == {.Tale_1} && new_page, "every fragment of Act I")
	got, new_page = progress.collect_fragment(&p, ACT_1 - 1)
	testing.expect(t, got == {} && !new_page, "an achievement is unlocked only once, a page is new only once")
	for i in ACT_1 ..< content.FRAGMENT_COUNT - 1 {
		got, _ = progress.collect_fragment(&p, i)
	}
	testing.expect(t, .Tale_4 in p.achievements && .Old_Woman not_in p.achievements, "every act, but not yet the epilogue")
	got, _ = progress.collect_fragment(&p, content.FRAGMENT_COUNT - 1)
	testing.expect(t, got == {.Old_Woman}, "the last fragment reveals the frame")

	old: progress.Progress
	progress.parse("fragments = I.3 I.4\n", &old)
	testing.expect(t, old.fragments == {2, 4}, "a save from before the second fragment of I.3 keeps its fragments")

	q: progress.Progress
	testing.expect(t, progress.complete_level(&q, {level = 3, lightings = 3, lamp_par = 2}) == {}, "a wasted light")
	testing.expect(t, progress.complete_level(&q, {level = 3, lightings = 2, lamp_par = 2}) == {.No_Wasted_Light}, "only the light that was needed")
	testing.expect(t, progress.complete_level(&q, {level = 5, lightings = 0, lamp_par = 0}) == {}, "levels without a par give nothing")
	testing.expect(t, !progress.game_finished(q), "the game is not finished")
	testing.expect(t, progress.complete_level(&q, {level = content.LEVEL_COUNT - 1}) == {.Wedding}, "the epilogue finishes the game")
	testing.expect(t, progress.game_finished(q), "the secret ending opens")
	testing.expect(t, progress.complete_level(&q, {level = 3, trust = true}) == {.Trust}, "the secret ending")
}

@(test)
level_unlocking :: proc(t: ^testing.T) {
	p: progress.Progress
	first := -1
	for i in 0 ..< content.LEVEL_COUNT {
		if content.is_built(i) {
			first = i
			break
		}
	}
	testing.expect(t, first >= 0, "at least one level is built")
	testing.expect(t, progress.is_unlocked(p, first), "the first built level is open")
	testing.expect(t, progress.current_level(p) == first, "a new game starts at the first built level")
	for i in 0 ..< content.LEVEL_COUNT {
		if !content.is_built(i) {
			testing.expectf(t, !progress.is_unlocked(p, i), "%s is not built: it cannot be played", content.LEVELS[i].id)
		}
	}
	p.completed += {first}
	testing.expect(t, progress.is_unlocked(p, first), "a finished level can be played again")
}

@(private)
FRAGMENT :: iso.Cell{3, 11, 6}
@(private)
LAST_PILLAR :: iso.Cell{1, 10, 5} // joined to the fragment's pillar in view 0

@(test)
fragment_of_the_tale :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	testing.expect(t, len(g.data.fragments) == 1 && g.data.fragments[0] == FRAGMENT, "I.4 hides its fragment on a pillar")
	g.psyche.cell = LAST_PILLAR
	found := false
	for r in 0 ..< 4 {
		game.set_view(&g, r)
		path: palace.Path
		if palace.find_path(&g.palace, LAST_PILLAR, FRAGMENT, true, &path) {
			found = walk(t, &g, FRAGMENT)
			break
		}
	}
	testing.expect(t, found, "one view joins the last pillar to the fragment's")
	testing.expect(t, 0 in g.fragments_taken && g.fragment_new, "Psyche picks up the fragment")
	testing.expect(t, game.fragment_key(&g, 0) == i18n.Key.Fragment_04, "the fragment of I.4")

	// collected in an earlier play: it stays collected
	h: game.Game
	defer game.destroy(&h)
	if !start(t, &h) {
		return
	}
	h.fragments_known = {0}
	h.psyche.cell = LAST_PILLAR
	for r in 0 ..< 4 {
		game.set_view(&h, r)
		path: palace.Path
		if palace.find_path(&h.palace, LAST_PILLAR, FRAGMENT, true, &path) {
			walk(t, &h, FRAGMENT)
			break
		}
	}
	testing.expect(t, !h.fragment_new, "a fragment is found only once")
}

// Before the game is finished, reaching Cupid in the dark ends nothing: the
// story goes on with the lamp.
@(test)
trust_waits_for_the_end_of_the_game :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g, diorama = 1) {
		return
	}
	in_chamber(&g)
	testing.expect(t, walk(t, &g, BEDSIDE), "Psyche walks to Cupid's side")
	run(&g, 6)
	testing.expect(t, g.phase == .Play && g.heard[i18n.Key.V_Doubt], "no secret ending yet: Psyche doubts")
	game.toggle_lamp(&g)
	testing.expect(t, g.lightings == 1, "the lighting is counted")
	run(&g, 10)
	testing.expect(t, g.phase == .Finished && g.ending == .Oil, "the lamp: the canonical ending")
}

// Two lines said one right after the other: the second waits for the first.
@(private)
VOICE_LEVEL :: `
size 4
column 0 0 0 0
column 1 0 0 0
column 2 0 0 0
start 0 0 1
voice 1 0 1 intro_i_2
voice 2 0 1 intro_i_3
`

@(test)
voices_wait_their_turn :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if err := game.load_text(&g, 0, VOICE_LEVEL); err != nil {
		testing.expect(t, false, "the test level does not load")
		return
	}
	game.begin(&g)
	testing.expect(t, walk(t, &g, {1, 0, 1}) && walk(t, &g, {2, 0, 1}), "Psyche walks over both voices")
	testing.expect(t, g.hud.voice.key == i18n.Key.Intro_I_2, "the second line does not cut off the first")
	for i := 0; i < 60 * 30 && g.hud.voice.key != i18n.Key.Intro_I_3; i += 1 {
		run(&g, 1.0 / 60)
	}
	testing.expect(t, g.hud.voice.active && g.hud.voice.key == i18n.Key.Intro_I_3, "then it is spoken")
}

@(private)
DARK_LEVEL :: `
size 5
column 0 0 0 0
column 1 0 0 0
column 2 0 0 0
column 2 1 0 0
start 0 0 1
exit 2 1 1
fragment 2 0 1
`

@(test)
dark_level_with_an_exit :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if err := game.load_text(&g, 0, DARK_LEVEL); err != nil {
		testing.expect(t, false, "the test level does not load")
		return
	}
	game.begin(&g)
	game.toggle_lamp(&g)
	testing.expect(t, !g.lamp_on && g.lightings == 0, "no lamp in this level")
	testing.expect(t, walk(t, &g, {2, 0, 1}) && 0 in g.fragments_taken, "Psyche picks up the fragment on the way")
	testing.expect(t, walk(t, &g, {2, 1, 1}), "then walks on to the exit")
	run(&g, game.PART_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the exit ends the level")
}

// DARK_LEVEL, then a second diorama: one level of two.
@(private)
TWO_DIORAMAS :: DARK_LEVEL + `
diorama
size 5
column 0 0 0 0
column 1 0 0 0
column 1 1 0 0
start 0 0 1
exit 1 1 1
fragment 1 0 1
`

@(test)
a_level_of_two_dioramas :: proc(t: ^testing.T) {
	parts := level.dioramas(TWO_DIORAMAS)
	testing.expect(t, len(parts) == 2, "two dioramas in the text")
	g: game.Game
	defer game.destroy(&g)
	if err := game.load_text(&g, 0, TWO_DIORAMAS); err != nil {
		testing.expect(t, false, "the test level does not load")
		return
	}
	testing.expect(t, g.diorama == 0 && g.dioramas == 2 && game.leads_on(&g), "the first diorama leads on")
	game.begin(&g)
	testing.expect(t, walk(t, &g, {2, 0, 1}) && walk(t, &g, {2, 1, 1}), "Psyche walks to the first exit (a fragment on the way)")
	run(&g, game.PART_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the first diorama ends at its exit")

	if err := game.load_text(&g, 0, TWO_DIORAMAS, 1); err != nil {
		testing.expect(t, false, "the second diorama does not load")
		return
	}
	testing.expect(t, g.diorama == 1 && !game.leads_on(&g), "the second diorama is the last")
	testing.expect(t, g.psyche.cell == {0, 0, 1} && len(g.data.fragments) == 1, "the second diorama is its own palace")
	testing.expect(t, g.fragment_base == 1, "its fragment comes after the first diorama's")
	game.begin(&g, arrival = true)
	run(&g, game.ARRIVE_END + 0.2)
	testing.expect(t, g.phase == .Play && !g.hud.title.active, "it rises into place without the level's title")
	testing.expect(t, walk(t, &g, {1, 0, 1}) && walk(t, &g, {1, 1, 1}), "Psyche walks to the last exit (a fragment on the way)")
	run(&g, game.PART_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the level ends")
}

// The games side by side, in a config directory of their own: the single save
// of the builds before becomes slot 1; a slot saved is there, erased is empty.
@(test)
progress_slots :: proc(t: ^testing.T) {
	dir := fmt.tprintf("%s/trial-of-psyche-slots-test", os.temp_directory(context.temp_allocator) or_else "/tmp")
	os.remove_all(dir)
	os.set_env("XDG_CONFIG_HOME", dir)
	defer os.remove_all(dir)
	before := progress.Progress{completed = {0, 1}, fragments = {0}}
	text := progress.serialize(before, context.temp_allocator)
	testing.expect(t, settings.write_config_file(progress.OLD_FILE_NAME, string(progress.seal(text, context.temp_allocator))), "the old save is written")
	progress.migrate()
	one, used := progress.load(1)
	testing.expect(t, used && one == before, "the old save is slot 1")
	testing.expect(t, !os.exists(settings.config_file(progress.OLD_FILE_NAME)), "the old save is gone")
	testing.expect(t, !progress.peek(3).used, "slot 3 is empty")
	testing.expect(t, progress.save({completed = {0}}, 3), "slot 3 saved")
	testing.expect(t, progress.peek(3).used && progress.peek(3).prog.completed == {0}, "slot 3 holds its game")
	progress.erase(3)
	testing.expect(t, !progress.peek(3).used, "slot 3 erased")
	again, _ := progress.load(1)
	testing.expect(t, again == before, "slot 1 untouched")
}
