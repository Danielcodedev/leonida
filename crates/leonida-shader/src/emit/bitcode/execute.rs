//! CPU execution of the small integer control-flow modules used by lowering tests.

use super::*;

pub(crate) struct Execution {
    pub blocks: Vec<usize>,
    pub values: HashMap<V, u32>,
    pub discarded: bool,
}

fn word(m: &Module, values: &HashMap<V, u32>, v: V) -> u32 {
    match v {
        V::Const(i) => match m.consts[i as usize].1 {
            Const::Int(n) => n as u32,
            _ => panic!("expected integer constant"),
        },
        _ => *values.get(&v).expect("value must dominate its use"),
    }
}

/// Check every phi against the actual predecessor blocks, including edges not executed.
pub(crate) fn check_phis(m: &Module) {
    for (b, block) in m.blocks.iter().enumerate() {
        let mut predecessors: Vec<_> = m
            .blocks
            .iter()
            .enumerate()
            .filter_map(|(from, block)| successors(block.term).contains(&b).then_some(from))
            .collect();
        predecessors.sort_unstable();
        for &id in &block.phis {
            let Op::Phi(incoming) = &m.insts[id as usize].op else {
                panic!("not a phi");
            };
            let mut from: Vec<_> = incoming.iter().map(|(_, from)| *from).collect();
            from.sort_unstable();
            assert_eq!(from, predecessors, "phi {id} in block {b}");
        }
    }
}

/// Interpret the emitted operations, not a second implementation of the lowering rules.
/// Unknown operations fail the test; a step budget catches missing loop guards.
pub(crate) fn run(m: &Module, budget: usize) -> Execution {
    let mut result = Execution {
        blocks: Vec::new(),
        values: HashMap::new(),
        discarded: false,
    };
    let (mut at, mut previous) = (0, None);
    for _ in 0..budget {
        result.blocks.push(at);
        let block = &m.blocks[at];
        // Phi assignments are simultaneous, including self-referential loop values.
        let phis: Vec<_> = block
            .phis
            .iter()
            .map(|&id| {
                let Op::Phi(incoming) = &m.insts[id as usize].op else {
                    panic!("not a phi");
                };
                let &(value, _) = incoming
                    .iter()
                    .find(|(_, from)| Some(*from) == previous)
                    .expect("phi must have an incoming value for the executed edge");
                (V::Inst(id), word(m, &result.values, value))
            })
            .collect();
        result.values.extend(phis);
        for &id in &block.body {
            let get = |v| word(m, &result.values, v);
            let value = match &m.insts[id as usize].op {
                Op::Bin(op, a, b) => match op {
                    Bin::Add => get(*a).wrapping_add(get(*b)),
                    Bin::Sub => get(*a).wrapping_sub(get(*b)),
                    Bin::And => get(*a) & get(*b),
                    Bin::Or => get(*a) | get(*b),
                    Bin::Xor => get(*a) ^ get(*b),
                    _ => panic!("unexpected operation {op:?}"),
                },
                Op::Cmp(op, a, b) => u32::from(match *op {
                    pred::EQ => get(*a) == get(*b),
                    pred::NE => get(*a) != get(*b),
                    pred::IULT => get(*a) < get(*b),
                    pred::IUGE => get(*a) >= get(*b),
                    pred::SLT => (get(*a) as i32) < (get(*b) as i32),
                    _ => panic!("unexpected comparison {op}"),
                }),
                Op::Select(c, t, f) => get(if get(*c) != 0 { *t } else { *f }),
                Op::Call(f, args) if m.funcs[*f as usize].name == "dx.op.discard" => {
                    result.discarded |= get(args[1]) != 0;
                    0
                }
                op => panic!("unexpected instruction {op:?}"),
            };
            result.values.insert(V::Inst(id), value);
        }
        let next = match block.term.expect("terminated block") {
            Term::Br(next) => next,
            Term::CondBr(condition, yes, no) => {
                if word(m, &result.values, condition) != 0 {
                    yes
                } else {
                    no
                }
            }
            Term::Ret => return result,
        };
        previous = Some(at);
        at = next;
    }
    panic!("emitted control flow did not return within {budget} blocks");
}

/// Evaluate one emitted integer value for an authored lane-local fixture. Only
/// the entry wave-allocation atomic is modeled: its returned base identifies
/// this physical wave. This checks emitted data dependencies, not GPU barriers.
pub(crate) fn lane_value(m: &Module, value: V, lane: u32, base: u32, width: u32) -> u32 {
    fn eval(m: &Module, value: V, lane: u32, base: u32, width: u32, left: usize) -> u32 {
        assert!(left != 0, "lane expression exceeds its evaluation budget");
        let get = |v| eval(m, v, lane, base, width, left - 1);
        let V::Inst(id) = value else {
            return word(m, &HashMap::new(), value);
        };
        match &m.insts[id as usize].op {
            Op::Bin(op, a, b) => match op {
                Bin::Add => get(*a).wrapping_add(get(*b)),
                Bin::Sub => get(*a).wrapping_sub(get(*b)),
                Bin::Mul => get(*a).wrapping_mul(get(*b)),
                Bin::And => get(*a) & get(*b),
                Bin::Or => get(*a) | get(*b),
                Bin::Xor => get(*a) ^ get(*b),
                Bin::Shl => get(*a).wrapping_shl(get(*b)),
                Bin::LShr => get(*a).wrapping_shr(get(*b)),
                Bin::UDiv => get(*a) / get(*b),
                Bin::URem => get(*a) % get(*b),
                _ => panic!("unexpected lane operation {op:?}"),
            },
            Op::Cmp(op, a, b) => u32::from(match *op {
                pred::EQ => get(*a) == get(*b),
                pred::NE => get(*a) != get(*b),
                pred::IULT => get(*a) < get(*b),
                pred::IUGE => get(*a) >= get(*b),
                _ => panic!("unexpected lane comparison {op}"),
            }),
            Op::Select(c, t, f) => get(if get(*c) != 0 { *t } else { *f }),
            Op::Cast(Cast::Bitcast | Cast::ZExt | Cast::Trunc, v) => get(*v),
            Op::AtomicRmw(Rmw::Add, _, amount) => {
                assert_eq!(lane, 0, "only wave-first allocation result is observed");
                assert_eq!(get(*amount), 32);
                base
            }
            Op::Call(f, args) => match m.funcs[*f as usize].name.as_str() {
                "dx.op.waveGetLaneIndex" => lane,
                "dx.op.flattenedThreadIdInGroup.i32" => base + lane,
                "dx.op.waveReadLaneFirst.i32" => eval(m, args[1], 0, base, width, left - 1),
                "dx.op.waveReadLaneAt.i32" => {
                    let source = get(args[2]);
                    assert!(
                        source < width,
                        "shuffle source must stay within physical wave"
                    );
                    eval(m, args[1], source, base, width, left - 1)
                }
                name => panic!("unexpected lane call {name}"),
            },
            op => panic!("unexpected lane expression {op:?}"),
        }
    }
    eval(m, value, lane, base, width, 512)
}
