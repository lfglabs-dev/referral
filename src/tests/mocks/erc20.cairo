#[abi]
trait IERC20 {
  #[view]
  fn balance_of(account: starknet::ContractAddress) -> u256;

  #[external]
  fn transfer_from(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool;

  #[external]
  fn transfer(recipient: starknet::ContractAddress, amount: u256) -> bool;

  #[external]
  fn approve(spender: starknet::ContractAddress, amount: u256) -> bool;
}

#[contract]
mod ERC20 {
  use super::IERC20;
  use zeroable::Zeroable;

  //
  // Storage
  //

  struct Storage {
    _balances: LegacyMap<starknet::ContractAddress, u256>,
    _allowances: LegacyMap<(starknet::ContractAddress, starknet::ContractAddress), u256>,
  }

  #[event]
  fn Approval(owner: starknet::ContractAddress, spender: starknet::ContractAddress, value: u256) {}

  //
  // Constructor
  //

  #[constructor]
  fn constructor(initial_supply: u256, recipient: starknet::ContractAddress) {
    _mint(recipient, initial_supply);
  }

  //
  // Interface impl
  //

  impl ERC20 of IERC20 {
    fn balance_of(account: starknet::ContractAddress) -> u256 {
      _balances::read(account)
    }

    fn transfer_from(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool {
      _transfer(sender, recipient, amount);
      true
    }

    fn transfer(recipient: starknet::ContractAddress, amount: u256) -> bool {
        let sender = starknet::get_caller_address();
        _transfer(sender, recipient, amount);
        true
    }

    fn approve(spender: starknet::ContractAddress, amount: u256) -> bool {
        let caller = starknet::get_caller_address();
        _approve(caller, spender, amount);
        true
    }
  }

  #[view]
  fn balance_of(account: starknet::ContractAddress) -> u256 {
    ERC20::balance_of(account)
  }

  #[external]
  fn transfer_from(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool {
    ERC20::transfer_from(sender, recipient, amount)
  }

  #[external]
  fn transferFrom(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) -> bool {
    ERC20::transfer_from(sender, recipient, amount)
  }

  #[external]
  fn transfer(recipient: starknet::ContractAddress, amount: u256) -> bool {
      ERC20::transfer(recipient, amount)
  }

  #[external]
  fn approve(spender: starknet::ContractAddress, amount: u256) -> bool {
    ERC20::approve(spender, amount)
  }

  //
  // Internals
  //

  #[internal]
  fn _mint(recipient: starknet::ContractAddress, amount: u256) {
    assert(!recipient.is_zero(), 'ERC20: mint to 0');

    _balances::write(recipient, _balances::read(recipient) + amount);
  }

  #[internal]
  fn _transfer(sender: starknet::ContractAddress, recipient: starknet::ContractAddress, amount: u256) {
    assert(!sender.is_zero(), 'ERC20: transfer from 0');
    assert(!recipient.is_zero(), 'ERC20: transfer to 0');

    _balances::write(sender, _balances::read(sender) - amount);
    _balances::write(recipient, _balances::read(recipient) + amount);
  }

  #[internal]
  fn _approve(owner: starknet::ContractAddress, spender: starknet::ContractAddress, amount: u256) {
      assert(!owner.is_zero(), 'ERC20: approve from 0');
      assert(!spender.is_zero(), 'ERC20: approve to 0');
      _allowances::write((owner, spender), amount);
      Approval(owner, spender, amount);
  }
}