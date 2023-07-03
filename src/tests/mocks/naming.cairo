#[abi]
trait INaming {
    #[external]
    fn set_referral_addr(referral_addr: starknet::ContractAddress) -> bool;

    #[external]
    fn buy_domain(amount: u256, sponsor_addr: starknet::ContractAddress) -> bool;
}

#[contract]
mod Naming {
  use super::INaming;
  use zeroable::Zeroable;
  use debug::PrintTrait;

  use referral::referral::{ IReferral, IReferralDispatcher, IReferralDispatcherTrait };

  struct Storage {
    referral_contract: starknet::ContractAddress
  }

  #[external]
  fn set_referral_addr(referral_addr: starknet::ContractAddress) -> bool {
    referral_contract::write(referral_addr);
    true
  }

  #[external]
  fn buy_domain(amount: u256, sponsor_addr: starknet::ContractAddress) -> bool {
    let Referral = IReferralDispatcher { contract_address: referral_contract::read() };
    Referral.add_commission(amount, sponsor_addr);
    true
  }
}