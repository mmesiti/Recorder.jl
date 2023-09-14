# Recorder.jl

A library of utilities to conveniently record 
the input and output of functions,
to quickly create regression tests.

## Examples - WIP

You need to create a regression test for a function 
which is called inside some julia code 
*that you can temporarily modify:*

```julia
    myvar = myfunc(a,b,c)
```

Just use `Recorder` and slap `@record` in front of the function call:

``` julia
using Recorder
[...]

myvar = @record myfunc(a,b,c)

[...]

```

This will make record the input arguments, the output and the values of the arguments
after the call.
Then, with the function 

``` julia
create_regression_tests("myfunc")
```

a script that contains a `@testset` of regression tests
plus a file that contains the data for the regression tests
is added.

Have I already said, it's WIP?

## Planned features
  This is somewhat tested but will probably require more work:
  - [X] records input arguments, even for multiple calls
  - [X] records output values, even for multiple calls
  - [X] records values of arguments after call, even for multiple calls
  - [X] deals with functions called multiple times, 
        recording only a selected number of calls
  - [X] creates automagically code and data for regression test cases
        based on the recording
  - [ ] the recording and clearing is thread-safe 
  - [ ] makes sure that if expressions are passed as arguments,
        these expressions are evaluated only once
  - [ ] makes sure that if expressions are passed as arguments,
        their value after the function is not evaluated again

