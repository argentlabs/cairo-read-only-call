# Safe Read-Only Calls to Untrusted Contracts

A Cairo library for safely calling untrusted contracts on Starknet using a revert-based mechanism that guarantees read-only semantics at runtime.

## Problem

Starknet does not enforce that a function declared as a view (`self: @ContractState`) is truly read-only at runtime. An untrusted contract can implement a view interface function as state-modifying (`ref self: ContractState`), potentially causing unexpected side effects.

## Solution

This library provides a component and pattern for building safe dispatchers that ensure external calls cannot modify state, even if the target contract is malicious.

**How it works**: Calls are wrapped in a revert-based pattern. Any state changes are rolled back, while return values are safely extracted and validated.

## Quick Start

### 1. Add the component to your contract

```cairo
use read_only_call::safe_read_component;

#[starknet::contract]
pub mod YourContract {
    component!(path: safe_read_component, storage: safe_read, event: SafeReadEvent);
    
    #[abi(embed_v0)]
    impl SafeRead = safe_read_component::SafeReadCallImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        safe_read: safe_read_component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SafeReadEvent: safe_read_component::Event,
    }
}
```

### 2. Build your safe dispatcher

The library provides the building blocks. You implement the dispatcher for your specific interface:

```cairo
use read_only_call::read_only_call;

#[derive(Copy, Drop)]
pub struct ShieldedDispatcher {
    pub contract_address: ContractAddress,
}

// Implement your interface trait on ShieldedDispatcher
impl MyInterfaceTrait of IMyInterface<ShieldedDispatcher> {
    fn balance_of(self: @ShieldedDispatcher, account: ContractAddress) -> u256 {
        let call = Call {
            to: *self.contract_address,
            selector: selector!("balance_of"),
            calldata: serialize(account).span(),
        };
        read_only_call(call)
    }
}
```

See `src/example.cairo` for a complete working example.

## Running Tests

```bash
scarb test
```

The tests in `src/example.cairo` demonstrate the pattern in action: shielded dispatchers prevent state modifications while regular dispatchers don't.

## How it works

1. Your shielded dispatcher calls `read_only_call()` with the target contract call
2. `read_only_call()` invokes `read_only_call_panicking` on your contract (via safe dispatcher)
3. The external call executes and immediately reverts with a magic value + return data
4. The revert is caught and validated (checks magic value and `ENTRYPOINT_FAILED`)
5. Return data is deserialized and returned to the caller
6. Any state changes are rolled back

## Why a Component Instead of a Library Contract?

We use the **component pattern** because it's the idiomatic way to provide reusable contract logic in Cairo. Components embed directly into your contract, keeping everything self-contained.

A library call approach would work equally well from a technical standpoint—it's primarily an architectural preference.

## Comparison with Solidity's `staticcall`

**Starknet does not have a `staticcall` equivalent.** 

In Solidity, `staticcall` enforces read-only semantics at the **EVM protocol level**—the runtime rejects state-modifying opcodes when attempted. In Starknet, there are only **compiler-level hints** (`self: @ContractState`) with no runtime enforcement.

This library bridges that gap with an **application-level pattern**: the external call executes completely, then gets reverted. 

**The key difference**: `staticcall` is **protocol-enforced** (the VM stops you), while this pattern is **application-enforced** (your contract reverts itself). Both protect your state, but `staticcall` is a language primitive while this is a design pattern.

