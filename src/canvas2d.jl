# canvas2d.jl — Canvas2D import stubs + JS glue
#
# Pattern B from the research: WASM calls Canvas2D directly via imports.
# Each stub is a no-op in Julia. When compiled to WASM, WasmTarget's
# func_registry maps them to WASM imports. JS provides the implementations.
#
# Design decisions:
# - No ctx parameter: JS captures the Canvas2D context in a closure.
#   This avoids externref complexity for the MWE.
# - All coords are Float64 (f64 in WASM — pass as regular JS numbers).
# - Colors as 3×Float64 (0–255 range) — avoids string passing.
# - Return Int64 to match Therapy.jl's import pattern (0n in JS).
# - @noinline prevents inlining; optimize=false in WasmTarget prevents DCE.
#
# Matches: plotters-rs CanvasBackend, AssemblyScript canvas-api pattern.

# ─── Path operations ───
@noinline canvas_begin_path()::Int64 = Int64(0)
@noinline canvas_close_path()::Int64 = Int64(0)
@noinline canvas_move_to(x::Float64, y::Float64)::Int64 = Int64(0)
@noinline canvas_line_to(x::Float64, y::Float64)::Int64 = Int64(0)
@noinline canvas_arc(x::Float64, y::Float64, r::Float64, start_angle::Float64, end_angle::Float64)::Int64 = Int64(0)

# ─── Drawing ───
@noinline canvas_stroke()::Int64 = Int64(0)
@noinline canvas_fill()::Int64 = Int64(0)
@noinline canvas_fill_rect(x::Float64, y::Float64, w::Float64, h::Float64)::Int64 = Int64(0)
@noinline canvas_clear_rect(x::Float64, y::Float64, w::Float64, h::Float64)::Int64 = Int64(0)
@noinline canvas_stroke_rect(x::Float64, y::Float64, w::Float64, h::Float64)::Int64 = Int64(0)

# ─── Style ───
@noinline canvas_set_stroke_rgb(r::Float64, g::Float64, b::Float64)::Int64 = Int64(0)
@noinline canvas_set_fill_rgb(r::Float64, g::Float64, b::Float64)::Int64 = Int64(0)
@noinline canvas_set_fill_rgba(r::Float64, g::Float64, b::Float64, a::Float64)::Int64 = Int64(0)
@noinline canvas_set_line_width(w::Float64)::Int64 = Int64(0)
@noinline canvas_set_font_size(size::Float64)::Int64 = Int64(0)

# ─── Text (single ASCII char — avoids string passing for v0.1) ───
# char_code is the ASCII code point (e.g., 48 for '0', 65 for 'A')
@noinline canvas_fill_text_char(char_code::Float64, x::Float64, y::Float64)::Int64 = Int64(0)

# ─── State ───
@noinline canvas_save()::Int64 = Int64(0)
@noinline canvas_restore()::Int64 = Int64(0)

# ─── Dash pattern (for linestyle support) ───
@noinline canvas_set_line_dash_solid()::Int64 = Int64(0)       # []
@noinline canvas_set_line_dash_dashed()::Int64 = Int64(0)      # [6, 4]
@noinline canvas_set_line_dash_dotted()::Int64 = Int64(0)      # [2, 3]

# ─── All stubs collected for import registration ───

