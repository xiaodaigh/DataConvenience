module DataConvenience

import WeakRefStrings:StringVector
using DataFrames: categorical, AbstractDataFrame, DataFrame, names!
using CategoricalArrays
using Statistics
using Missings:nonmissingtype
using RCall

import Statistics:cor
export cor, dfcor, @replicate, StringVector
export cleannames!

"""
    cleannames!(df::DataFrame)

Uses R's `janitor::clean_names` to clean the names
"""
function cleannames!(df::AbstractDataFrame)
    rdf = DataFrame(df[1, :])
    @rput rdf
    R"""
    new_names = names(janitor::clean_names(rdf))
    """
    @rget new_names
    if new_names isa AbstractVector
        names!(df, Symbol.(new_names))
    else # must be singular
        names!(df, [Symbol(new_names)])
    end
end

# head(df::AbstractDataFrame) = first(df, 10)
#
# tail(df::AbstractDataFrame) = last(df, 10)
"""
    @replicate n expr

Replicate the expression `n` times

## Example
```julia
using DataConvenience, Random
@replicate 10 randstring(8) # returns 10 random length 8 strings
```
"""
macro replicate(n, expr)
    :([$(esc(expr)) for i=1:$(esc(n))])
end

"""
    StringVector(v::CategoricalVector{String})

Convert `v::CategoricalVector` efficiently to WeakRefStrings.StringVector

## Example
```julia
using DataFrames
a  = categorical(["a","c", "a"])
a.refs
a.pool.index

# efficiently convert
sa = StringVector(a)

sa.buffer
sa.lengths
sa.offsets
```
"""
StringVector(v::CategoricalVector{S}) where S<:AbstractString = begin
    sa = StringVector(v.pool.index)
    StringVector{S}(sa.buffer, sa.offsets[v.refs], sa.lengths[v.refs])
end


"""
    cor(x::AbstractVector{Bool}, y)

    cor(y, x::AbstractVector{Bool})

Compute correlation between `Bool` and other types
"""
Statistics.cor(x::AbstractVector{Bool}, y::AbstractVector) = cor(y, Int.(x))
Statistics.cor(x::AbstractVector{Union{Bool, Missing}}, y::AbstractVector) = cor(y, passmissing(Int).(x))

"""
    dfcor(df::AbstractDataFrame, cols1=names(df), cols2=names(df), verbose=false)

Compute correlation in a DataFrames by specifying a set of columns `cols1` vs
another set `cols2`. The cartesian product of `cols1` and `cols2`'s correlation
will be computed
"""
dfcor(df::AbstractDataFrame, cols1 = names(df), cols2 = names(df); verbose=false) = begin
    k = 1
    l1 = length(cols1)
    l2 = length(cols2)
    res = Vector{Float32}(undef, l1*l2)
    names1 = Vector{Symbol}(undef, l1*l2)
    names2 = Vector{Symbol}(undef, l1*l2)
    for i in 1:l1
        icol = df[!, cols1[i]]

        if eltype(icol) >: String
            # do nothing
        else
            Threads.@threads for j in 1:l2
                if eltype(df[!, cols2[j]]) >: String
                    # do nothing
                else
                    if verbose
                        println(k, " ", cols1[i], " ", cols2[j])
                    end
                    df2 = df[:,[cols1[i], cols2[j]]] |> dropmissing
                    if size(df2, 1) > 0
                        res[k] = cor(df2[!,1], df2[!, 2])
                        names1[k] = cols1[i]
                        names2[k] = cols2[j]
                        k+=1
                    end
                end
            end
        end
    end
    (names1[1:k-1], names2[1:k-1], res[1:k-1])
end

# support for nanoseconds in dates
using Dates

struct DateTimeN
    d::Date
    t::Time
end

str = "2019-10-23T12:01:15.123456789"

parseDateTimeN(str)
parseDateTimeN( "2019-10-23T12:01:15.230")

function parseDateTimeN(str)
    date, mmn = split(str, '.')
    date1, time1 = split(date,'T')

    time2 = parse.(Int64, split(time1, ':'))

    mmn1 = mmn * reduce(*, ["0" for i in 1:(9-length(mmn))])

    rd = reverse(digits(parse(Int, mmn1), pad = 9))

    t = reduce(vcat, [
        time2,
        parse(Int, reduce(*, string.(rd[1:3]))),
        parse(Int, reduce(*, string.(rd[4:6]))),
        parse(Int, reduce(*, string.(rd[7:9])))]
        )

    DateTimeN(Date(date1), Time(t...))
end

parseDateTimeN(str)

import Base:show

show(io::IO, dd::DateTimeN) = begin
    print(io, dd.d)
    print(io, dd.t)
end

DateTimeN(str::String) = parseDateTimeN(str)

################################################################################
# convenient function for CategoricalArrays
################################################################################
import SortingLab:sorttwo!
import StatsBase: rle
using CategoricalArrays

SortingLab.sorttwo!(x::CategoricalVector, y) = begin
    SortingLab.sorttwo!(x.refs, y)
    x, y
end

pooltype(::CategoricalPool{T,S}) where {T, S} = T,S

rle(x::CategoricalVector) = begin
   	refrle = rle(x.refs)
   	T,S = pooltype(x.pool)
   	(CategoricalArray{T, 1}(S.(refrle[1]), x.pool), refrle[2])
end

end # module
