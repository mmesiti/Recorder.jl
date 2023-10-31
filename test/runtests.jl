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
            clear()
            @record f3arg(4, 5, 6)
            Recorder.gs.return_values["TestModule.f3arg"] |> last == f3arg(4, 5, 6)
        end
        @test begin
            clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.return_values["TestModule1.f"] |> last == TestModule1.f(4, 5, 6)
        end
    end

    @testset "Arguments are recorded and can be retrieved with Recorder.gs.argumentss" begin
        @test begin
            clear()
            @record f3arg(4, 5, 6)
            Recorder.gs.argumentss["TestModule.f3arg"] |> last == [4, 5, 6]
        end
        @test begin
            clear()
            @record TestModule1.f(4, 5, 6)
            Recorder.gs.argumentss["TestModule1.f"] |> last == [4, 5, 6]
        end
    end

    @testset "Post-values of args are recorded and can be retrieved with Recorder.gs.argumentss_post" begin
        @test begin
            v = [1, 2, 3]
            clear()
            @record push!(v, 4)
            Recorder.gs.argumentss["Base.push!"] |> last == [[1, 2, 3], 4] &&
                Recorder.gs.argumentss_post["Base.push!"] |> last == [[1, 2, 3, 4], 4]
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
            Recorder.gs.call_number["Base.identity"] == 10
        end
    end

    @testset "When using record range, only the right calls are recorded." begin
        @test begin
            clear()
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

    @testset "Use custom state instead of Recorder's global" begin
        @test begin
           clear()
	       mystate = Recorder.State()
           @record mystate identity(50)
           Recorder.gs.argumentss == Dict() &&
               mystate.argumentss["Base.identity"] == [[50]]
        end
    end

    @testset "Use record range and custom state" begin
        @test begin
            clear()
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

    @testset "clear(mystate) works as intended" begin
        mystate = Recorder.State()
        for i in 1:10
            @record mystate 3:2:7 identity(i)
        end
        @test length(mystate.argumentss["Base.identity"]) == 3
        clear(mystate)
        @test length(mystate.argumentss) == 0
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

    @testset "create_regression_test(fname,state) uses user-provided state" begin
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

    @testset "create_regression_test(fname,namestem) uses namestem in filenames" begin
        @test begin
            setup_cleanup("A_Namestem") do
                @record identity(5)
                @record identity("hello")
                create_regression_tests("Base.identity",namestem="A_Namestem")
                "regression_tests_A_Namestem.jl" in readdir()
            end
        end
    end
end
