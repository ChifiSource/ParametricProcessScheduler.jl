module ParametricScheduler
using ParametricProcesses
using Dates
using Pkg
import Base: close

"""
```julia
mutable struct RecurringTime
```
- `start_time`**::Dates.DateTime**
- `interval`**::Dates.Period**

The `RecurringTime` object is used to create recurring event times. Like `DateTime`, 
a `RecurringTime` may be passed to `new_task` to create a new `Task`. The `Task` holds 
the time type as a parameter. `RecurringTime` will make the task occur continuously until interrupted.

`RecurringTime` is created by providing a `start_time` and an interval. An interval is 
one of the 7 interval options,
- `Year`, `Month`, `Day`, `Hour`, `Minute`, `Second`, and `Millisecond`

as well as a starting `DateTime`
```julia
RecurringTime(start_time::Dates.DateTime, interval::Dates.Period)
```
```julia
using ParametricScheduler

                            # now and then every 10 seconds after that
time_for_task = RecurringTime(now(), Second(10))
```
- See also: `next_time`, `start`, `Task`, `new_task`, `Dates.DateTime`, `Scheduler`
"""
mutable struct RecurringTime
    start_time::DateTime
    interval::Dates.Period
end

"""
```julia
next_time(time::DateTime, args ...) -> ::DateTime
# also returns the enumeration of the next time:
next_time(time::DateTime, schedule::Schedule) -> ::Tuple{DateTime, Int64}
```
`next_time` is used to get the next time corresponding to a *task* **or** a `Scheduler`. 
For example, when a `DateTime` is passed as the second argument `next_time` simply returns that 
date. This changes when `next_time` is called on a `RecurringTime`, as this time it passed the 
recurring time closest to our current time.

The `next_time(::DateTime, ::Schedule)` binding works a little differently... This `Method` will 
return a `DateTime`, as well as the enumeration of task that corresponds to that time.
```julia
next_time(now::DateTime, date::DateTime)
next_time(now::DateTime, date::RecurringTime)
next_time(now::DateTime, sched::Schedule)
```
- See also: `Task`, `RecurringTime`, `new_task`
"""
function next_time end

next_time(now::DateTime, date::DateTime) = date

function next_time(now::DateTime, rt::RecurringTime)
	if now < rt.start_time
		return rt.start_time
	end
	delta = now - rt.start_time
	n_intervals = floor(Int, Millisecond(delta) / Millisecond(rt.interval))
	return rt.start_time + (n_intervals + 1) * rt.interval
end

"""
```julia
mutable struct Task{T <: Any} <: ParametricProcesses.AbstractJob
```
- `time`**T**
- `job`**::ParametricProcesses.ProcessJob**

The `Task` is used to represent time-bound jobs for a `Scheduler`. The `Task` will 
hold its time type (`RecurringTime` or `DateTime`) as a parameter. This constructor 
isn't usually called directly; instead, see `new_task`.
```julia
Task{T}(time)
```
example
```julia
mytask = new_task(println, now(), "hello world!")
```
- See also: `new_task`, `Scheduler`, `start`, `RecurringTime`, `DateTime`
"""
mutable struct Task{T <: Any} <: ParametricProcesses.AbstractJob
    time::T
    job::ParametricProcesses.ProcessJob
end

"""
```julia
new_task(f::Function, t::Any, args ...; keyargs ...) -> ::Task{<:Any}
```
Creates a new task with `t` as the time and a new job created from `f` and 
`args`/`keyargs`. `t` will be a time object -- either `Dates.DateTime` or 
`RecurringTime`.
```julia
mytask = new_task(println, now() + Minute(10), "it has been 10 minutes.")

mytask = new_task(now() + Minute(10), 1, 1) do (n1, n2)
    println(n1, n2)
end
```
- See also: `Scheduler`, `start`, `Task`, `RecurringTime`, `DateTime`
"""
function new_task(f::Function, t::Any, args ...; keyargs ...)
    Task{typeof(t)}(t, new_job(f, args ...; keyargs ...))
end

"""
```julia
clean!(workers::Workers{<:Any}, task::Task{<:Any}, taske::Int64) -> ::Nothing
```
Cleans any extra data from a completed task and/or deletes the task, does nothing 
for a recurring task. Called after tasks are run.
```julia

```
- See also: `Scheduler`, `start`, `Task`, `RecurringTime`, `DateTime`
"""
function clean!(workers::Workers{<:Any}, task::Task{<:Any}, taske::Int64) end

