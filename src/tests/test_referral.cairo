use array::ArrayTrait;
use traits::{ Into, TryInto };
use option::OptionTrait;
use debug::PrintTrait;
use starknet::testing;
use starknet::ContractAddress;

use referral::referral::{Referral, IReferralDispatcher, IReferralDispatcherTrait};

use super::constants::{OWNER, ZERO, OTHER, USER, REFERRAL_ADDR};
use super::utils;
use super::mocks::erc20::{ ERC20, IERC20Dispatcher, IERC20DispatcherTrait };
use super::mocks::naming::{ Naming, INamingDispatcher, INamingDispatcherTrait };
use super::mocks::referral_v2::{ Referral_V2, IReferral_V2Dispatcher, IReferral_V2DispatcherTrait };

// 
// SETUP
// 

fn setup(
    naming_addr: ContractAddress, 
    eth_addr: ContractAddress, 
    min_claim_amount: u256, 
    share: u256
) {
    Referral::constructor(OWNER(), naming_addr, eth_addr, min_claim_amount, share);
}

fn deploy_erc20(recipient: ContractAddress, initial_supply: u256) -> IERC20Dispatcher {
  let mut calldata = ArrayTrait::<felt252>::new();

  calldata.append(initial_supply.low.into());
  calldata.append(initial_supply.high.into());
  calldata.append(recipient.into());

  let address = utils::deploy(ERC20::TEST_CLASS_HASH, calldata);
  IERC20Dispatcher { contract_address: address }
}

fn deploy_naming() -> INamingDispatcher {
  let address = utils::deploy(Naming::TEST_CLASS_HASH, ArrayTrait::<felt252>::new());
  INamingDispatcher { contract_address: address }
}

fn deploy_referral(
    admin: ContractAddress, 
    naming_addr: ContractAddress,
    eth_addr: ContractAddress,
    min_claim_amount: u256, 
    share: u256
) -> IReferralDispatcher {
  let mut calldata = ArrayTrait::<felt252>::new();

  calldata.append(admin.into());
  calldata.append(naming_addr.into());
  calldata.append(eth_addr.into());
  calldata.append(min_claim_amount.low.into());
  calldata.append(min_claim_amount.high.into());
  calldata.append(share.low.into());
  calldata.append(share.high.into());

  let address = utils::deploy(Referral::TEST_CLASS_HASH, calldata);
  IReferralDispatcher { contract_address: address }
}


fn V2_CLASS_HASH() -> starknet::class_hash::ClassHash {
    Referral_V2::TEST_CLASS_HASH.try_into().unwrap()
}


#[test]
#[available_gas(20000000)]
fn test_deploy_referral_contract() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    // It should initialize the referral contract
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    assert(Referral::owner() == OWNER(), 'Owner is not set correctly');
}

