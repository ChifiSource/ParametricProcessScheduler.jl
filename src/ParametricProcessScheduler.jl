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

function clean!(workers::Workers{<:Any}, task::Task{<:Any}, taske::Int64)
end

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

function next_time(now::DateTime, sched::Scheduler)
    times = [next_time(now, task.time) for task in sched.jobs]
    findmin(times)
end

function start(scheduler::Scheduler)
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
    @info "started scheduler"
    scheduler::Scheduler
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

function start(path::String = pwd() * "config")

end

function save_config(sch::Scheduler)

end

export new_task, scheduler
end # module ParametricProcessScheduler
