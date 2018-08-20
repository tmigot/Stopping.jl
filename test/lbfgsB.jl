#export lbfgsB
using LinearOperators



function lbfgsB(nlp :: AbstractNLPModel;
                #stp :: AbstractStopping=TStoppingB(),
                stp :: TStoppingB=TStoppingB(),
                verbose :: Bool=false,
                verboseLS :: Bool = false,
                mem :: Int=5,#######
                scaling :: Bool = true,
                scaleK :: Float64 = 200000.0, 
                β :: Float64 = 0.15,
                kwargs...)
    
    print_h=false
    x = copy(nlp.meta.x0)
    n = nlp.meta.nvar

    lb = nlp.meta.lvar
    ub = nlp.meta.uvar
    
    # project initial point in case of infeasibility
    x = proj(ub, lb, x)

    xt = Array{Float64}(n)
    ∇ft = Array{Float64}(n)
    pg = Array{Float64}(n)

    f = obj(nlp, x)
    H = InverseLBFGSOperator(n, mem, scaling=scaling)########

    iter = 0

    #∇f = grad(nlp, x)
    stp, ∇f = start!(stp,x)
    ∇fNorm = BLAS.nrm2(n, ∇f, 1)

    verbose && @printf("%4s  %8s  %7s  %8s  %4s\n", "iter", "f", "‖∇f‖", "∇f'd", "bk")
    verbose && @printf("%4d  %8.1e  %7.1e", iter, f, ∇fNorm)

    stopped = stop(stp, iter, x, f, ∇f)
    OK = true
    
    stalled_linesearch = false;
    bk_max = 300

    τ₀ = 1.0e-4
    stalled_ascent_dir = false

    d = zeros(∇f)
    h = LineModel(nlp, x, d)

    while (OK && !stopped)
        # set up for an ϵ-active bounds
        pg = gradproj(ub, lb, ∇f, x)
        ϵ = min( minimum(ub - lb)/scaleK ,  norm(pg))
        #Auϵ = find((ub - x) .<= ϵ)
        #Alϵ = find((x - lb) .<= ϵ)
        #Aϵ = (Auϵ ∪ Alϵ)
        #Iϵ = setdiff(1:n,  Aϵ)

        Aϵ = find(((ub - x) .<= ϵ) .|((x - lb) .<= ϵ))
        Iϵ = find(((ub - x) .> ϵ) .&((x - lb) .> ϵ))
        # Compute the scaled projection on I
        d[Iϵ] = - lbfgs_multiply(H.data, ∇f, Iϵ)
        d[Aϵ] = - ∇f[Aϵ]

        #d = -∇f
        
        slope = ∇f[Iϵ]⋅d[Iϵ]
        if slope > 0.0
            #stalled_ascent_dir =true
            reset!(H);
            verbose && @printf("reset since slope  %8.1e  >0", slope)
        else
            # Perform piecewise linesearch.
            #
            #  TO BE REPLACED by an efficient projected line search
            #
            nbk = 0
            t = 1.0
            xt = proj(ub, lb, x+t*d)
            #verbose && @printf(" recomp f = %8.1e \n", obj(nlp,x))
            ft = obj(nlp, xt)
            while ( ft  > (f + τ₀*∇f⋅(xt - x)) ) && (nbk < bk_max)
                #verbose && @printf(" it =  %4d  ft = %8.1e  f = %8.1e \n", nbk,ft,f)
                t *= β
                xt = proj(ub, lb, x+t*d)
                ft = obj(nlp, xt)
                nbk += 1
            end
            stalled_linesearch = (nbk == bk_max)
            
            verbose && @printf("  %4d\n", nbk)
            
            ∇ft = grad!(nlp, xt, ∇ft)

            sk = xt - x
            yk = ∇ft - ∇f
            
            # Update L-BFGS approximation.
            push!(H, sk, yk)
            
            # Move on.
            x = xt
            f = ft
            BLAS.blascopy!(n, ∇ft, 1, ∇f, 1)
            pg = gradproj(ub,lb,∇ft,x)
            ∇fNorm =norm(pg)
            iter += 1
            
            verbose && @printf("%4d  %8.1e  %7.1e", iter, f, ∇fNorm)
           
            stopped = stop(stp, iter, x, f, ∇f)
            #optimal, unbounded, tired, elapsed_time = stop(nlp, stp, iter, x, f, ∇f, pg = pg)
            #optimal, unbounded, tired, elapsed_time = stop(nlp,stp,iter,x,f,pg)

        end
        OK =  !stalled_linesearch & !stalled_ascent_dir 
    end
    verbose && @printf("\n")
    
    if stp.optimal            status = :Optimal
    elseif stp.unbounded      status = :Unbounded
    elseif stalled_linesearch status = :StalledLinesearch
    elseif stalled_ascent_dir status = :StalledAscentDir
    elseif stp.stalled        status = :Stalled
    elseif stp.unfeasible     status = :Unfeasible
    else                      status = :UserLimit
    end

    Au0 = find((ub - x) .<= 0)
    Al0 = find((x - lb) .<= 0)
    A0 = (Au0 ∪ Al0)
    I0 = setdiff(1:n,  A0)

    println("#I0 = ", length(I0), " #A0 = ", length(A0)) 
    
    return (x, f, stp.optimality_residual(stp), iter, stp.optimal, stp.tired, status, stp.elapsed_time)
    #return (x, f, stp.optimality_residual(pg), iter, optimal, tired, status, elapsed_time)
