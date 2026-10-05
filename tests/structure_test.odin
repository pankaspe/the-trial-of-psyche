// Game structure: acts and levels, the save file, achievements, fragments of
// the tale, the canonical and secret endings, levels that end at an exit.
package tests

import "core:testing"

import "../src/content"
import "../src/game"
import "../src/i18n"
import "../src/iso"
import "../src/palace"
import "../src/progress"

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
		testing.expectf(t, !seen_fragment[info.fragment], "%s has its own fragment", info.id)
		seen_fragment[info.fragment] = true
	}
	testing.expect(t, per_act == {.I = 4, .II = 5, .III = 5, .IV = 5, .Epilogue = 1}, "4 + 5 + 5 + 5 levels and an epilogue")
	for i in ([?]int{0, 4, 9, 14, 19}) {
		testing.expectf(t, content.opens_act(i), "level %s opens an act", content.LEVELS[i].id)
	}
	testing.expect(t, !content.opens_act(3) && content.closes_act(3), "I.4 closes Act I")

	// the Book: every fragment exactly once
	in_book: [content.LEVEL_COUNT]int
	for i in content.BOOK_ORDER {
		in_book[i] += 1
	}
	for n, i in in_book {
		testing.expectf(t, n == 1, "fragment of %s appears once in the Book (%d)", content.LEVELS[i].id, n)
	}
}

@(test)
progress_round_trip :: proc(t: ^testing.T) {
	p: progress.Progress
	p.completed = {0, 3}
	p.fragments = {3, 19}
	p.achievements = {.Trust, .No_Wasted_Light}
	text := progress.serialize(p, context.temp_allocator)
	back: progress.Progress
	progress.parse(text, &back)
	testing.expectf(t, back == p, "progress survives a save and a load:\n%v\n%v\n%s", p, back, text)

	odd: progress.Progress
	progress.parse("completed = I.4 Z.9\nfragments = nothing\nachievements = trust flying\ngarbage\n", &odd)
	testing.expect(t, odd.completed == {3} && odd.fragments == {} && odd.achievements == {.Trust}, "unknown ids are ignored")
}

@(test)
achievements :: proc(t: ^testing.T) {
	p: progress.Progress
	got: progress.Achievements
	for i in 0 ..< 3 {
		got += progress.collect_fragment(&p, i)
	}
	testing.expect(t, got == {}, "three fragments of Act I are not the whole act")
	got = progress.collect_fragment(&p, 3)
	testing.expect(t, got == {.Tale_1}, "the four fragments of Act I")
	testing.expect(t, progress.collect_fragment(&p, 3) == {}, "an achievement is unlocked only once")
	for i in 4 ..< content.LEVEL_COUNT - 1 {
		got = progress.collect_fragment(&p, i)
	}
	testing.expect(t, .Tale_4 in p.achievements && .Old_Woman not_in p.achievements, "every act, but not yet the epilogue")
	got = progress.collect_fragment(&p, content.LEVEL_COUNT - 1)
	testing.expect(t, got == {.Old_Woman}, "the twentieth fragment reveals the frame")

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
FRAGMENT :: iso.Cell{2, 7, 4}

@(test)
fragment_of_the_tale :: proc(t: ^testing.T) {
	g: game.Game
	defer game.destroy(&g)
	if !start(t, &g) {
		return
	}
	testing.expect(t, g.data.has_fragment && g.data.fragment == FRAGMENT, "I.4 hides its fragment on a pillar")
	g.psyche.cell = BALCONY
	found := false
	for r in 0 ..< 4 {
		game.set_view(&g, r)
		path: palace.Path
		if palace.find_path(&g.palace, BALCONY, FRAGMENT, true, &path) {
			found = walk(t, &g, FRAGMENT)
			break
		}
	}
	testing.expect(t, found, "one view joins the pillar to the balcony")
	testing.expect(t, g.fragment_taken && g.fragment_new, "Psyche picks up the fragment")
	testing.expect(t, game.fragment_key(&g) == i18n.Key.Fragment_04, "the fragment of I.4")

	// collected in an earlier play: it stays collected
	h: game.Game
	defer game.destroy(&h)
	if !start(t, &h) {
		return
	}
	h.fragment_known = true
	h.psyche.cell = BALCONY
	for r in 0 ..< 4 {
		game.set_view(&h, r)
		path: palace.Path
		if palace.find_path(&h.palace, BALCONY, FRAGMENT, true, &path) {
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
	if !start(t, &g) {
		return
	}
	g.palace.risen = true
	palace.rebuild_graph(&g.palace)
	game.set_view(&g, 3)
	g.activated = true
	g.psyche.cell = BRIDGE
	testing.expect(t, walk(t, &g, ROOF_ENTRY), "Psyche reaches the roof")
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
	testing.expect(t, walk(t, &g, {2, 0, 1}) && g.fragment_taken, "Psyche picks up the fragment on the way")
	testing.expect(t, walk(t, &g, {2, 1, 1}), "then walks on to the exit")
	run(&g, game.EXIT_END + 0.5)
	testing.expect(t, g.phase == .Finished && g.ending == .Exit, "the exit ends the level")
}
