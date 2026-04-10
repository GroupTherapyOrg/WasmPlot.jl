# multi_panel.jl — Multi-panel layout demo
#
# Demonstrates: Figure grid layout, scatter, barplot, multiple axes.
# Run: julia --project=. examples/multi_panel.jl

using WasmPlot

fig = Figure(size=(900, 600))

# ── Panel 1: Line chart ──
ax1 = Axis(fig[1, 1]; xlabel="x", ylabel="y", title="Line Chart")
x = collect(range(0.0, 4π, 300))
lines!(ax1, x, sin.(x); color=:blue, linewidth=2)
lines!(ax1, x, cos.(x); color=:orange, linewidth=1.5, linestyle=:dash)

# ── Panel 2: Scatter plot ──
ax2 = Axis(fig[1, 2]; xlabel="x", ylabel="y", title="Scatter Plot")
xs = collect(range(0.0, 10.0, 50))
ys = sin.(xs) .+ 0.3 .* randn(50)
scatter!(ax2, xs, ys; color=:purple, markersize=8)

# ── Panel 3: Bar chart ──
ax3 = Axis(fig[2, 1]; xlabel="Category", ylabel="Value", title="Bar Chart")
barplot!(ax3, [1.0, 2.0, 3.0, 4.0, 5.0], [4.2, 7.1, 3.5, 8.9, 5.3]; color=:green)

# ── Panel 4: Multiple series ──
ax4 = Axis(fig[2, 2]; xlabel="t", ylabel="amplitude", title="Multiple Series")
t = collect(range(0.0, 2π, 150))
lines!(ax4, t, sin.(t); linewidth=2)
lines!(ax4, t, sin.(2.0 .* t); linewidth=2)
lines!(ax4, t, sin.(3.0 .* t); linewidth=2)

# Generate HTML
js_glue = WasmPlot.canvas2d_js_glue()
html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>WasmPlot — Multi-Panel Demo</title>
<style>
  body { margin: 0; display: flex; justify-content: center; align-items: center;
         min-height: 100vh; background: #f5f5f4; font-family: system-ui; }
  canvas { border: 1px solid #d4d4d4; border-radius: 8px; background: white;
           box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
</style>
</head>
<body>
<canvas id="plot" width="$(fig.size[1])" height="$(fig.size[2])"></canvas>
<script>
$(js_glue)
var canvas = document.getElementById('plot');
var dpr = window.devicePixelRatio || 1;
canvas.width = $(fig.size[1]) * dpr;
canvas.height = $(fig.size[2]) * dpr;
canvas.style.width = '$(fig.size[1])px';
canvas.style.height = '$(fig.size[2])px';
var ctx = canvas.getContext('2d');
ctx.scale(dpr, dpr);
var c2d = canvas2d_imports(ctx);
$(WasmPlot.generate_js_render(fig))
console.log('[WasmPlot] Multi-panel rendered');
</script>
</body>
</html>
"""

outpath = joinpath(@__DIR__, "multi_panel.html")
write(outpath, html)
println("Generated: $outpath")
