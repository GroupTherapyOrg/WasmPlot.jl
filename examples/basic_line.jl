# basic_line.jl — WasmPlot MWE
#
# Demonstrates Makie-compatible API rendering to Canvas2D.
# Run: julia --project=. examples/basic_line.jl
#
# This generates an HTML file that uses JavaScript to verify the rendering
# pipeline works correctly. When compiled to WASM, the same render!() calls
# become real Canvas2D operations.

using WasmPlot

# ─── Create a figure with Makie-compatible API ───

fig = Figure(size=(800, 500), backgroundcolor=:white)

# Single axis
ax = Axis(fig[1, 1];
    xlabel = "x",
    ylabel = "y",
    title = "WasmPlot: sin & cos"
)

# Generate data
x = collect(range(0.0, 2π, 200))
y_sin = sin.(x)
y_cos = cos.(x)

# Plot (same API as Makie)
lines!(ax, x, y_sin; color=:blue, linewidth=2, label="sin(x)")
lines!(ax, x, y_cos; color=:orange, linewidth=2, linestyle=:dash, label="cos(x)")

# ─── Generate standalone HTML for testing ───

js_glue = WasmPlot.canvas2d_js_glue()

# Build a JS version of the render calls for verification
# (In production, render!() compiles to WASM — this is the testing path)
html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>WasmPlot MWE — Canvas2D Rendering</title>
<style>
  body { margin: 0; display: flex; justify-content: center; align-items: center;
         min-height: 100vh; background: #f5f5f4; font-family: system-ui; }
  canvas { border: 1px solid #d4d4d4; border-radius: 8px; background: white;
           box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
  .info { position: fixed; top: 16px; left: 16px; font-size: 13px; color: #78716c; }
</style>
</head>
<body>
<div class="info">WasmPlot.jl — Canvas2D rendering MWE<br>
This is the JS reference renderer. Same calls will run as WASM imports.</div>
<canvas id="plot" width="$(fig.size[1])" height="$(fig.size[2])"></canvas>
<script>
$(js_glue)

// Get the Canvas2D context
var canvas = document.getElementById('plot');
// HiDPI support
var dpr = window.devicePixelRatio || 1;
canvas.width = $(fig.size[1]) * dpr;
canvas.height = $(fig.size[2]) * dpr;
canvas.style.width = '$(fig.size[1])px';
canvas.style.height = '$(fig.size[2])px';
var ctx = canvas.getContext('2d');
ctx.scale(dpr, dpr);

// Create the import object (same as what WASM would receive)
var c2d = canvas2d_imports(ctx);

// Execute the same sequence of Canvas2D calls that render!() would emit.
// In WASM, these are import calls. Here, we call the JS glue directly.
$(generate_js_render(fig))

console.log('[WasmPlot] Rendered successfully via Canvas2D');
</script>
</body>
</html>
"""

outpath = joinpath(@__DIR__, "basic_line.html")
write(outpath, html)
println("Generated: $outpath")
println("Open in browser to see the Canvas2D rendered chart.")
