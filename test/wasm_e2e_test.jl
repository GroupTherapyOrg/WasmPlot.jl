# wasm_e2e_test.jl — Rigorous e2e tests: compile to WASM, run in Node.js, compare to Julia
#
# Pattern: WasmTarget's compare_julia_wasm (Julia = ground truth, WASM = test)
# Each test function returns a scalar (Float64/Int64) that summarizes the computation.
# WASM result must match Julia exactly (or within float tolerance).
#
# Run: julia +1.12 --project=. test/wasm_e2e_test.jl

using Test
using WasmPlot
import WasmTarget

# Import WasmTarget's e2e test utilities
include(joinpath(dirname(pathof(WasmTarget)), "..", "test", "utils.jl"))

# ══════════════════════════════════════════════════════════════════════════════
# Test functions — each returns a scalar for Julia↔WASM comparison
# ══════════════════════════════════════════════════════════════════════════════

# ─── data_to_pixel ───

_e2e_d2p_mid()::Float64 = WasmPlot.data_to_pixel(5.0, 0.0, 10.0, 100.0, 200.0)
_e2e_d2p_min()::Float64 = WasmPlot.data_to_pixel(0.0, 0.0, 10.0, 100.0, 200.0)
_e2e_d2p_max()::Float64 = WasmPlot.data_to_pixel(10.0, 0.0, 10.0, 100.0, 200.0)
_e2e_d2p_neg()::Float64 = WasmPlot.data_to_pixel(-5.0, -10.0, 10.0, 0.0, 400.0)
_e2e_d2p_degen()::Float64 = WasmPlot.data_to_pixel(5.0, 5.0, 5.0, 100.0, 200.0)

# ─── RGBA struct ───

_e2e_rgba_sum()::Float64 = begin
    c = WasmPlot.RGBA(0.25, 0.5, 0.75, 1.0)
    c.r + c.g + c.b + c.a
end

_e2e_rgba_default()::Float64 = begin
    c = WasmPlot.RGBA(0.1, 0.2, 0.3)
    c.a  # should be 1.0
end

# ─── Color cycle (Makie wong palette order) ───

_e2e_color_cycle_1()::Float64 = WasmPlot.cycle_color(1).r  # blue: 0.0
_e2e_color_cycle_2()::Float64 = WasmPlot.cycle_color(2).g  # orange: 0.624
_e2e_color_cycle_4()::Float64 = WasmPlot.cycle_color(4).r  # reddish purple: 0.800
_e2e_color_cycle_7()::Float64 = WasmPlot.cycle_color(7).b  # yellow: 0.259
_e2e_color_cycle_wrap()::Float64 = WasmPlot.cycle_color(8).r  # wraps to 1st: 0.0

# ─── compute_ticks ───

_e2e_ticks_0_10_count()::Int64 = Int64(length(WasmPlot.compute_ticks(0.0, 10.0, 5)))
_e2e_ticks_0_10_sum()::Float64 = sum(WasmPlot.compute_ticks(0.0, 10.0, 5))
_e2e_ticks_neg()::Float64 = sum(WasmPlot.compute_ticks(-5.0, 5.0, 5))
_e2e_ticks_small()::Float64 = sum(WasmPlot.compute_ticks(0.0, 0.1, 5))
_e2e_ticks_large()::Float64 = sum(WasmPlot.compute_ticks(0.0, 1000.0, 5))

# ─── LinePlot struct ───

_e2e_lineplot_fields()::Float64 = begin
    p = WasmPlot.LinePlot(Float64[1.0, 2.0, 3.0], Float64[4.0, 5.0, 6.0],
        WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0), 2.0, Int64(0), "")
    p.linewidth + Float64(length(p.x)) + p.color.b
end

# ─── ScatterPlot struct ───

_e2e_scatterplot_fields()::Float64 = begin
    p = WasmPlot.ScatterPlot(Float64[1.0, 2.0], Float64[3.0, 4.0],
        WasmPlot.RGBA(1.0, 0.0, 0.0, 1.0), 9.0, Int64(0),
        WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0), 0.0, "")
    p.markersize + Float64(length(p.x)) + p.color.r
