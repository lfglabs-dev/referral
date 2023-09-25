use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
trait IReferral_V2<TContractState> {
    fn get_balance(self: @TContractState, sponsor_addr: starknet::ContractAddress) -> u256;
    fn owner(self: @TContractState) -> starknet::ContractAddress;
    fn a_new_function(self: @TContractState) -> bool;
    fn transfer_ownership(ref self: TContractState, new_admin: ContractAddress);

    fn upgrade(
        ref self: TContractState, impl_hash: ClassHash, selector: felt252, calldata: Array<felt252>
    );
}

#[starknet::contract]
mod Referral_V2 {
    use starknet::ContractAddress;
    use starknet::class_hash::ClassHash;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    use debug::PrintTrait;
    use super::IReferral_V2;
    use referral::access::ownable::Ownable;
    use referral::upgrades::upgradeable::Upgradeable;

    // dispatchers
    use referral::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        sponsor_balance: LegacyMap<ContractAddress, u256>,
        sponsor_comm: LegacyMap<ContractAddress, u256>,
        default_comm: u256,
        min_claim: u256,
        naming_contract: ContractAddress,
        eth_contract: ContractAddress,
    }

    //
    // Events
    //

    #[event]
    fn on_claim(timestamp: u64, amount: u256, sponsor_addr: ContractAddress,) {}

    #[event]
    fn on_commission(
        timestamp: u64, amount: u256, sponsor_addr: ContractAddress, caller: ContractAddress,
    ) {}


    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        naming_addr: ContractAddress,
        eth_addr: ContractAddress,
        min_claim_amount: u256,
        share: u256
    ) {
        let mut ownable_state = Ownable::unsafe_new_contract_state();
        Ownable::InternalTrait::_transfer_ownership(ref ownable_state, admin);
        self.naming_contract.write(naming_addr);
        self.eth_contract.write(eth_addr);
        self.min_claim.write(min_claim_amount);
        self.default_comm.write(share);
    }

    #[external(v0)]
    impl Referral_V2Impl of IReferral_V2<ContractState> {
        //
        // View
        //
        fn a_new_function(self: @ContractState) -> bool {
            true
        }

        fn get_balance(self: @ContractState, sponsor_addr: ContractAddress) -> u256 {
            self.sponsor_balance.read(sponsor_addr)
        }

        //
        // Ownership 
        //

        fn owner(self: @ContractState) -> ContractAddress {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::owner(@ownable_state)
        }


        fn transfer_ownership(ref self: ContractState, new_admin: ContractAddress) {
            let mut ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::transfer_ownership(ref ownable_state, new_admin);
        }

        fn upgrade(
            ref self: ContractState,
            impl_hash: ClassHash,
            selector: felt252,
            calldata: Array<felt252>
        ) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            let mut upgradeable_state = Upgradeable::unsafe_new_contract_state();
            Upgradeable::InternalTrait::upgrade(ref upgradeable_state, impl_hash);
        }
    }


    //
    // Internals
    //
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn check_share_size(share: u256) -> bool {
            if share > (u256 { low: 100, high: 0 }) {
                return false;
            }
            true
        }
    }
}
