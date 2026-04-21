using Test
using WasmPlot

@testset "WasmPlot.jl" begin
    @testset "Figure creation" begin
        fig = Figure(size=(800, 600))
        @test fig.width == 800
        @test fig.height == 600
        @test fig.backgroundcolor == WasmPlot.RGBA(1.0, 1.0, 1.0)
        @test isempty(fig.axes)
    end

    @testset "Axis creation" begin
        fig = Figure()
        ax = Axis(fig[1, 1]; xlabel="x", ylabel="y", title="Test")
        @test ax.xlabel == "x"
        @test ax.ylabel == "y"
        @test ax.title == "Test"
        @test length(fig.axes) == 1
        @test fig.axes[1] === ax
        @test ax.row == 1
        @test ax.col == 1
    end

    @testset "GridPosition" begin
        fig = Figure()
        gp = fig[2, 3]
        @test gp isa GridPosition
        @test gp.row == 2
        @test gp.col == 3
    end

    @testset "lines!" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p = lines!(ax, [1.0, 2.0, 3.0], [4.0, 5.0, 6.0]; color=:blue, linewidth=3.0)
        @test p isa WasmPlot.LinePlot
        @test p.x == [1.0, 2.0, 3.0]
        @test p.y == [4.0, 5.0, 6.0]
        @test p.linewidth == 3.0
        @test length(ax.line_plots) == 1
    end

    @testset "scatter!" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p = scatter!(ax, [1.0, 2.0], [3.0, 4.0]; markersize=12)
        @test p isa WasmPlot.ScatterPlot
        @test p.markersize == 12.0
        @test length(ax.scatter_plots) == 1
    end

    @testset "barplot!" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p = barplot!(ax, [1.0, 2.0, 3.0], [10.0, 20.0, 15.0])
        @test p isa WasmPlot.BarPlot
        @test p.heights == [10.0, 20.0, 15.0]
        # Makie width: min gap (1.0) * (1 - 0.2) = 0.8
        @test p.width ≈ 0.8
        @test length(ax.bar_plots) == 1
    end

    @testset "Non-mutating forms" begin
        result = lines([1.0, 2.0], [3.0, 4.0]; axis=(title="Test",))
        @test result.figure isa Figure
        @test result.axis isa Axis
        @test result.axis.title == "Test"
        @test result.plot isa WasmPlot.LinePlot
    end

    @testset "Color cycling" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p1 = lines!(ax, [1.0], [1.0])
        p2 = lines!(ax, [1.0], [1.0])
        @test p1.color == WasmPlot.cycle_color(1)
        @test p2.color == WasmPlot.cycle_color(2)
    end

    @testset "Tick computation" begin
        ticks = WasmPlot.compute_ticks(0.0, 10.0)
        @test length(ticks) >= 3
        @test all(t -> 0.0 <= t <= 10.0, ticks)
    end

    @testset "Data limits" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 5.0, 10.0], [-1.0, 0.0, 1.0])
        xmin, xmax, ymin, ymax = WasmPlot.compute_data_limits(ax)
        @test xmin < 0.0
        @test xmax > 10.0
        @test ymin < -1.0
        @test ymax > 1.0
    end

    @testset "Data limits with xlim/ylim" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 10.0], [0.0, 10.0])
        xlims!(ax, -5.0, 15.0)
        xmin, xmax, _, _ = WasmPlot.compute_data_limits(ax)
        @test xmin == -5.0
        @test xmax == 15.0
    end

    @testset "Bar chart includes y=0" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        barplot!(ax, [1.0, 2.0], [5.0, 10.0])
        _, _, ymin, _ = WasmPlot.compute_data_limits(ax)
        @test ymin <= 0.0
    end

    @testset "data_to_pixel" begin
        @test WasmPlot.data_to_pixel(5.0, 0.0, 10.0, 100.0, 200.0) ≈ 150.0
        @test WasmPlot.data_to_pixel(0.0, 0.0, 10.0, 100.0, 200.0) ≈ 100.0
    end

    @testset "Viewport computation" begin
        fig = Figure(size=(600, 400))
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 1.0], [0.0, 1.0])
        vp = WasmPlot.compute_viewport(ax, fig)
        @test vp.plot_left > 0.0
        @test vp.plot_right < 600.0
        @test vp.plot_top > 0.0
        @test vp.plot_bottom < 400.0
    end

    @testset "render! runs without error" begin
        fig = Figure(size=(400, 300))
        ax = Axis(fig[1, 1]; title="Test", xlabel="x", ylabel="y")
        lines!(ax, [1.0, 2.0, 3.0], [1.0, 4.0, 2.0])
        scatter!(ax, [1.5, 2.5], [3.0, 3.5])
        render!(fig)
    end

    @testset "generate_js_render" begin
        fig = Figure(size=(400, 300))
        ax = Axis(fig[1, 1])
        lines!(ax, [1.0, 2.0], [3.0, 4.0])
        js = generate_js_render(fig)
        @test contains(js, "c2d.clear_rect")
        @test contains(js, "c2d.begin_path")
        @test contains(js, "c2d.stroke")
    end

    @testset "Canvas2D JS glue" begin
        glue = canvas2d_js_glue()
        @test contains(glue, "canvas2d_imports")
        @test contains(glue, "beginPath")
        @test contains(glue, "return 0n")
    end

    @testset "Import specs" begin
        specs = canvas2d_import_specs()
        @test length(specs) == length(WasmPlot.CANVAS2D_STUBS)
        names = [s.name for s in specs]
        @test "begin_path" in names
        @test "move_to" in names
    end

    @testset "Multi-panel layout" begin
        fig = Figure(size=(800, 600))
        ax1 = Axis(fig[1, 1]; title="Top Left")
        ax2 = Axis(fig[1, 2]; title="Top Right")
        ax3 = Axis(fig[2, 1]; title="Bottom Left")
        lines!(ax1, [1.0, 2.0], [1.0, 2.0])
        scatter!(ax2, [1.0, 2.0], [1.0, 2.0])
        barplot!(ax3, [1.0, 2.0], [3.0, 4.0])
        render!(fig)
        js = generate_js_render(fig)
        @test length(js) > 100
    end

    @testset "NaN sentinel for auto limits" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        @test isnan(ax.xlim_min)
        @test isnan(ax.xlim_max)
        @test isnan(ax.ylim_min)
        @test isnan(ax.ylim_max)
    end

    @testset "Concrete types — no abstract fields" begin
        # Verify all fields are concrete (WASM-compilable)
        fig = Figure()
        ax = Axis(fig[1, 1])
        @test ax.line_plots isa Vector{WasmPlot.LinePlot}
        @test ax.scatter_plots isa Vector{WasmPlot.ScatterPlot}
        @test ax.bar_plots isa Vector{WasmPlot.BarPlot}
        @test ax.xscale isa Int64
        @test ax.yscale isa Int64
        @test ax._plot_count isa Int64
        @test ax.row isa Int64
        @test ax.col isa Int64
    end
end

include("wasm_compile_test.jl")
include("wasm_e2e_test.jl")
include("test_aqua.jl")
