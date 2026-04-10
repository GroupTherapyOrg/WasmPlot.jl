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

    canvas_set_line_width(0.5)
    _set_stroke(ax.gridcolor)
    canvas_set_line_dash_dashed()

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
    canvas_set_line_dash_solid()
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
    label_size = fontsize * 0.75

    _set_stroke(ax.spinecolor)
    _set_fill(RGBA(0.0, 0.0, 0.0))
    canvas_set_line_width(1.0)
    canvas_set_font_size(label_size)

    for t in vp.xticks
        px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        canvas_begin_path(); canvas_move_to(px, vp.plot_bottom)
        canvas_line_to(px, vp.plot_bottom + tick_len); canvas_stroke()
    end
    for t in vp.yticks
        py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        canvas_begin_path(); canvas_move_to(vp.plot_left - tick_len, py)
        canvas_line_to(vp.plot_left, py); canvas_stroke()
    end
end

# ─── Labels (char-by-char for WASM; JS reference renderer overrides) ───

function _render_labels!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    _set_fill(RGBA(0.0, 0.0, 0.0))
    canvas_set_font_size(fontsize)
    # Title, xlabel, ylabel rendered via char codes for WASM path
    # (JS reference renderer uses native ctx.fillText — see generate_js_render)
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

"""Simplified viridis colormap: t ∈ [0,1] → (r,g,b) in [0,255]."""
function _viridis(t::Float64)
    # 5-stop linear interpolation approximating viridis
    if t < 0.25
        s = t / 0.25
        r = 68.0 + s * (49.0 - 68.0)
        g = 1.0 + s * (104.0 - 1.0)
        b = 84.0 + s * (142.0 - 84.0)
    elseif t < 0.5
        s = (t - 0.25) / 0.25
        r = 49.0 + s * (33.0 - 49.0)
        g = 104.0 + s * (165.0 - 104.0)
        b = 142.0 + s * (133.0 - 142.0)
    elseif t < 0.75
        s = (t - 0.5) / 0.25
        r = 33.0 + s * (144.0 - 33.0)
        g = 165.0 + s * (206.0 - 165.0)
        b = 133.0 + s * (68.0 - 133.0)
    else
        s = (t - 0.75) / 0.25
        r = 144.0 + s * (253.0 - 144.0)
        g = 206.0 + s * (231.0 - 206.0)
        b = 68.0 + s * (37.0 - 68.0)
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
    println(js, "c2d.set_line_width(0.5);")
    _js_set_stroke(js, ax.gridcolor)
    println(js, "c2d.set_line_dash_dashed();")
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
    println(js, "c2d.set_line_dash_solid();")
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
    println(js, "ctx.font='$(label_size)px sans-serif'; ctx.textBaseline='top'; ctx.textAlign='center';")
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
        fs = fontsize * 1.2
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        println(js, "ctx.font='bold $(fs)px sans-serif'; ctx.textAlign='center'; ctx.textBaseline='bottom';")
        println(js, "ctx.fillText('$(ax.title)', $mid_x, $(vp.plot_top - 8.0));")
    end
    if !isempty(ax.xlabel)
        fs = fontsize * 0.9
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        println(js, "ctx.font='$(fs)px sans-serif'; ctx.textAlign='center'; ctx.textBaseline='bottom';")
        println(js, "ctx.fillText('$(ax.xlabel)', $mid_x, $(vp.plot_bottom + MARGIN_BOTTOM - 6.0));")
    end
    if !isempty(ax.ylabel)
        fs = fontsize * 0.9
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
