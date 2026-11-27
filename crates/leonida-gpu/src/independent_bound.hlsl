// One immutable dispatch snapshot, charged for every original logical wave.
#define RS "RootConstants(num32BitConstants=2, b0), SRV(t0), UAV(u0), UAV(u1)"
cbuffer Record : register(b0) {
    uint args_offset;
    uint original_threads;
};
ByteAddressBuffer src_args : register(t0);
RWByteAddressBuffer dst_args : register(u0);
RWByteAddressBuffer budget : register(u1);
static const uint BUDGET = 1u << 27;
static const uint GROUPS = 1u << 20;

[RootSignature(RS)]
[numthreads(1, 1, 1)]
void main() {
    // Read once before any logical wave executes; it may write the original
    // buffer. No wave can alter this private snapshot through title bindings.
    uint3 groups = src_args.Load3(args_offset);
    if (any(groups > 65535u) || any(groups == 0u)
            || original_threads < 64u || original_threads > 1024u
            || (original_threads & 63u) != 0u) {
        groups = uint3(0, 0, 0);
    } else if (groups.x * groups.y > GROUPS / groups.z) {
        groups = uint3(0, 0, 0);
    }
    // Admitted dimensions have <=2^20 groups and <=1024 threads each:
    // the full original work fits uint32 even when it exceeds the budget.
    uint cost = groups.x * groups.y * groups.z * original_threads;
    bool over = false;
    if (cost != 0u) {
        uint before;
        budget.InterlockedOr(0, 0, before);
        [allow_uav_condition]
        while (before < BUDGET) {
            uint next = BUDGET - before <= cost ? BUDGET : before + cost;
            uint previous;
            budget.InterlockedCompareExchange(0, before, next, previous);
            if (previous == before) break;
            before = previous;
        }
        over = cost > BUDGET - min(before, BUDGET);
    }
    // All replays see the complete grid, or all see zero. No partial wave
    // may consume the remaining budget before a later wave is refused.
    dst_args.Store3(0, over ? uint3(0, 0, 0) : groups);
}
