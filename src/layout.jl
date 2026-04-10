# layout.jl — Axis layout computation
#
# Pure math: tick positions, data→pixel transforms, margins.
# All functions are WASM-compilable (no allocations, no strings, no IO).

# ─── Margins (pixels) ───
# CairoMakie uses ~similar defaults via MakieLayout
const MARGIN_LEFT   = 60.0   # space for y-axis label + ticks
const MARGIN_RIGHT  = 20.0
const MARGIN_TOP    = 40.0   # space for title
const MARGIN_BOTTOM = 50.0   # space for x-axis label + ticks

"""
    compute_data_limits(ax::Axis) -> (xmin, xmax, ymin, ymax)

Compute axis limits from data, respecting user-set xlim/ylim.
Adds 5% padding (Makie's default `autolimitmargin`).
"""
function compute_data_limits(ax::Axis)
    xmin = Inf; xmax = -Inf
    ymin = Inf; ymax = -Inf

    has_bars = false
    for p in ax.plots
        xs = _plot_x(p)
        ys = _plot_y(p)
        for v in xs
            v < xmin && (xmin = v)
            v > xmax && (xmax = v)
        end
        for v in ys
            v < ymin && (ymin = v)
            v > ymax && (ymax = v)
        end
        if p isa BarPlot
            has_bars = true
        end
    end

    # Bar charts: include 0 baseline + extend x-limits by half bar width
    if has_bars
        ymin > 0.0 && (ymin = 0.0)
        ymax < 0.0 && (ymax = 0.0)
        # Find bar width to extend x-limits (Makie extends by half a bar)
        for p in ax.plots
            if p isa BarPlot
                half_w = p.width / 2.0
                xmin = min(xmin, minimum(p.x) - half_w)
                xmax = max(xmax, maximum(p.x) + half_w)
            end
        end
    end

    # Handle empty / degenerate
    if xmin == Inf
        xmin = 0.0; xmax = 1.0
    end
    if ymin == Inf
        ymin = 0.0; ymax = 1.0
    end
    if xmin == xmax
        xmin -= 1.0; xmax += 1.0
    end
    if ymin == ymax
        ymin -= 1.0; ymax += 1.0
    end

    # 5% padding (Makie default)
    xpad = (xmax - xmin) * 0.05
    ypad = (ymax - ymin) * 0.05
    xmin -= xpad; xmax += xpad
    ymin -= ypad; ymax += ypad

    # User overrides
    if ax.xlim !== nothing
        xmin, xmax = ax.xlim
    end
    if ax.ylim !== nothing
        ymin, ymax = ax.ylim
    end

    return (xmin, xmax, ymin, ymax)
end

_plot_x(p::LinePlot) = p.x
_plot_x(p::ScatterPlot) = p.x
_plot_x(p::BarPlot) = p.x
_plot_y(p::LinePlot) = p.y
_plot_y(p::ScatterPlot) = p.y
_plot_y(p::BarPlot) = p.heights

"""
    compute_ticks(lo, hi, target_count=5) -> Vector{Float64}

Compute "nice" tick positions between lo and hi.
Uses the 1-2-5 rule (Wilkinson's algorithm simplified).
"""
function compute_ticks(lo::Float64, hi::Float64, target_count::Int=5)
    range = hi - lo
    if range <= 0.0
        return Float64[lo]
    end

    # Raw step size
    raw_step = range / target_count

    # Round to nearest 1-2-5 × 10^n
    mag = 10.0^floor(log10(raw_step))
    residual = raw_step / mag

    if residual <= 1.5
        nice_step = 1.0 * mag
    elseif residual <= 3.5
        nice_step = 2.0 * mag
    elseif residual <= 7.5
        nice_step = 5.0 * mag
    else
        nice_step = 10.0 * mag
    end

    # Generate ticks from nice_step
    tick_start = ceil(lo / nice_step) * nice_step
    ticks = Float64[]
    t = tick_start
    while t <= hi + nice_step * 0.01  # small epsilon for floating point
        if t >= lo - nice_step * 0.01
            push!(ticks, t)
        end
        t += nice_step
    end

    return ticks
end

"""
    data_to_pixel(val, data_min, data_max, px_min, px_max) -> Float64

Linear interpolation from data space to pixel space.
"""
function data_to_pixel(val::Float64, data_min::Float64, data_max::Float64,
                       px_min::Float64, px_max::Float64)::Float64
    if data_max == data_min
        return (px_min + px_max) / 2.0
    end
    t = (val - data_min) / (data_max - data_min)
    return px_min + t * (px_max - px_min)
end

"""
    AxisViewport

Precomputed pixel region for an axis within the figure.
"""
struct AxisViewport
    # Plot area (inside margins)
    plot_left::Float64
    plot_right::Float64
    plot_top::Float64
    plot_bottom::Float64
    # Data limits
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    # Ticks
    xticks::Vector{Float64}
    yticks::Vector{Float64}
end

"""
    compute_viewport(ax, fig, row, col) -> AxisViewport

Compute the pixel viewport for an axis in the figure grid.
"""
function compute_viewport(ax::Axis, fig::Figure, row::Int, col::Int)
    # Find grid dimensions
    max_row = 1; max_col = 1
    for (r, c) in keys(fig._grid)
        r > max_row && (max_row = r)
        c > max_col && (max_col = c)
    end

    fw, fh = Float64(fig.size[1]), Float64(fig.size[2])
    cell_w = fw / max_col
    cell_h = fh / max_row

    # Cell bounds
    cx = (col - 1) * cell_w
    cy = (row - 1) * cell_h

    # Plot area within cell (after margins)
    pl = cx + MARGIN_LEFT
    pr = cx + cell_w - MARGIN_RIGHT
    pt = cy + MARGIN_TOP
    pb = cy + cell_h - MARGIN_BOTTOM

    xmin, xmax, ymin, ymax = compute_data_limits(ax)
    xticks = compute_ticks(xmin, xmax)
    yticks = compute_ticks(ymin, ymax)

    return AxisViewport(pl, pr, pt, pb, xmin, xmax, ymin, ymax, xticks, yticks)
end

# ─── Number formatting for tick labels ───

"""
    format_number_chars(val) -> Vector{Int}

Convert a number to a vector of ASCII char codes for rendering.
Simple formatting: integers stay as integers, floats get 1-2 decimal places.
"""
function format_number_chars(val::Float64)::Vector{Int}
    chars = Int[]

    if val < 0.0
        push!(chars, Int('-'))
        val = -val
    end

    # Decide formatting: if close to integer, use integer format
    if abs(val - round(val)) < 1e-9 && val < 1e6
        n = round(Int, val)
        if n == 0
            push!(chars, Int('0'))
        else
            digits = Int[]
            while n > 0
                push!(digits, Int('0') + n % 10)
                n = n ÷ 10
            end
            append!(chars, reverse(digits))
        end
    else
        # Fixed-point with 1 decimal
        n = round(Int, val * 10)
        integer_part = n ÷ 10
        frac_part = n % 10

        if integer_part == 0
            push!(chars, Int('0'))
        else
            digits = Int[]
            ip = integer_part
            while ip > 0
                push!(digits, Int('0') + ip % 10)
                ip = ip ÷ 10
            end
            append!(chars, reverse(digits))
        end
        push!(chars, Int('.'))
        push!(chars, Int('0') + frac_part)
    end

    return chars
end