end




proj(ub :: Vector, lb :: Vector, x :: Vector) = max.(min.(x,ub),lb)

gradproj(ub :: Vector, lb :: Vector, g::Vector, x :: Vector) =  x - proj(ub, lb, x-g)

function lbfgs_multiply(data, x :: Array, Iϵ)
    # Multiply operator[Iϵ,Iϵ] with a vector.
    # See, e.g., Nocedal & Wright, 2nd ed., Procedure 7.4, p. 178.
    #
    # For inactive components.

    ys = copy(data.ys)
    q = copy(x)
    #q =  @view qF[Iϵ]   #   bug in view? got inacurate results using this q

    s = @view data.s[Iϵ,:]
    y = @view data.y[Iϵ,:]
    for i = 1 : data.mem
        k = mod(data.insert - i - 1, data.mem) + 1
        #ys[k] = dot(data.y[Iϵ,k], data.s[Iϵ,k])
        ys[k] = dot(y[:,k], s[:,k])
        if ys[k] != 0
            #data.α[k] = dot(data.s[Iϵ,k], q[Iϵ]) / ys[k]
            data.α[k] = dot(s[:,k], q[Iϵ]) / ys[k]
            #q[Iϵ] -= data.α[k] * data.y[Iϵ,k]
            q[Iϵ] -= data.α[k] * y[:,k]
        end
    end
    
    k = mod(data.insert - 2, data.mem) + 1
    if ys[k] != 0
        #scaling_factor = ys[k] / dot(data.y[Iϵ,k], data.y[Iϵ,k])
         scaling_factor = ys[k] / dot(y[:,k], y[:,k])
        #data.scaling && (q[Iϵ] *= scaling_factor)
         data.scaling && (q[Iϵ] *= scaling_factor)
    end
    
    for i = 1 : data.mem
        k = mod(data.insert + i - 2, data.mem) + 1
        if ys[k] != 0
            #β = dot(data.y[Iϵ,k], q[Iϵ]) / ys[k]
             β = dot(y[:,k], q[Iϵ]) / ys[k]
            #q[Iϵ] += (data.α[k] - β) * data.s[Iϵ,k]
             q[Iϵ] += (data.α[k] - β) * s[:,k]
        end
    end
    
    return q[Iϵ]
    #return q
end