function clean!(workers::Workers{<:Any}, task::Task{DateTime}, taske::Int64)
    deleteat!(workers, taske)
end

"""
```julia
mutable struct Scheduler <: ParametricProcesses.AbstractProcessManager
```
- `jobs`**::Vector{Task}**
- `workers`**::Vector{Worker}**
- `active`**::Bool**

The `Scheduler` is a `ProcessManager` that performs jobs (optionally, across multiple threads,) at set times. 
A `Scheduler` can be created by calling `start`, or providing a number of tasks to the `Scheduler`.
```julia
Scheduler(tasks::Task ...)
```
example
```julia
using ParametricScheduler

my_scheduler = ParametricScheduler.start("myconfig.cfg")

main_task = new_task(+, now(), 5, 5)
                                # vv every 5 minutes from now
second_task = new_task(print, RecurringTime(now(), Minute(5)), "task complete")

my_tasks = [main_task]

second_scheduler = ParametricScheduler.start(my_tasks ...)

third_scheduler = Scheduler(my_tasks ...)
```
- See also: `Task`, `new_task`, `start`
"""
mutable struct Scheduler <: ParametricProcesses.AbstractProcessManager
    jobs::Vector{Task}
    workers::Vector{Worker}
    active::Bool
    Scheduler(tasks::Task ...) = new([tasks ...], Vector{Worker}(), false)
end

function assign_open!(pm::Scheduler, job::ParametricProcesses.AbstractJob; not = Async)
    ws = pm.workers
    ws = filter(w -> typeof(w) != Worker{not}, ws)
    open = findfirst(w -> ~(w.active), ws)
    if ~(isnothing(open))
        w = ws[open]
        assign!(w, job)
        return([w.pid])
    end
    job.f(job.args ...; job.kwargs ...)
end

function next_time(now::DateTime, sched::Scheduler)
    times = [next_time(now, task.time) for task in sched.jobs]
    if length(times) == 0
        return(0, 0)
    end
    enumer = findmin(times)
    return(enumer)
end

"""
```julia
start(args ..., mods ...; threads::Int64 = 1, async::Bool = true) -> ::Scheduler
```
Starts a `Schedule` and begins scheduling tasks. Opposite to `close`. The schedular 
may run asynchronously, or not. Our first positional argument will be some way to build our tasks, 
be it a `Scheduler` holding the tasks, a file path from which we read the tasks, or the tasks themselves. 
`threads` may be provided to enable task distribution across a certain number of Julia workers. This will 
**require** that all dependencies are appropriated with `mods`. `mods` is exclusively used for 
loading dependencies across threads for multi-threading, with `threads` set to 1 it does nothing.

For modules, simply provide the `Module` as part of `mods` in the extended arguments. 
For files, provide a `String` leading to the file's file path to `mods`. Note that functions simply defined in `Main` will not transfer across 
multiple threads, we will *need* to provide `mods` or our workers will not have our functions. Note 
that a provided `Module` also *must be a project*. Note that we only need to provide `mods` 
if we are using multi-threading.
```julia
start(scheduler::Scheduler, mods::Any ...; threads::Int64 = 1, async::Bool = true)
start(path::String = pwd() * "config.cfg", mods::Any ...; keyargs ...)
```
```julia
using ParametricScheduler

ParametricScheduler.start("config.cfg", "functions_for_config.jl", TOML)
```
- See also: `new_task`, `Task`, `DateTime`, `RecurringTime`, `Scheduler`
"""
function start(scheduler::Scheduler, mods::Any ...; threads::Int64 = 1, async::Bool = true)
    if threads > 1
        @info "spawning threads ..."
        scheduler.workers = ParametricProcesses.create_workers(threads, ParametricProcesses.Threaded)
        modstr = ""
        for mod in mods 
            if mod isa AbstractString
                if contains(mod, ".jl")
                    @everywhere include_string(Main, $(read(mod, String)))
                    continue
                end
            end
            modstr = modstr * "using $mod"
        end
        Main.eval(Meta.parse("""using ParametricScheduler: @everywhere; @everywhere begin
            using Dates
            $modstr
        end"""))
	end
    start_message = new_task(println, now() - Year(100), "task scheduler started! (ran as task)")
    insert!(scheduler.jobs, 1, start_message)
    current_dtime = now()
    next_task, taske = next_time(current_dtime, scheduler)
    scheduler.active = true
    if ~(async)
        while scheduler.active
            current_dtime = Dates.now()
            if current_dtime >= next_task
                try
                    assign_open!(scheduler, scheduler.jobs[taske].job)
                catch e
                    @warn "error in task $taske"
                    @warn e
                end
                clean!(scheduler.jobs, scheduler.jobs[taske], taske)
                next_task, taske = next_time(current_dtime, scheduler)
                if taske == 0
                    break
                end
            end
        end
        return scheduler
    end
    t = @async while scheduler.active
        current_dtime = Dates.now()
        if current_dtime >= next_task
            try
                assign_open!(scheduler, scheduler.jobs[taske].job)
            catch e
                throw(e)
            end
            clean!(scheduler.jobs, scheduler.jobs[taske], taske)
            next_task, taske = next_time(current_dtime, scheduler)
            if taske == 0
                break
            end
        end
        yield()
    end
    w = Worker{Async}("scheduler", rand(1000:3000))
    w.active = scheduler.active
    push!(scheduler.workers, w)
    scheduler::Scheduler
