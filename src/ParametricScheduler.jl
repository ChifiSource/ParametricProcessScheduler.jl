module ParametricScheduler
using ParametricProcesses
using Dates
using CodeTracking

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

mutable struct Task{T <: Any} <: ParametricProcesses.AbstractJob
    time::T
    job::ParametricProcesses.ProcessJob
end

function new_task(f::Function, t::Any, args ...; keyargs ...)
    Task{typeof(t)}(t, new_job(f, args ...; keyargs ...))
end

function clean!(workers::Workers{<:Any}, task::Task{<:Any}, taske::Int64) end

function clean!(workers::Workers{<:Any}, task::Task{DateTime}, taske::Int64)
    deleteat!(workers, taske)
end

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
    sched::Scheduler = Scheduler(read_config(path) ...)
    start(sched, mods ...; keyargs ...)
end

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


function save_config(tasks::Vector{Task}, path::String = pwd() * "/config.cfg")
    open(path, "w") do o::IO
        for task in tasks
            write(o, config_str(task))
        end
    end
end

function save_config(sch::Scheduler, args ...)
    save_config(sch.jobs, args ...)
end

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

abstract type TaskIdentifier{N} end


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

function read_config(path::String)
    tasks = Vector{Task}()
    for taskline in readlines(path)
        if length(taskline) < 1
            continue
        end
        if taskline[1] == "#"
            continue
        elseif taskline[1] == "u"
            if contains(taskline, "using")

            end
        end
        current_task = read_task(TaskIdentifier{parse(Int64, taskline[1])}, taskline)
        if isnothing(current_task)
            continue
        end
        push!(tasks, current_task)
    end
    tasks::Vector{Task}
end

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

export new_task, scheduler, RecurringTime
end # module ParametricProcessScheduler