const CANVAS2D_STUBS = [
    # (julia_func, import_name, arg_types, return_type)
    (canvas_begin_path,        "begin_path",        (),                                 Int64),
    (canvas_close_path,        "close_path",        (),                                 Int64),
    (canvas_move_to,           "move_to",           (Float64, Float64),                 Int64),
    (canvas_line_to,           "line_to",           (Float64, Float64),                 Int64),
    (canvas_arc,               "arc",               (Float64, Float64, Float64, Float64, Float64), Int64),
    (canvas_stroke,            "stroke",            (),                                 Int64),
    (canvas_fill,              "fill",              (),                                 Int64),
    (canvas_fill_rect,         "fill_rect",         (Float64, Float64, Float64, Float64), Int64),
    (canvas_clear_rect,        "clear_rect",        (Float64, Float64, Float64, Float64), Int64),
    (canvas_stroke_rect,       "stroke_rect",       (Float64, Float64, Float64, Float64), Int64),
    (canvas_set_stroke_rgb,    "set_stroke_rgb",    (Float64, Float64, Float64),        Int64),
    (canvas_set_fill_rgb,      "set_fill_rgb",      (Float64, Float64, Float64),        Int64),
    (canvas_set_fill_rgba,     "set_fill_rgba",     (Float64, Float64, Float64, Float64), Int64),
    (canvas_set_line_width,    "set_line_width",    (Float64,),                         Int64),
    (canvas_set_font_size,     "set_font_size",     (Float64,),                         Int64),
    (canvas_fill_text_char,    "fill_text_char",    (Float64, Float64, Float64),        Int64),
    (canvas_save,              "save",              (),                                 Int64),
    (canvas_restore,           "restore",           (),                                 Int64),
    (canvas_set_line_dash_solid,  "set_line_dash_solid",  (),                           Int64),
    (canvas_set_line_dash_dashed, "set_line_dash_dashed", (),                           Int64),
    (canvas_set_line_dash_dotted, "set_line_dash_dotted", (),                           Int64),
]

# ─── WASM import specs (for WasmTarget integration) ───

"""
    canvas2d_import_specs() -> Vector{NamedTuple}

Returns import specifications for WasmTarget.add_import!().
Each entry has: name, param_types (as WASM type symbols), return_type.
"""
function canvas2d_import_specs()
    specs = NamedTuple[]
    for (func, name, arg_types, ret) in CANVAS2D_STUBS
        wasm_params = Symbol[]
        for T in arg_types
            push!(wasm_params, T === Float64 ? :F64 : :I64)
        end
        wasm_ret = ret === Float64 ? :F64 : :I64
        push!(specs, (name=name, func=func, params=wasm_params, ret=wasm_ret, arg_types=arg_types, return_type=ret))
    end
    return specs
end

# ─── JS glue generation ───

"""
    canvas2d_js_glue() -> String

Generate the JavaScript import object for Canvas2D WASM imports.
The returned code defines a `canvas2d_imports(ctx)` function that takes
a CanvasRenderingContext2D and returns the WASM import object.

All functions return 0n (BigInt zero) to match i64 return convention.
"""
function canvas2d_js_glue()::String
    return """
function canvas2d_imports(ctx) {
  return {
    begin_path:        function()       { ctx.beginPath(); return 0n; },
    close_path:        function()       { ctx.closePath(); return 0n; },
    move_to:           function(x, y)   { ctx.moveTo(x, y); return 0n; },
    line_to:           function(x, y)   { ctx.lineTo(x, y); return 0n; },
    arc:               function(x,y,r,sa,ea) { ctx.arc(x, y, r, sa, ea); return 0n; },
    stroke:            function()       { ctx.stroke(); return 0n; },
    fill:              function()       { ctx.fill(); return 0n; },
    fill_rect:         function(x,y,w,h){ ctx.fillRect(x, y, w, h); return 0n; },
    clear_rect:        function(x,y,w,h){ ctx.clearRect(x, y, w, h); return 0n; },
    stroke_rect:       function(x,y,w,h){ ctx.strokeRect(x, y, w, h); return 0n; },
    set_stroke_rgb:    function(r,g,b)  { ctx.strokeStyle='rgb('+r+','+g+','+b+')'; return 0n; },
    set_fill_rgb:      function(r,g,b)  { ctx.fillStyle='rgb('+r+','+g+','+b+')'; return 0n; },
    set_fill_rgba:     function(r,g,b,a){ ctx.fillStyle='rgba('+r+','+g+','+b+','+a+')'; return 0n; },
    set_line_width:    function(w)      { ctx.lineWidth = w; return 0n; },
    set_font_size:     function(s)      { ctx.font = s+'px sans-serif'; return 0n; },
    fill_text_char:    function(c,x,y)  { ctx.fillText(String.fromCharCode(c), x, y); return 0n; },
    save:              function()       { ctx.save(); return 0n; },
    restore:           function()       { ctx.restore(); return 0n; },
    set_line_dash_solid:  function()    { ctx.setLineDash([]); return 0n; },
    set_line_dash_dashed: function()    { ctx.setLineDash([6,4]); return 0n; },
    set_line_dash_dotted: function()    { ctx.setLineDash([2,3]); return 0n; },
  };
}"""
end
