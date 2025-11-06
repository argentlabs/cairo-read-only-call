use starknet::ContractAddress;

#[starknet::interface]
pub trait IErc20<TContractState> {
    fn balance_of(ref self: TContractState, account: ContractAddress) -> u256;
    fn get_value(self: @TContractState) -> ContractAddress;
}

#[starknet::contract]
pub mod Erc20 {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IErc20;

    #[storage]
    struct Storage {
        last_caller: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl Erc20Impl of IErc20<ContractState> {
        fn balance_of(ref self: ContractState, account: ContractAddress) -> u256 {
            self.last_caller.write(get_caller_address());
            18
        }

        fn get_value(self: @ContractState) -> ContractAddress {
            self.last_caller.read()
        }
    }
}
