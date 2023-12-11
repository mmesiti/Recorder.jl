module TestModule
export f3arg, func1, func2
function f3arg(a, b, c)
    a - b + c
end
end

function func1(a, b, c)
    a + b + c
end

function func2(a, b, c)
    a * b * c
end

module TestModule1

function f(a, b, c)
    a + b - c
end

module SubMod11
function f(a, b, c)
    a - b - c
end
end
end