end

# ─── BarPlot struct ───

_e2e_barplot_fields()::Float64 = begin
    p = WasmPlot.BarPlot(Float64[1.0, 2.0, 3.0], Float64[10.0, 20.0, 15.0],
        WasmPlot.RGBA(0.0, 0.5, 0.0, 1.0), 0.8,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0), 0.0, "")
    p.width + Float64(length(p.heights)) + p.heights[2]
end

# ─── HeatmapPlot struct ───

_e2e_heatmap_fields()::Float64 = begin
    vals = Float64[]
    i = Int64(0)
    while i < Int64(25)
        push!(vals, sin(Float64(i) * 0.5))
        i = i + Int64(1)
    end
    p = WasmPlot.HeatmapPlot(Int64(5), Int64(5), 0.0, 5.0, 0.0, 5.0, vals, -1.0, 1.0)
    Float64(p.nx) + Float64(length(p.values)) + p.vmax
end

# ─── Viridis colormap ───

_e2e_viridis_0()::Float64 = begin r, g, b = WasmPlot._viridis(0.0); r + g + b end
_e2e_viridis_25()::Float64 = begin r, g, b = WasmPlot._viridis(0.25); r + g + b end
_e2e_viridis_50()::Float64 = begin r, g, b = WasmPlot._viridis(0.5); r + g + b end
_e2e_viridis_75()::Float64 = begin r, g, b = WasmPlot._viridis(0.75); r + g + b end
_e2e_viridis_100()::Float64 = begin r, g, b = WasmPlot._viridis(1.0); r + g + b end

# ─── compute_data_limits ───

_e2e_limits_line()::Float64 = begin
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[WasmPlot.LinePlot(Float64[0.0, 5.0, 10.0], Float64[-1.0, 0.0, 1.0],
            WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0), 1.5, Int64(0), "")],
        WasmPlot.ScatterPlot[], WasmPlot.BarPlot[], WasmPlot.HeatmapPlot[],
        "", "", "", NaN, NaN, NaN, NaN, Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12), WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
        Int64(0), Int64(1), Int64(1))
    xmin, xmax, ymin, ymax = WasmPlot.compute_data_limits(ax)
    xmin + xmax + ymin + ymax
end

_e2e_limits_bar_includes_zero()::Float64 = begin
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[], WasmPlot.ScatterPlot[],
        WasmPlot.BarPlot[WasmPlot.BarPlot(Float64[1.0, 2.0], Float64[5.0, 10.0],
            WasmPlot.RGBA(0.0, 0.5, 0.0, 1.0), 0.8, WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0), 0.0, "")],
        WasmPlot.HeatmapPlot[],
        "", "", "", NaN, NaN, NaN, NaN, Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12), WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
        Int64(0), Int64(1), Int64(1))
    _, _, ymin, _ = WasmPlot.compute_data_limits(ax)
    ymin  # should be <= 0
end

# ─── compute_viewport ───

_e2e_viewport_bounds()::Float64 = begin
    fig = WasmPlot.Figure(Int64(600), Int64(400), WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), 14.0, WasmPlot.Axis[])
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[WasmPlot.LinePlot(Float64[0.0, 1.0], Float64[0.0, 1.0],
            WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0), 1.5, Int64(0), "")],
        WasmPlot.ScatterPlot[], WasmPlot.BarPlot[], WasmPlot.HeatmapPlot[],
        "", "", "", NaN, NaN, NaN, NaN, Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12), WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
        Int64(0), Int64(1), Int64(1))
    push!(fig.axes, ax)
    vp = WasmPlot.compute_viewport(ax, fig)
    vp.plot_left + vp.plot_right + vp.plot_top + vp.plot_bottom
end

# ─── Full multi-panel figure ───

