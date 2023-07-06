#[abi]
trait IReferral_V2 {
    #[view]
    fn get_balance(sponsor_addr: starknet::ContractAddress) -> u256;
    #[view]
    fn owner() -> starknet::ContractAddress;
    #[external]
    fn claim(amount: u256);
    #[external]
    fn add_commission(amount: u256, sponsor_addr: starknet::ContractAddress);
    #[external]
    fn withdraw(addr: starknet::ContractAddress, amount: u256);
    #[view]
    fn a_new_function() -> bool;
}

#[contract]
mod Referral_V2 {
    use starknet::ContractAddress;
    use starknet::class_hash::ClassHash;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    use debug::PrintTrait;

    use referral::access::ownable::Ownable;
    use referral::upgrades::upgradeable::Upgradeable;

    // dispatchers
    use referral::token::erc20::{ IERC20Dispatcher, IERC20DispatcherTrait };

    struct Storage {
        sponsor_balance: LegacyMap::<ContractAddress, u256>,
        sponsor_comm: LegacyMap::<ContractAddress, u256>, 
        default_comm: u256,
        min_claim: u256,
        naming_contract: ContractAddress,
        eth_contract: ContractAddress,
    }

    //
    // Events
    //

    #[event]
    fn on_claim(timestamp: u64, amount: u256, sponsor_addr: ContractAddress, ) {}

    #[event]
    fn on_commission(timestamp: u64, amount: u256, sponsor_addr: ContractAddress, caller: ContractAddress, ) {}


    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        admin: ContractAddress, 
        naming_addr: ContractAddress,
        eth_addr: ContractAddress,
        min_claim_amount: u256, 
        share: u256
    ) {
        initializer(:admin);
        naming_contract::write(naming_addr);
        eth_contract::write(eth_addr);
        min_claim::write(min_claim_amount);
        default_comm::write(share);
    }
    
    //
    // View
    //
    #[view]
    fn a_new_function() -> bool {
        true
    }



    #[view]
    fn get_balance(sponsor_addr: ContractAddress) -> u256 {
        sponsor_balance::read(sponsor_addr)
    }

    //
    // Ownership 
    //

    #[view]
    fn owner() -> ContractAddress {
        Ownable::owner()
    }

    #[internal]
    fn initializer(admin: ContractAddress) {
        Ownable::_transfer_ownership(new_owner: admin);
    }

    #[external]
    fn transfer_ownership(new_admin: ContractAddress) {
        Ownable::transfer_ownership(new_admin);
    }

    #[external]
    fn upgrade(impl_hash: ClassHash, selector: felt252, calldata: Array<felt252>) {
        Ownable::assert_only_owner();
        Upgradeable::upgrade(impl_hash);
    }

    //
    // Internals
    //

    fn check_share_size(share: u256) -> bool {
        if share > (u256 { low: 100, high: 0 }) {
            return false;
        }
        true
    }

}
