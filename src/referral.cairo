use starknet::ContractAddress;

#[starknet::interface]
trait IReferral<TContractState> {
    fn get_balance(
        self: @TContractState, sponsor_addr: ContractAddress, erc20_addr: ContractAddress
    ) -> u256;
    fn claim(ref self: TContractState, erc20_addr: ContractAddress);
    fn add_commission(
        ref self: TContractState,
        amount: u256,
        sponsor_addr: ContractAddress,
        sponsored_addr: ContractAddress,
        erc20_addr: ContractAddress,
    );
    fn withdraw(
        ref self: TContractState, addr: ContractAddress, amount: u256, erc20_addr: ContractAddress
    );
    fn set_min_claim(ref self: TContractState, amount: u256);
    fn set_default_commission(ref self: TContractState, share: u256);
    fn override_commission(ref self: TContractState, sponsor_addr: ContractAddress, share: u256);
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

    use openzeppelin::{
        account, access::ownable::OwnableComponent,
        upgrades::{UpgradeableComponent, interface::IUpgradeable},
        token::erc20::interface::{IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait},
    };
    use storage_read::{main::storage_read_component, interface::IStorageRead};

    component!(path: storage_read_component, storage: storage_read, event: StorageReadEvent);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[abi(embed_v0)]
    impl StorageReadImpl = storage_read_component::StorageRead<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        sponsor_balance: LegacyMap<ContractAddress, u256>,
        new_sponsor_balance: LegacyMap<(ContractAddress, ContractAddress), u256>,
        sponsor_comm: LegacyMap<ContractAddress, u256>,
        sponsored_by: LegacyMap<ContractAddress, ContractAddress>,
        default_comm: u256,
        min_claim: u256,
        naming_contract: ContractAddress,
        eth_contract: ContractAddress,
        #[substorage(v0)]
        storage_read: storage_read_component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage
    }

    //
    // Events
    //

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OnClaim: OnClaim,
        OnCommission: OnCommission,
        #[flat]
        StorageReadEvent: storage_read_component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event
    }


    #[derive(Drop, starknet::Event)]
    struct OnClaim {
        timestamp: u64,
        amount: u256,
        #[key]
        sponsor_addr: ContractAddress,
        #[key]
        erc20_addr: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct OnCommission {
        timestamp: u64,
        amount: u256,
        #[key]
        sponsor_addr: ContractAddress,
        #[key]
        sponsored_addr: ContractAddress,
        #[key]
        erc20_addr: ContractAddress
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
        self.ownable.initializer(admin);
        self.naming_contract.write(naming_addr);
        self.eth_contract.write(eth_addr);
        self.min_claim.write(min_claim_amount);
        self.default_comm.write(share);
    }

    #[abi(embed_v0)]
    impl ReferralImpl of IReferral<ContractState> {
        //
        // View
        //
        fn get_balance(
            self: @ContractState, sponsor_addr: ContractAddress, erc20_addr: ContractAddress
        ) -> u256 {
            if erc20_addr == self.eth_contract.read() {
                return self.sponsor_balance.read(sponsor_addr)
                    + self.new_sponsor_balance.read((sponsor_addr, erc20_addr));
            }
            self.new_sponsor_balance.read((sponsor_addr, erc20_addr))
        }

        //
        // External
        //

        fn claim(ref self: ContractState, erc20_addr: ContractAddress) {
            let sponsor_addr = get_caller_address();
            let balance = self.get_balance(sponsor_addr, erc20_addr);
            assert(balance >= self.min_claim.read(), 'Balance is too low');
            let ERC20 = IERC20CamelDispatcher { contract_address: erc20_addr };
            ERC20.transfer(recipient: sponsor_addr, amount: balance);
            self.new_sponsor_balance.write((sponsor_addr, erc20_addr), 0);
            if erc20_addr == self.eth_contract.read() {
                self.sponsor_balance.write(sponsor_addr, 0);
            }
            self
                .emit(
                    Event::OnClaim(
                        OnClaim {
                            timestamp: get_block_timestamp(),
                            amount: balance,
                            sponsor_addr,
                            erc20_addr
                        }
                    )
                );
        }

        fn add_commission(
            ref self: ContractState,
            amount: u256,
            sponsor_addr: ContractAddress,
            sponsored_addr: ContractAddress,
            erc20_addr: ContractAddress,
        ) {
            let caller = get_caller_address();
            assert(caller == self.naming_contract.read(), 'Caller not naming contract');
            // we update the sponsor of "sponsored" so if sponsored refers someone, sponsor
            // will also receive something recursively
            self.sponsored_by.write(sponsored_addr, sponsor_addr);

            let mut circular_lock: Felt252Dict<felt252> = Default::default();
            // 1 is the initial accumulator value (denominator factor)
            self
                .rec_distribution(
                    sponsored_addr, sponsor_addr, amount, ref circular_lock, 1, erc20_addr
                );
            // to protect against malicious prover
            circular_lock.squash();
        }


        //
        // Admin functions
        //

        fn set_min_claim(ref self: ContractState, amount: u256) {
            self.ownable.assert_only_owner();
            self.min_claim.write(amount);
        }

        fn set_default_commission(ref self: ContractState, share: u256) {
            self.ownable.assert_only_owner();
            assert(self.check_share_size(share), 'Share must be between 0 and 100');
            self.default_comm.write(share);
        }


        fn override_commission(
            ref self: ContractState, sponsor_addr: ContractAddress, share: u256
        ) {
            self.ownable.assert_only_owner();
            assert(self.check_share_size(share), 'Share must be between 0 and 100');
            self.sponsor_comm.write(sponsor_addr, share);
        }

        fn withdraw(
            ref self: ContractState,
            addr: ContractAddress,
            amount: u256,
            erc20_addr: ContractAddress
        ) {
            self.ownable.assert_only_owner();
            let contract_addr = get_contract_address();
            let ERC20 = IERC20CamelDispatcher { contract_address: erc20_addr };
            ERC20.approve(spender: contract_addr, amount: amount);
            ERC20.transferFrom(sender: contract_addr, recipient: addr, amount: amount);
        }
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable._upgrade(new_class_hash);
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
            erc20_addr: ContractAddress,
        ) {
            // if we checked one or there is no sponsor
            if (1 - circular_lock.get(sponsor_addr.into())) * sponsor_addr.into() == 0 {
                return;
            }
            circular_lock.insert(sponsor_addr.into(), true.into());

            let custom_comm = self.sponsor_comm.read(sponsor_addr);
            let share = match integer::u256_is_zero(custom_comm) {
                zeroable::IsZeroResult::Zero(()) => self.default_comm.read(),
                zeroable::IsZeroResult::NonZero(_x) => custom_comm,
            };

            // takes share% of base_amount and divides by acc
            let comm = (base_amount * share) / (100 * acc);

            self
                .new_sponsor_balance
                .write(
                    (sponsor_addr, erc20_addr),
                    self.new_sponsor_balance.read((sponsor_addr, erc20_addr)) + comm
                );

            self
                .emit(
                    Event::OnCommission(
                        OnCommission {
                            timestamp: get_block_timestamp(),
                            amount: comm,
                            sponsor_addr,
                            sponsored_addr,
                            erc20_addr
                        }
                    )
                );

            self
                .rec_distribution(
                    sponsored_addr,
                    self.sponsored_by.read(sponsor_addr),
                    base_amount,
                    ref circular_lock,
                    2 * acc,
                    erc20_addr
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
