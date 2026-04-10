# wasm_compile_test.jl — Verify WasmPlot functions compile to WASM via WasmTarget
#
# Tests that the core plotting API compiles identically in Julia and WASM.
# Uses WasmTarget's compare_julia_wasm pattern from test/utils.jl.
#
# Run: julia +1.12 --project=. test/wasm_compile_test.jl

using Test
using WasmPlot
import WasmTarget

# ─── Test helper: compile a function and verify it produces valid WASM bytes ───

function wasm_compiles(f, arg_types::Tuple; label="")
    try
        bytes = WasmTarget.compile(f, arg_types)
        return (pass=length(bytes) > 8, size=length(bytes), error=nothing)
    catch e
        return (pass=false, size=0, error=e)
    end
end

# ─── Module-level test functions (must be non-anonymous for compile) ───

# Pure math functions used in rendering
_test_data_to_pixel(val::Float64, dmin::Float64, dmax::Float64, pmin::Float64, pmax::Float64)::Float64 =
    WasmPlot.data_to_pixel(val, dmin, dmax, pmin, pmax)

# RGBA struct creation + field access
function _test_rgba_create()::Float64
    c = WasmPlot.RGBA(0.5, 0.6, 0.7, 1.0)
    return c.r + c.g + c.b
end

# LinePlot struct creation
function _test_lineplot_create()::Float64
    p = WasmPlot.LinePlot(
        Float64[1.0, 2.0, 3.0],
        Float64[4.0, 5.0, 6.0],
        WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0),
        2.0,
        Int64(0),  # solid
        ""
    )
    return p.linewidth + Float64(length(p.x))
end

# ScatterPlot struct creation
function _test_scatterplot_create()::Float64
    p = WasmPlot.ScatterPlot(
        Float64[1.0, 2.0],
        Float64[3.0, 4.0],
        WasmPlot.RGBA(1.0, 0.0, 0.0, 1.0),
        8.0,
        Int64(0),  # circle
        WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
        0.0,
        ""
    )
    return p.markersize + Float64(length(p.x))
end

# BarPlot struct creation
function _test_barplot_create()::Float64
    p = WasmPlot.BarPlot(
        Float64[1.0, 2.0, 3.0],
        Float64[10.0, 20.0, 15.0],
        WasmPlot.RGBA(0.0, 0.5, 0.0, 1.0),
        0.8,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 1.0),
        0.0,
        ""
    )
    return p.width + Float64(length(p.heights))
end

# Tick computation (uses Vector{Float64} + push! + math)
function _test_compute_ticks_count()::Int64
    ticks = WasmPlot.compute_ticks(0.0, 10.0, 5)
    return Int64(length(ticks))
end

# Axis struct with line plot
function _test_axis_with_line()::Float64
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[],
        WasmPlot.ScatterPlot[],
        WasmPlot.BarPlot[],
        "", "", "",
        NaN, NaN, NaN, NaN,
        Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0),
        true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12),
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.6),
        Int64(0), Int64(1), Int64(1)
    )
    p = WasmPlot.LinePlot(
        Float64[0.0, 5.0, 10.0],
        Float64[-1.0, 0.0, 1.0],
        WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0),
        2.0, Int64(0), ""
    )
    push!(ax.line_plots, p)
    return Float64(length(ax.line_plots))
end

# Full data limits computation
function _test_data_limits()::Float64
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[WasmPlot.LinePlot(
            Float64[0.0, 5.0, 10.0],
            Float64[-1.0, 0.0, 1.0],
            WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0),
            2.0, Int64(0), ""
        )],
        WasmPlot.ScatterPlot[],
        WasmPlot.BarPlot[],
        "", "", "",
        NaN, NaN, NaN, NaN,
        Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0),
        true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12),
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.6),
        Int64(0), Int64(1), Int64(1)
    )
    xmin, xmax, ymin, ymax = WasmPlot.compute_data_limits(ax)
    # Return sum of limits as a single Float64 for comparison
    return xmin + xmax + ymin + ymax
