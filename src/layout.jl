# layout.jl — Axis layout computation
#
# Pure math: tick positions, data→pixel transforms, margins.
# All functions are WASM-compilable (concrete types, no IO).

# ─── Margins (pixels) ───
const MARGIN_LEFT   = 60.0
const MARGIN_RIGHT  = 20.0
const MARGIN_TOP    = 40.0
const MARGIN_BOTTOM = 50.0

"""
    compute_data_limits(ax::Axis) -> (xmin, xmax, ymin, ymax)

Compute axis limits from data. Adds 5% padding (Makie default).
"""
function compute_data_limits(ax::Axis)
    xmin = Inf; xmax = -Inf
    ymin = Inf; ymax = -Inf

    # Scan all plot types (concrete iteration, no abstract dispatch)
    for p in ax.line_plots
        for v in p.x; v < xmin && (xmin = v); v > xmax && (xmax = v); end
        for v in p.y; v < ymin && (ymin = v); v > ymax && (ymax = v); end
    end
    for p in ax.scatter_plots
        for v in p.x; v < xmin && (xmin = v); v > xmax && (xmax = v); end
        for v in p.y; v < ymin && (ymin = v); v > ymax && (ymax = v); end
    end
    for p in ax.bar_plots
        for v in p.x; v < xmin && (xmin = v); v > xmax && (xmax = v); end
        for v in p.heights; v < ymin && (ymin = v); v > ymax && (ymax = v); end
    end
    for p in ax.heatmap_plots
        p.xmin < xmin && (xmin = p.xmin)
        p.xmax > xmax && (xmax = p.xmax)
        p.ymin < ymin && (ymin = p.ymin)
        p.ymax > ymax && (ymax = p.ymax)
    end

    # Bar charts: include 0 baseline + extend x by half bar width
    if !isempty(ax.bar_plots)
        ymin > 0.0 && (ymin = 0.0)
        ymax < 0.0 && (ymax = 0.0)
        for p in ax.bar_plots
            half_w = p.width / 2.0
            for v in p.x
                (v - half_w) < xmin && (xmin = v - half_w)
                (v + half_w) > xmax && (xmax = v + half_w)
            end
        end
    end

    # Handle empty / degenerate
    if xmin == Inf;  xmin = 0.0; xmax = 1.0; end
    if ymin == Inf;  ymin = 0.0; ymax = 1.0; end
    if xmin == xmax; xmin -= 1.0; xmax += 1.0; end
    if ymin == ymax; ymin -= 1.0; ymax += 1.0; end

    # 5% padding
    xpad = (xmax - xmin) * 0.05
    ypad = (ymax - ymin) * 0.05
    xmin -= xpad; xmax += xpad
    ymin -= ypad; ymax += ypad

    # User overrides (NaN = auto)
    if !isnan(ax.xlim_min); xmin = ax.xlim_min; end
    if !isnan(ax.xlim_max); xmax = ax.xlim_max; end
    if !isnan(ax.ylim_min); ymin = ax.ylim_min; end
    if !isnan(ax.ylim_max); ymax = ax.ylim_max; end

    return (xmin, xmax, ymin, ymax)
end

"""
    compute_ticks(lo, hi, target_count=5) -> Vector{Float64}

Compute "nice" tick positions. Uses the 1-2-5 rule.
"""
function compute_ticks(lo::Float64, hi::Float64, target_count::Int=5)
    range_val = hi - lo
    if range_val <= 0.0
        return Float64[lo]
    end

    raw_step = range_val / target_count
    mag = 10.0^floor(log10(raw_step))
    residual = raw_step / mag

    nice_step = if residual <= 1.5; 1.0 * mag
    elseif residual <= 3.5; 2.0 * mag
    elseif residual <= 7.5; 5.0 * mag
    else; 10.0 * mag; end

    tick_start = ceil(lo / nice_step) * nice_step
    ticks = Float64[]
    t = tick_start
    while t <= hi + nice_step * 0.01
        if t >= lo - nice_step * 0.01
            push!(ticks, t)
        end
        t += nice_step
    end
    return ticks
end

"""
    data_to_pixel(val, data_min, data_max, px_min, px_max) -> Float64
"""
function data_to_pixel(val::Float64, data_min::Float64, data_max::Float64,
                       px_min::Float64, px_max::Float64)::Float64
    if data_max == data_min
        return (px_min + px_max) / 2.0
    end
    t = (val - data_min) / (data_max - data_min)
    return px_min + t * (px_max - px_min)
end

"""Precomputed pixel region for an axis within the figure."""
struct AxisViewport
    plot_left::Float64
    plot_right::Float64
    plot_top::Float64
    plot_bottom::Float64
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    xticks::Vector{Float64}
    yticks::Vector{Float64}
end

"""
    compute_viewport(ax, fig) -> AxisViewport
"""
function compute_viewport(ax::Axis, fig::Figure)
    # Find grid dimensions from all axes
    max_row = Int64(1); max_col = Int64(1)
    for a in fig.axes
        a.row > max_row && (max_row = a.row)
        a.col > max_col && (max_col = a.col)
    end

    fw = Float64(fig.width)
    fh = Float64(fig.height)
    cell_w = fw / Float64(max_col)
    cell_h = fh / Float64(max_row)

    cx = Float64(ax.col - Int64(1)) * cell_w
    cy = Float64(ax.row - Int64(1)) * cell_h

    pl = cx + MARGIN_LEFT
    pr = cx + cell_w - MARGIN_RIGHT
    pt = cy + MARGIN_TOP
    pb = cy + cell_h - MARGIN_BOTTOM

    xmin, xmax, ymin, ymax = compute_data_limits(ax)
    xticks = compute_ticks(xmin, xmax)
    yticks = compute_ticks(ymin, ymax)

    return AxisViewport(pl, pr, pt, pb, xmin, xmax, ymin, ymax, xticks, yticks)
end

"""Format a tick value as a clean string.

We compose the result from `string(::Int)` calls only — `string(::Float64)`
goes through `Ryu.writeshortest`, which WasmTarget auto-discovers but
currently traps with `unreachable` somewhere in its body. Using the
integer-only path here keeps every WasmPlot tick label safe in WASM
until that upstream fix lands. Format matches the previous
`round(val; digits=1)` output for the values WasmPlot actually emits
(compute_ticks always picks 1-2-5-step ticks, so |val| ≤ 1e6 is
sufficient for any realistic plot range).
"""
function _format_tick(val::Float64)::String
    if abs(val - round(val)) < 1e-9 && abs(val) < 1e6
        return string(round(Int, val))
    end
    # Float branch — emit "<int>.<tenth>" without ever calling
    # string(::Float64). Round to nearest tenth, then split into the
    # integer part and the absolute single-digit fractional part.
    scaled = round(Int, val * 10.0)
    int_part = scaled ÷ 10
    frac = abs(scaled % 10)
    sign_prefix = (val < 0.0 && int_part == 0) ? "-" : ""
    return sign_prefix * string(int_part) * "." * string(frac)
end
