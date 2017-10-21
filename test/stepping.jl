
using ASTInterpreter2
using Base.Meta
using DebuggerFramework: execute_command, dummy_state

immutable DummyState; end
Base.LineEdit.transition(s::DummyState, _) = nothing

# Steps through the whole expression using `s`
function step_through(frame)
    state = DebuggerFramework.dummy_state([frame])
    while !isexpr(ASTInterpreter2.pc_expr(state.stack[end]), :return)
        execute_command(state, state.stack[1], Val{:s}(), "s")
    end
    return ASTInterpreter2.lookup_var_if_var(state.stack[end], ASTInterpreter2.pc_expr(state.stack[end]).args[1])
end

@assert step_through(ASTInterpreter2.enter_call_expr(:($(+)(1,2.5)))) == 3.5
@assert step_through(ASTInterpreter2.enter_call_expr(:($(sin)(1)))) == sin(1)
@assert step_through(ASTInterpreter2.enter_call_expr(:($(gcd)(10,20)))) == gcd(10, 20)

# Step into generated functions
@generated function generatedfoo(T)
    :(return $T)
end
callgenerated() = generatedfoo(1)
frame = ASTInterpreter2.enter_call_expr(:($(callgenerated)()))
state = dummy_state([frame])

# Step into the generated function itself
execute_command(state, state.stack[1], Val{:sg}(), "sg")

# Should now be in generated function
execute_command(state, state.stack[1], Val{:finish}(), "finish")

# Now finish the regular function
execute_command(state, state.stack[1], Val{:finish}(), "finish")

@assert isempty(state.stack)


# Optional arguments
function optional(n = sin(1))
    x = asin(n)
    cos(x)
end

frame = ASTInterpreter2.enter_call_expr(:($(optional)()))
state = dummy_state([frame])
# First call steps in
execute_command(state, state.stack[1], Val{:n}(), "n")
# cos(1.0)
execute_command(state, state.stack[1], Val{:n}(), "n")
# return
execute_command(state, state.stack[1], Val{:n}(), "n")

@assert isempty(state.stack)

# Macros
macro insert_some_calls()
    esc(quote
        x = sin(b)
        y = asin(x)
        z = sin(y)
    end)
end

# Work around the fact that we can't detect macro expansions if the macro
# is defined in the same file
include_string("""
function test_macro()
    a = sin(5)
    b = asin(a)
    @insert_some_calls
    z
end
""","file.jl")

frame = ASTInterpreter2.enter_call_expr(:($(test_macro)()))
state = dummy_state([frame])
# a = sin(5)
execute_command(state, state.stack[1], Val{:n}(), "n")
# b = asin(5)
execute_command(state, state.stack[1], Val{:n}(), "n")
# @insert_some_calls
execute_command(state, state.stack[1], Val{:n}(), "n")
# TODO: Is this right?
execute_command(state, state.stack[1], Val{:n}(), "n")
# return z
execute_command(state, state.stack[1], Val{:n}(), "n")
execute_command(state, state.stack[1], Val{:n}(), "n")
@test isempty(state.stack)

# Test stepping into functions with keyword arguments
f(x; b = 1) = x+b
g() = f(1; b = 2)
frame = ASTInterpreter2.enter_call_expr(:($(g)()));
state = dummy_state([frame])
# Step to the actual call
execute_command(state, state.stack[1], Val{:nc}(), "nc")
execute_command(state, state.stack[1], Val{:nc}(), "nc")
execute_command(state, state.stack[1], Val{:nc}(), "nc")
# Step in
execute_command(state, state.stack[1], Val{:s}(), "s")
# Should get out in two steps
execute_command(state, state.stack[1], Val{:finish}(), "finish")
execute_command(state, state.stack[1], Val{:finish}(), "finish")
@assert isempty(state.stack)

# Test stepping into functions with exception frames
function f_exc()
    try
    catch err
    end
end

function g_exc()
    try
        error()
    catch err
        return err
    end
end

stack = @make_stack f_exc()
state = dummy_state(stack)

execute_command(state, state.stack[1], Val{:n}(), "n")
@assert isempty(state.stack)

stack = @make_stack g_exc()
state = dummy_state(stack)

execute_command(state, state.stack[1], Val{:n}(), "n")
execute_command(state, state.stack[1], Val{:n}(), "n")
@assert isempty(state.stack)
@assert state.overall_result isa ErrorException

# Test throwing exception across frames
function f_exc_inner()
    error()
end

function f_exc_outer()
    try
        f_exc_inner()
    catch err
        return err
    end
end

stack = @make_stack f_exc_outer()
state = dummy_state(stack)

execute_command(state, state.stack[1], Val{:s}(), "s")
execute_command(state, state.stack[1], Val{:n}(), "n")
execute_command(state, state.stack[1], Val{:n}(), "n")
@assert isempty(state.stack)
@assert state.overall_result isa ErrorException

# Test that symbols don't get an extra QuoteNode
f_symbol() = :limit => true

stack = @make_stack f_symbol()
state = dummy_state(stack)

execute_command(state, state.stack[1], Val{:s}(), "s")
execute_command(state, state.stack[1], Val{:finish}(), "finish")
execute_command(state, state.stack[1], Val{:finish}(), "finish")
@assert isempty(state.stack)
@assert state.overall_result == f_symbol()