end

function start(path::String = pwd() * "config.cfg", mods::Any ...; keyargs ...)
    modstr = ""
    for mod in mods 
        if mod isa AbstractString
            if contains(mod, ".jl")
                @everywhere include_string(Main, $(read(mod, String)))
                continue
            end
        end
        modstr = modstr * "using $mod"
    end
    Base.eval(Main, Meta.parse(modstr))
    ts, cfg_mods = read_config(path)
    sched::Scheduler = Scheduler(ts ...)
    start(sched, mods ..., cfg_mods ...; keyargs ...)
end

"""
```julia
config_str(task::Task) -> ::String
```
Creates output for a configuration file from a `Task`. Used internally by `save_config` 
    to save configurations.
```julia
config_str(task::Task{DateTime})
config_str(task::Task{RecurringTime})
```
- See also: `save_config`, `start`, `Scheduler`, `Task`, `new_task`
"""
function config_str(task::Task{DateTime})
    # 0 _ _ _ _ _ _ _ - cmd args ...
    d = task.time
    jb_args = join(("\"$arg\"" for arg in task.job.args), "-")
    *("0 $(year(d)) $(month(d)) $(hour(d)) $(minute(d)) $(second(d)) $(millisecond(d))", 
    " - $(task.job.f) $jb_args")
end

function config_str(task::Task{RecurringTime})
    # 1 _ _ _ _ _ _ _ - _ _ cmd args-...
    d = task.time.start_time
    intervals = [Year, Month, Day, Hour, Minute, Second, Millisecond]
    T = typeof(task.interval)
    int_num = findfirst(y -> y == T, intervals)
    
    jb_args = join(("\"$arg\"" for arg in task.job.args), "-")
    *("1 $(year(d)) $(month(d)) $(hour(d)) $(minute(d)) $(second(d)) $(millisecond(d))", 
    " - $int_num $(task.interval.value) $(task.job.f) $jb_args")
end

"""
```julia
save_config(tasks::Vector{Task}, path::String = pwd() * "/config.cfg") -> ::Nothing
save_config(sch::Scheduler, args ...) -> ::Nothing
```
Writes a task to a configuration file at `path`. Do note that this will require an 
import or include of your functions. Also note that only `Ints`, `Floats`, `Commands`, 
and `Strings` will be parsed back.
- See also: `config_str`, `parse_config_args`, `new_task`, `read_task`, `start`
"""
function save_config(tasks::Vector{Task}, path::String = pwd() * "/config.cfg")
    open(path, "w") do o::IO
        for task in tasks
            write(o, config_str(task))
        end
    end
    nothing::Nothing
end

save_config(sch::Scheduler, args ...) = save_config(sch.jobs, args ...)

