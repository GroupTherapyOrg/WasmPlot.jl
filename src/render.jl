# render.jl — Walk Figure → Axis → Plot tree and emit Canvas2D calls
#
# This is the core rendering pipeline. Every function here calls Canvas2D
# import stubs, which are no-ops in Julia but become real Canvas2D calls
# when compiled to WASM.
#
# Rendering order (matches CairoMakie):
# 1. Figure background
# 2. For each axis:
#    a. Axis background
#    b. Grid lines
#    c. Plots (data)
#    d. Axis spines (frame)
#    e. Tick marks + labels
#    f. Axis title + labels

const TWO_PI = 2.0 * π

"""
    render!(fig::Figure)

Render the entire figure to the current Canvas2D context.
In WASM, the JS glue sets up the context before calling this.
"""
function render!(fig::Figure)
    w, h = Float64(fig.size[1]), Float64(fig.size[2])

    # 1. Clear + figure background
    canvas_clear_rect(0.0, 0.0, w, h)
    _set_fill(fig.backgroundcolor)
    canvas_fill_rect(0.0, 0.0, w, h)

    # 2. Render each axis
    for ((row, col), ax) in fig._grid
        vp = compute_viewport(ax, fig, row, col)
        _render_axis!(ax, vp, fig.fontsize)
    end
end

function _render_axis!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    # a. Axis background
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top
    _set_fill(ax.backgroundcolor)
    canvas_fill_rect(vp.plot_left, vp.plot_top, pw, ph)

    # b. Grid lines
    _render_grid!(ax, vp)

    # c. Plots
    canvas_save()
    # Clip to plot area (done manually — no clip API needed for v0.1)
    for p in ax.plots
        _render_plot!(p, vp)
    end
    canvas_restore()

    # d. Spines
    _render_spines!(ax, vp)

    # e. Tick marks + labels
    _render_ticks!(ax, vp, fontsize)

    # f. Title + axis labels
    _render_labels!(ax, vp, fontsize)
end

# ─── Grid ───

function _render_grid!(ax::Axis, vp::AxisViewport)
    if !ax.xgridvisible && !ax.ygridvisible
        return
    end

    canvas_set_line_width(0.5)
    _set_stroke(ax.gridcolor)
    canvas_set_line_dash_dashed()

    if ax.xgridvisible
        for t in vp.xticks
            px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
            canvas_begin_path()
            canvas_move_to(px, vp.plot_top)
            canvas_line_to(px, vp.plot_bottom)
            canvas_stroke()
        end
    end

    if ax.ygridvisible
        for t in vp.yticks
            py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)  # y is inverted
            canvas_begin_path()
            canvas_move_to(vp.plot_left, py)
            canvas_line_to(vp.plot_right, py)
            canvas_stroke()
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

    # X ticks
    for t in vp.xticks
        px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        # Tick mark
        canvas_begin_path()
        canvas_move_to(px, vp.plot_bottom)
        canvas_line_to(px, vp.plot_bottom + tick_len)
        canvas_stroke()
        # Label
        chars = format_number_chars(t)
        label_w = length(chars) * label_size * 0.6  # approximate char width
        start_x = px - label_w / 2.0
        for (i, c) in enumerate(chars)
            canvas_fill_text_char(Float64(c), start_x + (i - 1) * label_size * 0.6, vp.plot_bottom + tick_len + label_size + 2.0)
        end
    end

    # Y ticks
    for t in vp.yticks
        py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        # Tick mark
        canvas_begin_path()
        canvas_move_to(vp.plot_left - tick_len, py)
        canvas_line_to(vp.plot_left, py)
        canvas_stroke()
        # Label
        chars = format_number_chars(t)
        label_w = length(chars) * label_size * 0.6
        for (i, c) in enumerate(chars)
            canvas_fill_text_char(Float64(c), vp.plot_left - tick_len - label_w + (i - 1) * label_size * 0.6 - 2.0, py + label_size * 0.35)
        end
    end
end

# ─── Labels ───

function _render_labels!(ax::Axis, vp::AxisViewport, fontsize::Float64)
    _set_fill(RGBA(0.0, 0.0, 0.0))

    # Title (centered above plot area)
    if !isempty(ax.title)
        canvas_set_font_size(fontsize * 1.1)
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        char_w = fontsize * 1.1 * 0.6
        start_x = mid_x - length(ax.title) * char_w / 2.0
        for (i, ch) in enumerate(ax.title)
            canvas_fill_text_char(Float64(Int(ch)), start_x + (i - 1) * char_w, vp.plot_top - 10.0)
        end
    end

    # X label (centered below ticks)
    if !isempty(ax.xlabel)
        canvas_set_font_size(fontsize * 0.85)
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        char_w = fontsize * 0.85 * 0.6
        start_x = mid_x - length(ax.xlabel) * char_w / 2.0
        y_pos = vp.plot_bottom + MARGIN_BOTTOM - 8.0
        for (i, ch) in enumerate(ax.xlabel)
            canvas_fill_text_char(Float64(Int(ch)), start_x + (i - 1) * char_w, y_pos)
        end
    end

    # Y label (rotated — approximate with vertical char placement for v0.1)
    if !isempty(ax.ylabel)
        canvas_set_font_size(fontsize * 0.85)
        mid_y = (vp.plot_top + vp.plot_bottom) / 2.0
        char_h = fontsize * 0.85
        start_y = mid_y - length(ax.ylabel) * char_h / 2.0
        x_pos = vp.plot_left - MARGIN_LEFT + 10.0
        for (i, ch) in enumerate(ax.ylabel)
            canvas_fill_text_char(Float64(Int(ch)), x_pos, start_y + (i - 1) * char_h)
        end
    end
