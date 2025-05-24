module ParametricProcessScheduler
using ParametricProcesses
using Dates

mutable struct RecurringTime
    start_time::DateTime
    interval::Dates.Period
end

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
    @info "deleted task"
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
    findmin(times)
end

function start(scheduler::Scheduler; threads::Int64 = 1)
    if threads > 1
        @info "spawning threads ..."
        add_workers!(scheduler, threads)
    end
    start_message = new_task(now(), println, "task scheduler started! (ran as task)")
    push!(schedculer.tasks, start_message)
    current_dtime = now()
    next_task, taske = next_time(current_dtime, scheduler)
    scheduler.active = true
    t = @async while scheduler.active
        current_dtime = Dates.now()
        if current_dtime >= next_task
            @info "performing task"
            assign_open!(scheduler, scheduler.jobs[taske].job)
            clean!(scheduler.jobs, scheduler.jobs[taske], taske)
            sleep(1)
            next_task, taske = next_time(current_dtime, scheduler)
        end
        yield()
    end
    w = Worker{Async}("scheduler", rand(1000:3000))
    w.active = scheduler.active
    push!(scheduler.workers, w)
    scheduler::Scheduler
end

start(tasks::Task{<:Any} ...; keyargs ...) = start(Scheduler(tasks ...; keyargs ...))

function start(path::String = pwd() * "config.conf.d"; keyargs ...)
    sched::Scheduler = read_config(path)
    start(sched; kargs ...)
end


function save_config(tasks::Vector{Task}, path::String)

end

function save_config(sch::Scheduler, path::String)

end

function parse_config_args(args::Vector{SubString{String}})
    Vector{Any}([begin 
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
        arg
    end for arg in args])
end

function read_config(path::String)
    tasks = Vector{Task}()
    for taskline in readlines(path)
        current_task = nothing
        if taskline[1] == '0'
            timeargs = split(taskline, " - ")
            taskday = DateTime([parse(Int64, e) for e in split(timeargs[1], " ")[2:end]] ...)
            timestr = timeargs[2]
            task_fend = findfirst(" ", timestr)
            fname = timestr[begin:minimum(task_fend) - 1]
            task_fn = try
                getfield(Main, Symbol(fname))
            catch e
                @warn "error in schedule configuration"
                @info "could not get function $(taskline[19:minimum(task_fend)]) (not defined in `Main`)"
                @warn e
                continue
            end
            args = parse_config_args(split(timestr[minimum(task_fend) + 1:end], "-"))
            @info args
            current_task = new_task(task_fn, taskday, args ...)
        elseif taskline[1] == '1'

        elseif taskline[1] == '2'

        else
            println(taskline[1])
            @info "skipped line"
            continue
        end
        push!(tasks, current_task)
    end
    tasks::Vector{Task}
end
#==
#    (0 denotes dated task and 1 denotes recurring)
# 7 values, representing date:
0 _ _ _ _ _ _ _ - cmd args ...
# 7 values representing date - interval ID and interval count
1 _ _ _ _ _ _ _ - _ _ cmd args-...
==#

export new_task, scheduler, RecurringTime
end # module ParametricProcessScheduler
