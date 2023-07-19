#[abi]
trait IReferral {
    #[view]
    fn get_balance(sponsor_addr: starknet::ContractAddress) -> u256;
    #[view]
    fn owner() -> starknet::ContractAddress;
    #[external]
    fn claim();
    #[external]
    fn add_commission(amount: u256, sponsor_addr: starknet::ContractAddress);
    #[external]
    fn withdraw(addr: starknet::ContractAddress, amount: u256);
    #[external]
    fn upgrade(impl_hash: starknet::class_hash::ClassHash);
    #[external]
    fn upgrade_and_call(
        new_hash: starknet::class_hash::ClassHash, selector: felt252, calldata: Array<felt252>
    );
}

#[contract]
mod Referral {
    use starknet::ContractAddress;
    use starknet::class_hash::ClassHash;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};

    use debug::PrintTrait;

    use referral::access::ownable::Ownable;
    use referral::upgrades::upgradeable::Upgradeable;

    // dispatchers
    use referral::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

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
    fn on_commission(
        timestamp: u64, amount: u256, sponsor_addr: ContractAddress, caller: ContractAddress, 
    ) {}


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
    fn get_balance(sponsor_addr: ContractAddress) -> u256 {
        sponsor_balance::read(sponsor_addr)
    }

    //
    // External
    //

    #[external]
    fn claim() {
        let sponsor_addr = get_caller_address();
        let balance = sponsor_balance::read(sponsor_addr);
        assert(balance >= min_claim::read(), 'Balance is too low');
        let contract_addr = get_contract_address();
        let ERC20 = IERC20Dispatcher { contract_address: eth_contract::read() };
        ERC20.transfer(recipient: sponsor_addr, amount: balance);
        sponsor_balance::write(sponsor_addr, 0);
        on_claim(get_block_timestamp(), balance, sponsor_addr);
    }

    #[external]
    fn add_commission(amount: u256, sponsor_addr: ContractAddress) {
        let caller = get_caller_address();
        assert(caller == naming_contract::read(), 'Caller not naming contract');

        // Calculate commission
        let mut share = sponsor_comm::read(sponsor_addr);
        if share == (u256 { low: 0, high: 0 }) {
            share = default_comm::read();
        }
        // u256_is_zero is not accepted yet
        // let share = match integer::u256_is_zero(sponsor_comm::read(sponsor_addr)) {
        //     zeroable::IsZeroResult::Zero(()) => default_comm::read(),
        //     zeroable::IsZeroResult::NonZero(x) => sponsor_comm::read(sponsor_addr),
        // };

        // todo: update to use u256_safe_divmod when we can
        // warning: make sure to check for overflow
        let comm = (amount.low * share.low) / 100_u128;

        sponsor_balance::write(
            sponsor_addr, sponsor_balance::read(sponsor_addr) + u256 { low: comm, high: 0 }
        );
        on_commission(get_block_timestamp(), u256 { low: comm, high: 0 }, sponsor_addr, caller);
    }


    //
    // Admin functions
    //

    #[external]
    fn set_min_claim(amount: u256) {
        Ownable::assert_only_owner();
        min_claim::write(amount);
    }

    #[external]
    fn set_default_commission(share: u256) {
        Ownable::assert_only_owner();
        assert(check_share_size(share), 'Share must be between 0 and 100');
        default_comm::write(share);
    }

    #[external]
    fn override_commission(sponsor_addr: ContractAddress, share: u256) {
        Ownable::assert_only_owner();
        assert(check_share_size(share), 'Share must be between 0 and 100');
        sponsor_comm::write(sponsor_addr, share);
    }

    #[external]
    fn withdraw(addr: ContractAddress, amount: u256) {
        Ownable::assert_only_owner();
        let contract_addr = get_contract_address();
        let ERC20 = IERC20Dispatcher { contract_address: eth_contract::read() };
        ERC20.approve(spender: contract_addr, amount: amount);
        ERC20.transferFrom(sender: contract_addr, recipient: addr, amount: amount);
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
    fn upgrade(impl_hash: ClassHash) {
        Ownable::assert_only_owner();
        Upgradeable::upgrade(impl_hash);
    }

    #[external]
    fn upgrade_and_call(impl_hash: ClassHash, selector: felt252, calldata: Array<felt252>) {
        Ownable::assert_only_owner();
        Upgradeable::upgrade_and_call(impl_hash, selector, calldata);
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