_e2e_multi_panel_viewport_count()::Int64 = begin
    fig = WasmPlot.Figure(Int64(800), Int64(600), WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), 14.0, WasmPlot.Axis[])
    for r in Int64(1):Int64(2)
        for c in Int64(1):Int64(2)
            ax = WasmPlot.Axis(
                WasmPlot.LinePlot[WasmPlot.LinePlot(Float64[0.0, 1.0], Float64[0.0, 1.0],
                    WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0), 1.5, Int64(0), "")],
                WasmPlot.ScatterPlot[], WasmPlot.BarPlot[], WasmPlot.HeatmapPlot[],
                "", "", "", NaN, NaN, NaN, NaN, Int64(0), Int64(0),
                WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0), true, true,
                WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12), WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
                Int64(0), r, c)
            push!(fig.axes, ax)
        end
    end
    Int64(length(fig.axes))
end

# ══════════════════════════════════════════════════════════════════════════════
# Run all e2e tests
# ══════════════════════════════════════════════════════════════════════════════

@testset "WasmPlot e2e: Julia↔WASM Parity" begin

    @testset "data_to_pixel" begin
        for (name, f) in [
            ("midpoint", _e2e_d2p_mid),
            ("min", _e2e_d2p_min),
            ("max", _e2e_d2p_max),
            ("negative", _e2e_d2p_neg),
            ("degenerate", _e2e_d2p_degen),
        ]
            r = compare_julia_wasm(f)
            @test r.pass
            !r.pass && println("  ✗ d2p $name: expected=$(r.expected) actual=$(r.actual)")
        end
    end

    @testset "RGBA struct" begin
        r1 = compare_julia_wasm(_e2e_rgba_sum)
        @test r1.pass
        r2 = compare_julia_wasm(_e2e_rgba_default)
        @test r2.pass
    end

    @testset "Color cycle (wong palette order)" begin
        for (name, f, expected) in [
            ("blue.r", _e2e_color_cycle_1, 0.0),
            ("orange.g", _e2e_color_cycle_2, 0.624),
            ("reddish_purple.r", _e2e_color_cycle_4, 0.8),
            ("yellow.b", _e2e_color_cycle_7, 0.259),
            ("wrap", _e2e_color_cycle_wrap, 0.0),
        ]
            r = compare_julia_wasm(f)
            @test r.pass
        end
    end

    @testset "compute_ticks" begin
        for (name, f) in [
            ("0-10 count", _e2e_ticks_0_10_count),
            ("0-10 sum", _e2e_ticks_0_10_sum),
            ("negative", _e2e_ticks_neg),
            ("small range", _e2e_ticks_small),
            ("large range", _e2e_ticks_large),
        ]
            r = compare_julia_wasm(f)
            @test r.pass
            !r.pass && println("  ✗ ticks $name: expected=$(r.expected) actual=$(r.actual)")
        end
    end

    @testset "Plot struct fields" begin
        r1 = compare_julia_wasm(_e2e_lineplot_fields)
        @test r1.pass
        r2 = compare_julia_wasm(_e2e_scatterplot_fields)
        @test r2.pass
        r3 = compare_julia_wasm(_e2e_barplot_fields)
        @test r3.pass
        r4 = compare_julia_wasm(_e2e_heatmap_fields)
        @test r4.pass
    end

    @testset "Viridis colormap" begin
        for (name, f) in [
            ("t=0.0", _e2e_viridis_0),
            ("t=0.25", _e2e_viridis_25),
            ("t=0.5", _e2e_viridis_50),
            ("t=0.75", _e2e_viridis_75),
            ("t=1.0", _e2e_viridis_100),
        ]
            r = compare_julia_wasm(f)
            @test r.pass
            !r.pass && println("  ✗ viridis $name: expected=$(r.expected) actual=$(r.actual)")
        end
    end

    @testset "compute_data_limits" begin
        r1 = compare_julia_wasm(_e2e_limits_line)
        @test r1.pass
        r2 = compare_julia_wasm(_e2e_limits_bar_includes_zero)
        @test r2.pass
        # Bar chart: ymin must be <= 0 (Makie fillto=0)
        @test r2.expected <= 0.0
    end

    @testset "compute_viewport" begin
        r = compare_julia_wasm(_e2e_viewport_bounds)
        @test r.pass
    end

    @testset "Multi-panel figure" begin
        r = compare_julia_wasm(_e2e_multi_panel_viewport_count)
        @test r.pass
        @test r.expected == 4
    end
end
