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


    @testset "Return Value is recorded and can be retrieved with Recorder.get_return_value" begin
        @test begin
            clear()
            @record f3arg(4, 5, 6)
            Recorder.return_values["TestModule.f3arg"] |> last == f3arg(4, 5, 6)
        end
        @test begin
            clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.return_values["TestModule1.f"] |> last == TestModule1.f(4, 5, 6)
        end
    end

    @testset "Arguments are recorded and can be retrieved with get_arguments" begin
        @test begin
            clear()
            @record f3arg(4, 5, 6)
            Recorder.argumentss["TestModule.f3arg"] |> last == [4, 5, 6]
        end
        @test begin
            clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.argumentss["TestModule1.f"] |> last == [4, 5, 6]
        end
    end

    @testset "Post-values of args are recorded and can be retrieved with get_arguments_post" begin
        @test begin
            v = [1, 2, 3]
            clear()
            @record push!(v, 4)
            Recorder.argumentss["Base.push!"] |> last == [[1, 2, 3], 4] &&
                Recorder.argumentss_post["Base.push!"] |> last == [[1, 2, 3, 4], 4]
        end
    end

    @testset "Function that modify in-place work as expected" begin
        @test begin
            v = [1, 2, 3]
            clear()
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
            clear()
            testfun() != 6 && testfun() == 55
        end
    end

    @testset "When calling in a loop, number of calls is increased each time" begin
        @test begin
            clear()
            for i in 1:10
                @record identity(i)
            end
            Recorder.get_call_no("Base.identity") == 10
        end
    end

    @testset "When using record range, only the right calls are recorded." begin
        @test begin
            clear()
            for i in 1:10
                @record 3:2:7 identity(i)
            end
            try
                Recorder.argumentss["Base.identity"] == [[3], [5], [7]]
            catch
                println(Recorder.return_values)
                false
            end
        end
    end

    function setup_cleanup(test, namestem)
        clear()
        rm("regression_tests_$namestem.data", force=true)
        rm("regression_tests_$namestem.jl", force=true)
        try
            test()
        catch
            false
        finally
            rm("regression_tests_$namestem.data", force=true)
            rm("regression_tests_$namestem.jl", force=true)
        end
    end

    @testset "create_regression_tests(fname) saves arguments and outputs to file" begin
        @test begin
            setup_cleanup("Base.identity") do
                @record identity(5)
                try
                    create_regression_tests("Base.identity")
                catch
                    println(Recorder.return_values)
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
                    occursin("Base.identity", filestring)
            end
        end
    end
end
