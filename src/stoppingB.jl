# A stopping manager for iterative solvers, bound constraints compatible
export TStoppingB, start!, stop

type TResult   # simplified state for bound constrained problems
    x :: Vector  # current iterate
    ∇f :: Vector # current objective gradient
    pg :: Vector # current objective projected gradient
    λ :: Vector  # current Lagrange multipliers
    # etc
end


type TStoppingB <: AbstractStopping
    atol :: Float64                  # absolute tolerance
    rtol :: Float64                  # relative tolerance
    unbounded_threshold :: Float64   # below this value, the problem is declared unbounded
    # fine grain control on ressources
    max_obj_f :: Int                 # max objective function (f) evaluations allowed
    max_obj_grad :: Int              # max objective gradient (g) evaluations allowed
    max_obj_hess :: Int              # max objective hessian (H) evaluations allowed
    max_obj_hv :: Int                # max objective H*v (Hv) evaluations allowed
    # global control on ressources
    max_eval :: Int                  # max evaluations (f+g+H+Hv) allowed
    max_iter :: Int                  # max iterations allowed
    max_time :: Float64              # max elapsed time allowed
    # global information to the stopping manager
    start_time :: Float64            # starting time of the execution of the method
    optimality0 :: Float64           # value of the optimality residual at starting point
    optimality_residual :: Function  # function to compute the optimality residual
    # diagnostic
    elapsed_time :: Float64
    optimal :: Bool
    tired :: Bool
    unbounded :: Bool
    #
    nlp :: AbstractNLPModel
    #
    nlp_at_x :: TResult


    function TStoppingB(nlp :: AbstractNLPModel;
                        atol :: Float64 = 1.0e-8,
                        rtol :: Float64 = 1.0e-6,
                        unbounded_threshold :: Float64 = -1.0e50,
                        max_obj_f :: Int = typemax(Int),
                        max_obj_grad :: Int = typemax(Int),
                        max_obj_hess :: Int = typemax(Int),
                        max_obj_hv :: Int = typemax(Int),
                        max_eval :: Int = 20000,
                        max_iter :: Int = 5000,
                        max_time :: Float64 = 600.0, # 10 minutes
                        optimality_residual :: Function = (s) ->
                        norm(gradproj(s.nlp.meta.uvar,s.nlp.meta.lvar,s.nlp_at_x.∇f,s.nlp_at_x.x),Inf),
                        kwargs...)
        
        return new(atol, rtol, unbounded_threshold,
                   max_obj_f, max_obj_grad, max_obj_hess, max_obj_hv, max_eval,
                   max_iter, max_time, NaN, Inf, optimality_residual, 0.0, false, false, false, nlp,
                   TAbstractResult([],[],[],[]))
    end
end

proj(ub :: Vector, lb :: Vector, x :: Vector) = max.(min.(x,ub),lb)

gradproj(ub :: Vector, lb :: Vector, g::Vector, x :: Vector) =  x - proj(ub, lb, x-g)

function start!(nlp :: AbstractNLPModel,
                s :: TStoppingB,
                x₀ :: Array{Float64,1})
    
    ∇f₀ = grad(nlp,x₀)
    s.start_time  = time()

    s.nlp_at_x.x = x₀
    s.nlp_at_x.∇f = ∇f₀
    
    s.optimality0 = s.optimality_residual(s)
    return s, ∇f₀
end


function stop(nlp :: AbstractNLPModel,
              s :: TStoppingB,
              iter :: Int,
              x :: Vector,
              f :: Float64,
              ∇f :: Vector;
              pg :: Vector = [],
              λ ::  Vector = [])

    calls = [neval_obj(nlp), neval_grad(nlp), neval_hess(nlp), neval_hprod(nlp)]

    s.nlp_at_x.x = x
    s.nlp_at_x.∇f = ∇f
    s.nlp_at_x.pg = pg
    s.nlp_at_x.λ = λ

    optimality = s.optimality_residual(s)

    optimal = (optimality < s.atol) | (optimality <( s.rtol * s.optimality0))
    #optimal = optimality < s.atol +s.rtol*s.optimality0
    unbounded =  f <= s.unbounded_threshold


    # fine grain limits
    max_obj_f  = calls[1] > s.max_obj_f
    max_obj_g  = calls[2] > s.max_obj_grad
    max_obj_H  = calls[3] > s.max_obj_hess
    max_obj_Hv = calls[4] > s.max_obj_hv

    max_total = sum(calls) > s.max_eval

    # global evaluations diagnostic
    max_calls = (max_obj_f) | (max_obj_g) | (max_obj_H) | (max_obj_Hv) | (max_total)

    elapsed_time = time() - s.start_time

    max_iter = iter >= s.max_iter
    max_time = elapsed_time > s.max_time

    # global user limit diagnostic
    tired = (max_iter) | (max_calls) | (max_time)


    # return everything. Most users will use only the first four fields, but return
    # the fine grained information nevertheless.

    #return (optimal || unbounded || tired), elapsed_time

    return optimal, unbounded, tired, elapsed_time,
           max_obj_f, max_obj_g, max_obj_H, max_obj_Hv, max_total, max_iter, max_time
end
