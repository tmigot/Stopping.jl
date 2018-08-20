using Stopping
#include("../src/Stopping.jl")
using Base.Test

# write your own tests here
using NLPModels
using JuMP


include("CUTEstProblemsB.jl")
probs = open(readlines,"CUTEstBound.list")


include("line_model.jl")  # For LineFunction  definition
#include("woods.jl")
#nlp = MathProgNLPModel(woods(), name="woods")
#include("genrose.jl")
#nlp = MathProgNLPModel(genrose(800), name="genrose")

#nlp = CUTEstModel(probs[6])




# bounded
using LSDescentMethods
#include("lbfgsB.jl")

test_probs = (CUTEstModel(p)  for p in probs)

#for nlp in test_probs
#nlp = CUTEstModel("MINSURFO")
nlp = CUTEstModel("ALLINIT")
    n = nlp.meta.nvar

    sB = TStopping(atol=1.0e-6, rtol = 0.0, max_eval = 100000, max_iter = 10000, max_time = 10.0)


    (x, f, gNorm, iter, optimal, tired, status, Stime) = lbfgsB(nlp, stp=sB, verbose=false, mem = 5, scaling = true)


    @printf("%-5s  %3d  %9.2e  %7.1e  %5d  %5d  %6d   %6d  %-20s  %7.3e\n",
            nlp.meta.name, nlp.meta.nvar, f, gNorm,
            nlp.counters.neval_obj, nlp.counters.neval_grad,
            nlp.counters.neval_hprod, iter, status, Stime) 
        
    #@test status == :Optimal
    
    reset!(nlp)
    
    (x, f, gNorm, iter, optimal, tired, status, Stime) = lbfgsB(nlp, stp=sB, verbose=false, mem = 5, scaling = true, β = 0.5,scaleK = 10.0)


    @printf("%-5s  %3d  %9.2e  %7.1e  %5d  %5d  %6d   %6d  %-20s  %7.3e\n",
            nlp.meta.name, nlp.meta.nvar, f, gNorm,
            nlp.counters.neval_obj, nlp.counters.neval_grad,
            nlp.counters.neval_hprod, iter, status, Stime) 
        
    #@test status == :Optimal
    
    reset!(nlp)




    using Lbfgsb
    solver = LbfgsBS
    
    #stp = TStoppingB(-Inf*ones(n),Inf*ones(n),atol=1.0e-7, rtol = 0.0, max_eval = 100000, max_iter = 10000, max_time = 4.0)
    
    xb, fb, residb, iterBb, optimalb, tiredb, statusb, elapsed_timeb = solver(nlp, verbose = false, stp = sB, m = 5)
    
    @printf("%-5s  %3d  %9.2e  %7.1e  %5d  %5d  %6d   %6d  %-20s  %7.3e\n",
            nlp.meta.name, nlp.meta.nvar, fb, residb,
            nlp.counters.neval_obj, nlp.counters.neval_grad,
            nlp.counters.neval_hprod, iterBb, statusb,  elapsed_timeb) 

    println("\n")
    
    finalize(nlp)
#end
