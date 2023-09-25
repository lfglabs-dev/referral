use starknet::ContractAddress;

#[starknet::interface]
trait IReferral<TContractState> {
    fn get_balance(self: @TContractState, sponsor_addr: ContractAddress) -> u256;
    fn owner(self: @TContractState) -> ContractAddress;
    fn transfer_ownership(ref self: TContractState, new_admin: ContractAddress);
    fn claim(ref self: TContractState);
    fn add_commission(
        ref self: TContractState,
        amount: u256,
        sponsor_addr: ContractAddress,
        sponsored_addr: ContractAddress
    );
    fn withdraw(ref self: TContractState, addr: ContractAddress, amount: u256);
    fn set_min_claim(ref self: TContractState, amount: u256);
    fn set_default_commission(ref self: TContractState, share: u256);
    fn override_commission(ref self: TContractState, sponsor_addr: ContractAddress, share: u256);
    fn upgrade(ref self: TContractState, impl_hash: starknet::class_hash::ClassHash);
    fn upgrade_and_call(
        ref self: TContractState,
        new_hash: starknet::class_hash::ClassHash,
        selector: felt252,
        calldata: Array<felt252>
    );
}

#[starknet::contract]
mod Referral {
    use starknet::ContractAddress;
    use starknet::class_hash::ClassHash;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use debug::PrintTrait;
    use super::IReferral;
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
    #[derive(Drop, starknet::Event)]
    fn on_claim(timestamp: u64, amount: u256, sponsor_addr: ContractAddress,) {}

    #[event]
    #[derive(Drop, starknet::Event)]
    fn on_commission(
        timestamp: u64,
        amount: u256,
        sponsor_addr: ContractAddress,
        sponsored_addr: ContractAddress,
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
    impl ReferralImpl of IReferral<ContractState> {
        //
        // View
        //
        fn get_balance(self: @ContractState, sponsor_addr: ContractAddress) -> u256 {
            self.sponsor_balance.read(sponsor_addr)
        }


        //
        // External
        //

        fn claim(ref self: ContractState,) {
            let sponsor_addr = get_caller_address();
            let balance = self.sponsor_balance.read(sponsor_addr);
            assert(balance >= self.min_claim.read(), 'Balance is too low');
            let contract_addr = get_contract_address();
            let ERC20 = IERC20Dispatcher { contract_address: self.eth_contract.read() };
            ERC20.transfer(recipient: sponsor_addr, amount: balance);
            self.sponsor_balance.write(sponsor_addr, 0);
            on_claim(get_block_timestamp(), balance, sponsor_addr);
        }

        fn add_commission(
            ref self: ContractState,
            amount: u256,
            sponsor_addr: ContractAddress,
            sponsored_addr: ContractAddress
        ) {
            let caller = get_caller_address();
            assert(caller == self.naming_contract.read(), 'Caller not naming contract');

            // Calculate commission
            let mut share = self.sponsor_comm.read(sponsor_addr);
            if share == 0 {
                share = self.default_comm.read();
            }
            // u256_is_zero is not accepted yet
            // let share = match integer::u256_is_zero(sponsor_comm::read(sponsor_addr)) {
            //     zeroable::IsZeroResult::Zero(()) => default_comm::read(),
            //     zeroable::IsZeroResult::NonZero(x) => sponsor_comm::read(sponsor_addr),
            // };

            // todo: update to use u256_safe_divmod when we can
            // warning: make sure to check for overflow
            let comm = (amount.low * share.low) / 100_u128;

            self
                .sponsor_balance
                .write(
                    sponsor_addr,
                    self.sponsor_balance.read(sponsor_addr) + u256 { low: comm, high: 0 }
                );
            on_commission(
                get_block_timestamp(), u256 { low: comm, high: 0 }, sponsor_addr, sponsored_addr
            );
        }


        //
        // Admin functions
        //

        fn set_min_claim(ref self: ContractState, amount: u256) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            self.min_claim.write(amount);
        }

        fn set_default_commission(ref self: ContractState, share: u256) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            assert(self.check_share_size(share), 'Share must be between 0 and 100');
            self.default_comm.write(share);
        }


        fn override_commission(
            ref self: ContractState, sponsor_addr: ContractAddress, share: u256
        ) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            assert(self.check_share_size(share), 'Share must be between 0 and 100');
            self.sponsor_comm.write(sponsor_addr, share);
        }

        fn withdraw(ref self: ContractState, addr: ContractAddress, amount: u256) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            let contract_addr = get_contract_address();
            let ERC20 = IERC20Dispatcher { contract_address: self.eth_contract.read() };
            ERC20.approve(spender: contract_addr, amount: amount);
            ERC20.transferFrom(sender: contract_addr, recipient: addr, amount: amount);
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

        fn upgrade(ref self: ContractState, impl_hash: ClassHash) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);

            let mut upgradeable_state = Upgradeable::unsafe_new_contract_state();
            Upgradeable::InternalTrait::upgrade(ref upgradeable_state, impl_hash);
        }

        fn upgrade_and_call(
            ref self: ContractState,
            new_hash: ClassHash,
            selector: felt252,
            calldata: Array<felt252>
        ) {
            let ownable_state = Ownable::unsafe_new_contract_state();
            Ownable::InternalTrait::assert_only_owner(@ownable_state);
            let mut upgradeable_state = Upgradeable::unsafe_new_contract_state();
            Upgradeable::InternalTrait::upgrade_and_call(
                ref upgradeable_state, new_hash, selector, calldata
            );
        }
    }


    //
    // Internals
    //

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn check_share_size(self: @ContractState, share: u256) -> bool {
            if share > 100 {
                return false;
            }
            true
        }
    }
}
