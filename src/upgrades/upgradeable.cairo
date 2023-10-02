use starknet::class_hash::ClassHash;

#[starknet::contract]
mod Upgradeable {
    use array::ArrayTrait;
    use starknet::class_hash::ClassHash;
    use starknet::ContractAddress;
    use starknet::get_contract_address;
    use zeroable::Zeroable;

    #[event]
    fn Upgraded(implementation: ClassHash) {}

    #[storage]
    struct Storage {}

    //
    // Unprotected
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            assert(!impl_hash.is_zero(), 'Class hash cannot be zero');
            starknet::replace_class_syscall(impl_hash).unwrap();
            Upgraded(impl_hash);
        }

        fn upgrade_and_call(
            ref self: ContractState,
            impl_hash: ClassHash,
            selector: felt252,
            calldata: Array<felt252>
        ) {
            self.upgrade(impl_hash);
            // The call_contract syscall is used in order to call a selector from the new class.
            // See: https://docs.starknet.io/documentation/architecture_and_concepts/Contracts/system-calls-cairo1/#replace_class
            starknet::call_contract_syscall(get_contract_address(), selector, calldata.span())
                .unwrap();
        }
    }
}
