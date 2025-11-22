# Recorder.jl

A library of utilities to conveniently record 
the input and output of functions,
to quickly create regression/approval/characterisation tests.

## Rationale

Very often in my experience it happens that one needs to optimise,
refactor or parallelise code that does not have any tests,
or at least tests that are useful in this regard.
One might argue that such code *defines itself*,
and if we so believe, 
the correctness of a new version of the code 
can be checked with characterisation tests 
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
`JLD2` library,
it is quite trivial to do the recording in Julia
(at least for serial code).

## Examples 
### Basic usage

You need to create a test for a function `func`
which is called inside some julia code 
*that you can temporarily modify*,
and is buried down a tall call stack
or called in a loop:


```julia
using MyModule

function deep_in_the_callstack_in_nested_loops_and_without_tests()
    [...]
    res = func(a,b,c)
    [...]
end
```

In order to create a characterization test,
follow the following steps:

1. add a  `using Recorder` statement at the top of the file

   ```diff
   + using Recorder
     using MyModule
   ...
   ```

2. add `@record` in front of the function call you want to 

   ``` diff
   function deep_in_the_callstack_in_nested_loops_and_without_tests()
       [...]
   +    res = @record func(a,b,c)
   -    res = func(a,b,c)
       [...]
   end
   
   ```
   
   This will make record the input arguments, 
   the output and the values of the arguments
   after the call.  
3. If the instrumented code is in a package,
   you might also have to add `Recorder.jl` 
   to its dependencies.
   To this aim:
   1. Back up `Project.toml` and `Manifest.toml`
      of the package 
   2. Add the `Recorder` package to the depenencies
      of the package.

4. Then, with the function 

   ``` julia
   create_regression_tests("MyModule.func")
   ```

   a file can be created 
   that contains all the data for the regression test,
   plus a script that contains a `@testset` of "skeleton" regression tests
   based on that data.  

5. Check the scripts generated. 
   Very likely, they will need to be modified 
   for readability and to define proper equality conditions
   between the real return values and the expected return values 
   and between the real output argument values 
   and the expected output argument values.

   In particular:
   - if the functions you are recording act on struct types, 
     one might have to define their own equality operator,
     for example
     - to compare the structure fields by value (recursively)
     - to provide better diagnostics for failing tests
       (where is the difference?)
     - to use `isapprox` instead of `==`
   - In the case of MPI ports:
     - to add `MPI` initialization/finalization calls if necessary;
     - to add scatter/gather steps for the input/output arguments if necessary;

6. Check the tests:
   1. Check that the tests pass
   2. Check that if you modify the function under test
      the tests do not pass any more
   3. Restore the original state of the function
   
7. After the regression tests have been created
   and work as intended,
   restore the source files of the package
   to their original state.
   
8. Then recover the state of `Project.toml` 
   and of the `Manifest.toml` as they were,
   from the backup

9. Verify that there is no mention of `Recorder`
   in the project.


### Record selectively
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

### Use custom state objects 

It is possible to create your own object 
where all the calls will be stored,
Instead of using the global state inside the Recorder module:
``` julia
using Recorder
using MyModule

mystate = Recorder.State()
res = @record mystate 13:2:17 func1(a,b,c)
```

Then, it will be possible to create 
the regression test data and script 
with the `create_regression_test` function:

``` julia
create_regression_test(state=mystate,tag="batch-1")
```
which will create 
the `regression_tests_batch-1.jl`,
the `regression_tests_batch-1-func1.data` 
and the `regression_tests_batch-1-func2.data` 
files.
In `regression_tests_batch-1.jl`,
a different `@testset` will be created for each function.

This can be useful to group tests into different logically separate scenarios.

## Troubleshooting 


### Recorder not found when running instrumented code

**Problem**: `ERROR: ArgumentError: Package Recorder not found in current path`

**Solutions**:
  - Ensure Recorder is added to the project where it's used: `julia --project -e 'using Pkg;
  Pkg.add("Recorder")'`
  - When using separate test environment, activate it: `julia --project=test-utils script.jl`
  - Remember to remove Recorder from production dependencies after generating tests




## Possible features
  - [X] records input arguments, even for multiple calls
  - [X] records output values, even for multiple calls
  - [X] records values of arguments after call, even for multiple calls
  - [X] deals with functions called multiple times, 
        recording only a selected number of calls
  - [X] creates automagically code and data for regression test cases
        based on the recording
    - [ ] and the code created works out of the box (getting close)
  - [X] store state in and create regression tests from a user-defined object 
    - [ ] make it possible to use expressions for the state object
          (e.g., `mystates["first-batch"]`)
  - [ ] allow "keyword arguments" for `@record` 
        (possibly using [MacroTools.jl](https://github.com/FluxML/MacroTools.jl))
  - [ ] Use custom names for output data and script files.  
        At the moment a tag can be chosen, but not more than that.
  - [ ] the recording and clearing is thread-safe 
  - [ ] makes sure that if expressions are passed as arguments,
        these expressions are evaluated only once
  - [ ] makes sure that if expressions are passed as arguments,
        their value after the function is not evaluated again
  - [ ] make it possible to "disable" `@record` (maybe with an environment variable?)
        so that it can be left in the code without causing issues.
  - [ ] `create_regression_tests` should error if the files are already there
  - [ ] automatic value-based comparisons
 
  If you are interested in any of these or more, 
  please open an issue and start the discussion.
## Impossible features
  Some of the features in the "Possible Features" list might move here.
  - monitor side effects of functions


