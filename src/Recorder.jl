module Recorder
using Base: remove_linenums!, nothing_sentinel
export @record, create_regression_tests, recursive_value_equality


import JLD2
using JuliaFormatter

struct State
    return_values::Dict{Function,Vector{Any}}
    argumentss::Dict{Function,Vector{Any}}
    argumentss_post::Dict{Function,Vector{Any}}
    call_number::Dict{Function,Int32}
end

State() = State(Dict(), Dict(), Dict(), Dict())

gs = State()

"""Adds the logic to  determine the key for recording."""
function _add_getkey!(output::Expr, input::Expr)
    args = input.args[2:end]
    # get module_implementing, and key
    argtypes = :(())
    for arg in args
        push!(argtypes.args, :(typeof($(esc(arg)))))
    end
    push!(output.args, :(argtypes = $argtypes))
    push!(output.args, :(method = which($(esc(input.args[1])), argtypes)))
    push!(output.args, :(module_implementing = method.module))
    push!(output.args, :(name = method.name))
    push!(output.args, :(_func = $(esc(input.args[1]))))
    push!(
        output.args,
        :(
            key = _func
            # key = replace(
            #     string(module_implementing) * "." * string(name),
            #     r"^Main\." => s"",
            # )
        ),
    )
end

"""Creates the expression to record the function call."""
function _record_expr(input::Expr, state)
    args = input.args[2:end]

    # Start assembling macro
    output::Expr = quote
        args_input = []
        args_output = []
    end
    _add_getkey!(output, input)

    # process each argument pre-call
    for arg in args
        push!(output.args, :(push!(args_input, deepcopy($(esc(arg))))))
    end

    # record argument list in global dictionary
    push!(output.args, :(record_arguments(key, args_input, $(esc(state)))))

    # evaluate function
    push!(output.args, :(output = $(esc(input))))
    push!(output.args, :(record_return_values(key, deepcopy(output), $(esc(state)))))
    # increase call_number
    push!(output.args, :(increase_call_no(key, $(esc(state)))))

    # process each argument post evaluation
    for arg in args
        push!(output.args, :(push!(args_output, deepcopy($(esc(arg))))))
    end

    # record argument list in global dictionary (post evaluation)
    push!(output.args, :(record_arguments_post(key, args_output, $(esc(state)))))

    # leaving output at the end as the expression value
    push!(output.args, :(output))
    output
end

"""Return an expression where the function call is not recorded,
   but the call counter is increased.
"""
function _no_record_expr(expr::Expr, state)
    output::Expr = quote end
    _add_getkey!(output, expr)
    push!(output.args, :(increase_call_no(key, $(esc(state)))))
    push!(output.args, :($(esc(expr))))
    output
end

"""Creates an expression where function calls are recorded
   only in the specified range.
"""
function _record_with_range(record_range, expr::Expr, state)
    output::Expr = quote end
    _add_getkey!(output, expr)

    if record_range !== nothing
        condition = :(get_call_no(key, $(esc(state))) + 1 in $record_range)
    else
        condition = :(true)
    end


    ifblock = :(
        if $condition
        else
        end
    )
    ifblock.args[2] = _record_expr(expr, state)
    ifblock.args[3] = _no_record_expr(expr, state)
    push!(output.args, ifblock)
    output
end

# Macros

"""Record macro with a single expression.
   Uses the global state in the Recorder module,
   records every call to the function.
"""
macro record(expr::Expr)
    _record_expr(expr, :(Recorder.gs))
end

"""Record macro with an additional range expression.
   Uses the global state in the Recorder module.
   Only records the calls in the specified range.
   The range must be given in the form

   <1st call to record>:<interval>:<last call to record>
   and only every <interval>-th function call
   will be recorded.
"""
macro record(range_expr::Expr, expr::Expr)
    if range_expr.args[1] == :(:)
        _record_with_range(range_expr, expr, :(Recorder.gs))
    else
        message = """
        The expression '$range_expr' does not represent a range.
        If you want to pass a state object,
        assign it to a symbol and pass that instead.
        """
        quote
            throw(ArgumentError($message))
        end
    end
end

"""Record macro
   using a provided Recorded.State
   instead of the the global state in the Recorder module.
"""
macro record(state_expr::Symbol, expr::Expr)
    _record_expr(expr, state_expr)
end

"""Record macro with an additional range expression,
   using a provided Recorded.State
   instead of the the global state in the Recorder module.

   Only records the calls in the specified range.
   The range must be given in the form

   <1st call to record>:<interval>:<last call to record>
   and only every <interval>-th function call
   will be recorded.
"""
macro record(state_expr::Symbol, range_expr::Expr, expr::Expr)
    _record_with_range(range_expr, expr, state_expr)
end


# Internal functions to be used output expressions

function record_arguments(key, args_input, state::State)
    if !haskey(state.argumentss, key)
        state.argumentss[key] = []
    end
    push!(state.argumentss[key], args_input)
end

function record_return_values(key, return_value, state::State)
    if !haskey(state.return_values, key)
        state.return_values[key] = []
    end
    push!(state.return_values[key], return_value)
end

function record_arguments_post(key, args_output, state::State)
    if !haskey(state.argumentss_post, key)
        state.argumentss_post[key] = []
    end
    push!(state.argumentss_post[key], args_output)
end

