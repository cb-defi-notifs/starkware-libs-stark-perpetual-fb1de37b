# Inline functions with no locals.

# Verifies that value != 0. The proof will fail otherwise.
func assert_not_zero(value):
    %{ assert ids.value % PRIME != 0, f'assert_not_zero failed: {ids.value} = 0.' %}
    if value == 0:
        # If value == 0, add an unsatisfiable requirement.
        value = 1
    end

    return ()
end

# Verifies that a != b. The proof will fail otherwise.
func assert_not_equal(a, b):
    %{ assert (ids.a - ids.b) % PRIME != 0, f'assert_not_equal failed: {ids.a} = {ids.b}.' %}
    if a == b:
        # If a == b, add an unsatisfiable requirement.
        [fp - 1] = [fp - 1] + 1
    end

    return ()
end

# Verifies that a >= 0 (or more precisely 0 <= a < RANGE_CHECK_BOUND).
func assert_nn{range_check_ptr}(a):
    %{ assert 0 <= ids.a % PRIME < range_check_builtin.bound, f'a = {ids.a} is out of range.' %}
    a = [range_check_ptr]
    let range_check_ptr = range_check_ptr + 1
    return ()
end

# Verifies that a <= b (or more precisely 0 <= b - a < RANGE_CHECK_BOUND).
func assert_le{range_check_ptr}(a, b):
    assert_nn(b - a)
    return ()
end

# Verifies that a <= b - 1 (or more precisely 0 <= b - 1 - a < RANGE_CHECK_BOUND).
func assert_lt{range_check_ptr}(a, b):
    assert_le(a, b - 1)
    return ()
end

# Verifies that 0 <= a <= b and that a < RANGE_CHECK_BOUND.
#
# Prover assumption: b < RANGE_CHECK_BOUND.
#
# If the prover assumption isn't satisfied, The function assures that b < 2 * RANGE_CHECK_BOUND.
func assert_nn_le{range_check_ptr}(a, b):
    assert_nn(a)
    assert_le(a, b)
    return ()
end

# Asserts that value is in the range [lower, upper).
# Or more precisely:
# (0 <= value - lower < RANGE_CHECK_BOUND) and (0 <= upper - 1 - value < RANGE_CHECK_BOUND).
func assert_in_range{range_check_ptr}(value, lower, upper):
    assert_le(lower, value)
    assert_le(value, upper - 1)
    return ()
end

