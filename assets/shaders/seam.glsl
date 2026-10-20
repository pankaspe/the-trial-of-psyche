// The seam between two skies as the world turns over (render.backdrop_roll),
// joined to the sky, ridges and clouds shaders when they load: the sky going
// away rolls off, the one coming rolls in, and they meet under a band of dark
// matter (seam.fs) that hides where one gives way to the other.
uniform vec4 seam; // x the seam (screen uv, y down), y 1 the sky coming / -1 the one going (cut) / -2 the one going, kept whole / 0 none, w the band's half width (screen uv; < 0: the sky coming is above it)
uniform vec4 rect; // this rectangle in screen uv: x0, y0, width, height (y down)

// How much of this backdrop shows at `uv` (this rectangle's).
float seam_cut(vec2 uv) {
    if (seam.y == 0.0 || seam.y == -2.0) {
        return 1.0;
    }
    float y = rect.y + uv.y * rect.w;
    float d = (y - seam.x) / seam.w; // toward the sky coming
    float k = smoothstep(-0.3, 0.3, d);
    return seam.y > 0.0 ? k : 1.0 - k;
}

