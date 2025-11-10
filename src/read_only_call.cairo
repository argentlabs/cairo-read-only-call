use starknet::account::Call;
use starknet::get_contract_address;

const MAGIC: felt252 = 'read_only_call_panicking';

#[starknet::interface]
trait ISafeReadCall<TContractState> {
    fn read_only_call_panicking(self: @TContractState, call: Call);
}

pub fn read_only_call<T, +Serde<T>, +Drop<T>>(call: Call) -> T {
    let inner_call_result = ISafeReadCallSafeDispatcher { contract_address: get_contract_address() }
        .read_only_call_panicking(call);
    let error = inner_call_result.expect_err('ROC: didnt panic');
    let mut error_span = error.span();
    let first_felt = *error_span.pop_front().unwrap_or_default();
    let last_felt = *error_span.pop_back().unwrap_or_default();
    // https://community.starknet.io/t/starknet-v0-13-4-pre-release-notes/115257#p-2358763-catching-errors-12
    if first_felt != MAGIC || last_felt != 'ENTRYPOINT_FAILED' {
        // It should never happen:
        // - If the error cannot be caught, we won't be here.
        // - If the error can be caught, we should be able to parse it
        panic_with('ROC', error)
    }
    match full_deserialize(error_span) {
        Option::Some(result) => result,
        Option::None => panic_with('ROC: result parsing', error),
    }
}

#[starknet::component]
pub mod safe_read_component {
    use alexandria_data_structures::array_ext::ArrayTraitExt;
    use starknet::account::Call;
    use starknet::syscalls::call_contract_syscall;
    use starknet::{get_caller_address, get_contract_address};
    use super::{ISafeReadCall, MAGIC, panic_with};

    #[storage]
    pub struct Storage {}

    #[embeddable_as(SafeReadCallImpl)]
    impl ImplSafeReadCall<
        TContractState, +HasComponent<TContractState>,
    > of ISafeReadCall<ComponentState<TContractState>> {
        fn read_only_call_panicking(self: @ComponentState<TContractState>, call: Call) {
            assert(get_caller_address() == get_contract_address(), 'Read-only call: only self');
            match call_contract_syscall(call.to, call.selector, call.calldata) {
                Ok(result) => {
                    let mut final_panic = array![MAGIC];
                    final_panic.extend_from_span(result);
                    panic(final_panic);
                },
                Err(err) => {
                    // Different MAGIC value to avoid this being interpreted as an ok result
                    panic_with('read_only_call_panicking_error', err)
                },
            }
        }
    }
}

pub fn serialize<E, impl ESerde: Serde<E>, +Drop<E>>(value: E) -> Array<felt252> {
    let mut output = array![];
    ESerde::serialize(@value, ref output);
    output
}

pub fn full_deserialize<E, impl ESerde: Serde<E>, impl EDrop: Drop<E>>(
    mut data: Span<felt252>,
) -> Option<E> {
    let parsed_value: E = ESerde::deserialize(ref data)?;
    if data.is_empty() {
        Option::Some(parsed_value)
    } else {
        Option::None
    }
}

pub fn panic_with(prefix_message: felt252, original_error: Array<felt252>) -> core::never {
    let mut final_error = array![prefix_message];
    for revert_reason in original_error {
        final_error.append(revert_reason);
    }
    panic(final_error)
}

