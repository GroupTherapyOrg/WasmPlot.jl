# types.jl — Makie-compatible type hierarchy for WasmPlot
#
# Follows Makie's user-facing patterns:
#   fig = Figure(size=(600, 400))
#   ax = Axis(fig[1,1]; xlabel="x", ylabel="y", title="Demo")
#   lines!(ax, x, y; color=:blue, linewidth=2)
#
# Internals are minimal — just enough to drive Canvas2D rendering.

# ─── Colors ───

struct RGBA
    r::Float64  # 0.0–1.0
    g::Float64
    b::Float64
    a::Float64
end

RGBA(r, g, b) = RGBA(Float64(r), Float64(g), Float64(b), 1.0)
rgba(r, g, b, a=1.0) = RGBA(Float64(r), Float64(g), Float64(b), Float64(a))

# Named color lookup — if-else chain instead of Dict to avoid jl_object_id foreigncalls in WASM
function resolve_color(c::Symbol)
    c === :black      && return RGBA(0.0, 0.0, 0.0)
    c === :white      && return RGBA(1.0, 1.0, 1.0)
    c === :red        && return RGBA(1.0, 0.0, 0.0)
    c === :green      && return RGBA(0.0, 0.5, 0.0)
    c === :blue       && return RGBA(0.235, 0.51, 0.965)    # Makie's default blue
    c === :orange     && return RGBA(0.902, 0.494, 0.133)
    c === :purple     && return RGBA(0.584, 0.345, 0.698)
    c === :cyan       && return RGBA(0.0, 0.745, 0.812)
    c === :gray       && return RGBA(0.5, 0.5, 0.5)
    c === :lightgray  && return RGBA(0.83, 0.83, 0.83)
    c === :transparent && return RGBA(0.0, 0.0, 0.0, 0.0)
    return RGBA(0.0, 0.0, 0.0)  # default: black
end

resolve_color(c::RGBA) = c
resolve_color(c::Tuple{Float64, Float64, Float64}) = RGBA(c[1], c[2], c[3])
resolve_color(c::Tuple{Float64, Float64, Float64, Float64}) = RGBA(c[1], c[2], c[3], c[4])
resolve_color(::Nothing) = RGBA(0.0, 0.0, 0.0)

# Color cycle — if-else chain instead of Vector lookup (Makie's wong palette)
function cycle_color(idx::Int)
    i = mod1(idx, Int64(7))
    i == Int64(1) && return RGBA(0.0, 0.447, 0.698)      # blue
    i == Int64(2) && return RGBA(0.902, 0.624, 0.0)      # orange
    i == Int64(3) && return RGBA(0.0, 0.620, 0.451)      # green
    i == Int64(4) && return RGBA(0.800, 0.475, 0.655)    # reddish purple
    i == Int64(5) && return RGBA(0.337, 0.706, 0.914)    # sky blue
    i == Int64(6) && return RGBA(0.835, 0.369, 0.0)      # vermillion
    return RGBA(0.941, 0.894, 0.259)                      # yellow
end

# ─── Plot Types (concrete — no abstract dispatch, WASM-friendly) ───

struct LinePlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::RGBA
    linewidth::Float64
    linestyle::Int64       # 0=solid, 1=dash, 2=dot
    label::String
end

struct ScatterPlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::RGBA
    markersize::Float64
    marker::Int64          # 0=circle, 1=rect, 2=cross
    strokecolor::RGBA
    strokewidth::Float64
    label::String
end

struct BarPlot
    x::Vector{Float64}
    heights::Vector{Float64}
    color::RGBA
    width::Float64
    strokecolor::RGBA
    strokewidth::Float64
    label::String
end

struct HeatmapPlot
    nx::Int64               # grid columns
    ny::Int64               # grid rows
    xmin::Float64
    xmax::Float64
    ymin::Float64
    ymax::Float64
    values::Vector{Float64} # row-major: values[row * nx + col + 1]
    vmin::Float64
    vmax::Float64
end

# ─── Axis ───

