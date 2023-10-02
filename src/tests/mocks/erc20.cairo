#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: starknet::ContractAddress) -> u256;

    fn transfer_from(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256
    ) -> bool;

    fn transferFrom(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256
    ) -> bool;

    fn transfer(
        ref self: TContractState, recipient: starknet::ContractAddress, amount: u256
    ) -> bool;

    fn approve(ref self: TContractState, spender: starknet::ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
mod ERC20 {
    use super::IERC20;
    use zeroable::Zeroable;

    //
    // Storage
    //

    #[storage]
    struct Storage {
        _balances: LegacyMap<starknet::ContractAddress, u256>,
        _allowances: LegacyMap<(starknet::ContractAddress, starknet::ContractAddress), u256>,
    }

    #[event]
    fn Approval(
        owner: starknet::ContractAddress, spender: starknet::ContractAddress, value: u256
    ) {}

    //
    // Constructor
    //

    #[constructor]
    fn constructor(
        ref self: ContractState, initial_supply: u256, recipient: starknet::ContractAddress
    ) {
        self._mint(recipient, initial_supply);
    }


    //
    // Interface impl
    //
    #[external(v0)]
    impl ERC20 of IERC20<ContractState> {
        fn balance_of(self: @ContractState, account: starknet::ContractAddress) -> u256 {
            self._balances.read(account)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: starknet::ContractAddress,
            recipient: starknet::ContractAddress,
            amount: u256
        ) -> bool {
            self._transfer(sender, recipient, amount);
            true
        }

        fn transferFrom(
            ref self: ContractState,
            sender: starknet::ContractAddress,
            recipient: starknet::ContractAddress,
            amount: u256
        ) -> bool {
            self._transfer(sender, recipient, amount);
            true
        }


        fn transfer(
            ref self: ContractState, recipient: starknet::ContractAddress, amount: u256
        ) -> bool {
            let sender = starknet::get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(
            ref self: ContractState, spender: starknet::ContractAddress, amount: u256
        ) -> bool {
            let caller = starknet::get_caller_address();
            self._approve(caller, spender, amount);
            true
        }
    }

    //
    // Internals
    //
    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _mint(ref self: ContractState, recipient: starknet::ContractAddress, amount: u256) {
            assert(!recipient.is_zero(), 'ERC20: mint to 0');

            self._balances.write(recipient, self._balances.read(recipient) + amount);
        }

        fn _transfer(
            ref self: ContractState,
            sender: starknet::ContractAddress,
            recipient: starknet::ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from 0');
            assert(!recipient.is_zero(), 'ERC20: transfer to 0');

            self._balances.write(sender, self._balances.read(sender) - amount);
            self._balances.write(recipient, self._balances.read(recipient) + amount);
        }

        fn _approve(
            ref self: ContractState,
            owner: starknet::ContractAddress,
            spender: starknet::ContractAddress,
            amount: u256
        ) {
            assert(!owner.is_zero(), 'ERC20: approve from 0');
            assert(!spender.is_zero(), 'ERC20: approve to 0');
            self._allowances.write((owner, spender), amount);
            Approval(owner, spender, amount);
        }
    }
}
