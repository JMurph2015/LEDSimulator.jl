function validate_json(json_data::Dict{String,Any})
    ref_dict = Dict(
        "ip"=>"",
        "mac"=>"",
        "msg_type"=>""
    )
    return collect(keys(json_data)) == collect(keys(ref_dict))
end

check_json(x::T, y::T) where {T<:Dict{String, N} where N<:Any} = check_symmetry(x,y)
check_json(x::T, y::N) where {T,N} = false

function check_symmetry(x::T, y::T) where {T<:Dict{S, N} where {S<:Any, N<:Any}}
    if collect(keys(x)) == collect(keys(y))
        return reduce(check_symmetry.(collect(values(x)), collect(values(y)))) do x, y
            return x && y
        end
    else
        return false
    end
end

function check_symmetry(x::AbstractArray, y::AbstractArray)
    try
        return reduce(check_symmetry.(x,y)) do x, y
            return x && y
        end
    catch
        return false
    end
end

check_symmetry(x::T, y::T) where T<:Union{Number, String, Bool} = true
check_symmetry(x::T, y::N) where {T, N} = false
