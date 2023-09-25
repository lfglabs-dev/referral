use array::ArrayTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use debug::PrintTrait;
use starknet::testing;
use starknet::ContractAddress;

use referral::referral::{Referral, IReferralDispatcher, IReferralDispatcherTrait};

use super::constants::{OWNER, ZERO, OTHER, USER, REFERRAL_ADDR};
use super::utils;
use super::mocks::erc20::{ERC20, IERC20Dispatcher, IERC20DispatcherTrait};
use super::mocks::naming::{Naming, INamingDispatcher, INamingDispatcherTrait};
use super::mocks::referral_v2::{Referral_V2, IReferral_V2Dispatcher, IReferral_V2DispatcherTrait};
use referral::upgrades::upgradeable::Upgradeable;

// 
// SETUP
// 

fn setup(
    min_claim_amount: u256, share: u256
) -> (IERC20Dispatcher, INamingDispatcher, IReferralDispatcher) {
    let erc20 = deploy_erc20(recipient: OWNER(), initial_supply: 100000);
    let naming = deploy_naming();
    // It should initialize the referral contract

    let referral = deploy_referral(
        OWNER(), naming.contract_address, erc20.contract_address, min_claim_amount, share
    );

    (erc20, naming, referral)
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
    let (_, _, referral) = setup(1, 10);
    assert(referral.owner() == OWNER(), 'Owner is not set correctly');
}

#[test]
#[available_gas(20000000)]
fn test_ownership_transfer() {
    let (_, _, referral) = setup(1, 10);

    assert(referral.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract
    testing::set_contract_address(OWNER());
    referral.transfer_ownership(OTHER());
    assert(referral.owner() == OTHER(), 'Ownership transfer failed');
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_ownership_transfer_failed() {
    let (_, _, referral) = setup(1, 10);

    assert(referral.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract with a non-admin account
    testing::set_contract_address(OTHER());
    referral.transfer_ownership(OTHER());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_set_default_commission_failed_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test setting up default commission higher than 100%
    testing::set_contract_address(OWNER());
    referral.set_default_commission(u256 { low: 1000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_override_commission_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test overriding the default commission with a share higher than 100%
    testing::set_contract_address(OWNER());
    referral.override_commission(OTHER(), u256 { low: 1000, high: 0 });
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not naming contract', 'ENTRYPOINT_FAILED'))]
fn test_add_commission_fail_not_naming_contract() {
    let (_, _, referral) = setup(1, 10);

    // It should test buying a domain from another contract
    testing::set_caller_address(USER());
    referral.add_commission(u256 { low: 100, high: 0 }, USER(), USER());
}

#[test]
#[available_gas(20000000)]
fn test_add_commission() {
    let default_comm = 10;
    let price_domain = 1000;

    let (_, naming, referral) = setup(1, default_comm);

    let balance = referral.get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / 100, 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_add_custom_commission() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;

    let (_, naming, referral) = setup(1, default_comm);

    let balance = referral.get_balance(OTHER());
    assert(balance == u256 { low: 0, high: 0 }, 'Balance is not 0');

    // It should define override the default commission for OTHER() user to 20%
    testing::set_contract_address(OWNER());
    referral.override_commission(OTHER(), custom_comm);

    // It should test calling add_commission from the naming contract & add the right commission
    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    let balance = referral.get_balance(OTHER());
    assert(
        balance == (price_domain * custom_comm) / (u256 { low: 100, high: 0 }),
        'Balance is incorrect'
    );
}

#[test]
#[available_gas(20000000)]
fn test_withdraw() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    //testing::set_caller_address(OWNER());
    testing::set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');
    referral.withdraw(OWNER(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 0, 'Contract balance is not 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_not_owner() {
    let default_comm = 10;
    let price_domain = 1000;
    let custom_comm = 20;

    let (erc20, naming, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then another user try withdrawing this amount
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    testing::set_contract_address(OTHER());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_zero_addr() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then try withdraw this amount from the addr zero
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), 100000);
    let contract_balance = erc20.balance_of(REFERRAL_ADDR());
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    testing::set_caller_address(ZERO());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_balance_too_low() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    testing::set_contract_address(OWNER());
    // It sends ETH to referral contract and then try withrawing a higher amount from the contract balance
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 100, high: 0 });
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
fn test_claim() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);
    testing::set_contract_address(OWNER());
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 1000, high: 0 });

    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());
    let balance = referral.get_balance(OTHER());
    assert(
        balance == (price_domain * default_comm) / u256 { low: 100, high: 0 },
        'Error adding commission'
    );

    // It should test claiming the commission
    testing::set_contract_address(OTHER());
    referral.claim();
    let balance = referral.get_balance(OTHER());
    assert(balance == 0, 'Claiming commissions failed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('u256_sub Overflow', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_claim_fail_contract_balance_too_low() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);
    testing::set_contract_address(OWNER());
    erc20.transfer_from(OWNER(), REFERRAL_ADDR(), u256 { low: 10, high: 0 });

    testing::set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    // It should test claiming the commission with an amount higher than the balance of the referral contract
    testing::set_contract_address(OTHER());
    referral.claim();
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_upgrade_unauthorized() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It should test upgrading implementation from a non-admin account
    testing::set_contract_address(OTHER());
    referral.upgrade(V2_CLASS_HASH());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_upgrade_fail_from_zero() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    // It should test upgrading implementation from the zero address
    referral.upgrade(V2_CLASS_HASH());
}