mutable struct Axis
    # Plot storage — separate vectors per type (concrete, no abstract dispatch)
    line_plots::Vector{LinePlot}
    scatter_plots::Vector{ScatterPlot}
    bar_plots::Vector{BarPlot}
    heatmap_plots::Vector{HeatmapPlot}
    xlabel::String
    ylabel::String
    title::String
    # Limits: use NaN sentinel instead of Union{..., Nothing} for WASM compatibility
    xlim_min::Float64   # NaN = auto
    xlim_max::Float64
    ylim_min::Float64
    ylim_max::Float64
    xscale::Int64            # 0 = identity, 1 = log10
    yscale::Int64
    backgroundcolor::RGBA
    xgridvisible::Bool
    ygridvisible::Bool
    gridcolor::RGBA
    spinecolor::RGBA
    _plot_count::Int64       # for color cycling
    row::Int64               # grid position (stored on axis, not in Dict)
    col::Int64
end

# ─── Figure ───

mutable struct Figure
    width::Int64
    height::Int64
    backgroundcolor::RGBA
    fontsize::Float64
    axes::Vector{Axis}       # Vector, not Dict (WASM-friendly)
end

struct GridPosition
    figure::Figure
    row::Int64
    col::Int64
end

# ─── Constructors (Makie API) ───

"""
    Figure(; size=(600, 450), backgroundcolor=:white, fontsize=14)

Create a new figure. Matches Makie's `Figure()` constructor.
"""
function Figure(;
    size::Tuple{Int,Int} = (600, 450),
    backgroundcolor = :white,
    fontsize::Real = 14
)
    Figure(Int64(size[1]), Int64(size[2]), resolve_color(backgroundcolor), Float64(fontsize), Axis[])
end

Base.getindex(fig::Figure, row::Int, col::Int) = GridPosition(fig, row, Int64(col))

"""
    Axis(gridpos; xlabel="", ylabel="", title="", ...)

Create an axis at a grid position. Matches Makie's `Axis(fig[1,1]; ...)`.
"""
function Axis(gp::GridPosition;
    xlabel::String = "",
    ylabel::String = "",
    title::String = "",
    xlim = nothing,
    ylim = nothing,
    xscale::Symbol = :identity,
    yscale::Symbol = :identity,
    backgroundcolor = :white,
    xgridvisible::Bool = true,
    ygridvisible::Bool = true,
    gridcolor = nothing,
    spinecolor = nothing,
)
    gc = gridcolor === nothing ? RGBA(0.0, 0.0, 0.0, 0.12) : resolve_color(gridcolor)
    sc = spinecolor === nothing ? RGBA(0.0, 0.0, 0.0, 1.0) : resolve_color(spinecolor)  # Makie: solid black
    xl_min = xlim === nothing ? NaN : Float64(xlim[1])
    xl_max = xlim === nothing ? NaN : Float64(xlim[2])
    yl_min = ylim === nothing ? NaN : Float64(ylim[1])
    yl_max = ylim === nothing ? NaN : Float64(ylim[2])
    xs = xscale === :log10 ? Int64(1) : Int64(0)
    ys = yscale === :log10 ? Int64(1) : Int64(0)

    ax = Axis(LinePlot[], ScatterPlot[], BarPlot[], HeatmapPlot[],
              xlabel, ylabel, title,
              xl_min, xl_max, yl_min, yl_max,
              xs, ys, resolve_color(backgroundcolor),
              xgridvisible, ygridvisible, gc, sc, Int64(0),
              Int64(gp.row), Int64(gp.col))
    push!(gp.figure.axes, ax)
    return ax
end

# ─── Plot Functions (Makie ! convention) ───

"""
    lines!(ax, x, y; color=:auto, linewidth=1.5, linestyle=:solid, label="")

Add a line plot to an existing axis. Matches Makie's `lines!`.
"""
function lines!(ax::Axis, x::Vector{Float64}, y::Vector{Float64};
    color = nothing,
    linewidth::Real = 1.5,
    linestyle::Symbol = :solid,
    label::String = ""
)
    ax._plot_count += Int64(1)
    c = color === nothing ? cycle_color(Int(ax._plot_count)) : resolve_color(color)
    ls = linestyle === :dash ? Int64(1) : linestyle === :dot ? Int64(2) : Int64(0)
    p = LinePlot(x, y, c, Float64(linewidth), ls, label)
    push!(ax.line_plots, p)
    return p
end

# Generic fallback: convert to Vector{Float64} then dispatch to concrete method
function lines!(ax::Axis, x, y; kw...)
    lines!(ax, Float64.(collect(x)), Float64.(collect(y)); kw...)
end

