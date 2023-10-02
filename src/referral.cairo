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
    use core::dict::Felt252DictTrait;
    use starknet::ContractAddress;
    use starknet::class_hash::ClassHash;
    use starknet::contract_address::ContractAddressZeroable;
    use starknet::{get_caller_address, get_contract_address, get_block_timestamp};
    use integer::u256_safe_divmod;
    use super::IReferral;
    use referral::access::ownable::Ownable;
    use referral::upgrades::upgradeable::Upgradeable;

    // dispatchers
    use referral::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};

    #[storage]
    struct Storage {
        sponsor_balance: LegacyMap<ContractAddress, u256>,
        sponsor_comm: LegacyMap<ContractAddress, u256>,
        sponsored_by: LegacyMap<ContractAddress, ContractAddress>,
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
    enum Event {
        OnClaim: OnClaim,
        OnCommission: OnCommission,
    }


    #[derive(Drop, starknet::Event)]
    struct OnClaim {
        timestamp: u64,
        amount: u256,
        #[key]
        sponsor_addr: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct OnCommission {
        timestamp: u64,
        amount: u256,
        #[key]
        sponsor_addr: ContractAddress,
        #[key]
        sponsored_addr: ContractAddress,
    }


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
            self
                .emit(
                    Event::OnClaim(
                        OnClaim { timestamp: get_block_timestamp(), amount: balance, sponsor_addr, }
                    )
                );
        }

        fn add_commission(
            ref self: ContractState,
            amount: u256,
            sponsor_addr: ContractAddress,
            sponsored_addr: ContractAddress
        ) {
            let caller = get_caller_address();
            assert(caller == self.naming_contract.read(), 'Caller not naming contract');
            // we update the sponsor of "sponsored" so if sponsored refers someone, sponsor
            // will also receive something recursively
            self.sponsored_by.write(sponsored_addr, sponsor_addr);

            let mut circular_lock: Felt252Dict<felt252> = Default::default();
            // 1 is the initial accumulator value (denominator factor)
            self.rec_distribution(sponsored_addr, sponsor_addr, amount, ref circular_lock, 1);
            // to protect against malicious prover
            circular_lock.squash();
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
        fn rec_distribution(
            ref self: ContractState,
            sponsored_addr: ContractAddress,
            sponsor_addr: ContractAddress,
            base_amount: u256,
            ref circular_lock: Felt252Dict<felt252>,
            acc: u256,
        ) {
            // if we checked one or there is no sponsor
            if (1 - circular_lock.get(sponsor_addr.into())) * sponsor_addr.into() == 0 {
                return;
            }
            circular_lock.insert(sponsor_addr.into(), true.into());

            let custom_comm = self.sponsor_comm.read(sponsor_addr);
            let share = match integer::u256_is_zero(custom_comm) {
                zeroable::IsZeroResult::Zero(()) => self.default_comm.read(),
                zeroable::IsZeroResult::NonZero(x) => custom_comm,
            };

            // takes share% of base_amount and divides by acc
            let comm = (base_amount * share) / (100 * acc);

            self
                .sponsor_balance
                .write(sponsor_addr, self.sponsor_balance.read(sponsor_addr) + comm);

            self
                .emit(
                    Event::OnCommission(
                        OnCommission {
                            timestamp: get_block_timestamp(),
                            amount: comm,
                            sponsor_addr,
                            sponsored_addr
                        }
                    )
                );

            self
                .rec_distribution(
                    sponsored_addr,
                    self.sponsored_by.read(sponsor_addr),
                    base_amount,
                    ref circular_lock,
                    2 * acc
                );
        }

        fn check_share_size(self: @ContractState, share: u256) -> bool {
            if share > 100 {
                return false;
            }
            true
        }
    }
}
