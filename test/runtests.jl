using Test
using ParametricScheduler
using ParametricScheduler: next_time, read_task, save_config, read_config, config_str

include("functions.jl")

module TestData
x = 5
value = ""
end

@testset "Parametric Scheduler" verbose = true begin
    @testset "times" begin
        moment = now()
        rect = RecurringTime(moment, Minute(5))
        @test typeof(rect) == RecurringTime
        T = next_time(now(), rect)
        @test T == moment || T == moment + Minute(5)
        @test next_time(now(), moment) == moment
    end
    @testset "task API" begin
        moment = now()
        rect = RecurringTime(moment, Minute(5))
        new_t = new_task(println, rect, "hello tests!")
        @test typeof(new_t) == ParametricScheduler.Task{RecurringTime}
        other_t = new_task(now()) do 
           TestData.x = 5
        end
        @test typeof(other_t) == ParametricScheduler.Task{DateTime}
        sched = Scheduler(new_t, other_t)
    end
    @testset "tasks and scheduling" begin
        other_t = new_task(now()) do 
           TestData.x = 12
        end
        @test typeof(other_t) == ParametricScheduler.Task{DateTime}
        sched = ParametricScheduler.start(other_t)
        sleep(1)
        close(sched)
        sched = nothing
        @test TestData.x == 12
        other_t = new_task(RecurringTime(now(), Second(5))) do 
            TestData.x += 2
        end
        sched = ParametricScheduler.start(other_t)
        @info "(sleeping for 6 seconds)"
        sleep(6)
        @test TestData.x == 14
        close(sched)
        @test length(sched.workers) == 0
    end
    @testset "configuration files" verbose = true begin
        sched = ParametricScheduler.start("testconf.cfg", threads = 5)
        @testset "threads" begin
            @test length(sched.workers) == 5
            @test ParametricScheduler.Worker{ParametricScheduler.ParametricProcesses.Threaded} in [typeof(w) for w in sched.workers] 
        end
        @testset "configuration read" begin
            @test length(read_config("testconf.cfg")[1]) == 2
            did = false
            try
                Main.Pkg.instantiate()
                did = true
            catch e
                @warn e
            end
            @test did
            did = false
            try
                Main.sample_function()
                did = true
            catch e
                @warn e
            end
            @test did
            f = findfirst(t -> typeof(t).parameters[1] == RecurringTime, sched.jobs)
            @test ~(isnothing(f))
        end
        @testset "configuration scheduling" begin
            @test TestData.x == 30
            @info "(sleeping for 7 seconds)"
            sleep(7)
            @test isfile("newval.txt")
        end
        close(sched)
        @testset "configuration write" begin
            t_1 = new_task(println, RecurringTime(now(), Second(5)), "test task one") 
            t_2 = new_task(println, now(), "test task two") 
            new_t1 = read_task(ParametricScheduler.TaskIdentifier{1}, config_str(t_1))
            new_t2 = read_task(ParametricScheduler.TaskIdentifier{0}, config_str(t_2))
            @test typeof(new_t1).parameters[1] == RecurringTime
            @test typeof(new_t2).parameters[1] == DateTime
            save_config(Scheduler(new_t1, new_t2))
            @test isfile("config.cfg")
            tasks = ParametricScheduler.read_config("config.cfg")[1]
            @test length(tasks) == 2
            f = findfirst(t -> typeof(t).parameters[1] == RecurringTime, sched.jobs)
            @test ~(isnothing(f))
            sched = ParametricScheduler.start(tasks ...)
            @test sched.active
            @test sched.workers[1].active
            close(sched)
            @test length(sched.workers) == 0
        end
    end
end

if isfile("newval.txt")
    rm("newval.txt")
end

if isfile("config.cfg")
    rm("config.cfg")
end