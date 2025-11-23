using Test
using Recorder
using JLD2
include("TestModules.jl")

using .TestModule

eval(Recorder.recursive_value_equality_expr)

@testset verbose = true "Recorder Tests..." begin
    @testset "The recorded function returns the same value" begin
        @test @record identity(6.5) == identity(6.5)
        @test @record TestModule.f3arg(4, 5, 6) == TestModule.f3arg(4, 5, 6)
        @test @record TestModule1.f(4, 5, 6) == TestModule1.f(4, 5, 6)
    end


    @testset "Return Value is recorded and can be retrieved with Recorder.gs.return_values" begin
        @test begin
            Recorder.clear()
            @record TestModule.f3arg(4, 5, 6)
            Recorder.gs.return_values[TestModule.f3arg] |> last == TestModule.f3arg(4, 5, 6)
        end
        @test begin
            Recorder.clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.return_values[TestModule1.f] |> last == TestModule1.f(4, 5, 6)
        end
    end

     @testset "Arguments are recorded and can be retrieved with Recorder.gs.argumentss" begin
        @test begin
            Recorder.clear()
            @record TestModule.f3arg(4, 5, 6)
            Recorder.gs.argumentss[TestModule.f3arg] |> last == [4, 5, 6]
        end
        @test begin
            Recorder.clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.argumentss[TestModule1.f] |> last == [4, 5, 6]
        end
        @test begin
            Recorder.clear()
            @record TestModule1.SubMod11.f(4, 5, 6)
            Recorder.gs.argumentss[TestModule1.SubMod11.f] |> last == [4, 5, 6]
        end
    end


    @testset "Post-values of args are recorded and can be retrieved with Recorder.gs.argumentss_post" begin
        @test begin
            v = [1, 2, 3]
            Recorder.clear()
            @record push!(v, 4)
            Recorder.gs.argumentss[Base.push!] |> last == [[1, 2, 3], 4] &&
                Recorder.gs.argumentss_post[Base.push!] |> last == [[1, 2, 3, 4], 4]
        end
    end

    @testset "Function that modify in-place work as expected" begin
        @test begin
            v = [1, 2, 3]
            Recorder.clear()
            @record push!(v, 4)
            v == [1, 2, 3, 4]
        end
    end

    @testset "When called inside another function, @record should not return for it" begin
        function testfun()
            function inner(a)
                a + 2
            end
            @record inner(4)
            return 55
        end

        @test begin
            Recorder.clear()
            testfun() != 6 && testfun() == 55
        end
    end

    @testset "When calling in a loop, number of calls is increased each time" begin
        @test begin
            Recorder.clear()
            for i = 1:10
                @record identity(i)
            end
            Recorder.gs.call_number[Base.identity] == 10
        end
    end

    @testset "When using record range, only the right calls are recorded." begin
        @test begin
            Recorder.clear()
            for i = 1:10
                @record 3:2:7 identity(i)
            end
            try
                Recorder.gs.argumentss[Base.identity] == [[3], [5], [7]]
            catch
                println(Recorder.gs.return_values)
                false
            end
        end
    end

    @testset "@record complains meaningfully if the expression passed is not a range" begin
        try
            @record a = b identity(5)
            @test false
        catch e
            @test typeof(e) == ArgumentError
            @test contains(e.msg, "does not represent a range")
            @test contains(e.msg, "assign it to a symbol and pass that")
        end
    end


    @testset "Use custom state instead of Recorder's global" begin
        @test begin
            Recorder.clear()
            mystate = Recorder.State()
            @record mystate identity(50)
            Recorder.gs.argumentss == Dict() &&
                mystate.argumentss[Base.identity] == [[50]]
        end
    end

    @testset "Use record range and custom state" begin
        @test begin
            Recorder.clear()
            mystate = Recorder.State()
            for i = 1:10
                @record mystate 3:2:7 identity(i)
            end
            try
                Recorder.gs.argumentss == Dict() &&
                    mystate.argumentss[Base.identity] == [[3], [5], [7]]
            catch
                println(Recorder.gs.return_values)
                println(mystate.return_values)
                false
            end
        end
    end

    @testset "Recorder.clear(mystate) works as intended" begin
        mystate = Recorder.State()
        for i = 1:10
            @record mystate 3:2:7 identity(i)
        end
        @test length(mystate.argumentss[Base.identity]) == 3
        Recorder.clear(mystate)
        @test length(mystate.argumentss) == 0
    end


    """
    Utility function to setup and teardown tests,
    when create_regression_tests is called with a specific key.
    """
    function setup_cleanup(test::Function, tag::String)
        function clean_filesystem()
            rm("regression_tests_$tag.data", force=true)
            rm("regression_tests_$tag.jl", force=true)
        end

        Recorder.clear()
        clean_filesystem()
        try
            r = test()
            @test "regression_tests_$tag.data" in readdir()
            @test "regression_tests_$tag.jl" in readdir()
            r
        catch e
            rethrow(e)
            false
        finally
            clean_filesystem()
        end
    end

    @testset "create_regression_tests(fname) saves arguments and outputs to file" begin
        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                try
                    create_regression_tests(Base.identity)
                catch e
                    println(Recorder.gs.return_values)
                    rethrow(e)
                    false
                else
                    "regression_tests_Base.identity.data" in readdir()
                end
            end
        end
        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                create_regression_tests(Base.identity)
                data = load_object("regression_tests_Base.identity.data")
                data["return_value"] == [5] &&
                    data["arguments"] == [[5]] &&
                    data["arguments_post"] == [[5]]
            end
        end

        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                @record identity("hello")
                @record identity(["hello", 7])
                create_regression_tests(Base.identity)
                data = load_object("regression_tests_Base.identity.data")
                data["return_value"] == [5, "hello", ["hello", 7]] &&
                    data["arguments"] == [[5], ["hello"], [["hello", 7]]] &&
                    data["arguments_post"] == [[5], ["hello"], [["hello", 7]]]
            end
        end

    end

    @testset "create_regression_tests(fname,state) uses user-provided state" begin
        @test begin
            setup_cleanup("Base.identity") do
                mystate = Recorder.State()
                @record mystate identity(5)
                @record mystate identity("hello")
                @record mystate identity(["hello", 7])
                create_regression_tests(Base.identity, state=mystate)
                data = load_object("regression_tests_Base.identity.data")
                data["return_value"] == [5, "hello", ["hello", 7]] &&
                    data["arguments"] == [[5], ["hello"], [["hello", 7]]] &&
                    data["arguments_post"] == [[5], ["hello"], [["hello", 7]]]
            end
        end
    end

    @testset "create_regression_tests(fname) creates script with tests" begin
        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                @record identity("hello")
                create_regression_tests(Base.identity)
                "regression_tests_Base.identity.jl" in readdir()
            end
        end

        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                @record identity("hello")
                expr = create_regression_tests(Base.identity)
                io = IOBuffer()
                print(io, expr)
                filestring = String(take!(io))
                occursin("using Test", filestring) &&
                    occursin("using JLD2", filestring) &&
                    occursin("@testset for i", filestring) &&
                    occursin("Base.identity", filestring) &&
                    occursin("@test ", filestring)
            end
        end
    end

    @testset "create_regression_tests(fname,tag) uses tag in filenames" begin
        @test begin
            setup_cleanup("A_Tag") do
                @record identity(5)
                @record identity("hello")
                create_regression_tests(Base.identity, tag="A_Tag")
                "regression_tests_A_Tag.jl" in readdir()
            end
        end
    end

    @testset "create_regression_tests creates appropriate scripts" begin
        text = setup_cleanup("A_Tag") do
            @record identity(5)
            @record identity("hello")
            _, text = create_regression_tests(Base.identity, tag="A_Tag")
            text 
        end


        @test contains(text, "using Base") # Module containing the identity function
        @test contains(text, "using Test")
        @test contains(text, "using JLD2")

        @test contains(text, "@testset")
        @test contains(text, "@test ")
        @test contains(text, "function compare_return_values")
        @test contains(text, "function compare_arguments_post")

    end

    """
    Utility function to setup and teardown tests,
    when create_regression_tests is called without a specific key.
    """
    function setup_cleanup_nokey(test::Function, tagjl::String, tagsdata::String...)
        Recorder.clear()
        function check_filesystem()
            for tag in tagsdata
                @test "regression_tests_$tag.data" in readdir()
            end
            @test "regression_tests_$tagjl.jl" in readdir()
        end
        function clean_filesystem()
            for tag in tagsdata
                rm("regression_tests_$tag.data", force=true)
            end
            rm("regression_tests_$tagjl.jl", force=true)
        end

        clean_filesystem()
        try
            r = test()
            check_filesystem()
            r
        catch
            false
        finally
            clean_filesystem()
        end
    end
    @testset verbose = true "create_regression_test works without key" begin
        text = setup_cleanup_nokey("A_Tag", "A_Tag-Main.TestModule.f3arg", "A_Tag-Base.identity") do
            mystate = Recorder.State()
            @record mystate identity(5)
            @record mystate TestModule.f3arg(4, 5, 6)
            _, text = create_regression_tests(state=mystate, tag="A_Tag")
            text
        end

        @test count("using Test\n", text) == 1
        @test count("using JLD2", text) == 1
        @test count("using Base", text) == 1 # Module containing the identity function
        @test count("using Main.TestModule", text) == 1

        @test count("@testset", text) == 2 * 2 # Inner and outer
        @test count("@test ", text) == 2
        @test count("function compare_return_values", text) == 2
        @test count("function compare_arguments_post", text) == 2
        @test contains(text, "Tests for Main.TestModule.f3arg")
        @test contains(text, "Tests for Base.identity")
    end


    @testset verbose = true "create_regression_test works by README.md example" begin
        text = setup_cleanup_nokey("batch-1", "batch-1-Main.TestModule.func1", "batch-1-Main.TestModule.func2") do
            a, b, c = 3, 4, 5

            mystate = Recorder.State()
            @record mystate TestModule.func1(a, b, c)
            @record mystate TestModule.func2(a, b, c)

            _, text = create_regression_tests(state=mystate, tag="batch-1")
            @test "regression_tests_batch-1.jl" in readdir()
            @test "regression_tests_batch-1-Main.TestModule.func1.data" in readdir()
            @test "regression_tests_batch-1-Main.TestModule.func2.data" in readdir()
            text
        end

        @test contains(text, "Tests for Main.TestModule.func1")
        @test contains(text, "Tests for Main.TestModule.func2")
    end

    @testset verbose = true "check recursive equality " begin


        @testset verbose = true "value checks" begin
            @test recursive_value_equality(1, 1)
            @test !recursive_value_equality(1, 2)
        end

        @testset verbose = true "immutable structure checks" begin
            # naive_equality(A,B) = all( getfield(A) )
            struct S1
                a::Int
                b::Int
            end

            @test recursive_value_equality(S1(1, 2), S1(1, 2))
            @test !recursive_value_equality(S1(1, 2), S1(1, 3))


            struct S2
                a::Int
                b::Vector{Int64}
            end

            @test recursive_value_equality(S2(1, [2,3]), S2(1, [2,3]))
            @test ! recursive_value_equality(S2(1, [2,4]), S2(1, [2,3]))

            struct S3
                a::S1
                b::S2
                c::Int64
            end

            @test recursive_value_equality(
            S3(S1(1,2), S2(1, [2,3]), 45),
            S3(S1(1,2), S2(1, [2,3]), 45))

            @test !recursive_value_equality(
            S3(S1(1,12), S2(1, [2,3]), 45),
            S3(S1(1,2), S2(1, [2,3]), 45))

            @test !recursive_value_equality(
            S3(S1(1,2), S2(1, [2,3]), 45),
            S3(S1(1,2), S2(1, [1,3]), 45))

            @test !recursive_value_equality(
            S3(S1(1,2), S2(1, [2,3]), 45),
            S3(S1(1,2), S2(1, [1,3]), 46))

        end

        @testset verbose = true "mutable structure checks" begin
            # naive_equality(A,B) = all( getfield(A) )
            mutable struct S1m
                a::Int
                b::Int
            end

            @test recursive_value_equality(S1m(1, 2), S1m(1, 2))
            @test !recursive_value_equality(S1m(1, 2), S1m(1, 3))


            mutable struct S2m
                a::Int
                b::Vector{Int64}
            end

            @test recursive_value_equality(S2m(1, [2,3]), S2m(1, [2,3]))
            @test ! recursive_value_equality(S2m(1, [2,4]), S2m(1, [2,3]))

            mutable struct S3m
                a::S1m
                b::S2m
                c::Int64
            end

            @test recursive_value_equality(
            S3m(S1m(1,2), S2m(1, [2,3]), 45),
            S3m(S1m(1,2), S2m(1, [2,3]), 45))

            @test !recursive_value_equality(
            S3m(S1m(1,12), S2m(1, [2,3]), 45),
            S3m(S1m(1,2), S2m(1, [2,3]), 45))

            @test !recursive_value_equality(
            S3m(S1m(1,2), S2m(1, [2,3]), 45),
            S3m(S1m(1,2), S2m(1, [1,3]), 45))

            @test !recursive_value_equality(
            S3m(S1m(1,2), S2m(1, [2,3]), 45),
            S3m(S1m(1,2), S2m(1, [1,3]), 46))

        end


        @testset verbose = true "vector checks" begin
            # naive_equality(v1,v2) = all(naive_equality(a,b) for (a,b) in zip(v1,v2))

            @test recursive_value_equality([1,3,"hello"],[1,3,"hello"])
            @test ! recursive_value_equality([1,3,"hello"],[1,3,"hellu"])

            @test recursive_value_equality([1,3,[1,2,3]],[1,3,[1,2,3]])
            @test ! recursive_value_equality([1,3,[1,3]],[1,3,[1,2,3]])

            @test recursive_value_equality([1,S1(2,3),[1,2,3]],[1,S1(2,3),[1,2,3]])
            @test ! recursive_value_equality([1,S1(2,3),[1,2,3]],[1,S1(1,3),[1,2,3]])

            @test recursive_value_equality([1,S2(2,[3,3]),[1,2,3]],
                                                 [1,S2(2,[3,3]),[1,2,3]])

            @test ! recursive_value_equality([1,S2(2,[3,3]),[1,2,3]],
                                                 [1,S2(2,[4,3]),[1,2,3]])

            end
        @testset verbose = true "vector checks, floating point" begin

            v = [1.0,2.0,3.0]
            w = Vector(v)
            v[3] += 1.0e-14
            @test recursive_value_equality(v,w)

            v = [1,2,3]
            w = [1.0,2.0,3.0]
            w[3] += 1.0e-14
            @test recursive_value_equality(v,w)
 
            end
    end
end
