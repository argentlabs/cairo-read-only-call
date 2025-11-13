# Safe Read-Only Calls to Untrusted Contracts

A Cairo library for safely calling untrusted contracts on Starknet using a revert-based mechanism that guarantees read-only semantics at runtime.

## Problem

Starknet does not enforce that a function declared as a view (`self: @ContractState`) is truly read-only at runtime. An untrusted contract can implement a view interface function as state-modifying (`ref self: ContractState`), potentially causing unexpected side effects.

## Solution

This library provides a simple function that wraps the entire logic for building safe dispatchers that ensure external calls cannot modify state, even if the target contract is malicious.

**How it works**: Calls are wrapped in a revert-based pattern using a library call to the `SafeReadCall` contract. Any state changes are rolled back, while return values are safely extracted and validated.

## Quick Start

### 1. Build your safe dispatcher

The library provides the building blocks. You implement the dispatcher for your specific interface:

```cairo
use starknet::ContractAddress;
use starknet::account::Call;
use read_only_call::{read_only_call, serialize};

#[derive(Copy, Drop)]
pub struct ShieldedDispatcher {
    pub contract_address: ContractAddress,
}

// Implement your interface trait on ShieldedDispatcher
#[generate_trait]
impl ShieldedDispatcherTrait of IShieldedErc20 {
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

### 2. Use the shielded dispatcher

In your contract, you can now use the shielded dispatcher to safely call untrusted contracts:

```cairo
ShieldedDispatcher { contract_address: erc20 }.balance_of(user)
```

## Running Tests

```bash
scarb test
```

The tests in `src/example.cairo` demonstrate the pattern in action: shielded dispatchers prevent state modifications while regular dispatchers don't.

## How it works

1. Your shielded dispatcher calls `read_only_call()` with the target contract call
2. `read_only_call()` performs a library call to `SafeReadCall` contract using `ISafeReadCallSafeLibraryDispatcher`
3. The library call executes `read_only_call_panicking` which makes the external call
4. The external call executes and immediately reverts with a magic value + return data
5. The revert is caught and validated (checks magic value and `ENTRYPOINT_FAILED`)
6. Return data is deserialized and returned to the caller
7. Any state changes are rolled back

## Library Call Architecture

This library uses **library calls** to a deployed `SafeReadCall` contract. The `CLASS_HASH` is hardcoded, and the library call executes in the caller's context without any storage requirements.

**Why library calls instead of a component?**

We initially implemented this as a component, but that approach had significant drawbacks:
- Added a lot of integration overhead related to component embedding
- Would have failed if any other contract tried to library call into it

The library call approach solves both issues:
- No storage overhead in your contract
- No need to embed a component
- Works seamlessly when called via library call from any contract
- Cleaner contract architecture

## Comparison with Solidity's `staticcall`

**Starknet does not have a `staticcall` equivalent.** 

In Solidity, `staticcall` enforces read-only semantics at the **EVM protocol level**—the runtime rejects state-modifying opcodes when attempted. In Starknet, there are only **compiler-level hints** (`self: @ContractState`) with no runtime enforcement.

This library bridges that gap with an **application-level pattern**: the external call executes completely, then gets reverted. 

**The key difference**: `staticcall` is **protocol-enforced** (the VM stops you), while this pattern is **application-enforced** (your contract reverts itself). Both protect your state, but `staticcall` is a language primitive while this is a design pattern.

