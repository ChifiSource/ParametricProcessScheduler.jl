module ParametricProcessScheduler

using ParametricProcesses
using Dates

mutable struct RecurringTime
    start::DateTime
    interval::Dates.Period
end

function next_time(now::DateTime, rt::RecurringTime)
	if ref_time < rt.start_time
		return rt.start_time
	end
	delta = ref_time - rt.start_time
	n_intervals = floor(Int, Millisecond(delta) / Millisecond(rt.interval))
	return rt.start_time + (n_intervals + 1) * rt.interval
end

mutable struct Task{T <: Any} <: ParametricProcesses.AbstractJob
    time::T
    job::ParametricProcesses.ProcessJob
end

mutable struct Scheduler <: ParametricProcesses.AbstractProcessManager
    jobs::Vector{Task}
    workers::ParametricProcesses.Workers{<:Any}
    active::Bool
end

function start(scheduler::Scheduler)
    next_task = 1
    t = @async while scheduler.active

    end
end

function start(path::String = pwd() * "config")

end

function save_config(sch::Scheduler)

end


end # module ParametricProcessScheduler
