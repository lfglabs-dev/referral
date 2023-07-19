#[abi]
trait IERC20 {
    #[view]
    fn balance_of(account: starknet::ContractAddress) -> u256;

    #[external]
    fn transfer(recipient: ContractAddress, amount: u256) -> bool;

    #[external]
    fn transferFrom(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool;

    #[external]
    fn approve(spender: starknet::ContractAddress, amount: u256) -> bool;
}