# Recorder.jl

**Disclaimer: This is almost my first Julia project,
so do not take this as an example of good practices.**

A library of utilities to conveniently record 
the input and output of functions,
to quickly create regression tests.

## Rationale

Very often in my experience it happens that one needs to optimise,
refactor or parallelise code that does not have any tests,
or at least tests that are useful in this regard.
One might argue that such code *defines itself*,
and if we so believe, 
the correctness of a new version of the code 
can be checked with regression tests 
that check that, for given inputs, output and side effects 
are the same as for the old code.

Creating such tests is quite tedious. 
One possibility is to record input, output 
and side effects of the code we want to test
while it is running
(possibly only for a subset of the calls),
and create a test harness based on these data.
This requires a lot of boilerplate code for the recording
and the serialization/deserialization 
of the data.
Fortunately, thanks to the macro system and the 
`Serialization` library,
it is quite trivial to do the recording in Julia
(at least for serial code).

## Examples - WIP

You need to create a regression test for a function 
which is called inside some julia code 
*that you can temporarily modify:*

```julia
using MyModule
myvar = myfunc(a,b,c)
```

Just use `Recorder` and slap `@record` in front of the function call:

``` julia
using Recorder
using MyModule
[...]

myvar = @record myfunc(a,b,c)

[...]

```

This will make record the input arguments, 
the output and the values of the arguments
after the call.
Then, with the function 

``` julia
create_regression_tests("MyModule.myfunc")
```

one can create a file 
that contains all the data for the regression test,
plus a script that contains a `@testset` of regression tests
based on that data.  

The script itself might need some modifications.
In particular:
- if the functions you are recording act on struct types, 
  one might have to define their own equality operator,
  for example
  - to compare the structure fields by value (recursively)
  - to provide better diagnostics for failing tests
    (where is the difference?)
  - to use `isapprox` instead of `==`
- to add `MPI` initialization/finalization calls if necessary;


## Possible features
  The crossed ones are somewhat tested but not yet thoroughly.
  Have I already said, it's WIP?
  - [X] records input arguments, even for multiple calls
  - [X] records output values, even for multiple calls
  - [X] records values of arguments after call, even for multiple calls
  - [X] deals with functions called multiple times, 
        recording only a selected number of calls
  - [X] creates automagically code and data for regression test cases
        based on the recording
    - [ ] and the code created works out of the box (getting close)
  - [ ] Use custom names for output data and script files
  - [ ] the recording and clearing is thread-safe 
  - [ ] makes sure that if expressions are passed as arguments,
        these expressions are evaluated only once
  - [ ] makes sure that if expressions are passed as arguments,
        their value after the function is not evaluated again
## Impossible features
  Some of the features in the "Possible Features" list might move here.
  - monitor side effects of functions


