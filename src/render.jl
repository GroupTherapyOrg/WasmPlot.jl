# render.jl — Walk Figure → Axis → Plot tree and emit Canvas2D calls
#
# Every function calls Canvas2D import stubs. No abstract dispatch.
# All types are concrete — compiles directly to WASM via WasmTarget.

const TWO_PI = 2.0 * π

"""
    render!(fig::Figure)

Render the entire figure to the current Canvas2D context.
"""
function render!(fig::Figure)
    w = Float64(fig.width)
    h = Float64(fig.height)

    canvas_clear_rect(0.0, 0.0, w, h)
    _set_fill(fig.backgroundcolor)
    canvas_fill_rect(0.0, 0.0, w, h)

    for ax in fig.axes
        vp = compute_viewport(ax, fig)
        _render_axis!(ax, vp, fig.fontsize)
    end
end

function _render_axis!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top

    _set_fill(ax.backgroundcolor)
    canvas_fill_rect(vp.plot_left, vp.plot_top, pw, ph)

    _render_grid!(ax, vp)

    canvas_save()
    for p in ax.heatmap_plots; _render_heatmap!(p, vp); end
    for p in ax.line_plots;    _render_line!(p, vp); end
    for p in ax.scatter_plots; _render_scatter!(p, vp); end
    for p in ax.bar_plots;     _render_bar!(p, vp); end
    canvas_restore()

    _render_spines!(ax, vp)
    _render_ticks!(ax, vp, fontsize)
    _render_labels!(ax, vp, fontsize)
end

# ─── Grid ───

function _render_grid!(ax::Axis, vp::AxisViewport)
    if !ax.xgridvisible && !ax.ygridvisible; return; end

    canvas_set_line_width(1.0)  # Makie default: 1.0
    _set_stroke(ax.gridcolor)

    if ax.xgridvisible
        for t in vp.xticks
            px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
            canvas_begin_path(); canvas_move_to(px, vp.plot_top)
            canvas_line_to(px, vp.plot_bottom); canvas_stroke()
        end
    end
    if ax.ygridvisible
        for t in vp.yticks
            py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
            canvas_begin_path(); canvas_move_to(vp.plot_left, py)
            canvas_line_to(vp.plot_right, py); canvas_stroke()
        end
    end
end

# ─── Spines ───

function _render_spines!(ax::Axis, vp::AxisViewport)
    _set_stroke(ax.spinecolor)
    canvas_set_line_width(1.0)
    canvas_stroke_rect(vp.plot_left, vp.plot_top,
                       vp.plot_right - vp.plot_left,
                       vp.plot_bottom - vp.plot_top)
end

# ─── Ticks ───

function _render_ticks!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    tick_len = 5.0
    label_size = fontsize

    _set_stroke(ax.spinecolor)
    _set_fill(RGBA(0.0, 0.0, 0.0))
    canvas_set_line_width(1.0)
    canvas_set_font_size(label_size)

    for t in vp.xticks
        px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        canvas_begin_path(); canvas_move_to(px, vp.plot_bottom)
        canvas_line_to(px, vp.plot_bottom + tick_len); canvas_stroke()
        _draw_text_prop(_format_tick(t), px, vp.plot_bottom + tick_len + label_size, label_size, Int64(0))  # 0 = center
    end
    for t in vp.yticks
        py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        canvas_begin_path(); canvas_move_to(vp.plot_left - tick_len, py)
        canvas_line_to(vp.plot_left, py); canvas_stroke()
        _draw_text_prop(_format_tick(t), vp.plot_left - tick_len - 3.0, py + label_size * 0.35, label_size, Int64(1))  # 1 = right
    end
end

