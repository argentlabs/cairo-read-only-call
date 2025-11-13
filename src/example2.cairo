use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait IExample2<TContractState> {
    fn unshielded_libraby_call(
        ref self: TContractState,
        class_hash: ClassHash,
        erc20: ContractAddress,
        user: ContractAddress,
    );
    fn shielded_library_call(
        ref self: TContractState,
        class_hash: ClassHash,
        erc20: ContractAddress,
        user: ContractAddress,
    );
}

#[starknet::contract]
pub mod Example2 {
    use starknet::{ClassHash, ContractAddress};
    use crate::example::{IExampleDispatcherTrait, IExampleLibraryDispatcher};
    #[storage]
    struct Storage {}

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl Erc20Impl of super::IExample2<ContractState> {
        fn unshielded_libraby_call(
            ref self: ContractState,
            class_hash: ClassHash,
            erc20: ContractAddress,
            user: ContractAddress,
        ) {
            IExampleLibraryDispatcher { class_hash }.unshielded_call(erc20, user);
        }
        fn shielded_library_call(
            ref self: ContractState,
            class_hash: ClassHash,
            erc20: ContractAddress,
            user: ContractAddress,
        ) {
            IExampleLibraryDispatcher { class_hash }.shielded_call(erc20, user);
        }
    }
}

#[cfg(test)]
mod tests {
    use snforge_std::{ContractClassTrait, DeclareResultTrait, declare};
    use crate::erc20::{IErc20Dispatcher, IErc20DispatcherTrait};
    use super::*;

    fn setup() -> (IErc20Dispatcher, ClassHash, IExample2Dispatcher) {
        // Declare the SafeReadCall contract to ensure it is deployed
        declare("SafeReadCall").expect('Failed to declare SafeReadCall');
        let (erc20, _) = declare("Erc20")
            .expect('Failed to declare Erc20')
            .contract_class()
            .deploy(@array![])
            .unwrap();
        let example = declare("Example")
            .expect('Failed to declare Example')
            .contract_class()
            .class_hash;
        let (example2, _) = declare("Example2")
            .expect('Failed to declare Example')
            .contract_class()
            .deploy(@array![])
            .unwrap();
        (
            IErc20Dispatcher { contract_address: erc20 },
            *example,
            IExample2Dispatcher { contract_address: example2 },
        )
    }

    const USER: ContractAddress = 'user'.try_into().unwrap();
    #[test]
    fn test_unshielded_call() {
        let (erc20_dispatcher, class_hash, example2_dispatcher) = setup();
        let value_before = erc20_dispatcher.get_value();

        example2_dispatcher
            .unshielded_libraby_call(class_hash, erc20_dispatcher.contract_address, USER);
        let value_after = erc20_dispatcher.get_value();
        assert_ne!(value_before, value_after);
    }

    #[test]
    fn test_shielded_call() {
        let (erc20_dispatcher, class_hash, example2_dispatcher) = setup();
        let value_before = erc20_dispatcher.get_value();

        example2_dispatcher
            .shielded_library_call(class_hash, erc20_dispatcher.contract_address, USER);
        let value_after = erc20_dispatcher.get_value();
        assert_eq!(value_before, value_after);
    }
}