"""
```julia
parse_config_args(args::Vector{SubString{String}}) -> ::Vector{Any}
```
Parses the 'argument' portion of a `ParametricScheduler` `.cfg` file. 
Returns the arguments, vectorized as their appropriate types.
- See also: `save_config`, `read_task`, `read_config`, `Scheduler`, `start`
"""
function parse_config_args(args::Vector{SubString{String}})
    filter(x -> ~(isnothing(x)), Vector{Any}([begin 
        if contains(arg, "'")
            arg = replace(arg, "'" => "")
            arg = `$arg`
        elseif contains(arg, "\"")
            arg = replace(arg, "\"" => "")
        else
            try
                arg = parse(Float64, arg)
            catch
                try
                    arg = parse(Float64, arg)
                catch
                end
            end
        end
        argcheck = findfirst(x::Char -> x != ' ', arg)
        if isnothing(argcheck)
            nothing
        else
            arg
        end
    end for arg in args]))
end

"""
```julia
abstract TaskIdentifier{N}
```
The `TaskIdentifier` is used by the `.cfg` file to read new format types parametrically. 
Keep in mind that each number is unique and may only be used once. This is primarily how 
`ParametricScheduler` loads different task types from files. This function is primarily used 
by `read_task.`
```julia
# consistencies
raw::String
```
- See also: `read_task`, `read_config`, `start`, `Scheduler`, `RecurringTime`, `Task`
"""
abstract type TaskIdentifier{N} end

"""
```julia
read_task(t::Type{TaskIdentifier{<:Any}}, taskline::String) -> ::Task{<:Any}
```
Reads a line of text (`taskline`) into a new `Task` using the parameters set by the task 
type, `t`.
```julia
read_task(t::Type{TaskIdentifier{0}}, taskline::String) -> ::Task{DateTime}
read_task(t::Type{TaskIdentifier{1}}, taskline::String) -> ::Task{RecurringTime}
read_task(t::Type{TaskIdentifier{2}}, taskline::String) -> ::Task{DateTime}
read_task(t::Type{TaskIdentifier{3}}, taskline::String) -> ::Task{RecurringTime}
```
```julia
# simple read example:
for x in readlines(myfile.cfg)
    read_task(TaskIdentifier{x[1]}, x)
end
```
- See also: `TaskIdentifier`, `Task`, `start`, `Task`
"""
function read_task(t::Type{TaskIdentifier{0}}, taskline::String)
    timeargs = split(taskline, " - ")
    taskday = DateTime([parse(Int64, e) for e in split(timeargs[1], " ")[2:end]] ...)
    timestr = timeargs[2]
    task_fend = findfirst(" ", timestr)
    if isnothing(task_fend)
        task_fend = length(timestr)
    end
    fname = timestr[begin:minimum(task_fend) - 1]
    task_fn = try
        getfield(Main, Symbol(fname))
    catch e
        @warn "error in schedule configuration"
        @info "could not get function $(taskline[19:minimum(task_fend)]) (not defined in `Main`)"
        @warn e
        return(nothing)
    end
    args = parse_config_args(split(timestr[minimum(task_fend) + 1:end], "-"))
    new_task(task_fn, taskday, args ...)::Task{DateTime}
end

function close(sched::Scheduler)
    @info "closing scheduler"

end

function read_task(t::Type{TaskIdentifier{1}}, taskline::String)
    timeargs = split(taskline, " - ")
    taskday = DateTime([parse(Int64, e) for e in split(timeargs[1], " ")[2:end]] ...)
    rec_line = timeargs[2]
    select_end = findfirst(" ", rec_line)
    select_end = minimum(select_end)
    interval_end = findnext(" ", rec_line, select_end + 1)
    interval_end = minimum(interval_end)
    task_fend = findnext(" ", rec_line, interval_end + 1)
    if isnothing(task_fend)
        task_fend = length(timestr)
    end
    task_fend = minimum(task_fend)
    fname = rec_line[interval_end + 1:task_fend - 1]
    task_fn = try
        getfield(Main, Symbol(fname))
    catch e
        @warn "error in schedule configuration"
        @info "could not get function $(taskline[19:minimum(task_fend)]) (not defined in `Main`)"
        @warn e
        return(nothing)
    end
    args = parse_config_args(split(rec_line[task_fend + 1:end], "-"))
    intervals = [Year, Month, Day, Hour, Minute, Second, Millisecond]
    interval = intervals[parse(Int64, rec_line[begin:select_end])](parse(Int64, 
        rec_line[select_end + 1:interval_end - 1]))
    new_time = RecurringTime(taskday, 
    interval)
    new_task(task_fn, new_time, args ...)::Task{RecurringTime}
