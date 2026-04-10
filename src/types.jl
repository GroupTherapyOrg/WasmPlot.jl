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

# Named color palette (Makie uses Colors.jl, we inline the essentials)
const NAMED_COLORS = Dict{Symbol, RGBA}(
    :black      => RGBA(0.0, 0.0, 0.0),
    :white      => RGBA(1.0, 1.0, 1.0),
    :red        => RGBA(1.0, 0.0, 0.0),
    :green      => RGBA(0.0, 0.5, 0.0),
    :blue       => RGBA(0.235, 0.51, 0.965),    # Makie's default blue
    :orange     => RGBA(0.902, 0.494, 0.133),
    :purple     => RGBA(0.584, 0.345, 0.698),
    :cyan       => RGBA(0.0, 0.745, 0.812),
    :gray       => RGBA(0.5, 0.5, 0.5),
    :lightgray  => RGBA(0.83, 0.83, 0.83),
    :transparent => RGBA(0.0, 0.0, 0.0, 0.0),
)

# Default color cycle (Makie's wong palette)
const COLOR_CYCLE = RGBA[
    RGBA(0.0, 0.447, 0.698),    # blue
    RGBA(0.902, 0.624, 0.0),    # orange
    RGBA(0.0, 0.620, 0.451),    # green
    RGBA(0.835, 0.369, 0.0),    # vermillion
    RGBA(0.337, 0.706, 0.914),  # sky blue
    RGBA(0.800, 0.475, 0.655),  # pink
]

resolve_color(c::RGBA) = c
resolve_color(c::Symbol) = get(NAMED_COLORS, c, NAMED_COLORS[:black])
resolve_color(c::Tuple{Float64, Float64, Float64}) = RGBA(c[1], c[2], c[3])
resolve_color(c::Tuple{Float64, Float64, Float64, Float64}) = RGBA(c[1], c[2], c[3], c[4])
resolve_color(::Nothing) = NAMED_COLORS[:black]

cycle_color(idx::Int) = COLOR_CYCLE[mod1(idx, length(COLOR_CYCLE))]

# ─── Abstract Plot ───

abstract type AbstractPlot end

struct LinePlot <: AbstractPlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::RGBA
    linewidth::Float64
    linestyle::Symbol      # :solid, :dash, :dot
    label::String
end

struct ScatterPlot <: AbstractPlot
    x::Vector{Float64}
    y::Vector{Float64}
    color::RGBA
    markersize::Float64
    marker::Symbol         # :circle, :rect, :cross
    strokecolor::RGBA
    strokewidth::Float64
    label::String
end

struct BarPlot <: AbstractPlot
    x::Vector{Float64}
    heights::Vector{Float64}
    color::RGBA
    width::Float64
    strokecolor::RGBA
    strokewidth::Float64
    label::String
end

# ─── Axis ───

mutable struct Axis
    plots::Vector{AbstractPlot}
    xlabel::String
    ylabel::String
    title::String
    xlim::Union{Tuple{Float64, Float64}, Nothing}
    ylim::Union{Tuple{Float64, Float64}, Nothing}
    xscale::Symbol           # :identity, :log10
    yscale::Symbol
    backgroundcolor::RGBA
    xgridvisible::Bool
    ygridvisible::Bool
    gridcolor::RGBA
    spinecolor::RGBA
    _plot_count::Int         # for color cycling
end

# ─── Figure + GridPosition ───

mutable struct Figure
    size::Tuple{Int, Int}
    backgroundcolor::RGBA
    fontsize::Float64
    _grid::Dict{Tuple{Int,Int}, Axis}
end

struct GridPosition
    figure::Figure
    row::Int
    col::Int
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
    Figure(size, resolve_color(backgroundcolor), Float64(fontsize), Dict{Tuple{Int,Int}, Axis}())
end

Base.getindex(fig::Figure, row::Int, col::Int) = GridPosition(fig, row, col)

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
    sc = spinecolor === nothing ? RGBA(0.0, 0.0, 0.0, 0.6) : resolve_color(spinecolor)
    xl = xlim === nothing ? nothing : (Float64(xlim[1]), Float64(xlim[2]))
    yl = ylim === nothing ? nothing : (Float64(ylim[1]), Float64(ylim[2]))

    ax = Axis(AbstractPlot[], xlabel, ylabel, title, xl, yl,
              xscale, yscale, resolve_color(backgroundcolor),
              xgridvisible, ygridvisible, gc, sc, 0)
    gp.figure._grid[(gp.row, gp.col)] = ax
    return ax
end

# ─── Plot Functions (Makie ! convention) ───

"""
    lines!(ax, x, y; color=:auto, linewidth=1.5, linestyle=:solid, label="")

Add a line plot to an existing axis. Matches Makie's `lines!`.
"""
function lines!(ax::Axis, x, y;
    color = nothing,
    linewidth::Real = 1.5,
    linestyle::Symbol = :solid,
    label::String = ""
)
    ax._plot_count += 1
    c = color === nothing ? cycle_color(ax._plot_count) : resolve_color(color)
    p = LinePlot(Float64.(collect(x)), Float64.(collect(y)),
                 c, Float64(linewidth), linestyle, label)
    push!(ax.plots, p)
    return p
end

"""
    scatter!(ax, x, y; color=:auto, markersize=9, marker=:circle, label="")

Add a scatter plot to an existing axis. Matches Makie's `scatter!`.
"""
function scatter!(ax::Axis, x, y;
    color = nothing,
    markersize::Real = 9,
    marker::Symbol = :circle,
    strokecolor = :black,
    strokewidth::Real = 0,
    label::String = ""
)
    ax._plot_count += 1
    c = color === nothing ? cycle_color(ax._plot_count) : resolve_color(color)
    p = ScatterPlot(Float64.(collect(x)), Float64.(collect(y)),
                    c, Float64(markersize), marker,
                    resolve_color(strokecolor), Float64(strokewidth), label)
    push!(ax.plots, p)
    return p
end

"""
    barplot!(ax, x, heights; color=:auto, width=0.8, label="")

Add a bar plot to an existing axis. Matches Makie's `barplot!`.
"""
function barplot!(ax::Axis, x, heights;
    color = nothing,
    width::Real = 0.8,
    strokecolor = :black,
    strokewidth::Real = 0,
    label::String = ""
)
    ax._plot_count += 1
    c = color === nothing ? cycle_color(ax._plot_count) : resolve_color(color)
    p = BarPlot(Float64.(collect(x)), Float64.(collect(heights)),
                c, Float64(width), resolve_color(strokecolor), Float64(strokewidth), label)
    push!(ax.plots, p)
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
    ax.xlim = (Float64(lo), Float64(hi))
end

function ylims!(ax::Axis, lo::Real, hi::Real)
    ax.ylim = (Float64(lo), Float64(hi))
end
