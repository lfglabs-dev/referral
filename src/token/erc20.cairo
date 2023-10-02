#[starknet::interface]
trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: starknet::ContractAddress) -> u256;

    fn transfer(ref self: TContractState, recipient: starknet::ContractAddress, amount: u256) -> bool;

    fn transferFrom(ref self: TContractState, sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool;

    fn approve(ref self: TContractState, spender: starknet::ContractAddress, amount: u256) -> bool;
}