function clear(state::State=gs)
    function cleardict!(d)
        for k in keys(d)
            delete!(d, k)
        end
    end
    cleardict!(state.return_values)
    cleardict!(state.argumentss)
    cleardict!(state.argumentss_post)
    cleardict!(state.call_number)
    nothing
end

function get_call_no(key, state::State)
    if !haskey(state.call_number, key)
        state.call_number[key] = 0
    end
    state.call_number[key]
end

function increase_call_no(key, state::State)
    if !haskey(state.call_number, key)
        state.call_number[key] = 0
    end
    state.call_number[key] += 1
end

function create_regression_tests_data(key, tag, state::State=gs)
    return_value = state.return_values[key]
    argument = state.argumentss[key]
    argument_post = state.argumentss_post[key]
    output_filename = "regression_tests_$tag.data"

    data = Dict(
        "return_value" => return_value,
        "arguments" => argument,
        "arguments_post" => argument_post,
    )

    JLD2.save_object(output_filename, data)
    output_filename

end


_base_using_directives = quote
    using Test
    using JLD2
end

recursive_value_equality_expr = quote
    function recursive_value_equality(strA, strB)
        strA == strB || (
            typeof(strA) == typeof(strB) &&
            if fieldnames(typeof(strA)) == ()
                strA == strB
            else
                all(getfield(strA, field) == getfield(strB, field) ||
                    recursive_value_equality(getfield(strA, field),
                        getfield(strB, field))
                    for field in fieldnames(typeof(strA))
                )
            end
        )
    end
    function recursive_value_equality(strA::Vector, strB::Vector)
        strA == strB || (
            typeof(strA) == typeof(strB) &&
            length(strA) == length(strB) &&
            all(strA[i] == strB[i] ||
                recursive_value_equality(strA[i],
                strB[i])
                for i in eachindex(strA))
        )
    end

    function recursive_value_equality(strA::Vector{T}, strB::Vector{U}) where {T<:Number} where {U<:Number}
        length(strA) == length(strB) &&
            (strA ≈ strB ||
             all(strA[i] ≈ strB[i] ||
                 recursive_value_equality(strA[i],
                strB[i])
                 for i in eachindex(strA)))
    end


end




function testset_expr(full_func_name, data_output_filename)
    testsetname = "Tests for $(name_from_function(full_func_name))"
    quote
        @testset verbose = true $testsetname begin
            "You might need to modify this function!"
            function compare_return_values(rvexp, rv)
                recursive_value_equality(rvexp, rv)
            end
            "You might need to modify this function!"
            function compare_arguments_post(args_post_exp, arg_post)
                recursive_value_equality(args_post_exp, arg_post)
            end

            data = load_object(joinpath(@__DIR__,$data_output_filename))
            @testset for i = 1:length(data["return_value"])
                return_value = data["return_value"][i]
                arguments = data["arguments"][i]
                arguments_post = data["arguments_post"][i]
                @test compare_return_values(
                    return_value,
                    full_func_name(arguments...),
                ) && compare_arguments_post(arguments, arguments_post)
            end
        end
    end
end

function mod_hierarchy_str(func)
    methods(func)[1].module
end

function create_text(filecontentexpr, modhierarchstrs...)::String
    sbuffer = IOBuffer()

    for modhierarchstr in modhierarchstrs
        println(sbuffer, "using $modhierarchstr")
    end

    for line in filecontentexpr.args
        if typeof(line) != LineNumberNode
            println(sbuffer, line)
        end
    end

    text = sbuffer |> take! |> String |> (t -> replace(t, r"#=.*=#\s*" => ""))
    #text = replace(text, r"#=.*=#\s*" => "")
    text
end

function write_to_file(tag, text)
    script_filename = "regression_tests_$tag.jl" 
    script_file = open(script_filename, "w")
    write(script_file, text)
    close(script_file)
    format(script_filename)
    script_filename
end

function name_from_function(f)
    m = methods(f)[1]
    "$(m.module).$(m.name)" 
end
    
function create_regression_tests(func::Function;  tag=nothing, state::State=gs)
    if isnothing(tag)
        tag=name_from_function(func)
    end

    _create_regression_tests([func], tag=tag, state=state)
end

function create_regression_tests(; tag, state::State=gs)
    all_keys = [k for k in keys(state.return_values)]
    _create_regression_tests(all_keys, tag=tag, state=state)
end

function _create_regression_tests(all_funcs::Vector; tag, state::State=gs)::Tuple{String,String}

    func_names = [ name_from_function(func) for func in all_funcs ]

    function get_ns(tag, func_name)
        if length(all_funcs) == 1
            tag
        else
            "$tag-$func_name"
        end
    end

    data_output_filenames = [
        create_regression_tests_data(key, get_ns(tag, func_name), state) for
        (key, func_name) in zip(all_funcs, func_names)
    ]

    filecontentexpr = quote end
    append!(
        filecontentexpr.args,
        _base_using_directives.args,
        recursive_value_equality_expr.args,
        [
            testset_expr(func,data_output_filename).args for
            (func, data_output_filename) in zip(all_funcs, data_output_filenames)
        ]...,
    )

    text = create_text(filecontentexpr, [mod_hierarchy_str(k) for k in all_funcs]...)
    script_filename = write_to_file(tag, text)
    script_filename, text
end


end # module Recorder