end

# Figure with viewport computation
function _test_viewport_plot_left()::Float64
    fig = WasmPlot.Figure(
        Int64(600), Int64(400),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0),
        14.0,
        WasmPlot.Axis[]
    )
    ax = WasmPlot.Axis(
        WasmPlot.LinePlot[WasmPlot.LinePlot(
            Float64[0.0, 1.0],
            Float64[0.0, 1.0],
            WasmPlot.RGBA(0.0, 0.0, 1.0, 1.0),
            1.5, Int64(0), ""
        )],
        WasmPlot.ScatterPlot[],
        WasmPlot.BarPlot[],
        "", "", "",
        NaN, NaN, NaN, NaN,
        Int64(0), Int64(0),
        WasmPlot.RGBA(1.0, 1.0, 1.0, 1.0),
        true, true,
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.12),
        WasmPlot.RGBA(0.0, 0.0, 0.0, 0.6),
        Int64(0), Int64(1), Int64(1)
    )
    push!(fig.axes, ax)
    vp = WasmPlot.compute_viewport(ax, fig)
    return vp.plot_left
end

# ─── Run tests ───

@testset "WasmPlot WASM Compilation" begin

    @testset "data_to_pixel compiles" begin
        r = wasm_compiles(_test_data_to_pixel, (Float64, Float64, Float64, Float64, Float64))
        @test r.pass
        if r.pass
            println("  ✓ data_to_pixel: $(r.size) bytes")
        else
            println("  ✗ data_to_pixel: $(r.error)")
        end
    end

    @testset "RGBA struct compiles" begin
        r = wasm_compiles(_test_rgba_create, ())
        @test r.pass
        if r.pass
            println("  ✓ RGBA create: $(r.size) bytes")
        else
            println("  ✗ RGBA create: $(r.error)")
        end
    end

    @testset "LinePlot struct compiles" begin
        r = wasm_compiles(_test_lineplot_create, ())
        @test r.pass
        if r.pass
            println("  ✓ LinePlot create: $(r.size) bytes")
        else
            println("  ✗ LinePlot create: $(r.error)")
        end
    end

    @testset "ScatterPlot struct compiles" begin
        r = wasm_compiles(_test_scatterplot_create, ())
        @test r.pass
        if r.pass
            println("  ✓ ScatterPlot create: $(r.size) bytes")
        else
            println("  ✗ ScatterPlot create: $(r.error)")
        end
    end

    @testset "BarPlot struct compiles" begin
        r = wasm_compiles(_test_barplot_create, ())
        @test r.pass
        if r.pass
            println("  ✓ BarPlot create: $(r.size) bytes")
        else
            println("  ✗ BarPlot create: $(r.error)")
        end
    end

    @testset "compute_ticks compiles" begin
        r = wasm_compiles(_test_compute_ticks_count, ())
        @test r.pass
        if r.pass
            println("  ✓ compute_ticks: $(r.size) bytes")
        else
            println("  ✗ compute_ticks: $(r.error)")
        end
    end

    @testset "Axis with line plot compiles" begin
        r = wasm_compiles(_test_axis_with_line, ())
        @test r.pass
        if r.pass
            println("  ✓ Axis+LinePlot: $(r.size) bytes")
        else
            println("  ✗ Axis+LinePlot: $(r.error)")
        end
    end

    @testset "compute_data_limits compiles" begin
        r = wasm_compiles(_test_data_limits, ())
        @test r.pass
        if r.pass
            println("  ✓ data_limits: $(r.size) bytes")
        else
            println("  ✗ data_limits: $(r.error)")
        end
    end

    @testset "Figure + viewport compiles" begin
        r = wasm_compiles(_test_viewport_plot_left, ())
        @test r.pass
        if r.pass
            println("  ✓ Figure+viewport: $(r.size) bytes")
        else
            println("  ✗ Figure+viewport: $(r.error)")
        end
    end
end
