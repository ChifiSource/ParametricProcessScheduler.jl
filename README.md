<div align="center">
  <img src="https://github.com/ChifiSource/image_dump/blob/main/parametricprocesses/parscheduler.png"></img>
</div>

`ParametricScheduler` is used to schedule recurring and one-time tasks from Julia. This fills the role of applications like `Crontab` in systems applications, only in this case facilitated through Julia and its `Dates` `Module`. These tasks can also be scaled using multi-threading and `ParametricProcesses`.
- getting started
  - [installing](#installing)
  - [docs](#docs)
- usage
  - [configuration files](#configuration-files)
  - [api](#api)
  - [threading](#threading)
#### installing
As *per usual* in [julia](https://julialang.org), installation is done using `Pkg`:
```julia
using Pkg; Pkg.add("ParametricScheduler")
```
Alternatively, add `Unstable` for the latest development updates that may occassionally be broken:
```julia
using Pkg; Pkg.add(name = "ParametricScheduler", rev = "Unstable")
```
#### docs
- We pride ourselves on having REPL-browseable documentation, use `?(ParametricScheduler)` for a full list of available functions.
- There is also [documentation on chifi docs](https://chifidocs.com/parametric/ParametricScheduler) for this package.
### configuration files
`ParametricScheduler` is primarily intended for use *through configuration files*. This package has its own unique formatting for `.cfg` files that are *relatively* straightforward to configure. Each *Task* is represented by a line inside of our `.cfg` file -- missing lines and lines starting with comments are an exception, as are some other special lines. Each `Task` line will start with a number, and this number tells the reader how that task should be read. There are four different task types:
- **0** A `DateTime` task,
- **1** a *recurring* `DateTime` task,
- **2** an **immediate task**,
- and **3**: A *recurring immediate* task.

For **0** and **1**, we start by providing the datetime associated with the command. These are 7 unique and ordered numbers, representing
- 1. Year
  2. Month
  3. Day
  4. Hour
  5. Minute
  6. Second
  7. Millisecond

For example, the following is at 5 in February, 2025:
```julia
# v 0 means datetime task
0 2025 2 1 5 0 1 0
```
following this is ` - ` and the command and arguments. The arguments are separated from the command by another space, and separated from eachother using a `-`.
```julia
0 2025 2 1 5 0 1 0 - println "hello"-"hi"-"hola"
```
Argument types are somewhat limited, arguments are only parsed as floats, integers, commands, and strings.
As for recurring events, they are very similar but also feature two additional numbers alongside the command.
```julia
1 _ _ _ _ _ _ _ - _ _ cmd args-...
```
These two additional values represent **the type of interval** and **the interval**. For the type, we use the same number classification from before:
- 1. Year
  2. Month
  3. Day
  4. Hour
  5. Minute
  6. Second
  7. Millisecond
 
For example, thirty seconds from our aforementioned date:
```julia
1 2025 2 1 5 0 1 0 - 6 30 sum 5-6
```
The codes two and three remove the dates from the beginning, and will set the date of the task to `now` -- performing the task immediately on startup, and if recurring recurring from there. `2` is non-recurring and `3` is recurring.
```julia
# 2 = do immediately...

2 cmd args-

# 3 = do recurringly at x interval

3 _ _ cmd args ...
```
Configuration files also have the ability to load modules into `mod` for multi-threading; when using functions and modules across multiple threads, it will be essential that we `use` those modules or `include` them from files before starting. For more information, see [threading](#threading). We load in our dependencies using `activate`, `using`, and `include` lines
```julia
# sample config
# activates our environment
activate .
# loads Pkg 
using Pkg
# loads `fns.jl`, containing `sampletwo`
include fns.jl
# every 7 seconds
3 6 7 sampletwo "hi! I am running!"
2 sampletwo "immediately runs"
# every 24 hours from now, as well as right now
3 4 24 Pkg.instantiate
```
### api

### threading
