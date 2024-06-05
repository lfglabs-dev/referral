use array::ArrayTrait;
use traits::{Into, TryInto};
use option::OptionTrait;
use starknet::testing;
use starknet::testing::set_contract_address;
use starknet::ContractAddress;
use referral::referral::{Referral, IReferralDispatcher, IReferralDispatcherTrait};
use super::constants::{OWNER, ZERO, OTHER, USER, USER_A, USER_B, USER_C};
use super::utils;
use super::mocks::erc20::ERC20;
use openzeppelin::{
    access::ownable::interface::{IOwnable, IOwnableDispatcher, IOwnableDispatcherTrait},
    token::erc20::interface::{IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait},
    upgrades::interface::{IUpgradeable, IUpgradeableDispatcher, IUpgradeableDispatcherTrait},
};
use identity::{identity::main::Identity};
use naming::{
    pricing::Pricing, naming::main::Naming,
    interface::naming::{INaming, INamingDispatcher, INamingDispatcherTrait}
};

// 
// SETUP
// 

fn setup(
    min_claim_amount: u256, share: u256
) -> (IERC20CamelDispatcher, INamingDispatcher, IReferralDispatcher) {
    let erc20 = IERC20CamelDispatcher {
        contract_address: utils::deploy(ERC20::TEST_CLASS_HASH, array![])
    };
    // pricing
    let pricing = utils::deploy(Pricing::TEST_CLASS_HASH, array![erc20.contract_address.into()]);
    // identity
    let identity = utils::deploy(Identity::TEST_CLASS_HASH, array![0x123, 0, 0, 0]);
    // naming
    let naming = INamingDispatcher {
        contract_address: utils::deploy(
            Naming::TEST_CLASS_HASH, array![identity.into(), pricing.into(), 0, 0x123]
        )
    };

    // It should initialize the referral contract

    let referral = deploy_referral(
        OWNER(), naming.contract_address, erc20.contract_address, min_claim_amount, share
    );

    (erc20, naming, referral)
}

fn deploy_referral(
    admin: ContractAddress,
    naming_addr: ContractAddress,
    eth_addr: ContractAddress,
    min_claim_amount: u256,
    share: u256
) -> IReferralDispatcher {
    let address = utils::deploy(
        Referral::TEST_CLASS_HASH,
        array![
            admin.into(),
            naming_addr.into(),
            eth_addr.into(),
            min_claim_amount.low.into(),
            min_claim_amount.high.into(),
            share.low.into(),
            share.high.into()
        ]
    );
    IReferralDispatcher { contract_address: address }
}


#[test]
#[available_gas(20000000)]
fn test_deploy_referral_contract() {
    let (_, _, referral) = setup(1, 10);
    let ownable = IOwnableDispatcher { contract_address: referral.contract_address };
    assert(ownable.owner() == OWNER(), 'Owner is not set correctly');
}

