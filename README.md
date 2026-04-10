<div align="center">

# WasmPlot<span style="color: #b45309">.</span><span style="color: #9333ea">j</span><span style="color: #16a34a">l</span>

### Canvas2D Plotting. Makie API. Compiled to WebAssembly.

A plotting library with Makie-compatible API that compiles to WasmGC via [WasmTarget.jl](https://github.com/GroupTherapyOrg/WasmTarget.jl). All chart logic — layout, ticks, data transforms, rendering — runs as WebAssembly in the browser via Canvas2D imports.

[![CI](https://github.com/GroupTherapyOrg/WasmPlot.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/GroupTherapyOrg/WasmPlot.jl/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)

</div>

## Quick Start

```julia
using WasmPlot

fig = Figure(size=(800, 500))
ax = Axis(fig[1, 1]; xlabel="x", ylabel="y", title="sin & cos")

x = range(0, 2pi, 200)
lines!(ax, x, sin.(x); color=:blue, linewidth=2)
lines!(ax, x, cos.(x); color=:orange, linestyle=:dash)

render!(fig)  # emits Canvas2D draw calls
```

## Plot Types

| Type | Function | Status |
|------|----------|--------|
| Line | `lines!(ax, x, y)` | Solid, dash, dot styles |
| Scatter | `scatter!(ax, x, y)` | Circle markers |
| Bar | `barplot!(ax, x, heights)` | Makie width algorithm |
| Heatmap | `heatmap!(ax, ...)` | Viridis colormap |

## Architecture

```
Julia code (WasmGC)
  Figure → Axis → Plot structs
  compute_viewport, compute_ticks, data_to_pixel
    ↓
  Canvas2D import stubs (21 functions)
    ↓
  JS glue (~30 one-liner wrappers)
    ↓
  Browser Canvas2D (GPU-accelerated)
```

All types compile to WasmGC structs. Verified by 112 tests: 69 unit + 11 WASM compilation + 32 Julia-to-WASM e2e parity.

## Integration with Therapy.jl

WasmPlot is designed for use inside [Therapy.jl](https://github.com/GroupTherapyOrg/Therapy.jl) `@island` components. Canvas2D imports are auto-registered in the compilation pipeline.

## Makie Parity

Everything provided matches Makie defaults: Wong color cycle, axis padding (5%), bar gap (0.2), tick algorithm (1-2-5 rule), markersize (9px diameter), grid/spine styling. See the [parity audit](test/wasm_e2e_test.jl).
