using Flou
using OrdinaryDiffEq
using LinearAlgebra: BLAS

# Progress of ODEsolver
using Logging: global_logger
using TerminalLoggers: TerminalLogger
global_logger(TerminalLogger())

# Header
print_flou_header()

# BLAS threading pool clashes with Julia's one 😢
if Threads.nthreads() > 1
    BLAS.set_num_threads(1)
end

# Discretization
Δt = 1e-4
tf = 1.0
save_steps = 1:100:(Int(round(tf/Δt)) + 1)
solver = ORK256(williamson_condition=false)

std = StdQuad{Float64}((7, 7), GL())
div = SSFVDivOperator(
    ChandrasekharAverage(),
    LxFNumericalFlux(
        StdAverageNumericalFlux(),
        1.0,
    ),
    # 3e-1,
    # MatrixDissipation(
    #     ChandrasekharAverage(),
    #     1.0,
    # ),
    1e-1,
)
numflux = MatrixDissipation(
    ChandrasekharAverage(),
    1.0,
)
# numflux = LxFNumericalFlux(
#     StdAverageNumericalFlux(),
#     1.0,
# )

# mesh = CartesianMesh{2,Float64}((0, 0), (1, 0.5), (11, 5))
mesh = StepMesh{Float64}((0, 0), (3, 1), 0.6, 0.2, ((8, 4), (8, 12), (16, 12)))

equation = EulerEquation{2}(div, 1.4)

M0 = 3.0
a0 = soundvelocity(1.0, 1.0, equation)
Q0 = Flou.vars_prim2cons((1.0, M0 * a0, 0.0, 1.0), equation)
∂Ω = [
    1 => EulerInflowBC(Q0),
    2 => EulerOutflowBC(),
    3 => EulerSlipBC(),
    4 => EulerSlipBC(),
    5 => EulerSlipBC(),
    6 => EulerSlipBC(),
]
DG = DGSEM(mesh, std, equation, ∂Ω, numflux)

Q = StateVector{Float64}(undef, DG.dofhandler, DG.stdvec, nvariables(equation))
for ie in eachelement(mesh)
    for i in eachindex(DG.stdvec[1])
        Q[1][i, :, ie] .= Q0
    end
end

display(DG)
println()

sb = get_save_callback("../results/solution", save_steps)

@info "Starting simulation..."

_, exetime = integrate(Q, DG, solver, tf; save_everystep=false, alias_u0=true,
    adaptive=false, dt=Δt, callback=sb, progress=true, progress_steps=50)

@info "Elapsed time: $(exetime) s"
@info "Time per iteration and DOF: $(exetime / (tf/Δt) / ndofs(DG)) s"