#[test]
#[available_gas(20000000)]
fn test_ownership_transfer() {
    let (_, _, referral) = setup(1, 10);

    let ownable = IOwnableDispatcher { contract_address: referral.contract_address };
    assert(ownable.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract
    set_contract_address(OWNER());
    ownable.transfer_ownership(OTHER());
    assert(ownable.owner() == OTHER(), 'Ownership transfer failed');
}
#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_ownership_transfer_failed() {
    let (_, _, referral) = setup(1, 10);
    let ownable = IOwnableDispatcher { contract_address: referral.contract_address };

    assert(ownable.owner() == OWNER(), 'Owner is not set correctly');

    // It should test transferring ownership of the referral contract with a non-admin account
    set_contract_address(OTHER());
    ownable.transfer_ownership(OTHER());
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_set_default_commission_failed_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test setting up default commission higher than 100%
    set_contract_address(OWNER());
    referral.set_default_commission(1000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Share must be between 0 and 100', 'ENTRYPOINT_FAILED'))]
fn test_override_commission_wrong_share_size() {
    let (_, _, referral) = setup(1, 10);

    // It should test overriding the default commission with a share higher than 100%
    set_contract_address(OWNER());
    referral.override_commission(OTHER(), 1000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller not naming contract', 'ENTRYPOINT_FAILED'))]
fn test_add_commission_fail_not_naming_contract() {
    let (_, _, referral) = setup(1, 10);

    // It should test buying a domain from another contract
    set_contract_address(USER());
    referral.add_commission(100, USER(), USER());
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
    set_contract_address(naming.contract_address);
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
    set_contract_address(OWNER());
    referral.override_commission(OTHER(), custom_comm);

    // It should test calling add_commission from the naming contract & add the right commission
    set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * custom_comm) / (100), 'Balance is incorrect');
}

#[test]
#[available_gas(20000000)]
fn test_withdraw() {
    let default_comm = 10;
    let (erc20, _, referral) = setup(1, default_comm);

    set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    erc20.transfer(referral.contract_address, 100000);
    let contract_balance = erc20.balanceOf(referral.contract_address);
    assert(contract_balance == 100000, 'Contract balance is not 100000');
    referral.withdraw(OWNER(), 100000);
    let contract_balance = erc20.balanceOf(referral.contract_address);
    assert(contract_balance == 0, 'Contract balance is not 0');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_not_owner() {
    let default_comm = 10;
    let (erc20, _, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then another user try withdrawing this amount
    set_contract_address(OWNER());
    erc20.transfer(referral.contract_address, 100000);
    let contract_balance = erc20.balanceOf(referral.contract_address);
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    set_contract_address(OTHER());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Caller is the zero address', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_zero_addr() {
    let default_comm = 10;
    let (erc20, _, referral) = setup(1, default_comm);

    // It sends ETH to referral contract and then try withdraw this amount from the addr zero
    set_contract_address(OWNER());
    erc20.transfer(referral.contract_address, 100000);
    let contract_balance = erc20.balanceOf(referral.contract_address);
    assert(contract_balance == 100000, 'Contract balance is not 100000');

    set_contract_address(ZERO());
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('ERC20: insufficient balance', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_withdraw_fail_balance_too_low() {
    let default_comm = 10;
    let (erc20, _, referral) = setup(1, default_comm);

    set_contract_address(OWNER());
    // It sends ETH to referral contract and then try withrawing a higher amount from the contract balance
    erc20.transfer(referral.contract_address, 100);
    referral.withdraw(OTHER(), 100000);
}

#[test]
#[available_gas(20000000)]
fn test_claim() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);

    set_contract_address(OWNER());
    erc20.transfer(referral.contract_address, 1000);

    set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());
    let balance = referral.get_balance(OTHER());
    assert(balance == (price_domain * default_comm) / 100, 'Error adding commission');

    // It should test claiming the commission
    set_contract_address(OTHER());
    referral.claim();
    let balance = referral.get_balance(OTHER());
    assert(balance == 0, 'Claiming commissions failed');
}

#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('ERC20: insufficient balance', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
fn test_claim_fail_contract_balance_too_low() {
    let default_comm = 10;
    let price_domain = 1000;
    let (erc20, naming, referral) = setup(1, default_comm);
    set_contract_address(OWNER());
    erc20.transfer(referral.contract_address, u256 { low: 10, high: 0 });

    set_contract_address(naming.contract_address);
    referral.add_commission(price_domain, OTHER(), USER());

    // It should test claiming the commission with an amount higher than the balance of the referral contract
    set_contract_address(OTHER());
    referral.claim();
}

#[test]
#[available_gas(20000000)]
fn test_add_rec_commission() {
    let default_comm = 10;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    let initial_balance = 10000;
    erc20.transfer(USER_A(), initial_balance);
    erc20.transfer(USER_B(), initial_balance);
    erc20.transfer(USER_C(), initial_balance);

    // It should test calling add_commission from the naming contract & add the right commission
    set_contract_address(naming.contract_address);
    assert(referral.get_balance(USER_A()) == 0, 'Init balance is incorrect');

    // B referred by C
    referral.add_commission(price_domain, USER_C(), USER_B());
    let initial_expected = (price_domain * default_comm) / 100;
    assert(referral.get_balance(USER_B()) == 0, 'Balance of B is incorrect');
    assert(referral.get_balance(USER_C()) == initial_expected, 'Balance of C is incorrect');

    // A referred by B
    referral.add_commission(price_domain, USER_B(), USER_A());

    assert(referral.get_balance(USER_A()) == 0, 'Balance of A is incorrect');
    assert(referral.get_balance(USER_B()) == initial_expected, 'Balance of B is incorrect');
    assert(
        referral.get_balance(USER_C()) == initial_expected + initial_expected / 2,
        'Balance of C is incorrect'
    );
}


#[test]
#[available_gas(20000000)]
fn test_add_rec_circular_commission() {
    // The goal of this test is to ensure that if a circular commission is created,
    // people can still buy domains and will receive a reward only once

    let default_comm = 10;
    let price_domain = 1000;

    let (erc20, naming, referral) = setup(1, default_comm);

    set_contract_address(OWNER());

    // It sends ETH to referral contract and then withdraw this amount from the contract
    let initial_balance = 10000;
    erc20.transfer(USER_A(), initial_balance);
    erc20.transfer(USER_B(), initial_balance);
    erc20.transfer(USER_C(), initial_balance);

    set_contract_address(naming.contract_address);

    // B referred by C
    referral.add_commission(price_domain, USER_C(), USER_B());
    // A referred by B
    referral.add_commission(price_domain, USER_B(), USER_A());
    // C referred by A
    referral.add_commission(price_domain, USER_A(), USER_C());

    let initial_expected = (price_domain * default_comm) / 100;
    assert(
        referral.get_balance(USER_C()) == initial_expected
            + initial_expected / 2
            + initial_expected / 4,
        'Balance of C is incorrect'
    );

    assert(
        referral.get_balance(USER_B()) == initial_expected + initial_expected / 2,
        'Balance of B is incorrect'
    );

    assert(referral.get_balance(USER_A()) == initial_expected, 'Balance of B is incorrect');
}
