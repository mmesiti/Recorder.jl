using Test
using Recorder
using Serialization

function f3arg(a,b,c)
    a-b+c
end

@testset "The recorded function returns the same value" begin
    @test @record identity(6.5) == identity(6.5)
    @test @record f3arg(4,5,6) == f3arg(4,5,6)
end


@testset "Return Value is recorded and can be retrieved with Recorder.get_return_value" begin
    @test begin
        clear()
        @record f3arg(4,5,6)
        get_return_value("f3arg") |> last == f3arg(4,5,6)
    end
end

@testset "Arguments are recorded and can be retrieved with Recorder.get_arguments" begin
    @test begin
        clear()
        @record f3arg(4,5,6)
        get_arguments("f3arg") |> last == [4,5,6]
    end
end

@testset "Post-values of arguments are recorded and can be retrieved with Recorder.get_arguments_post" begin
    @test begin
        v = [1,2,3]
        clear()
        @record push!(v,4)
        get_arguments("push!") |> last == [[1,2,3],4] &&
            get_arguments_post("push!") |> last == [[1,2,3,4],4]
    end
end

@testset "Function that modify in-place work as expected" begin
    @test begin
        v = [1,2,3]
        clear()
        @record push!(v,4)
        v == [1,2,3,4]
    end
end

@testset "When called inside another function, @record should not return for it" begin
    function testfun()
        function inner(a)
            a+2
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
        Recorder.get_call_no("identity") == 10
    end
end

@testset "When using record range, only the right calls are recorded." begin
    @test begin
        clear()
        for i in 1:10
            @record 3:2:7 identity(i)
        end
        get_arguments("identity") == [[3],[5],[7]]

    end
end

@testset "create_regression_tests(fname) saves arguments and outputs to file" begin
    rm("regression_tests_identity.data", force=true)
    @test begin
        clear()
        @record identity(5)
        create_regression_tests("identity")
        "regression_tests_identity.data" in readdir()
    end

    rm("regression_tests_identity.data", force=true)
    @test begin
        clear()
        @record identity(5)
        create_regression_tests("identity")
        data = deserialize("regression_tests_identity.data")
        data["return_value"] == [5] &&
            data["arguments"] == [[5]] &&
            data["arguments_post"] == [[5]]
    end
    rm("regression_tests_identity.data", force=true)

    @test begin
        clear()
        @record identity(5)
        @record identity("hello")
        @record identity(["hello", 7])
        create_regression_tests("identity")
        data = deserialize("regression_tests_identity.data")
        data["return_value"] == [5,"hello",["hello",7]] &&
            data["arguments"] ==      [[5],["hello"],[["hello",7]]] &&
            data["arguments_post"] == [[5],["hello"],[["hello",7]]]
    end
    rm("regression_tests_identity.data", force=true)
    rm("regression_tests_identity.jl", force=true)

end

@testset "create_regression_tests(fname) creates script with tests" begin
    rm("regression_tests_identity.jl", force=true)
    @test begin
        clear()
        @record identity(5)
        @record identity("hello")
        create_regression_tests("identity")
        "regression_tests_identity.jl" in readdir()
    end
    rm("regression_tests_identity.jl", force=true)
    @test begin
        clear()
        @record identity(5)
        @record identity("hello")
        expr = create_regression_tests("identity")
        io = IOBuffer()
        print(io, expr)
        filestring = String(take!(io))
        occursin("using Test",filestring) &&
        occursin("using Serialization",filestring) &&
        occursin("@testset for (",filestring)

    end
    rm("regression_tests_identity.jl", force=true)
    rm("regression_tests_identity.data", force=true)

end
