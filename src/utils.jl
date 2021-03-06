function q(ex, module′)
    @switch ex begin
    @case Expr(:macrocall, a, b, args...)  && let new_args = Any[a, b] end ||
          Expr(head, args...) && let new_args = [] end
        for i in eachindex(args)
            @switch args[i] begin
            @case ::LineNumberNode
            @case _
                push!(new_args, q(args[i], module′))
            end
        end
        if length(ex.args) !== length(new_args)
            ex.args = new_args
        end
        nothing
    @case _
    end
    ex
end

macro q(ex)
    esc(Expr(:quote, q(ex, __module__)))
end

macro codegen(ex)
    ex = __module__.eval(ex)
    if DEBUG
        @info macroexpand(__module__, ex)
    end
    __module__.eval(ex)
end

@inline function index(xs, x)
    @inbounds for i = eachindex(xs)
        if xs[i] === x
            return i
        end
    end
    nothing
end

@generated function GEP(a::Ptr{T}, ::Val{s}) where {T, s}
    off = fieldoffset(T, index(fieldnames(T), s))
    R = fieldtype(T, s)
    :(reinterpret(Ptr{$R}, a + $off))
end

function _pointer_access(@nospecialize(ex::Expr))
    @match ex begin
        :($a.$(s::Symbol) :: $A) =>
            :(reinterpret(Ptr{$A}, $GEP($(_pointer_access(a)),  $(Val(s)))))
        :($a.$(s::Symbol)) =>
            :($GEP($(_pointer_access(a)),  $(Val(s))))
        ex =>
            begin
                for i in eachindex(ex.args) 
                    ex.args[i] = _pointer_access(ex.args[i])
                end
                ex
            end
    end
end

_pointer_access(a) = a

macro pointer_access(ex)
    esc(_pointer_access(ex))
end