# Asserts that a <= b. More specifically, asserts that b - a is in the range [0, 2**250).
#
# Prover assumptions:
#    PRIME - 2**250 > 2**(250 - 128) + 1 * RC_BOUND.
func assert_le_250_bit{range_check_ptr}(a, b):
    const UPPER_BOUND = %[2**(250)%]
    const HIGH_PART_SHIFT = %[2**250 // 2**128 %]
    let low = [range_check_ptr]
    let high = [range_check_ptr + 1]
    tempvar diff = b - a
    %{
        def as_int(val):
            return val if val < PRIME // 2 else val - PRIME
        # Soundness checks.
        assert range_check_builtin.bound == 2**128
        assert ids.UPPER_BOUND == ids.HIGH_PART_SHIFT * range_check_builtin.bound

        # Correctness check.
        diff = as_int(ids.diff)
        values_msg = f'(a={as_int(ids.a)}, b={as_int(ids.b)}).'
        assert diff < ids.UPPER_BOUND, f'(b - a)={diff} is outside of the valid range. {values_msg}'
        assert PRIME - ids.UPPER_BOUND > (ids.HIGH_PART_SHIFT + 1) * range_check_builtin.bound

        assert diff >= 0, f'(b - a)={diff} < 0. {values_msg}'

        # Calculation for the assertion.
        ids.high = ids.diff // ids.HIGH_PART_SHIFT
        ids.low = ids.diff % ids.HIGH_PART_SHIFT
    %}

    # Assuming the assert below, we have
    # diff = high * HIGH_PART_SHIFT + low < (HIGH_PART_SHIFT + 1) * RC_BOUND < PRIME - UPPER_BOUND.
    # If 0 <= b < a < UPPER_BOUND then diff < 0 => diff % P = PRIME - diff > PRIME - UPPER_BOUND.
    # So given the soundness assumptions listed above it must be the case that a <= b.
    assert diff = high * HIGH_PART_SHIFT + low

    # Check that low < HIGH_PART_SHIFT.
    assert [range_check_ptr + 2] = HIGH_PART_SHIFT - low
    let range_check_ptr = range_check_ptr + 3

    return ()
end

# Splits the unsigned integer lift of a field element into the higher 128 bit and lower 128 bit.
# The unsigned integer lift is the unique integer in the range [0, PRIME) that represents the field
# element.
# For example, if value=17 * 2^128 + 8, then high=17 and low=8.
func split_felt{range_check_ptr}(value) -> (high, low):
    const MAX_HIGH = %[(PRIME - 1) >> 128%]
    const MAX_LOW = %[(PRIME - 1) & ((1 << 128) - 1)%]

    # Guess the low and high parts of the integer.
    let low = [range_check_ptr]
    let high = [range_check_ptr + 1]
    let range_check_ptr = range_check_ptr + 2

    %{
        assert PRIME < 2**256
        ids.low = ids.value & ((1 << 128) - 1)
        ids.high = ids.value >> 128
    %}
    assert value = high * %[2**128%] + low
    if high == MAX_HIGH:
        assert_le(low, MAX_LOW)
    else:
        assert_le(high, MAX_HIGH - 1)
    end
    return (high=high, low=low)
end

# Asserts that the unsigned integer lift (as a number in the range [0, PRIME)) of a is lower than
# or equal to that of b.
# See split_felt() for more details.
func assert_le_felt{range_check_ptr}(a, b):
    %{
        assert (ids.a % PRIME) <= (ids.b % PRIME), \
            f'a = {ids.a % PRIME} is not less than or equal to b = {ids.b % PRIME}.'
    %}
    alloc_locals
    let (local a_high, local a_low) = split_felt(a)
    let (b_high, b_low) = split_felt(b)

    if a_high == b_high:
        assert_le(a_low, b_low)
        return ()
    end
    assert_le(a_high, b_high)
    return ()
end

# Asserts that the unsigned integer lift (as a number in the range [0, PRIME)) of a is lower than
# that of b.
func assert_lt_felt{range_check_ptr}(a, b):
    %{
        assert (ids.a % PRIME) < (ids.b % PRIME), \
            f'a = {ids.a % PRIME} is not less than b = {ids.b % PRIME}.'
    %}
    alloc_locals
    let (local a_high, local a_low) = split_felt(a)
    let (b_high, b_low) = split_felt(b)

    if a_high == b_high:
        assert_lt(a_low, b_low)
        return ()
    end
    assert_lt(a_high, b_high)
    return ()
end

# Returns the absolute value of value.
# Prover asumption: -rc_bound < value < rc_bound.
func abs_value{range_check_ptr}(value) -> (abs_value):
    %{
        from starkware.cairo.common.math_utils import is_positive
        memory[ap] = 1 if is_positive(
            value=ids.value, prime=PRIME, rc_bound=range_check_builtin.bound) else 0
    %}
    jmp is_positive if [ap] != 0; ap++
    tempvar new_range_check_ptr = range_check_ptr + 1
    tempvar abs_value = value * (-1)
    [range_check_ptr] = abs_value
    let range_check_ptr = new_range_check_ptr
    return (abs_value=abs_value)

    is_positive:
    [range_check_ptr] = value
    let range_check_ptr = range_check_ptr + 1
    return (abs_value=value)
end

# Returns the sign of value: -1, 0 or 1.
# Prover asumption: -rc_bound < value < rc_bound.
func sign{range_check_ptr}(value) -> (sign):
    if value == 0:
        return (sign=0)
    end

    %{
        from starkware.cairo.common.math_utils import is_positive
        memory[ap] = 1 if is_positive(
            value=ids.value, prime=PRIME, rc_bound=range_check_builtin.bound) else 0
    %}
    jmp is_positive if [ap] != 0; ap++
    assert [range_check_ptr] = value * (-1)
    let range_check_ptr = range_check_ptr + 1
    return (sign=-1)

    is_positive:
    [range_check_ptr] = value
    let range_check_ptr = range_check_ptr + 1
    return (sign=1)
end

# Returns q and r such that:
#  0 <= q < rc_bound, 0 <= r < div and value = q * div + r.
#
# Assumption: 0 < div <= PRIME / rc_bound.
# Prover assumption: value / div < rc_bound.
#
# The value of div is restricted to make sure there is no overflow.
# q * div + r < (q + 1) * div <= rc_bound * (PRIME / rc_bound) = PRIME.
func unsigned_div_rem{range_check_ptr}(value, div) -> (q, r):
    let r = [range_check_ptr]
    let q = [range_check_ptr + 1]
    let range_check_ptr = range_check_ptr + 2
    %{
        assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div)} is out of the valid range.'
        ids.q, ids.r = divmod(ids.value, ids.div)
    %}
    assert_le(r, div - 1)

    assert value = q * div + r
    return (q, r)
end

# Returns q and r such that. -bound <= q < bound, 0 <= r < div and value = q * div + r.
# value < PRIME / 2 is considered positive and value > PRIME / 2 is considered negative.
#
# Assumptions:
#   0 < div <= PRIME / (rc_bound)
#   bound <= rc_bound / 2.
# Prover assumption:   -bound <= value / div < bound.
#
# The values of div and bound are restricted to make sure there is no overflow.
# q * div + r <  (q + 1) * div <=  rc_bound / 2 * (PRIME / rc_bound)
# q * div + r >=  q * div      >= -rc_bound / 2 * (PRIME / rc_bound)
func signed_div_rem{range_check_ptr}(value, div, bound) -> (q, r):
    let r = [range_check_ptr]
    let biased_q = [range_check_ptr + 1]  # == q + bound.
    let range_check_ptr = range_check_ptr + 2
    %{
        def as_int(val):
            return val if val < PRIME // 2 else val - PRIME

        assert 0 < ids.div <= PRIME // range_check_builtin.bound, \
            f'div={hex(ids.div)} is out of the valid range.'

        assert ids.bound <= range_check_builtin.bound // 2, \
            f'bound={hex(ids.bound)} is out of the valid range.'

        int_value = as_int(ids.value)
        q, ids.r = divmod(int_value, ids.div)

        assert -ids.bound <= q < ids.bound, \
            f'{int_value} / {ids.div} = {q} is out of the range [{-ids.bound}, {ids.bound}).'

        ids.biased_q = q + ids.bound
    %}
    let q = biased_q - bound
    assert value = q * div + r
    assert_le(r, div - 1)
    assert_le(biased_q, 2 * bound - 1)
    return (q, r)
end
