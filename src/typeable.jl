abstract type TypeLevel{T} end
struct TVal{T, Val} <: TypeLevel{T} end
struct TApp{Ret, Fn, Args} <: TypeLevel{Ret} end
struct TCons{T, Hd, Tl} <: TypeLevel{Cons{T}} end
struct TNil{T} <: TypeLevel{Nil{T}} end

function interpret(t::Type{TNil{T}}) where T
    nil(T)
end

function interpret(t::Type{TVal{T, V}}) where {T, V}
    V
end

function interpret(t::Type{TCons{T, Hd, Tl}}) where {T, Hd, Tl}
    tl :: List{T} = from_type(Tl)
    cons(from_type(Hd), tl)
end

function interpret(t::Type{TApp{Ret, Fn, Args}}) where {Fn, Args, Ret}
    args = from_type(Args)
    Fn(args...) :: Ret
end

Base.show(io::IO, t::Type{TypeLevel{T}}) where T = print(io, "TypeLevel{$T}")
Base.show(io::IO, t::Type{<:TypeLevel{T}}) where T = show_repr(io, t)

@trait Typeable{T} begin
    to_type    :: T => Type{<:TypeLevel{T}}
    to_type(x) = TVal{T, x}
    from_type  :: Type{<:TypeLevel{T}} => T
    from_type(t) = interpret(t)

    show_repr :: [IO, Type{<:TypeLevel{T}}] => Nothing
    show_repr(io, t) = begin
        print(io, from_type(t))
    end
end

to_typelist(many) =
    let T = eltype(many)
        foldr(many, init=TNil{T}) do each, prev
            TCons{T, to_type(each), prev}
        end
    end

types_to_typelist(many) =
    let T = eltype(many)
        foldr(many, init=TNil{T}) do each, prev
            TCons{T, each, prev}
        end
    end

# compat
expr2typelevel = to_type

@implement Typeable{L} where {T, L <: List{T}} begin
    to_type(x) = to_typelist(T[x...])
end

@implement Typeable{Expr} begin
    function to_type(x::Expr)
        @when Expr(args...) = x begin
            args = to_typelist(args)
            f  = Expr
            TApp{Expr, f, args}
        @otherwise
            error("impossible")
        end
    end
end


@implement Typeable{Ptr{T}} where T

@implement Typeable{Vector{T}} where T begin
    to_type(xs) = TVal{Vector{T}, to_typelist(xs)}
    from_type(::Type{TVal{Vector{T}, V}}) where V = T[interpret(V)...]
end

@implement Typeable{Set{T}} where T begin
    to_type(xs) = TVal{Set{T}, to_typelist(collect(xs))}
    from_type(::Type{TVal{Set{T}, V}}) where V = Set(T[interpret(V)...])
end

@implement Typeable{Dict{K, V}} where {K, V} begin
    to_type(xs) = TVal{Dict{K, V}, to_typelist(collect(xs))}
    from_type(::Type{TVal{Dict{K, V}, Ps}}) where Ps = Dict{K, V}(interpret(Ps)...)
end

@implement Typeable{Pair{K, V}} where {K, V} begin
    to_type(xs) = TVal{Pair{K, V}, to_typelist(xs)}
    from_type(::Type{TVal{Pair{K, V}, Ps}}) where Ps = Pair{K, V}(interpret(Ps)...)
end

@implement Typeable{LineNumberNode} begin
    function to_type(ln)
        f = LineNumberNode
        args = Any[ln.line, ln.file] |> to_typelist
        TApp{LineNumberNode, f, args}
    end
end

@implement Typeable{QuoteNode} begin
    function to_type(x)
        f = QuoteNode
        args = [x.value] |> to_typelist
        TApp{QuoteNode, f, args}
    end
end

@implement Typeable{Tp} where Tp <: Tuple  begin
    function to_type(x)
        args = collect(x) |> to_typelist
        TApp{Tp, tuple, args}
    end
end

const named_tuple_maker(p...) = (;p...)

@implement Typeable{NamedTuple{Ks, Ts}} where {Ks, Ts} begin
    function to_type(x)
        f = named_tuple_maker
        args = [kv for kv in zip(Ks, values(x))] |> to_typelist
        TApp{NamedTuple{Ks, Ts}, f, args}
    end
end

@implement Typeable{Symbol}
@implement Typeable{T} where T <: Number
@implement Typeable{T} where T <: Type
@implement Typeable{T} where T <: Function
@implement Typeable{Nothing}

@implement Typeable{String} begin
    function to_type(x::String)
        wrapped = Symbol(x) |> to_type
        TVal{String, wrapped}
    end
    function from_type(::Type{TVal{String, V}}) where V
        string(V)
    end
end

using Base.Threads: lock, unlock, SpinLock
const _modules = Module[]
const _lock = SpinLock()
function module_index(m::Module)
    lock(_lock)
    try
        i = findfirst(==(m), _modules)
        if i === nothing
            # TODO: thread safe
            push!(_modules, m)
            i = length(_modules)
        end
        i
    finally
        unlock(_lock)
    end
end

@implement Typeable{Module} begin
    function to_type(x::Module)
        TVal{Module, module_index(x)}
    end
    function from_type(:: Type{TVal{Module, V}}) where V
        _modules[V]
    end
end

@implement Typeable{Val{T}} where T