struct RuntimeFn{Args, Kwargs, Body} end
struct Unset end

@implement Typeable{RuntimeFn{Args, Kwargs, Body}} where {Args, Kwargs, Body}


struct Argument
    name    :: Symbol
    type    :: Union{Nothing, Any}
    default :: Union{Unset,  Any}
end

struct Arguments
    args   :: Vector{Argument}
    kwargs :: Vector{Argument}
end

@implement Typeable{Unset}

@implement Typeable{Argument} begin
    to_type(arg) =
        let f = Argument
            args = [arg.name, arg.type, arg.default] |> to_typelist
            TApp{Argument, f, args}
        end
end

function _ass_positional_args!(assign_block::Vector{Expr}, args :: List{Argument}, ninput::Int, pargs :: Symbol)
    i = 1
    for arg in args
        ass = arg.name
        if arg.type !== nothing
            ass = :($ass :: $(arg.type))
        end
        if i > ninput
            arg.default === Unset() && error("Input arguments too few.")
            ass = :($ass = $(arg.default))
        else
            ass = :($ass = $pargs[$i])
        end
        push!(assign_block, ass)
        i += 1
    end
end

@generated function (::RuntimeFn{Args, TNil{Argument}, Body})(pargs...) where {Args, Body}
    args   = interpret(Args)
    ninput = length(pargs)
    assign_block = Expr[]
    body = interpret(Body)
    _ass_positional_args!(assign_block, args, ninput, :pargs)
    quote
        let $(assign_block...)
            $body
        end
    end
end

@generated function (::RuntimeFn{Args, Kwargs, Body})(pargs...; pkwargs...) where {Args, Kwargs, Body}
    args   = interpret(Args)
    kwargs = interpret(Kwargs)
    ninput = length(pargs)
    assign_block = Expr[]
    body = interpret(Body)
    if isempty(kwargs)
        _ass_positional_args!(assign_block, args, ninput, :pargs)
    else
        function get_kwds(::Type{Base.Iterators.Pairs{A, B, C, NamedTuple{Kwds,D}}}) where {Kwds, A, B, C, D}
            Kwds
        end
        kwds = gensym("kwds")
        feed_in_kwds = get_kwds(pkwargs)
        push!(assign_block, :($kwds = pkwargs))
        _ass_positional_args!(assign_block, args, ninput, :pargs)
        for kwarg in kwargs
            ass = k = kwarg.name
            if kwarg.type !== nothing
                ass = :($ass :: $(kwarg.type))
            end
            if k in feed_in_kwds
                ass = :($ass = $kwds[$(QuoteNode(k))])
            else
                default = kwarg.default
                default === Unset() && error("no default value for keyword argument $(k)")
                ass = :($ass = $default)
            end
            push!(assign_block, ass)
        end
    end
    quote
        let $(assign_block...)
            $body
        end
    end
end