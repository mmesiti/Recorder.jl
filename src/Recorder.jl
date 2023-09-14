module Recorder
using Base: remove_linenums!
export @record,
    get_return_value,
    get_arguments,
    get_arguments_post,
    clear,
    create_regression_tests

import Serialization


function _record_expr(expr, key)
    args = expr.args[2:end]

    # Start assembling macro
    res = quote
        args_input = []
        args_output = []
    end

    # process each argument pre-call
    for arg in args
        push!(res.args, :(push!(args_input, deepcopy(eval($(esc(arg)))))))
    end

    # record argument list in global dictionary
    push!(res.args, :(record_arguments($key, args_input)))

    # evaluate function
    push!(res.args, :(output = $(esc(expr))))
    push!(res.args, :(record_return_values($key, deepcopy(output))))
    # increase call_number
    push!(res.args, :(increase_call_no($key)))

    # process each argument post evaluation
    for arg in args
        push!(res.args, :(push!(args_output, deepcopy(eval($(esc(arg)))))))

    end

    # record argument list in global dictionary (post evaluation)
    push!(res.args, :(record_arguments_post($key, args_output)))

    # leaving output at the end as the expression value
    push!(res.args, :(output))
    res
end

function _no_record_expr(expr, key)
    quote
        increase_call_no($key)
        $(esc(expr))
    end
end

macro record(expr)
    key = string(expr.args[1])
    _record_expr(expr, key)
end

macro record(record_range, expr)
    key = string(expr.args[1])

    condition = :(get_call_no($key) + 1 in $record_range)

    res = :(
        if $condition
        else
        end
    )
    res.args[2] = _record_expr(expr, key)
    res.args[3] = _no_record_expr(expr, key)
    res
end

return_values = Dict{String,Vector{Any}}()
argumentss = Dict{String,Vector{Any}}()
argumentss_post = Dict{String,Vector{Any}}()
call_number = Dict{String,Int32}()


function get_return_value(fname)
    return_values[fname]
end

function get_arguments(fname)
    argumentss[fname]
end

function get_arguments_post(fname)
    argumentss_post[fname]
end

function record_arguments(fname, args_input)
    if !haskey(argumentss, fname)
        argumentss[fname] = []
    end
    push!(argumentss[fname], args_input)
end

function record_return_values(fname, return_value)
    if !haskey(return_values, fname)
        return_values[fname] = []
    end
    push!(return_values[fname], return_value)
end


function record_arguments_post(fname, args_output)
    if !haskey(argumentss_post, fname)
        argumentss_post[fname] = []
    end
    push!(argumentss_post[fname], args_output)
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

function get_call_no(fname)
    if !haskey(call_number, fname)
        call_number[fname] = 0
    end
    call_number[fname]
end

function increase_call_no(fname)
    if !haskey(call_number, fname)
        call_number[fname] = 0
    end
    call_number[fname] += 1
end

function create_regression_tests_data(fname)
    return_value = return_values[fname]
    argument = argumentss[fname]
    argument_post = argumentss_post[fname]
    output_filename = "regression_tests_$fname.data"

    data = Dict("return_value" => return_value,
        "arguments" => argument,
        "arguments_post" => argument_post)

    Serialization.serialize(output_filename, data)
    output_filename

end

function create_regression_tests(fname)
    output_filename = create_regression_tests_data(fname)
    script_filename = "regression_tests_$fname.jl"
    filecontentexpr = quote
        using Test
        using Serialization
        data = deserialize($output_filename)
        @testset for (return_value,
            arguments,
            arguments_post) in zip(data["return_value"],
            data["arguments"],
            data["arguments_post"])
            return_value == $(Symbol(fname))(arguments...) &&
                arguments == arguments_post
        end
    end
    sbuffer = IOBuffer()
    for line in filecontentexpr.args
        if typeof(line) != LineNumberNode
            println(sbuffer, line)
        end
    end
    text = take!(sbuffer) |> String
    text = replace(text, r"#=.*=#\s*" => "")
    script_file = open(script_filename, "w")
    write(script_file, text)
    close(script_file)
    filecontentexpr
end

end # module Recorder
