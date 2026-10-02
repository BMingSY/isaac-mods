-- A forgiven decrease becomes part of the input for the next increase.
-- Store the carried amount BEFORE the current multiplier, so a later x2
-- also multiplies the retained amount, instead of only the vanilla raw stat.
local rebase = {}

function rebase.isFinite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

function rebase.update(previous, raw, multiplier, initialPeak)
    if not rebase.isFinite(raw) then
        return previous
    end
    if not rebase.isFinite(multiplier) or multiplier < 0.000001 then
        multiplier = previous and previous.multiplier or 1
    end

    local carry = previous and previous.carry or 0
    local peak = previous and previous.peak or initialPeak or raw
    local candidate = raw + carry * multiplier
    -- Native stats are single-precision floats. Ignore rounding noise from
    -- repeated cache calculations, especially converting tear delay to TPS.
    local tolerance = math.max(0.00001, math.abs(peak) * 0.000001)
    if candidate > peak + tolerance then
        peak = candidate
    elseif candidate < peak - tolerance then
        carry = (peak - raw) / multiplier
    end
    return {peak = peak, carry = math.max(0, carry), multiplier = multiplier}
end

return rebase