function _render_labels!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    _set_fill(RGBA(0.0, 0.0, 0.0))
    title_size = fontsize * 1.15
    axis_size  = fontsize

    subtitle_size = fontsize * 0.85
    cx = (vp.plot_left + vp.plot_right) / 2.0

    if length(ax.title) > 0
        canvas_set_font_size(title_size)
        if length(ax.subtitle) > 0
            _draw_text_prop(ax.title, cx, vp.plot_top - subtitle_size - 10.0, title_size, Int64(0))
        else
            _draw_text_prop(ax.title, cx, vp.plot_top - 8.0, title_size, Int64(0))
        end
    end
    if length(ax.subtitle) > 0
        canvas_set_font_size(subtitle_size)
        _draw_text_prop(ax.subtitle, cx, vp.plot_top - 6.0, subtitle_size, Int64(0))
    end

    if length(ax.xlabel) > 0
        canvas_set_font_size(axis_size)
        cx = (vp.plot_left + vp.plot_right) / 2.0
        _draw_text_prop(ax.xlabel, cx, vp.plot_bottom + 45.0, axis_size, Int64(0))
    end

    # Y label — rotated -π/2 (Makie/CairoMakie convention):
    #   ctx.save(); ctx.translate(anchor_x, anchor_y); ctx.rotate(-π/2);
    #   draw_centered(ylabel, 0, 0); ctx.restore();
    if length(ax.ylabel) > 0
        canvas_set_font_size(axis_size)
        anchor_x = vp.plot_left - 42.0
        anchor_y = (vp.plot_top + vp.plot_bottom) / 2.0
        canvas_save()
        canvas_translate(anchor_x, anchor_y)
        canvas_rotate(-1.5707963267948966)  # -π/2 radians
        _draw_text_prop(ax.ylabel, 0.0, 0.0, axis_size, Int64(0))  # centered at rotated origin
        canvas_restore()
    end
end

# Proportional-width char approximation (sans-serif).
# Returns width-as-fraction-of-fontsize. Values from a visual fit to typical
# sans-serif proportional fonts (narrow i/l/1 vs wide m/w/M/W).
function _char_w_ratio(c::UInt8)::Float64
    # narrow
    if c == UInt8('i') || c == UInt8('l') || c == UInt8('I') || c == UInt8('j') ||
       c == UInt8('t') || c == UInt8('f') || c == UInt8('r') ||
       c == UInt8('.') || c == UInt8(',') || c == UInt8(':') || c == UInt8(';') ||
       c == UInt8('!') || c == UInt8('|') || c == UInt8('\'') || c == UInt8('`') ||
       c == UInt8('(') || c == UInt8(')') || c == UInt8('[') || c == UInt8(']') ||
       c == UInt8('1')
        return 0.3
    # wide
    elseif c == UInt8('m') || c == UInt8('w') || c == UInt8('M') || c == UInt8('W')
        return 0.85
    # punctuation / spaces
    elseif c == UInt8(' ')
        return 0.28
    elseif c == UInt8('-') || c == UInt8('_')
        return 0.4
    # default for digits, letters
    else
        return 0.55
    end
end

function _string_width(s::String, fontsize::Float64)::Float64
    n = ncodeunits(s)
    total = 0.0
    i = Int64(1)
    while i <= n
        total += _char_w_ratio(codeunit(s, i)) * fontsize
        i += Int64(1)
    end
    return total
end

# align: 0 = center (x is midpoint), 1 = right (x is right edge), 2 = left (x is left edge)
function _draw_text_prop(s::String, x::Float64, y::Float64, fontsize::Float64, align::Int64)
    n = ncodeunits(s)
    if n == 0; return; end
    w = _string_width(s, fontsize)
    start_x = align == Int64(0) ? (x - w / 2.0) :
              align == Int64(1) ? (x - w) :
                                  x
    cur = start_x
    i = Int64(1)
    while i <= n
        c = codeunit(s, i)
        canvas_fill_text_char(Float64(c), cur, y)
        cur += _char_w_ratio(c) * fontsize
        i += Int64(1)
    end
end

# ─── Plot rendering (concrete types — no abstract dispatch) ───

function _render_line!(p::LinePlot, vp::AxisViewport)
    n = length(p.x)
    n < 2 && return

    _set_stroke(p.color)
    canvas_set_line_width(p.linewidth)

    if p.linestyle == Int64(1);     canvas_set_line_dash_dashed()
    elseif p.linestyle == Int64(2); canvas_set_line_dash_dotted()
    else;                           canvas_set_line_dash_solid()
    end

    canvas_begin_path()
    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        if i == 1; canvas_move_to(px, py)
        else;      canvas_line_to(px, py)
        end
    end
    canvas_stroke()
    canvas_set_line_dash_solid()
end

