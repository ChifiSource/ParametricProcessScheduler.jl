using Test
using ParametricScheduler
using ParametricScheduler: next_time
module TestData
x = 5
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
        sleep(6)
        @test TestData.x == 14
        close(sched)
        @test length(sched.workers) == 0
    end
    @testset "threads" begin

    end
    @testset "configuration files" verbose = true begin

    end
    @testset "configuration scheduling" begin

    end
end