#[test]
#[available_gas(20000000)]
fn test_ownership_transfer() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    assert(Referral::owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract
    testing::set_caller_address(OWNER());
    Referral::transfer_ownership(OTHER());
    assert(Referral::owner() == OTHER(), 'Ownership transfer failed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_ownership_transfer_failed() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    assert(Referral::owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract with a non-admin account
    testing::set_caller_address(OTHER());
    Referral::transfer_ownership(OTHER());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100',))]
fn test_set_default_commission_failed_wrong_share_size() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    // It should test setting up default commission higher than 100%
    testing::set_caller_address(OWNER());
    Referral::set_default_commission(u256 { low: 1000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100',))]
fn test_override_commission_wrong_share_size() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    // It should test overriding the default commission with a share higher than 100%
    testing::set_caller_address(OWNER());
    Referral::override_commission(OTHER(), u256 { low: 1000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not naming contract',))]
fn test_add_commission_fail_not_naming_contract() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    // It should test buying a domain from the naming contract add add the right commission
    testing::set_caller_address(USER());
    Referral::add_commission(u256 { low: 100, high: 0 }, USER());
}

#[test]
#[available_gas(20000000)]
fn test_add_commission() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    let balance = Referral::get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());

    let balance = Referral::get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / u256 { low: 100, high: 0 }, 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_add_custom_commission() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };
    let custom_comm = u256 { low: 20, high: 0 };

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    let balance = Referral::get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should define override the default commission for OTHER() user to 20%
    testing::set_caller_address(OWNER());
    Referral::override_commission(OTHER(), custom_comm);

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());

    let balance = Referral::get_balance(OTHER());
    assert(balance == (price_domain * custom_comm) / (u256 { low: 100, high: 0 }), 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_withdraw() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    // It sends ETH to referral contract and then withdraw this amount from the contract
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 100000, high: 0 });
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == u256 { low: 100000, high: 0 }, 'Contract balance is not 100000');
    
    Referral::withdraw(OWNER(), u256 { low: 100000, high: 0 });
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == u256 { low: 0, high: 0 }, 'Contract balance is not 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_withdraw_fail_not_owner() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    // It sends ETH to referral contract and then another user try withdrawing this amount
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 100000, high: 0 });
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == u256 { low: 100000, high: 0 }, 'Contract balance is not 100000');
    
    testing::set_caller_address(OTHER());
    Referral::withdraw(OTHER(), u256 { low: 100000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address',))]
fn test_withdraw_fail_zero_addr() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    // It sends ETH to referral contract and then try withdraw this amount from the addr zero
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 100000, high: 0 });
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == u256 { low: 100000, high: 0 }, 'Contract balance is not 100000');
    
    testing::set_caller_address(ZERO());
    Referral::withdraw(OTHER(), u256 { low: 100000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED',))]
fn test_withdraw_fail_balance_too_low() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());

    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);

    // It sends ETH to referral contract and then try withrawing a higher amount from the contract balance
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 100, high: 0 });
    Referral::withdraw(OTHER(), u256 { low: 100000, high: 0 });
}

#[test]
#[available_gas(20000000)]
fn test_claim() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  default_comm);
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 1000, high: 0 });

    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());
    let balance = Referral::get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / u256 { low: 100, high: 0 }, 'Error adding commission');

    // It should test claiming the commission
    testing::set_caller_address(OTHER());
    Referral::claim(u256 { low: 100, high: 0 });
    let balance = Referral::get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Claiming commissions failed');

}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Amount is too low',))]
fn test_claim_fail_min_claim_amount() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());
    setup(naming.contract_address, erc20.contract_address, u256  { low: 100, high: 0 }, share:  default_comm);
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 1000, high: 0 });

    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());

    // It should test claiming the commission with an amount lower than the min claim amount
    testing::set_caller_address(OTHER());
    Referral::claim(u256 { low: 50, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Amount greater than balance',))]
fn test_claim_fail_claimed_too_much_than_balance() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());
    setup(naming.contract_address, erc20.contract_address, u256  { low: 100, high: 0 }, share:  default_comm);
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 1000, high: 0 });

    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());

    // It should test claiming the commission with an amount higher than the balance of the user
    testing::set_caller_address(OTHER());
    Referral::claim(u256 { low: 2000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED',))]
fn test_claim_fail_contract_balance_too_low() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    let default_comm = u256 { low: 10, high: 0 };
    let price_domain = u256 { low: 1000, high: 0 };

    testing::set_caller_address(OWNER());
    testing::set_contract_address(REFERRAL_ADDR());
    setup(naming.contract_address, erc20.contract_address, u256  { low: 10, high: 0 }, share:  default_comm);
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 10, high: 0 });

    testing::set_caller_address(naming.contract_address);
    Referral::add_commission(price_domain, OTHER());

    // It should test claiming the commission with an amount higher than the balance of the referral contract
    testing::set_caller_address(OTHER());
    Referral::claim(u256 { low: 100, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner',))]
fn test_upgrade_unauthorized() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    // It should test upgrading implementation from a non-admin account
    testing::set_caller_address(OTHER());
    Referral::upgrade(V2_CLASS_HASH());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address',))]
fn test_upgrade_fail_from_zero() {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: u256 { low: 100000, high: 0 });
    let naming = deploy_naming();
    setup(naming.contract_address, erc20.contract_address, u256  { low: 1, high: 0 }, share:  u256 { low: 10, high: 0 });

    // It should test upgrading implementation from the zero address
    Referral::upgrade(V2_CLASS_HASH());
}
