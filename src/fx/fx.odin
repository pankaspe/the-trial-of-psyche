// Small animation helpers: easing curves, a deterministic RNG and fixed-size
// particle pools. Nothing here allocates.
package fx

import "core:math"

// --- easing --------------------------------------------------------------------

// Works for scalars and fixed arrays (vectors).
lerp :: proc(a, b: $T, t: f32) -> T {
	return a + (b - a) * t
}

clamp01 :: proc(x: f32) -> f32 {
	return clamp(x, 0, 1)
}

// Progress of a segment that starts at `start` and lasts `duration`, clamped to 0..1.
progress :: proc(t, start, duration: f32) -> f32 {
	if duration <= 0 {
		return t >= start ? 1 : 0
	}
	return clamp01((t - start) / duration)
}

move_toward :: proc(from, to, step: f32) -> f32 {
	if abs(to - from) <= step {
		return to
	}
	return from + math.sign(to - from) * step
}

sine_in_out :: proc(t: f32) -> f32 {
	return -(math.cos(math.PI * t) - 1) * 0.5
}

quad_in :: proc(t: f32) -> f32 {
	return t * t
}

quad_out :: proc(t: f32) -> f32 {
	return 1 - (1 - t) * (1 - t)
}

cubic_out :: proc(t: f32) -> f32 {
	u := 1 - t
	return 1 - u * u * u
}

// Fade in, hold, fade out; `t` is the time since the start.
envelope :: proc(t, fade_in, hold, fade_out: f32) -> f32 {
	if t < 0 {
		return 0
	}
	if t < fade_in {
		return t / fade_in
	}
	if t < fade_in + hold {
		return 1
	}
	return clamp01(1 - (t - fade_in - hold) / fade_out)
}

// --- random --------------------------------------------------------------------

// xorshift32: tiny, fast and reproducible (tests and replays see the same values).
Rng :: struct {
	state: u32,
}

rng_init :: proc(seed: u32) -> Rng {
	return {seed == 0 ? 0x9e3779b9 : seed}
}

next_u32 :: proc(r: ^Rng) -> u32 {
	x := r.state
	x ~= x << 13
	x ~= x >> 17
	x ~= x << 5
	r.state = x
	return x
}

// Uniform in [0, 1).
randf :: proc(r: ^Rng) -> f32 {
	return f32(next_u32(r) >> 8) / f32(1 << 24)
}

rand_range :: proc(r: ^Rng, lo, hi: f32) -> f32 {
	return lo + (hi - lo) * randf(r)
}

// Stateless hash of an integer to [0, 1): per-piece random values without storage.
hash01 :: proc(i: u32) -> f32 {
	x := i * 0x9e3779b1 + 0x7f4a7c15
	x ~= x >> 15
	x *= 0x2c1b3c6d
	x ~= x >> 12
	x *= 0x297a2d39
	x ~= x >> 15
	return f32(x >> 8) / f32(1 << 24)
}

// --- particles -----------------------------------------------------------------

Particle :: struct {
	pos:   [3]f32,
	vel:   [3]f32,
	accel: [3]f32,
	age:   f32,
	life:  f32,
	size:  f32,
	color: [4]f32,
}

// A pool of N particles; dead slots are reused, the oldest is replaced when full.
Pool :: struct($N: int) {
	items: [N]Particle,
	count: int,
}

emit :: proc(pool: ^Pool($N), p: Particle) {
	if pool.count < N {
		pool.items[pool.count] = p
		pool.count += 1
		return
	}
	oldest := 0
	for it, i in pool.items {
		if it.age / it.life > pool.items[oldest].age / pool.items[oldest].life {
			oldest = i
		}
	}
	pool.items[oldest] = p
}

update :: proc(pool: ^Pool($N), dt: f32) {
	i := 0
	for i < pool.count {
		p := &pool.items[i]
		p.age += dt
		if p.age >= p.life {
			pool.count -= 1
			pool.items[i] = pool.items[pool.count]
			continue
		}
		p.vel += p.accel * dt
		p.pos += p.vel * dt
		i += 1
	}
}

clear_pool :: proc(pool: ^Pool($N)) {
	pool.count = 0
}

alive :: proc(pool: ^Pool($N)) -> []Particle {
	return pool.items[:pool.count]
}

// Alpha of a mote over its life: fades in, holds, fades out.
mote_alpha :: proc(p: Particle) -> f32 {
	u := p.age / p.life
	if u < 0.3 {
		return u / 0.3
	}
	if u > 0.7 {
		return (1 - u) / 0.3
	}
	return 1
}