function _render_scatter!(p::ScatterPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

    _set_fill(p.color)
    r = p.markersize / 2.0

    if p.strokewidth > 0.0
        _set_stroke(p.strokecolor)
        canvas_set_line_width(p.strokewidth)
    end

    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        canvas_begin_path()
        if p.marker == Int64(0)  # circle
            canvas_arc(px, py, r, 0.0, TWO_PI)
        elseif p.marker == Int64(1)  # rect
            canvas_fill_rect(px - r, py - r, r * 2.0, r * 2.0)
        end
        canvas_fill()
        if p.strokewidth > 0.0; canvas_stroke(); end
    end
end

function _render_bar!(p::BarPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

    _set_fill(p.color)
    half_w = p.width / 2.0

    for i in 1:n
        x_left  = data_to_pixel(p.x[i] - half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        x_right = data_to_pixel(p.x[i] + half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        y_top   = data_to_pixel(p.heights[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        y_base  = data_to_pixel(0.0, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        canvas_fill_rect(x_left, y_top, x_right - x_left, y_base - y_top)
        if p.strokewidth > 0.0
            _set_stroke(p.strokecolor)
            canvas_set_line_width(p.strokewidth)
            canvas_stroke_rect(x_left, y_top, x_right - x_left, y_base - y_top)
        end
    end
end

function _render_heatmap!(p::HeatmapPlot, vp::AxisViewport)
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top
    cell_w = pw / Float64(p.nx)
    cell_h = ph / Float64(p.ny)
    range_val = p.vmax - p.vmin

    row = Int64(0)
    while row < p.ny
        col = Int64(0)
        while col < p.nx
            idx = row * p.nx + col + Int64(1)
            t = range_val > 0.0 ? (p.values[idx] - p.vmin) / range_val : 0.5
            t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t)
            r, g, b = _viridis(t)
            canvas_set_fill_rgb(r, g, b)
            x = vp.plot_left + Float64(col) * cell_w
            # Heatmap row 0 = bottom (y inverted)
            y = vp.plot_bottom - Float64(row + Int64(1)) * cell_h
            canvas_fill_rect(x, y, cell_w + 0.5, cell_h + 0.5)  # +0.5 avoids gaps
            col = col + Int64(1)
        end
        row = row + Int64(1)
    end
end

"""Viridis colormap: t ∈ [0,1] → (r,g,b) in [0,255]. 9-stop piecewise linear."""
function _viridis(t::Float64)
    # 9 key stops from the matplotlib viridis table (0-255 scale)
    # Stops at t = 0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0
    if t < 0.125
        s = t / 0.125
        r = 68.0 + s * (72.0 - 68.0); g = 1.0 + s * (34.0 - 1.0); b = 84.0 + s * (115.0 - 84.0)
    elseif t < 0.25
        s = (t - 0.125) / 0.125
        r = 72.0 + s * (59.0 - 72.0); g = 34.0 + s * (82.0 - 34.0); b = 115.0 + s * (139.0 - 115.0)
    elseif t < 0.375
        s = (t - 0.25) / 0.125
        r = 59.0 + s * (44.0 - 59.0); g = 82.0 + s * (114.0 - 82.0); b = 139.0 + s * (142.0 - 139.0)
    elseif t < 0.5
        s = (t - 0.375) / 0.125
        r = 44.0 + s * (33.0 - 44.0); g = 114.0 + s * (145.0 - 114.0); b = 142.0 + s * (140.0 - 142.0)
    elseif t < 0.625
        s = (t - 0.5) / 0.125
        r = 33.0 + s * (53.0 - 33.0); g = 145.0 + s * (172.0 - 145.0); b = 140.0 + s * (118.0 - 140.0)
    elseif t < 0.75
        s = (t - 0.625) / 0.125
        r = 53.0 + s * (94.0 - 53.0); g = 172.0 + s * (201.0 - 172.0); b = 118.0 + s * (98.0 - 118.0)
    elseif t < 0.875
        s = (t - 0.75) / 0.125
        r = 94.0 + s * (171.0 - 94.0); g = 201.0 + s * (221.0 - 201.0); b = 98.0 + s * (56.0 - 98.0)
    else
        s = (t - 0.875) / 0.125
        r = 171.0 + s * (253.0 - 171.0); g = 221.0 + s * (231.0 - 221.0); b = 56.0 + s * (37.0 - 56.0)
    end
    return (r, g, b)
end

# ─── Color helpers ───

function _set_fill(c::RGBA)
    if c.a < 1.0
        canvas_set_fill_rgba(c.r * 255.0, c.g * 255.0, c.b * 255.0, c.a)
    else
        canvas_set_fill_rgb(c.r * 255.0, c.g * 255.0, c.b * 255.0)
    end
end

function _set_stroke(c::RGBA)
    canvas_set_stroke_rgb(c.r * 255.0, c.g * 255.0, c.b * 255.0)
end

# ─── JS code generation (reference renderer for testing without WASM) ───

"""
    generate_js_render(fig::Figure) -> String

Generate JavaScript that renders the figure via Canvas2D.
Uses native ctx.fillText() for proper text rendering.
"""
function generate_js_render(fig::Figure)::String
    js = IOBuffer()
    w = Float64(fig.width); h = Float64(fig.height)
    println(js, "c2d.clear_rect(0, 0, $w, $h);")
    _js_set_fill(js, fig.backgroundcolor)
    println(js, "c2d.fill_rect(0, 0, $w, $h);")

    for ax in fig.axes
        vp = compute_viewport(ax, fig)
        _js_render_axis!(js, ax, vp, fig.fontsize)
    end
    return String(take!(js))
end

function _js_render_axis!(js::IOBuffer, ax::Axis, vp::AxisViewport, fontsize::Float64)
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top
    _js_set_fill(js, ax.backgroundcolor)
    println(js, "c2d.fill_rect($(vp.plot_left), $(vp.plot_top), $pw, $ph);")
    _js_render_grid!(js, ax, vp)
    println(js, "c2d.save();")
    for p in ax.heatmap_plots; _js_render_heatmap!(js, p, vp); end
    for p in ax.line_plots;    _js_render_line!(js, p, vp); end
    for p in ax.scatter_plots; _js_render_scatter!(js, p, vp); end
    for p in ax.bar_plots;     _js_render_bar!(js, p, vp); end
    println(js, "c2d.restore();")
    _js_set_stroke(js, ax.spinecolor)
    println(js, "c2d.set_line_width(1.0);")
    println(js, "c2d.stroke_rect($(vp.plot_left), $(vp.plot_top), $pw, $ph);")
    _js_render_ticks!(js, ax, vp, fontsize)
    _js_render_labels!(js, ax, vp, fontsize)
end

function _js_render_grid!(js::IOBuffer, ax::Axis, vp::AxisViewport)
    (!ax.xgridvisible && !ax.ygridvisible) && return
    println(js, "c2d.set_line_width(1.0);")  # Makie default
    _js_set_stroke(js, ax.gridcolor)
    if ax.xgridvisible
        for t in vp.xticks
            px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
            println(js, "c2d.begin_path(); c2d.move_to($px, $(vp.plot_top)); c2d.line_to($px, $(vp.plot_bottom)); c2d.stroke();")
        end
    end
    if ax.ygridvisible
        for t in vp.yticks
            py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
            println(js, "c2d.begin_path(); c2d.move_to($(vp.plot_left), $py); c2d.line_to($(vp.plot_right), $py); c2d.stroke();")
        end
    end
end

function _js_render_line!(js::IOBuffer, p::LinePlot, vp::AxisViewport)
    n = length(p.x); n < 2 && return
    _js_set_stroke(js, p.color)
    println(js, "c2d.set_line_width($(p.linewidth));")
    if p.linestyle == Int64(1);     println(js, "c2d.set_line_dash_dashed();")
    elseif p.linestyle == Int64(2); println(js, "c2d.set_line_dash_dotted();")
    else;                           println(js, "c2d.set_line_dash_solid();")
    end
    println(js, "c2d.begin_path();")
    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, i == 1 ? "c2d.move_to($px, $py);" : "c2d.line_to($px, $py);")
    end
    println(js, "c2d.stroke(); c2d.set_line_dash_solid();")
end

function _js_render_scatter!(js::IOBuffer, p::ScatterPlot, vp::AxisViewport)
    n = length(p.x); n == 0 && return
    _js_set_fill(js, p.color)
    r = p.markersize / 2.0
    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, "c2d.begin_path(); c2d.arc($px, $py, $r, 0, $(TWO_PI)); c2d.fill();")
    end
end

function _js_render_bar!(js::IOBuffer, p::BarPlot, vp::AxisViewport)
    n = length(p.x); n == 0 && return
    _js_set_fill(js, p.color)
    half_w = p.width / 2.0
    for i in 1:n
        xl = data_to_pixel(p.x[i] - half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        xr = data_to_pixel(p.x[i] + half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        yt = data_to_pixel(p.heights[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        yb = data_to_pixel(0.0, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, "c2d.fill_rect($xl, $yt, $(xr - xl), $(yb - yt));")
    end
end

function _js_render_ticks!(js::IOBuffer, ax::Axis, vp::AxisViewport, fontsize::Float64)
    tick_len = 5.0
    label_size = fontsize * 0.75
    _js_set_stroke(js, ax.spinecolor)
    _js_set_fill(js, RGBA(0.0, 0.0, 0.0))
    println(js, "c2d.set_line_width(1.0);")
    println(js, "ctx.font='$(fontsize)px sans-serif'; ctx.textBaseline='top'; ctx.textAlign='center';")
    for t in vp.xticks
        px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        println(js, "c2d.begin_path(); c2d.move_to($px, $(vp.plot_bottom)); c2d.line_to($px, $(vp.plot_bottom + tick_len)); c2d.stroke();")
        println(js, "ctx.fillText('$(_format_tick(t))', $px, $(vp.plot_bottom + tick_len + 3.0));")
    end
    println(js, "ctx.textAlign='right'; ctx.textBaseline='middle';")
    for t in vp.yticks
        py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, "c2d.begin_path(); c2d.move_to($(vp.plot_left - tick_len), $py); c2d.line_to($(vp.plot_left), $py); c2d.stroke();")
        println(js, "ctx.fillText('$(_format_tick(t))', $(vp.plot_left - tick_len - 3.0), $py);")
    end
end

function _js_render_labels!(js::IOBuffer, ax::Axis, vp::AxisViewport, fontsize::Float64)
    _js_set_fill(js, RGBA(0.0, 0.0, 0.0))
    if !isempty(ax.title)
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        println(js, "ctx.font='bold $(fontsize)px sans-serif'; ctx.textAlign='center'; ctx.textBaseline='bottom';")
        println(js, "ctx.fillText('$(ax.title)', $mid_x, $(vp.plot_top - 8.0));")
    end
    if !isempty(ax.xlabel)
        fs = fontsize
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        println(js, "ctx.font='$(fs)px sans-serif'; ctx.textAlign='center'; ctx.textBaseline='bottom';")
        println(js, "ctx.fillText('$(ax.xlabel)', $mid_x, $(vp.plot_bottom + MARGIN_BOTTOM - 6.0));")
    end
    if !isempty(ax.ylabel)
        fs = fontsize
        mid_y = (vp.plot_top + vp.plot_bottom) / 2.0
        xp = vp.plot_left - MARGIN_LEFT + 14.0
        println(js, "ctx.save(); ctx.translate($xp, $mid_y); ctx.rotate(-Math.PI/2);")
        println(js, "ctx.font='$(fs)px sans-serif'; ctx.textAlign='center'; ctx.textBaseline='bottom';")
        println(js, "ctx.fillText('$(ax.ylabel)', 0, 0); ctx.restore();")
    end
end

_js_set_fill(js::IOBuffer, c::RGBA) = c.a < 1.0 ?
    println(js, "c2d.set_fill_rgba($(c.r*255), $(c.g*255), $(c.b*255), $(c.a));") :
    println(js, "c2d.set_fill_rgb($(c.r*255), $(c.g*255), $(c.b*255));")

_js_set_stroke(js::IOBuffer, c::RGBA) =
    println(js, "c2d.set_stroke_rgb($(c.r*255), $(c.g*255), $(c.b*255));")

function _js_render_heatmap!(js::IOBuffer, p::HeatmapPlot, vp::AxisViewport)
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top
    cw = pw / Float64(p.nx)
    ch = ph / Float64(p.ny)
    range_val = p.vmax - p.vmin
    row = 0
    while row < p.ny
        col = 0
        while col < p.nx
            idx = row * Int(p.nx) + col + 1
            t = range_val > 0 ? (p.values[idx] - p.vmin) / range_val : 0.5
            t = clamp(t, 0.0, 1.0)
            r, g, b = _viridis(t)
            println(js, "c2d.set_fill_rgb($r, $g, $b);")
            x = vp.plot_left + Float64(col) * cw
            y = vp.plot_bottom - Float64(row + 1) * ch
            println(js, "c2d.fill_rect($x, $y, $(cw + 0.5), $(ch + 0.5));")
            col += 1
        end
        row += 1
    end
end
