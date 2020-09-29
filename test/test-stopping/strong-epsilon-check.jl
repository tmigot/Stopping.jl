###############################################################################
#
# The Stopping structure eases the implementation of algorithms and the
# stopping criterion.
# We illustrate here the basic features of Stopping.
#
# -> the case where the score is a Vector and not a Number.
# a) tol_check is a Number;
# b) tol_check is a Vector of the same size.
# Note that if tol_check is a Vector and the score is a Number, only
# the smallest value of tol_check is considered.
#
#
###############################################################################

#We consider a regularized MPCC problem:
x0 = ones(2)
t  = 1.0
c(x) = [(x[1] - t) .* (x[2] - t)]
nlp = ADNLPModel(x -> x[1]+x[2],  x0,
                 lvar = zeros(2), uvar = Inf*ones(2),
                 y0 = zeros(1), c = c, lcon = -Inf*ones(1), ucon = zeros(1))

#We consider a vectorized optimality_check KKT function:
function KKTvect(pb    :: AbstractNLPModel,
                 state :: NLPAtX;
                 kwargs...)

    #Check the gradient of the Lagrangian
    gLagx      = Main.Stopping._grad_lagrangian(pb, state)
    #Check the complementarity condition for the bounds
    dual_res_bounds = Main.Stopping._sign_multipliers_bounds(pb, state)
    #Check the complementarity condition for the constraints
    res_nonlin = Main.Stopping._sign_multipliers_nonlin(pb, state)
    #Check the feasibility
    feas       = Main.Stopping._feasibility(pb, state)

    res = vcat(gLagx, feas, dual_res_bounds, res_nonlin)

    return res
end

#One solution is [1.0, 0.0] while [1. + 1e-7, 0] is an approximate solution.
sol  = [1.0, 0.0]
esol = [1.0 + 1e-7, 0.0]

#As usual, we initialize the State and the Stopping
nlp_at_x_c = NLPAtX(x0, NaN*ones(nlp.meta.ncon))
stop_nlp = NLPStopping(nlp, nlp_at_x_c, optimality_check = KKTvect)
fill_in!(stop_nlp, x0)
OK = stop!(stop_nlp)
@test !OK #the initial guess (1.0, 1.0) is not a solution
reinit!(stop_nlp, rstate = true) #reinitialize the Stopping and the State
fill_in!(stop_nlp, sol)
OK = stop!(stop_nlp)
@test OK #sol is a solution
reinit!(stop_nlp, rstate = true)
fill_in!(stop_nlp, esol)
OK = stop!(stop_nlp)
@test OK #esol is also an (approximate) solution.
#KKTvect(stop_nlp.pb, stop_nlp.current_state)

#Our aim is to verify that a solution satisfies the strong epsilon-stationarity
#condition, i.e. the feasibility and the complementarity condition have to be
#satisfied exactly.
tol_check1(atol,rtol,opt0) = vcat(max(atol,rtol*opt0) .* ones(6), zeros(8))

stop_nlp = NLPStopping(nlp, nlp_at_x_c, optimality_check = KKTvect, tol_check = tol_check1)
fill_in!(stop_nlp, esol)
OK = stop!(stop_nlp)
@test !OK #esol is not a solution in this case as it satisfies the feasibility approximately
reinit!(stop_nlp, rstate = true) #reinitialize the Stopping and the State
fill_in!(stop_nlp, sol)
OK = stop!(stop_nlp)
@test OK #However, sol is a solution.

#Finally, let us comment on the case where the optimality_check returns a number:
stop_nlp = NLPStopping(nlp, nlp_at_x_c, optimality_check = KKT, tol_check = tol_check1)
fill_in!(stop_nlp, esol)
OK = stop!(stop_nlp)
@test !OK #esol is not a solution as the score returned by KKT is not smaller than minimum(tol_check)