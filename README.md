# Safe Read-Only Calls to Untrusted Contracts

A Cairo library for safely calling untrusted contracts on Starknet using a revert-based mechanism that guarantees read-only semantics at runtime.

## Problem

Starknet does not enforce that a function declared as a view (`self: @ContractState`) is truly read-only at runtime. An untrusted contract can implement a view interface function as state-modifying (`ref self: ContractState`), potentially causing unexpected side effects.

## Solution

This library provides `ShieldedDispatcher`, a safe dispatcher that ensures external calls cannot modify state, even if the target contract is malicious.

**How it works**: Calls are wrapped in a revert-based pattern. Any state changes are rolled back, while return values are safely extracted and validated.

## Quick Start

### 1. Add the component to your contract

```cairo
use crate::read_only_call::safe_read_component;

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

### 2. Use ShieldedDispatcher

```cairo
use crate::read_only_call::{ShieldedDispatcher, ShieldedDispatcherTrait};

fn safe_call(erc20_address: ContractAddress, user: ContractAddress) -> u256 {
    // ✅ Safe! State changes are reverted
    ShieldedDispatcher { contract_address: erc20_address }.balance_of(user)  
}
```

### Comparison

```cairo
// ⚠️ Unsafe: state can be modified
fn unsafe_call(ref self: ContractState, erc20: ContractAddress, user: ContractAddress) -> u256 {
    IErc20Dispatcher { contract_address: erc20 }.balance_of(user)
}

// ✅ Safe: state changes reverted
fn safe_call(ref self: ContractState, erc20: ContractAddress, user: ContractAddress) -> u256 {
    ShieldedDispatcher { contract_address: erc20 }.balance_of(user)
}
```

## Running Tests

```bash
scarb test
```

The tests demonstrate that `ShieldedDispatcher` prevents state modifications while regular dispatchers don't.

## How it works

1. `ShieldedDispatcher` wraps calls through `read_only_call_panicking`
2. The call executes and immediately reverts with a magic value + return data
3. Safe dispatcher catches the revert and validates the magic value
4. Return data is deserialized and returned to the caller
5. Any state changes are rolled back

## Couldn't this just be one contract everyone uses?

You might think: "Why not deploy one shared contract and have everyone call it?" 

We chose the **component pattern** instead because:

- **No address management**: No hardcoded addresses or storage variables needed (No risk of misconfigured addresses pointing to malicious contracts)
- **Lower gas**: Internal calls instead of library syscalls
- **Self-contained**: No external contract deployment needed
- **Simpler**: Works immediately, no dependency management

The tradeoff is slightly larger bytecode, but gas savings on every call more than compensate.

## Comparison with Solidity's `staticcall`

**Starknet does not have a `staticcall` equivalent.** 

In Solidity, `staticcall` enforces read-only semantics at the EVM protocol level, state modifications are rejected immediately. Starknet only has compiler-level hints (`self: @ContractState`), with no runtime enforcement.

| Feature | Solidity `staticcall` | Cairo `ShieldedDispatcher` |
|---------|----------------------|---------------------------|
| **Enforcement Level** | EVM protocol (runtime) | Application pattern (revert-based) |
| **State Protection** | Caller + target both protected | Caller protected, target reverted |
| **Gas on Attack** | Fails early, minimal gas wasted | Executes fully then reverts, more gas used |
| **Setup Required** | None, built into EVM | Must embed component in contract |
| **Trust Model** | Zero trust, enforced by VM | Trust your own contract implementation |
| **Cross-Contract** | Protects entire call chain | Only protects calling contract's state |
| **Return Values** | Direct return from call | Extracted from revert data |
| **Failure Mode** | Immediate rejection | Successful call that gets unwound |

**Key tradeoff**: `staticcall` prevents malicious operations before they execute. `ShieldedDispatcher` lets them run then reverts everything—your state is safe, but attackers can waste more of your gas.

