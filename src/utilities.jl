
#
# Utilties.
#

#
# Method grouping.
#

"""
Group all methods of function `func` with type signatures `typesig` in module `modname`.

$(:signatures)

Keyword argument `exact = true` matches signatures "exactly" with `==` rather than `<:`.

# Examples

```julia
groups = methodgroups(f, Union{Tuple{Any}, Tuple{Any, Integer}}, Main; exact = false)
```

$(:methodlist)
"""
function methodgroups(func, typesig, modname; exact = true)
    # Group methods by file and line number.
    local methods = getmethods(func, typesig)
    local groups = groupby(Tuple{Symbol, Int}, Vector{Method}, methods) do m
        (m.file, m.line), m
    end

    # Filter out methods from other modules and with non-matching signatures.
    local typesigs = alltypesigs(typesig)
    local results = Vector{Method}[]
    for (key, group) in groups
        filter!(group) do m
            local ismod = m.module == modname
            exact ? (ismod && Base.tuple_type_tail(m.sig) in typesigs) : ismod
        end
        isempty(group) || push!(results, group)
    end

    # Sort the groups by file and line.
    local sorter = function(a, b)
        comp = a.file < b.file ? -1 : a.file > b.file ? 1 : 0
        comp == 0 ? a.line < b.line : comp < 0
    end
    sort!(results, lt = sorter, by = first)

    return results
end

"""
$(:signatures)

A helper method for [`getmethods`](@ref) that collects methods in `results`.
"""
function getmethods!(results, f, sig)
    if sig == Union{}
        append!(results, methods(f))
    elseif isa(sig, Union)
        for each in sig.types
            append!(results, getmethods(f, each))
        end
    else
        append!(results, methods(f, sig))
    end
    return results
end
"""
Collect and return all methods of function `f` matching signature `sig`.

$(:signatures)

This is similar to `methods(f, sig)`, but handles type signatures found in `DocStr` objects
more consistently that `methods`.
"""
getmethods(f, sig) = getmethods!(Method[], f, sig)

"""
$(:signatures)

Returns a `SimpleVector` of the `Tuple` types contained in `sig`.
"""
alltypesigs(sig) = isa(sig, Union) ? sig.types : Core.svec(sig)

"""
$(:signatures)

A helper method for [`groupby`](@ref) that uses a pre-allocated `groups` `Dict`.
"""
function groupby!(f, groups, data)
    for each in data
        key, value = f(each)
        push!(get!(groups, key, []), value)
    end
    return sort!(collect(groups), by = first)
end

"""
Group `data` using function `f` where key type is specified by `K` and group type by `V`.

$(:signatures)

The function `f` takes a single argument, an element of `data`, and should return a 2-tuple
of `(computed_key, element)`. See the example below for details.

# Examples

```julia
groupby(Int, Vector{Int}, collect(1:10)) do num
    mod(num, 3), num
end
```
"""
groupby(f, K, V, data) = groupby!(f, Dict{K, V}(), data)

"""
$(:signatures)

Remove the `Pkg.dir` part of a file `path` if it exists.
"""
function cleanpath(path::AbstractString)
    local pkgdir = joinpath(Pkg.dir(), "")
    return startswith(path, pkgdir) ? first(split(path, pkgdir; keep = false)) : path
end

"""
Parse all docstrings defined within a module `mod`.

$(:signatures)
"""
function parsedocs(mod::Module)
    for (binding, multidoc) in Docs.meta(mod)
        for (typesig, docstr) in multidoc.docs
            Docs.parsedoc(docstr)
        end
    end
end


"""
Print a simplified representation of a method signature to `buffer`.

$(:signatures)

Simplifications include:

  * no `TypeVar`s;
  * no types;
  * no keyword default values;
  * `?` printed where `#unused#` arguments are found.

# Examples

```julia
f(x; a = 1, b...) = x
sig = printmethod(Docs.Binding(Main, :f), f, first(methods(f)))
```
"""
function printmethod(buffer::IOBuffer, binding::Docs.Binding, func, method::Method)
    # TODO: print qualified?
    print(buffer, binding.var)
    print(buffer, "(")
    join(buffer, arguments(method), ", ")
    local kws = keywords(func, method)
    if !isempty(kws)
        print(buffer, "; ")
        join(buffer, kws, ", ")
    end
    print(buffer, ")")
    return buffer
end

printmethod(b, f, m) = takebuf_string(printmethod(IOBuffer(), b, f, m))


"""
Returns the list of keywords for a particular method `m` of a function `func`.

$(:signatures)

# Examples

```julia
f(x; a = 1, b...) = x
kws = keywords(f, first(methods(f)))
```
"""
function keywords(func, m::Method)
    local table = methods(func).mt
    if isdefined(table, :kwsorter)
        local kwsorter = table.kwsorter
        local signature = Base.tuple_type_cons(Vector{Any}, m.sig)
        if method_exists(kwsorter, signature)
            local method = which(kwsorter, signature)
            if isdefined(method, :lambda_template)
                local template = method.lambda_template
                # `.slotnames` is a `Vector{Any}`. Convert it to the right type.
                local args = map(Symbol, template.slotnames[(template.nargs + 1):end])
                # Only return the usable symbols, not ones that aren't identifiers.
                filter!(arg -> !contains(string(arg), "#"), args)
                # Keywords *may* not be sorted correctly. We move the vararg one to the end.
                local index = findfirst(arg -> endswith(string(arg), "..."), args)
                if index > 0
                    args[index], args[end] = args[end], args[index]
                end
                return args
            end
        end
    end
    return Symbol[]
end


"""
Returns the list of arguments for a particular method `m`.

$(:signatures)

# Examples

```julia
f(x; a = 1, b...) = x
args = arguments(first(methods(f)))
```
"""
function arguments(m::Method)
    if isdefined(m, :lambda_template)
        local template = m.lambda_template
        if isdefined(template, :slotnames)
            local args = map(template.slotnames[1:template.nargs]) do arg
                arg === Symbol("#unused#") ? "?" : arg
            end
            return filter(arg -> arg !== Symbol("#self#"), args)
        end
    end
    return Symbol[]
end

