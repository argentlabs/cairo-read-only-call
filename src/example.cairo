use starknet::ContractAddress;
use starknet::account::Call;
use crate::read_only_call::{read_only_call, serialize};

#[derive(Copy, Drop)]
struct ShieldedDispatcher {
    contract_address: ContractAddress,
}

// Here is where you add the function that you want to be shielded
#[generate_trait]
impl ShieldedErc20DispatcherTrait of IShieldedErc20 {
    fn balance_of(self: @ShieldedDispatcher, account: ContractAddress) -> u256 {
        let call = Call {
            to: *self.contract_address,
            selector: selector!("balance_of"),
            calldata: serialize(account).span(),
        };
        read_only_call(call)
    }
}

#[starknet::interface]
pub trait IExample<TContractState> {
    fn unshielded_call(
        ref self: TContractState, erc20: ContractAddress, user: ContractAddress,
    ) -> u256;
    fn shielded_call(
        ref self: TContractState, erc20: ContractAddress, user: ContractAddress,
    ) -> u256;
}

#[starknet::contract]
mod Example {
    use starknet::ContractAddress;
    use crate::erc20::{IErc20Dispatcher, IErc20DispatcherTrait};
    use super::{IExample, ShieldedDispatcher, ShieldedErc20DispatcherTrait};


    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl ExampleImpl of IExample<ContractState> {
        fn unshielded_call(
            ref self: ContractState, erc20: ContractAddress, user: ContractAddress,
        ) -> u256 {
            IErc20Dispatcher { contract_address: erc20 }.balance_of(user)
        }

        fn shielded_call(
            ref self: ContractState, erc20: ContractAddress, user: ContractAddress,
        ) -> u256 {
            ShieldedDispatcher { contract_address: erc20 }.balance_of(user)
        }
    }
}

#[cfg(test)]
mod tests {
    use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
    use crate::erc20::{IErc20Dispatcher, IErc20DispatcherTrait};
    use super::*;

    fn setup() -> (IErc20Dispatcher, IExampleDispatcher) {
        // Declare the SafeReadCall contract to ensure it is deployed
        declare("SafeReadCall").expect('Failed to declare SafeReadCall');
        let (erc20, _) = declare("Erc20")
            .expect('Failed to declare Erc20')
            .contract_class()
            .deploy(@array![])
            .unwrap();
        let (example, _) = declare("Example")
            .expect('Failed to declare Example')
            .contract_class()
            .deploy(@array![])
            .unwrap();
        (
            IErc20Dispatcher { contract_address: erc20 },
            IExampleDispatcher { contract_address: example },
        )
    }

    const USER: ContractAddress = 'user'.try_into().unwrap();
    #[test]
    fn test_unshielded_call() {
        let (erc20_dispatcher, example_dispatcher) = setup();
        let value_before = erc20_dispatcher.get_value();

        example_dispatcher.unshielded_call(erc20_dispatcher.contract_address, USER);
        let value_after = erc20_dispatcher.get_value();
        assert_ne!(value_before, value_after);
    }

    #[test]
    fn test_shielded_call() {
        let (erc20_dispatcher, example_dispatcher) = setup();
        let value_before = erc20_dispatcher.get_value();

        example_dispatcher.shielded_call(erc20_dispatcher.contract_address, USER);
        let value_after = erc20_dispatcher.get_value();
        assert_eq!(value_before, value_after);
    }
}