"""
    scatter!(ax, x, y; color=:auto, markersize=9, marker=:circle, label="")

Add a scatter plot to an existing axis. Matches Makie's `scatter!`.
"""
function scatter!(ax::Axis, x::Vector{Float64}, y::Vector{Float64};
    color = nothing,
    markersize::Real = 9,
    marker::Symbol = :circle,
    strokecolor = :black,
    strokewidth::Real = 0,
    label::String = ""
)
    ax._plot_count += Int64(1)
    c = color === nothing ? cycle_color(Int(ax._plot_count)) : resolve_color(color)
    mk = marker === :rect ? Int64(1) : marker === :cross ? Int64(2) : Int64(0)
    p = ScatterPlot(x, y, c, Float64(markersize), mk,
                    resolve_color(strokecolor), Float64(strokewidth), label)
    push!(ax.scatter_plots, p)
    return p
end

# Generic fallback
function scatter!(ax::Axis, x, y; kw...)
    scatter!(ax, Float64.(collect(x)), Float64.(collect(y)); kw...)
end

"""
    barplot!(ax, x, heights; color=:auto, width=0.8, label="")

Add a bar plot to an existing axis. Matches Makie's `barplot!`.
"""
function barplot!(ax::Axis, x::Vector{Float64}, heights::Vector{Float64};
    color = nothing,
    width = nothing,   # nothing = automatic (Makie default)
    gap::Real = 0.2,
    strokecolor = :black,
    strokewidth::Real = 0,
    label::String = ""
)
    ax._plot_count += Int64(1)
    c = color === nothing ? cycle_color(Int(ax._plot_count)) : resolve_color(color)

    # Makie's width algorithm: min gap between x positions, scaled by (1 - gap)
    if width === nothing
        if length(x) <= 1
            w = 1.0
        else
            sorted = sort(unique(x))
            diffs = diff(sorted)
            w = isempty(diffs) ? 1.0 : minimum(diffs)
        end
        w *= (1.0 - Float64(gap))
    else
        w = Float64(width)
    end

    p = BarPlot(x, heights, c, w, resolve_color(strokecolor), Float64(strokewidth), label)
    push!(ax.bar_plots, p)
    return p
end

# Generic fallback
function barplot!(ax::Axis, x, heights; kw...)
    barplot!(ax, Float64.(collect(x)), Float64.(collect(heights)); kw...)
end

"""
    heatmap!(ax, x_range, y_range, values; ...)

Add a heatmap to an axis. values is a flat Vector (row-major).
"""
function heatmap!(ax::Axis, x_range::Tuple, y_range::Tuple,
                  nx::Int, ny::Int, values::Vector{Float64})
    vmin = Inf; vmax = -Inf
    for v in values
        v < vmin && (vmin = v)
        v > vmax && (vmax = v)
    end
    if vmin == vmax; vmin -= 1.0; vmax += 1.0; end

    p = HeatmapPlot(Int64(nx), Int64(ny),
        Float64(x_range[1]), Float64(x_range[2]),
        Float64(y_range[1]), Float64(y_range[2]),
        values, vmin, vmax)
    push!(ax.heatmap_plots, p)
    return p
end

# ─── Non-mutating forms (create Figure + Axis automatically) ───

function lines(x, y; axis=(;), figure=(;), kwargs...)
    fig = Figure(; figure...)
    ax = Axis(fig[1,1]; axis...)
    p = lines!(ax, x, y; kwargs...)
    return (figure=fig, axis=ax, plot=p)
end

function scatter(x, y; axis=(;), figure=(;), kwargs...)
    fig = Figure(; figure...)
    ax = Axis(fig[1,1]; axis...)
    p = scatter!(ax, x, y; kwargs...)
    return (figure=fig, axis=ax, plot=p)
end

function barplot(x, heights; axis=(;), figure=(;), kwargs...)
    fig = Figure(; figure...)
    ax = Axis(fig[1,1]; axis...)
    p = barplot!(ax, x, heights; kwargs...)
    return (figure=fig, axis=ax, plot=p)
end

# ─── Axis helpers ───

function xlims!(ax::Axis, lo::Real, hi::Real)
    ax.xlim_min = Float64(lo)
    ax.xlim_max = Float64(hi)
end

function ylims!(ax::Axis, lo::Real, hi::Real)
    ax.ylim_min = Float64(lo)
    ax.ylim_max = Float64(hi)
end
