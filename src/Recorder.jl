module Recorder
using Base: remove_linenums!
export @record,
    clear,
    create_regression_tests

import Serialization

return_values = Dict{String,Vector{Any}}()
argumentss = Dict{String,Vector{Any}}()
argumentss_post = Dict{String,Vector{Any}}()
call_number = Dict{String,Int32}()



function _add_getkey!(expr, res)
    args = expr.args[2:end]
    # get module_implementing, and key
    argtypes = :(())
    for arg in args
        push!(argtypes.args, :(typeof($(esc(arg)))))
    end
    push!(res.args, :(argtypes = $argtypes))
    push!(res.args, :(method = which($(esc(expr.args[1])), argtypes)))
    push!(res.args, :(module_implementing = method.module))
    push!(res.args, :(name = method.name))
    push!(res.args, :(key = replace(string(module_implementing) * "." * string(name),
        r"^Main\." => s"")))
end


function _record_expr(expr)
    args = expr.args[2:end]

    # Start assembling macro
    res = quote
        args_input = []
        args_output = []
    end
    _add_getkey!(expr, res)

    # process each argument pre-call
    for arg in args
        push!(res.args, :(push!(args_input, deepcopy($(esc(arg))))))
    end

    # record argument list in global dictionary
    push!(res.args, :(record_arguments(key, args_input)))

    # evaluate function
    push!(res.args, :(output = $(esc(expr))))
    push!(res.args, :(record_return_values(key, deepcopy(output))))
    # increase call_number
    push!(res.args, :(increase_call_no(key)))

    # process each argument post evaluation
    for arg in args
        push!(res.args, :(push!(args_output, deepcopy($(esc(arg))))))
    end

    # record argument list in global dictionary (post evaluation)
    push!(res.args, :(record_arguments_post(key, args_output)))

    # leaving output at the end as the expression value
    push!(res.args, :(output))
    res
end

function _no_record_expr(expr)
    res = quote end
    _add_getkey!(expr, res)
    push!(res.args, :(increase_call_no(key)))
    push!(res.args, :($(esc(expr))))
    res
end

macro record(expr)
    _record_expr(expr)
end

macro record(record_range, expr)
    res = quote end
    _add_getkey!(expr, res)

    condition = :(get_call_no(key) + 1 in $record_range)

    ifblock = :(
        if $condition
        else
        end
    )
    ifblock.args[2] = _record_expr(expr)
    ifblock.args[3] = _no_record_expr(expr)
    push!(res.args, ifblock)
    res
end

return_values = Dict{String,Vector{Any}}()
argumentss = Dict{String,Vector{Any}}()
argumentss_post = Dict{String,Vector{Any}}()
call_number = Dict{String,Int32}()

function record_arguments(key, args_input)
    if !haskey(argumentss, key)
        argumentss[key] = []
    end
    push!(argumentss[key], args_input)
end

function record_return_values(key, return_value)
    if !haskey(return_values, key)
        return_values[key] = []
    end
    push!(return_values[key], return_value)
end

function record_arguments_post(key, args_output)
    if !haskey(argumentss_post, key)
        argumentss_post[key] = []
    end
    push!(argumentss_post[key], args_output)
end

function clear()
    function cleardict!(d)
        for k in keys(d)
            delete!(d, k)
        end
    end
    cleardict!(return_values)
    cleardict!(argumentss)
    cleardict!(argumentss_post)
    cleardict!(call_number)
    nothing
end

function get_call_no(key)
    if !haskey(call_number, key)
        call_number[key] = 0
    end
    call_number[key]
end

function increase_call_no(key)
    if !haskey(call_number, key)
        call_number[key] = 0
    end
    call_number[key] += 1
end

function create_regression_tests_data(key, namestem)
    return_value = return_values[key]
    argument = argumentss[key]
    argument_post = argumentss_post[key]
    output_filename = "regression_tests_$namestem.data"

    data = Dict("return_value" => return_value,
        "arguments" => argument,
        "arguments_post" => argument_post)

    Serialization.serialize(output_filename, data)
    output_filename

end

function create_regression_tests(key, namestem=key)
    output_filename = create_regression_tests_data(key, namestem)
    script_filename = "regression_tests_$namestem.jl"

    fname = split(key, ".")[end]
    modhierarchstr = join(split(key, ".")[1:end-1], ".")

    testsetname = "Tests for $fname"
    filecontentexpr = quote
        using Test
        using Serialization
        data = deserialize($output_filename)
        "You might need to modify this function!"
        function compare_return_values(rvexp, rv)
            rvexp == rv
        end
        "You might need to modify this function!"
        function compare_arguments_post(args_post_exp, arg_post)
            arg_post_exp == arg_post
        end

        @testset verbose = true $testsetname begin
            @testset for i in 1:length(data["return_value"])
                return_value = data["return_value"][i]
                arguments = data["arguments"][i]
                arguments_post = data["arguments_post"][i]
                compare_return_values(return_value, $(Symbol(fname))(arguments...)) &&
                    compare_arguments_post(arguments, arguments_post)
            end
        end
    end
    sbuffer = IOBuffer()
    println(sbuffer, "using $modhierarchstr")
    for line in filecontentexpr.args
        if typeof(line) != LineNumberNode
            println(sbuffer, line)
        end
    end
    text = sbuffer |>
           take! |>
           String |>
           (t -> replace(t, r"#=.*=#\s*" => ""))
    #text = replace(text, r"#=.*=#\s*" => "")
    script_file = open(script_filename, "w")
    write(script_file, text)
    close(script_file)
    filecontentexpr
end

end # module Recorder
