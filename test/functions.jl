function sample_function()
    TestData.x = 30
    @info "updated testdata x"
end

function sample2()
    touch("newval.txt")
    @info "touched newval.txt"
end