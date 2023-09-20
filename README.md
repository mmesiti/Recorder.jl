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
One possibility is to "instrument" the code 
to record input, output 
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

Imagine you need to create a regression test for a function `func`
which is called inside some julia code 
*that you can temporarily modify*,
and might be buried down a tall call stack
or called in a loop:


```julia
using MyModule

function deep_in_the_callstack_in_nested_loops_and_without_tests()
    [...]
    res = func(a,b,c)
    [...]
end
```

Just use `Recorder` and slap `@record` in front of the function call:

``` julia
using Recorder
using MyModule

function deep_in_the_callstack_in_nested_loops_and_without_tests()
    [...]
    res = @record func(a,b,c)
    [...]
end

```

This will make record the input arguments, 
the output and the values of the arguments
after the call.  
In the case where the function we want to record 
is buried deep into a call stack or in a loop,
the input/output of  all `@record`ed call to `func` 
will all be saved. This might be expensive. 
To record only some calls, we can specify a range:

``` julia
using Recorder
using MyModule

function deep_in_the_callstack_in_nested_loops_and_without_tests()
    [...]
    res = @record 13:2:17 func(a,b,c)
    [...]
end
```

In this case, `@record` will keep track 
of how many times we have called the function,
and record only the calls in the range
(in the example, the 13th, the 15th and the 17th).

Then, with the function 

``` julia
create_regression_tests("Module.func")
```

a file can be created 
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

After the regression tests have been created,
you can remove all the references to `Recorder` from your code,
and use the recorded data and the modified scripts in your test suite.

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
  - [ ] make it possible to "disable" `@record` (maybe with an environment variable?)
        so that it can be left in the code without causing issues.
  - [ ] `create_regression_tests` should error if the files are already there
  - [ ] automatic value-based comparisons
## Impossible features
  Some of the features in the "Possible Features" list might move here.
  - monitor side effects of functions


