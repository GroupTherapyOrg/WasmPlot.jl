using Aqua
using Test
using WasmPlot

@testset "Aqua" begin
    Aqua.test_all(WasmPlot)
end
