using Test
using WasmPlot

@testset "WasmPlot.jl" begin
    @testset "Figure creation" begin
        fig = Figure(size=(800, 600))
        @test fig.size == (800, 600)
        @test fig.backgroundcolor == WasmPlot.RGBA(1.0, 1.0, 1.0)
        @test isempty(fig._grid)
    end

    @testset "Axis creation" begin
        fig = Figure()
        ax = Axis(fig[1, 1]; xlabel="x", ylabel="y", title="Test")
        @test ax.xlabel == "x"
        @test ax.ylabel == "y"
        @test ax.title == "Test"
        @test haskey(fig._grid, (1, 1))
        @test fig._grid[(1, 1)] === ax
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
        x = [1.0, 2.0, 3.0]
        y = [4.0, 5.0, 6.0]
        p = lines!(ax, x, y; color=:blue, linewidth=3.0)
        @test p isa WasmPlot.LinePlot
        @test p.x == [1.0, 2.0, 3.0]
        @test p.y == [4.0, 5.0, 6.0]
        @test p.linewidth == 3.0
        @test length(ax.plots) == 1
    end

    @testset "scatter!" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p = scatter!(ax, [1.0, 2.0], [3.0, 4.0]; markersize=12)
        @test p isa WasmPlot.ScatterPlot
        @test p.markersize == 12.0
    end

    @testset "barplot!" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p = barplot!(ax, [1.0, 2.0, 3.0], [10.0, 20.0, 15.0])
        @test p isa WasmPlot.BarPlot
        @test p.heights == [10.0, 20.0, 15.0]
    end

    @testset "Non-mutating forms" begin
        result = lines([1.0, 2.0], [3.0, 4.0]; axis=(title="Test",))
        @test result.figure isa Figure
        @test result.axis isa Axis
        @test result.axis.title == "Test"
        @test result.plot isa WasmPlot.LinePlot
    end

    @testset "Color resolution" begin
        @test WasmPlot.resolve_color(:blue) == WasmPlot.NAMED_COLORS[:blue]
        @test WasmPlot.resolve_color(:black) == WasmPlot.RGBA(0.0, 0.0, 0.0)
        c = WasmPlot.resolve_color((0.5, 0.6, 0.7))
        @test c.r ≈ 0.5
    end

    @testset "Color cycling" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        p1 = lines!(ax, [1.0], [1.0])
        p2 = lines!(ax, [1.0], [1.0])
        @test p1.color == WasmPlot.COLOR_CYCLE[1]
        @test p2.color == WasmPlot.COLOR_CYCLE[2]
    end

    @testset "Tick computation" begin
        ticks = WasmPlot.compute_ticks(0.0, 10.0)
        @test length(ticks) >= 3
        @test all(t -> 0.0 <= t <= 10.0, ticks)
        # Should be "nice" numbers
        @test all(t -> t == round(t), ticks)
    end

    @testset "Data limits" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 5.0, 10.0], [-1.0, 0.0, 1.0])
        xmin, xmax, ymin, ymax = WasmPlot.compute_data_limits(ax)
        @test xmin < 0.0   # padding
        @test xmax > 10.0  # padding
        @test ymin < -1.0
        @test ymax > 1.0
    end

    @testset "Data limits with xlim/ylim override" begin
        fig = Figure()
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 10.0], [0.0, 10.0])
        xlims!(ax, -5.0, 15.0)
        xmin, xmax, _, _ = WasmPlot.compute_data_limits(ax)
        @test xmin == -5.0
        @test xmax == 15.0
    end

    @testset "data_to_pixel" begin
        # Map 5.0 from [0, 10] to [100, 200]
        px = WasmPlot.data_to_pixel(5.0, 0.0, 10.0, 100.0, 200.0)
        @test px ≈ 150.0
        # Map 0.0 (start) to px_min
        px0 = WasmPlot.data_to_pixel(0.0, 0.0, 10.0, 100.0, 200.0)
        @test px0 ≈ 100.0
    end

    @testset "Number formatting" begin
        @test WasmPlot.format_number_chars(0.0) == [Int('0')]
        @test WasmPlot.format_number_chars(5.0) == [Int('5')]
        @test WasmPlot.format_number_chars(-3.0) == [Int('-'), Int('3')]
        chars10 = WasmPlot.format_number_chars(10.0)
        @test chars10 == [Int('1'), Int('0')]
    end

    @testset "Viewport computation" begin
        fig = Figure(size=(600, 400))
        ax = Axis(fig[1, 1])
        lines!(ax, [0.0, 1.0], [0.0, 1.0])
        vp = WasmPlot.compute_viewport(ax, fig, 1, 1)
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
        # render! calls canvas2d stubs (no-ops) — should not error
        render!(fig)
    end

    @testset "generate_js_render" begin
        fig = Figure(size=(400, 300))
        ax = Axis(fig[1, 1])
        lines!(ax, [1.0, 2.0], [3.0, 4.0])
        js = generate_js_render(fig)
        @test contains(js, "c2d.clear_rect")
        @test contains(js, "c2d.begin_path")
        @test contains(js, "c2d.move_to")
        @test contains(js, "c2d.line_to")
        @test contains(js, "c2d.stroke")
    end

    @testset "Canvas2D JS glue" begin
        glue = canvas2d_js_glue()
        @test contains(glue, "canvas2d_imports")
        @test contains(glue, "beginPath")
        @test contains(glue, "moveTo")
        @test contains(glue, "fillRect")
        @test contains(glue, "return 0n")
    end

    @testset "Import specs" begin
        specs = canvas2d_import_specs()
        @test length(specs) == length(WasmPlot.CANVAS2D_STUBS)
        names = [s.name for s in specs]
        @test "begin_path" in names
        @test "move_to" in names
        @test "stroke" in names
        @test "fill_rect" in names
    end

    @testset "Multi-panel layout" begin
        fig = Figure(size=(800, 600))
        ax1 = Axis(fig[1, 1]; title="Top Left")
        ax2 = Axis(fig[1, 2]; title="Top Right")
        ax3 = Axis(fig[2, 1]; title="Bottom Left")
        lines!(ax1, [1.0, 2.0], [1.0, 2.0])
        scatter!(ax2, [1.0, 2.0], [1.0, 2.0])
        barplot!(ax3, [1.0, 2.0], [3.0, 4.0])
        # Should render all panels without error
        render!(fig)
        js = generate_js_render(fig)
        @test length(js) > 100
    end
end
