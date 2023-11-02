using Test
using Recorder
using Serialization
include("TestModules.jl")

using .TestModule


@testset verbose = true "Recorder Tests..." begin
    @testset "The recorded function returns the same value" begin
        @test @record identity(6.5) == identity(6.5)
        @test @record f3arg(4, 5, 6) == f3arg(4, 5, 6)
        @test @record TestModule1.f(4, 5, 6) == TestModule1.f(4, 5, 6)
    end


    @testset "Return Value is recorded and can be retrieved with Recorder.gs.return_values" begin
        @test begin
            Recorder.clear()
            @record f3arg(4, 5, 6)
            Recorder.gs.return_values["TestModule.f3arg"] |> last == f3arg(4, 5, 6)
        end
        @test begin
            Recorder.clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.return_values["TestModule1.f"] |> last == TestModule1.f(4, 5, 6)
        end
    end

    @testset "Arguments are recorded and can be retrieved with Recorder.gs.argumentss" begin
        @test begin
            Recorder.clear()
            @record f3arg(4, 5, 6)
            Recorder.gs.argumentss["TestModule.f3arg"] |> last == [4, 5, 6]
        end
        @test begin
            Recorder.clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.argumentss["TestModule1.f"] |> last == [4, 5, 6]
        end
        @test begin
            Recorder.clear()
            @record TestModule1.SubMod11.f(4, 5, 6)
            Recorder.gs.argumentss["TestModule1.SubMod11.f"] |> last == [4, 5, 6]
        end
    end


    @testset "Post-values of args are recorded and can be retrieved with Recorder.gs.argumentss_post" begin
        @test begin
            v = [1, 2, 3]
            Recorder.clear()
            @record push!(v, 4)
            Recorder.gs.argumentss["Base.push!"] |> last == [[1, 2, 3], 4] &&
                Recorder.gs.argumentss_post["Base.push!"] |> last == [[1, 2, 3, 4], 4]
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
            for i in 1:10
                @record identity(i)
            end
            Recorder.gs.call_number["Base.identity"] == 10
        end
    end

    @testset "When using record range, only the right calls are recorded." begin
        @test begin
            Recorder.clear()
            for i in 1:10
                @record 3:2:7 identity(i)
            end
            try
                Recorder.gs.argumentss["Base.identity"] == [[3], [5], [7]]
            catch
                println(Recorder.gs.return_values)
                false
            end
        end
    end

    @testset "@record complains meaningfully if the expression passed is not a range" begin
        try
            @record a=b identity(5)
            @test false
        catch e
            @test typeof(e) == ArgumentError
            @test contains(e.msg,"does not represent a range")
            @test contains(e.msg,"assign it to a symbol and pass that")
        end
    end


    @testset "Use custom state instead of Recorder's global" begin
        @test begin
           Recorder.clear()
	       mystate = Recorder.State()
           @record mystate identity(50)
           Recorder.gs.argumentss == Dict() &&
               mystate.argumentss["Base.identity"] == [[50]]
        end
    end

    @testset "Use record range and custom state" begin
        @test begin
            Recorder.clear()
            mystate = Recorder.State()
            for i in 1:10
                @record mystate 3:2:7 identity(i)
            end
            try
                Recorder.gs.argumentss == Dict() &&
                   mystate.argumentss["Base.identity"] == [[3],[5],[7]]
            catch
                println(Recorder.gs.return_values)
                println(mystate.return_values)
                false
            end
        end
    end

    @testset "Recorder.clear(mystate) works as intended" begin
        mystate = Recorder.State()
        for i in 1:10
            @record mystate 3:2:7 identity(i)
        end
        @test length(mystate.argumentss["Base.identity"]) == 3
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
        catch
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
                    create_regression_tests("Base.identity")
                catch
                    println(Recorder.gs.return_values)
                    false
                else
                    "regression_tests_Base.identity.data" in readdir()
                end
            end
        end
        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                create_regression_tests("Base.identity")
                data = deserialize("regression_tests_Base.identity.data")
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
                create_regression_tests("Base.identity")
                data = deserialize("regression_tests_Base.identity.data")
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
                create_regression_tests("Base.identity",state=mystate)
                data = deserialize("regression_tests_Base.identity.data")
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
                create_regression_tests("Base.identity")
                "regression_tests_Base.identity.jl" in readdir()
            end
        end

        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                @record identity("hello")
                expr = create_regression_tests("Base.identity")
                io = IOBuffer()
                print(io, expr)
                filestring = String(take!(io))
                occursin("using Test", filestring) &&
                    occursin("using Serialization", filestring) &&
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
                create_regression_tests("Base.identity",tag="A_Tag")
                "regression_tests_A_Tag.jl" in readdir()
            end
        end
    end

    @testset "create_regression_tests creates appropriate scripts" begin
        text = setup_cleanup("A_Tag") do
            @record identity(5)
            @record identity("hello")
            create_regression_tests("Base.identity",tag="A_Tag")
        end

        @test contains(text, "using Base") # Module containing the identity function
        @test contains(text, "using Test")
        @test contains(text, "using Serialization")

        @test contains(text,"@testset")
        @test contains(text,"@test ")
        @test contains(text,"function compare_return_values")
        @test contains(text,"function compare_arguments_post")

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
    @testset verbose=true "create_regression_test works without key" begin
        text = setup_cleanup_nokey("A_Tag",
                                   "A_Tag-f3arg",
                                   "A_Tag-identity") do
            mystate = Recorder.State()
            @record mystate identity(5)
            @record mystate f3arg(4,5,6)
            create_regression_tests(state=mystate,tag="A_Tag")
        end

        @test count("using Test\n"       ,text) == 1
        @test count("using Serialization",text) == 1
        @test count("using Base"         ,text) == 1 # Module containing the identity function
        @test count("using TestModule"   ,text) == 1

        @test count("@testset",text) == 2*2 # Inner and outer
        @test count("@test "                         ,text) == 2
        @test count("function compare_return_values" ,text) == 2
        @test count("function compare_arguments_post",text) == 2
        @test contains(text,"Tests for f3arg")
        @test contains(text,"Tests for identity")
    end


    @testset verbose=true "create_regression_test works by README.md example" begin
        text = setup_cleanup_nokey("batch-1",
                                   "batch-1-func1",
                                   "batch-1-func2") do
            a,b,c = 3,4,5

            mystate = Recorder.State()
            @record mystate func1(a,b,c)
            @record mystate func2(a,b,c)

            text = create_regression_tests(state=mystate,tag="batch-1")
            @test "regression_tests_batch-1.jl" in readdir()
            @test "regression_tests_batch-1-func1.data" in readdir()
            @test "regression_tests_batch-1-func2.data" in readdir()
            text
        end

        @test contains(text,"Tests for func1")
        @test contains(text,"Tests for func2")
    end
end
