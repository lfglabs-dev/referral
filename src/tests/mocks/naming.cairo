#[starknet::interface]
trait INaming<TContractState> {
    fn set_referral_addr(
        ref self: TContractState, referral_addr: starknet::ContractAddress
    ) -> bool;
    fn buy_domain(
        ref self: TContractState, amount: u256, sponsor_addr: starknet::ContractAddress
    ) -> bool;
}

#[starknet::contract]
mod Naming {
    use super::INaming;
    use zeroable::Zeroable;
    use debug::PrintTrait;
    use referral::referral::{IReferral, IReferralDispatcher, IReferralDispatcherTrait};

    #[storage]
    struct Storage {
        referral_contract: starknet::ContractAddress
    }

    #[external(v0)]
    impl NamingImpl of INaming<ContractState> {
        fn set_referral_addr(
            ref self: ContractState, referral_addr: starknet::ContractAddress
        ) -> bool {
            self.referral_contract.write(referral_addr);
            true
        }
        fn buy_domain(
            ref self: ContractState, amount: u256, sponsor_addr: starknet::ContractAddress
        ) -> bool {
            let Referral = IReferralDispatcher { contract_address: self.referral_contract.read() };
            Referral.add_commission(amount, sponsor_addr, starknet::get_caller_address());
            true
        }
    }
}