end

# ─── Plot rendering ───

function _render_plot!(p::LinePlot, vp::AxisViewport)
    n = length(p.x)
    n < 2 && return

    _set_stroke(p.color)
    canvas_set_line_width(p.linewidth)

    if p.linestyle == :dash
        canvas_set_line_dash_dashed()
    elseif p.linestyle == :dot
        canvas_set_line_dash_dotted()
    else
        canvas_set_line_dash_solid()
    end

    canvas_begin_path()
    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        if i == 1
            canvas_move_to(px, py)
        else
            canvas_line_to(px, py)
        end
    end
    canvas_stroke()
    canvas_set_line_dash_solid()
end

function _render_plot!(p::ScatterPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

    _set_fill(p.color)
    r = p.markersize / 2.0

    if p.strokewidth > 0
        _set_stroke(p.strokecolor)
        canvas_set_line_width(p.strokewidth)
    end

    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)

        canvas_begin_path()
        if p.marker == :circle
            canvas_arc(px, py, r, 0.0, TWO_PI)
        elseif p.marker == :rect
            canvas_fill_rect(px - r, py - r, r * 2.0, r * 2.0)
        end
        canvas_fill()

        if p.strokewidth > 0
            canvas_stroke()
        end
    end
end

function _render_plot!(p::BarPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

    _set_fill(p.color)
    half_w = p.width / 2.0

    for i in 1:n
        x_left = data_to_pixel(p.x[i] - half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        x_right = data_to_pixel(p.x[i] + half_w, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        y_top = data_to_pixel(p.heights[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        y_base = data_to_pixel(0.0, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)

        canvas_fill_rect(x_left, y_top, x_right - x_left, y_base - y_top)

        if p.strokewidth > 0
            _set_stroke(p.strokecolor)
            canvas_set_line_width(p.strokewidth)
            canvas_stroke_rect(x_left, y_top, x_right - x_left, y_base - y_top)
        end
    end
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

# ─── JS code generation (for testing without WASM) ───

"""
    generate_js_render(fig::Figure) -> String

Generate JavaScript that calls canvas2d_imports() functions to render the figure.
This is the "reference renderer" — same draw sequence that WASM would execute.
Used for testing and verification before WASM compilation is wired up.
"""
function generate_js_render(fig::Figure)::String
    js = IOBuffer()

    w, h = Float64(fig.size[1]), Float64(fig.size[2])
    println(js, "c2d.clear_rect(0, 0, $w, $h);")
    _js_set_fill(js, fig.backgroundcolor)
    println(js, "c2d.fill_rect(0, 0, $w, $h);")

    for ((row, col), ax) in fig._grid
        vp = compute_viewport(ax, fig, row, col)
        _js_render_axis!(js, ax, vp, fig.fontsize)
    end

    return String(take!(js))
end

function _js_render_axis!(js::IOBuffer, ax::Axis, vp::AxisViewport, fontsize::Float64)
    pw = vp.plot_right - vp.plot_left
    ph = vp.plot_bottom - vp.plot_top

    # Background
    _js_set_fill(js, ax.backgroundcolor)
    println(js, "c2d.fill_rect($(vp.plot_left), $(vp.plot_top), $pw, $ph);")

    # Grid
    _js_render_grid!(js, ax, vp)

    # Plots
    println(js, "c2d.save();")
    for p in ax.plots
        _js_render_plot!(js, p, vp)
    end
    println(js, "c2d.restore();")

    # Spines
    _js_set_stroke(js, ax.spinecolor)
    println(js, "c2d.set_line_width(1.0);")
    println(js, "c2d.stroke_rect($(vp.plot_left), $(vp.plot_top), $pw, $ph);")

    # Ticks
    _js_render_ticks!(js, ax, vp, fontsize)

    # Labels
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

function _js_render_plot!(js::IOBuffer, p::LinePlot, vp::AxisViewport)
    n = length(p.x)
    n < 2 && return

    _js_set_stroke(js, p.color)
    println(js, "c2d.set_line_width($(p.linewidth));")
    if p.linestyle == :dash
        println(js, "c2d.set_line_dash_dashed();")
    elseif p.linestyle == :dot
        println(js, "c2d.set_line_dash_dotted();")
    else
        println(js, "c2d.set_line_dash_solid();")
    end

    println(js, "c2d.begin_path();")
    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        if i == 1
            println(js, "c2d.move_to($px, $py);")
        else
            println(js, "c2d.line_to($px, $py);")
        end
    end
    println(js, "c2d.stroke();")
    println(js, "c2d.set_line_dash_solid();")
end

function _js_render_plot!(js::IOBuffer, p::ScatterPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

    _js_set_fill(js, p.color)
    r = p.markersize / 2.0

    for i in 1:n
        px = data_to_pixel(p.x[i], vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        py = data_to_pixel(p.y[i], vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, "c2d.begin_path(); c2d.arc($px, $py, $r, 0, $(TWO_PI)); c2d.fill();")
    end
end

function _js_render_plot!(js::IOBuffer, p::BarPlot, vp::AxisViewport)
    n = length(p.x)
    n == 0 && return

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
    println(js, "c2d.set_font_size($label_size);")

    # X ticks
    for t in vp.xticks
        px = data_to_pixel(t, vp.xmin, vp.xmax, vp.plot_left, vp.plot_right)
        println(js, "c2d.begin_path(); c2d.move_to($px, $(vp.plot_bottom)); c2d.line_to($px, $(vp.plot_bottom + tick_len)); c2d.stroke();")
        chars = format_number_chars(t)
        lw = length(chars) * label_size * 0.6
        sx = px - lw / 2.0
        for (i, c) in enumerate(chars)
            println(js, "c2d.fill_text_char($(Float64(c)), $(sx + (i-1) * label_size * 0.6), $(vp.plot_bottom + tick_len + label_size + 2.0));")
        end
    end

    # Y ticks
    for t in vp.yticks
        py = data_to_pixel(t, vp.ymin, vp.ymax, vp.plot_bottom, vp.plot_top)
        println(js, "c2d.begin_path(); c2d.move_to($(vp.plot_left - tick_len), $py); c2d.line_to($(vp.plot_left), $py); c2d.stroke();")
        chars = format_number_chars(t)
        lw = length(chars) * label_size * 0.6
        for (i, c) in enumerate(chars)
            println(js, "c2d.fill_text_char($(Float64(c)), $(vp.plot_left - tick_len - lw + (i-1) * label_size * 0.6 - 2.0), $(py + label_size * 0.35));")
        end
    end
end

function _js_render_labels!(js::IOBuffer, ax::Axis, vp::AxisViewport, fontsize::Float64)
    _js_set_fill(js, RGBA(0.0, 0.0, 0.0))

    if !isempty(ax.title)
        fs = fontsize * 1.1
        println(js, "c2d.set_font_size($fs);")
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        cw = fs * 0.6
        sx = mid_x - length(ax.title) * cw / 2.0
        for (i, ch) in enumerate(ax.title)
            println(js, "c2d.fill_text_char($(Float64(Int(ch))), $(sx + (i-1) * cw), $(vp.plot_top - 10.0));")
        end
    end

    if !isempty(ax.xlabel)
        fs = fontsize * 0.85
        println(js, "c2d.set_font_size($fs);")
        mid_x = (vp.plot_left + vp.plot_right) / 2.0
        cw = fs * 0.6
        sx = mid_x - length(ax.xlabel) * cw / 2.0
        yp = vp.plot_bottom + MARGIN_BOTTOM - 8.0
        for (i, ch) in enumerate(ax.xlabel)
            println(js, "c2d.fill_text_char($(Float64(Int(ch))), $(sx + (i-1) * cw), $yp);")
        end
    end

    if !isempty(ax.ylabel)
        fs = fontsize * 0.85
        println(js, "c2d.set_font_size($fs);")
        mid_y = (vp.plot_top + vp.plot_bottom) / 2.0
        ch_h = fs
        sy = mid_y - length(ax.ylabel) * ch_h / 2.0
        xp = vp.plot_left - MARGIN_LEFT + 10.0
        for (i, ch) in enumerate(ax.ylabel)
            println(js, "c2d.fill_text_char($(Float64(Int(ch))), $xp, $(sy + (i-1) * ch_h));")
        end
    end
end

function _js_set_fill(js::IOBuffer, c::RGBA)
    if c.a < 1.0
        println(js, "c2d.set_fill_rgba($(c.r * 255.0), $(c.g * 255.0), $(c.b * 255.0), $(c.a));")
    else
        println(js, "c2d.set_fill_rgb($(c.r * 255.0), $(c.g * 255.0), $(c.b * 255.0));")
    end
end

function _js_set_stroke(js::IOBuffer, c::RGBA)
    println(js, "c2d.set_stroke_rgb($(c.r * 255.0), $(c.g * 255.0), $(c.b * 255.0));")
end
