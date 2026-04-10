module WasmPlot

include("types.jl")
include("canvas2d.jl")
include("layout.jl")
include("render.jl")

# ─── Makie-compatible API ───

# Types
export Figure, Axis, GridPosition
export RGBA, rgba

# Plot functions (! = mutating, adds to existing axis)
export lines!, scatter!, barplot!, heatmap!
# Non-mutating forms (create figure + axis)
export lines, scatter, barplot
export HeatmapPlot

# Axis helpers
export xlims!, ylims!

# Canvas2D stubs (for WASM import registration)
export canvas_begin_path, canvas_move_to, canvas_line_to, canvas_stroke, canvas_fill
export canvas_fill_rect, canvas_clear_rect, canvas_stroke_rect
export canvas_set_stroke_rgb, canvas_set_fill_rgb, canvas_set_fill_rgba
export canvas_set_line_width, canvas_arc, canvas_close_path
export canvas_save, canvas_restore, canvas_set_font_size
export canvas_fill_text_char

# Rendering
export render!

# JS glue
export canvas2d_js_glue, canvas2d_import_specs, generate_js_render

end