end

function read_task(t::Type{TaskIdentifier{2}}, taskline::String)
    taskline = taskline[3:end]
    task_fend = findfirst(" ", taskline)
    if isnothing(task_fend)
        task_fend = length(timestr)
    end
    task_fend = minimum(task_fend)
    fname = taskline[begin:task_fend - 1]
    task_fn = try
        getfield(Main, Symbol(fname))
    catch e
        @warn "error in schedule configuration"
        @info "could not get function $(taskline[19:minimum(task_fend)]) (not defined in `Main`)"
        @warn e
        return(nothing)
    end
    args = parse_config_args(split(taskline[task_fend + 1:end], "-"))
    new_task(task_fn, now(), args ...)
end

function read_task(t::Type{TaskIdentifier{3}}, taskline::String)
    taskline = taskline[3:end]
    taskday = now()
    select_end = findfirst(" ", taskline)
    select_end = minimum(select_end)
    interval_end = findnext(" ", taskline, select_end + 1)
    interval_end = minimum(interval_end)
    task_fend = findnext(" ", taskline, interval_end + 1)
    if isnothing(task_fend)
        task_fend = length(timestr)
    end
    task_fend = minimum(task_fend)
    fname = taskline[interval_end + 1:task_fend - 1]
    task_fn = try
        getfield(Main, Symbol(fname))
    catch e
        @warn "error in schedule configuration"
        @info "could not get function $(taskline[19:minimum(task_fend)]) (not defined in `Main`)"
        @warn e
        return(nothing)
    end
    args = parse_config_args(split(taskline[task_fend + 1:end], "-"))
    intervals = [Year, Month, Day, Hour, Minute, Second, Millisecond]
    interval = intervals[parse(Int64, taskline[begin:select_end])](parse(Int64, 
        taskline[select_end + 1:interval_end - 1]))
    new_time = RecurringTime(taskday, 
    interval)
    new_task(task_fn, new_time, args ...)::Task{RecurringTime}
end

"""
```julia
read_config(path::String) -> ::Tuple{Vector{Task}, Vector{String}}
```
Reads the configuration file format. Configuration file key:
```julia
#==
#    (0 denotes dated task and 1 denotes recurring)
# 7 values, representing date:
# (Year, Month, Day, Hour, Minute, Second, Millisecond)

0 _ _ _ _ _ _ _ - cmd args ...

# 7 values representing date - interval ID and interval count

1 _ _ _ _ _ _ _ - _ _ cmd args-...

# 2 = do immediately...

2 cmd args-

# 3 = do recurringly at x interval

3 _ _ cmd args ...
==#
```
A shorter way to do this is to call `start` directly with your path!
- See also: `new_task`, `start`, `Scheduler`, `Task`, `RecurringTime`, `DateTime`
"""
function read_config(path::String)
    tasks = Vector{Task}()
    mods::Vector{String} = Vector{String}()
    for taskline in readlines(path)
        if length(taskline) < 1
            continue
        end
        if taskline[1] == '#'
            continue
        elseif taskline[1] == 'u'
            if contains(taskline, "using")
                path = split(taskline, " ")
                push!(mods, path[2])
            end
            continue
        elseif taskline[1] == 'i'
            if contains(taskline, "include")
                path = split(taskline, " ")
                if length(path) < 2
                    throw("error in include: $taskline")
                end
                Main.eval(Meta.parse("""include("$(path[2])")"""))
                push!(mods, path[2])
            end
            continue
        elseif taskline[1] == 'a'
            if contains(taskline, "activate")
                path = split(taskline, " ")
                if length(path) < 2
                    throw("error on project activation: $taskline")
                end
                Pkg.activate(replace(path[2], " " => ""))
            end
            continue
        end
        current_task = read_task(TaskIdentifier{parse(Int64, taskline[1])}, taskline)
        if isnothing(current_task)
            continue
        end
        push!(tasks, current_task)
    end
    return(tasks, mods)
end

export new_task, scheduler, RecurringTime
end # module ParametricProcessScheduler
